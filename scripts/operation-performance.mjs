// Acceptance evidence only. This module grants no runtime authority and does
// not replace package provenance, the public result oracle, or resource guards.
export const operationTargets = Object.freeze({
  'warm-select': {samples: 100, medianMs: 5, p95Ms: 10},
  'warm-result': {samples: 100, medianMs: 5, p95Ms: 10},
  'warm-status': {samples: 100, medianMs: 5, p95Ms: 10},
  'warm-join': {samples: 100, p95Ms: 500},
  'warm-union': {samples: 100, p95Ms: 500},
  'warm-decimal-sum': {samples: 100, p95Ms: 500},
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

export function assessLatency(series) {
  requireValue(Object.hasOwn(operationTargets, series.operation), 'Unknown public operation');
  const target = operationTargets[series.operation];
  requireValue(digest(series.cohortSha256) && digest(series.fixtureSha256) && digest(series.environmentSha256),
    'Exact cohort, fixture and environment identities are required');
  requireValue(['diagnostic', 'final'].includes(series.mode) && Array.isArray(series.samples), 'Invalid measurement mode');
  const failures = [], missing = [];
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
  if (summary.p95Ms !== null && summary.p95Ms > target.p95Ms) failures.push('p95 latency exceeds target');
  if (summary.count >= target.samples && target.medianMs !== undefined && summary.medianMs > target.medianMs) {
    failures.push('median latency exceeds target');
  }
  return outcome(failures, missing, {operation: series.operation, target, summary});
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
    const facts = new Map();
    if (!Array.isArray(operation.fullChecks)) missing.push(`${label}: explicit full-validation attribution`);
    else for (const check of operation.fullChecks) {
      requireValue(fullCheckKinds.includes(check.kind) && nonempty(check.fact) &&
        (nonempty(check.revision) || integer(check.revision)), 'Full checks require actual fact kind, identity and relevant revision');
      requireValue(typeof check.required === 'boolean', 'Declare required versus pure fact work');
      let tuple = null;
      if (check.kind === 'account-evaluation') {
        const value = check.tuple ?? {};
        requireValue(['subject', 'operation', 'resource'].every(key => nonempty(value[key])) &&
          ['run', 'target'].every(key => Object.hasOwn(value, key) && (value[key] === null || nonempty(value[key]))),
        'Account checks require the exact subject/operation/resource/Run/target tuple');
        tuple = ['subject', 'operation', 'resource', 'run', 'target'].map(key => value[key]);
      }
      // Internal frames, helpers, awaits, FFI phases and cache eviction are not
      // validation identities. Sum every entry for the same actual fact and
      // relevant revision across this entire public call. A cache hit reports
      // zero full calls; changing an Account getter's name cannot split a tuple.
      const key = JSON.stringify([check.kind, tuple === null ? check.fact : tuple, String(check.revision)]);
      const fact = facts.get(key) ?? {kind: check.kind, required: check.required, fullCalls: 0, complete: true};
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
      else if (![...facts.values()].some(fact => fact.kind === kind && !fact.complete)) {
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
  now = () => process.hrtime.bigint(), cpu = () => process.cpuUsage(), pid = process.pid}) {
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
    if (!verified || wallNs / 1e6 >= target.p95Ms * 10) {
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
    gates[series.operation] = assessLatency(series);
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
  requireValue(args.length === 2 && args[0] === '--input' || args.length === 4 && args[0] === '--input' && args[2] === '--output',
    'Usage: node scripts/operation-performance.mjs --input REPORT.json [--output SUMMARY.json]');
  requireValue((await stat(args[1])).size <= 16 * 1024 ** 2, 'Measurement report exceeds bounded input');
  const result = assessPerformanceEvidence(JSON.parse(await readFile(args[1], 'utf8')));
  const body = JSON.stringify(result, null, 2) + '\n';
  if (args[3]) await writeFile(args[3], body, {flag: 'wx'});
  process.stdout.write(body);
  return result.status === 'passed' ? 0 : 1;
}
const {pathToFileURL} = await import('node:url');
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { process.exitCode = await main(process.argv.slice(2)); }
  catch (error) { console.error(String(error.message)); process.exitCode = 2; }
}
