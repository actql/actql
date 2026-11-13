// Actual fixed-cohort global installation and source-free Local execution.
// Mock bindings, live Connectors, approval and public-registry publication are
// separate acceptance subjects. No repository runtime or Node Host is loaded.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {lstat, mkdir, readFile, readdir, writeFile, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {createInterface} from 'node:readline';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';
import {admitInstalledLocalRuntime} from '../packages/native-cli/lib/local-runtime.mjs';
import {canonicalText} from './check-canonical-json.mjs';
import {nativeMockAcceptanceObservations} from '../packages/native-cli/lib/project-scaffold.mjs';
import {nativeLauncherEnvelope} from './native-cli-mock-scenario.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));

// Existing process counters measure these actual call sites, not SQL compiler
// internals. In particular tag 17 counts a legacy JSON/submitted-intent helper;
// zero there does not establish zero SQL parse, check or compilation work.
export function requireNativeSourceFreeWorkCounts(operation, counters) {
  assert(['check', 'run', 'sql', 'result'].includes(operation));
  const selected = tag => {
    const rows = counters.filter(row => row.tag === tag);
    assert.equal(rows.length, 1, `Missing or duplicate Native work counter ${tag}`);
    assert(Number.isSafeInteger(rows[0].count) && rows[0].count >= 0);
    return rows[0].count;
  };
  const measured = {
    checkingEnvironmentAdmissions: selected(21),
    runInstallationAdmissions: selected(31),
    productConfigurationStagePasses: selected(58),
    packagedRuntimeOriginalChecks: selected(59),
    legacyJsonOrSubmittedIntentHelperCalls: selected(17),
    requestQueryParseCalls: selected(66),
    requestQueryLowerCalls: selected(67),
    requestSemanticCheckCalls: selected(68),
    requestProgramCompileCalls: selected(69),
  };
  assert.equal(measured.checkingEnvironmentAdmissions, operation === 'result' ? 0 : 1,
    'Repeated or missing checking Environment admission');
  for (const name of ['runInstallationAdmissions', 'productConfigurationStagePasses',
    'packagedRuntimeOriginalChecks']) assert.equal(measured[name], 1, `Repeated or missing ${name}`);
  for (const name of ['requestQueryParseCalls', 'requestQueryLowerCalls', 'requestSemanticCheckCalls'])
    assert.equal(measured[name], operation === 'result' ? 0 : 1, `Repeated or missing ${name}`);
  assert.equal(measured.requestProgramCompileCalls, operation === 'run' || operation === 'sql' ? 1 : 0,
    'Repeated or missing requestProgramCompileCalls');
  return {operation, measured, unmeasured: {
    otherCheckerPhaseCalls: null, immutableBodyReadmissionCalls: null,
  }};
}

export async function observeNativeSourceFreeCommand({args, cwd, cli, environment}) {
  assert(['check', 'run', 'sql', 'result'].includes(args[0]));
  const flags = ['ACTQL_NATIVE_TIMINGS', 'ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS'];
  const previous = flags.map(key => [key, environment[key]]);
  let record;
  try {
    for (const key of flags) environment[key] = '1';
    record = await cli(args, cwd);
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete environment[key];
      else environment[key] = value;
    }
  }
  assert.equal(record.code, 0); assert.equal(record.signal, null);
  const envelope = nativeLauncherEnvelope(record.stderr, 'required');
  const groups = nativeMockAcceptanceObservations(envelope.native);
  assert.equal(groups.length, 1, 'One original Native process required');
  assert.equal(groups[0].events.length, 0, 'Source-free command repeated Model or Effect work');
  // The existing parser owns the complete schema and tag inventory. Inspect
  // only recording integrity and the selected existing counters afterward.
  const rows = envelope.native.trimEnd().split('\n').map(line => {
    const space = line.indexOf(' ');
    return {marker: line.slice(0, space), value: JSON.parse(line.slice(space + 1))};
  });
  const meta = rows.find(row => row.marker === 'ACTQL_NATIVE_TIMINGS').value;
  for (const key of ['initializing_drops', 'invalid_tags', 'invalid_amounts', 'clock_failures',
    'stack_overflows']) assert.equal(meta[key], 0, `Incomplete Native counter recording: ${key}`);
  assert.equal(meta.overflow, false, 'Overflowed Native work counters');
  record.sourceFreeWork = {pid: groups[0].pid,
    ...requireNativeSourceFreeWorkCounts(args[0], rows.filter(row => row.marker === 'ACTQL_NATIVE_COUNTER').map(row => row.value))};
  return record;
}

// Independent expectations for the ordinary, unmodified init profile. These
// are aggregate semantics, unlike the separate large VALUES row-delivery case.
export const nativeDefaultNumericQueries = Object.freeze([
  {name: 'sum', sql: 'WITH x AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT SUM(n) AS total FROM x', rows: [{total: 3}]},
  {name: 'average', sql: 'WITH x AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT AVG(n) AS total FROM x', rows: [{total: 1.5}]},
  {name: 'decimal', sql: "WITH x AS (SELECT CAST('1.25' AS DECIMAL(8,2)) AS n UNION ALL SELECT CAST('2.75' AS DECIMAL(8,2)) AS n) SELECT SUM(n) AS total FROM x", rows: [{total: '4.00'}]},
  {name: 'controls', sql: 'WITH x AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT COUNT(*) AS count, MIN(n) AS minimum FROM x', rows: [{count: 2, minimum: 1}]},
  {name: 'where', sql: 'WITH x AS (SELECT 1 AS n UNION ALL SELECT 2 AS n) SELECT n FROM x WHERE n > 1', rows: [{n: 2}]},
  {name: 'grouped', sql: "WITH x AS (SELECT 'a' AS bucket, 1 AS n UNION ALL SELECT 'a' AS bucket, 2 AS n UNION ALL SELECT 'b' AS bucket, 4 AS n) SELECT bucket, SUM(n) AS total, AVG(n) AS average FROM x GROUP BY bucket ORDER BY bucket", rows: [{bucket: 'a', total: 3, average: 1.5}, {bucket: 'b', total: 4, average: 4}]},
  {name: 'empty', sql: 'WITH x AS (SELECT 1 AS n WHERE FALSE) SELECT SUM(n) AS total, AVG(n) AS average, COUNT(n) AS count FROM x', rows: [{total: null, average: null, count: 0}]},
  {name: 'nulls', sql: 'WITH x AS (SELECT CAST(NULL AS NUMBER) AS n UNION ALL SELECT CAST(NULL AS NUMBER) AS n) SELECT SUM(n) AS total, AVG(n) AS average, COUNT(n) AS count FROM x', rows: [{total: null, average: null, count: 0}]},
  {name: 'mixed-null', sql: 'WITH x AS (SELECT 1 AS n UNION ALL SELECT CAST(NULL AS NUMBER) AS n UNION ALL SELECT 2 AS n) SELECT SUM(n) AS total, AVG(n) AS average FROM x', rows: [{total: 3, average: 1.5}]},
  {name: 'parameters', sql: 'WITH x AS (SELECT @first AS n UNION ALL SELECT @second AS n) SELECT SUM(n) AS total, AVG(n) AS average FROM x', rows: [{total: 3, average: 1.5}], parameters: true},
]);

export async function observeNativeDefaultNumericQueries({project, cli, queries = nativeDefaultNumericQueries}) {
  assert(queries.length > 0 && queries.every(entry => nativeDefaultNumericQueries.includes(entry)));
  const cases = join(project, 'numeric-cases');
  await mkdir(cases, {mode: 0o700});
  const rows = text => text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  const observations = [];
  const retained = [];
  const currentProject = join(cases, 'ordinary');
  // Repeated admitted intents share one ordinary installation and its finite
  // Journal policy. A fresh Host per query would conceal cumulative refusal.
  await cli(['init', currentProject], project);
  for (const entry of queries) {
    const file = `numeric-${entry.name}.sql`;
    await writeFile(join(currentProject, file), entry.sql, {flag: 'wx', mode: 0o600});
    const parameters = entry.parameters ? ['--parameter-declarations-file', 'numeric-declarations.json',
      '--parameters-file', 'numeric-parameters.json'] : [];
    if (entry.parameters) {
      await writeFile(join(currentProject, 'numeric-declarations.json'), JSON.stringify({first: {type: 'number'}, second: {type: 'number'}}), {flag: 'wx'});
      await writeFile(join(currentProject, 'numeric-parameters.json'), '{"first":1,"second":2}', {flag: 'wx'});
    }
    const checked = JSON.parse((await cli(['check', file, '--format', 'sql', '--json', ...parameters], currentProject)).stdout);
    assert.equal(checked.outcome, 'completed', `${entry.name}: completed check required`);
    assert.equal(checked.report.verdict, 'verified', `${entry.name}: verified check required`);
    assert.equal(checked.report.runnable.verdict, 'yes', `${entry.name}: runnable check required`);
    const state = JSON.parse((await cli(['run', file, '--format', 'sql', '--json', ...parameters], currentProject)).stdout);
    assert.equal(state.version, 'actql-run-state/0.1'); assert.equal(state.status, 'succeeded');
    assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
    assert(!retained.some(value => value.runId === state.run_id), 'Fresh submissions must have distinct original Runs');
    assert.deepEqual(rows((await cli(['result', state.run_id, '--format', 'jsonl'], currentProject)).stdout), entry.rows);
    // Every cli invocation is a separate process. Removing original inputs
    // makes a new prepare or reexecution unable to replace the saved Result.
    await unlink(join(currentProject, file));
    if (entry.parameters) {
      await unlink(join(currentProject, 'numeric-declarations.json'));
      await unlink(join(currentProject, 'numeric-parameters.json'));
    }
    assert.deepEqual(rows((await cli(['result', state.run_id, '--format', 'jsonl'], currentProject)).stdout), entry.rows);
    retained.push({runId: state.run_id, entry});
    observations.push({name: entry.name, checkRunnable: 'yes', rows: entry.rows, coldSavedWithoutProgram: true});
  }
  for (const [invalid, sql] of [['numeric-invalid.sql', "SELECT SUM('not a number') AS total"],
    ['numeric-invalid-syntax.sql', 'SELECT )']]) {
    await writeFile(join(currentProject, invalid), sql, {flag: 'wx'});
    const refusal = JSON.parse((await cli(['check', invalid, '--format', 'sql', '--json'], currentProject, 1)).stdout);
    assert.equal(refusal.report.verdict, 'invalid'); assert.equal(refusal.report.runnable.verdict, 'no');
    await unlink(join(currentProject, invalid));
  }
  assert.deepEqual(rows((await cli(['sql', nativeDefaultNumericQueries[0].sql, '--format', 'jsonl'], currentProject)).stdout), [{total: 3}]);
  // Later successful submissions and rejected checks must not evict the oldest
  // originals. These are Saved reads, never another run/sql or hidden Host.
  for (const {runId, entry} of retained) {
    assert.deepEqual(rows((await cli(['result', runId, '--format', 'jsonl'], currentProject)).stdout), entry.rows);
    observations.find(value => value.name === entry.name).savedAfterLaterSubmissions = true;
  }
  return observations;
}

// Exercise the former 64 KiB Plan boundary with the ordinary init profile.
// Public explain bytes do not measure the separately stored Run metadata row.
export const nativeDefaultUnionCases = Object.freeze([
  {branches: 11, total: 55}, {branches: 17, total: 136}, {branches: 24, total: 276},
]);

// The independent WITH-set golden emits values/derive/select for each
// literal SELECT, N-1 UNION ALL appends, then SUM group/final projection.
// Assert those original logical occurrences and their complete input/output
// connections, rather than accepting any nonempty JSON as a retained Plan.
function assertNativeUnionPlan(value, originalRef, branches) {
  assert.equal(value.version, 'actql-run-plan-view/0.1');
  assert.deepEqual(value.run_ref, originalRef, 'Saved explain must select the original Run reference');
  const plan = value.plan_view;
  assert.equal(plan?.version, 'actql-plan-view/0.1', 'Complete retained Plan required');
  const cid = /^sha256:[0-9a-f]{64}$/u;
  assert.match(plan.compiled_plan_cid, cid);
  assert.equal(plan.observation, 'static');
  assert.equal(plan.provider_io, 0);
  const map = plan.logical_map;
  assert.equal(map?.version, 'actql-logical-map/0.1');
  assert.equal(map.compiled_plan_cid, plan.compiled_plan_cid);
  assert.match(map.program_definition_cid, cid);
  assert.match(map.self_cid, cid);
  assert(Array.isArray(map.steps) && map.steps.length > 0, 'Complete logical steps required');
  const counts = new Map(), outputs = new Map(), steps = new Set(), ports = new Set();
  let lastOperator;
  for (const step of map.steps) {
    const arity = new Map([['values', 0], ['derive', 1], ['select', 1], ['append', 2], ['group', 1]]).get(step.operator);
    assert.notEqual(arity, undefined, 'Unexpected operation in the original UNION/SUM fixture');
    assert.match(step.step_id, cid);
    assert(!steps.has(step.step_id), 'Distinct original logical occurrences required');
    steps.add(step.step_id);
    assert.equal(step.key?.version, 'actql-logical-step-key/0.1');
    assert.equal(step.key.compiled_plan_cid, plan.compiled_plan_cid);
    assert.equal(step.key.self_cid, step.step_id);
    assert.equal(step.key.stage_ordinal, 0, 'This SQL retains the independent one-stage WITH-set shape');
    assert.deepEqual(step.key.occurrence, {kind: 'operation', operation_ordinal: steps.size - 1});
    assert(Array.isArray(step.ports));
    const inputs = step.ports.filter(port => port.role === 'input');
    const output = step.ports.filter(port => port.role === 'output');
    assert.equal(inputs.length, arity, 'Retain every original input port');
    assert.equal(output.length, 1, 'Retain the original output port');
    assert.equal(step.ports.length, arity + 1);
    for (const port of step.ports) {
      assert.match(port.port_id, cid);
      assert(!ports.has(port.port_id), 'Distinct original logical ports required');
      ports.add(port.port_id);
      assert.equal(port.carrier, 'relation');
      if (port.role === 'input') {
        assert(port.source, 'Original input producer required');
        assert.equal(port.source.kind, 'logical_output', 'This source-free WITH uses same-stage producers');
        assert(outputs.has(port.source.output_port_id), 'Original earlier output port required');
        assert.equal(outputs.get(port.source.output_port_id), port.source.step_id,
          'Retain the exact earlier logical producer, not a truncated graph');
      }
    }
    outputs.set(output[0].port_id, step.step_id);
    counts.set(step.operator, (counts.get(step.operator) ?? 0) + 1);
    lastOperator = step.operator;
  }
  assert.equal(counts.get('values'), branches, 'Retain every literal SELECT seed');
  assert.equal(counts.get('derive'), branches, 'Retain every literal evaluation before its projection');
  assert.equal(counts.get('append'), branches - 1, 'Retain every UNION ALL occurrence');
  assert.equal(counts.get('group'), 1, 'Retain the original SUM aggregate');
  assert.equal(counts.get('select'), branches + 1, 'Retain branch projections and the final total projection');
  assert.equal(map.steps.length, 4 * branches + 1, 'Complete current fixture lowering, not a public planning limit');
  assert.equal(lastOperator, 'select', 'Retain the final aggregate projection');
  const planBytes = Buffer.byteLength(JSON.stringify(plan), 'utf8');
  if (branches === nativeDefaultUnionCases.at(-1).branches)
    assert(planBytes > 65536, 'The largest complete inner Plan must actually cross the former 64 KiB boundary');
  return {planBytes, logicalSteps: map.steps.length};
}

export async function observeNativeDefaultUnionMetadata({root, cli}) {
  const project = join(root, 'ordinary-union-metadata');
  await cli(['init', project], root);
  const configuration = await readFile(join(project, 'actql.config.json'), 'utf8');
  assert.equal(JSON.parse(configuration).profile, undefined, 'Ordinary default profile required');
  const rows = text => text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  const observations = [], retained = [];
  for (const {branches, total} of nativeDefaultUnionCases) {
    const file = `union-${branches}.sql`;
    const sql = 'WITH t AS (' + Array.from({length: branches}, (_, index) =>
      `SELECT ${index} AS v`).join(' UNION ALL ') + ') SELECT SUM(v) AS total FROM t';
    await writeFile(join(project, file), sql, {flag: 'wx', mode: 0o600});
    const run = await cli(['run', file, '--format', 'sql', '--json'], project);
    const state = JSON.parse(run.stdout);
    assert.equal(state.version, 'actql-run-state/0.1');
    assert.equal(state.status, 'succeeded', `${branches}-branch admission must succeed`);
    assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
    assert(!retained.some(value => value.runId === state.run_id), 'Distinct original Runs required');
    await unlink(join(project, file));
    // Every command is a new actual installed process. The invalid input must
    // not poison the unchanged installation or cause Saved to reexecute SQL.
    await cli(['sql', 'SELECT )', '--format', 'json'], project, 1);
    assert.deepEqual(rows((await cli(['sql', 'SELECT 9821 AS n', '--format', 'jsonl'], project)).stdout), [{n: 9821}]);
    const saved = await cli(['result', state.run_id, '--format', 'jsonl'], project);
    assert.deepEqual(rows(saved.stdout), [{total}]);
    const status = JSON.parse((await cli(['status', '--run-id', state.run_id, '--json'], project)).stdout);
    assert.equal(status.kind, 'local_saved_run_state');
    assert.equal(status.state?.version, 'actql-run-state/0.1');
    assert.equal(status.state.run_id, state.run_id, 'Observe the same originally returned Run');
    assert.equal(status.state.status, 'succeeded');
    const originalRef = status.ref;
    assert(originalRef && typeof originalRef === 'object' && !Array.isArray(originalRef));
    assert.equal(typeof originalRef.namespaceId, 'string'); assert(originalRef.namespaceId.length > 0);
    for (const field of ['authorityScopeCid', 'runDefinitionCid'])
      assert.match(originalRef[field], /^sha256:[0-9a-f]{64}$/u);
    const explain = await cli(['explain', '--run', state.run_id, '--json'], project);
    const value = JSON.parse(explain.stdout);
    const plan = assertNativeUnionPlan(value, originalRef, branches);
    const again = await cli(['explain', '--run', state.run_id, '--json'], project);
    assert.equal(again.stdout, explain.stdout, 'Repeated cold Saved explain must retain exact bytes');
    assert.equal(await readFile(join(project, 'actql.config.json'), 'utf8'), configuration,
      'Acceptance must not widen the ordinary project profile');
    retained.push({runId: state.run_id, total});
    observations.push({branches, total, runId: state.run_id, coldSavedWithoutProgram: true,
      recoveryAfterInvalidQuery: true, repeatedExplainBytesIdentical: true,
      planBytes: plan.planBytes, logicalSteps: plan.logicalSteps, storedRunMetadataBytes: null,
      runElapsedMs: run.elapsedMs, savedElapsedMs: saved.elapsedMs,
      explainElapsedMs: explain.elapsedMs, repeatedExplainElapsedMs: again.elapsedMs});
  }
  for (const {runId, total} of retained) {
    assert.deepEqual(rows((await cli(['result', runId, '--format', 'jsonl'], project)).stdout), [{total}]);
  }
  return {profile: 'ordinary-unmodified-init', cases: observations, oldestSavedAfterLaterSubmissions: true};
}

export async function observeNativeFileSourceNumeric({root, cli}) {
  const project = join(root, 'numeric-file-source');
  await cli(['init', '--template', 'churn-risk-mock', project], root);
  const program = join(project, 'numeric-source.sql');
  const source = join(project, 'mock/data.json');
  const original = await readFile(source);
  await writeFile(program, "SELECT SUM(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS total, AVG(CASE WHEN trend = 'down' THEN 4 ELSE 12 END) AS average FROM snowflake.usage_30d", {flag: 'wx'});
  const checked = JSON.parse((await cli(['check', 'numeric-source.sql', '--format', 'sql', '--json'], project)).stdout);
  assert.equal(checked.outcome, 'completed'); assert.equal(checked.report.verdict, 'verified');
  assert.equal(checked.report.runnable.verdict, 'yes');
  const state = JSON.parse((await cli(['run', 'numeric-source.sql', '--format', 'sql', '--json'], project)).stdout);
  assert.equal(state.status, 'succeeded'); assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
  const resultRows = text => text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  assert.deepEqual(resultRows((await cli(['result', state.run_id, '--format', 'jsonl'], project)).stdout), [{total: 16, average: 8}]);
  assert.deepEqual(await readFile(source), original, 'The read-only aggregate must not change its file Source');
  await unlink(program); await unlink(source);
  const rows = resultRows((await cli(['result', state.run_id, '--format', 'jsonl'], project)).stdout);
  assert.deepEqual(rows, [{total: 16, average: 8}]);
  return {checkRunnable: 'yes', rows, completeResultBeforeInputRemoval: true,
    coldSavedWithoutProgramOrSource: true};
}

// The exact same authored JSON is checked independently by the portable
// client_local_host fixture. Its 30 Units retain 33 physical tasks, including
// one real captured File Source; source-free UNION size is not its oracle.
export async function observeNativeFileTaskBoundary({root, cli, environment}) {
  const project = join(root, 'file-task-boundary');
  await cli(['init', '--template', 'churn-risk-mock', project], root);
  const file = 'file-task-boundary.json', source = join(project, 'mock/data.json');
  const original = await readFile(source);
  const wire = await readFile(new URL('./fixtures/native-file-task-boundary.json', import.meta.url));
  await writeFile(join(project, file), wire, {flag: 'wx', mode: 0o600});
  const checked = JSON.parse((await cli(['check', file, '--format', 'json', '--json'], project)).stdout);
  assert.equal(checked.outcome, 'completed'); assert.equal(checked.report.verdict, 'verified');
  assert.equal(checked.report.runnable.verdict, 'yes');
  const command = async args => {
    const flags = ['ACTQL_NATIVE_TIMINGS', 'ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS'];
    const previous = flags.map(key => [key, environment[key]]);
    let record;
    try {
      for (const key of flags) environment[key] = '1';
      record = await cli(args, project);
    } finally {
      for (const [key, value] of previous) {
        if (value === undefined) delete environment[key]; else environment[key] = value;
      }
    }
    assert.equal(record.code, 0); assert.equal(record.signal, null);
    const native = nativeLauncherEnvelope(record.stderr, 'required').native;
    const groups = nativeMockAcceptanceObservations(native);
    assert.equal(groups.length, 1, 'One original Native process required');
    assert.equal(groups[0].events.length, 0, 'No Model or Effect work in this File fixture');
    const rows = native.trimEnd().split('\n').map(line => {
      const space = line.indexOf(' ');
      return {marker: line.slice(0, space), value: JSON.parse(line.slice(space + 1))};
    });
    const meta = rows.find(row => row.marker === 'ACTQL_NATIVE_TIMINGS').value;
    for (const key of ['initializing_drops', 'invalid_tags', 'invalid_amounts', 'clock_failures', 'stack_overflows'])
      assert.equal(meta[key], 0, `Incomplete Native File observation: ${key}`);
    assert.equal(meta.overflow, false);
    const close = rows.find(row => row.marker === 'ACTQL_NATIVE_PHASE' && row.value.tag === 5).value;
    assert.equal(close.begins, 1, 'Observe the first original command cleanup, without a retry');
    assert.equal(close.ends, 1); assert.equal(close.active, 0); assert.equal(close.unmatched_end, 0);
    // Tag 5 surrounds the actual command cleanup. Successful exit is also
    // required; neither fact is independent physical FD/whole-Host ACK.
    return {record, pid: groups[0].pid};
  };
  const run = await command(['run', file, '--format', 'json', '--json']);
  const state = JSON.parse(run.record.stdout);
  assert.equal(state.version, 'actql-run-state/0.1'); assert.equal(state.status, 'succeeded');
  assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
  const rows = text => text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  const first = await command(['result', state.run_id, '--result', 'answer', '--format', 'jsonl']);
  // The authored churn template contains two usage rows. Do not derive this
  // expectation from the compiler, a preview, or the delivered result itself.
  assert.deepEqual(rows(first.record.stdout), [{id: 2}]);
  assert.deepEqual(await readFile(source), original, 'The complete File Source must remain unchanged');
  await unlink(join(project, file)); await unlink(source);
  const cold = await command(['result', state.run_id, '--result', 'answer', '--format', 'jsonl']);
  assert.notEqual(cold.pid, first.pid, 'Saved must use a separate Native process');
  assert.deepEqual(rows(cold.record.stdout), [{id: 2}]);
  return {runId: state.run_id, rows: [{id: 2}], fixtureSha256: createHash('sha256').update(wire).digest('hex'),
    independentCheckedFixture: {tasks: 33, units: 30, acquisitions: 1, capturedPrefix: 1},
    firstCommandCleanupObserved: true, independentPhysicalAck: false,
    completeResultBeforeInputRemoval: true, coldSavedWithoutProgramOrSource: true};
}

// Read the actual delivered file, including its last row. A count, preview or
// aggregate alone cannot establish the contents of the original stored Result.
export async function verifyNativeNumericRows(path, count = 100000) {
  const input = createReadStream(path), lines = createInterface({input, crlfDelay: Infinity});
  const closed = new Promise(resolve => input.once('close', resolve));
  let rows = 0, sum = 0n, squares = 0n;
  try {
    for await (const line of lines) {
      const row = JSON.parse(line);
      assert(rows < count, 'Unexpected extra numeric Result row');
      assert.deepEqual(Object.keys(row), ['v0']);
      assert.equal(row.v0, rows, `Numeric Result row ${rows}`);
      const value = BigInt(row.v0);
      sum += value; squares += value * value; rows++;
    }
  } finally {lines.close(); input.destroy(); await closed;}
  const n = BigInt(count);
  assert.equal(rows, count, 'Complete numeric Result required');
  assert.equal(sum, n * (n - 1n) / 2n);
  assert.equal(squares, n * (n - 1n) * (2n * n - 1n) / 6n);
  return {rows, sum: String(sum), squares: String(squares)};
}

// Each cli call below launches the same installed Native entry in a new
// process. Its successful reply/exit is gated by the entry's real command
// cleanup; it is not independent FD inspection or a whole-Host stop claim.
export async function observeNativeNumericScale({project, cli, outputDirectory = project}) {
  const count = 100000, input = join(project, 'numeric-scale.json');
  const first = join(outputDirectory, 'numeric-first.jsonl'), saved = join(outputDirectory, 'numeric-saved.jsonl');
  const program = {version: 'actql/0.1', id: 'numeric-scale',
    stages: [{id: 'main', inputs: {}, steps: [{as: 'v', values: {
      schema: {v0: {type: 'number', nullable: false}},
      rows: Array.from({length: count}, (_, v0) => ({v0})),
    }}], results: {rows: {from: 'v', fields: ['v0']}}}],
    results: {answer0: {from: {stage: 'main', result: 'rows'}}}};
  const wire = JSON.stringify(program), inputWireBytes = Buffer.byteLength(wire);
  assert(inputWireBytes > 1048576, 'The public JSON Source must exceed one MiB');
  await writeFile(input, wire, {flag: 'wx', mode: 0o600});
  const command = async args => {
    const reply = await cli(args, project);
    assert.equal(reply.code, 0); assert.equal(reply.signal, null);
    return reply;
  };
  const original = JSON.parse((await command(['run', 'numeric-scale.json', '--format', 'json', '--json'])).stdout);
  assert.equal(original.version, 'actql-run-state/0.1');
  assert.equal(original.status, 'succeeded');
  assert.equal(typeof original.run_id, 'string'); assert(original.run_id.length > 0);
  await command(['result', original.run_id, '--result', 'answer0', '--format', 'jsonl', '--output', first]);
  const firstRows = await verifyNativeNumericRows(first, count);
  // No second submission or source-file fallback is available to Saved.
  await unlink(input);
  const restored = JSON.parse((await command(['status', original.run_id, '--json'])).stdout);
  assert.equal(restored.version, original.version);
  assert.equal(restored.run_id, original.run_id); assert.equal(restored.status, 'succeeded');
  await command(['result', original.run_id, '--result', 'answer0', '--format', 'jsonl', '--output', saved]);
  const savedRows = await verifyNativeNumericRows(saved, count);
  assert.deepEqual(savedRows, firstRows);
  return {scope: 'installed-native-json-source-values', inputWireBytes, runId: original.run_id,
    inputRemovedBeforeSaved: true, first: firstRows, saved: savedRows,
    cleanup: 'successful Native command cleanup before reply and process exit',
    independentFdInspection: false};
}

// Explicit operator configuration through the existing Native adopt path. The
// same installed assets/libraries remain originals; no product default changes
// and no accepted Host is reconfigured. The actual Owners still decide admission.
export async function prepareNativeNumericOperator({project, assets, libraries, runtimeWire, maxRows,
  journalRecordLimit = 8}) {
  assert(Number.isSafeInteger(maxRows) && maxRows > 0 && maxRows <= 100000);
  // These are the explicit finite acceptance fixtures, not a product limit.
  assert([1, 2, 8].includes(journalRecordLimit));
  assert(isAbsolute(project) && isAbsolute(libraries.sqlite) && isAbsolute(libraries.crypto));
  assert.equal(typeof runtimeWire, 'string'); JSON.parse(runtimeWire);
  const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');
  const environment = JSON.parse(assets.environment);
  delete environment.evidence_bundle_cid;
  Object.assign(environment.host_policy_profile.capacity, {
    max_relation_output_rows: maxRows, max_artifact_rows: maxRows, max_artifact_bytes: 16777216,
  });
  environment.evidence_bundle_cid = cid(environment);
  const policy = JSON.parse(assets['result-policy']), policyCid = cid(policy);
  const dependencies = [['retention_contract', 'local-result-retention'],
    ['metadata_retention_policy', 'local-result-metadata'], ['clock_contract', 'local-clock']]
    .map(([kind, name]) => {
      const body = {name, version: 'actql-installed-local-policy/0.1'};
      return {kind, cid: cid(body), wire: canonicalText(body)};
    });
  const retention = {version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: dependencies[0].cid, effective_data_policy_cid: policyCid,
    available_until: '2099-01-01T00:00:00.000Z', delete_by: '2099-01-02T00:00:00.000Z',
    extension_ceiling_at: '2099-01-02T00:00:00.000Z',
    metadata_retention_policy_cid: dependencies[1].cid, metadata_delete_by: '2099-01-03T00:00:00.000Z',
    clock_contract_cid: dependencies[2].cid};
  retention.effective_retention_policy_cid = cid(retention);
  // Select the existing finite profile from these same dependency originals.
  // The Native Owner admits it and binds first acceptance; this DATA assembly
  // does not issue a Run policy or reinterpret the absolute retention original.
  const profile = {version: 'actql-local-run-policy-profile/0.1',
    available_for_ms: 86400000, delete_after_ms: 172800000,
    metadata_after_ms: 604800000, read_for_ms: 86400000,
    effective_data_policy_cid: policyCid, retention_contract_cid: dependencies[0].cid,
    metadata_retention_policy_cid: dependencies[1].cid, clock_contract_cid: dependencies[2].cid};
  const principal = 'numeric-operator', connection = 'cli';
  const permission = (entry_id, resource, operations) => ({entry_id, outcome: 'allow',
    principal: {any_of: [principal]}, connection: {any_of: [connection]},
    resource: {any_of: [resource]}, operation: {any_of: operations}, exclusions: []});
  // This existing Store owner uses its declared original property order.
  const storeWire = JSON.stringify({version: 'actql-local-store-owner/0.1',
    root: join(project, 'results'), principalId: principal});
  const storeCid = 'sha256:' + createHash('sha256').update(storeWire).digest('hex');
  const files = {
    'account.json': {version: 'actql-execution-account-config/0.1', account_id: principal,
      entries: [permission('numeric-result', 'result/answer0', ['read']),
        permission('numeric-run', 'run', ['cancel', 'publish', 'read', 'submit'])]},
    'environment.json': environment,
    'run.json': {version: 'actql-config/0.1', native: {run: {
      namespace_id: 'numeric', store_name: 'results', store_authority_cid: storeCid,
      store_capacity_bytes: 33554432, store_objects: 32, store_record_bytes: 16777216,
      result_payload_bytes: 16777216, retention_policy_wire: canonicalText(retention),
      source_free: {registry: assets.registry, values: assets.values, fragment: assets.fragment,
        ordered: assets.ordered, result_policy_cid: policyCid, result_policy_wire: assets['result-policy']},
    }}},
    'read.json': {version: 'actql-config/0.1', native: {result_read: {
      enabled: true, principal, connection, result_names: ['answer0'], formats: ['jsonl'],
      purpose: 'cli-read', sink: 'stdout', data_policy_cids: [policyCid], max_bytes: 16777216,
      max_uses: 1, run_policy_profile_cid: cid(profile),
      run_file: 'run.json', retention_file: 'retention.json', store_file: 'store.json',
    }}},
    'retention.json': dependencies,
    'profile.json': profile,
    'operator.json': {version: 'actql-config/0.1', account_config: 'account.json', native: {
      check_environment: {file: 'environment.json', evidence_bundle_cid: environment.evidence_bundle_cid},
      local: {account_id: principal, principal, connection, state_parent: project, state_name: 'host',
        managed_root: project, sqlite_library: libraries.sqlite, signature_library: libraries.crypto,
        submission_ttl_ms: 86400000, journal_record_limit: journalRecordLimit, journal_snapshot_bytes: 8388608,
        installation_files: ['run.json', 'read.json', 'retention.json', 'store.json', 'runtime.json', 'profile.json', 'file-read.json'],
        run_file: 'run.json', read_file: 'read.json', run_policy_profile_file: 'profile.json'},
    }},
  };
  // File output has its own adopted selection; a later --output destination
  // cannot manufacture it from the stdout read original.
  files['file-read.json'] = structuredClone(files['read.json']);
  Object.assign(files['file-read.json'].native.result_read, {sink: 'file', purpose: 'cli-file'});
  await mkdir(project, {mode: 0o700});
  for (const [name, value] of Object.entries(files)) {
    await writeFile(join(project, name), canonicalText(value), {flag: 'wx', mode: 0o600});
  }
  await writeFile(join(project, 'store.json'), storeWire, {flag: 'wx', mode: 0o600});
  await writeFile(join(project, 'runtime.json'), runtimeWire, {flag: 'wx', mode: 0o600});
  return {configuration: ['--mode', 'local', '--config-root', project, '--config-file', 'operator.json'],
    environmentCid: environment.evidence_bundle_cid, maxRows};
}

// This reads the original closed typed diagnostic from this deliberately
// exhausted fixture. A generic refusal, Unknown or process exit is insufficient.
export function requireNativeJournalCapacityRefusal(record) {
  assert.equal(record.code, 1); assert.equal(record.signal, null);
  assert.equal(record.stdout, '');
  const envelope = nativeLauncherEnvelope(record.stderr, 'required');
  const lines = envelope.native.trimEnd().split('\n');
  const diagnostics = lines.filter(line => line.startsWith('ACTQL_NATIVE_'));
  const publicLines = lines.filter(line => !line.startsWith('ACTQL_NATIVE_'));
  assert.equal(publicLines.length, 1);
  // Fresh submissions keep the CLI's original reconciliation IDs and warning;
  // these are correlation data, not permission to retry or absence evidence.
  assert.match(publicLines[0], /^actql-native-client: LocalSubmissionAcceptanceUnavailable originalSubmissionRequestId=sha256:[0-9a-f]{64} originalOperationAttemptId=cli-[0-9a-f]{64} \(reconcile with lookup-request; do not resend this operation\)$/u);
  const groups = nativeMockAcceptanceObservations(diagnostics.join('\n') + '\n');
  assert.equal(groups.length, 1); assert.equal(groups[0].events.length, 0);
  const values = prefix => diagnostics.filter(line => line.startsWith(prefix))
    .map(line => JSON.parse(line.slice(prefix.length)));
  const metadata = values('ACTQL_NATIVE_TIMINGS ')[0];
  for (const name of ['initializing_drops', 'invalid_tags', 'invalid_amounts',
    'clock_failures', 'stack_overflows']) assert.equal(metadata[name], 0);
  assert.equal(metadata.overflow, false);
  const counters = new Map(values('ACTQL_NATIVE_COUNTER ').map(row => [row.tag, row.count]));
  // Slot 8 also contains the returned Read inventory's retained peak. Keep
  // that observation untouched; it cannot count Native failed acceptances.
  assert.equal(counters.get(10), 7, 'Original Journal failure required');
  assert.equal(counters.get(11), 5001, 'Original Journal CapacityExceeded required');
  // This admission failure precedes business preparation in local_start.mbt.
  // Compute cleanup also uses slots 14/15: do not read transaction tags after
  // business work or an ambiguous/missing domain observation.
  const phases = values('ACTQL_NATIVE_PHASE ');
  for (const tag of [2, 3, 4]) {
    const phase = phases.find(row => row.tag === tag);
    assert(phase.begins === 0 && phase.ends === 0 && phase.active === 0,
      'Only the original pre-business Journal admission failure qualifies');
  }
  for (const tag of [60, 61, 62, 63]) assert.equal(counters.get(tag), 0,
    'Compute inventory overlap or unavailable observation cannot qualify transaction tags');
  assert([0, 2].includes(counters.get(14)), 'Transaction Unknown cannot qualify this refusal');
  const close = phases.find(row => row.tag === 5);
  assert(close.begins > 0 && close.begins === close.ends && close.active === 0 &&
    close.unmatched_end === 0, 'The original failed command must complete its first cleanup');
  return {pid: groups[0].pid, publicFailure: 'LocalSubmissionAcceptanceUnavailable',
    originalCause: 'Journal.CapacityExceeded', firstCommandCleanupObserved: true,
    independentPhysicalAck: false,
    nativeFailedAcceptanceCount: {status: 'unavailable', counterTag: 8,
      reason: 'shared-with-original-read-inventory'}};
}

export async function observeNativeJournalExhaustion({project, cli, assets, libraries,
  runtimeWire, environment}) {
  await mkdir(project, {mode: 0o700});
  const observations = [];
  for (const limit of [1, 2]) {
    const root = join(project, `limit-${limit}`);
    const selected = await prepareNativeNumericOperator({project: root, assets, libraries,
      runtimeWire, maxRows: 16, journalRecordLimit: limit});
    const operator = (args, code = 0) => cli([...selected.configuration, ...args], root, code);
    assert.equal(JSON.parse((await operator(['adopt', '--initialize-signing', '--json'])).stdout).kind,
      'local_host_adopted');
    const retained = [];
    for (let index = 0; index <= limit; index++) {
      const file = `intent-${index}.json`, expected = [{id: index + 1}];
      const document = {version: 'actql/0.1', id: `journal-${limit}-${index}`,
        stages: [{id: 'main', inputs: {}, steps: [{as: 'values', values: {
          schema: {id: {type: 'number', nullable: false}}, rows: expected,
        }}], results: {rows: {from: 'values', fields: ['id']}}}],
        results: {answer0: {from: {stage: 'main', result: 'rows'}}}};
      await writeFile(join(root, file), JSON.stringify(document), {flag: 'wx', mode: 0o600});
      if (index === limit) {
        const flags = ['ACTQL_NATIVE_TIMINGS', 'ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS'];
        const previous = flags.map(key => [key, environment[key]]);
        let refused;
        try {
          for (const key of flags) environment[key] = '1';
          refused = requireNativeJournalCapacityRefusal(await operator(
            ['run', file, '--format', 'json', '--json'], 1));
        } finally {
          for (const [key, value] of previous) {
            if (value === undefined) delete environment[key]; else environment[key] = value;
          }
        }
        observations.push({limit, acceptedSubmissions: retained.length,
          failedFreshSubmissionAttempts: 1, refusal: refused});
        continue;
      }
      const state = JSON.parse((await operator(['run', file, '--format', 'json', '--json'])).stdout);
      assert.equal(state.status, 'succeeded');
      assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
      assert(!retained.some(value => value.runId === state.run_id));
      retained.push({runId: state.run_id, expected});
      await unlink(join(root, file));
    }
    for (const {runId, expected} of retained) {
      const result = await operator(['result', runId, '--result', 'answer0', '--format', 'jsonl']);
      assert.deepEqual(result.stdout.trim().split('\n').map(line => JSON.parse(line)), expected);
    }
    observations.at(-1).allOriginalSavedAfterRefusal = true;
  }
  return {scope: 'explicit-finite-Journal-policy', observations,
    historyDeletion: false, postAdoptionPolicyChange: false};
}

export async function observeNativeNumericOperatorScale({project, cli, assets, libraries, runtimeWire}) {
  const selected = await prepareNativeNumericOperator({project, assets, libraries, runtimeWire, maxRows: 100000});
  const operator = (args, cwd = project, code = 0) => cli([...selected.configuration, ...args], cwd, code);
  const adopted = await operator(['adopt', '--initialize-signing', '--json']);
  assert.equal(JSON.parse(adopted.stdout).kind, 'local_host_adopted');
  // Presentation output must be outside the adopted managed namespace. Keep
  // its original protected boundary; select a distinct owned directory instead.
  const outputDirectory = project + '-output';
  await mkdir(outputDirectory, {mode: 0o700});
  const result = await observeNativeNumericScale({project, cli: operator, outputDirectory});
  // A distinct fresh operator deliberately selects a lower finite row policy.
  // Its original refusal is neither retried nor a reason to weaken enforcement.
  const lowProject = project + '-low-policy';
  const low = await prepareNativeNumericOperator({project: lowProject, assets, libraries, runtimeWire, maxRows: 1});
  const lowCli = (args, code = 0) => cli([...low.configuration, ...args], lowProject, code);
  await lowCli(['adopt', '--initialize-signing', '--json']);
  const small = {version: 'actql/0.1', id: 'numeric-low-policy', stages: [{id: 'main', inputs: {},
    steps: [{as: 'v', values: {schema: {v0: {type: 'number', nullable: false}}, rows: [{v0: 0}, {v0: 1}]}}],
    results: {rows: {from: 'v', fields: ['v0']}}}],
    results: {answer0: {from: {stage: 'main', result: 'rows'}}}};
  await writeFile(join(lowProject, 'low.json'), JSON.stringify(small), {flag: 'wx', mode: 0o600});
  const refused = await lowCli(['run', 'low.json', '--format', 'json', '--json'], 1);
  assert.equal(refused.stdout, ''); assert.equal(refused.signal, null);
  // Statically excessive Values rows are RowsExceeded/InvalidInput in the
  // existing checker; this is distinct from an unclassified preparation failure.
  assert.equal(JSON.parse(refused.stderr).code, 'ACTQL_E_PROGRAM_INVALID');
  return {...result, operator: {environmentCid: selected.environmentCid, maxRows: selected.maxRows,
    lowPolicyRows: low.maxRows, lowPolicyRefused: true}};
}

export function nativeResourceShapeFixtures() {
  const values = (schema, rows) => ({schema, rows: rows.map(row => Object.fromEntries(
    Object.entries(row).map(([key, value]) => [key, typeof value === 'string' ? {literal: value} : value])))});
  const program = (id, steps, fields) => ({version: 'actql/0.1', id,
    stages: [{id: 'main', inputs: {}, steps, results: {rows: {from: 'output', fields}}}],
    results: {answer0: {from: {stage: 'main', result: 'rows'}}}});
  const textSchema = {id: {type: 'number', nullable: false}, text: {type: 'string', nullable: false}};
  const longRows = [{id: 0, text: 'a'.repeat(524288)}, {id: 1, text: 'b'.repeat(524288)}];
  const unicodeRows = ['日本語😀', 'e\u0301', 'é', '"\\\b\f\n\r\t\u0000\u001f', '\u2028\u2029']
    .map((text, id) => ({id, text: text.repeat(128)}));
  const payload = 'expand:'.repeat(585), copies = Array.from({length: 512}, (_, copy) => ({copy}));
  return [
    {id: 'few-long-strings', key: 'id', expectedRows: longRows,
      program: program('few-long-strings', [{as: 'output', values: values(textSchema, longRows)}], ['id', 'text'])},
    {id: 'unicode-escapes', key: 'id', expectedRows: unicodeRows,
      program: program('unicode-escapes', [{as: 'output', values: values(textSchema, unicodeRows)}], ['id', 'text'])},
    {id: 'small-input-large-output', key: 'copy', expectedRows: copies.map(({copy}) => ({text: payload, copy})),
      program: program('small-input-large-output', [
        {as: 'left_rows', values: values({text: {type: 'string', nullable: false}}, [{text: payload}])},
        {as: 'right_rows', values: values({copy: {type: 'number', nullable: false}}, copies)},
        {as: 'output', from: 'left_rows', cross_join: {
          with: 'right_rows', select: {text: 'left.text', copy: 'right.copy'}}},
      ], ['text', 'copy'])},
  ];
}

// JSON Lines delimit records with LF, not Unicode line/paragraph separators.
// Keep stream backpressure and buffer only the current record plus one chunk;
// do not turn the complete Result into an in-memory array of lines.
async function* nativeJsonlLines(input) {
  input.setEncoding('utf8');
  let pending = '';
  for await (const chunk of input) {
    pending += chunk;
    let start = 0, end;
    while ((end = pending.indexOf('\n', start)) !== -1) {
      yield pending.slice(start, end);
      start = end + 1;
    }
    pending = pending.slice(start);
  }
  if (pending.length) yield pending;
}

// Compare every actual delivered scalar, including Unicode normalization and
// escaped controls. Neither a preview nor a digest alone is this oracle.
export async function verifyNativeResourceRows(path, expectedRows, keyField = 'id') {
  const expected = new Map(), seen = new Set();
  for (const row of expectedRows) {
    const key = row[keyField];
    assert(Number.isSafeInteger(key)); assert(!expected.has(key), 'Unique expected resource key required');
    expected.set(key, row);
  }
  const input = createReadStream(path), lines = nativeJsonlLines(input);
  const closed = new Promise(resolve => input.once('close', resolve));
  let rows = 0;
  try {
    for await (const line of lines) {
      assert(rows < expectedRows.length, 'Unexpected extra resource Result row');
      const row = JSON.parse(line);
      assert(row !== null && typeof row === 'object' && !Array.isArray(row), 'Resource Result object required');
      const key = row[keyField];
      assert(expected.has(key), 'Unexpected resource Result key');
      assert(!seen.has(key), 'Duplicate resource Result key');
      assert.deepEqual(row, expected.get(key), `Resource Result key ${key}`);
      seen.add(key); rows++;
    }
  } finally {input.destroy(); await closed;}
  assert.equal(rows, expectedRows.length, 'Complete resource Result required');
  // Every keyed row above has now been compared in full. Hash that verified
  // content in key order, not unspecified product traversal or delivery order.
  const content = createHash('sha256');
  for (const key of [...expected.keys()].sort((a, b) => a - b)) {
    content.update(canonicalText(expected.get(key)) + '\n');
  }
  return {rows, contentSha256: content.digest('hex'), wireBytes: (await lstat(path)).size};
}

export async function observeNativeResourceOperatorShapes({project, cli, assets, libraries, runtimeWire}) {
  const selected = await prepareNativeNumericOperator({project, assets, libraries, runtimeWire, maxRows: 1024});
  const command = async args => {
    const reply = await cli([...selected.configuration, ...args], project);
    assert.equal(reply.code, 0); assert.equal(reply.signal, null);
    return reply;
  };
  assert.equal(JSON.parse((await command(['adopt', '--initialize-signing', '--json'])).stdout).kind,
    'local_host_adopted');
  const outputDirectory = project + '-output';
  await mkdir(outputDirectory, {mode: 0o700});
  const observations = [];
  for (const fixture of nativeResourceShapeFixtures()) {
    const inputName = fixture.id + '.json', input = join(project, inputName);
    const wire = JSON.stringify(fixture.program), inputWireBytes = Buffer.byteLength(wire);
    if (fixture.id === 'few-long-strings') assert(inputWireBytes > 1048576);
    const first = join(outputDirectory, fixture.id + '-first.jsonl');
    const saved = join(outputDirectory, fixture.id + '-saved.jsonl');
    await writeFile(input, wire, {flag: 'wx', mode: 0o600});
    const original = JSON.parse((await command(['run', inputName, '--format', 'json', '--json'])).stdout);
    assert.equal(original.version, 'actql-run-state/0.1');
    assert.equal(original.status, 'succeeded');
    assert.equal(typeof original.run_id, 'string'); assert(original.run_id.length > 0);
    await command(['result', original.run_id, '--result', 'answer0', '--format', 'jsonl', '--output', first]);
    const firstRows = await verifyNativeResourceRows(first, fixture.expectedRows, fixture.key);
    if (fixture.id === 'few-long-strings') {
      assert.equal(firstRows.rows, 2); assert(firstRows.wireBytes > 1048576);
    }
    await unlink(input);
    const restored = JSON.parse((await command(['status', original.run_id, '--json'])).stdout);
    assert.deepEqual([restored.version, restored.run_id, restored.status],
      [original.version, original.run_id, original.status]);
    await command(['result', original.run_id, '--result', 'answer0', '--format', 'jsonl', '--output', saved]);
    const savedRows = await verifyNativeResourceRows(saved, fixture.expectedRows, fixture.key);
    assert.equal(savedRows.contentSha256, firstRows.contentSha256);
    if (fixture.id === 'small-input-large-output') {
      assert(inputWireBytes < 16384); assert(firstRows.wireBytes > 1048576);
      assert(firstRows.wireBytes > 100 * inputWireBytes);
    }
    observations.push({id: fixture.id, runId: original.run_id, inputWireBytes,
      first: firstRows, saved: savedRows, inputRemovedBeforeSaved: true});
  }
  return {scope: 'installed-native-json-source-resource-shapes', observations,
    operator: {environmentCid: selected.environmentCid, maxRows: selected.maxRows},
    cleanup: 'successful Native command cleanup before reply and process exit',
    independentFdInspection: false};
}

// Registry close permits provisional observations only. The consumer must still
// exit and complete owned-scratch cleanup before the parent can publish success.
export async function finishSourceFreeObservations(receipt, primaryFailure,
  {close, saveObserved, saveFailed}) {
  let failure = primaryFailure;
  try { await close(); }
  catch (error) {
    failure = failure === undefined ? error
      : new AggregateError([failure, error], 'Source-free acceptance and registry cleanup failed');
  }
  if (failure !== undefined) {
    try { await saveFailed(failure); }
    catch (error) { throw new AggregateError([failure, error], 'Source-free failure evidence could not be saved'); }
    throw failure;
  }
  assert(receipt, 'Completed source-free observations required');
  await saveObserved({...receipt, status: 'observed', registryClosed: true});
}

const unsupportedBindings = 'actql: The installed Native runtime does not implement the selected project bindings; no project files were created.\n';

async function unchangedDirectory(path) {
  const state = await lstat(path, {bigint: true});
  assert(state.isDirectory() && !state.isSymbolicLink());
  return {entries: (await readdir(path)).sort(), ...Object.fromEntries(
    ['dev', 'ino', 'mode', 'mtimeNs', 'ctimeNs'].map(key => [key, String(state[key])]))};
}

async function requireAbsent(path) {
  try { await lstat(path); assert.fail(`Unexpected initialized target: ${path}`); }
  catch (error) {if (error.code !== 'ENOENT') throw error;}
}

// Query the actual installed implementation without creating a Project. A
// supported Mock reply is not Mock execution evidence for this source-free
// consumer. An unsupported reply still requires every original no-write case.
export async function observeNativeInitializationSupport({root, cli}) {
  const queryParent = join(root, 'query-no-write');
  await mkdir(queryParent, {mode: 0o700});
  const queryBefore = await unchangedDirectory(queryParent);
  const configuration = join(queryParent, 'actql.config.json'), state = join(queryParent, 'state');
  await requireAbsent(configuration); await requireAbsent(state);
  const query = await cli(['--config', configuration, '--state-dir', state, 'project-init-support'], queryParent);
  assert.equal(query.code, 0); assert.equal(query.signal, null); assert.equal(query.stderr, '');
  await requireAbsent(configuration); await requireAbsent(state);
  const queryAfter = await unchangedDirectory(queryParent);
  assert.deepEqual(queryAfter, queryBefore);
  const support = JSON.parse(query.stdout);
  assert.equal(typeof support.mock, 'boolean');
  assert.deepEqual(support, {version: 'actql-project-init-support/0.1', sourceFree: true, mock: support.mock});
  if (support.mock) return {scope: 'mock-implementation-available-execution-unmeasured', support,
    query: {configuration, state, before: queryBefore, after: queryAfter}, cases: []};
  const cases = [];
  for (const template of ['deal-review-mock', 'churn-risk-mock']) {
    const parent = join(root, `refused-${template}`), empty = join(parent, 'empty');
    await mkdir(parent, {mode: 0o700}); await mkdir(empty, {mode: 0o700});
    const originalParent = await unchangedDirectory(parent), originalEmpty = await unchangedDirectory(empty);
    assert.deepEqual(originalParent.entries, ['empty']); assert.deepEqual(originalEmpty.entries, []);
    for (const targetState of ['new', 'empty']) for (let iteration = 1; iteration <= 2; iteration++) {
      const target = join(parent, targetState);
      if (targetState === 'new') await requireAbsent(target);
      const result = await cli(['init', '--template', template, targetState], parent, 69);
      assert.equal(result.code, 69); assert.equal(result.signal, null);
      assert.equal(result.stdout, ''); assert.equal(result.stderr, unsupportedBindings);
      if (targetState === 'new') await requireAbsent(target);
      const retainedParent = await unchangedDirectory(parent), retainedEmpty = await unchangedDirectory(empty);
      assert.deepEqual(retainedParent, originalParent); assert.deepEqual(retainedEmpty, originalEmpty);
      cases.push({template, targetState, iteration, target,
        parentBefore: originalParent, parentAfter: retainedParent,
        emptyBefore: originalEmpty, emptyAfter: retainedEmpty, newTargetAbsent: true});
    }
  }
  return {scope: 'unsupported-mock-initialization-refusal-only', support,
    query: {configuration, state, before: queryBefore, after: queryAfter}, cases};
}

// Catalog metadata alone remains a Mock binding request. This control is a
// refusal before reading its absent inputs, not Mock execution acceptance.
export async function observeCatalogOnlyMockRefusal({root, cli}) {
  const directory = join(root, 'refused-catalog-only');
  await mkdir(directory, {mode: 0o700});
  const configuration = join(directory, 'actql.config.json'), state = join(directory, 'state');
  const absent = [state, join(directory, 'never-opened.json'),
    join(directory, 'never-opened-connectors.json'), join(directory, 'never-read.aql')];
  await writeFile(configuration, JSON.stringify({version: 'actql-config/0.1',
    mock: {catalog: 'never-opened.json'}, connectors: 'never-opened-connectors.json'}) + '\n',
  {flag: 'wx', mode: 0o600});
  const retainedConfiguration = async () => {
    const metadata = await lstat(configuration, {bigint: true});
    assert(metadata.isFile() && !metadata.isSymbolicLink());
    return {sha256: createHash('sha256').update(await readFile(configuration)).digest('hex'),
      ...Object.fromEntries(['dev', 'ino', 'mode', 'size', 'mtimeNs', 'ctimeNs']
        .map(key => [key, String(metadata[key])]))};
  };
  const before = await unchangedDirectory(directory), configurationBefore = await retainedConfiguration();
  for (const path of absent) await requireAbsent(path);
  const result = await cli(['--config', configuration, '--state-dir', state, 'check', 'never-read.aql'], directory, 1);
  assert.equal(result.code, 1); assert.equal(result.signal, null); assert.equal(result.stdout, '');
  assert.equal(result.stderr, 'actql-native-client: LocalProjectBindingsUnavailable\n');
  for (const path of absent) await requireAbsent(path);
  const after = await unchangedDirectory(directory), configurationAfter = await retainedConfiguration();
  assert.deepEqual(after, before); assert.deepEqual(configurationAfter, configurationBefore);
  return {scope: 'catalog-only-mock-binding-refusal-only', configuration, state,
    before, after, configurationBefore, configurationAfter, absent};
}

export async function observeTimingEnabledPlainInitialization({root, cli, environment}) {
  const original = environment.ACTQL_NATIVE_TIMINGS;
  let result;
  try {
    environment.ACTQL_NATIVE_TIMINGS = '1';
    result = await cli(['init', 'project'], root);
  } finally {
    if (original === undefined) delete environment.ACTQL_NATIVE_TIMINGS;
    else environment.ACTQL_NATIVE_TIMINGS = original;
  }
  assert.equal(result.code, 0); assert.equal(result.signal, null);
  assert.match(result.stdout, /^Local Host adopted; no Run has been admitted\.\nAccount: local-cli\nAdoption: sha256:[a-f0-9]{64}\n$/u);
  const diagnostics = result.stderr.trimEnd().split('\n').map(line => {
    const match = /^(ACTQL_NATIVE_(?:TIMINGS|PHASE|COUNTER|LAUNCHER_TIMINGS)) (\{.*\})$/u.exec(line);
    assert(match, `Unexpected timing-enabled initialization diagnostic: ${line}`);
    return {marker: match[1], value: JSON.parse(match[2])};
  });
  const native = diagnostics.filter(value => value.marker === 'ACTQL_NATIVE_TIMINGS');
  const launcher = diagnostics.filter(value => value.marker === 'ACTQL_NATIVE_LAUNCHER_TIMINGS');
  assert.equal(native.length, 1); assert.equal(launcher.length, 1);
  assert.equal(native[0].value.origin, 'first_hook');
  assert.equal(native[0].value.child_process_counters, false);
  assert(Number.isSafeInteger(native[0].value.pid) && native[0].value.pid > 0);
  assert.equal(launcher[0].value.units, 'nanoseconds');
  for (const key of ['preparation', 'child', 'total']) assert(Number.isSafeInteger(launcher[0].value[key]) && launcher[0].value[key] >= 0);
  return {scope: 'plain-initialization-with-diagnostics', diagnostics};
}

// A failed ordinary request is never retried. This independent actor uses the
// same verified installation with fresh project/home/state and one new request.
export async function observeFreshSubmissionFailureDiagnostic({root, cli, environment}) {
  await mkdir(root, {mode: 0o700});
  const saved = Object.fromEntries(['HOME', 'TMPDIR', 'ACTQL_NATIVE_TIMINGS']
    .map(key => [key, environment[key]]));
  try {
    for (const name of ['home', 'tmp']) await mkdir(join(root, name), {mode: 0o700});
    environment.HOME = join(root, 'home'); environment.TMPDIR = join(root, 'tmp');
    environment.ACTQL_NATIVE_TIMINGS = '1';
    await cli(['init', 'project'], root);
    const result = await cli(['sql', 'SELECT 2 AS id', '--format', 'jsonl'], root);
    assert.deepEqual(result.stdout.trim().split('\n').map(line => JSON.parse(line)), [{id: 2}]);
    return {scope: 'fresh-submission-failure-diagnostic-only', newRequests: 1,
      commandSucceeded: true, ordinaryAcceptance: false};
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete environment[key]; else environment[key] = value;
    }
  }
}

export async function preserveOrdinaryFailureWithDiagnostic(primary, diagnose) {
  try {
    return {failure: primary, diagnostic: {status: 'observed', ...await diagnose()}};
  } catch (error) {
    return {failure: new AggregateError([primary, error],
      'Ordinary Local failure and independent diagnostic failure'),
    diagnostic: {status: 'failed', error: error.message}};
  }
}

async function observeInstalledSourceFree(input, observationPath) {
  const directory = resolve(input), manifest = await verifyNativeCliRelease(directory);
  const source = checkoutState(repository);
  assert(source.clean && source.revision === manifest.sourceSha, 'Exact clean fixed source required');
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  const expected = manifest.artifacts.find(value => value.platform === platform);
  assert(expected?.localRuntime, 'Source-free installed acceptance requires a real Local runtime artifact');
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-source-free-install-',
    label: 'Native source-free Local external installation'});
  const root = scratch.path, prefix = join(root, 'global'), project = join(root, 'project'), records = [];
  const registry = await openReleaseTestRegistry([{directory, manifest}]);
  const env = {...process.env};
  for (const key of Object.keys(env)) if (/^npm_config_/iu.test(key) || /^(?:ACTQL_|DYLD_)/u.test(key) ||
    ['NODE_PATH', 'NODE_OPTIONS', 'LD_PRELOAD', 'LD_LIBRARY_PATH', 'MOON_HOME'].includes(key)) delete env[key];
  Object.assign(env, {HOME: join(root, 'home'), TMPDIR: join(root, 'tmp'),
    npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
    npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
    npm_config_proxy: '', npm_config_https_proxy: '', npm_config_update_notifier: 'false',
    NO_PROXY: '127.0.0.1,localhost'});
  const execute = promisify(execFile);
  async function run(command, args, cwd = root, expectedCode = 0) {
    const started = Date.now();
    let result;
    try {
      result = {...await execute(command, args, {cwd, env, timeout: 180_000,
        killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024}), code: 0, signal: null};
    } catch (error) {
      result = {code: error.code ?? null, signal: error.signal ?? null,
        killed: error.killed ?? false, stdout: error.stdout ?? '', stderr: error.stderr ?? ''};
    }
    const record = {command, args, cwd, elapsedMs: Date.now() - started, ...result};
    records.push(record);
    await writeFile(join(root, 'commands.json'), `${JSON.stringify(records, null, 2)}\n`);
    assert.equal(record.code, expectedCode, `${command}: ${record.code}/${record.signal}\n${record.stdout}\n${record.stderr}`);
    assert.equal(record.signal, null);
    return record;
  }
  const rows = text => text.trim().split('\n').map(line => JSON.parse(line));
  let receipt, failure, failureDiagnostic, diagnoseFailure, runIngress, verifyInstalledOriginals;
  try {
    for (const path of [prefix, env.HOME, env.TMPDIR, join(root, 'empty-path')]) await mkdir(path);
    await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
    await writeFile(join(root, 'npmrc-global'), '');
    await run('npm', ['install', '-g', '--prefix', prefix, '--ignore-scripts', '--no-audit', '--no-fund',
      `actql@${manifest.cohort.packageVersion}`]);
    const installed = join(prefix, 'lib/node_modules/actql'), launcher = join(prefix, 'bin/actql');
    assert.deepEqual((await readdir(join(installed, 'node_modules/@actql'))).sort(), [`cli-${platform}`]);
    const platformRoot = join(installed, 'node_modules/@actql', `cli-${platform}`);
    const artifact = JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8'));
    assert.deepEqual(artifact, expected);
    const originalBinary = await readFile(join(platformRoot, 'bin/actql-native-client'));
    assert.equal(originalBinary.length, expected.binaryBytes);
    assert.equal(createHash('sha256').update(originalBinary).digest('hex'), expected.binarySha256);
    verifyInstalledOriginals=async()=>{
      assert.deepEqual(await readFile(join(platformRoot, 'bin/actql-native-client')), originalBinary);
      assert.deepEqual(checkoutState(repository), source);
    };
    // Reuse this same installed cohort and its actual launcher/runtime. The
    // Remote-only CLI harness cannot supply the Local preparation constructor.
    const localRuntime=admitInstalledLocalRuntime({root:platformRoot,metadata:artifact.localRuntime,
      expected:{sourceSha:manifest.sourceSha,platform,localRuntimeSha256:artifact.localRuntime.sha256}});
    runIngress=async()=>{
      env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER=launcher;
      env.ACTQL_TEST_NATIVE_CLIENT_BINARY=join(platformRoot,'bin/actql-native-client');
      for(const [role,key] of [['sqlite','ACTQL_TEST_NATIVE_SQLITE_LIBRARY'],
        ['crypto','ACTQL_TEST_NATIVE_CRYPTO_LIBRARY']]) {
        const library=localRuntime.libraries.find(value=>value.role===role);assert(library);
        env[key]=join(platformRoot,library.path);
      }
      const focused=new URL('./test-execution.mjs',import.meta.url).href;
      const fixture=fileURLToPath(new URL('./test-native-local-cli.test.mjs',import.meta.url));
      await run(process.execPath,['--input-type=module','-e',
        `import {runFocusedTests} from ${JSON.stringify(focused)};process.exitCode=runFocusedTests('node',[${JSON.stringify(fixture)}],{cwd:process.cwd(),expectedTests:12});`]);
    };
    // Node launches only the installed npm entry. Neither it nor the Native child
    // can discover a compiler, a repository executable, a provider or a Node Host.
    env.PATH = join(root, 'empty-path');
    const cli = (args, cwd = project, code = 0) => run(process.execPath, [launcher, ...args], cwd, code);
    // Observe the SAME required commands; never add another submission merely
    // to count work. Invalid-input controls retain their original failure path.
    const sourceFreeCli = (args, cwd = project, code = 0) => code === 0 && ['check', 'run', 'sql', 'result'].includes(args[0])
      ? observeNativeSourceFreeCommand({args, cwd, cli, environment: env}) : cli(args, cwd, code);
    diagnoseFailure = () => observeFreshSubmissionFailureDiagnostic({
      root: join(root, 'submission-failure-diagnostic'), cli, environment: env});
    assert.equal((await cli(['--version'], root)).stdout, `${manifest.cohort.packageVersion}\n`);
    const mockInitialization = await observeNativeInitializationSupport({root, cli});
    const catalogOnlyMockRefusal = await observeCatalogOnlyMockRefusal({root, cli});
    const plainInitialization = await observeTimingEnabledPlainInitialization({root, cli, environment: env});
    assert.equal(env.ACTQL_NATIVE_TIMINGS, undefined);
    assert.equal(JSON.parse(await readFile(join(project, 'actql.config.json'))).profile, undefined);
    const defaultNumeric = await observeNativeDefaultNumericQueries({project, cli: sourceFreeCli});
    const defaultUnionMetadata = await observeNativeDefaultUnionMetadata({root, cli: sourceFreeCli});
    const fileSourceNumeric = await observeNativeFileSourceNumeric({root, cli});
    const fileTaskBoundary = await observeNativeFileTaskBoundary({root, cli, environment: env});
    await writeFile(join(project, 'query.sql'), 'SELECT 1 AS id\n');
    const help = (await cli(['--help'])).stdout;
    assert.match(help, /Usage: actql/u);
    assert.doesNotMatch(help, /actql-native-client/u);
    assert.match(help, /Validate a Program without reading business data/u);
    const checkText = (await cli(['check', 'query.sql', '--format', 'sql'])).stdout;
    assert.match(checkText, /Validation: Valid\nRunnable: yes/u);
    assert.doesNotMatch(checkText, /sha256:|"outcome"/u);
    const checked = JSON.parse((await sourceFreeCli(['check', 'query.sql', '--format', 'sql', '--json'])).stdout);
    assert.equal(checked.version, 'actql-check-outcome/0.1');
    assert.equal(checked.outcome, 'completed');
    assert.equal(checked.report.verdict, 'verified');
    assert.equal(checked.report.runnable.verdict, 'yes');
    const explained = JSON.parse((await cli(['explain', 'query.sql', '--format', 'sql', '--json'])).stdout);
    assert.equal(explained.version, 'actql-plan-view/0.1');
    const explainText = (await cli(['explain', 'query.sql', '--format', 'sql'])).stdout;
    assert.match(explainText, /Plan: [1-9][0-9]* logical steps/u);
    assert.match(explainText, /1\. values/u);
    assert.doesNotMatch(explainText, /sha256:/u);
    const explainDetail = (await cli(['explain', 'query.sql', '--format', 'sql', '--verbose'])).stdout;
    assert.match(explainDetail, /Compiled computation: "sha256:/u);
    const explainJsonVerbose = JSON.parse((await cli(['explain', 'query.sql', '--format', 'sql', '--json', '--verbose'])).stdout);
    assert.deepEqual(explainJsonVerbose, explained);

    assert.deepEqual(rows((await sourceFreeCli(['sql', 'SELECT 2 AS id', '--format', 'jsonl'])).stdout), [{id: 2}]);
    const state = JSON.parse((await sourceFreeCli(['run', 'query.sql', '--format', 'sql', '--json'])).stdout);
    assert.equal(state.version, 'actql-run-state/0.1');
    assert.equal(state.status, 'succeeded');
    assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
    // Subsequent processes must use retained Run/Result originals, not reexecute
    // the now-absent source file or manufacture a fresh successful Run.
    await unlink(join(project, 'query.sql'));
    const savedExplain = (await cli(['explain', '--run', state.run_id])).stdout;
    assert.match(savedExplain, /ActQL EXPLAIN · saved Run/u);
    assert.match(savedExplain, /Plan: [1-9][0-9]* logical steps/u);
    assert.doesNotMatch(savedExplain, /Compiled computation:|Logical map:/u);
    const savedDetail = (await cli(['explain', '--run', state.run_id, '--verbose'])).stdout;
    assert.match(savedDetail, /Compiled computation: "sha256:/u);
    const savedJson = JSON.parse((await cli(['explain', '--run', state.run_id, '--json'])).stdout);
    const savedJsonVerbose = JSON.parse((await cli(['explain', '--run', state.run_id, '--json', '--verbose'])).stdout);
    assert.equal(savedJson.version, 'actql-run-plan-view/0.1');
    assert.deepEqual(savedJsonVerbose, savedJson);
    await writeFile(join(project, 'invalid.sql'), 'SELECT\r)');
    const invalidCheck = await cli(['check', 'invalid.sql', '--format', 'sql'], project, 1);
    assert.match(invalidCheck.stdout, /Validation: Invalid\nRunnable: no/u);
    assert.match(invalidCheck.stdout, /query_syntax_invalid: The query syntax is invalid\./u);
    assert.match(invalidCheck.stdout, /At source: line 2, byte 1/u);

    for (let count = 0; count < 2; count++) {
      const saved = JSON.parse((await cli(['status', state.run_id, '--json'])).stdout);
      assert.equal(saved.run_id, state.run_id); assert.equal(saved.status, 'succeeded');
      assert.deepEqual(rows((await sourceFreeCli(['result', state.run_id, '--format', 'jsonl'])).stdout), [{id: 1}]);
    }
    await cli(['result', state.run_id, '--format', 'jsonl', '--output', 'saved.jsonl']);
    assert.deepEqual(rows(await readFile(join(project, 'saved.jsonl'), 'utf8')), [{id: 1}]);
    const numericAssets = {};
    for (const asset of localRuntime.assets) {
      numericAssets[asset.role] = await readFile(join(platformRoot, asset.path), 'utf8');
    }
    const numericLibraries = Object.fromEntries(localRuntime.libraries.map(item =>
      [item.role, join(platformRoot, item.path)]));
    const journalExhaustion = await observeNativeJournalExhaustion({project: join(root, 'journal-exhaustion'),
      cli, assets: numericAssets, libraries: numericLibraries, environment: env,
      runtimeWire: await readFile(join(platformRoot, artifact.localRuntime.path), 'utf8')});
    const numericScale = await observeNativeNumericOperatorScale({project: join(root, 'numeric-operator'),
      cli, assets: numericAssets, libraries: numericLibraries,
      runtimeWire: await readFile(join(platformRoot, artifact.localRuntime.path), 'utf8')});
    const resourceShapes = await observeNativeResourceOperatorShapes({project: join(root, 'resource-operator'),
      cli, assets: numericAssets, libraries: numericLibraries,
      runtimeWire: await readFile(join(platformRoot, artifact.localRuntime.path), 'utf8')});
    receipt = {version: 'actql-native-cli-install-acceptance/0.1', scope: 'source-free-local',
      cliSourceSha: manifest.sourceSha, platform, node: process.version, glibc: glibc ?? null,
      artifact, scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex'),
      cliPackages: manifest.packages.map(({name, version, sha256}) => ({name, version, sha256})),
      registry: 'private-loopback-fixed-RC', registryRequests: registry.requested,
      mockInitialization, catalogOnlyMockRefusal, plainInitialization, defaultNumeric, defaultUnionMetadata, fileSourceNumeric, fileTaskBoundary,
      journalExhaustion, numericScale, resourceShapes,
      sourceFreeWork: records.filter(record => record.sourceFreeWork).map(record => record.sourceFreeWork),
      publicRegistryPublication: 'not-tested', records,
      unverified: ['Mock or live Connector bindings', 'Model inference', 'Effect approval', 'other platforms']};
  } catch (error) {
    failure = error;
    if (diagnoseFailure && /LocalSubmissionAcceptanceUnknown/u.test(error.message)) {
      const observed = await preserveOrdinaryFailureWithDiagnostic(error, diagnoseFailure);
      failure = observed.failure; failureDiagnostic = observed.diagnostic;
    }
  }
  // Independent Local controls share only the verified installed cohort. A
  // business-case failure cannot hide their result, and either failure rejects
  // the consumer before its existing registry/physical cleanup certification.
  if(runIngress) {
    try {await runIngress();}
    catch(error) {failure=failure===undefined?error:
      new AggregateError([failure,error],'Installed Local execution and ingress failed');}
  }
  // The original before/after fences cover both independent case groups,
  // including their failure continuations, before any observation is accepted.
  if(verifyInstalledOriginals) {
    try {await verifyInstalledOriginals();}
    catch(error) {failure=failure===undefined?error:
      new AggregateError([failure,error],'Installed Local cases and original correspondence failed');}
  }
  await finishSourceFreeObservations(receipt, failure, {
    close: () => registry.close(),
    saveObserved: value => writeFile(observationPath,
      `${JSON.stringify({...value, consumer: root}, null, 2)}\n`, {flag: 'wx'}),
    saveFailed: error => writeFile(join(directory, `source-free-install-failed-${platform}-${Date.now()}.json`),
      `${JSON.stringify({version: 'actql-native-cli-install-acceptance/0.1', scope: 'source-free-local',
        cliSourceSha: manifest.sourceSha, platform, status: 'failed', error: error.message,
        failures: (error instanceof AggregateError ? error.errors : [error]).map(value => value.message),
        consumer: root, records, failureDiagnostic}, null, 2)}\n`, {flag: 'wx'}),
  });
  scratch.passed();
}

// This parent has no owned-scratch exit handler. An observed receipt is not
// acceptance: the real child's exit status and original directory absence are
// both required. Tests exercise this same boundary with real child cleanup.
export async function runCleanupConditionedConsumer({command, args, observationPath,
  receiptPath, failurePath, expected, env = process.env, timeout = 600_000}) {
  let child, observation, failure;
  try {
    child = {...await promisify(execFile)(command, args, {env, timeout,
      killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024}), code: 0, signal: null};
  } catch (error) {
    failure = error;
    child = {code: error.code ?? null, signal: error.signal ?? null,
      stdout: error.stdout ?? '', stderr: error.stderr ?? ''};
  }
  try {
    observation = JSON.parse(await readFile(observationPath, 'utf8'));
    if (failure === undefined) {
      assert.equal(observation.status, 'observed');
      assert.equal(observation.registryClosed, true);
      for (const [key, value] of Object.entries(expected)) assert.deepEqual(observation[key], value);
      assert(isAbsolute(observation.consumer), 'Original consumer directory required');
      try {
        await lstat(observation.consumer);
        assert.fail('Consumer scratch remains after child exit');
      } catch (error) {if (error.code !== 'ENOENT') throw error;}
      // Remove provisional DATA before writing success, so no later cleanup
      // obligation can retroactively turn this receipt into a false pass.
      await unlink(observationPath);
    }
  } catch (error) {failure ??= error;}
  if (failure !== undefined) {
    await writeFile(failurePath, `${JSON.stringify({...expected, status: 'failed',
      error: failure.message, child, consumer: observation?.consumer,
      records: observation?.records}, null, 2)}\n`, {flag: 'wx'});
    throw failure;
  }
  const receipt = {...observation, status: 'passed', scratchRemoved: true, consumerProcess: child};
  await writeFile(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  return receipt;
}

export async function acceptInstalledSourceFree(input) {
  const directory = resolve(input), manifest = await verifyNativeCliRelease(directory);
  const source = checkoutState(repository);
  assert(source.clean && source.revision === manifest.sourceSha, 'Exact clean fixed source required');
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  const artifact = manifest.artifacts.find(value => value.platform === platform);
  assert(artifact?.localRuntime, 'Source-free installed acceptance requires a real Local runtime artifact');
  const stamp = `${platform}-${Date.now()}-${randomUUID()}`;
  const observationPath = join(directory, `source-free-observed-${stamp}.json`);
  const receiptPath = join(directory, `source-free-install-${stamp}.json`);
  await runCleanupConditionedConsumer({command: process.execPath,
    args: [fileURLToPath(import.meta.url), '--consumer', directory, observationPath],
    observationPath, receiptPath, failurePath: join(directory, `source-free-install-failed-${stamp}.json`),
    expected: {version: 'actql-native-cli-install-acceptance/0.1', scope: 'source-free-local',
      cliSourceSha: manifest.sourceSha, platform, artifact,
      scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex')}});
  console.log(`Installed Native source-free Local passed: ${receiptPath}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [first, ...rest] = process.argv.slice(2);
  if (first === '--consumer') {
    assert(rest.length === 2 && isAbsolute(rest[1]), 'Explicit private consumer observation path required');
    await observeInstalledSourceFree(rest[0], rest[1]);
  } else {
    assert(first && rest.length === 0, 'usage: test-native-cli-source-free-install.mjs <fixed-CLI-RC>');
    await acceptInstalledSourceFree(first);
  }
}
