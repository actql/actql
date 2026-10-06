import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {joinStarProgram, joinStarSuccesses, joinStarRefusals}
  from './fixtures/join-star-source-input.mjs';

test('JOIN-star independent oracles distinguish USING order from input order', () => {
  const cases = new Map(joinStarSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('join-star-independent-json').text), joinStarProgram);
  assert.deepEqual(cases.get('join-star-on-unique-columns').columns.map(column => column.name), ['amount', 'id', 'k']);
  assert.deepEqual(cases.get('join-star-left-using-key-first').columns.map(column => column.name), ['id', 'amount']);
  assert.deepEqual(cases.get('join-star-declared-using-order').expected,
    [{id: 2, amount: 20}, {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}, {id: 3, amount: 30}]);
  assert.deepEqual(cases.get('join-star-using-qualified-null-control').expected[0],
    {id: 1, amount: null, original: 1, joined: null});
  assert.equal(cases.get('join-star-using-qualified-null-control').columns.at(-1).contract.nullable, true);
  assert.deepEqual(cases.get('join-star-empty-typed-result').columns, cases.get('join-star-on-unique-columns').columns);
  const all = [...joinStarSuccesses, ...joinStarRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('JOIN-star cases remain in ordinary and targeted public acceptance', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...joinStarSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...joinStarRefusals)'));
  assert.match(fixture, /const scopeOnly = [^;]*joinStarOnly/u);
  assert.ok(fixture.includes('joinStarOnly ? {successes: joinStarSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_JOIN_STAR_ONLY = '1'"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--join-star-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--join-star-only'\)\) return;/u);
});
