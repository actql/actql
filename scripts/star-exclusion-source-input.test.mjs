import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {starExclusionProgram as program, starExclusionSuccesses as successes,
  starExclusionRefusals as refusals} from './fixtures/star-exclusion-source-input.mjs';

test('independent star exclusion fixture preserves NULL multiplicity order and input scope', () => {
  const cases = new Map(successes.map(item => [item.name, item]));
  const get = suffix => cases.get('star-exclusion-' + suffix);
  assert.deepEqual(JSON.parse(successes[0].text), program);
  assert.deepEqual(get('sql-hidden-order-null-duplicates').expected,
    [{amount: null}, {amount: 20}, {amount: 30}, {amount: 30}]);
  assert.deepEqual(get('mixed-projection-order').columns.map(column => column.name), ['amount', 'kept']);
  assert.deepEqual(get('grouped-ordinal').expected,
    [{amount: 20, n: 1}, {amount: 30, n: 2}, {amount: null, n: 1}]);
  assert.deepEqual(get('typed-empty').columns, get('sql-hidden-order-null-duplicates').columns);
  assert.deepEqual(get('typed-empty').expected, []);
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size,
    successes.length + refusals.length);
});

test('star exclusion acceptance joins the ordinary packed corpus and isolated narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...starExclusionSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...starExclusionRefusals)'));
  assert.match(fixture, /starExclusionOnly \? \{successes: starExclusionSuccesses, refusals: starExclusionRefusals\}/);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_STAR_EXCLUSION_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/star-exclusion-source-input.mjs', 'star-exclusion-source-input.mjs']"));
  assert.match(driver, /if \(plannerSelectionOnly[^;]*process\.argv\.includes\('--star-exclusion-only'\)[^;]*\) return;/);
});
