import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {selectReleaseTimeSeriesQueryCases} from './release-time-series-query-cases.mjs';
import {selectInstalledSourcefreeQuerySuite} from './release-sourcefree-query-cases.mjs';
import {timeSeriesPrimarySuccesses as successes, timeSeriesPrimaryRefusals as refusals}
  from './fixtures/time-series-primary-source-input.mjs';
import {sourcefreeFixtureAuthorization} from './fixtures/release-sourcefree-authorization.mjs';

test('TimeSeries selects the complete original 9+7 and preserves typed UTC parameters', () => {
  const before = JSON.stringify({successes, refusals});
  const selected = selectReleaseTimeSeriesQueryCases();
  assert.deepEqual(selectInstalledSourcefreeQuerySuite('time-series'), selected);
  assert.equal(selected.successes.length, 9); assert.equal(selected.refusals.length, 7);
  for (const [index, item] of selected.successes.entries()) assert.equal(item, successes[index]);
  for (const [index, item] of selected.refusals.entries()) assert.equal(item, refusals[index]);
  assert.deepEqual(selected.successes[0].results.answer.columns,
    [{name: 'time', contract: {type: 'timestamp', nullable: false}}]);
  assert.deepEqual(selected.successes[0].results.answer.rows, [
    {time: '2026-10-12T00:00:00.000Z'}, {time: '2026-10-12T00:01:00.000Z'},
    {time: '2026-10-12T00:02:00.000Z'}]);
  assert.deepEqual(selected.successes[7].parameters,
    {begin: '2026-10-12T00:00:00.000Z', finish: '2026-10-12T00:03:00.000Z', tick: 60000});
  assert.equal(JSON.stringify({successes, refusals}), before);
});
test('TimeSeries cannot omit duplicate reorder or replace the source-free inventory', () => {
  for (const changed of [successes.slice(1), [...successes, successes[0]], [...successes].reverse(),
    successes.map((item, index) => index === 0 ? {...item, sourceReadCount: 1} : item)]) {
    assert.throws(() => selectReleaseTimeSeriesQueryCases({successes: changed}));
  }
  for (const changed of [refusals.slice(1), [...refusals, refusals[0]], [...refusals].reverse()]) {
    assert.throws(() => selectReleaseTimeSeriesQueryCases({refusals: changed}));
  }
});
test('TimeSeries retains its synthetic authorization unchanged for a second process', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-timeseries-auth-unit-'));
  try {
    for (const mode of ['local', 'https']) {
      const original = await sourcefreeFixtureAuthorization(mode, 'time-series', {directory});
      const path = join(directory, `sourcefree-time-series-authorization-${mode}.json`);
      assert.equal((await stat(path)).mode & 0o777, 0o600);
      assert.deepEqual(await sourcefreeFixtureAuthorization(mode, 'time-series', {directory, reopen: true}), original);
      await assert.rejects(sourcefreeFixtureAuthorization(mode, 'time-series', {directory}), {code: 'EEXIST'});
    }
    await assert.rejects(sourcefreeFixtureAuthorization('local', 'sequence', {directory, reopen: true}));
    await assert.rejects(sourcefreeFixtureAuthorization('local', 'unknown', {directory}));
  } finally {await rm(directory, {recursive: true});}
});
test('existing default authorization does not write a retained credential', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-sourcefree-auth-unit-'));
  try {
    for (const suite of ['in-unnest']) {
      const authorization = await sourcefreeFixtureAuthorization('local', suite, {directory});
      assert.equal(authorization.reviewers.length, 1);
      assert.match(authorization.hostKey.privateKey, /BEGIN PRIVATE KEY/u);
      await assert.rejects(readFile(join(directory, `sourcefree-${suite}-authorization-local.json`)), {code: 'ENOENT'});
      await assert.rejects(sourcefreeFixtureAuthorization('local', suite, {directory, reopen: true}));
    }
  } finally {await rm(directory, {recursive: true});}
});
test('separate-process reread and original bounded recipes parse without starting the product', () => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  for (const path of ['scripts/fixtures/release-time-series-reread.mjs',
    'reviews/2026-10-14-time-series-release-matrix/prepared-checks.mjs',
    'reviews/2026-10-14-time-series-release-matrix/prepared-release-public.mjs']) {
    execFileSync(process.execPath, ['--check', resolve(root, path)], {timeout: 10000});
  }
});


// The audit consumes saved observations and the original independent fixture;
// these synthetic mutations establish no product execution qualification.
import {auditTimeSeriesTransport} from '../reviews/2026-10-14-time-series-release-matrix/public-audit.mjs';
const counts = acceptedRuns => ({acceptedRuns, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0});
function auditControl() {
  const providerObservation = {forbiddenProcesses: 0, forbiddenFetches: 0, sourceSecrets: 0};
  const completed = successes.map((item, index) => ({name: item.name,
    ref: {testRun: index}, submissionRef: {testSubmission: index},
    observedResults: structuredClone(item.results), beforeSubmit: counts(index),
    beforeRead: counts(index + 1), afterReplay: counts(index + 1)}));
  return {mode: 'local', suite: 'time-series', complete: true,
    actualNormal: 9, actualRefusal: 7,
    expectedSuccessNames: successes.map(item => item.name), successNames: successes.map(item => item.name),
    expectedRefusalNames: refusals.map(item => item.name), refusalNames: refusals.map(item => item.name),
    completed, providerObservation,
    completedRefusals: refusals.map((item, index) => ({name: item.name,
      submissionRef: {testRefusal: index}, beforeSubmit: counts(9), afterRefusal: counts(9),
      outcome: {kind: 'not_accepted', problem: {code: item.expectedCode}, submissionRef: {testRefusal: index}}})),
    freshProcessReread: {mode: 'local', suite: 'time-series', phase: 'fresh-process-reread', complete: true,
      providerObservation, completed: completed.map(item => ({name: item.name, ref: item.ref,
        submissionRef: item.submissionRef, observedResults: structuredClone(item.observedResults),
        beforeAcceptedRuns: 9, afterAcceptedRuns: 9}))}};
}
test('TimeSeries independent audit requires the complete original normal refusal and restart observations', () => {
  assert.deepEqual(auditTimeSeriesTransport(auditControl()), {mode: 'local', actualNormal: 9,
    actualRefusal: 7, actualNamedResults: 9, actualRows: 21, freshRereadNamedResults: 9, complete: true});
});
test('TimeSeries audit rejects changed values types Refusals source counters or restart identity', () => {
  for (const mutate of [
    value => value.completed[0].observedResults.answer.rows.reverse(),
    value => { value.completed[0].observedResults.answer.columns[0].contract.nullable = true; },
    value => { value.completed[0].beforeRead.sourceReads = 1; },
    value => { value.completed[0].afterReplay.acceptedRuns = 10; },
    value => { value.completedRefusals[0].outcome.problem.code = 'DifferentRefusal'; },
    value => value.completedRefusals.pop(),
    value => { value.freshProcessReread = undefined; },
    value => { value.freshProcessReread.completed[0].ref = {testRun: 999}; },
  ]) {
    const report = auditControl(); mutate(report); assert.throws(() => auditTimeSeriesTransport(report));
  }
});
