import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {ceilingSuccesses, ceilingRefusals, ceilingExecutionFailures}
  from './fixtures/ceiling-source-input.mjs';

const cases = new Map(ceilingSuccesses.map(item => [item.name, item]));
test('ceiling expectations distinguish floor and truncation and retain typed NULLs and duplicates', () => {
  assert.deepEqual(cases.get('ceiling-fractional-and-integral').expected,
    [{positive: 3, negative: -2, integral: 2, zero: 0}]);
  assert.deepEqual(cases.get('ceiling-sql-field').expected,
    [{id: 1, value: 3}, {id: 2, value: null}, {id: 3, value: -2}, {id: 3, value: -2}]);
  assert.deepEqual(cases.get('ceiling-pipe-field').expected, cases.get('ceiling-sql-field').expected);
  assert.deepEqual(cases.get('ceiling-empty').expected, []);
  assert.deepEqual(cases.get('ceiling-empty').columns, cases.get('ceiling-sql-field').columns);
  assert.deepEqual(cases.get('ceiling-literal-null').columns,
    ['value', 'typed_value'].map(name => ({name, contract: {type: 'number', nullable: true}})));
  assert.deepEqual(cases.get('ceiling-finite-extremes').expected,
    [{tiny: 1, large: 1.7976931348623157e308}]);
  const control = JSON.parse(cases.get('ceiling-json-control').text);
  assert.deepEqual(control.stages[0].steps[1].derive.value,
    {negate: {floor: {subtract: [{literal: 0}, {literal: -2.3}]}}});
  const all = [...ceilingSuccesses, ...ceilingRefusals, ...ceilingExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('alias-first and qualified-input sort expectations have opposite orders', () => {
  const alias = cases.get('ceiling-order-output-alias');
  const input = cases.get('ceiling-order-qualified-input');
  assert.deepEqual(alias.expected.map(row => row.id), [1, 3, 3, 2]);
  assert.deepEqual(input.expected.map(row => row.id), [3, 3, 1, 2]);
  assert.deepEqual(alias.sourceRows, input.sourceRows);
  assert.deepEqual(alias.columns, input.columns);
  assert.equal(alias.sourceReadSessionCount, 1);
  assert.equal(input.sourceReadSessionCount, 1);
});

test('authored ceiling cases are registered in ordinary packed acceptance and its focused selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'ceilingSuccesses'], ['refusals', 'ceilingRefusals'],
    ['executionFailures', 'ceilingExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('ceilingOnly ? {successes: ceilingSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bceilingOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_CEILING_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/ceiling-source-input.mjs', 'ceiling-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--ceiling-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--ceiling-only')) return;"));
});
