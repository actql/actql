import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {pipePivotSuccesses, pipePivotRefusals, pivotCountStarProgram} from './fixtures/pipe-pivot-source-input.mjs';

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
  assert.deepEqual(cases.get('pipe-pivot-anonymous-count-empty-source').expected,
    [{second: 0, first: 1}]);
  assert.deepEqual(cases.get('pipe-pivot-anonymous-count-identity-source').expected,
    [{other: 0, second: 1, first: 1}]);
  assert.deepEqual(cases.get('pipe-pivot-anonymous-count-json-control').expected,
    cases.get('pipe-pivot-anonymous-count-identity-source').expected);
  assert.deepEqual(cases.get('pipe-pivot-anonymous-count-json-control').columns,
    cases.get('pipe-pivot-anonymous-count-identity-source').columns);
  assert.equal(pipePivotSuccesses.length, 24);
  assert.equal(pipePivotRefusals.length, 16);
  assert.equal(new Set([...pipePivotSuccesses, ...pipePivotRefusals].map(input => input.name)).size, 40);
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

test('HAVING scope oracles preserve named aliases and reject actual anonymous slots', () => {
  const cases = new Map(pipePivotSuccesses.map(input => [input.name, input]));
  const control = cases.get('pipe-pivot-aggregate-having-json-control');
  for (const name of ['pipe-pivot-anonymous-aggregate-having-call',
    'pipe-pivot-authored-aggregate-having-alias']) {
    assert.deepEqual(cases.get(name).expected, control.expected);
    assert.deepEqual(cases.get(name).columns, control.columns);
  }
  const refusals = pipePivotRefusals.filter(input => input.name.includes('anonymous-aggregate-having'));
  assert.equal(refusals.length, 3);
  for (const input of refusals) assert.equal(input.expectedCode, 'ClientProgramInvalidInput');
});


test('COUNT star includes NULL rows while retaining every unconsumed current key', () => {
  const cases = new Map(pipePivotSuccesses.map(input => [input.name, input]));
  assert.deepEqual(cases.get('pipe-pivot-count-star-null-rows').expected, [{n: 1, A: 1}, {n: null, A: 2}]);
  assert.deepEqual(cases.get('pipe-pivot-count-star-json-control').expected, cases.get('pipe-pivot-count-star-null-rows').expected);
  assert.deepEqual(cases.get('pipe-pivot-count-star-json-control').columns, cases.get('pipe-pivot-count-star-null-rows').columns);
  assert.deepEqual(cases.get('pipe-pivot-column-count-contrast').expected, [{A: 1}]);
  assert.deepEqual(cases.get('pipe-pivot-count-star-empty-global').expected, [{n_later: 0, n_first: 0}]);
  assert.deepEqual(cases.get('pipe-pivot-count-star-empty-keyed').expected, []);
  assert.deepEqual(cases.get('pipe-pivot-count-star-prefix-range-axis').columns.map(column => column.name), ['n', 'total_later', 'total_first']);
  assert.deepEqual(pivotCountStarProgram.stages[0].steps[1].derive, {row_witness: {literal: 1}});
  assert.deepEqual(pivotCountStarProgram.stages[0].steps[2].pivot,
    {index: ['n'], column: 'axis', value: 'row_witness', values: ['A'], aggregate: 'count'});
  assert.deepEqual(pivotCountStarProgram.stages[0].steps[4].select, ['n', 'A']);
  const newRefusals = pipePivotRefusals.filter(item => item.name.startsWith('pipe-pivot-refuse-'));
  assert.equal(newRefusals.length, 5);
  assert.ok(newRefusals.every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});
