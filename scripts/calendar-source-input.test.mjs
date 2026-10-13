import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {calendarSourceSuccesses, calendarSourceArtifact, calendarSourceSelection,
  calendarSourceArtifactLimits} from './fixtures/calendar-source-input.mjs';

test('prepared Calendar controls preserve the original independent UTC rows and ordered full schema', async () => {
  const expected = JSON.parse(await readFile(new URL(
    '../reviews/2026-10-13-frontend-calendar-source/expected.json', import.meta.url), 'utf8'));
  assert.equal(calendarSourceSuccesses.length, 6);
  for (const [index, item] of calendarSourceSuccesses.entries()) {
    const oracle = index < 3 ? expected : expected.bucketed;
    assert.deepEqual(item.results.answer, {rows: oracle.rows, columns: oracle.columns});
    assert.equal(item.sourceReadCount, 0);
    assert.equal(item.sourceReadSessionCount, 0);
  }
  const programs = calendarSourceSuccesses.filter(item => item.format === 'json').map(item => JSON.parse(item.text));
  for (const program of programs) {
    assert.deepEqual(program.stages[0].steps[0].calendar_series, {
      start: '2000-01-01T00:00:00.000Z', end: '2000-01-03T00:00:00.000Z', unit: 'day', timezone: 'UTC',
    });
    assert.deepEqual(program.results, {answer: {from: {stage: 'main', result: 'rows'}}});
  }
  assert.deepEqual(programs[1].stages[0].steps[1].calendar_bucket,
    {time: 'start', into: 'month', unit: 'month', timezone: 'UTC'});
  assert.deepEqual(programs[1].stages[0].results.rows.fields, ['start', 'end', 'month']);
  for (const item of calendarSourceSuccesses.filter(item => item.format !== 'json')) {
    assert.ok(item.text.startsWith('WITH days AS (calendar_series('));
    assert.ok(item.text.includes('`end`'));
    assert.ok(item.text.endsWith('ORDER BY start'));
  }
});

test('prepared Calendar selection retains exact original canonical artifact bytes and bounded admission', async () => {
  const original = await readFile(new URL(
    '../reviews/2026-10-13-frontend-calendar-source/utc-table.json', import.meta.url), 'utf8');
  assert.equal(calendarSourceArtifact, original);
  // Artifact admission hashes the canonical body without its file newline.
  const wire = calendarSourceArtifact.slice(0, -1);
  assert.equal(`sha256:${createHash('sha256').update(wire).digest('hex')}`,
    calendarSourceSelection.table_bytes_cid);
  assert.equal(calendarSourceSelection.tzdb_version, 'test-fixture');
  assert.deepEqual(calendarSourceArtifactLimits,
    {max_bytes: 1000, max_nodes: 100, max_depth: 8, max_zones: 1, max_transitions: 0});
  assert.ok(Buffer.byteLength(wire) <= calendarSourceArtifactLimits.max_bytes);
});
