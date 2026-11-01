import {createHash} from 'node:crypto';
// Acceptance evidence only. This module grants no runtime authority and does
// not replace package provenance, the public result oracle, or resource guards.
export const publicLatencyTarget = Object.freeze({p95Ms: 200, maxMs: 200});
export const operationTargets = Object.freeze({
  ...Object.fromEntries(['warm-select', 'warm-result', 'warm-status', 'warm-join',
    'warm-union', 'warm-decimal-sum', 'warm-parameters', 'warm-unicode'].map(operation => [operation,
    {samples: 100, comparison: 'local-sqlite', publicEndToEnd: true, ...publicLatencyTarget}])),
  'cold-existing': {samples: 30, publicEndToEnd: true, ...publicLatencyTarget},
  'first-init': {samples: 30, publicEndToEnd: true, ...publicLatencyTarget},
  'mock-workflow': {samples: 30, p95Ms: 5000},
});
for (const target of Object.values(operationTargets)) Object.freeze(target);
export const historySizes = Object.freeze([1, 10, 100, 1000]);
const integer = value => Number.isSafeInteger(value) && value >= 0;
const digest = value => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const requireValue = (condition, message) => { if (!condition) throw new Error(message); };
const outcome = (failures, missing, detail = {}) => ({
  status: failures.length ? 'failed' : missing.length ? 'incomplete' : 'passed', failures, missing, ...detail,
});

export function latencySummary(samples, minimum) {
  requireValue(integer(minimum) && minimum > 0, 'A nonzero sample minimum is required');
  for (const row of samples) {
    requireValue(integer(row.wallNs) && integer(row.cpuUserUs) && integer(row.cpuSystemUs), 'Invalid wall/CPU sample');
  }
  const values = samples.map(row => row.wallNs / 1e6).sort((a, b) => a - b);
  const n = values.length;
  return {count: n, medianMs: n ? (values[Math.floor((n - 1) / 2)] + values[Math.floor(n / 2)]) / 2 : null,
    // A small diagnostic never supplies an acceptance p95.
    p95Ms: n >= minimum ? values[Math.ceil(n * 0.95) - 1] : null,
    maxMs: n ? values[n - 1] : null, quantile: 'nearest-rank', minimum};
}

export function resourceSummary(samples, minimum) {
  const cpuAvailable = samples.length > 0 && samples.every(row =>
    row.cpuAvailable !== false && row.childCpuAvailable !== false &&
    integer(row.cpuUserUs) && integer(row.cpuSystemUs) && typeof row.cpuScope === 'string' && row.cpuScope.length > 0);
  const rssAvailable = samples.length > 0 && samples.every(row =>
    integer(row.peakRssBytes) && row.peakRssBytes > 0 && typeof row.rssScope === 'string' && row.rssScope.length > 0);
  return {cpu: cpuAvailable ? {available: true, scopes: [...new Set(samples.map(row => row.cpuScope))],
    ...latencySummary(samples.map(row => ({wallNs: (row.cpuUserUs + row.cpuSystemUs) * 1000,
      cpuUserUs: row.cpuUserUs, cpuSystemUs: row.cpuSystemUs})), minimum)} : {available: false},
  rss: rssAvailable ? {available: true, scopes: [...new Set(samples.map(row => row.rssScope))],
    maximumBytes: Math.max(...samples.map(row => row.peakRssBytes))} : {available: false}};
}

// These are actual clocks around the existing public caller and its row
// oracle, not validation-call counters or inferred work durations. Child
// clocks are compared by elapsed time only, never by cross-process origin.
export function assessPublicLatencySamples(samples, minimum, operation) {
  const summary = latencySummary(samples, minimum), failures = [], missing = [];
  for (const row of samples) {
    if (row.completed !== true || row.verified !== true) continue;
    const timing = row.publicTiming;
    if (!timing) {missing.push(`sample ${row.iteration}: public completion timing`); continue;}
    const names = timing.kind === 'process-result-close'
      ? ['startNs', 'observedNs', 'closeStartNs', 'closeEndNs', 'endNs']
      : timing.kind === 'cli-result-exit' ? ['startNs', 'exitNs', 'observedNs', 'endNs']
        : ['startNs', 'observedNs', 'endNs'];
    const allowed = operation.startsWith('warm-')
      ? [operation === 'warm-status' ? 'public-status' : 'public-result']
      : operation.endsWith('-process-first-result')?['process-first-result']
        : ['process-result-close', 'cli-result-exit'];
    if (!allowed.includes(timing.kind) || names.some(name => !integer(timing[name])) ||
        names.some((name, index) => index > 0 && timing[name] < timing[names[index - 1]]) ||
        timing.endNs - timing.startNs > row.wallNs) {
      failures.push(`sample ${row.iteration}: public timer excludes completion or close`);
    }
  }
  if (summary.p95Ms !== null && summary.p95Ms > publicLatencyTarget.p95Ms) failures.push('public E2E p95 exceeds 200ms');
  if (summary.maxMs !== null && summary.maxMs > publicLatencyTarget.maxMs) failures.push('public E2E observed max exceeds 200ms');
  return {summary, failures, missing};
}

// Diagnostic calibration consumes independently measured SQLite data, never
// candidate durations. Public acceptance additionally needs a matched control
// for the existing semantic Owner's independently required durable transitions.
export const sqliteComparisonPolicy = Object.freeze({ratio: 3, minimumSamples: 100,
  noise: 'matched baseline p95 minus median', essentialTransactionsPerNewRun: 1});
const evidenceHash = value => createHash('sha256').update(JSON.stringify(value) ?? 'null').digest('hex');
const explicitSqliteSettings = value => value?.journal_mode === 'wal' && value.synchronous === 2 &&
  typeof value.sqliteVersion === 'string' && [0, 1].includes(value.fullfsync) &&
  [0, 1].includes(value.checkpoint_fullfsync);
function sqliteSettingsComparison(observed, comparator) {
  const result = {matched: false, equivalentDifferences: []};
  if (!explicitSqliteSettings(observed) || !explicitSqliteSettings(comparator)) return result;
  if (evidenceHash(observed) === evidenceHash(comparator)) return {...result, matched: true};
  // https://www.sqlite.org/pragma.html#pragma_checkpoint_fullfsync:
  // fullfsync selects the full method for all syncs, including checkpoints.
  // Retain both observed flags; do not normalize the original reports/profile.
  if (observed.fullfsync === 1 && comparator.fullfsync === 1 &&
      observed.checkpoint_fullfsync !== comparator.checkpoint_fullfsync &&
      evidenceHash({...observed, checkpoint_fullfsync: comparator.checkpoint_fullfsync}) === evidenceHash(comparator)) {
    return {matched: true, equivalentDifferences: [{setting: 'checkpoint_fullfsync',
      observed: observed.checkpoint_fullfsync, comparator: comparator.checkpoint_fullfsync,
      reason: 'fullfsync=1 selects full synchronization for all sync operations'}]};
  }
  return result;
}
// The original collector hashes bytes, not a JSON string, for the seed fixture.
const seedFixture = createHash('sha256').update('SELECT 1 AS id\n[{"id":1}]\n').digest('hex');
const comparisonQueries = Object.freeze({
  'warm-join': {text: "WITH lhs AS (SELECT 1 AS id), rhs AS (SELECT 1 AS id, 'joined' AS label) "
    + 'SELECT lhs.id AS id, rhs.label AS label FROM lhs JOIN rhs ON lhs.id = rhs.id MAX_OUTPUT_ROWS 1',
    sqlite: "WITH lhs AS (SELECT 1 AS id), rhs AS (SELECT 1 AS id, 'joined' AS label) "
      + 'SELECT lhs.id AS id, rhs.label AS label FROM lhs JOIN rhs ON lhs.id = rhs.id LIMIT 1',
    expected: [{id: 1, label: 'joined'}]},
  'warm-union': {text: 'WITH items AS (SELECT 2 AS id UNION ALL SELECT 1 AS id) '
    + 'SELECT id FROM items |> ASSERT UNIQUE BY (id) |> ORDER BY id',
    sqlite: 'WITH items AS (SELECT 2 AS id UNION ALL SELECT 1 AS id) SELECT id FROM items ORDER BY id',
    expected: [{id: 1}, {id: 2}]},
  'warm-parameters': {text: 'SELECT @id AS id', sqlite: 'SELECT ? AS id', parameters: [7],
    options: {parameters: {id: 7}, parameterDeclarations: {id: {type: 'number'}}}, expected: [{id: 7}]},
  'warm-unicode': {text: "SELECT 'é😀' AS label", sqlite: "SELECT 'é😀' AS label", expected: [{label: 'é😀'}]},
});
function resultStorageComparison(control, baseline) {
  requireValue(control.kind === 'local-sqlite-result-control' && [1, 2].includes(control.schemaVersion) &&
    control.productAcceptance === false, 'Bounded Result storage control required');
  requireValue(control.cleanup?.closed === true && control.failure == null && control.profiled === false,
    'Completed successful unprofiled Result control required');
  const synchronizationComparison = sqliteSettingsComparison(control.settings, baseline.settings);
  requireValue(control.executableSha256 === baseline.executableSha256 && digest(control.collectorSha256) &&
    evidenceHash(control.environment) === evidenceHash(baseline.environment) && control.load === baseline.load &&
    synchronizationComparison.matched, 'Result control runtime/environment/durability differs');
  const protocol = control.protocol, groups = ['clock', 'start', 'end'];
  requireValue(protocol?.binding === 'node:sqlite DatabaseSync' && protocol.concurrency === 1 &&
    control.protocolSha256 === evidenceHash(protocol), 'Fixed Result control protocol required');
  if (Object.hasOwn(protocol, 'fullfsyncRequested')) requireValue(typeof protocol.fullfsyncRequested === 'boolean' &&
    control.settings.fullfsync === Number(protocol.fullfsyncRequested), 'Result control requested/readback synchronization differs');
  requireValue(/^[a-f0-9]{40}$/u.test(control.ownerMapping?.source ?? '') && digest(control.ownerMapping.sha256) &&
    JSON.stringify(control.ownerMapping.groups?.map(row => row.id)) === JSON.stringify(groups),
  'Existing Result Owner clock/start/end mapping required');
  const keyWidths = {namespaceId: 5, authorityScopeCid: 71, runDefinitionCid: 71,
    principalId: 4, purpose: 8, resultName: 4, attemptId: 36};
  requireValue(evidenceHash(protocol.keyWidths) === evidenceHash(keyWidths) &&
    protocol.groups?.length === 3 && nonempty(protocol.preparation) && nonempty(protocol.coverage),
  'Exact seven-key bounded Result workload required');
  const sizes = protocol.bodyBytes;
  const bodies = ['grant', 'attempt', 'streaming', 'receipt', 'terminalSucceeded'];
  requireValue(bodies.every(key => integer(sizes?.[key]) && sizes[key] >= 128 && sizes[key] <= 65536) &&
    integer(sizes?.clock) && sizes.clock >= 128 && sizes.clock <= 65536 &&
    sizes.totalCanonicalBusinessBytes === bodies.reduce((sum, key) => sum + sizes[key], 0) &&
    sizes.outputJsonlBytes === 9 && protocol.payload === '{"id":1}\n' &&
    evidenceHash(protocol.expected) === evidenceHash([{id: 1}]), 'Matched Result bodies and JSONL oracle required');
  const materialized = control.schemaVersion === 2;
  const shaText = text => createHash('sha256').update(text).digest('hex');
  const sameFields = (actual, expected) => actual !== null && typeof actual === 'object' &&
    !Array.isArray(actual) && Object.keys(actual).length === Object.keys(expected).length &&
    Object.entries(expected).every(([key, value]) => Object.hasOwn(actual, key) && actual[key] === value);
  const materialization = {storedFormat: 'json-array-utf8', storedBytes: 10,
    storedSha256: shaText('[{"id":1}]'), schemaFormat: 'actql-schema-json-utf8', schemaBytes: 41,
    schemaSha256: shaText('{"id":{"nullable":false,"type":"number"}}'), outputFormat: 'jsonl-utf8',
    outputBytes: 9, outputSha256: shaText(protocol.payload),
    conversion: 'stored-array-and-schema -> JSONL -> ordinary-JS-records'};
  if (materialized) requireValue(sameFields(protocol.materialization, materialization),
    'Explicit stored array/schema/output conversion correspondence required');
  else requireValue(!Object.hasOwn(protocol, 'materialization') || typeof protocol.materialization === 'string',
    'Structured materialization requires Result control v2');
  requireValue(Array.isArray(control.samples) && control.samples.length >= sqliteComparisonPolicy.minimumSamples &&
    control.warmSamples === control.samples.length, 'Sufficient complete raw Result control samples required');
  const indexes = new Set(), attempts = new Set(), pids = new Set();
  const expectedEvents = ['clock-committed', 'start-committed',
    ...(materialized ? ['stored-array-decoded', 'jsonl-serialized'] : []), 'payload-materialized', 'end-committed'];
  const expectedCounts = {begins: 3, commits: 3, rollbacks: 0, reads: 3, writes: 8};
  for (const sample of control.samples) {
    requireValue(integer(sample.index) && !indexes.has(sample.index) && integer(sample.pid) && sample.pid > 0 &&
      sample.verified === true && sample.outputSha256 === evidenceHash(protocol.expected) &&
      /^sha256:[a-f0-9]{64}$/u.test(sample.attemptCid ?? '') && !attempts.has(sample.attemptCid),
    'Distinct verified Result control observation required');
    indexes.add(sample.index); attempts.add(sample.attemptCid); pids.add(sample.pid);
    requireValue(evidenceHash(sample.events) === evidenceHash(expectedEvents) &&
      evidenceHash(sample.counts) === evidenceHash(expectedCounts), 'Result durable ordering/counts differ');
    if (materialized) requireValue(sameFields(sample.materialization, {storedBytes: 10, schemaBytes: 41,
      jsonlBytes: 9, decodedRows: 1, outputSha256: materialization.outputSha256}),
    'Complete Result conversion observation required');
    else requireValue(!Object.hasOwn(sample, 'materialization'), 'Materialization observation requires Result control v2');
    const phases = sample.phases;
    requireValue(integer(phases?.fixtureConstructionNs) && integer(phases?.payloadAndMaterializeNs) &&
      groups.every(key => integer(phases[key]?.totalNs) && integer(phases[key]?.commitNs) &&
        phases[key].commitNs <= phases[key].totalNs), 'Complete Result phase observations required');
    requireValue(phases.fixtureConstructionNs + phases.payloadAndMaterializeNs +
      groups.reduce((sum, key) => sum + phases[key].totalNs, 0) <= sample.wallNs,
    'Result phases exceed public-control total');
  }
  requireValue(pids.size === 1, 'Warm Result control must retain the same process');
  const summary = latencySummary(control.samples.map(sample => ({wallNs: sample.wallNs,
    cpuUserUs: sample.userUs, cpuSystemUs: sample.systemUs})), sqliteComparisonPolicy.minimumSamples);
  const noiseMs = Math.max(0, summary.p95Ms - summary.medianMs);
  return {controlBodySha256: evidenceHash(control), protocolSha256: control.protocolSha256,
    ownerMapping: control.ownerMapping, conditions: {keyWidths, bodyBytes: sizes,
      payload: protocol.payload, preparation: protocol.preparation, groups, settings: control.settings,
      ...(materialized ? {materialization: protocol.materialization} : {})},
    summary, coverage: protocol.coverage, noiseMs,
    ...(synchronizationComparison.equivalentDifferences.length ? {synchronizationComparison} : {}),
    diagnosticLimits: {medianMs: 3 * summary.medianMs + noiseMs, p95Ms: 3 * summary.p95Ms + noiseMs,
      ratio: 3, basis: 'whole minimal Result control including indexed materialization'},
    qualification: 'Measured minimal Result storage only. Required Account, typed/cryptographic work and actual public context correspondence remain separate; this is not an unconditional SDK SLA.'};
}
export function calibrateSqliteComparisonProfile(baseline, resultControl) {
  requireValue(baseline?.kind === 'local-sqlite-comparator' && baseline.schemaVersion === 1,
    'Actual local SQLite comparator required');
  requireValue(baseline.cleanup?.closed === true && baseline.profiled === false,
    'Completed unprofiled comparator required');
  requireValue(baseline.protocol?.binding === 'node:sqlite DatabaseSync' && baseline.protocol.concurrency === 1 &&
    ['isolated', 'concurrent'].includes(baseline.load), 'Explicit local binding/concurrency/load required');
  requireValue(digest(baseline.executableSha256) && digest(baseline.collectorSha256) &&
    baseline.protocolSha256 === evidenceHash(baseline.protocol), 'Comparator source/tool/protocol identity required');
  requireValue(baseline.environment && nonempty(baseline.environment.node), 'Explicit comparator runtime required');
  requireValue(explicitSqliteSettings(baseline.settings),
  'Explicit WAL/FULL/fullfsync/checkpoint synchronization settings required');
  if (Object.hasOwn(baseline.protocol, 'fullfsyncRequested')) requireValue(typeof baseline.protocol.fullfsyncRequested === 'boolean' &&
    baseline.settings.fullfsync === Number(baseline.protocol.fullfsyncRequested), 'Comparator requested/readback synchronization differs');
  const observed = (operation, mode) => {
    const entries = baseline.warm.filter(row => row.operation === operation && row.mode === mode);
    requireValue(entries.length <= 1, 'Duplicate comparator workload');
    if (!entries.length) return null;
    const row = entries[0], indexes = new Set(), outputs = new Set();
    requireValue(row.samples.length >= sqliteComparisonPolicy.minimumSamples, 'Insufficient comparator samples');
    for (const sample of row.samples) {
      requireValue(integer(sample.index) && !indexes.has(sample.index) && sample.verified === true &&
        integer(sample.pid) && sample.pid > 0 && digest(sample.outputSha256), 'Invalid comparator observation');
      indexes.add(sample.index); outputs.add(sample.outputSha256);
    }
    requireValue(outputs.size === 1, 'Comparator oracle changed');
    const summary = latencySummary(row.samples.map(sample => ({wallNs: sample.wallNs,
      cpuUserUs: sample.userUs, cpuSystemUs: sample.systemUs})), sqliteComparisonPolicy.minimumSamples);
    return {row, summary, outputSha256: [...outputs][0]};
  };
  const durable = observed('durable-transaction-read', 'prepared');
  if (durable) requireValue(durable.outputSha256 === evidenceHash([{id: 1}]), 'Durable comparator oracle differs');
  const entries = [];
  for (const operation of ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union', 'warm-parameters', 'warm-unicode']) {
    const mode = ['warm-result', 'warm-status'].includes(operation) ? 'prepared' : 'one-shot';
    const value = observed(operation, mode); if (!value) continue;
    const query = comparisonQueries[operation];
    let fixtureSha256 = seedFixture;
    if (query) {
      requireValue(value.row.fixture?.sql === query.sqlite &&
        evidenceHash(value.row.fixture.expected) === evidenceHash(query.expected) &&
        evidenceHash(value.row.fixture.parameters) === evidenceHash(query.parameters ?? []), 'Unmatched SQLite query fixture');
      fixtureSha256 = evidenceHash({operation, text: query.text,
        ...(query.options ? {options: query.options} : {}), expected: query.expected});
    } else if (operation === 'warm-select') {
      requireValue(value.row.fixture?.sql === 'SELECT 1 AS id' &&
        JSON.stringify(value.row.fixture.parameters) === '[]' &&
        value.outputSha256 === evidenceHash([{id: 1}]), 'Unmatched SELECT fixture');
    } else requireValue(baseline.savedFixture?.rows === 1 && baseline.savedFixture.payload === '[{"id":1}]' &&
      baseline.savedFixture.plan?.some(row => row.detail.includes('USING INTEGER PRIMARY KEY')),
    'Matched indexed saved-row fixture required');
    const newRun = !['warm-result', 'warm-status'].includes(operation);
    if (newRun && !durable) continue;
    const oracle = query?.expected ?? (operation === 'warm-status' ? {status: 'succeeded', revision: 0} : [{id: 1}]);
    requireValue(value.outputSha256 === evidenceHash(oracle), 'Comparator output differs from fixed literal oracle');
    const noiseMs = Math.max(0, value.summary.p95Ms - value.summary.medianMs);
    const essential = newRun ? durable.summary : {medianMs: 0, p95Ms: 0};
    entries.push({operation, mode, fixtureSha256, expectedSha256: value.outputSha256,
      matchQualification: newRun ? 'matched literal-query input/output' : 'minimum indexed control only; actual saved Run key/row not yet matched',
      conditions: {concurrency: 1, preparation: mode, temperature: 'warm',
        materialization: 'ordinary JS records', parameters: query?.parameters ?? [],
        data: query || operation === 'warm-select' ? {input: 'literal CTE', indexes: []}
          : {logicalRows: [{id: 1}], indexes: ['single bound primary key']},
        durability: newRun ? 'diagnostic minimum WAL/FULL transaction; public Run/Result duties unmatched' : 'pure indexed-read diagnostic; no invented write'},
      engine: value.summary, noiseMs,
      essentialOverhead: {medianMs: essential.medianMs, p95Ms: essential.p95Ms,
        qualification: newRun ? 'One diagnostic WAL/FULL transaction/read; not a sufficient public Run/Result allowance.' : 'Pure indexed-read diagnostic only; public Result attempt/grant/terminal duties remain unmatched.'},
      medianMs: sqliteComparisonPolicy.ratio * value.summary.medianMs + noiseMs + essential.medianMs,
      p95Ms: sqliteComparisonPolicy.ratio * value.summary.p95Ms + noiseMs + essential.p95Ms});
  }
  return {kind: 'local-sqlite-comparison-profile', policy: sqliteComparisonPolicy,
    baselineBodySha256: evidenceHash(baseline), environmentSha256: evidenceHash(baseline.environment),
    runtime: baseline.environment.node, load: baseline.load, settings: baseline.settings, entries,
    ...(resultControl ? {resultStorage: resultStorageComparison(resultControl, baseline)} : {}),
    qualification: 'Frozen baseline-only diagnostic calibration, not an unconditional SDK SLA. Public essential-work mapping remains unmatched; total public latency remains primary.'};
}
// A process-family control is useful diagnostic evidence even when its SQLite
// build and essential public work do not match the product. It supplies no
// calibration profile, overhead allowance, warm gate or percentile acceptance.
export function assessNativeSqliteDiagnostic(control, protocolText) {
  requireValue(control?.kind === 'native-cli-sqlite-process-control-diagnostic' &&
    control.schemaVersion === 1 && control.productAcceptance === 'incomplete',
  'Incomplete Native SQLite diagnostic required');
  for (const field of ['firstFailure', 'packageFailure', 'cleanupFailure', 'failure']) {
    requireValue(control[field] == null, 'Native control records a known failure');
  }
  requireValue(control.childrenAllExitedSynchronously === true && Array.isArray(control.liveDuties) &&
    control.liveDuties.length === 0 && control.publicActqlOperationMeasured === false &&
    control.externalRunOrKeyStateOpened === false && control.comparisonProfile === null &&
    control.essentialOverheadAllowance === null, 'Native control completion or diagnostic scope differs');
  requireValue(typeof protocolText === 'string' && Buffer.byteLength(protocolText) <= 16 * 1024 ** 2 &&
    control.protocol?.bytes === Buffer.byteLength(protocolText) && digest(control.protocol.sha256) &&
    createHash('sha256').update(protocolText).digest('hex') === control.protocol.sha256,
  'Native control differs from exact frozen protocol bytes');
  const protocol = JSON.parse(protocolText);
  requireValue(protocol.concurrency === 1 && protocol.prepared === 'one-shot/fresh process' &&
    integer(protocol.samplesPerOperation) && protocol.samplesPerOperation > 0 &&
    integer(protocol.warmupsPerOperation) &&
    2 * (protocol.samplesPerOperation + protocol.warmupsPerOperation) <= 10000,
  'Invalid bounded Native control sampling protocol');
  const nonempty = value => typeof value === 'string' && value.length > 0;
  requireValue(nonempty(protocol.nodeExecutable) && nonempty(protocol.sqliteExecutable) &&
    protocol.nodeExecutable !== protocol.sqliteExecutable && Array.isArray(control.binaries) &&
    control.binaries.length === 2 && control.binaries.every(row =>
      nonempty(row.path) && integer(row.bytes) && row.bytes > 0 && digest(row.sha256)) &&
    control.binaries.filter(row => row.path === protocol.nodeExecutable).length === 1 &&
    control.binaries.filter(row => row.path === protocol.sqliteExecutable).length === 1,
  'Distinct Native control binary identities required');
  requireValue(control.environment?.concurrency === 1 && nonempty(control.environment.platform) &&
    nonempty(control.environment.arch) && nonempty(control.environment.nodeVersion) &&
    nonempty(control.environment.sqliteVersion) && nonempty(control.environment.startup) &&
    nonempty(control.preparation) && nonempty(control.completion),
  'Native control runtime and process completion conditions required');
  const settingNames = ['journalMode', 'lockingMode', 'synchronous', 'fullfsync',
    'checkpointFullfsync', 'cacheSize', 'tempStore', 'queryOnly', 'pageSize'];
  requireValue(control.actualSettings && protocol.expectedSettings &&
    settingNames.every(key => Object.hasOwn(control.actualSettings, key) &&
      Object.hasOwn(protocol.expectedSettings, key) &&
      control.actualSettings[key] === protocol.expectedSettings[key]) &&
    Object.keys(control.actualSettings).length === settingNames.length &&
    Object.keys(protocol.expectedSettings).length === settingNames.length &&
    control.actualSettings.journalMode === 'wal' && control.actualSettings.synchronous === 2 &&
    control.actualSettings.fullfsync === 1 && control.actualSettings.queryOnly === 1,
  'Native control observed synchronization/settings differ from protocol');
  for (const observed of [control.mmapSettingObservation, protocol.mmapSettingObservation]) {
    requireValue(observed?.requestedBytes === 0 && observed.actualBytes === 0 && nonempty(observed.probeSql),
      'Explicit Native control mmap observation required');
  }
  requireValue(Array.isArray(control.actualIndexedPlan) && control.actualIndexedPlan.some(row =>
    typeof row.detail === 'string' && /^SEARCH saved_result USING PRIMARY KEY/u.test(row.detail)),
  'Actual indexed Native control plan required');
  const fixture = control.fixture;
  requireValue(fixture?.totalRows === 1 && fixture.databaseBefore && fixture.databaseAfter &&
    nonempty(fixture.databaseBefore.path) && fixture.databaseBefore.path === fixture.databaseAfter.path &&
    integer(fixture.databaseBefore.bytes) && fixture.databaseBefore.bytes > 0 &&
    fixture.databaseBefore.bytes === fixture.databaseAfter.bytes && digest(fixture.databaseBefore.sha256) &&
    fixture.databaseBefore.sha256 === fixture.databaseAfter.sha256 &&
    protocol.expectedJsonl === '{"x":1}\n' && fixture.expectedJsonl === protocol.expectedJsonl,
  'Native control fixture/output correspondence required');
  const names = ['select', 'savedRow'];
  requireValue(protocol.operations && fixture.materialization && control.operations &&
    Object.keys(protocol.operations).length === names.length &&
    Object.keys(control.operations).length === names.length && names.every(name =>
      nonempty(protocol.operations[name]?.sql) && nonempty(protocol.operations[name]?.materialization) &&
      protocol.operations[name].durableLogicalTransitions === 0 &&
      ['sql', 'materialization', 'durableLogicalTransitions'].every(key =>
        fixture.materialization[name]?.[key] === protocol.operations[name][key])),
  'Native query-only materialization conditions differ');
  const unknownCounters = ['actualPhysicalDbReads', 'sqlPrepareCalls', 'engineOnlyElapsedNs', 'fullfsyncCalls'];
  requireValue(unknownCounters.every(key => control[key] === null),
    'Unmeasured Native counters must remain explicit null');
  requireValue(Array.isArray(control.missingCorrespondence) && control.missingCorrespondence.length > 0 &&
    control.missingCorrespondence.every(nonempty) &&
    evidenceHash(control.missingCorrespondence) === evidenceHash(protocol.missingCorrespondence),
  'Native public correspondence gaps must remain explicit');
  requireValue(Array.isArray(control.raw) &&
    control.raw.length === names.length * (protocol.samplesPerOperation + protocol.warmupsPerOperation),
  'Complete bounded Native raw sample extent required');
  const nanos = value => {
    requireValue(typeof value === 'string' && /^(?:0|[1-9][0-9]*)$/u.test(value) &&
      integer(Number(value)), 'Invalid exact Native duration');
    return Number(value);
  };
  const positive = value => integer(value) && value > 0;
  const measured = Object.fromEntries(names.map(name => [name, []])), seen = new Set();
  const outputSha256 = createHash('sha256').update(protocol.expectedJsonl).digest('hex');
  for (const row of control.raw) {
    requireValue(names.includes(row.operation) && typeof row.warmup === 'boolean' &&
      Number.isSafeInteger(row.index) && (row.warmup
        ? row.index >= -protocol.warmupsPerOperation && row.index < 0
        : row.index >= 0 && row.index < protocol.samplesPerOperation), 'Invalid Native sample coordinate');
    const key = `${row.operation}:${row.index}`;
    requireValue(!seen.has(key), 'Duplicate Native sample coordinate'); seen.add(key);
    const total = nanos(row.publicLikeProcessTotalNs), sqlite = nanos(row.sqliteProcessElapsedNs),
      conversion = nanos(row.conversionAndOracleElapsedNs), remaining = nanos(row.launcherAndRemainingNs);
    const child = row.child;
    requireValue(positive(row.collectorPid) && child?.kind === 'sqlite-cli-control-child' &&
      positive(child.launcherPid) && positive(child.sqlitePid) &&
      new Set([row.collectorPid, child.launcherPid, child.sqlitePid]).size === 3 &&
      child.parentPid === row.collectorPid && child.operation === row.operation &&
      child.nodeExecutable === protocol.nodeExecutable && child.stateId === fixture.databaseBefore.path &&
      child.outputBytes === Buffer.byteLength(protocol.expectedJsonl) &&
      child.outputSha256 === outputSha256 && row.output === protocol.expectedJsonl,
    'Native sample process/output correspondence required');
    const adapter = nanos(child.adapterElapsedNs);
    requireValue(total > adapter && adapter > sqlite + conversion &&
      total === sqlite + conversion + remaining &&
      nanos(child.sqliteProcessElapsedNs) === sqlite &&
      nanos(child.conversionAndOracleElapsedNs) === conversion &&
      child.engineOnlyElapsedNs === null && child.durableLogicalTransitions === 0 &&
      Number.isFinite(Date.parse(row.wallStart)) && Number.isFinite(Date.parse(row.wallEnd)) &&
      Date.parse(row.wallEnd) >= Date.parse(row.wallStart), 'Invalid Native sample clock decomposition');
    if (!row.warmup) measured[row.operation].push({total, sqlite, conversion, remaining});
  }
  const summary = values => {
    const sorted = values.map(value => value / 1e6).sort((a, b) => a - b);
    return {count: sorted.length, minMs: sorted[0], medianMs: sorted[Math.floor(sorted.length / 2)],
      maxMs: sorted.at(-1), p95Ms: null, medianMethod: 'upper-middle order statistic'};
  };
  const operations = {};
  for (const name of names) {
    const rows = measured[name], total = summary(rows.map(row => row.total));
    requireValue(rows.length === protocol.samplesPerOperation &&
      ['count', 'minMs', 'medianMs', 'maxMs', 'p95Ms'].every(key => control.operations[name][key] === total[key]),
    'Native summary differs from raw measured samples');
    operations[name] = {total, sqliteProcess: summary(rows.map(row => row.sqlite)),
      conversionAndOracle: summary(rows.map(row => row.conversion)),
      launcherAndRemaining: summary(rows.map(row => row.remaining))};
  }
  return outcome([], ['matched Native product comparator and essential-work profile', ...control.missingCorrespondence], {
    scope: 'query-only process diagnostic; no public operation or latency-gate coverage',
    structuredControlSha256: evidenceHash(control), protocolSha256: control.protocol.sha256,
    binaries: control.binaries, environment: control.environment, actualSettings: control.actualSettings,
    preparation: control.preparation, completion: control.completion, operations,
    unmeasuredCounters: Object.fromEntries(unknownCounters.map(key => [key, null])),
    comparisonProfile: null, essentialOverheadAllowance: null,
    timingQualification: 'Per-sample components sum exactly; marginal medians are not additive. No acceptance p95 or retained-Host temperature is inferred.'});
}

export function calibratedLatencyTarget(series, comparison) {
  const target = operationTargets[series.operation];
  requireValue(Object.hasOwn(operationTargets, series.operation), 'Unknown public operation');
  if (!target.comparison) return {target, missing: []};
  if (!comparison?.baseline || !comparison.profile) return {target, missing: ['measured fixed SQLite comparison profile']};
  const actual = calibrateSqliteComparisonProfile(comparison.baseline, comparison.resultControl);
  requireValue(evidenceHash(comparison.profile) === evidenceHash(actual), 'Comparison profile differs from fixed baseline-only policy');
  const entry = actual.entries.find(row => row.operation === series.operation);
  if (!entry) return {target, missing: ['matched SQLite operation comparator']};
  const storage = series.operation === 'warm-result' ? actual.resultStorage : undefined;
  const synchronizationComparison = sqliteSettingsComparison(series.comparisonSettings, actual.settings);
  const resultStorageSynchronizationComparison = storage
    ? sqliteSettingsComparison(series.resultStorageMatch?.settings, storage.conditions.settings) : undefined;
  const missing = storage ? ['required public work coverage outside the storage control']
    : ['matched minimum public essential-work comparator'];
  if (storage && (!resultStorageSynchronizationComparison.matched ||
      evidenceHash({...series.resultStorageMatch, settings: storage.conditions.settings}) !== evidenceHash(storage.conditions))) {
    missing.push('actual Result key/body/group correspondence');
  }
  if (['warm-result', 'warm-status'].includes(series.operation)) missing.push('actual saved-row/key/durability comparator correspondence');
  if (actual.environmentSha256 !== series.environmentSha256 || actual.load !== series.load) missing.push('matched comparator environment/load');
  if (series.executableSha256 !== comparison.baseline.executableSha256) missing.push('matched comparator runtime executable');
  if (!synchronizationComparison.matched) missing.push('matched stated transaction/durability settings');
  if (entry.fixtureSha256 !== series.fixtureSha256 || series.expectedSha256 !== entry.expectedSha256) missing.push('matched public fixture/oracle');
  if (evidenceHash(series.comparisonMatch) !== evidenceHash(entry.conditions)) missing.push('matched data/indexes/materialization/preparation/durability conditions');
  // These measured engine/minimum-control limits are diagnostic history. They
  // become public acceptance limits only after the existing semantic Owner's
  // required transitions have a matched measured comparator.
  return {target: {...target, diagnosticComparison: entry, synchronizationComparison,
    ...(storage ? {resultStorageComparison: storage, resultStorageSynchronizationComparison} : {})}, missing};
}

export function assessLatency(series, comparison) {
  requireValue(Object.hasOwn(operationTargets, series.operation), 'Unknown public operation');
  const calibration = calibratedLatencyTarget(series, comparison);
  return assessLatencyTarget(series, calibration.target, calibration.missing);
}

function assessLatencyTarget(series, target, initialMissing = []) {
  requireValue(digest(series.cohortSha256) && digest(series.fixtureSha256) && digest(series.environmentSha256),
    'Exact cohort, fixture and environment identities are required');
  requireValue(['diagnostic', 'final'].includes(series.mode) && Array.isArray(series.samples), 'Invalid measurement mode');
  const failures = [], missing = [...initialMissing];
  const successful = [];
  const keys = new Set();
  for (const row of series.samples) {
    requireValue(integer(row.iteration) && !keys.has(row.iteration), 'Duplicate or invalid sample iteration');
    keys.add(row.iteration);
    requireValue(row.cohortSha256 === series.cohortSha256 && row.fixtureSha256 === series.fixtureSha256,
      'Mixed cohort or fixture samples');
    requireValue(integer(row.pid) && row.pid > 0 && typeof row.cpuScope === 'string' && row.cpuScope.length > 0,
      'Actual process and CPU scope are required');
    if (row.completed !== true || row.verified !== true) failures.push(`sample ${row.iteration}: public completion/oracle failed`);
    else successful.push(row);
  }
  // Validate failed samples too; errors cannot remove inconvenient durations.
  latencySummary(series.samples, target.samples);
  // Retain every raw duration, including a failed or slow original sample.
  // An oracle failure still fails independently; it cannot improve p95/max.
  const summary = latencySummary(series.samples, target.samples);
  const verifiedSummary = latencySummary(successful, target.samples);
  const resources = resourceSummary(series.samples, target.samples);
  if (series.mode !== 'final') missing.push('diagnostic only');
  if (series.profiled !== false) missing.push('uninstrumented latency samples');
  if (series.load !== 'isolated') missing.push('controlled isolated measurement');
  if (series.stoppedEarly) missing.push('measurement stopped early');
  if (summary.count !== target.samples || verifiedSummary.count !== target.samples) missing.push(`${target.samples} successful raw samples`);
  if (target.publicEndToEnd) {
    const actual = assessPublicLatencySamples(series.samples, target.samples, series.operation);
    failures.push(...actual.failures); missing.push(...actual.missing);
    if (!resources.cpu.available) missing.push('actual scoped CPU observations');
    if (!resources.rss.available) missing.push('actual scoped peak RSS observations');
  }
  if (series.operation.startsWith('warm')) {
    if (successful.some(row => typeof row.hostId !== 'string' || !row.hostId)) missing.push('explicit warm Host identity');
    else if (new Set(successful.map(row => row.hostId)).size !== 1 || new Set(successful.map(row => row.pid)).size !== 1) {
      failures.push('warm samples must use the same open Host and process');
    }
  }
  if (series.operation.startsWith('cold') && new Set(successful.map(row => row.pid)).size !== successful.length) {
    failures.push('cold samples must use distinct processes');
  }
  if (series.operation === 'first-init' && new Set(successful.map(row => row.stateId)).size !== successful.length) {
    failures.push('first initialization samples must use distinct state directories');
  }
  if (successful.some(row => typeof row.stateId !== 'string' || !row.stateId)) missing.push('explicit state identity');
  if (target.p95Ms !== undefined && summary.p95Ms !== null && summary.p95Ms > target.p95Ms) failures.push('p95 latency exceeds target');
  if (target.maxMs !== undefined && summary.maxMs !== null && summary.maxMs > target.maxMs) failures.push('maximum latency exceeds target');
  if (summary.count >= target.samples && target.medianMs !== undefined && summary.medianMs > target.medianMs) {
    failures.push('median latency exceeds target');
  }
  const entry = target.diagnosticComparison;
  const diagnosticComparison = entry ? Object.fromEntries(['medianMs', 'p95Ms'].map(key => [key, {
    publicMs: summary[key], engineMs: entry.engine[key],
    ratio: summary[key] === null || entry.engine[key] === 0 ? null : summary[key] / entry.engine[key],
    deltaMs: summary[key] === null ? null : summary[key] - entry.engine[key],
    diagnosticLimitMs: entry[key], publicAcceptance: 'unmatched',
  }])) : null;
  const storage = target.resultStorageComparison;
  const resultStorage = storage ? Object.fromEntries(['medianMs', 'p95Ms'].map(key => [key, {
    publicMs: summary[key], storageControlMs: storage.summary[key],
    ratio: summary[key] === null || storage.summary[key] === 0 ? null : summary[key] / storage.summary[key],
    deltaMs: summary[key] === null ? null : summary[key] - storage.summary[key],
    diagnosticLimitMs: storage.diagnosticLimits[key], publicAcceptance: 'unmatched',
  }])) : null;
  return outcome(failures, missing, {operation: series.operation, target, summary, verifiedSummary, resources, diagnosticComparison, resultStorage});
}

const fullCheckKinds = Object.freeze(['physical-validation', 'current-validation', 'account-evaluation',
  'row-admission', 'decode', 'parse', 'mac', 'hash', 'scope-digest', 'configuration-inventory']);
const activityCounters = Object.freeze(['materialGetterCalls', 'materialCacheHits', 'decodeCalls',
  'databaseReads', 'sqlPrepares']);
const nonempty = value => typeof value === 'string' && value.length > 0;
export function assessStructure(report) {
  const failures = [], missing = [];
  if (!Array.isArray(report.operations) || !report.operations.length) return outcome([], ['actual public-operation counters']);
  if (Object.hasOwn(report, 'frames')) missing.push('legacy frames do not establish public-operation coverage');
  const ids = new Set();
  const measured = [];
  for (const operation of report.operations) {
    requireValue(nonempty(operation.id) && !ids.has(operation.id), 'Duplicate or missing public-operation identity');
    requireValue(Object.hasOwn(operationTargets, operation.operation), 'Unknown measured public operation');
    ids.add(operation.id);
    const label = operation.id;
    if (operation.complete !== true || operation.overflow !== false) missing.push(`${label}: complete non-overflow counters`);
    for (const key of ['unrelatedRunRows', 'unrelatedEffectRows']) {
      if (!integer(operation[key])) missing.push(`${label}: ${key}`);
      else if (operation[key] !== 0) failures.push(`${label}: ${key} is not zero`);
    }
    const activity = operation.activity ?? {};
    for (const key of activityCounters) if (!integer(activity[key])) missing.push(`${label}: ${key}`);
    if (integer(activity.materialGetterCalls) && integer(activity.materialCacheHits) &&
        activity.materialCacheHits > activity.materialGetterCalls) failures.push(`${label}: cache hits exceed material getter calls`);
    const facts = new Map(), incompleteAttribution = new Set(), accountRevisionAttribution = new Map();
    if (!Array.isArray(operation.fullChecks)) missing.push(`${label}: explicit full-validation attribution`);
    else for (const check of operation.fullChecks) {
      requireValue(fullCheckKinds.includes(check.kind) && (check.kind === 'account-evaluation' ||
        nonempty(check.fact) && (nonempty(check.revision) || integer(check.revision))),
      'Full checks require actual fact kind, identity and relevant revision');
      requireValue(typeof check.required === 'boolean', 'Declare required versus pure fact work');
      let tuple = null, revision = check.revision;
      if (check.kind === 'account-evaluation') {
        const value = check.tuple ?? {};
        // subject is the actual AccessTuple.principal. A configured connection
        // and authority scope are permission identities, not getter aliases.
        requireValue(['subject', 'connection', 'operation', 'resource'].every(key => nonempty(value[key])) &&
          ['run', 'target'].every(key => Object.hasOwn(value, key) && (value[key] === null || nonempty(value[key]))),
        'Account checks require the exact subject/connection/operation/resource/Run/target tuple');
        const scope = Object.hasOwn(value, 'authorityScope') ? value.authorityScope : operation.authorityScope;
        requireValue(nonempty(scope), 'Account checks require actual authority scope');
        if (Object.hasOwn(operation, 'authorityScope')) {
          requireValue(nonempty(operation.authorityScope) && scope === operation.authorityScope,
            'Account authority scope differs from the fixed public operation');
        }
        if (!check.accountConfigurationCid) {
          missing.push(`${label}: actual admitted Account configuration attribution`);
          incompleteAttribution.add(check.kind);
          continue;
        }
        requireValue(/^sha256:[a-f0-9]{64}$/u.test(check.accountConfigurationCid),
          'Account checks require the original admitted Account configuration CID');
        if (Object.hasOwn(check, 'policyRevision')) requireValue(nonempty(check.policyRevision) || integer(check.policyRevision),
          'Account policy revision must be an actual observed revision');
        // evaluate_account receives the admitted Account and AccessTuple's four
        // fields. Discovered Run/target and a Run-row revision are trace context,
        // not new evaluator inputs. Target-bound grants remain separate facts.
        tuple = [check.accountConfigurationCid, scope,
          ...['subject', 'connection', 'operation', 'resource'].map(key => value[key])];
        const inputKey = JSON.stringify(tuple);
        const attribution = accountRevisionAttribution.get(inputKey) ?? new Set();
        attribution.add(Object.hasOwn(check, 'policyRevision') ? 'observed-policy' : 'configuration-only');
        accountRevisionAttribution.set(inputKey, attribution);
        // The immutable configuration CID already versions the policy bytes.
        // Use an actual policy revision if supplied, never a made-up zero or
        // the surrounding Run/adoption row revision.
        revision = check.policyRevision ?? check.accountConfigurationCid;
      }
      // Internal frames, helpers, awaits, FFI phases and cache eviction are not
      // validation identities. Sum every entry for the same actual fact and
      // relevant revision across this entire public call. A cache hit reports
      // zero full calls; changing an Account getter's name cannot split a tuple.
      const key = JSON.stringify([check.kind, tuple === null ? check.fact : tuple, String(revision)]);
      const fact = facts.get(key) ?? {kind: check.kind, required: check.required, fullCalls: 0, complete: true,
        ...(tuple ? {evaluatorInputs: tuple, revision, traceContexts: []} : {})};
      if (tuple) fact.traceContexts.push({run: check.tuple.run, target: check.tuple.target,
        observedRevision: check.revision, fullCalls: check.fullCalls});
      requireValue(fact.required === check.required, 'Conflicting required/pure classification for the same fact');
      if (!integer(check.fullCalls)) {
        fact.complete = false;
        missing.push(`${label}: ${check.kind} full calls, separate from entries/cache hits`);
      } else {
        fact.fullCalls += check.fullCalls;
        requireValue(integer(fact.fullCalls), 'Full-validation count overflow');
      }
      facts.set(key, fact);
    }
    const fullCallsByKind = {};
    for (const [key, attribution] of accountRevisionAttribution) if (attribution.size > 1) {
      missing.push(`${label}: consistent actual Account policy revision attribution`);
      incompleteAttribution.add('account-evaluation');
      for (const fact of facts.values()) if (fact.evaluatorInputs && JSON.stringify(fact.evaluatorInputs) === key) {
        fact.complete = false;
      }
    }
    for (const fact of facts.values()) {
      if (!fact.complete) continue;
      if (fact.fullCalls !== (fact.required ? 1 : 0)) failures.push(`${label}: ${fact.kind} must run ${fact.required ? 'once' : 'zero times'} per unchanged fact`);
      fullCallsByKind[fact.kind] = (fullCallsByKind[fact.kind] ?? 0) + fact.fullCalls;
    }
    // Every physical full-work counter must be supplied, including real zeros.
    // Attribution alone cannot hide unmeasured or omitted validation kinds.
    for (const kind of fullCheckKinds) {
      const total = operation.fullTotals?.[kind];
      if (!integer(total)) missing.push(`${label}: ${kind} full total`);
      else if (!incompleteAttribution.has(kind) && ![...facts.values()].some(fact => fact.kind === kind && !fact.complete)) {
        if (total > 0 && !Object.hasOwn(fullCallsByKind, kind)) missing.push(`${label}: ${kind} fact attribution`);
        else if (total !== (fullCallsByKind[kind] ?? 0)) failures.push(`${label}: ${kind} full total differs from fact attribution`);
      }
    }
    if (integer(activity.decodeCalls)) {
      if (integer(operation.fullTotals?.decode) && activity.decodeCalls !== operation.fullTotals.decode) {
        failures.push(`${label}: decode calls differ from attributed full decodes`);
      }
    }
    if (operation.operation === 'warm-status' && typeof operation.unchangedStatus !== 'boolean') missing.push(`${label}: status change observation`);
    if (operation.unchangedStatus === true) {
      if (!integer(operation.statusWrites) || !integer(operation.revisionBefore) || !integer(operation.revisionAfter)) missing.push(`${label}: status observation`);
      else if (operation.statusWrites !== 0 || operation.revisionBefore !== operation.revisionAfter) failures.push(`${label}: unchanged status mutated`);
    }
    measured.push({id: operation.id, operation: operation.operation, factCount: facts.size, fullCallsByKind,
      incompleteAttribution: [...incompleteAttribution],
      accountEvaluations: [...facts.values()].filter(fact => fact.kind === 'account-evaluation'),
      // Keep physical DB/prepare work and getters observable without presenting
      // function entries or cache hits as full validation counts.
      activity});
  }
  return outcome(failures, missing, {operationCount: ids.size, operations: measured});
}

export function assessHistory(rows) {
  return assessHistoryOperations(rows, Object.keys(operationTargets).filter(name => name.startsWith('warm-')));
}

function assessHistoryOperations(rows, requiredOperations) {
  const failures = [], missing = [], operations = new Map();
  for (const row of rows) {
    requireValue(historySizes.includes(row.size), 'Unsupported history selection');
    if (row.operation === undefined) {
      missing.push(`history ${row.size}: public-operation attribution`);
      continue;
    }
    requireValue(Object.hasOwn(operationTargets, row.operation), 'Unknown history public operation');
    let group = operations.get(row.operation);
    if (!group) {group = {sizes: new Set(), control: undefined}; operations.set(row.operation, group);}
    const {sizes} = group, label = `history ${row.operation} ${row.size}`;
    requireValue(!sizes.has(row.size), 'Duplicate history public-operation selection');
    sizes.add(row.size);
    if (row.supported !== true) { missing.push(`${label}: ${row.reason || 'not supported'}`); continue; }
    requireValue(digest(row.fixtureSha256), 'History fixture identity required');
    group.control ??= row;
    const {control} = group;
    if (row.fixtureSha256 !== control.fixtureSha256) failures.push(`${label}: target fixture changed`);
    for (const key of ['targetRowsRead', 'databaseReads', 'sqlPrepares', 'materialGetterCalls', 'materialCacheHits',
      'fullPhysicalValidations', 'fullCurrentValidations', 'fullRowAdmissions', 'decodeCalls', 'fullParses',
      'fullMacValidations', 'fullHashValidations', 'fullScopeDigests', 'fullConfigurationInventories', 'fullAccountEvaluations']) {
      if (!integer(row[key])) missing.push(`${label}: ${key}`);
      else if (row[key] !== control[key]) failures.push(`${label}: target ${key} changed with unrelated history`);
    }
    for (const key of ['unrelatedRunRows', 'unrelatedEffectRows']) {
      if (!integer(row[key])) missing.push(`${label}: ${key}`);
      else if (row[key] !== 0) failures.push(`${label}: ${key} is not zero`);
    }
  }
  // Derive coverage from the existing warm public operations. A saved-read
  // series cannot stand in for new query binding or another execution path.
  for (const operation of requiredOperations) {
    for (const size of historySizes) if (!operations.get(operation)?.sizes.has(size)) {
      missing.push(`history ${operation} ${size}`);
    }
  }
  return outcome(failures, missing);
}

export function assessChunks(rows) {
  const failures = [], missing = [], sizes = new Set();
  let boundaryCount;
  for (const row of rows) {
    requireValue([1024, 16384, 262144].includes(row.bytes) && !sizes.has(row.bytes), 'Duplicate or unknown chunk fixture');
    sizes.add(row.bytes);
    for (const key of ['chunks', 'rows', 'boundaries', 'hostCalls', 'scalarByteCalls']) {
      if (!integer(row[key])) missing.push(`${row.bytes}: ${key}`);
    }
    if (!integer(row.chunkBytes) || row.chunkBytes < 16384 || row.chunkBytes > 65536) missing.push(`${row.bytes}: bounded chunk size`);
    else if (row.chunks !== Math.ceil(row.bytes / row.chunkBytes)) failures.push(`${row.bytes}: chunk count does not match payload`);
    if (integer(row.boundaries)) {
      boundaryCount ??= row.boundaries;
      if (row.boundaries !== boundaryCount) failures.push('control boundaries changed with payload size');
    }
    if (integer(row.rows) && row.rows !== 1) failures.push(`${row.bytes}: expected one controlled fixture row`);
    // One bulk call per declared transfer unit. The owner counts actual row and
    // control boundaries separately; a bytes field cannot inflate the budget.
    if (integer(row.hostCalls) && integer(row.chunks) && integer(row.rows) && integer(row.boundaries) &&
        row.hostCalls > row.chunks + row.rows + row.boundaries) failures.push(`${row.bytes}: host calls exceed transfer units`);
    if (integer(row.scalarByteCalls) && row.scalarByteCalls !== 0) failures.push(`${row.bytes}: scalar byte calls remain`);
    if (row.complete !== true || row.overflow !== false) missing.push(`${row.bytes}: complete chunk observation`);
  }
  for (const size of [1024, 16384, 262144]) if (!sizes.has(size)) missing.push(`journal fixture ${size}`);
  return outcome(failures, missing);
}

export const boundaryExpectations = Object.freeze({
  'deny-before-operation': {outcome: 'rejected', sends: 0},
  'policy-before-dispatch': {outcome: 'rejected', sends: 0},
  'target-before-dispatch': {outcome: 'rejected', sends: 0},
  'key-before-dispatch': {outcome: 'rejected', sends: 0},
  'reentry-revision': {staleFrameRejected: true},
  'foreign-cache': {outcome: 'rejected'},
  'used-row-tamper': {outcome: 'rejected'},
  'unrelated-row-corruption': {targetSucceeded: true, targetUnrelatedRows: 0, explicitIntegrityDetected: true},
  'index-original-mismatch': {outcome: 'rejected', blindResends: 0},
  'concurrent-claim': {dispatches: 1},
  'commit-unknown': {outcome: 'unknown', blindResends: 0},
  'send-reply-lost': {outcome: 'unknown', blindResends: 0},
  'chunk-interrupted': {incompleteRejected: true, resourcesAccounted: true},
  'configuration-missing': {outcome: 'rejected', regrants: 0, rekeys: 0},
  'cancel-or-budget': {additionalWorkStopped: true, cleanupPossible: true, overwrittenAsSuccess: false},
  'reopen-cache-miss': {sameRun: true, newRuns: 0},
});
for (const expectation of Object.values(boundaryExpectations)) Object.freeze(expectation);
export function assessBoundaries(rows) {
  return assessBoundarySet(rows, boundaryExpectations);
}

function assessBoundarySet(rows, expectations) {
  const failures = [], missing = [], seen = new Set();
  for (const row of rows) {
    requireValue(Object.hasOwn(expectations, row.case) && !seen.has(row.case), 'Duplicate or unknown boundary case');
    seen.add(row.case);
    for (const [key, expected] of Object.entries(expectations[row.case])) {
      if (!Object.hasOwn(row, key)) missing.push(`${row.case}: ${key}`);
      else if (row[key] !== expected) failures.push(`${row.case}: ${key}`);
    }
  }
  for (const name of Object.keys(expectations)) if (!seen.has(name)) missing.push(name);
  return outcome(failures, missing);
}

// The callback must await the public operation AND verify materialized output.
// Timing hooks do not wrap product getters, authorization or cryptography.
export async function collectOperationSamples({operation, mode, identity, stateId, execute, emit,
  now = () => process.hrtime.bigint(), cpu = () => process.cpuUsage(), pid = process.pid, targetP95Ms}) {
  // Cold/init measurements must come from actual child-process adapters with
  // their individual PID/state observations, never this warm-process clock.
  requireValue(Object.hasOwn(operationTargets, operation) && operation.startsWith('warm-') &&
    ['diagnostic', 'final'].includes(mode), 'This collector supports warm operations only');
  const target = operationTargets[operation], count = mode === 'final' ? target.samples : 3;
  const samples = [];
  let stopReason = null;
  for (let iteration = 0; iteration < count; iteration++) {
    const beforeCpu = cpu(), start = now();
    let verified = false, error;
    try { await execute(iteration); verified = true; } catch (failure) { error = String(failure?.message ?? failure); }
    const end = now(), wallNs = Number(end - start), afterCpu = cpu();
    const row = {...identity, iteration, stateId, pid, wallNs,
      cpuUserUs: afterCpu.user - beforeCpu.user, cpuSystemUs: afterCpu.system - beforeCpu.system,
      cpuScope: 'collector-process-only', completed: verified, verified,
      peakRssBytes: process.resourceUsage().maxRSS * 1024,
      rssScope: 'actual Node process high-water RSS, including prior setup/operations; not operation allocation',
      ...(verified ? {publicTiming: {kind: operation === 'warm-status' ? 'public-status' : 'public-result',
        startNs: Number(start), observedNs: Number(end), endNs: Number(end)}} : {}),
      ...(error ? {error} : {})};
    latencySummary([row], target.samples);
    samples.push(row);
    await emit(row);
    // An obvious slow sample stops expensive preparation. It is retained as a
    // diagnostic; it cannot be turned into a final p95 or a successful gate.
    // A missing comparison never supplies a pass. Retain the existing 100 ms
    // unprofiled early-stop budget solely to avoid repeating an expensive diagnostic.
    const stopMs = targetP95Ms === undefined ? 100 : targetP95Ms * 10;
    requireValue(Number.isFinite(stopMs) && stopMs > 0, 'Invalid diagnostic stop budget');
    if (!verified || wallNs / 1e6 >= stopMs) {
      stopReason = verified ? 'slow diagnostic; final distribution not measured' : 'public functional failure';
      break;
    }
  }
  return {samples, stoppedEarly: samples.length < count || stopReason !== null, stopReason};
}

export function assessPerformanceEvidence(report) {
  requireValue(/^[a-f0-9]{40}$/u.test(report.sourceSha ?? '') && digest(report.cohortSha256), 'Fixed ordinary cohort identity required');
  requireValue(digest(report.environmentSha256) && digest(report.historyProtocolSha256), 'Environment and history protocol identities required');
  const native = report.comparison?.nativeSqliteDiagnostic;
  let diagnostics;
  if (native !== undefined) {
    requireValue(native && Object.keys(native).sort().join(',') === 'control,protocolText',
      'Explicit Native control and protocol text required');
    diagnostics = {nativeSqlite: assessNativeSqliteDiagnostic(native.control, native.protocolText)};
  }
  const gates = {}, failures = [], missing = [], seen = new Set();
  for (const series of report.latency ?? []) {
    requireValue(series.cohortSha256 === report.cohortSha256, 'Latency cohort differs from functional/structural cohort');
    requireValue(series.environmentSha256 === report.environmentSha256 &&
      series.historyProtocolSha256 === report.historyProtocolSha256, 'Latency environment or history protocol differs');
    requireValue(!seen.has(series.operation), 'Duplicate operation series');
    seen.add(series.operation);
    gates[series.operation] = assessLatency(series, report.comparison);
  }
  for (const operation of Object.keys(operationTargets)) if (!seen.has(operation)) missing.push(operation);
  for (const [name, assess] of [['functional', assessFunctions], ['structure', assessStructure], ['history', assessHistory],
    ['chunks', assessChunks], ['boundaries', assessBoundaries]]) {
    const section = report[name];
    if (!section) { missing.push(name); continue; }
    requireValue(section.cohortSha256 === report.cohortSha256, `${name} cohort differs from latency cohort`);
    requireValue(section.environmentSha256 === report.environmentSha256 &&
      section.historyProtocolSha256 === report.historyProtocolSha256, `${name} environment or history protocol differs`);
    gates[name] = assess(name === 'structure' ? section : section.rows);
    if (name === 'structure') {
      for (const operation of Object.keys(operationTargets)) {
        if (!section.operations?.some(row => row.operation === operation)) gates[name].missing.push(`${operation}: public-operation work coverage`);
      }
      if (gates[name].status === 'passed' && gates[name].missing.length) gates[name].status = 'incomplete';
    }
  }
  for (const [name, gate] of Object.entries(gates)) {
    failures.push(...gate.failures.map(reason => `${name}: ${reason}`));
    missing.push(...gate.missing.map(reason => `${name}: ${reason}`));
  }
  return outcome(failures, missing, {sourceSha: report.sourceSha, cohortSha256: report.cohortSha256, gates,
    ...(diagnostics ? {diagnostics} : {}),
    qualification: 'Assesses supplied measurements; does not authenticate their provenance or establish full product completion.'});
}

export function assessFunctions(rows) {
  return assessFunctionOperations(rows, Object.keys(operationTargets));
}

function assessFunctionOperations(rows, requiredOperations) {
  const failures = [], missing = [], seen = new Set();
  for (const row of rows) {
    requireValue(Object.hasOwn(operationTargets, row.operation) && !seen.has(row.operation), 'Duplicate or unknown functional case');
    seen.add(row.operation);
    if (row.completed !== true) failures.push(`${row.operation}: public operation did not complete`);
    if (!digest(row.expectedSha256) || !digest(row.actualSha256)) missing.push(`${row.operation}: independent result oracle`);
    else if (row.expectedSha256 !== row.actualSha256) failures.push(`${row.operation}: result oracle mismatch`);
  }
  for (const operation of requiredOperations) if (!seen.has(operation)) missing.push(operation);
  return outcome(failures, missing);
}

export const priorityTransitionTarget = Object.freeze({samples: 100, medianMs: 250, p95Ms: 500});
const priorityOperations = Object.freeze(['warm-select', 'warm-result']);
const priorityBoundaries = Object.freeze({
  ...Object.fromEntries(['deny-before-operation', 'target-before-dispatch', 'commit-unknown',
    'send-reply-lost', 'reopen-cache-miss', 'cancel-or-budget'].map(name => [name, boundaryExpectations[name]])),
  'no-preapproval-write': Object.freeze({writesBeforeApproval: 0, explicitSignedApproval: true,
    previewTargetMatched: true}),
});

function assessPriorityWorkload(series) {
  const failures = [], missing = [], workload = series.publicWorkload;
  if (!workload) return outcome([], ['actual varied public workload and original Run/Result metadata']);
  if (series.fixtureSha256 !== evidenceHash(workload)) failures.push('public workload differs from fixed fixture identity');
  const fresh = series.operation === 'warm-select';
  if (workload.kind !== (fresh ? 'new-durable-run-result-rows' : 'saved-original-result-rows')) {
    failures.push('public completion is not the selected durable operation');
  }
  const fixtures = new Map(), originals = new Map();
  for (const fixture of workload.fixtures ?? []) {
    requireValue(digest(fixture.querySha256) && digest(fixture.expectedSha256) &&
      !fixtures.has(fixture.querySha256), 'Unique independent query fixture identities required');
    fixtures.set(fixture.querySha256, fixture.expectedSha256);
  }
  for (const original of workload.originals ?? []) {
    requireValue(digest(original.runRefSha256) && digest(original.resultRefSha256) &&
      digest(original.expectedSha256) && !originals.has(original.resultRefSha256), 'Unique original Result identities required');
    originals.set(original.resultRefSha256, original);
  }
  const operations = new Set(), runs = new Set(), results = new Set(), queries = new Set(), outputs = new Set();
  for (const row of series.samples) {
    if (!['pid', 'hostId', 'stateId'].every(key => row[key] === series.samples[0][key])) {
      failures.push('warm public samples changed Host/process/state');
    }
    if (typeof row.publicOperationId !== 'string' || !row.publicOperationId) missing.push('actual public operation identity');
    else {
      if (operations.has(row.publicOperationId)) failures.push('public operation sample repeated');
      operations.add(row.publicOperationId);
    }
    if (![row.runRefSha256, row.resultRefSha256, row.expectedSha256, row.actualSha256].every(digest)) {
      missing.push('actual original Run/Result and materialized-row oracle identities'); continue;
    }
    if (row.actualSha256 !== row.expectedSha256) failures.push('materialized rows differ from independent oracle');
    if (fresh) {
      if (!digest(row.querySha256)) missing.push('actual new-query fixture identity');
      else {
        if (fixtures.get(row.querySha256) !== row.expectedSha256) failures.push('new query differs from fixed independent fixtures');
        queries.add(row.querySha256);
      }
      if (runs.has(row.runRefSha256) || results.has(row.resultRefSha256)) failures.push('new query reused a prior Run or Result');
    } else {
      const original = originals.get(row.resultRefSha256);
      if (!original || original.runRefSha256 !== row.runRefSha256 || original.expectedSha256 !== row.expectedSha256) {
        failures.push('saved read differs from original Run/Result');
      }
    }
    runs.add(row.runRefSha256); results.add(row.resultRefSha256); outputs.add(row.expectedSha256);
  }
  if ((fresh ? queries : results).size < 2 || outputs.size < 2) missing.push('varied small query/results, not one repeated fixed value');
  const first = series.firstQuery;
  if (!first) missing.push('separate actual first-query observation');
  else {
    requireValue(integer(first.wallNs) && integer(first.cpuUserUs) && integer(first.cpuSystemUs), 'Invalid first-query timing');
    if (typeof first.cpuScope !== 'string' || !first.cpuScope) missing.push('actual first-query CPU scope');
    if (first.completed !== true || first.verified !== true) failures.push('first public query failed');
    if (typeof first.publicOperationId !== 'string' || !first.publicOperationId ||
        ![first.runRefSha256, first.resultRefSha256, first.expectedSha256, first.actualSha256].every(digest)) {
      missing.push('first-query operation, original Run/Result and oracle identity');
    } else {
      if (operations.has(first.publicOperationId)) failures.push('first query blended into warm distribution');
      if (first.expectedSha256 !== first.actualSha256) failures.push('first-query materialized rows differ');
      if (fresh && (runs.has(first.runRefSha256) || results.has(first.resultRefSha256))) {
        failures.push('new warm query reused first-query Run or Result');
      }
    }
    const sample = series.samples[0];
    if (!sample || !['pid', 'hostId', 'stateId'].every(key => first[key] === sample[key])) {
      failures.push('first query belongs to another Host/process/state');
    }
  }
  return outcome(failures, missing, {firstQueryMs: first ? first.wallNs / 1e6 : null,
    distinctQueries: queries.size, distinctResults: results.size, publicOperations: operations.size});
}

function assessPriorityPopulation(series) {
  const failures = [], missing = [], population = series.population;
  if (!population) return outcome([], ['actual measured population scan and temporary-usage observations']);
  if (population.complete !== true || population.overflow !== false) missing.push('complete non-overflow population observations');
  if (!Array.isArray(population.publicOperationIds)) missing.push('observed public operation population');
  else if (evidenceHash(population.publicOperationIds) !== evidenceHash(series.samples.map(row => row.publicOperationId))) {
    failures.push('work observations differ from the timed public population');
  }
  for (const key of ['unrelatedRunRows', 'unrelatedEffectRows']) {
    if (!integer(population[key])) missing.push(key);
    else if (population[key] !== 0) failures.push(`${key} is not zero`);
  }
  // Observe quiescent temporary holdings after initial/shared preparation.
  // Genuine Host/shared holdings and durable history are outside this count;
  // neither a configured cap nor RSS can excuse retained temporary growth.
  const temporary = population.temporaryRetained;
  if (!temporary || !['beforeBytes', 'afterBytes', 'peakBytes', 'capacityBytes'].every(key => integer(temporary[key]))) {
    missing.push('actual temporary holdings and existing configured capacity');
  }
  else if (temporary.peakBytes < Math.max(temporary.beforeBytes, temporary.afterBytes) ||
      temporary.peakBytes > temporary.capacityBytes) failures.push('temporary holdings exceed their observed fixed bound');
  if (integer(temporary?.beforeBytes) && integer(temporary?.afterBytes) && temporary.afterBytes > temporary.beforeBytes) {
    failures.push('temporary holdings grew after quiescent population completion');
  }
  return outcome(failures, missing);
}

// The explicit input combines untouched raw reports from both ordinary SDK
// artifacts. Missing collector fields remain incomplete: CI must not synthesize
// variation, safety or environmental observations to satisfy this selection.
// This decision only changes work prioritization, never release acceptance.
export function assessPriorityTransition(input) {
  requireValue(/^[a-f0-9]{40}$/u.test(input.sourceSha ?? ''), 'Fixed priority-transition source required');
  const gates = {}, failures = [], missing = [];
  for (const platform of ['node', 'python']) {
    const reports = input.platforms?.[platform];
    if (!Array.isArray(reports) || !reports.length) {missing.push(`${platform}: ordinary raw reports`); continue;}
    const series = new Map(), functions = [], operations = [], histories = [], boundaries = [];
    let binding;
    const localFailures = [], localMissing = [];
    for (const report of reports) {
      requireValue(report.sourceSha === input.sourceSha && digest(report.cohortSha256) &&
        digest(report.environmentSha256) && digest(report.historyProtocolSha256), 'Fixed ordinary platform report identity required');
      binding ??= report;
      requireValue(report.cohortSha256 === binding.cohortSha256 && report.environmentSha256 === binding.environmentSha256,
        'Mixed platform artifact cohort or environment');
      if (report.historyProtocolSha256 !== binding.historyProtocolSha256) localMissing.push('one shared controlled history protocol');
      if (report.executionPath !== `${platform}-sdk`) localMissing.push('actual ordinary public SDK execution path');
      if (report.installedPayloadsUnchanged !== true) localMissing.push('successful installed-package correspondence');
      if (report.packageFailure || report.firstFailure || report.cleanup?.failure) localFailures.push('reported public/package/cleanup failure');
      if (report.managedRunObservations !== undefined) {
        const observed = report.managedRunObservations;
        requireValue(observed?.scope === 'managed-run-ledger' &&
          ['cohortSha256', 'environmentSha256', 'historyProtocolSha256'].every(key => observed[key] === report[key]),
        'Managed Run observation differs from original report binding');
        if (observed.status === 'failed') localFailures.push('requested managed Run observation failure');
        else if (observed.status !== 'passed') localMissing.push('complete requested managed Run observations');
        else {
          const samples = [report.firstQuery, ...(report.latency ?? []).flatMap(row => row.samples ?? [])].filter(Boolean);
          const captured = observed.operations;
          if (!Array.isArray(captured) || captured.length !== samples.length ||
              !Array.isArray(observed.records) || observed.records.length !== samples.length ||
              new Set(captured.map(row => row.publicOperationId)).size !== samples.length ||
              samples.some(sample => !captured.some(row => row.publicOperationId === sample.publicOperationId &&
                row.completed === true && row.runRefSha256 === sample.runRefSha256 &&
                Number.isSafeInteger(row.observationSequence) && observed.records.filter(record =>
                  record.sequence === row.observationSequence && record.traceId === row.traceId &&
                  record.spanId === row.spanId && record.runDefinitionCid === row.runDefinitionCid).length === 1))) {
            localFailures.push('managed Run observations differ from timed public operations');
          }
        }
      }
      if (report.historyProtocol?.rowObservations !== undefined || report.selectedRowObservations !== undefined) {
        const observed = report.selectedRowObservations;
        if (observed === undefined) localMissing.push('requested selected row observations');
        else {
          requireValue(report.historyProtocol?.rowObservations?.scope === 'selected-returned' &&
            observed.scope === 'selected-returned' &&
            ['cohortSha256', 'environmentSha256', 'historyProtocolSha256'].every(key => observed[key] === report[key]),
          'Selected row observation differs from original report binding');
          if (observed.status === 'failed') localFailures.push('requested selected row observation failure');
          else if (observed.status !== 'passed') localMissing.push('complete requested selected row observations');
          else {
            const samples = [report.firstQuery, ...(report.latency ?? []).flatMap(row => row.samples ?? [])].filter(Boolean);
            const captured = observed.operations, records = observed.records;
            if (!Array.isArray(captured) || !Array.isArray(records) || captured.length !== samples.length ||
                new Set(captured.map(row => row.publicOperationId)).size !== samples.length ||
                new Set(records.map(row => row.sequence)).size !== records.length ||
                records.some(row => row.owner !== 'request-journal' || row.kind !== 'run' ||
                  row.coverage !== 'selected-returned' || !['run-definition', 'request', 'mixed-selected'].includes(row.selection) ||
                  !integer(row.returned) || row.unrelated !== undefined && (!integer(row.unrelated) || row.unrelated > row.returned)) ||
                samples.some(sample => !captured.some(row => row.publicOperationId === sample.publicOperationId &&
                  row.completed === true && row.runRefSha256 === sample.runRefSha256 &&
                  Array.isArray(row.rowObservationSequences) && row.rowObservationSequences.length > 0 &&
                  new Set(row.rowObservationSequences).size === row.rowObservationSequences.length &&
                  row.rowObservationSequences.every(sequence => integer(sequence) && records.filter(record =>
                    record.sequence === sequence && record.traceId === row.traceId && record.spanId === row.spanId &&
                    record.runDefinitionCid === row.runDefinitionCid).length === 1))) ||
                records.some(record => captured.filter(row => row.rowObservationSequences?.includes(record.sequence) &&
                  row.traceId === record.traceId && row.spanId === record.spanId).length !== 1)) {
              localFailures.push('selected row observations differ from timed public operations');
            }
            if (Array.isArray(records) && records.some(row => row.unrelated > 0)) localFailures.push('observed unrelated selected Run rows');
          }
        }
      }
      if (report.cleanup?.closed !== true) localMissing.push('explicit successful original Host close');
      for (const key of ['startedHost', 'noCompetingLargeBuild', 'guaranteesUnchanged']) {
        if (report.priorityConditions?.[key] === false && key !== 'noCompetingLargeBuild') localFailures.push(`${key} requirement violated`);
        else if (report.priorityConditions?.[key] !== true) localMissing.push(`actual ${key} observation`);
      }
      if (report.priorityConditions?.boundedTemporaryGrowth === false) localFailures.push('reported unbounded temporary growth');
      for (const value of report.latency ?? []) {
        if (!priorityOperations.includes(value.operation)) continue;
        requireValue(!series.has(value.operation), 'Duplicate priority operation series');
        for (const key of ['cohortSha256', 'environmentSha256', 'historyProtocolSha256']) {
          requireValue(value[key] === report[key], 'Priority latency differs from original report binding');
        }
        series.set(value.operation, value);
      }
      for (const [key, target] of [['functional', functions], ['structure', operations], ['history', histories],
        ['boundaries', boundaries], ['prioritySafety', boundaries]]) {
        const section = report[key]; if (!section) continue;
        for (const identity of ['cohortSha256', 'environmentSha256', 'historyProtocolSha256']) {
          requireValue(section[identity] === report[identity], 'Priority safety/work section differs from original report binding');
        }
        target.push(...(key === 'structure' ? section.operations ?? [] : section.rows ?? []));
      }
    }
    const selected = Object.fromEntries([...series].map(([name, value]) => [name, {
      latency: assessLatencyTarget(value, priorityTransitionTarget), workload: assessPriorityWorkload(value),
      population: assessPriorityPopulation(value),
    }]));
    for (const [name, value] of series) {
      const row = functions.find(item => item.operation === name);
      if (!row || !digest(row.fixtureSha256)) localMissing.push(`${name}: functional population binding`);
      else if (row.fixtureSha256 !== value.fixtureSha256 ||
          row.expectedSha256 !== evidenceHash(value.samples.map(sample => sample.expectedSha256)) ||
          row.actualSha256 !== evidenceHash(value.samples.map(sample => sample.actualSha256))) {
        localFailures.push(`${name}: functional oracle differs from timed public population`);
      }
    }
    for (const name of priorityOperations) if (!series.has(name)) localMissing.push(`${name}: actual raw distribution`);
    // Detailed regressions remain useful if supplied, but missing full-release
    // attribution or history-grid coverage is not a transition prerequisite.
    if (operations.length) localFailures.push(...assessStructure({operations}).failures.map(reason => `reported structure: ${reason}`));
    if (histories.length) localFailures.push(...assessHistory(histories).failures.map(reason => `reported history: ${reason}`));
    const checks = {functional: assessFunctionOperations(functions.filter(row => priorityOperations.includes(row.operation)), priorityOperations),
      boundaries: assessBoundarySet(boundaries.filter(row => Object.hasOwn(priorityBoundaries, row.case)), priorityBoundaries)};
    for (const [name, value] of Object.entries(selected)) {
      checks[`${name} latency`] = value.latency; checks[`${name} workload`] = value.workload;
      checks[`${name} population`] = value.population;
    }
    for (const [name, check] of Object.entries(checks)) {
      localFailures.push(...check.failures.map(reason => `${name}: ${reason}`));
      localMissing.push(...check.missing.map(reason => `${name}: ${reason}`));
    }
    gates[platform] = outcome(localFailures, localMissing, {cohortSha256: binding.cohortSha256, checks});
    failures.push(...localFailures.map(reason => `${platform}: ${reason}`));
    missing.push(...localMissing.map(reason => `${platform}: ${reason}`));
  }
  return outcome(failures, missing, {purpose: 'priority-transition-only', sourceSha: input.sourceSha,
    target: priorityTransitionTarget, gates, releaseAccepted: false, fullPerformanceAccepted: false,
    qualification: 'Assesses supplied ordinary evidence only. Passing does not establish SQLite equivalence, release readiness or full product completion.'});
}


// CLI startup is measured on both routes. These targets do not add Native
// requirements to the retained-Host SDK gate or establish full acceptance.
export const nativeOperationTarget = Object.freeze({samples: 100, medianMs: 100,
  publicEndToEnd: true, ...publicLatencyTarget});
export function assessNativeOperations(report) {
  requireValue(report?.selection === 'native-operations' && report.executionPath === 'native-cli' &&
    /^[a-f0-9]{40}$/u.test(report.sourceSha), 'Ordinary Native operation report required');
  const identities = ['cohortSha256', 'environmentSha256', 'historyProtocolSha256'];
  requireValue(identities.every(key => digest(report[key])), 'Exact Native cohort/environment/protocol required');
  const failures = [], missing = [], checks = {};
  requireValue(evidenceHash(report.environment) === report.environmentSha256, 'Native environment differs from its identity');
  const protocol = report.historyProtocol, count = report.mode === 'final' ? 100 : 3;
  requireValue(['diagnostic', 'final'].includes(report.mode) && protocol?.selection === 'native-operations' &&
    protocol.mode === report.mode && protocol.samplesPerOperation === count &&
    evidenceHash(protocol) === report.historyProtocolSha256, 'Native protocol differs from its original identity');
  requireValue(protocol.firstQuery?.text === 'SELECT 0 AS id' &&
    evidenceHash(protocol.firstQuery.expected) === evidenceHash([{id: 0}]), 'Separate Native first query/oracle required');
  requireValue(protocol.queries?.length === count && protocol.queries.every((row, index) =>
    row.text === `SELECT ${index + 1} AS id` && evidenceHash(row.expected) === evidenceHash([{id: index + 1}])),
  'Varied Native query/oracle protocol required');
  if (report.firstFailure != null || report.packageFailure != null) failures.push('known original public/package failure');
  if (report.installedPayloadsUnchanged !== true) missing.push('successful final installed-package correspondence');
  if (report.cleanup?.closed === false) failures.push('original process cleanup failed');
  else if (report.cleanup?.closed !== true) missing.push('actual original process completion');
  if (report.initialization?.code !== 0 || !integer(report.initialization.pid) || report.initialization.pid <= 0 ||
    !integer(report.initialization.wallNs) || report.initialization.wallNs <= 0) {
    missing.push('separate successful ordinary initialization with actual child');
  }
  const returnedRun = (row, fixture, name) => {
    requireValue(typeof row.stateId === 'string' && row.stateId &&
      row.queryPath === `${row.stateId}/${name}.aql` && row.outputPath === `${row.stateId}/${name}.jsonl` &&
      row.queryFileSha256 === createHash('sha256').update(fixture.text + ';\n').digest('hex') &&
      row.querySha256 === evidenceHash(fixture.text) && row.expectedSha256 === evidenceHash(fixture.expected) &&
      row.actualSha256 === row.expectedSha256, 'Actual Native query/output identity differs');
    requireValue(row.command?.cwd === row.stateId && evidenceHash(row.command.args) === evidenceHash(
      ['run', `${name}.aql`, '--output', `${name}.jsonl`, '--json']), 'Actual Native NEW command differs');
    const response = row.publicResponse, delivery = response?.deliveries?.[0], request = delivery?.request;
    requireValue(typeof row.command.stdout === 'string' && evidenceHash(JSON.parse(row.command.stdout)) === evidenceHash(response),
      'Native returned response differs from actual command output');
    requireValue(typeof row.publicRunId === 'string' && row.publicRunId && response?.run?.run_id === row.publicRunId &&
      response.run.status === 'succeeded' && response.delivery_status === 'delivered' && response.deliveries.length === 1 &&
      delivery.status === 'delivered' && delivery.run_id === row.publicRunId && request?.path === row.outputPath &&
      request.format === 'jsonl' && typeof request.result === 'string' && request.result &&
      typeof request.result_cid === 'string' && request.result_cid, 'Original Native Run/Result delivery correspondence required');
    requireValue(row.runRefSha256 === evidenceHash({runId: row.publicRunId}) &&
      row.resultRefSha256 === evidenceHash({runId: row.publicRunId, resultName: request.result, resultCid: request.result_cid}),
    'Native returned reference differs');
    return request.result;
  };
  const first = report.firstQuery;
  if (first?.verified === false) failures.push('separate first query failed');
  else if (first?.completed !== true || first.verified !== true ||
    first.expectedSha256 !== evidenceHash([{id: 0}]) || first.actualSha256 !== first.expectedSha256) {
    missing.push('separate first query and materialized-row oracle');
  }
  if (first?.verified === true) {
    requireValue(integer(first.pid) && first.pid > 0 && first.command?.pid === first.pid && first.command.code === 0 &&
      integer(first.childWallNs) && first.childWallNs > 0 && first.command.wallNs === first.childWallNs &&
      integer(first.wallNs) && first.wallNs >= first.childWallNs &&
      first.querySha256 === evidenceHash(protocol.firstQuery.text), 'Actual separate first Native child/query required');
    returnedRun(first, protocol.firstQuery, 'first');
  }
  const series = new Map();
  for (const value of report.latency ?? []) {
    requireValue(['cold-new-run', 'cold-result'].includes(value.operation) && !series.has(value.operation), 'Unknown or duplicate Native route');
    requireValue(identities.every(key => value[key] === report[key]) && value.mode === report.mode,
      'Native route mixes original cohort/environment/protocol');
    requireValue(value.fixtureSha256 === evidenceHash(value.publicWorkload), 'Native workload identity differs');
    requireValue(value.samples.every(row => identities.every(key => row[key] === report[key])), 'Mixed Native sample identities');
    checks[value.operation] = assessLatencyTarget(value, nativeOperationTarget);
    failures.push(...checks[value.operation].failures.map(reason => `${value.operation}: ${reason}`));
    missing.push(...checks[value.operation].missing.map(reason => `${value.operation}: ${reason}`));
    series.set(value.operation, value);
  }
  const fresh = series.get('cold-new-run'), saved = series.get('cold-result');
  for (const name of ['cold-new-run', 'cold-result']) if (!series.has(name)) missing.push(`${name}: actual raw population`);
  const rows = [first, ...[...series.values()].flatMap(value => value.samples)].filter(Boolean);
  const pids = [report.initialization?.pid, ...rows.map(row => row.pid)].filter(value => value !== undefined);
  if (new Set(pids).size !== pids.length) failures.push('Native operations must use distinct actual child processes');
  if (rows.some(row => row.stateId !== first?.stateId) || typeof first?.stateId !== 'string' || !first.stateId) {
    failures.push('Native routes must retain the same actual project state');
  }
  const attempts = report.publicCallAttempts;
  if (!attempts) missing.push('actual public command attempts');
  else if (attempts.init !== 1 || attempts.run !== (first ? 1 : 0) + (fresh?.samples.length ?? 0) ||
    attempts.result !== (saved?.samples.length ?? 0)) failures.push('Native command attempts differ from observed public operations');
  const operationIds = rows.map(row => row.publicOperationId);
  if (operationIds.some(value => typeof value !== 'string' || !value) || new Set(operationIds).size !== operationIds.length) {
    failures.push('Native public-operation identity reused or missing');
  }
  const originals = [];
  const runIds = new Set(first?.publicRunId ? [first.publicRunId] : []);
  if (fresh) {
    requireValue(fresh.publicWorkload.kind === 'new-durable-run-result-file-rows' &&
      evidenceHash(fresh.publicWorkload.fixtures) === evidenceHash(protocol.queries.map(row => ({
        querySha256: evidenceHash(row.text), expectedSha256: evidenceHash(row.expected)}))), 'Native query population differs');
    for (const [index, row] of fresh.samples.entries()) {
      if (row.verified !== true) continue;
      const expected = protocol.queries[index];
      requireValue(expected, 'Native query population exceeded');
      const resultName = returnedRun(row, expected, `new-${index}`);
      requireValue(!runIds.has(row.publicRunId), 'Native new Run identity reused');
      runIds.add(row.publicRunId);
      if (originals.length < 3) originals.push({...row, resultName});
    }
  }
  if (saved) {
    requireValue(saved.publicWorkload.kind === 'saved-original-result-rows' && originals.length > 0 &&
      evidenceHash(saved.publicWorkload.originals) === evidenceHash(originals.map(row => Object.fromEntries(
        ['runRefSha256', 'resultRefSha256', 'expectedSha256'].map(key => [key, row[key]])))), 'Saved Native original population differs');
    for (const [index, row] of saved.samples.entries()) {
      if (row.verified !== true) continue;
      const original = originals[index % originals.length];
      requireValue(['runRefSha256', 'resultRefSha256', 'expectedSha256', 'publicRunId'].every(key => row[key] === original[key]) &&
        row.actualSha256 === row.expectedSha256 && row.command?.cwd === row.stateId && evidenceHash(row.command.args) === evidenceHash(
          ['result', original.publicRunId, '--result', original.resultName, '--format', 'jsonl']), 'Saved Native target or rows differ');
    }
  }
  requireValue(identities.every(key => report.functional?.[key] === report[key]), 'Native functional evidence differs');
  for (const [name, value] of series) {
    const matches = report.functional.rows?.filter(row => row.operation === name) ?? [];
    requireValue(matches.length === 1, 'Native functional population binding required');
    const row = matches[0];
    if (row.completed !== true) missing.push(`${name}: complete functional population`);
    else requireValue(row.fixtureSha256 === value.fixtureSha256 &&
      row.expectedSha256 === evidenceHash(value.samples.map(row => row.expectedSha256)) &&
      row.actualSha256 === evidenceHash(value.samples.map(row => row.actualSha256)), 'Native functional oracle differs');
    for (const sample of value.samples) {
      if (sample.verified !== true) continue;
      requireValue(sample.command?.pid === sample.pid && sample.command.code === 0 &&
        integer(sample.childWallNs) && sample.childWallNs > 0 && sample.command.wallNs === sample.childWallNs && sample.wallNs >= sample.childWallNs,
      'Actual Native child completion/boundary required');
    }
  }
  return outcome(failures, missing, {purpose: 'native-cli-latency-functional-only', sourceSha: report.sourceSha,
    cohortSha256: report.cohortSha256, target: nativeOperationTarget, checks, fullPerformanceAccepted: false,
    releaseAccepted: false, unverified: ['matched SQLite public-operation comparator', 'same-candidate permission/Unknown/recovery safety',
      'bounded history/temporary resource and structural evidence'],
    qualification: 'A passing selected latency/functional gate is not full public performance, safety, SQLite equivalence or release acceptance.'});
}

async function main(args) {
  const {readFile, writeFile, stat} = await import('node:fs/promises');
  const calibration = args[0] === '--calibrate-sqlite';
  const priority = args[0] === '--priority-transition';
  const native = args[0] === '--native-operations';
  requireValue(args.length >= 2 && args.length % 2 === 0 &&
    ['--input', '--calibrate-sqlite', '--priority-transition', '--native-operations'].includes(args[0]),
    'Usage: --input REPORT [--native-sqlite-control CONTROL --native-sqlite-protocol PROTOCOL] | --native-operations REPORT | --priority-transition COMBINED_REPORT | --calibrate-sqlite BASELINE [--result-control CONTROL] [--output JSON]');
  const options = {};
  for (let index = 2; index < args.length; index += 2) {
    const key = args[index];
    requireValue((key === '--output' || calibration && key === '--result-control' || !calibration && !priority && !native &&
      ['--native-sqlite-control', '--native-sqlite-protocol'].includes(key)) &&
      !Object.hasOwn(options, key), 'Unknown or duplicate assessment option');
    options[key] = args[index + 1];
  }
  const boundedInput = async path => {
    requireValue((await stat(path)).size <= 16 * 1024 ** 2, 'Measurement report exceeds bounded input');
    return JSON.parse(await readFile(path, 'utf8'));
  };
  const input = await boundedInput(args[1]);
  const nativeControl = options['--native-sqlite-control'], nativeProtocol = options['--native-sqlite-protocol'];
  requireValue(Boolean(nativeControl) === Boolean(nativeProtocol), 'Native control and protocol must be supplied together');
  if (nativeControl) {
    requireValue(input.comparison?.nativeSqliteDiagnostic === undefined, 'Native diagnostic already supplied');
    requireValue((await stat(nativeProtocol)).size <= 16 * 1024 ** 2, 'Native protocol exceeds bounded input');
    input.comparison = {...input.comparison, nativeSqliteDiagnostic: {
      control: await boundedInput(nativeControl), protocolText: await readFile(nativeProtocol, 'utf8')}};
  }
  const resultControl = options['--result-control'] ? await boundedInput(options['--result-control']) : undefined;
  const result = calibration ? {baseline: input, ...(resultControl ? {resultControl} : {}),
    profile: calibrateSqliteComparisonProfile(input, resultControl)}
    : priority ? assessPriorityTransition(input) : native ? assessNativeOperations(input) : assessPerformanceEvidence(input);
  const body = JSON.stringify(result, null, 2) + '\n';
  if (options['--output']) await writeFile(options['--output'], body, {flag: 'wx'});
  process.stdout.write(body);
  return calibration || result.status === 'passed' ? 0 : 1;
}
const {pathToFileURL} = await import('node:url');
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { process.exitCode = await main(process.argv.slice(2)); }
  catch (error) { console.error(String(error.message)); process.exitCode = 2; }
}
