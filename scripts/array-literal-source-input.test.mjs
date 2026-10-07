import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {arrayLiteralSuccesses, arrayLiteralRefusals}
  from './fixtures/array-literal-source-input.mjs';

test('ARRAY fixtures retain independently authored types order multiplicity and NULLs', () => {
  const byName = new Map(arrayLiteralSuccesses.map(value => [value.name, value]));
  const control = byName.get('array-literal-json-control');
  assert.deepEqual(JSON.parse(control.text).stages[0].steps[1].derive,
    {items: {array: [{literal: 2}, {literal: 1}, {literal: 2}]}});
  for (const name of ['brackets', 'keyword', 'declared-number']) {
    assert.deepEqual(byName.get('array-literal-' + name).expected, control.expected);
    assert.deepEqual(byName.get('array-literal-' + name).columns, control.columns);
  }
  assert.deepEqual(byName.get('array-literal-declared-only-null').expected, [{items: [null]}]);
  assert.equal(byName.get('array-literal-declared-only-null').columns[0].contract.items.nullable, true);
  assert.deepEqual(byName.get('array-literal-empty-rows').columns, control.columns);
  assert.deepEqual(byName.get('array-literal-expand-offsets').expected,
    [{element: 2, position: 0}, {element: 1, position: 1}, {element: 2, position: 2}]);
  for (const fixture of arrayLiteralRefusals.filter(value => value.name.includes('direct-nested'))) {
    assert.equal(fixture.expectedCode, 'ClientProgramUnsupported');
  }
  const names = [...arrayLiteralSuccesses, ...arrayLiteralRefusals].map(value => value.name);
  assert.equal(new Set(names).size, names.length);
});

test('ordinary public campaign and narrow consumer both include ARRAY fixtures', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...arrayLiteralSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...arrayLiteralRefusals)'));
  assert.ok(fixture.includes('arrayLiteralOnly ? {successes: arrayLiteralSuccesses'));
  assert.ok(driver.includes("['scripts/fixtures/array-literal-source-input.mjs', 'array-literal-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ARRAY_LITERAL_ONLY = '1'"));
  assert.ok(driver.includes("process.argv.includes('--array-literal-only')) return;"));
});
