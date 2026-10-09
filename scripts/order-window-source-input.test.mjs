import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {orderWindowProgram, joinOrderWindowProgram, joinOrderAliasProgram, joinOrderQualifiedProgram, joinSelectWindowProgram, orderWindowSuccesses, orderWindowRefusals} from './fixtures/order-window-source-input.mjs';

test('ORDER window controls distinguish alias, qualified input and pre-QUALIFY scopes', () => {
  const byName = new Map(orderWindowSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(byName.get('order-window-independent-json').text), orderWindowProgram);
  assert.deepEqual(orderWindowProgram.stages[0].steps[0].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(byName.get('order-window-sql-hidden-call').expected, [{id: 5}, {id: 1}, {id: 3}, {id: 4}, {id: 2}]);
  assert.notDeepEqual(byName.get('order-window-select-alias-collision').expected,
    byName.get('order-window-qualified-input-control').expected);
  assert.deepEqual(byName.get('order-window-qualify-after-order-window').expected,
    [{id: 4, n: 4}, {id: 3, n: 3}, {id: 5, n: 5}, {id: 1, n: 1}]);
  assert.equal(byName.get('order-window-set-combined-duplicates').expected.length, 10);
  assert.deepEqual(byName.get('order-window-typed-empty').columns, byName.get('order-window-sql-hidden-call').columns);
  assert.deepEqual(byName.get('order-window-typed-empty').expected, []);
  for (const name of ['window-alias-nesting', 'embedded-window-alias-nesting']) {
    assert.equal(orderWindowRefusals.find(item => item.name === 'order-window-refuse-' + name).expectedCode,
      'ClientProgramImplementationLimit');
  }
  const cases = [...orderWindowSuccesses, ...orderWindowRefusals];
  assert.equal(new Set(cases.map(item => item.name)).size, cases.length);
});

test('ordinary packed acceptance includes ORDER windows; narrow selection retains pristine packages', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'orderWindowSuccesses'], ['refusals', 'orderWindowRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.match(/const scopeOnly = ([^;]+);/u)?.[1].split(' || ').includes('orderWindowOnly'));
  assert.ok(fixture.includes('orderWindowOnly ? {successes: orderWindowSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_ORDER_WINDOW_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/order-window-source-input.mjs', 'order-window-source-input.mjs']"));
  assert.ok(driver.slice(driver.indexOf('const narrowPublicQuery =')).split('];')[0].includes("'--order-window-only'"));
  assert.match(driver.slice(driver.indexOf('if (plannerSelectionOnly || twoSourceExampleOnly ||')),
    /process\.argv\.includes\('--order-window-only'\).*?return;/su);
});

test('JOIN ORDER windows retain authored keys ceiling predicate and operand scopes', () => {
  const byName = new Map(orderWindowSuccesses.map(item => [item.name, item]));
  for (const [name, program] of [
    ['join-independent-json', joinOrderWindowProgram],
    ['join-alias-independent-json', joinOrderAliasProgram],
    ['join-qualified-independent-json', joinOrderQualifiedProgram],
  ]) {
    assert.deepEqual(JSON.parse(byName.get('order-window-' + name).text), program);
    assert.equal(program.stages[1].steps[1].join.max_output_rows, 10);
    assert.deepEqual(program.stages[1].steps[1].join.on, [{left: 'id', right: 'k'}]);
    assert.deepEqual(program.stages[1].steps[2].filter, {gt: [{field: 'id'}, {literal: 0}]});
  }
  const alias = byName.get('order-window-join-alias-priority');
  const qualified = byName.get('order-window-join-qualified-input');
  assert.deepEqual(alias.expected, [{id: 5, amount: null}, {id: 1, amount: null},
    {id: 3, amount: -10}, {id: 4, amount: -20}, {id: 2, amount: -20}]);
  assert.deepEqual(qualified.expected, [{id: 5, amount: null}, {id: 1, amount: null},
    {id: 4, amount: -20}, {id: 2, amount: -20}, {id: 3, amount: -10}]);
  assert.notDeepEqual(alias.expected, qualified.expected);
  assert.deepEqual(alias.expected, byName.get('order-window-join-alias-independent-json').expected);
  assert.deepEqual(qualified.expected, byName.get('order-window-join-qualified-independent-json').expected);
  assert.deepEqual(byName.get('order-window-join-pipe-projected-alias').expected, alias.expected);
  assert.deepEqual(byName.get('order-window-join-parameter-offset').expected, [{id: 1}, {id: 3}, {id: 4}]);
  assert.deepEqual(byName.get('order-window-join-typed-empty').expected, []);
  assert.equal(byName.get('order-window-join-duplicates').expected.length, 6);
  assert.equal(byName.get('order-window-join-left-preserved').columns[1].contract.nullable, true);
  assert.equal(orderWindowSuccesses.length, 33);
  assert.equal(orderWindowRefusals.length, 10);
  assert.equal(orderWindowRefusals.at(-1).expectedCode, 'ClientProgramInvalidInput');
});

test('JOIN SELECT windows preserve input scope predicate multiplicity and result columns', () => {
  const byName = new Map(orderWindowSuccesses.map(item => [item.name, item]));
  const json = byName.get('order-window-join-select-independent-json');
  assert.deepEqual(JSON.parse(json.text), joinSelectWindowProgram);
  const steps = joinSelectWindowProgram.stages[1].steps;
  assert.deepEqual(steps[1].join.on, [{left: 'id', right: 'k'}]);
  assert.equal(steps[1].join.max_output_rows, 10);
  assert.deepEqual(steps[2].filter, {gt: [{field: 'id'}, {literal: 0}]});
  assert.deepEqual(steps[3].analytic.order_by, [
    {field: 'amount', dir: 'desc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]);
  assert.deepEqual(steps[4].select, ['id', 'pos']);
  assert.deepEqual(steps[5].sort, [{field: 'pos', dir: 'desc', nulls: 'last'}]);
  assert.deepEqual(json.expected, [{id: 5, pos: 5}, {id: 1, pos: 4}, {id: 3, pos: 3},
    {id: 4, pos: 2}, {id: 2, pos: 1}]);
  for (const name of ['sql', 'pipe']) {
    const item = byName.get('order-window-join-select-' + name);
    assert.deepEqual(item.expected, json.expected);
    assert.deepEqual(item.columns, json.columns);
    assert.equal(item.sourceReadSessionCount, 1);
  }
  assert.deepEqual(byName.get('order-window-join-select-filter-before-numbering').expected,
    [{id: 5, pos: 3}, {id: 3, pos: 2}, {id: 4, pos: 1}]);
  const duplicates = byName.get('order-window-join-select-duplicates');
  assert.deepEqual(duplicates.expected.slice(-2), [{id: 2, pos: 2}, {id: 2, pos: 1}]);
  assert.equal(duplicates.expected.length, 6);
  const empty = byName.get('order-window-join-select-typed-empty');
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, json.columns);
  assert.equal(byName.get('order-window-join-select-left-preserved').columns[1].contract.nullable, true);
  for (const name of ['sibling-alias', 'projected-input']) {
    assert.equal(orderWindowRefusals.find(item => item.name === 'order-window-refuse-join-select-' + name).expectedCode,
      'ClientProgramInvalidInput');
  }
});
