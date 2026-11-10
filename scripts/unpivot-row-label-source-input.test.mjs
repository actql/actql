import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {unpivotRowLabelSuccesses, unpivotRowLabelRefusals}
  from './fixtures/unpivot-row-label-source-input.mjs';

test('UNPIVOT row-label oracle distinguishes repeated occurrences NULL and renamed defaults', () => {
  const cases = new Map(unpivotRowLabelSuccesses.map(item => [item.name, item]));
  const control = cases.get('unpivot-row-label-json-control');
  const steps = JSON.parse(control.text).stages[0].steps;
  assert.deepEqual(steps[1].select,
    ['id', 'feb', {first_input: 'jan'}, {second_input: 'jan'}]);
  assert.deepEqual(steps[3].derive.month, {if: [
    {eq: [{field: 'private_name'}, {literal: 'first_input'}]},
    {literal: 'first'}, {literal: 'second'}]});
  assert.deepEqual(control.expected, [{id: 1, amount: null, month: 'first'},
    {id: 1, amount: null, month: 'second'},
    {id: 2, amount: 7, month: 'first'}, {id: 2, amount: 7, month: 'first'},
    {id: 2, amount: 7, month: 'second'}, {id: 2, amount: 7, month: 'second'}]);
  assert.deepEqual(cases.get('unpivot-row-label-from-repeated').expected, control.expected);
  assert.deepEqual(cases.get('unpivot-row-label-pipe-excluded').expected, control.expected.slice(2));
  assert.deepEqual(cases.get('unpivot-row-label-empty').expected, []);
  assert.deepEqual(cases.get('unpivot-row-label-empty').columns, control.columns);
  assert.deepEqual(control.columns.map(column => column.name), ['id', 'amount', 'month']);
  assert.deepEqual(control.columns, [
    {name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'amount', contract: {type: 'number', nullable: true}},
    {name: 'month', contract: {type: 'string', nullable: false, max_utf8_bytes: 6}},
  ]);
  assert.deepEqual(cases.get('unpivot-row-label-renamed-default').columns.at(-1),
    {name: 'month', contract: {type: 'string', nullable: false, max_utf8_bytes: 7}});
  assert.deepEqual(cases.get('unpivot-row-label-same-label').columns.at(-1),
    {name: 'month', contract: {type: 'string', nullable: false, max_utf8_bytes: 4}});
  assert.equal(cases.get('unpivot-row-label-same-label').expected.length, 6);
  assert.equal(cases.get('unpivot-row-label-same-label').expected.filter(row => row.amount === null).length, 2);
  assert.equal(cases.get('unpivot-row-label-renamed-default').expected[0].month, 'current');
  assert.equal(unpivotRowLabelSuccesses.length, 6);
  assert.equal(unpivotRowLabelRefusals.length, 5);
  assert.equal(unpivotRowLabelRefusals.find(item => item.name.endsWith('exact-integer-gap')).expectedCode,
    'ClientProgramInvalidInput');
});

test('UNPIVOT row-label cases run in ordinary packed corpus and retain actual completion data', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'unpivotRowLabelSuccesses'], ['refusals', 'unpivotRowLabelRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('unpivotRowLabelOnly ? {successes: unpivotRowLabelSuccesses'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_UNPIVOT_ROW_LABEL_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/unpivot-row-label-source-input.mjs', 'unpivot-row-label-source-input.mjs']"));
  assert.ok(driver.includes("if (process.argv.includes('--unpivot-row-label-only')) return;"));
  assert.ok(driver.includes("'unpivot-row-label-receipts.local.json'"));
  assert.ok(driver.includes("'unpivot-row-label-receipts.remote.json'"));
  assert.ok(fixture.indexOf('await unpivotRowLabelReceipts.complete()') > fixture.indexOf('requireCompleteInventory'));
});
