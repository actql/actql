import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {analyticOffsetProgram, analyticOffsetSuccesses, analyticOffsetRefusals}
  from './fixtures/analytic-offset-source-input.mjs';

test('positive navigation source keeps the independent full Program, rows and schemas', async () => {
  const root = new URL('../docs/reviews/fixtures/', import.meta.url);
  const expectedProgram = JSON.parse(await readFile(new URL('analytic-offset.expected.program.json', root), 'utf8'));
  const expectedCases = JSON.parse(await readFile(new URL('analytic-offset.expected.json', root), 'utf8'));
  assert.deepEqual(analyticOffsetProgram, expectedProgram);
  assert.equal(analyticOffsetSuccesses.length, 5);
  for (const item of analyticOffsetSuccesses) {
    const expected = expectedCases.find(expected => expected.name === item.name);
    assert.ok(expected, item.name);
    assert.deepEqual(item.expected, expected.expected);
    assert.deepEqual(item.columns, expected.columns);
    assert.deepEqual(item.sourceRows, expected.sourceRows);
    assert.deepEqual(item.parameters, expected.parameters);
    assert.equal(item.sourceReadSessionCount, 1);
    if (item.format !== 'json') {
      assert.match(item.text, /LAG\(amount, [()+]+(?:2|@p|0)/u);
      assert.match(item.text, /LEAD\(amount, [()+]+(?:2|@p)/u);
    }
  }
});

test('positive navigation invalid operands are registered before any runtime substitution', () => {
  const items = analyticOffsetRefusals.filter(item => item.name.includes('positive-invalid-'));
  assert.equal(items.length, 4);
  assert.deepEqual(items.map(item => item.text), [
    'SELECT LEAD(amount, +(id)) OVER (ORDER BY id) AS next FROM records',
    'SELECT LEAD(amount, +(@p + 1)) OVER (ORDER BY id) AS next FROM records',
    'SELECT LEAD(amount, +NULL) OVER (ORDER BY id) AS next FROM records',
    'SELECT LEAD(amount, +(-1)) OVER (ORDER BY id) AS next FROM records',
  ]);
  for (const item of items) {
    assert.equal(item.hostProfile, 'analytic-offset');
    assert.equal(item.expectedCode, 'ClientProgramInvalidInput');
  }
});
