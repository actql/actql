import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {qualifiedStarProgram, qualifiedStarSuccesses, qualifiedStarRefusals}
  from './fixtures/qualified-star-source-input.mjs';

test('qualified star expectations distinguish current columns from retained ranges', () => {
  const cases = new Map(qualifiedStarSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('qualified-star-independent-json').text), qualifiedStarProgram);
  assert.deepEqual(qualifiedStarProgram.stages[0].steps[0].filter,
    {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(qualifiedStarProgram.stages[1].steps[0].sort,
    [{field: 'id', dir: 'asc', nulls: 'first'}]);
  assert.deepEqual(cases.get('qualified-star-pipe-original-values').expected,
    [{amount: null}, {amount: 20}, {amount: 30}, {amount: 30}]);
  assert.deepEqual(cases.get('qualified-star-left-join-nullability').columns,
    [{name: 'k', contract: {type: 'number', nullable: true}},
      {name: 'id', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(cases.get('qualified-star-grouped-ordinal').expected,
    [{amount: 20, n: 1}, {amount: 30, n: 2}, {amount: null, n: 1}]);
  assert.deepEqual(cases.get('qualified-star-typed-empty').columns,
    cases.get('qualified-star-sql-hidden-order').columns);
  assert.deepEqual(cases.get('qualified-star-typed-empty').expected, []);
  const all = [...qualifiedStarSuccesses, ...qualifiedStarRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('qualified star stays in normal packed acceptance and a narrow route', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, name] of [['successes', 'qualifiedStarSuccesses'], ['refusals', 'qualifiedStarRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${name})`));
  }
  assert.match(fixture, /const scopeOnly = [^;]*qualifiedStarOnly/u);
  assert.ok(fixture.includes('qualifiedStarOnly ? {successes: qualifiedStarSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_QUALIFIED_STAR_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/qualified-star-source-input.mjs', 'qualified-star-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--qualified-star-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--qualified-star-only'\)\) return;/u);
});
