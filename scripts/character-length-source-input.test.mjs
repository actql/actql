import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {characterLengthSuccesses, characterLengthRefusals}
  from './fixtures/character-length-source-input.mjs';

test('character length expectations distinguish bytes code units and retained scalars', () => {
  const cases = new Map(characterLengthSuccesses.map(value => [value.name, value]));
  assert.deepEqual(cases.get('character-length-retained-unicode').expected,
    [{composed: 1, decomposed: 2, supplementary: 1, existing: 3}]);
  assert.deepEqual(cases.get('character-length-empty-and-null').expected, [{empty: 0, unknown: null}]);
  assert.deepEqual(cases.get('character-length-pipe-parameter').parameters, {text: 'e\u0301😀'});
  assert.deepEqual(cases.get('character-length-empty-result').expected, []);
  assert.deepEqual(cases.get('character-length-empty-result').columns,
    [{name: 'n', contract: {type: 'number', nullable: false}}]);
  assert.deepEqual(cases.get('character-length-nullable-row').expected,
    [{id: 1, n: null}, {id: 2, n: 2}, {id: 3, n: 2}, {id: 3, n: 2}]);
  assert.deepEqual(JSON.parse(cases.get('character-length-json-control').text)
    .stages[0].steps[1].derive.n, {len: {literal: 'e\u0301😀'}});
  const all = [...characterLengthSuccesses, ...characterLengthRefusals];
  assert.equal(new Set(all.map(value => value.name)).size, all.length);
});

test('character length remains in normal packed acceptance and its focused route', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...characterLengthSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...characterLengthRefusals)'));
  assert.match(fixture, /const scopeOnly = characterLengthOnly \|\|/u);
  assert.ok(fixture.includes('characterLengthOnly ? {successes: characterLengthSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_CHARACTER_LENGTH_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/character-length-source-input.mjs', 'character-length-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--character-length-only'/u);
  assert.match(driver, /if \(plannerSelectionOnly[^;]+process\.argv\.includes\('--character-length-only'\)[^;]+\) return;/u);
});
