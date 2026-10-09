import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {orderWindowProgram, setWindowPrivateProgram, orderWindowSuccesses, orderWindowRefusals} from './fixtures/order-window-source-input.mjs';

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


test('set star preserves schema-supplied private names and authored row values', () => {
  const byName = new Map(orderWindowSuccesses.map(item => [item.name, item]));
  for (const [field, jsonName, sourceName] of [
    ['aql_order_window_0', 'json-control', 'star-column'],
    ['AQL_ORDER_WINDOW_0', 'case-json-control', 'case-star-column'],
  ]) {
    const control = setWindowPrivateProgram(field);
    const json = byName.get('order-window-set-private-' + jsonName);
    const source = byName.get('order-window-set-private-' + sourceName);
    assert.deepEqual(JSON.parse(json.text), control);
    assert.deepEqual(source.expected, [{[field]: 10, id: 2}, {[field]: 10, id: 2},
      {[field]: 90, id: 1}, {[field]: 90, id: 1}]);
    assert.deepEqual(json.expected, source.expected);
    assert.deepEqual(source.columns.map(column => column.name), [field, 'id']);
    assert.equal(source.columns[0].contract.nullable, true);
    assert.equal(source.sourceReadSessionCount, 0);
    assert.ok(!source.text.toLowerCase().includes(field.toLowerCase()),
      'the collision comes from the checked schema, not an authored name token');
    assert.deepEqual(control.stages[0].steps[5].append, {with: 'original'});
    assert.deepEqual(control.stages[0].steps[6].analytic.order_by,
      [{field: 'id', dir: 'asc', nulls: 'first'}]);
    assert.deepEqual(control.stages[0].steps[8].select, [field, 'id']);
  }
  assert.deepEqual(byName.get('order-window-set-private-empty').expected, []);
  assert.equal(byName.get('order-window-set-private-duplicates').expected.length, 6);
  assert.equal(byName.get('order-window-set-private-nullable-column').expected.at(-1).aql_order_window_0, null);
  assert.equal(orderWindowRefusals.at(-1).expectedCode, 'ClientProgramInvalidInput');
  assert.equal(orderWindowSuccesses.length, 23);
  assert.equal(orderWindowRefusals.length, 8);
});
