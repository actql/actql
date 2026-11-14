import assert from 'node:assert/strict';
import {readFile, writeFile, unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {nativeLauncherEnvelope} from './native-cli-mock-scenario.mjs';

// Authored rows, not expected values inferred from a preview or an aggregate.
export const nativeUnionRowCases = Object.freeze(['direct', 'cte'].flatMap(form =>
  [10, 11, 24, 25, 40].flatMap(branches => [false, true].map(duplicates => Object.freeze({
    form, branches, duplicates,
    rows: Object.freeze(Array.from({length: branches}, (_, i) => Object.freeze({n: duplicates ? i % 3 : i}))),
  })))));

export function nativeUnionRowSql(entry) {
  assert(nativeUnionRowCases.includes(entry));
  const body = entry.rows.map(({n}) => `SELECT ${n} AS n`).join(' UNION ALL ');
  return entry.form === 'direct' ? body : `WITH t AS (${body}) SELECT n FROM t`;
}

function completeRows(text, expected) {
  const rows = text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  for (const row of rows) {
    assert.deepEqual(Object.keys(row), ['n'], 'Exact one-column Result shape required');
    assert(Number.isSafeInteger(row.n), 'The original nonnull Number field must survive');
  }
  // UNION ALL retains every occurrence. Do not require an undeclared SQL sort.
  assert.deepEqual(rows.map(({n}) => n).sort((a, b) => a - b),
    expected.map(({n}) => n).sort((a, b) => a - b));
}

function firstClose(record) {
  assert.equal(record.code, 0); assert.equal(record.signal, null);
  const pid = record.sourceFreeWork?.pid;
  assert(Number.isSafeInteger(pid) && pid > 0, 'Existing original process/work observation required');
  const {native} = nativeLauncherEnvelope(record.stderr, 'required');
  const phases = native.split('\n').filter(line => line.startsWith('ACTQL_NATIVE_PHASE '))
    .map(line => JSON.parse(line.slice('ACTQL_NATIVE_PHASE '.length))).filter(row => row.tag === 5);
  assert.equal(phases.length, 1);
  assert.equal(phases[0].begins, 1); assert.equal(phases[0].ends, 1);
  assert.equal(phases[0].active, 0); assert.equal(phases[0].unmatched_end, 0);
  return pid; // First command cleanup observation, not independent physical ACK.
}

export async function observeNativeUnionRows({root, cli}) {
  const project = join(root, 'ordinary-union-rows');
  await cli(['init', project], root);
  const originalConfiguration = await readFile(join(project, 'actql.config.json'), 'utf8');
  assert.equal(JSON.parse(originalConfiguration).profile, undefined);
  const observations = [], runIds = new Set();
  for (const entry of nativeUnionRowCases) {
    const file = `union-${entry.form}-${entry.branches}-${entry.duplicates ? 'duplicates' : 'unique'}.sql`;
    await writeFile(join(project, file), nativeUnionRowSql(entry), {flag: 'wx', mode: 0o600});
    const checked = await cli(['check', file, '--format', 'sql', '--json'], project);
    firstClose(checked);
    const report = JSON.parse(checked.stdout);
    assert.equal(report.outcome, 'completed'); assert.equal(report.report?.verdict, 'verified');
    assert.equal(report.report?.runnable?.verdict, 'yes');
    const started = await cli(['run', file, '--format', 'sql', '--json'], project);
    const startPid = firstClose(started), state = JSON.parse(started.stdout);
    assert.equal(state.version, 'actql-run-state/0.1'); assert.equal(state.status, 'succeeded');
    assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0 && !runIds.has(state.run_id));
    runIds.add(state.run_id);
    const live = await cli(['result', state.run_id, '--format', 'jsonl'], project);
    firstClose(live); completeRows(live.stdout, entry.rows);
    const csv = await cli(['result', state.run_id, '--format', 'csv'], project);
    firstClose(csv);
    const [header, ...values] = csv.stdout.trim().split(/\r?\n/u);
    assert.equal(header, '"n"', 'CSV exposes exactly the same original column');
    assert(values.every(value => /^(?:0|[1-9][0-9]*)$/u.test(value)),
      'Every CSV cell retains the original nonnull integer, including zero');
    assert.deepEqual(values.map(Number).sort((a, b) => a - b), entry.rows.map(({n}) => n).sort((a, b) => a - b));
    await unlink(join(project, file));
    const rejected = await cli(['sql', 'SELECT )', '--format', 'json', '--json'], project, 1);
    assert.equal(rejected.stdout, ''); assert.equal(rejected.signal, null);
    assert.equal(JSON.parse(rejected.stderr).code, 'ACTQL_E_PROGRAM_INVALID');
    const recovered = await cli(['sql', 'SELECT 9821 AS n', '--format', 'jsonl'], project);
    firstClose(recovered); completeRows(recovered.stdout, [{n: 9821}]);
    const cold = await cli(['result', state.run_id, '--format', 'jsonl'], project);
    assert.notEqual(firstClose(cold), startPid, 'Cold Saved uses a different actual Native process');
    completeRows(cold.stdout, entry.rows);
    assert.equal(cold.stdout, live.stdout, 'Saved retains exact committed row bytes without the SQL input');
    assert.equal(await readFile(join(project, 'actql.config.json'), 'utf8'), originalConfiguration);
    observations.push({form: entry.form, branches: entry.branches, duplicates: entry.duplicates,
      runId: state.run_id, rows: entry.rows.length, observedColumns: ['n'],
      firstCloseObserved: true, physicalAckIndependentlyObserved: false,
      recoveredAfterInvalidQuery: true, coldSavedWithoutInput: true});
  }
  return {profile: 'ordinary-unmodified-init', cases: observations};
}

// The caller supplies its already-admitted, explicitly smaller row policy.
// This is static RowsExceeded/InputInvalid, not a same-parent memory/work
// shortage or evidence of its dimension. The ordinary project stays unchanged.
export async function observeNativeUnionRowPolicy({project, cli}) {
  await writeFile(join(project, 'union-low.sql'), 'SELECT 0 AS n UNION ALL SELECT 1 AS n', {flag: 'wx', mode: 0o600});
  const refused = await cli(['run', 'union-low.sql', '--format', 'sql', '--json'], project, 1);
  assert.equal(refused.stdout, ''); assert.equal(refused.signal, null);
  assert.equal(JSON.parse(refused.stderr).code, 'ACTQL_E_PROGRAM_INVALID');
  const recovered = await cli(['sql', 'SELECT 83 AS n', '--format', 'jsonl'], project);
  completeRows(recovered.stdout, [{n: 83}]);
  return {explicitRowPolicy: 1, originalRejectedRows: 2, recoveryRows: [{n: 83}],
    classification: 'static-row-policy-input-invalid', sameParentBudgetRefusal: 'not-tested',
    recoveryFirstCloseObserved: false, physicalAckIndependentlyObserved: false};
}
