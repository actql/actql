import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {inUnnestSuccesses, inUnnestRefusals, inUnnestExecutionFailures}
  from './fixtures/in-unnest-source-input.mjs';
import {inUnnestLiteralArraySuccesses, inUnnestLiteralArrayRefusals,
  inUnnestLiteralArrayExecutionFailures} from './fixtures/in-unnest-literal-array-source-input.mjs';

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

test('adopted general ARRAY operand is positive with the original bound and public Result', () => {
  const text = 'SELECT 1 IN UNNEST(IF(TRUE, @xs, @xs)) AS included';
  assert.equal(inUnnestRefusals.some(item => item.text === text), false);
  const item = inUnnestSuccesses.find(item => item.name === 'in-unnest-general-array-expression');
  assert.ok(item);
  assert.equal(item.text, text);
  assert.deepEqual(item.parameterDeclarations, {xs: {type: 'array', nullable: true,
    max_items: 3, items: {type: 'number', nullable: true}}});
  assert.deepEqual(item.parameters, {xs: [1]});
  assert.deepEqual(item.expected, [{included: true}]);
  assert.deepEqual(item.columns, [{name: 'included', contract: {type: 'boolean', nullable: true}}]);
  assert.equal(item.sourceReadCount, 0);
  assert.equal(item.sourceReadSessionCount, 0);
  assert.deepEqual(item.results, {main: {rows: item.expected, columns: item.columns}});
  for (const name of ['scalar-rhs', 'wrong-item-domain', 'bound-exceeded', 'multiple-arguments']) {
    assert.ok(inUnnestRefusals.some(item => item.name === 'in-unnest-' + name));
  }
});

test('membership public text Results use main and authored JSON retains answer', () => {
  for (const item of inUnnestSuccesses) {
    if (item.format === 'json') {
      assert.deepEqual(Object.keys(JSON.parse(item.text).results), ['answer']);
      assert.equal(item.results, undefined);
    } else {
      assert.deepEqual(item.results, {main: {rows: item.expected, columns: item.columns}});
    }
  }
  assert.deepEqual(inUnnestExecutionFailures[0].resultNames, ['main']);
});

test('normal packed acceptance registers the array predicate and its bounded narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const membership = await readFile(new URL('./fixtures/in-unnest-literal-array-source-input.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'inUnnestSuccesses'], ['refusals', 'inUnnestRefusals'],
    ['executionFailures', 'inUnnestExecutionFailures']]) {
    const selected = {successes: inUnnestLiteralArraySuccesses, refusals: inUnnestLiteralArrayRefusals,
      executionFailures: inUnnestLiteralArrayExecutionFailures}[kind];
    const original = {successes: inUnnestSuccesses, refusals: inUnnestRefusals,
      executionFailures: inUnnestExecutionFailures}[kind];
    assert.ok(original.every(item => selected.includes(item)), group);
    const active = {successes: 'inUnnestLiteralArraySuccesses', refusals: 'inUnnestLiteralArrayRefusals',
      executionFailures: 'inUnnestLiteralArrayExecutionFailures'}[kind];
    const registration = `scopeInputs.${kind}.push(...${active})`;
    assert.equal(fixture.split(registration).length - 1, 1,
      `${group} must be registered exactly once in the normal corpus`);
  }
  assert.ok(membership.includes("from './in-unnest-source-input.mjs'"));
  assert.ok(fixture.includes('inUnnestLiteralArrayOnly ? {successes: inUnnestLiteralArraySuccesses'));
  assert.ok(fixture.includes('executionFailures: inUnnestLiteralArrayExecutionFailures'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_IN_UNNEST_LITERAL_ARRAY_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/in-unnest-source-input.mjs', 'in-unnest-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--in-unnest-literal-array-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--in-unnest-literal-array-only')) return;"));
});
