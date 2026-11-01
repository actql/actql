// Run only against a separately prepared, source-qualified ordinary installation.
// No preload, package preparation, product overlay, internal Host port or resend.
import assert from 'node:assert/strict';
import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {appendFile, lstat, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {arch, platform, release, cpus, totalmem} from 'node:os';
import {dirname, join, relative, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {assessLatency, calibratedLatencyTarget, collectOperationSamples,
  assessPriorityTransition, priorityTransitionTarget} from './operation-performance.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');

// Keep failure inspection outside successful sample timing. Read only bounded
// public data: never call execution/status/result/cleanup methods to diagnose it.
export function nodeBenchmarkFailure(error) {
  const data = (value, key) => {
    try {
      for (let depth = 0; value !== null && typeof value === 'object' && depth < 4;
        depth++, value = Object.getPrototypeOf(value)) {
        const property = Object.getOwnPropertyDescriptor(value, key);
        if (property) return Object.hasOwn(property, 'value') ? property.value : undefined;
      }
    } catch { /* An unreadable diagnostic must not replace the original failure. */ }
  };
  const text = value => typeof value === 'string' ? value.slice(0, 2048) : undefined;
  const reference = value => {
    const result = {};
    for (const key of ['namespaceId', 'authorityScopeCid', 'runDefinitionCid']) {
      const field = text(data(value, key)); if (field !== undefined) result[key] = field;
    }
    return Object.keys(result).length ? result : undefined;
  };
  const queue = [{edge: 'primary', value: error}], seen = new Set(), chain = [];
  while (queue.length && chain.length < 8) {
    const {edge, value} = queue.shift();
    if (value === null || typeof value !== 'object' || seen.has(value)) continue;
    seen.add(value);
    const entry = {edge, name: text(data(value, 'name')) ?? 'Error',
      code: text(data(value, 'code')) ?? null, message: text(data(value, 'message')) ?? ''};
    const status = data(value, 'status'), requestId = text(data(value, 'requestId'));
    if (Number.isSafeInteger(status)) entry.status = status;
    if (requestId !== undefined) entry.requestId = requestId;
    const cleanupPending = data(value, 'cleanupPending');
    if (typeof cleanupPending === 'boolean') entry.cleanupPending = cleanupPending;
    const executionRef = reference(data(value, 'executionRef')) ?? reference(data(data(value, 'execution'), 'ref'));
    if (executionRef) entry.executionRef = executionRef;
    const observation = data(value, 'observation'), state = {};
    for (const key of ['run_id', 'status', 'revision', 'result_available']) {
      const field = data(observation, key);
      if (typeof field === 'string') state[key] = text(field);
      else if (typeof field === 'boolean' || Number.isSafeInteger(field)) state[key] = field;
    }
    if (Object.keys(state).length) entry.observation = state;
    chain.push(entry);
    for (const key of ['cause', 'original_error', 'cleanup_error', 'originalError', 'cleanupError']) {
      const child = data(value, key);
      if (child !== null && typeof child === 'object') queue.push({edge: key, value: child});
    }
  }
  const primary = chain[0] ?? {name: 'Error', code: null,
    message: typeof error === 'string' ? text(error) : 'Uninspectable thrown value'};
  return {...primary, errorChain: chain, ...(queue.length ? {errorChainTruncated: true} : {})};
}
// Independent literal oracles: JOIN selects the matching id and label; UNION
// retains both ordered ids; Decimal SUM is (125 + 250 + 25) / 100 = "4.00".
// No expected value is obtained from a compiler or a previous product result.
export const nodeWarmSmallQueryFixtures = Object.freeze([
  {operation: 'warm-join',
    text: "WITH lhs AS (SELECT 1 AS id), rhs AS (SELECT 1 AS id, 'joined' AS label) "
      + 'SELECT lhs.id AS id, rhs.label AS label FROM lhs JOIN rhs ON lhs.id = rhs.id MAX_OUTPUT_ROWS 1',
    expected: [{id: 1, label: 'joined'}]},
  {operation: 'warm-union',
    text: 'WITH items AS (SELECT 2 AS id UNION ALL SELECT 1 AS id) '
      + 'SELECT id FROM items |> ASSERT UNIQUE BY (id) |> ORDER BY id',
    expected: [{id: 1}, {id: 2}]},
  {operation: 'warm-decimal-sum',
    text: "WITH items AS (SELECT CAST('1.25' AS DECIMAL(8,2)) AS amount "
      + "UNION ALL SELECT CAST('2.50' AS DECIMAL(8,2)) AS amount "
      + "UNION ALL SELECT CAST('0.25' AS DECIMAL(8,2)) AS amount) "
      + 'SELECT SUM(amount) AS total FROM items',
    expected: [{total: '4.00'}]},
  {operation: 'warm-parameters', text: 'SELECT @id AS id',
    options: Object.freeze({parameters: Object.freeze({id: 7}),
      parameterDeclarations: Object.freeze({id: Object.freeze({type: 'number'})})}), expected: [{id: 7}]},
  {operation: 'warm-unicode', text: "SELECT 'é😀' AS label", expected: [{label: 'é😀'}]},
].map(fixture => Object.freeze({...fixture,
  expected: Object.freeze(fixture.expected.map(row => Object.freeze(row)))})));
export function nodeBenchmarkInstrumentation({execArgv = process.execArgv,
  nodeOptions = process.env.NODE_OPTIONS ?? '', coverage = process.env.NODE_V8_COVERAGE} = {}) {
  // Known startup instrumentation is evidence against unprofiled acceptance.
  // This is not whole-runtime provenance or hostile embedding detection.
  const flags = [...execArgv, nodeOptions].join(' ');
  return {profiled: /--(?:cpu-prof|heap-prof|prof|inspect|perf-basic-prof|trace-events-enabled|trace-event-categories)(?:[=\s-]|$)/u.test(flags) || Boolean(coverage)};
}
export function nodeWarmProtocol(mode) {
  assert(['diagnostic', 'final'].includes(mode));
  return {entry: 'ordinary open/stateDir', mode, priorState: 'new empty directory',
    seed: {source: 'SELECT 1 AS id', format: 'sql', expected: [{id: 1}], successfulRuns: 1},
    operationOrder: ['warm-select', 'warm-result', 'warm-status', ...nodeWarmSmallQueryFixtures.map(row => row.operation)],
    smallQueries: nodeWarmSmallQueryFixtures, samplesPerOperation: mode === 'final' ? 100 : 3,
    diagnosticContinuation: mode === 'diagnostic' ? 'verified success only; stop each slow family' : 'none',
    newShortQueries: 'one per SELECT/JOIN/UNION/Decimal SUM/Parameters/Unicode sample', savedReads: 'same original seed Run',
    status: 'same original revision after initial status observation', close: 'await original Client in finally'};
}
// One explicit experiment definition lets warm and process measurements share
// the assessor's cohort/environment/history binding without accepting arbitrary
// successful reports from different histories. Warm-only callers stay valid.
export function nodeOperationProtocol(mode) {
  return {warm: nodeWarmProtocol(mode), process: {
    samplesPerOperation: mode === 'final' ? 30 : 3,
    coldExisting: 'same candidate publicly initializes and closes state in a seed process; each distinct timed child submits a distinct NEW query/Run and materializes all rows, never Saved-only',
    firstInit: 'distinct empty state and actual child per SELECT/Result/awaited close',
    wall: 'parent launch to actual all-rows IPC notification separately from parent launch through natural child exit, including import/open/new-query/all-rows/first-close; child public spans nested, never added to parent totals',
    cpu: 'actual child process; separate workers and subprocesses excluded',
    failedOrUnknown: 'retain sample and stop; never replay the failed Run',
  }, boundaries: {usedMaterial: nodeUsedMaterialProtocol()}};
}
export function nodeUsedMaterialProtocol() {
  return {case: 'used-row-tamper', state: 'distinct empty directory',
    seed: {source: 'SELECT 1 AS id', format: 'sql', result: 'main', expected: [{id: 1}]},
    selection: 'original Run index -> single durable binding -> selected material generation',
    mutation: 'one same-size byte change, preserving the original generation bytes',
    observation: 'one later public Result.all must reject; no retry or restoration',
    close: 'await the original Client; cleanup failure cannot qualify the boundary'};
}
export async function verifyNodeBenchmarkPackages(manifest, manifestPath, consumer) {
  assert(Array.isArray(manifest.packages) && manifest.packages.length > 0);
  assert(manifest.packages.some(row => row.name === '@actql/node'));
  const observations = [], names = new Set();
  for (const pkg of manifest.packages) {
    assert(/^(?:@actql\/)?[a-z0-9-]+$/u.test(pkg.name) && !names.has(pkg.name));
    names.add(pkg.name);
    assert.equal(pkg.file, pkg.file.split('/').at(-1));
    const tar = await readFile(join(dirname(manifestPath), pkg.file));
    assert.equal(tar.length, pkg.bytes); assert.equal(hash(tar), pkg.sha256);
    assert.equal('sha512-' + createHash('sha512').update(tar).digest('base64'), pkg.integrity);
    const base = join(consumer, 'node_modules', pkg.name), files = [];
    async function visit(dir) {
      assert(!(await lstat(dir)).isSymbolicLink(), 'Installed package cannot be a source symlink');
      for (const name of (await readdir(dir)).sort()) {
        const file = join(dir, name), st = await lstat(file);
        assert(!st.isSymbolicLink(), 'Installed product payload cannot be linked');
        if (st.isDirectory()) await visit(file);
        else {
          assert(st.isFile()); const data = await readFile(file);
          files.push({path: relative(base, file), bytes: data.length, mode: st.mode & 0o777, sha256: hash(data)});
        }
      }
    }
    await visit(base);
    const sort = rows => rows.toSorted((a, b) => a.path.localeCompare(b.path));
    assert.deepEqual(sort(files), sort(pkg.files));
    observations.push({package: pkg.name, files});
  }
  return observations;
}
export async function runNodeWarmBenchmark({manifestPath, consumer, output, controlsPath, mode = 'diagnostic'}) {
  assert(['diagnostic', 'final'].includes(mode));
  consumer = resolve(consumer); output = resolve(output);
  const manifestBytes = await readFile(manifestPath), manifest = JSON.parse(manifestBytes);
  const controls = JSON.parse(await readFile(controlsPath));
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  assert.equal(controls.sourceSha, manifest.sourceSha);
  assert.equal(controls.cohortSha256, hash(manifestBytes));
  const actualEnvironment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  for (const [key, value] of Object.entries(actualEnvironment)) assert.equal(controls.environment[key], value, key);
  const combined = nodeOperationProtocol(mode);
  const protocol = controls.historyProtocolSha256 === hash(Buffer.from(JSON.stringify(combined)))
    ? combined : nodeWarmProtocol(mode);
  assert.equal(controls.historyProtocolSha256, hash(Buffer.from(JSON.stringify(protocol))));
  assert(['isolated', 'concurrent'].includes(controls.load));
  const executableSha256 = hash(await readFile(process.execPath));
  const comparisonSeries = (operation, expected) => {
    const query = nodeWarmSmallQueryFixtures.find(row => row.operation === operation);
    return {operation, environmentSha256: hash(Buffer.from(JSON.stringify(actualEnvironment))),
      executableSha256, load: controls.load,
      fixtureSha256: query ? hash(Buffer.from(JSON.stringify(query))) : hash(Buffer.from('SELECT 1 AS id\n[{"id":1}]\n')),
      ...(expected === undefined ? {} : {expectedSha256: hash(Buffer.from(JSON.stringify(expected)))}),
      // These are independently stated workload/settings facts from the fixed
      // experiment, never copied from the profile's expected conditions.
      comparisonMatch: controls.comparisonMatches?.[operation], comparisonSettings: controls.comparisonSettings,
      resultStorageMatch: controls.resultStorageMatches?.[operation]};
  };
  if (mode === 'final') {
    const missing = nodeWarmProtocol(mode).operationOrder.flatMap(operation => {
      const query = nodeWarmSmallQueryFixtures.find(row => row.operation === operation);
      const expected = query?.expected ?? (operation === 'warm-status' ? undefined : [{id: 1}]);
      return calibratedLatencyTarget(comparisonSeries(operation, expected), controls.comparison)
        .missing.map(reason => `${operation}: ${reason}`);
    });
    assert.equal(missing.length, 0, `Final comparison profile incomplete before public open: ${missing.join('; ')}`);
  }
  const before = await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer);
  await mkdir(output, {mode: 0o700}); // An existing benchmark directory is never reused.
  const stateId = join(output, 'new-state'), hostId = randomUUID();
  const identity = {cohortSha256: hash(manifestBytes),
    fixtureSha256: hash(Buffer.from('SELECT 1 AS id\n[{"id":1}]\n')), hostId};
  const environmentSha256 = hash(Buffer.from(JSON.stringify(controls.environment)));
  const report = {sourceSha: manifest.sourceSha, cohortSha256: identity.cohortSha256, environmentSha256,
    historyProtocolSha256: controls.historyProtocolSha256, mode, ordinaryPackageManifest: manifestPath,
    observedEnvironment: actualEnvironment,
    ...(controls.comparison ? {comparison: controls.comparison} : {}),
    historyProtocol: protocol,
    load: controls.load, latency: [], diagnosticFindings: [], functional: {cohortSha256: identity.cohortSha256,
      environmentSha256, historyProtocolSha256: controls.historyProtocolSha256, rows: []}, cleanup: {closed: false},
    qualification: 'Selected warm public operations only. Other latency, structural, history, chunk and fault gates remain unmeasured.'};
  const save = () => writeFile(join(output, 'measurements.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  let client, original, primary, active = 'ordinary public open and initial Result';
  const initial = process.hrtime.bigint();
  try {
    const {open} = await import(pathToFileURL(join(consumer, 'node_modules/@actql/node/index.mjs')).href);
    client = await open({stateDir: stateId});
    original = await client.startSource('SELECT 1 AS id', {format: 'sql', requestId: 'benchmark-original'});
    assert.equal((await original.wait()).status, 'succeeded');
    assert.deepEqual(await original.result('main').all(), [{id: 1}]);
    report.originalRun = original.ref;
    report.initialOpenAndResultNs = Number(process.hrtime.bigint() - initial);
    // This observation lacks close, so it is not a first-init percentile.
    // Diagnostic mode may still locate the separate saved-Result/status cost
    // after a slow SUCCESS. It never repeats an unknown or failed submission.
    report.initialLatencyExceeded = report.initialOpenAndResultNs > 200e6;
    if (report.initialLatencyExceeded) report.diagnosticFindings.push('initial operation exceeded 200ms; separate close/process evidence still required');
    if (report.initialLatencyExceeded && mode === 'final') report.stoppedAt = 'initial operation exceeded 200ms; final sampling not started';
    else {
      const baseline = await original.status();
      for (const operation of nodeWarmProtocol(mode).operationOrder) {
        active = operation;
        const query = nodeWarmSmallQueryFixtures.find(row => row.operation === operation);
        const expected = query?.expected ?? (operation === 'warm-status'
          ? {status: 'succeeded', revision: baseline.revision} : [{id: 1}]);
        const sampleIdentity = query ? {...identity,
          fixtureSha256: hash(Buffer.from(JSON.stringify(query)))} : identity;
        const comparison = comparisonSeries(operation, expected);
        const calibration = calibratedLatencyTarget(comparison, controls.comparison);
        let observed, observedFailure;
        const execute = async () => {
          try {
            if (query || operation === 'warm-select') {
              observed = await client.sql(query?.text ?? 'SELECT 1 AS id', query?.options).all();
              assert.deepEqual(observed, expected);
            } else if (operation === 'warm-result') {
              observed = await original.result('main').all(); assert.deepEqual(observed, expected);
            } else {
              const state = await original.status();
              observed = {status: state.status, revision: state.revision}; assert.deepEqual(observed, expected);
            }
          } catch (error) { observedFailure = error; throw error; }
        };
        const collected = await collectOperationSamples({operation, mode, identity: sampleIdentity, stateId, execute,
          ...(calibration.missing.length ? {} : {targetP95Ms: calibration.target.p95Ms}),
          emit: row => appendFile(join(output, 'samples.jsonl'), JSON.stringify({operation, ...row}) + '\n', {mode: 0o600})});
        const series = {...comparison, operation, mode, ...sampleIdentity, ...(query ? {query} : {}), environmentSha256,
          historyProtocolSha256: controls.historyProtocolSha256, ...nodeBenchmarkInstrumentation(), load: controls.load, ...collected};
        report.latency.push(series);
        report.functional.rows.push({operation, completed: collected.samples.every(row => row.verified),
          expectedSha256: hash(Buffer.from(JSON.stringify(expected))),
          ...(observed === undefined ? {} : {actualSha256: hash(Buffer.from(JSON.stringify(observed)))})});
        await save();
        if (collected.stoppedEarly) {
          const failed = collected.samples.find(row => row.verified !== true);
          if (failed) {
            report.firstFailure = {operation, ...nodeBenchmarkFailure(observedFailure)}; report.stoppedAt = operation; break;
          }
          report.diagnosticFindings.push(`${operation}: ${collected.stopReason}`);
          if (mode !== 'diagnostic') { report.stoppedAt = operation; break; }
        }
      }
    }
  } catch (error) {
    primary = error;
    report.firstFailure = {operation: active, ...nodeBenchmarkFailure(error)};
  } finally {
    if (client) {
      const closeStart = process.hrtime.bigint();
      try { await client.close(); report.cleanup.closed = true; }
      catch (error) { primary ??= error; report.cleanup.failure = nodeBenchmarkFailure(error); }
      report.cleanup.wallNs = Number(process.hrtime.bigint() - closeStart);
    }
    try { assert.deepEqual(await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer), before); report.installedPayloadsUnchanged = true; }
    catch (error) { primary ??= error; report.packageFailure = error.message; }
    report.assessments = report.latency.map(row => assessLatency(row, controls.comparison));
    report.fullAcceptance = false;
    await save();
  }
  if (primary) throw primary;
  return report;
}

// This is a smaller selection of the same ordinary public route, not a
// replacement for full performance acceptance or its SQLite comparison.
const managedRunScalarFields = Object.freeze([
  ...['planning_work', 'attempts', 'holdings', 'transfer_bytes', 'retained_bytes', 'execution_bytes']
    .map(key => `actql.resource.limit.${key}`),
  ...['planning', 'attempts', 'holdings', 'transferred', 'uncertain', 'reserved_transfer',
    'held_bytes', 'reserved_retention', 'reserved_execution', 'peak_retention']
    .map(key => `actql.resource.usage.${key}`),
]);
export function nodeManagedRunObservation(record) {
  assert.equal(record.version, 'actql-observation/0.1');
  assert.equal(record.operation, 'compute');
  assert.equal(record.event, 'resources_observed');
  assert.equal(record.attributes?.['actql.resource.scope'], 'managed-run-ledger');
  assert(Number.isSafeInteger(record.sequence) && record.sequence >= 0);
  assert.match(record.parent?.traceId ?? '', /^[a-f0-9]{32}$/u);
  assert.match(record.parent?.spanId ?? '', /^[a-f0-9]{16}$/u);
  const runDefinitionCid = record.attributes['actql.run.definition_cid'];
  assert.match(runDefinitionCid ?? '', /^sha256:[a-f0-9]{64}$/u);
  const scalars = Object.fromEntries(Object.entries(record.attributes)
    .filter(([key]) => /^actql\.resource\.(?:limit|usage)\./u.test(key)));
  assert.deepEqual(Object.keys(scalars).sort(), [...managedRunScalarFields].sort());
  for (const value of Object.values(scalars)) {
    assert.equal(typeof value, 'string'); assert.match(value, /^(?:0|[1-9][0-9]*)$/u);
    assert(BigInt(value) <= 9223372036854775807n);
  }
  return {version: record.version, operation: record.operation, event: record.event,
    sequence: record.sequence, traceId: record.parent.traceId,
    spanId: record.parent.spanId, runDefinitionCid, scalars};
}
export function nodeSelectedRowObservation(record) {
  assert.equal(record.version, 'actql-observation/0.1');
  assert.equal(record.operation, 'run');
  assert.equal(record.event, 'selected_rows_observed');
  assert(Number.isSafeInteger(record.sequence) && record.sequence >= 0);
  assert.match(record.parent?.traceId ?? '', /^[a-f0-9]{32}$/u);
  assert.match(record.parent?.spanId ?? '', /^[a-f0-9]{16}$/u);
  const a = record.attributes;
  assert.equal(a?.['actql.rows.owner'], 'request-journal');
  assert(['run-definition', 'request', 'mixed-selected'].includes(a['actql.rows.selection']));
  assert.equal(a['actql.rows.kind'], 'run');
  assert.equal(a['actql.rows.coverage'], 'selected-returned');
  const returned = a['actql.rows.returned'], unrelated = a['actql.rows.unrelated'];
  assert(Number.isSafeInteger(returned) && returned >= 0);
  if (unrelated !== undefined) assert(Number.isSafeInteger(unrelated) && unrelated >= 0 && unrelated <= returned);
  const runDefinitionCid = a['actql.run.definition_cid'];
  if (runDefinitionCid !== undefined) assert.match(runDefinitionCid, /^sha256:[a-f0-9]{64}$/u);
  return {version: record.version, operation: record.operation, event: record.event,
    sequence: record.sequence, traceId: record.parent.traceId, spanId: record.parent.spanId,
    owner: a['actql.rows.owner'], selection: a['actql.rows.selection'], kind: 'run',
    coverage: 'selected-returned', returned,
    ...(unrelated === undefined ? {} : {unrelated}),
    ...(runDefinitionCid === undefined ? {} : {runDefinitionCid})};
}
export function nodePriorityProtocol(mode, resourceObservations, rowObservations) {
  assert(['diagnostic', 'final'].includes(mode));
  assert(resourceObservations === undefined || resourceObservations === 'managed-run-ledger');
  assert(rowObservations === undefined || rowObservations === 'selected-returned');
  return {selection: 'priority-transition', mode, entry: 'ordinary open/stateDir',
    ...(resourceObservations ? {resourceObservations: {
      scope: resourceObservations, selection: 'compute/resources',
      binding: 'one trace/span per public operation and exact original Run',
      timing: 'resource observation enabled; not a whole-Host temporary population',
    }} : {}),
    ...(rowObservations ? {rowObservations: {
      scope: rowObservations, selection: 'run/rows',
      binding: 'actual trace/span per public operation; original Run correspondence when available',
      timing: 'selected row observation enabled; compare only the same selected protocol',
      coverage: 'partial selected returned Run rows; not all reads, unrelated history or a temporary population',
    }} : {}),
    state: 'new empty directory', firstQuery: {text: 'SELECT 0 AS id', expected: [{id: 0}]},
    queries: Array.from({length: mode === 'final' ? priorityTransitionTarget.samples : 3}, (_, index) =>
      ({text: `SELECT ${index + 1} AS id`, expected: [{id: index + 1}]})),
    samplesPerOperation: mode === 'final' ? priorityTransitionTarget.samples : 3,
    savedOriginals: 'first three successful new-query Results, read cyclically without resubmission',
    order: ['first-query-separate', 'warm-select', 'warm-result'],
    queryIdentity: 'SHA256 of JSON-encoded exact query string',
    timing: 'public construction/all plus public original-reference capture and independent row oracle',
    close: 'await the original Client once; no retry of failed or Unknown operations',
    missing: 'scan/temporary/safety observations are not synthesized from timings or configuration'};
}

export async function runNodePriorityBenchmark({manifestPath, consumer, output, controlsPath,
  mode = 'diagnostic', resourceObservations, rowObservations}) {
  const protocol = nodePriorityProtocol(mode, resourceObservations, rowObservations);
  consumer = resolve(consumer); output = resolve(output);
  const identify = value => hash(Buffer.from(JSON.stringify(value)));
  const bytes = await readFile(manifestPath), manifest = JSON.parse(bytes);
  const controls = JSON.parse(await readFile(controlsPath));
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  assert.equal(controls.sourceSha, manifest.sourceSha);
  assert.equal(controls.cohortSha256, hash(bytes));
  const environment = {platform: platform(), arch: arch(), osRelease: release(), node: process.version,
    cpuModel: cpus()[0].model, logicalCpus: cpus().length, memoryBytes: totalmem()};
  assert.deepEqual(controls.environment, environment);
  assert(['isolated', 'concurrent'].includes(controls.load));
  assert.equal(controls.historyProtocolSha256, identify(protocol));
  const before = await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer);
  await mkdir(output, {mode: 0o700});
  const stateId = join(output, 'new-state'), hostId = randomUUID();
  const binding = {cohortSha256: hash(bytes), environmentSha256: identify(environment),
    historyProtocolSha256: controls.historyProtocolSha256};
  const report = {sourceSha: manifest.sourceSha, ...binding, executionPath: 'node-sdk',
    selection: 'priority-transition', mode, historyProtocol: protocol, observedEnvironment: environment,
    ordinaryPackageManifest: resolve(manifestPath), load: controls.load, latency: [],
    functional: {...binding, rows: []}, cleanup: {closed: false}, publicCallAttempts: {sql: 0, savedResultAll: 0},
    priorityConditions: {},
    qualification: 'Raw Node checkpoint selection only. Missing actual population/safety observations remain incomplete; no full acceptance or comparator claim.'};
  // Explicit experiment facts stay explicit. A successful package check cannot
  // invent quiet-machine, unchanged-guarantee or managed-resource observations.
  for (const key of ['noCompetingLargeBuild', 'guaranteesUnchanged']) {
    if (typeof controls.priorityConditions?.[key] === 'boolean') report.priorityConditions[key] = controls.priorityConditions[key];
  }
  const save = () => writeFile(join(output, 'measurements.json'), JSON.stringify(report, null, 2) + '\n', {mode: 0o600});
  const originals = [], newRuns = new Set(), newResults = new Set();
  let client, observation, active = 'ordinary public open', observedFailure, context;
  const observedOperations = [], resourceRecords = [], rowRecords = [], resourceFailures = [];
  const resourceLimit = 1 + 2 * protocol.samplesPerOperation;
  const capture = (row, runRef, action) => {
    if (!resourceObservations && !rowObservations) return action();
    const selected = {publicOperationId: row.publicOperationId,
      traceId: randomBytes(16).toString('hex'), spanId: randomBytes(8).toString('hex')};
    observedOperations.push(selected); context = {traceId: selected.traceId, spanId: selected.spanId, traceFlags: 1};
    return (async () => {
      try {
        const result = await action();
        const ref = runRef ?? result.runRef;
        selected.runDefinitionCid = ref.runDefinitionCid; selected.runRefSha256 = identify(ref);
        selected.completed = true; return result;
      } finally {context = undefined;}
    })();
  };
  const attemptIdentity = fixture => ({publicOperationId: randomUUID(),
    querySha256: identify(fixture.text), expectedSha256: identify(fixture.expected)});
  const query = (fixture, row) => capture(row, undefined, async () => {
    report.publicCallAttempts.sql++;
    const pending = client.sql(fixture.text), rows = await pending.all();
    row.actualSha256 = identify(rows);
    // Await the same ResultPromise for its public original; never submit again.
    const selected = await pending;
    assert.equal(selected.ref.resultName, 'main');
    assert.deepEqual(selected.ref.run, selected.execution.ref);
    row.runRefSha256 = identify(selected.execution.ref); row.resultRefSha256 = identify(selected.ref);
    assert.deepEqual(rows, fixture.expected);
    assert(!newRuns.has(row.runRefSha256) && !newResults.has(row.resultRefSha256),
      'New query reused an original Run or Result');
    newRuns.add(row.runRefSha256); newResults.add(row.resultRefSha256);
    return {execution: selected.execution, runRef: selected.execution.ref,
      resultRef: selected.ref, expected: fixture.expected, expectedSha256: row.expectedSha256,
      runRefSha256: row.runRefSha256, resultRefSha256: row.resultRefSha256};
  });
  try {
    const openStart = process.hrtime.bigint(), openCpu = process.cpuUsage();
    if (resourceObservations || rowObservations) {
      const file = 'adapters/host-common/observation.mjs';
      assert(manifest.packages.some(pkg => pkg.name === '@actql/local-node' &&
        pkg.files.some(row => row.path === file)), 'Verified installed observation module required');
      const {createHostObservationConnection} = await import(pathToFileURL(
        join(consumer, 'node_modules/@actql/local-node', file)).href);
      observation = createHostObservationConnection({
        include: [...(resourceObservations ? ['compute'] : []), ...(rowObservations ? ['run'] : [])],
        measurements: {include: [...(resourceObservations ? ['resources'] : []), ...(rowObservations ? ['rows'] : [])]},
        ...(rowObservations ? {events: {level: 'diagnostic'}} : {}),
        currentContext: () => context, deliver: record => {
          try {
            if (resourceObservations && record.event === 'resources_observed') {
              assert(resourceRecords.length < resourceLimit, 'Resource observation buffer overflow');
              resourceRecords.push(nodeManagedRunObservation(record));
            }
            if (rowObservations && record.event === 'selected_rows_observed') {
              assert(rowRecords.length < 4096, 'Selected row observation buffer overflow');
              rowRecords.push(nodeSelectedRowObservation(record));
            }
          } catch (error) {
            if (resourceFailures.length < 16) resourceFailures.push(nodeBenchmarkFailure(error));
          }
        }});
    }
    const {open} = await import(pathToFileURL(join(consumer, 'node_modules/@actql/node/index.mjs')).href);
    client = await open({stateDir: stateId, ...(observation ? {installation: {observation}} : {})});
    report.moduleImportAndOpen = {wallNs: Number(process.hrtime.bigint() - openStart),
      ...process.cpuUsage(openCpu), cpuScope: 'collector-process-only'};
    assert.equal(client.info.stateDir, stateId);
    report.priorityConditions.startedHost = true;
    active = 'first-query-separate';
    const first = {...binding, ...attemptIdentity(protocol.firstQuery), pid: process.pid, hostId, stateId,
      completed: false, verified: false, cpuScope: 'collector-process-only'};
    const start = process.hrtime.bigint(), cpu = process.cpuUsage();
    try { await query(protocol.firstQuery, first); first.completed = first.verified = true; }
    finally {
      const used = process.cpuUsage(cpu);
      Object.assign(first, {wallNs: Number(process.hrtime.bigint() - start), cpuUserUs: used.user, cpuSystemUs: used.system});
      report.firstQuery = first;
    }
    for (const operation of ['warm-select', 'warm-result']) {
      active = operation;
      const fresh = operation === 'warm-select';
      const publicWorkload = fresh ? {kind: 'new-durable-run-result-rows', fixtures: protocol.queries.map(fixture =>
        ({querySha256: identify(fixture.text), expectedSha256: identify(fixture.expected)}))}
        : {kind: 'saved-original-result-rows', originals: originals.map(({runRefSha256, resultRefSha256, expectedSha256}) =>
          ({runRefSha256, resultRefSha256, expectedSha256}))};
      const identity = {...binding, hostId, fixtureSha256: identify(publicWorkload)};
      const execute = async iteration => {
        // A failed new attempt must not inherit the previous successful Run's
        // identities merely because the sampler uses the same private object.
        for (const key of ['runRefSha256', 'resultRefSha256', 'actualSha256']) delete identity[key];
        if (!fresh) identity.publicOperationId = randomUUID();
        try {
          if (fresh) {
            const fixture = protocol.queries[iteration]; Object.assign(identity, attemptIdentity(fixture));
            const original = await query(fixture, identity);
            if (originals.length < 3) originals.push(original);
          } else {
            assert(originals.length > 0, 'No successful original Result to read');
            const original = originals[iteration % originals.length];
            Object.assign(identity, {runRefSha256: original.runRefSha256,
              resultRefSha256: original.resultRefSha256, expectedSha256: original.expectedSha256});
            report.publicCallAttempts.savedResultAll++;
            await capture(identity, original.runRef, async () => {
              const rows = await original.execution.result('main').all(); identity.actualSha256 = identify(rows);
              assert.deepEqual(rows, original.expected);
            });
          }
        } catch (error) {observedFailure = error; throw error;}
      };
      const collected = await collectOperationSamples({operation, mode, identity, stateId, execute,
        targetP95Ms: priorityTransitionTarget.p95Ms,
        emit: row => appendFile(join(output, 'samples.jsonl'), JSON.stringify({operation, ...row}) + '\n', {mode: 0o600})});
      const series = {...binding, operation, mode, hostId, fixtureSha256: identify(publicWorkload), publicWorkload,
        firstQuery: report.firstQuery, load: controls.load, ...nodeBenchmarkInstrumentation(), ...collected};
      report.latency.push(series);
      report.functional.rows.push({operation, fixtureSha256: series.fixtureSha256,
        completed: collected.samples.every(row => row.verified),
        expectedSha256: identify(collected.samples.map(row => row.expectedSha256)),
        actualSha256: identify(collected.samples.map(row => row.actualSha256))});
      await save();
      if (observedFailure) throw observedFailure;
      if (collected.stoppedEarly) {report.stoppedAt = operation; break;}
    }
  } catch (error) {
    report.firstFailure = {operation: active, ...nodeBenchmarkFailure(error)};
  } finally {
    let beforeClose, afterClose;
    if (observation) try {
      for (let turn = 0; turn < 32 && (observation.status().queued || observation.status().active); turn++) {
        await new Promise(resolve => setImmediate(resolve));
      }
      beforeClose = observation.status();
    } catch (error) {resourceFailures.push(nodeBenchmarkFailure(error));}
    if (client) try {await client.close(); report.cleanup.closed = true;}
    catch (error) {report.cleanup.failure = nodeBenchmarkFailure(error);}
    if (observation) try {
      if (!client) await observation.close(); // Only the unadopted observer belongs to this collector.
      afterClose = observation.status();
    } catch (error) {resourceFailures.push(nodeBenchmarkFailure(error));}
    try {assert.deepEqual(await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer), before); report.installedPayloadsUnchanged = true;}
    catch (error) {report.packageFailure = error.message;}
    if (!report.cleanup.closed || report.packageFailure) for (const row of report.functional.rows) {
      row.completed = false; delete row.actualSha256;
    }
    report.savedOriginals = originals.map(({runRef, resultRef, expected}) => ({runRef, resultRef, expected}));
    if (resourceObservations) {
      const missing = [], failures = [...resourceFailures];
      if (report.packageFailure || report.installedPayloadsUnchanged !== true) {
        failures.push({message: 'Installed-package correspondence failed'});
      }
      for (const op of observedOperations) {
        const rows = resourceRecords.filter(row => row.traceId === op.traceId && row.spanId === op.spanId);
        if (!op.completed || rows.length === 0) missing.push(`${op.publicOperationId}: completed same-Run observation`);
        else if (rows.length !== 1 || rows[0].runDefinitionCid !== op.runDefinitionCid) {
          failures.push({message: `${op.publicOperationId}: duplicate or foreign Run observation`});
        } else op.observationSequence = rows[0].sequence;
      }
      if (resourceRecords.some(row => !observedOperations.some(op =>
        op.traceId === row.traceId && op.spanId === row.spanId))) failures.push({message: 'Unmatched resource context'});
      for (const [label, status] of [['beforeClose', beforeClose], ['afterClose', afterClose]]) {
        if (!status) {missing.push(`${label}: actual observer status`); continue;}
        for (const key of ['dropped', 'deliveryFailed', 'budgetUnavailable', 'queueOverflow', 'limited',
          ...(!rowObservations ? ['repeated'] : []), 'queued', 'queuedBytes', 'active', 'activeSegments']) {
          if (status[key] !== 0) missing.push(`${label}: ${key} must be observed zero`);
        }
        if (!status.loss || Object.keys(status.loss).length) missing.push(`${label}: complete loss observation`);
      }
      if (afterClose?.closed !== true || afterClose?.cleanupPending !== false) missing.push('observer close completion');
      report.managedRunObservations = {...binding, scope: resourceObservations,
        status: failures.length ? 'failed' : missing.length ? 'incomplete' : 'passed',
        operations: observedOperations, records: resourceRecords, beforeClose, afterClose, failures, missing,
        qualification: 'Same managed Run Ledger after successful row-consumption cleanup only. '
          + 'No earlier/global peak, whole-Host temporary holdings, physical ACK or unrelated-row inference.'};
    }
    if (rowObservations) {
      const missing = [], failures = [...resourceFailures];
      if (report.packageFailure || report.installedPayloadsUnchanged !== true) failures.push({message: 'Installed-package correspondence failed'});
      const operations = observedOperations.map(op => {
        const rows = rowRecords.filter(row => row.traceId === op.traceId && row.spanId === op.spanId);
        if (!op.completed || rows.length === 0) missing.push(`${op.publicOperationId}: selected row observations`);
        for (const row of rows) {
          if (row.runDefinitionCid === undefined) missing.push(`${op.publicOperationId}: original Run correspondence`);
          else if (row.runDefinitionCid !== op.runDefinitionCid) failures.push({message: `${op.publicOperationId}: foreign row Run`});
        }
        return {...op, rowObservationSequences: rows.map(row => row.sequence)};
      });
      if (new Set(rowRecords.map(row => row.sequence)).size !== rowRecords.length) failures.push({message: 'Duplicate row observation sequence'});
      if (rowRecords.some(row => !operations.some(op => op.traceId === row.traceId && op.spanId === row.spanId))) {
        failures.push({message: 'Unmatched row observation context'});
      }
      for (const [label, status] of [['beforeClose', beforeClose], ['afterClose', afterClose]]) {
        if (!status) {missing.push(`${label}: actual observer status`); continue;}
        for (const key of ['dropped', 'deliveryFailed', 'budgetUnavailable', 'queueOverflow', 'limited',
          'queued', 'queuedBytes', 'active', 'activeSegments']) {
          if (status[key] !== 0) missing.push(`${label}: ${key} must be observed zero`);
        }
        if (!Number.isSafeInteger(status.repeated) || status.repeated < 0) missing.push(`${label}: actual deduplicated event count`);
        if (!status.loss || Object.keys(status.loss).length) missing.push(`${label}: complete selected loss observation`);
      }
      if (afterClose?.closed !== true || afterClose?.cleanupPending !== false) missing.push('observer close completion');
      report.selectedRowObservations = {...binding, scope: rowObservations,
        status: failures.length ? 'failed' : missing.length ? 'incomplete' : 'passed',
        operations, records: rowRecords, beforeClose, afterClose, failures, missing,
        qualification: 'Partial logical selected returned Run rows only. Missing Run or unrelated-row classification '
          + 'stays absent. No all-reads/history, physical DB reads, temporary population, cleanup ACK or zero-work inference.'};
    }
    report.priorityAssessment = assessPriorityTransition({sourceSha: report.sourceSha, platforms: {node: [report]}});
    report.fullAcceptance = false;
    await save();
  }
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2), options = {};
    assert(args.length % 2 === 0);
    for (let n = 0; n < args.length; n += 2) {
      const key = {'--manifest': 'manifestPath', '--consumer': 'consumer', '--output': 'output',
        '--controls': 'controlsPath', '--mode': 'mode', '--selection': 'selection',
        '--resource-observations': 'resourceObservations', '--row-observations': 'rowObservations'}[args[n]];
      assert(key && !Object.hasOwn(options, key)); options[key] = args[n + 1];
    }
    for (const key of ['manifestPath', 'consumer', 'output', 'controlsPath']) assert(options[key]);
    assert(options.selection === undefined || options.selection === 'priority-transition');
    assert(options.resourceObservations === undefined || options.selection === 'priority-transition');
    assert(options.rowObservations === undefined || options.selection === 'priority-transition');
    if (options.selection === 'priority-transition') {
      const report = await runNodePriorityBenchmark(options);
      console.log(JSON.stringify({sourceSha: report.sourceSha, selection: report.selection,
        assessment: report.priorityAssessment.gates.node, fullAcceptance: false}));
      process.exitCode = report.priorityAssessment.gates.node?.status === 'passed' ? 0 : 1;
    } else {
      const report = await runNodeWarmBenchmark(options);
      console.log(JSON.stringify({sourceSha: report.sourceSha, stoppedAt: report.stoppedAt ?? null,
        assessments: report.assessments, fullAcceptance: false}));
      process.exitCode = report.initialLatencyExceeded || report.stoppedAt || report.assessments.some(row => row.status !== 'passed') ? 1 : 0;
    }
  } catch (error) { console.error(error.message); process.exitCode = 2; }
}
