import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {selectReleaseTemporalJoinQueryCases} from './release-temporal-join-query-cases.mjs';
import {selectInstalledSourcefreeQuerySuite} from './release-sourcefree-query-cases.mjs';
import {temporalJoinSourceSuccesses as successes, temporalJoinSourceRefusals as refusals}
  from './fixtures/temporal-join-source-input.mjs';
import {sourcefreeFixtureAuthorization} from './fixtures/release-sourcefree-authorization.mjs';
import {auditTemporalJoinTransport} from '../reviews/2026-10-14-temporal-join-release-matrix/public-audit.mjs';

test('temporal release preserves all original JSON SQL AQL controls, NULLs and operation ceilings', () => {
  const before = JSON.stringify({successes, refusals});
  const cases = selectReleaseTemporalJoinQueryCases();
  assert.deepEqual(selectInstalledSourcefreeQuerySuite('temporal-join'), cases);
  assert.equal(cases.successes.length, 12); assert.equal(cases.refusals.length, 9);
  for (const [index, item] of cases.successes.entries()) assert.equal(item, successes[index]);
  for (const [index, item] of cases.refusals.entries()) assert.equal(item, refusals[index]);
  for (const [index, rows] of [[0, [{id: 1, value: 7}, {id: 2, value: 8}, {id: 3, value: null}]],
    [3, [{id: 1, value: 7}, {id: 2, value: 8}]],
    [6, [{id: 1, value: 7}, {id: 2, value: null}, {id: 3, value: null}]],
    [9, [{id: 1, value: 7}]]]) {
    for (const item of cases.successes.slice(index, index + 3)) {
      const resultName = item.format === 'json' ? 'answer' : 'main';
      assert.deepEqual(Object.keys(item.results), [resultName]);
      assert.deepEqual(item.results[resultName].rows, rows);
      assert.deepEqual(item.results[resultName].columns, [
        {name: 'id', contract: {type: 'number', nullable: false}},
        {name: 'value', contract: {type: 'number', nullable: index === 0 || index === 6}}]);
    }
    const step = JSON.parse(cases.successes[index].text).stages[0].steps[2];
    assert.equal(step.from, 'l');
    const operation = step.asof_join ?? step.interval_join;
    assert.equal(operation.with, 'r');
    assert.deepEqual(operation.select, {id: 'left.id', value: 'right.id'});
    if (step.asof_join) {assert.equal(operation.tolerance, 12); assert.equal(operation.direction, 'backward');}
    else assert.equal(operation.max_output_rows, 3);
  }
  assert.equal(JSON.stringify({successes, refusals}), before);
});
test('temporal release refuses incomplete, reordered or Source-backed cohorts', () => {
  for (const changed of [successes.slice(1), [...successes, successes[0]], [...successes].reverse(),
    ...['sourceReadCount', 'sourceReadSessionCount'].map(key => successes.map((item, index) =>
      index === 0 ? {...item, [key]: 1} : item))]) {
    assert.throws(() => selectReleaseTemporalJoinQueryCases({successes: changed}));
  }
  for (const changed of [refusals.slice(1), [...refusals, refusals[0]], [...refusals].reverse()]) {
    assert.throws(() => selectReleaseTemporalJoinQueryCases({refusals: changed}));
  }
});
test('temporal second process reopens only its exact retained synthetic authorization', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-temporal-auth-unit-'));
  try {
    for (const mode of ['local', 'https']) {
      const original = await sourcefreeFixtureAuthorization(mode, 'temporal-join', {directory});
      assert.equal((await stat(join(directory, `sourcefree-temporal-join-authorization-${mode}.json`))).mode & 0o777, 0o600);
      assert.deepEqual(await sourcefreeFixtureAuthorization(mode, 'temporal-join', {directory, reopen: true}), original);
      await assert.rejects(sourcefreeFixtureAuthorization(mode, 'temporal-join', {directory}), {code: 'EEXIST'});
      await assert.rejects(sourcefreeFixtureAuthorization(mode, 'time-series', {directory, reopen: true}), {code: 'ENOENT'});
    }
  } finally {await rm(directory, {recursive: true});}
});
test('independent temporal audit detects lost NULL, ceiling result, replay, schema and refusal evidence', () => {
  // Synthetic reports test the audit only; they are never product receipts.
  const quiet = {forbiddenProcesses: 0, forbiddenFetches: 0, sourceSecrets: 0};
  const count = acceptedRuns => ({acceptedRuns, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0});
  const completed = successes.map((item, index) => ({name: item.name, ref: {run: index},
    submissionRef: {submission: index}, observedResults: structuredClone(item.results),
    beforeSubmit: count(index), beforeRead: count(index + 1), afterReplay: count(index + 1)}));
  const completedRefusals = refusals.map((item, index) => ({name: item.name,
    submissionRef: {refusal: index}, outcome: {kind: 'not_accepted',
      problem: {code: item.expectedCode}, submissionRef: {refusal: index}},
    beforeSubmit: count(12), afterRefusal: count(12)}));
  const report = {mode: 'local', suite: 'temporal-join', complete: true, actualNormal: 12, actualRefusal: 9,
    expectedSuccessNames: successes.map(item => item.name), successNames: successes.map(item => item.name),
    expectedRefusalNames: refusals.map(item => item.name), refusalNames: refusals.map(item => item.name),
    completed, completedRefusals, providerObservation: quiet,
    freshProcessReread: {mode: 'local', suite: 'temporal-join', phase: 'fresh-process-reread',
      complete: true, providerObservation: quiet, completed: completed.map(item => ({...item,
        beforeAcceptedRuns: 12, afterAcceptedRuns: 12}))}};
  assert.equal(auditTemporalJoinTransport(report).actualRows, 27);
  for (const change of [r => {r.completed[0].observedResults.answer.rows.pop();},
    r => {r.completed[0].observedResults.answer.rows[2].value = 0;},
    r => {r.completed[0].observedResults.answer.columns.reverse();},
    r => {r.completed[0].afterReplay.acceptedRuns++;},
    r => {r.completedRefusals[0].outcome.problem.code = 'Other';},
    r => {r.freshProcessReread.completed[0].ref = {run: 'different'};},
    r => {r.freshProcessReread.complete = false;}]) {
    const altered = structuredClone(report); change(altered);
    assert.throws(() => auditTemporalJoinTransport(altered));
  }
});
test('temporal bounded public recipes and independent audit parse without executing a product', async () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const path of ['prepared-checks.mjs', 'prepared-release-public.mjs', 'public-audit.mjs']) {
    execFileSync(process.execPath, ['--check', resolve(root,
      'reviews/2026-10-14-temporal-join-release-matrix', path)], {timeout: 10000});
  }
  const consumer = await readFile(resolve(root, 'scripts/test-package-release-sourcefree-query.mjs'), 'utf8');
  assert.ok(consumer.includes('--temporal-join-only'));
});
