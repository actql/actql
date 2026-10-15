import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {selectReleaseCalendarQueryCases} from './release-calendar-query-cases.mjs';
import {selectInstalledSourcefreeQuerySuite, releaseSourcefreeFixturePaths,
  releaseSourcefreeSuccessNames, releaseSourcefreeRefusalNames} from './release-sourcefree-query-cases.mjs';
import {calendarSourceSuccesses, calendarSourceSelection, calendarSourceArtifactLimits}
  from './fixtures/calendar-source-input.mjs';

test('Calendar release selection preserves all six independent Program text rows and ordered schemas', () => {
  const cases = selectReleaseCalendarQueryCases();
  const original = JSON.parse(readFileSync('reviews/2026-10-13-frontend-calendar-source/expected.json','utf8'));
  assert.equal(cases.successes.length,6);assert.deepEqual(cases.refusals,[]);
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
