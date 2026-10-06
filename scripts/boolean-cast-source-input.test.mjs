import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {booleanCastSuccesses, booleanCastRefusals, booleanCastExecutionFailures}
  from './fixtures/boolean-cast-source-input.mjs';

test('BOOLEAN cast fixtures preserve independent type, NULL, empty and failure expectations', () => {
  const byName = new Map(booleanCastSuccesses.map(value => [value.name, value]));
  assert.deepEqual(byName.get('boolean-cast-alias-boolean').expected,
    [{flag: true, missing: null}]);
  assert.deepEqual(byName.get('boolean-cast-alias-boolean').columns, [
    {name: 'flag', contract: {type: 'boolean', nullable: false}},
    {name: 'missing', contract: {type: 'boolean', nullable: true}},
  ]);
  assert.deepEqual(byName.get('boolean-cast-empty-typed-null').expected, []);
  assert.deepEqual(byName.get('boolean-cast-empty-typed-null').columns,
    [{name: 'flag', contract: {type: 'boolean', nullable: true}}]);
  const control = JSON.parse(byName.get('boolean-cast-json-control').text);
  assert.deepEqual(control.stages[0].steps[1].derive.flag,
    {cast: {value: {literal: true}, target: {type: 'boolean'}}});
  assert.equal(booleanCastExecutionFailures.length, 1);
  assert.ok(booleanCastRefusals.some(value => value.text.includes('`BOOLEAN`')));
});

test('BOOLEAN cast cases remain in normal packed acceptance and its narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'booleanCastSuccesses'], ['refusals', 'booleanCastRefusals'],
    ['executionFailures', 'booleanCastExecutionFailures']]) assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  assert.ok(fixture.includes('booleanCastOnly ? {successes: booleanCastSuccesses'));
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('booleanCastOnly'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_BOOLEAN_CAST_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/boolean-cast-source-input.mjs', 'boolean-cast-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--boolean-cast-only'/u);
  assert.ok(driver.includes("process.argv.includes('--boolean-cast-only')) return;"));
});
