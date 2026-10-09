import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {windowScalarProgram, windowScalarSuccesses, windowScalarRefusals,
  windowScalarExecutionFailures, groupedLagOperandProgram,
  groupedSumOperandProgram} from './fixtures/window-scalar-source-input.mjs';

test('grouped window operands have independent Programs, NULLs and opposing scope orders', () => {
  const cases = new Map(windowScalarSuccesses.map(item => [item.name, item]));
  const get = name => cases.get('window-scalar-aggregate-operand-' + name);
  const lag = get('lag');
  assert.deepEqual(lag.expected, [{amount: 10, n: null}, {amount: 20, n: 1}, {amount: null, n: 2}]);
  assert.deepEqual(lag.columns, [{name: 'amount', contract: {type: 'number', nullable: true}},
    {name: 'n', contract: {type: 'number', nullable: true}}]);
  assert.deepEqual(JSON.parse(get('lag-json').text), groupedLagOperandProgram);
  assert.deepEqual(groupedLagOperandProgram.stages[1].steps[0],
    {from: 'records', group: {by: ['amount'], aggregates: {measured: {fn: 'count'}}}});
  assert.deepEqual(groupedLagOperandProgram.stages[1].steps[1].analytic.functions,
    {n: {fn: 'lag', expr: {field: 'measured'}}});
  assert.deepEqual(JSON.parse(get('sum-json').text), groupedSumOperandProgram);
  assert.deepEqual(groupedSumOperandProgram.stages[1].steps[0].group.aggregates,
    {measured: {fn: 'sum', field: 'id'}});
  assert.deepEqual(groupedSumOperandProgram.stages[1].steps[1].analytic.frame,
    {start: 'unbounded_preceding', end: 'current_row'});
  assert.deepEqual(get('running-sum').expected, [{amount: 10, n: 3}, {amount: 20, n: 9}, {amount: null, n: 15}]);
  assert.deepEqual(get('order-alias').expected.map(row => row.original), [null, 20, 10]);
  assert.deepEqual(get('order-qualified-input').expected.map(row => row.original), [20, null, 10]);
  assert.ok(get('order-alias').text.includes('LAG(SUM(amount))'));
  assert.ok(get('order-qualified-input').text.includes('LAG(SUM(records.amount))'));
  assert.deepEqual(get('typed-empty').columns, lag.columns);
  assert.deepEqual(get('typed-empty').expected, []);
  assert.deepEqual(get('parameter-offset').parameters, {increment: 1});
  assert.ok(get('parameter-offset').text.includes('LAG(COUNT(*), @increment)'));
  for (const name of ['ordinary-aggregate-nesting', 'aggregate-operand-sibling-alias',
    'aggregate-operand-pipe-implicit-group']) {
    assert.equal(windowScalarRefusals.find(item => item.name.endsWith(name)).expectedCode, 'ClientProgramInvalidInput');
  }
  for (const name of ['aggregate-operand-missing-frame', 'aggregate-operand-row-offset']) {
    assert.equal(windowScalarRefusals.find(item => item.name.endsWith(name)).expectedCode, 'ClientProgramImplementationLimit');
  }
});

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
