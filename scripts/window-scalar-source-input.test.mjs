import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {windowScalarProgram, windowScalarSuccesses, windowScalarRefusals,
  windowScalarExecutionFailures} from './fixtures/window-scalar-source-input.mjs';

test('window operands retain independent ordering, NULL, keys and scope controls', () => {
  const byName = new Map(windowScalarSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(byName.get('window-scalar-independent-json').text), windowScalarProgram);
  assert.deepEqual(windowScalarProgram.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(windowScalarProgram.stages[1].steps[1].derive.n,
    {add: [{field: 'position'}, {$param: 'increment'}]});
  assert.deepEqual(byName.get('window-scalar-sql-arithmetic').expected,
    [{id: 1, n: 5}, {id: 2, n: 2}, {id: 3, n: 4}, {id: 4, n: 3}, {id: 5, n: 6}]);
  assert.deepEqual(byName.get('window-scalar-qualify-evaluated-alias').expected, [{id: 2, n: 2}, {id: 4, n: 3}]);
  assert.deepEqual(byName.get('window-scalar-typed-empty').columns, byName.get('window-scalar-sql-arithmetic').columns);
  assert.deepEqual(byName.get('window-scalar-typed-empty').expected, []);
  assert.deepEqual(byName.get('window-scalar-group-before-window').expected,
    [{amount: 10, n: 2}, {amount: 20, n: 4}, {amount: null, n: 5}]);
  assert.deepEqual(byName.get('window-scalar-distinct-window-values').expected, [{n: 2}, {n: 4}, {n: 5}]);
  assert.equal(byName.get('window-scalar-multiple-windows').parameterDeclarations, undefined);
  assert.equal(byName.get('window-scalar-multiple-windows').parameters, undefined);
  assert.deepEqual(byName.get('window-scalar-sql-arithmetic').parameterDeclarations,
    {increment: {type: 'number', nullable: false}});
  const unused = windowScalarRefusals.find(item => item.name === 'window-scalar-refuse-unused-parameter');
  assert.deepEqual(unused.parameterDeclarations, byName.get('window-scalar-sql-arithmetic').parameterDeclarations);
  assert.equal(unused.expectedCode, 'ClientProgramInvalidInput');
  const all = [...windowScalarSuccesses, ...windowScalarRefusals, ...windowScalarExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('normal packed acceptance includes window operands and its narrow scope is isolated', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'windowScalarSuccesses'],
    ['refusals', 'windowScalarRefusals'], ['executionFailures', 'windowScalarExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('windowScalarOnly'));
  assert.ok(fixture.includes('windowScalarOnly ? {successes: windowScalarSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_WINDOW_SCALAR_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/window-scalar-source-input.mjs', 'window-scalar-source-input.mjs']"));
  assert.ok(driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0].includes("'--window-scalar-only'"));
  assert.match(driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||')),
    /process\.argv\.includes\('--window-scalar-only'\).*?return;/su);
});
