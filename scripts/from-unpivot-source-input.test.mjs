import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {fromUnpivotSuccesses, fromUnpivotRefusals} from './fixtures/from-unpivot-source-input.mjs';
import {createVerifiedCaseReceipts} from './fixtures/cte-value-table-receipts.mjs';

test('FROM UNPIVOT independently fixes NULL duplicate ordering and bounded JOIN expectations', () => {
  const cases = new Map(fromUnpivotSuccesses.map(item => [item.name, item]));
  const include = cases.get('from-unpivot-include-json-control');
  const exclude = cases.get('from-unpivot-exclude-json-control');
  assert.deepEqual(include.expected, [{id: 1, amount: 5, month: 'feb'},
    {id: 1, amount: null, month: 'jan'}, {id: 2, amount: null, month: 'feb'},
    {id: 2, amount: null, month: 'feb'}, {id: 2, amount: 7, month: 'jan'},
    {id: 2, amount: 7, month: 'jan'}]);
  assert.deepEqual(exclude.expected, [{id: 1, amount: 5, month: 'feb'},
    {id: 2, amount: 7, month: 'jan'}, {id: 2, amount: 7, month: 'jan'}]);
  assert.deepEqual(JSON.parse(include.text).stages[0].steps[1].unpivot,
    {columns: ['jan', 'feb'], keep: ['id'], value_column: 'amount', name_column: 'month'});
  assert.deepEqual(cases.get('from-unpivot-default').expected, exclude.expected);
  assert.deepEqual(cases.get('from-unpivot-filtered-limit-offset').expected,
    [{id: 2, amount: 7, month: 'jan'}]);
  for (const name of ['left-join-port', 'right-join-port']) {
    const item = cases.get('from-unpivot-' + name);
    assert.match(item.text, /MAX_OUTPUT_ROWS 10/u);
    assert.deepEqual(item.expected, [{id: 2, amount: null, month: 'feb', marker: 100},
      {id: 2, amount: null, month: 'feb', marker: 100},
      {id: 2, amount: 7, month: 'jan', marker: 100},
      {id: 2, amount: 7, month: 'jan', marker: 100}]);
    assert.deepEqual(item.columns.map(column => column.name), ['id', 'amount', 'month', 'marker']);
  }
  assert.deepEqual(cases.get('from-unpivot-empty').expected, []);
  assert.deepEqual(cases.get('from-unpivot-empty').columns, include.columns);
  assert.deepEqual(include.columns, [{name: 'id', contract: {type: 'number', nullable: false}},
    {name: 'amount', contract: {type: 'number', nullable: true}},
    {name: 'month', contract: {type: 'string', nullable: false}}]);
  assert.equal(fromUnpivotSuccesses.length, 9);
  assert.equal(fromUnpivotRefusals.length, 6);
  assert.equal(fromUnpivotRefusals.find(item => item.name.endsWith('value-table')).expectedCode,
    'ClientProgramRejected');
  assert.ok(fromUnpivotRefusals.filter(item => !item.name.endsWith('value-table'))
    .every(item => item.expectedCode === 'ClientProgramInvalidInput'));
});

test('FROM UNPIVOT joins ordinary public acceptance and retains actual completion observations', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'fromUnpivotSuccesses'], ['refusals', 'fromUnpivotRefusals']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('fromUnpivotOnly ? {successes: fromUnpivotSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bfromUnpivotOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_FROM_UNPIVOT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/from-unpivot-source-input.mjs', 'from-unpivot-source-input.mjs']"));
  assert.ok(driver.includes("if (process.argv.includes('--from-unpivot-only')) return;"));
  for (const mode of ['local', 'remote']) assert.ok(driver.includes(`'from-unpivot-receipts.${mode}.json'`));
  assert.match(fixture, /if \(item\.name\.startsWith\('from-unpivot-'\)\) await fromUnpivotReceipts\.record\(item, mode\)/u);
  assert.ok(fixture.indexOf('await fromUnpivotReceipts.complete()') > fixture.indexOf('requireCompleteInventory'));
});

test('generic receipt collector keeps actual values separate from authored expectations', async () => {
  const files = new Map();
  const collector = createVerifiedCaseReceipts('local', async (path, text) => {
    files.set(path, JSON.parse(text));
  }, {prefix: 'from-unpivot', version: 'actql-from-unpivot-acceptance/0.1'});
  await collector.complete();
  assert.equal(files.size, 0);
  const actual = {name: 'from-unpivot-empty', ref: {runId: 'actual-completed-run'},
    observedResults: {answer: {rows: [], columns: fromUnpivotSuccesses[6].columns}},
    beforeSubmit: {acceptedRuns: 0}, beforeRead: {acceptedRuns: 1}};
  await collector.record(actual);
  assert.equal(files.get('from-unpivot-receipts.local.json').complete, false);
  await collector.complete();
  assert.deepEqual(files.get('from-unpivot-receipts.local.json'), {
    version: 'actql-from-unpivot-acceptance/0.1', mode: 'local', complete: true,
    cases: [{mode: 'local', name: actual.name, ref: actual.ref, results: actual.observedResults,
      beforeSubmit: actual.beforeSubmit, beforeRead: actual.beforeRead}],
  });
});
