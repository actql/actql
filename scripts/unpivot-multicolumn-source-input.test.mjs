import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {unpivotMulticolumnSuccesses, unpivotMulticolumnRefusals}
  from './fixtures/unpivot-multicolumn-source-input.mjs';

test('tuple oracle preserves partial NULL duplicate rows ordered contracts and empty typing', () => {
  const cases = new Map(unpivotMulticolumnSuccesses.map(item => [item.name, item]));
  const exclude = cases.get('unpivot-multicolumn-json-exclude-control');
  const include = cases.get('unpivot-multicolumn-json-include-control');
  assert.deepEqual(exclude.expected, [
    {id: 1, amount: null, note: 'kept', month: 'Feb'},
    {id: 1, amount: 5, note: null, month: 'Jan'},
    {id: 2, amount: 7, note: 'B', month: 'Feb'},
    {id: 2, amount: 7, note: 'B', month: 'Feb'},
  ]);
  assert.deepEqual(include.expected.slice(4), [
    {id: 2, amount: null, note: null, month: 'Jan'},
    {id: 2, amount: null, note: null, month: 'Jan'},
  ]);
  assert.deepEqual(JSON.parse(exclude.text).stages[0].steps[5], {filter: {or: [
    {not: {is_null: {field: 'amount'}}}, {not: {is_null: {field: 'note'}}},
  ]}});
  assert.equal(JSON.parse(include.text).stages[0].steps.some(step => step.filter), false);
  assert.deepEqual(exclude.columns, [
    {name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'amount', contract: {type: 'number', nullable: true}},
    {name: 'note', contract: {type: 'string', nullable: true}},
    {name: 'month', contract: {type: 'string', nullable: false, max_utf8_bytes: 3}},
  ]);
  const empty = cases.get('unpivot-multicolumn-typed-empty');
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, exclude.columns);
  assert.deepEqual(empty.parameters, {rows: []});
  assert.equal(cases.get('unpivot-multicolumn-default-labels').columns.at(-1).contract.max_utf8_bytes, 19);
  assert.equal(cases.get('unpivot-multicolumn-renamed-default-labels').columns.at(-1).contract.max_utf8_bytes, 21);
  const gap = unpivotMulticolumnRefusals.at(-1);
  assert.equal(gap.parameterDeclarations.rows.items.fields.jan_amount.nullable, false);
  assert.equal(gap.parameterDeclarations.rows.items.fields.feb_amount.nullable, true);
  assert.equal(gap.parameters.rows[0].jan_amount, 5);
  assert.equal(unpivotMulticolumnSuccesses.length, 7);
  assert.equal(unpivotMulticolumnRefusals.length, 6);
});

test('tuple cases use the existing full corpus and actual completion receipts', async () => {
  const packed = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, exportName] of [['successes', 'unpivotMulticolumnSuccesses'],
    ['refusals', 'unpivotMulticolumnRefusals']]) {
    assert.ok(packed.includes(`scopeInputs.${kind}.push(...${exportName})`));
  }
  assert.ok(packed.includes('unpivotMulticolumnOnly ? {successes: unpivotMulticolumnSuccesses'));
  assert.ok(packed.includes("if (item.name.startsWith('unpivot-multicolumn-')) await unpivotMulticolumnReceipts.record(item, mode)"));
  assert.ok(packed.indexOf('await unpivotMulticolumnReceipts.complete()') > packed.indexOf('requireCompleteInventory'));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_UNPIVOT_MULTICOLUMN_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/unpivot-multicolumn-source-input.mjs', 'unpivot-multicolumn-source-input.mjs']"));
  assert.ok(driver.includes("'unpivot-multicolumn-receipts.local.json'"));
  assert.ok(driver.includes("'unpivot-multicolumn-receipts.remote.json'"));
});
