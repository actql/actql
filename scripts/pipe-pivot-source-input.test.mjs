import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipePivotSuccesses, pipePivotRefusals} from './fixtures/pipe-pivot-source-input.mjs';

test('PIVOT independent controls preserve duplicates NULLs grouping and declared column order', () => {
  const cases = new Map(pipePivotSuccesses.map(input => [input.name, input]));
  const control = JSON.parse(cases.get('pipe-pivot-duplicate-null-json-control').text);
  assert.deepEqual(control.stages[0].steps[1].pivot,
    {index: ['product'], column: 'quarter', value: 'sales', values: ['Q2', 'Q1'], aggregate: 'count'});
  assert.equal(control.stages[0].steps[0].values.rows.length, 3);
  assert.deepEqual(cases.get('pipe-pivot-duplicate-null-json-control').expected,
    [{product: 'kale', second: 0, first: 2}]);
  assert.deepEqual(cases.get('pipe-pivot-duplicate-null-source').expected,
    [{product: 'kale', second: 0, first: 2}]);
  assert.deepEqual(cases.get('pipe-pivot-min-missing-authored-order').columns.map(column => column.name),
    ['product', 'Q2', 'Q1']);
  assert.deepEqual(cases.get('pipe-pivot-empty-global').expected, [{Q2: 0, Q1: 0}]);
  assert.deepEqual(cases.get('pipe-pivot-empty-keyed').expected, []);
  assert.ok(cases.get('pipe-pivot-empty-keyed').columns.slice(1).every(column => column.contract.nullable));
  assert.deepEqual(cases.get('pipe-pivot-current-value').expected, [{product: 'kale', present: 99}]);
  assert.equal(cases.get('pipe-pivot-duplicate-null-json-control').columns[0].contract.max_utf8_bytes, undefined);
  assert.equal(cases.get('pipe-pivot-min-missing-authored-order').columns[0].contract.max_utf8_bytes, Buffer.byteLength('kale', 'utf8'));
  assert.deepEqual(cases.get('pipe-pivot-anonymous-set-operands').expected,
    [{product: 'kale', second: 0, first: 2}]);
  assert.deepEqual(cases.get('pipe-pivot-anonymous-set-operands').columns,
    cases.get('pipe-pivot-duplicate-null-source').columns);
  assert.equal(pipePivotRefusals.some(input => input.name.endsWith('anonymous-set-operands')), false);
  assert.equal(pipePivotSuccesses.length, 9);
  assert.equal(pipePivotRefusals.length, 8);
  assert.equal(new Set([...pipePivotSuccesses, ...pipePivotRefusals].map(input => input.name)).size, 17);
});

test('PIVOT uses the same cases in the normal corpus and scoped packed execution', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(packed.includes('scopeInputs.successes.push(...pipePivotSuccesses)'));
  assert.ok(packed.includes('scopeInputs.refusals.push(...pipePivotRefusals)'));
  assert.ok(packed.includes('pipePivotOnly ? {successes: pipePivotSuccesses'));
  assert.ok(packed.match(/^const scopeOnly = (.+);$/mu)[1].includes('pipePivotOnly'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_PIPE_PIVOT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/pipe-pivot-source-input.mjs', 'pipe-pivot-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^\]]*'--pipe-pivot-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--pipe-pivot-only')) return;"));
});
