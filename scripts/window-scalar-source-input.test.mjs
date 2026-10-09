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

test('EXTEND windows preserve the complete current row and local input scopes', async () => {
  const {pipeExtendWindowProgram} = await import('./fixtures/window-scalar-source-input.mjs');
  const get = name => windowScalarSuccesses.find(value => value.name === 'window-scalar-extend-' + name);
  assert.deepEqual(JSON.parse(get('json').text), pipeExtendWindowProgram);
  assert.deepEqual(pipeExtendWindowProgram.stages[1].steps[0].analytic.functions, {n: {fn: 'row_number'}});
  assert.deepEqual(pipeExtendWindowProgram.stages[1].results.rows.fields, ['amount', 'id', 'n']);
  assert.deepEqual(get('inline').expected.map(row => row.n), [4, 1, 3, 2, 5]);
  assert.deepEqual(get('inline').columns.map(column => column.name), ['amount', 'id', 'n']);
  assert.equal(get('inline').columns[0].contract.nullable, true);
  assert.deepEqual(get('named').expected, get('inline').expected);
  assert.deepEqual(get('empty').columns, get('inline').columns);
  assert.deepEqual(get('empty').expected, []);
  assert.deepEqual(get('operand').parameters, {increment: 1});
  assert.deepEqual(get('filter-limit').expected, [{id: 2, n: 1}]);
  assert.deepEqual(get('immutable-receiver').expected.map(row => [row.before_amount, row.after_amount]),
    [[null, null], [null, null], [20, -20], [10, -10], [20, -20]]);
  for (const value of windowScalarRefusals.filter(value => value.name.includes('refuse-extend-'))) {
    assert.equal(value.expectedCode, 'ClientProgramInvalidInput');
  }
});

test('named Pipe SELECT preserves independent analytic values and output contracts', async () => {
  const {pipeSelectNamedWindowProgram} = await import('./fixtures/window-scalar-source-input.mjs');
  const get = name => windowScalarSuccesses.find(value => value.name === 'window-scalar-pipe-named-' + name);
  assert.deepEqual(JSON.parse(get('json').text), pipeSelectNamedWindowProgram);
  assert.deepEqual(pipeSelectNamedWindowProgram.stages[1].steps[0].analytic.functions, {n: {fn: 'row_number'}});
  assert.deepEqual(get('direct').expected.map(row => row.n), [4, 1, 3, 2, 5]);
  assert.deepEqual(get('quoted-inheritance').expected, get('direct').expected);
  assert.deepEqual(get('empty').expected, []);
  assert.deepEqual(get('empty').columns, get('direct').columns);
  assert.deepEqual(get('operand').parameters, {increment: 1});
  assert.deepEqual(get('star-replace').columns.map(value => [value.name, value.contract.nullable]), [['amount', false], ['id', false]]);
  assert.deepEqual(get('star-replace').expected.map(row => row.amount), [4, 1, 3, 2, 5]);
  assert.equal(get('nullable').columns[1].contract.nullable, true);
  assert.deepEqual(get('nullable').expected.map(row => row.n), [null, null, 21, 11, 21]);
  assert.deepEqual(get('local-declarations').expected.map(row => [row.pos, row.reverse_pos]), [[1, 5], [2, 4], [3, 3], [4, 2], [5, 1]]);
  const refusals = windowScalarRefusals.filter(value => value.name.includes('refuse-pipe-named-'));
  assert.equal(refusals.length, 5);
  for (const value of refusals) assert.equal(value.expectedCode, 'ClientProgramInvalidInput');
});

test('Pipe WHERE window controls preserve predicates current rows and private slots', async () => {
  const {pipeWhereWindowProgram} = await import('./fixtures/window-scalar-source-input.mjs');
  const get = name => windowScalarSuccesses.find(value => value.name === 'window-scalar-where-window-' + name);
  assert.deepEqual(JSON.parse(get('json').text), pipeWhereWindowProgram);
  assert.deepEqual(pipeWhereWindowProgram.stages[1].steps[1], {filter: {lte: [{field: 'position'}, {literal: 3}]}});
  assert.deepEqual(pipeWhereWindowProgram.stages[1].results.rows.fields, ['amount', 'id']);
  assert.deepEqual(get('direct').expected.map(row => row.id), [2, 3, 4]);
  assert.deepEqual(get('parameter').expected.map(row => row.id), [2, 4]);
  assert.deepEqual(get('parameter').parameters, {top: 2});
  assert.deepEqual(get('empty').expected, []);
  assert.deepEqual(get('empty').columns, get('direct').columns);
  assert.deepEqual(get('nullable').expected, [{amount: 10, id: 3}, {amount: null, id: 5}]);
  assert.deepEqual(get('multiple').expected.map(row => row.id), [2, 3]);
  assert.deepEqual(get('sequential').expected, [{amount: 20, id: 2}]);
  assert.deepEqual(get('immutable-range').expected, [{amount: -10, id: 3}, {amount: null, id: 5}]);
  assert.deepEqual(get('authored-private-name').expected, [{id: 1, n: null}, {id: 2, n: 20}]);
  assert.equal(windowScalarRefusals.filter(value => value.name.includes('refuse-where-window-')).length, 6);
});
