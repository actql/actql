import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {lowerSuccesses, lowerRefusals, lowerExecutionFailures} from './fixtures/lower-source-input.mjs';

const cases = new Map(lowerSuccesses.map(item => [item.name, item]));
test('lowercase expectations distinguish default mappings, sigma context and retained marks', () => {
  assert.deepEqual(cases.get('lower-full-mapping-not-folding').expected, [{value: 'i\u0307 ß ß ﬃ ꭰ ǳ'}]);
  assert.deepEqual(cases.get('lower-sigma-context').expected,
    [{isolated: 'σ', final: 'ος', medial: 'οσα', repeated: 'σσς'}]);
  assert.deepEqual(cases.get('lower-sigma-overlap-before').expected, [{alone: '\u0345σ', preceded: 'a\u0345ς'}]);
  assert.deepEqual(cases.get('lower-sigma-overlap-after').expected,
    [{final: 'aς\u0345', medial: 'aσ\u0345b', modifier: 'aσʰb'}]);
  assert.deepEqual(cases.get('lower-sigma-supplementary-nonletter').expected, [{before: '🄰ς', after: 'aσ🄰'}]);
  assert.deepEqual(cases.get('lower-no-normalization').expected,
    [{decomposed: 'e\u0301', composed: 'é', mark_order: 'i\u0307\u0323'}]);
  assert.deepEqual(cases.get('lower-unicode-16-and-supplementary').expected,
    [{deseret: '𐐨', garay: '𐵰', cyrillic: 'ᲊ'}]);
  assert.deepEqual(JSON.parse(cases.get('lower-json-control').text).stages[0].steps[1].derive.value,
    {lower: {literal: 'ΟΣ'}});
});

test('lowercase public fixtures retain checked NULL, parameters, duplicate rows and demand', () => {
  assert.deepEqual(cases.get('lower-parameter-context').parameters, {text: "AΣ'B"});
  assert.deepEqual(cases.get('lower-parameter-context').expected, [{value: "aσ'b"}]);
  assert.deepEqual(cases.get('lower-sql-input').expected,
    [{id: 1, value: null}, {id: 2, value: 'ος-20'}, {id: 3, value: 'ος-30'}, {id: 3, value: 'ος-30'}]);
  assert.deepEqual(cases.get('lower-pipe-input').expected, cases.get('lower-sql-input').expected);
  assert.deepEqual(cases.get('lower-typed-empty').expected, []);
  assert.deepEqual(cases.get('lower-typed-empty').columns, cases.get('lower-sql-input').columns);
  assert.equal(lowerSuccesses.length, 19);
  assert.equal(lowerRefusals.length, 7);
  assert.ok(lowerRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
  assert.equal(lowerExecutionFailures.length, 1);
  const all = [...lowerSuccesses, ...lowerRefusals, ...lowerExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('lowercase cases participate in the ordinary producer and bounded public selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'lowerSuccesses'], ['refusals', 'lowerRefusals'],
    ['executionFailures', 'lowerExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('lowerOnly ? {successes: lowerSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\blowerOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_LOWER_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/lower-source-input.mjs', 'lower-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--lower-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--lower-only')) return;"));
});
