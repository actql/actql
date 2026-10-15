import assert from 'node:assert/strict';
import {calendarSourceSuccesses, calendarSourceArtifact, calendarSourceSelection,
  calendarSourceArtifactLimits} from './fixtures/calendar-source-input.mjs';

const names = ['day-series', 'month-bucket'].flatMap(operation =>
  ['json', 'sql', 'aql-text'].map(format => `calendar-${operation}-${format}`));

export function selectReleaseCalendarQueryCases({successes = calendarSourceSuccesses} = {}) {
  assert.deepEqual(successes.map(item => item.name), names);
  for (const item of successes) {
    assert.equal(item.sourceReadCount, 0);
    assert.equal(item.sourceReadSessionCount, 0);
    assert.ok(Array.isArray(item.results.answer.rows));
    assert.ok(Array.isArray(item.results.answer.columns));
  }
  // The original fixture is a framed file. Its independently pinned canonical
  // artifact is the body without that one known terminal LF, not trim/normalize.
  assert(calendarSourceArtifact.endsWith('\n'));
  const calendarArtifact = {selection: calendarSourceSelection,
    tableBytes: Buffer.from(calendarSourceArtifact.slice(0, -1)),
    limits: calendarSourceArtifactLimits, maxSelectionWork: 10000};
  return Object.freeze({successes: Object.freeze([...successes]),
    refusals: Object.freeze([]), calendarArtifact});
}
