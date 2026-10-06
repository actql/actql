import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {qualifyProgram, qualifySuccesses, qualifyRefusals, qualifyExecutionFailures}
  from './fixtures/qualify-source-input.mjs';

test('QUALIFY oracles distinguish aliases inputs NULLs duplicates and output demand', () => {
  const cases = new Map(qualifySuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('qualify-independent-json').text), qualifyProgram);
  assert.deepEqual(qualifyProgram.stages[1].steps[1], {filter: {lte: [{field: 'n'}, {literal: 2}]}});
  assert.deepEqual(cases.get('qualify-alias-collision').expected, [{amount: 20, id: 1}]);
  assert.deepEqual(cases.get('qualify-qualified-input-control').expected, [{amount: null, id: 4}]);
  assert.deepEqual(cases.get('qualify-nullable-filter-and-duplicates').expected,
    [{id: 3, n: 3}, {id: 3, n: 4}]);
  assert.deepEqual(cases.get('qualify-distinct-order-limit').expected, [{amount: 30}]);
  assert.deepEqual(cases.get('qualify-typed-empty').columns, cases.get('qualify-window-alias').columns);
  assert.deepEqual(cases.get('qualify-undemanded-select-error').expected,
    [{ratio: 1, n: 2}, {ratio: 0.5, n: 3}, {ratio: 0.5, n: 4}]);
  const all = [...qualifySuccesses, ...qualifyRefusals, ...qualifyExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('QUALIFY runs in both the ordinary and narrow packed public corpora', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'qualifySuccesses'], ['refusals', 'qualifyRefusals'],
    ['executionFailures', 'qualifyExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.match(fixture, /const scopeOnly = [^;]*qualifyOnly/u);
  assert.ok(fixture.includes('qualifyOnly ? {successes: qualifySuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_QUALIFY_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/qualify-source-input.mjs', 'qualify-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--qualify-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--qualify-only'\)\) return;/u);
});
