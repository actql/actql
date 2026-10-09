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
    assert.equal(fixture.expectedCode, 'ClientProgramRejected');
  }
  const refusals = new Map(arrayLiteralRefusals.map(value => [value.name, value]));
  const reference = refusals.get('array-literal-direct-nested-parameter-reference');
  assert.equal(reference.text, 'SELECT @matrix AS items');
  assert.deepEqual(reference.parameters, {matrix: [[1, 2]]});
  assert.equal(reference.parameterDeclarations.matrix.items.type, 'array');
  assert.equal(refusals.get('array-literal-direct-nested-aggregate').text,
    'FROM records |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(@xs IGNORE NULLS ORDER BY id) AS items GROUP BY id |> ORDER BY id');
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

test('DOUBLE fixtures retain the independent numeric CAST and ARRAY contracts', () => {
  const cases = new Map(arrayLiteralSuccesses.map(value => [value.name, value]));
  const control = cases.get('array-literal-double-json-control');
  assert.deepEqual(JSON.parse(control.text).stages[0].steps[1].derive, {
    value: {cast: {value: {literal: 1.25}, target: {type: 'number'}}},
    missing: {cast: {value: {literal: null}, target: {type: 'number'}}},
    items: {if: [{literal: true}, {array: [{literal: 2}, {literal: null}, {literal: 2}]},
      {empty_array: {items: {type: 'number', nullable: false}}}]},
  });
  assert.deepEqual(control.expected, [{value: 1.25, missing: null, items: [2, null, 2]}]);
  assert.deepEqual(control.columns, [
    {name: 'value', contract: {type: 'number', nullable: false}},
    {name: 'missing', contract: {type: 'number', nullable: true}},
    {name: 'items', contract: {type: 'array', nullable: false, max_items: 3,
      items: {type: 'number', nullable: true}}},
  ]);
  for (const index of [0, 1, 2]) {
    assert.deepEqual(cases.get('array-literal-double-type-' + index).expected, control.expected);
    assert.deepEqual(cases.get('array-literal-double-type-' + index).columns, control.columns);
  }
  assert.deepEqual(cases.get('array-literal-double-empty-array').expected, [{items: []}]);
  assert.deepEqual(cases.get('array-literal-double-typed-empty-result').expected, []);
  assert.equal(cases.get('array-literal-double-typed-empty-result').columns[0].contract.nullable, true);
  assert.equal(cases.get('array-literal-double-only-null-array').columns[0].contract.items.type, 'number');
  assert.ok(cases.get('array-literal-double-lazy-cast').text.includes("CAST('invalid' AS DOUBLE)"));
  for (const target of ['FLOAT', 'FLOAT32']) {
    assert.ok(arrayLiteralRefusals.some(value => value.text === `SELECT CAST(1 AS ${target}) AS value`));
    assert.ok(arrayLiteralRefusals.some(value => value.text === `SELECT ARRAY<${target}>[1] AS items`));
  }
});
