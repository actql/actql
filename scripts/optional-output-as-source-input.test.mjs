import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {optionalOutputAsSuccesses, optionalOutputAsRefusals, optionalOutputAsExecutionFailures}
  from './fixtures/optional-output-as-source-input.mjs';

test('optional AS fixtures distinguish output aliases from qualified inputs', () => {
  const byName = new Map(optionalOutputAsSuccesses.map(value => [value.name, value]));
  assert.deepEqual(byName.get('optional-output-as-alias-priority').expected,
    [{amount: 1}, {amount: 2}]);
  assert.deepEqual(byName.get('optional-output-as-qualified-input').expected,
    [{amount: 2}, {amount: 1}]);
  assert.deepEqual(byName.get('optional-output-as-analytic').expected,
    [{id: 1, n: 1}, {id: 2, n: 2}, {id: 3, n: 3}]);
  assert.deepEqual(byName.get('optional-output-as-pipe-extend').columns,
    [{name: 'id', contract: {type: 'number', nullable: false}},
      {name: 'next_amount', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(byName.get('optional-output-as-empty').expected, []);
  const control = JSON.parse(byName.get('optional-output-as-json-control').text);
  assert.deepEqual(control.stages[0].steps[1].derive,
    {id: {literal: 1}, label: {literal: 'hello'}});
  assert.equal(optionalOutputAsRefusals.length, 6);
  assert.equal(optionalOutputAsExecutionFailures.length, 1);
});

test('optional AS cases remain in normal packed acceptance and its narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'optionalOutputAsSuccesses'], ['refusals', 'optionalOutputAsRefusals'],
    ['executionFailures', 'optionalOutputAsExecutionFailures']]) assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  assert.ok(fixture.includes('optionalOutputAsOnly ? {successes: optionalOutputAsSuccesses'));
  assert.ok(fixture.match(/^const scopeOnly = (.+);$/mu)[1].split(/\s*\|\|\s*/u).includes('optionalOutputAsOnly'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_OPTIONAL_OUTPUT_AS_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/optional-output-as-source-input.mjs', 'optional-output-as-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--optional-output-as-only'/u);
  assert.ok(driver.includes("process.argv.includes('--optional-output-as-only') || process.argv.includes('--boolean-cast-only')) return;"));
});
