import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {mkdtemp, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {selectReleaseCalendarQueryCases} from './release-calendar-query-cases.mjs';
import {selectInstalledSourcefreeQuerySuite, releaseSourcefreeFixturePaths,
  releaseSourcefreeSuccessNames, releaseSourcefreeRefusalNames} from './release-sourcefree-query-cases.mjs';
import {calendarSourceSuccesses, calendarSourceRefusals, calendarSourceSelection, calendarSourceArtifactLimits}
  from './fixtures/calendar-source-input.mjs';
import {calendarSourceSuccesses as originalSuccesses,
  calendarSourceArtifact as originalArtifact,
  calendarSourceSelection as originalSelection,
  calendarSourceArtifactLimits as originalLimits}
  from '../reviews/2026-10-15-calendar-public-reread/preimages/calendar-source-input.mjs';
import {sourcefreeFixtureAuthorization} from './fixtures/release-sourcefree-authorization.mjs';
import {auditCalendarTransport} from '../reviews/2026-10-15-calendar-host-installation/public-audit.mjs';

test('Calendar release selection preserves all six independent Program text rows and ordered schemas', () => {
  const cases = selectReleaseCalendarQueryCases();
  const original = JSON.parse(readFileSync('reviews/2026-10-15-calendar-host-installation/expected.json','utf8'));
  assert.equal(cases.successes.length,6);assert.deepEqual(cases.refusals,calendarSourceRefusals);
  for(const [index,value] of cases.successes.entries()) {
    assert.equal(value,calendarSourceSuccesses[index]);
    const oracle=index<3?original:original.bucketed;
    assert.deepEqual(value.results.answer,{rows:oracle.rows,columns:oracle.columns});
    assert.equal(value.sourceReadCount,0);assert.equal(value.sourceReadSessionCount,0);
  }
  assert.deepEqual(cases.calendarArtifact.selection,calendarSourceSelection);
  assert.deepEqual(cases.calendarArtifact.limits,calendarSourceArtifactLimits);
  assert.equal(`sha256:${createHash('sha256').update(cases.calendarArtifact.tableBytes).digest('hex')}`,
    calendarSourceSelection.table_bytes_cid);
  assert.equal(cases.calendarArtifact.maxSelectionWork,10000);
});

test('Calendar suite is closed while the original default normal refusal inventory stays unchanged', () => {
  const calendar=selectInstalledSourcefreeQuerySuite('calendar');assert.equal(calendar.successes.length,6);
  assert.throws(()=>selectReleaseCalendarQueryCases({successes:calendarSourceSuccesses.slice(1)}));
  assert.throws(()=>selectReleaseCalendarQueryCases({successes:[...calendarSourceSuccesses,...calendarSourceSuccesses]}));
  assert.deepEqual(selectInstalledSourcefreeQuerySuite().successes.map(v=>v.name),releaseSourcefreeSuccessNames);
  assert.deepEqual(selectInstalledSourcefreeQuerySuite().refusals.map(v=>v.name),releaseSourcefreeRefusalNames);
  assert(releaseSourcefreeFixturePaths.includes('scripts/release-calendar-query-cases.mjs'));
  assert(releaseSourcefreeFixturePaths.includes('scripts/fixtures/calendar-source-input.mjs'));
});

test('Calendar NULL-unit refusals change only the independently typed unit selector', () => {
  const cases = selectReleaseCalendarQueryCases();
  assert.deepEqual(cases.refusals.map(item => item.format), ['json', 'sql', 'aql-text']);
  const valid = JSON.parse(cases.successes[0].text), invalid = JSON.parse(cases.refusals[0].text);
  assert.equal(invalid.stages[0].steps[0].calendar_series.unit, null);
  invalid.stages[0].steps[0].calendar_series.unit = 'day';
  assert.deepEqual(invalid, valid);
  for (const format of ['sql', 'aql-text']) {
    const success = cases.successes.find(item => item.format === format);
    const refusal = cases.refusals.find(item => item.format === format);
    assert.equal(refusal.text.replace('unit:NULL', "unit:'day'"), success.text);
    assert.equal(refusal.expectedCode, 'ClientProgramInvalidInput');
  }
  for (const refusals of [cases.refusals.slice(1), [...cases.refusals].reverse(),
    [...cases.refusals, cases.refusals[0]]]) {
    assert.throws(() => selectReleaseCalendarQueryCases({refusals}));
  }
});

test('Calendar reread preserves the six authored inputs, UTC artifact and original contracts', () => {
  assert.deepEqual(calendarSourceSuccesses, originalSuccesses);
  const selected = selectReleaseCalendarQueryCases();
  assert.equal(selected.calendarArtifact.tableBytes.toString('utf8'), originalArtifact.slice(0, -1));
  assert.deepEqual(selected.calendarArtifact.selection, originalSelection);
  assert.deepEqual(selected.calendarArtifact.limits, originalLimits);
});

test('Calendar process reopen retains the original synthetic authorization instead of issuing another', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-calendar-reread-authorization-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  for (const mode of ['local', 'https']) {
    const first = await sourcefreeFixtureAuthorization(mode, 'calendar', {directory});
    assert.equal((await stat(join(directory, `sourcefree-calendar-authorization-${mode}.json`))).mode & 0o777, 0o600);
    assert.deepEqual(await sourcefreeFixtureAuthorization(mode, 'calendar', {directory, reopen: true}), first);
  }
});

test('Calendar receipt audit requires every refusal, exact same Run and all fresh-process values', () => {
  const {successes, refusals} = selectReleaseCalendarQueryCases();
  const quiet = {forbiddenProcesses:0,forbiddenFetches:0,sourceSecrets:0};
  const count = acceptedRuns => ({acceptedRuns,sourceIo:0,sourceReads:0,sourceReadSessions:0});
  for (const mode of ['local','https']) {
    const completed = successes.map((value,index) => ({name:value.name,
      ref:{independentRun:index},submissionRef:{independentSubmission:index},
      observedResults:structuredClone(value.results),beforeSubmit:count(index),
      beforeRead:count(index+1),afterReplay:count(index+1)}));
    const report = {mode,suite:'calendar',complete:true,actualNormal:6,actualRefusal:3,
      expectedSuccessNames:successes.map(v=>v.name),successNames:successes.map(v=>v.name),completed,
      expectedRefusalNames:refusals.map(v=>v.name),refusalNames:refusals.map(v=>v.name),
      completedRefusals:refusals.map((value,index)=>({name:value.name,
        submissionRef:{independentRefusal:index},outcome:{kind:'not_accepted',
          problem:{code:value.expectedCode},submissionRef:{independentRefusal:index}},
        beforeSubmit:count(6),afterRefusal:count(6)})),providerObservation:quiet,
      freshProcessReread:{mode,suite:'calendar',phase:'fresh-process-reread',complete:true,
        providerObservation:quiet,completed:completed.map(value=>({name:value.name,
          ref:structuredClone(value.ref),submissionRef:structuredClone(value.submissionRef),
          observedResults:structuredClone(value.observedResults),beforeAcceptedRuns:6,afterAcceptedRuns:6}))}};
    assert.equal(auditCalendarTransport(report).freshProcessReread,6);
    for (const mutate of [
      value=>{delete value.freshProcessReread;},
      value=>{value.freshProcessReread.completed.pop();},
      value=>{value.freshProcessReread.completed[0].ref.independentRun=99;},
      value=>{value.freshProcessReread.completed[0].observedResults.answer.rows=[];},
      value=>{value.freshProcessReread.completed[0].afterAcceptedRuns=7;},
      value=>{value.freshProcessReread.providerObservation.forbiddenFetches=1;},
      value=>{value.completedRefusals[0].outcome.problem.code='unexpected';},
      value=>{value.completedRefusals[0].afterRefusal.acceptedRuns=7;},
    ]) {
      const bad=structuredClone(report);mutate(bad);assert.throws(()=>auditCalendarTransport(bad));
    }
  }
});
