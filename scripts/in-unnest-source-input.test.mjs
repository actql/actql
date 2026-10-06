import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {inUnnestSuccesses, inUnnestRefusals, inUnnestExecutionFailures}
  from './fixtures/in-unnest-source-input.mjs';

test('membership corpus keeps distinct container/item NULL boundaries and independent JSON operands', () => {
  const cases = new Map(inUnnestSuccesses.map(value => [value.name, value]));
  const control = JSON.parse(cases.get('in-unnest-json-control').text);
  assert.deepEqual(control.stages[1].steps[0].derive, {
    included: {in: [{field: 'amount'}, {$param: 'xs'}]},
    excluded: {not_in: [{field: 'amount'}, {$param: 'xs'}]},
  });
  assert.deepEqual(cases.get('in-unnest-null-array').expected,
    cases.get('in-unnest-empty-array').expected);
  assert.notDeepEqual(cases.get('in-unnest-null-array').expected,
    cases.get('in-unnest-null-item').expected);
  assert.deepEqual(cases.get('in-unnest-filter-duplicates').expected, [{id: 3}, {id: 3}]);
  assert.equal(cases.get('in-unnest-proven-empty-null-left').columns[0].contract.nullable, false);
  assert.equal(cases.get('in-unnest-null-array').columns[1].contract.nullable, true);
  assert.deepEqual(cases.get('in-unnest-empty-input').expected, []);
  const all = [...inUnnestSuccesses, ...inUnnestRefusals, ...inUnnestExecutionFailures];
  assert.equal(new Set(all.map(value => value.name)).size, all.length);
});

test('normal packed acceptance registers the array predicate and its bounded narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'inUnnestSuccesses'], ['refusals', 'inUnnestRefusals'],
    ['executionFailures', 'inUnnestExecutionFailures']]) {
    const registration = `scopeInputs.${kind}.push(...${group})`;
    assert.equal(fixture.split(registration).length - 1, 1,
      `${group} must be registered exactly once in the normal corpus`);
  }
  assert.ok(fixture.includes('const scopeOnly = inUnnestOnly ||'));
  assert.ok(fixture.includes('inUnnestOnly ? {successes: inUnnestSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_IN_UNNEST_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/in-unnest-source-input.mjs', 'in-unnest-source-input.mjs']"));
  assert.ok(driver.includes("const narrowPublicQuery = process.argv.some(flag => ['--in-unnest-only'"));
  assert.ok(driver.includes("if (process.argv.includes('--in-unnest-only')) return;"));
});
