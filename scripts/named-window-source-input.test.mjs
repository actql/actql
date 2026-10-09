import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {namedWindowProgram, namedAggregateWindowProgram, namedWindowSuccesses, namedWindowRefusals}
  from './fixtures/named-window-source-input.mjs';

test('named aggregate WINDOW controls retain independent counts, NULLs and declaration ownership', () => {
  const cases = new Map(namedWindowSuccesses.map(item => [item.name, item]));
  const get = name => cases.get('named-window-aggregate-' + name);
  assert.deepEqual(JSON.parse(get('independent-json').text), namedAggregateWindowProgram);
  assert.deepEqual(namedAggregateWindowProgram.stages[1].steps[0],
    {from: 'records', group: {by: ['id'], aggregates: {counted: {fn: 'count'}}}});
  assert.deepEqual(namedAggregateWindowProgram.stages[1].steps[1].analytic.order_by,
    [{field: 'counted', dir: 'desc', nulls: 'last'}, {field: 'id', dir: 'asc', nulls: 'first'}]);
  assert.deepEqual(get('order-key').expected, [{id: 3, n: 1}, {id: 1, n: 2}, {id: 2, n: 3}]);
  assert.deepEqual(get('nullable-count').expected, [{id: 3, n: 1}, {id: 2, n: 2}, {id: 1, n: 3}]);
  assert.deepEqual(get('reused-alias-collision').expected,
    [{original: 3, id: 2, n: 1}, {original: 1, id: 1, n: 2}, {original: 2, id: 1, n: 3}]);
  assert.deepEqual(get('typed-empty').columns, get('order-key').columns);
  assert.deepEqual(get('typed-empty').expected, []);
  assert.deepEqual(get('global-empty').expected, [{n: 1}]);
  assert.deepEqual(get('unused-no-evaluation').expected, cases.get('named-window-bare-reference').expected);
  assert.ok(get('unused-no-evaluation').text.includes('SUM(1 / 0)'));
  assert.deepEqual(get('having-before-window').expected, [{id: 3, total: 2, n: 1}]);
  assert.ok(namedWindowRefusals.some(item => item.text.includes('COUNT(invented)')));
  assert.ok(namedWindowRefusals.some(item => item.text.includes('HAVING TRUE WINDOW unused')));
});

test('named-window independent oracles retain NULLs multiplicity frames and scope', () => {
  const cases = new Map(namedWindowSuccesses.map(item => [item.name, item]));
  assert.deepEqual(JSON.parse(cases.get('named-window-independent-json').text), namedWindowProgram);
  assert.deepEqual(cases.get('named-window-bare-reference').expected,
    [{id: 2, n: 1}, {id: 3, n: 2}, {id: 3, n: 3}, {id: 1, n: 4}]);
  assert.deepEqual(cases.get('named-window-declaration-inheritance').expected,
    [{id: 1, n: 1}, {id: 2, n: 1}, {id: 3, n: 1}, {id: 3, n: 2}]);
  assert.deepEqual(cases.get('named-window-qualify-alias-collision').expected, [{amount: 20, id: 1}]);
  assert.deepEqual(cases.get('named-window-qualify-qualified-control').expected, [{amount: null, id: 4}]);
  assert.deepEqual(cases.get('named-window-typed-empty').columns, cases.get('named-window-bare-reference').columns);
  assert.deepEqual(cases.get('named-window-unused-specification-no-evaluation').expected,
    cases.get('named-window-bare-reference').expected);
  const all = [...namedWindowSuccesses, ...namedWindowRefusals];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('named WINDOW is registered in both ordinary and narrow public acceptance', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...namedWindowSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...namedWindowRefusals)'));
  assert.match(fixture, /const scopeOnly = [^;]*namedWindowOnly/u);
  assert.ok(fixture.includes('namedWindowOnly ? {successes: namedWindowSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_NAMED_WINDOW_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/named-window-source-input.mjs', 'named-window-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--named-window-only'/u);
  assert.match(driver, /if \(process\.argv\.includes\('--named-window-only'\)\) return;/u);
});
