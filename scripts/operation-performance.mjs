import {createHash} from 'node:crypto';
// Acceptance evidence only. This module grants no runtime authority and does
// not replace package provenance, the public result oracle, or resource guards.
export const operationTargets = Object.freeze({
  'warm-select': {samples: 100, comparison: 'local-sqlite'},
  'warm-result': {samples: 100, comparison: 'local-sqlite'},
  'warm-status': {samples: 100, comparison: 'local-sqlite'},
  'warm-join': {samples: 100, comparison: 'local-sqlite'},
  'warm-union': {samples: 100, comparison: 'local-sqlite'},
  'warm-decimal-sum': {samples: 100, comparison: 'local-sqlite'},
  'cold-existing': {samples: 30, p95Ms: 2000},
  'first-init': {samples: 30, p95Ms: 5000},
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

// Diagnostic calibration consumes independently measured SQLite data, never
// candidate durations. Public acceptance additionally needs a matched control
// for the existing semantic Owner's independently required durable transitions.
export const sqliteComparisonPolicy = Object.freeze({ratio: 3, minimumSamples: 100,
  noise: 'matched baseline p95 minus median', essentialTransactionsPerNewRun: 1});
const evidenceHash = value => createHash('sha256').update(JSON.stringify(value) ?? 'null').digest('hex');
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
});
function resultStorageComparison(control, baseline) {
  requireValue(control.kind === 'local-sqlite-result-control' && control.schemaVersion === 1 &&
    control.productAcceptance === false, 'Bounded Result storage control required');
  requireValue(control.cleanup?.closed === true && control.failure == null && control.profiled === false,
    'Completed successful unprofiled Result control required');
  requireValue(control.executableSha256 === baseline.executableSha256 && digest(control.collectorSha256) &&
    evidenceHash(control.environment) === evidenceHash(baseline.environment) && control.load === baseline.load &&
    evidenceHash(control.settings) === evidenceHash(baseline.settings), 'Result control runtime/environment/durability differs');
  const protocol = control.protocol, groups = ['clock', 'start', 'end'];
  requireValue(protocol?.binding === 'node:sqlite DatabaseSync' && protocol.concurrency === 1 &&
    control.protocolSha256 === evidenceHash(protocol), 'Fixed Result control protocol required');
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
  requireValue(Array.isArray(control.samples) && control.samples.length >= sqliteComparisonPolicy.minimumSamples &&
    control.warmSamples === control.samples.length, 'Sufficient complete raw Result control samples required');
  const indexes = new Set(), attempts = new Set(), pids = new Set();
  const expectedEvents = ['clock-committed', 'start-committed', 'payload-materialized', 'end-committed'];
  const expectedCounts = {begins: 3, commits: 3, rollbacks: 0, reads: 3, writes: 8};
  for (const sample of control.samples) {
    requireValue(integer(sample.index) && !indexes.has(sample.index) && integer(sample.pid) && sample.pid > 0 &&
      sample.verified === true && sample.outputSha256 === evidenceHash(protocol.expected) &&
      /^sha256:[a-f0-9]{64}$/u.test(sample.attemptCid ?? '') && !attempts.has(sample.attemptCid),
    'Distinct verified Result control observation required');
    indexes.add(sample.index); attempts.add(sample.attemptCid); pids.add(sample.pid);
    requireValue(evidenceHash(sample.events) === evidenceHash(expectedEvents) &&
      evidenceHash(sample.counts) === evidenceHash(expectedCounts), 'Result durable ordering/counts differ');
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
      payload: protocol.payload, preparation: protocol.preparation, groups, settings: control.settings},
    summary, coverage: protocol.coverage, noiseMs,
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
  requireValue(baseline.settings?.journal_mode === 'wal' && baseline.settings.synchronous === 2 &&
    typeof baseline.settings.sqliteVersion === 'string' &&
    [0, 1].includes(baseline.settings.fullfsync) && [0, 1].includes(baseline.settings.checkpoint_fullfsync),
  'Explicit WAL/FULL/fullfsync/checkpoint synchronization settings required');
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
  for (const operation of ['warm-select', 'warm-result', 'warm-status', 'warm-join', 'warm-union']) {
    const mode = ['warm-result', 'warm-status'].includes(operation) ? 'prepared' : 'one-shot';
    const value = observed(operation, mode); if (!value) continue;
    const query = comparisonQueries[operation];
    let fixtureSha256 = seedFixture;
    if (query) {
      requireValue(value.row.fixture?.sql === query.sqlite &&
        evidenceHash(value.row.fixture.expected) === evidenceHash(query.expected) &&
        JSON.stringify(value.row.fixture.parameters) === '[]', 'Unmatched SQLite query fixture');
      fixtureSha256 = evidenceHash({operation, text: query.text, expected: query.expected});
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
        materialization: 'ordinary JS records', parameters: [],
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
  const missing = storage ? ['required public work coverage outside the storage control']
    : ['matched minimum public essential-work comparator'];
  if (storage && evidenceHash(series.resultStorageMatch) !== evidenceHash(storage.conditions)) {
    missing.push('actual Result key/body/group correspondence');
  }
  if (['warm-result', 'warm-status'].includes(series.operation)) missing.push('actual saved-row/key/durability comparator correspondence');
  if (actual.environmentSha256 !== series.environmentSha256 || actual.load !== series.load) missing.push('matched comparator environment/load');
  if (series.executableSha256 !== comparison.baseline.executableSha256) missing.push('matched comparator runtime executable');
  if (evidenceHash(series.comparisonSettings) !== evidenceHash(actual.settings)) missing.push('matched stated transaction/durability settings');
  if (entry.fixtureSha256 !== series.fixtureSha256 || series.expectedSha256 !== entry.expectedSha256) missing.push('matched public fixture/oracle');
  if (evidenceHash(series.comparisonMatch) !== evidenceHash(entry.conditions)) missing.push('matched data/indexes/materialization/preparation/durability conditions');
  // These measured engine/minimum-control limits are diagnostic history. They
  // become public acceptance limits only after the existing semantic Owner's
  // required transitions have a matched measured comparator.
  return {target: {...target, diagnosticComparison: entry,
    ...(storage ? {resultStorageComparison: storage} : {})}, missing};
}

export function assessLatency(series, comparison) {
  requireValue(Object.hasOwn(operationTargets, series.operation), 'Unknown public operation');
  const calibration = calibratedLatencyTarget(series, comparison);
  const target = calibration.target;
  requireValue(digest(series.cohortSha256) && digest(series.fixtureSha256) && digest(series.environmentSha256),
    'Exact cohort, fixture and environment identities are required');
  requireValue(['diagnostic', 'final'].includes(series.mode) && Array.isArray(series.samples), 'Invalid measurement mode');
  const failures = [], missing = [...calibration.missing];
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
  const summary = latencySummary(successful, target.samples);
  if (series.mode !== 'final') missing.push('diagnostic only');
  if (series.profiled !== false) missing.push('uninstrumented latency samples');
  if (series.load !== 'isolated') missing.push('controlled isolated measurement');
  if (series.stoppedEarly) missing.push('measurement stopped early');
  if (summary.count < target.samples) missing.push(`${target.samples} successful raw samples`);
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
  return outcome(failures, missing, {operation: series.operation, target, summary, diagnosticComparison, resultStorage});
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
  const failures = [], missing = [], sizes = new Set();
  let control;
  for (const row of rows) {
    requireValue(historySizes.includes(row.size) && !sizes.has(row.size), 'Duplicate or unsupported history selection');
    sizes.add(row.size);
    if (row.supported !== true) { missing.push(`history ${row.size}: ${row.reason || 'not supported'}`); continue; }
    requireValue(digest(row.fixtureSha256), 'History fixture identity required');
    if (!control) control = row;
    if (row.fixtureSha256 !== control.fixtureSha256) failures.push('history target fixture changed');
    for (const key of ['targetRowsRead', 'databaseReads', 'sqlPrepares', 'materialGetterCalls', 'materialCacheHits',
      'fullPhysicalValidations', 'fullCurrentValidations', 'fullRowAdmissions', 'decodeCalls', 'fullParses',
      'fullMacValidations', 'fullHashValidations', 'fullScopeDigests', 'fullConfigurationInventories', 'fullAccountEvaluations']) {
      if (!integer(row[key])) missing.push(`history ${row.size}: ${key}`);
      else if (row[key] !== control[key]) failures.push(`history ${row.size}: target ${key} changed with unrelated history`);
    }
    for (const key of ['unrelatedRunRows', 'unrelatedEffectRows']) {
      if (!integer(row[key])) missing.push(`history ${row.size}: ${key}`);
      else if (row[key] !== 0) failures.push(`history ${row.size}: ${key} is not zero`);
    }
  }
  for (const size of historySizes) if (!sizes.has(size)) missing.push(`history ${size}`);
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
  const failures = [], missing = [], seen = new Set();
  for (const row of rows) {
    requireValue(Object.hasOwn(boundaryExpectations, row.case) && !seen.has(row.case), 'Duplicate or unknown boundary case');
    seen.add(row.case);
    for (const [key, expected] of Object.entries(boundaryExpectations[row.case])) {
      if (!Object.hasOwn(row, key)) missing.push(`${row.case}: ${key}`);
      else if (row[key] !== expected) failures.push(`${row.case}: ${key}`);
    }
  }
  for (const name of Object.keys(boundaryExpectations)) if (!seen.has(name)) missing.push(name);
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
    const wallNs = Number(now() - start), afterCpu = cpu();
    const row = {...identity, iteration, stateId, pid, wallNs,
      cpuUserUs: afterCpu.user - beforeCpu.user, cpuSystemUs: afterCpu.system - beforeCpu.system,
      cpuScope: 'collector-process-only', completed: verified, verified, ...(error ? {error} : {})};
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
    qualification: 'Assesses supplied measurements; does not authenticate their provenance or establish full product completion.'});
}

export function assessFunctions(rows) {
  const failures = [], missing = [], seen = new Set();
  for (const row of rows) {
    requireValue(Object.hasOwn(operationTargets, row.operation) && !seen.has(row.operation), 'Duplicate or unknown functional case');
    seen.add(row.operation);
    if (row.completed !== true) failures.push(`${row.operation}: public operation did not complete`);
    if (!digest(row.expectedSha256) || !digest(row.actualSha256)) missing.push(`${row.operation}: independent result oracle`);
    else if (row.expectedSha256 !== row.actualSha256) failures.push(`${row.operation}: result oracle mismatch`);
  }
  for (const operation of Object.keys(operationTargets)) if (!seen.has(operation)) missing.push(operation);
  return outcome(failures, missing);
}

async function main(args) {
  const {readFile, writeFile, stat} = await import('node:fs/promises');
  const calibration = args[0] === '--calibrate-sqlite';
  requireValue(args.length >= 2 && args.length % 2 === 0 &&
    ['--input', '--calibrate-sqlite'].includes(args[0]),
    'Usage: --input REPORT | --calibrate-sqlite BASELINE [--result-control CONTROL] [--output JSON]');
  const options = {};
  for (let index = 2; index < args.length; index += 2) {
    const key = args[index];
    requireValue((key === '--output' || calibration && key === '--result-control') &&
      !Object.hasOwn(options, key), 'Unknown or duplicate assessment option');
    options[key] = args[index + 1];
  }
  const boundedInput = async path => {
    requireValue((await stat(path)).size <= 16 * 1024 ** 2, 'Measurement report exceeds bounded input');
    return JSON.parse(await readFile(path, 'utf8'));
  };
  const input = await boundedInput(args[1]);
  const resultControl = options['--result-control'] ? await boundedInput(options['--result-control']) : undefined;
  const result = calibration ? {baseline: input, ...(resultControl ? {resultControl} : {}),
    profile: calibrateSqliteComparisonProfile(input, resultControl)}
    : assessPerformanceEvidence(input);
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
