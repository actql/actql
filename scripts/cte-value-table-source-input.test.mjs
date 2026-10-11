import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {cteValueTableSuccesses, cteValueTableRefusals, cteValueTableJoinControl}
  from './fixtures/cte-value-table-source-input.mjs';
import {exercisePublicQueryInput} from './fixtures/public-query-input.mjs';

test('CTE value-table controls preserve NULL duplicates and the declared join bound', () => {
  assert.equal(cteValueTableSuccesses.length, 9);
  assert.equal(cteValueTableRefusals.length, 2);
  const cases = new Map(cteValueTableSuccesses.map(item => [item.name, item]));
  assert.deepEqual(cases.get('cte-value-table-scalar').expected, [{value: null}, {value: 2}, {value: 2}]);
  assert.deepEqual(cases.get('cte-value-table-shared-join').expected,
    [{value: 2}, {value: 2}, {value: 2}, {value: 2}]);
  assert.deepEqual(cteValueTableJoinControl.stages[0].steps[1].join,
    {with: 'elements', kind: 'inner', on: [{left: 'element', right: 'element'}],
      max_output_rows: 10, select: {value: 'left.element'}});
  assert.deepEqual(cases.get('cte-value-table-nullable-object').expected,
    [{value: null, id: null}, {value: {id: 2, label: null}, id: 2}, {value: {id: 2, label: 'kept'}, id: 2}]);
  for (const item of cteValueTableSuccesses) assert.equal(item.sourceReadSessionCount, 0);
});

test('CTE value-table cases run in the normal public corpus and a narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(fixture.includes('scopeInputs.successes.push(...cteValueTableSuccesses)'));
  assert.ok(fixture.includes('scopeInputs.refusals.push(...cteValueTableRefusals)'));
  assert.ok(fixture.includes('ACTQL_TEST_CTE_VALUE_TABLE_ONLY'));
  assert.ok(driver.includes("['scripts/fixtures/cte-value-table-source-input.mjs', 'cte-value-table-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_CTE_VALUE_TABLE_ONLY = '1'"));
  for (const mode of ['local', 'remote']) {
    assert.ok(driver.includes(`'cte-value-table-receipts.${mode}.json'`));
  }
});

test('completed-case receipts use actual rows and columns without an extra read', async () => {
  const source = cteValueTableSuccesses[1];
  const ref = {runId: 'actual-run'};
  let reads = 0, descriptions = 0, acceptedRuns = 0, submissionRef, saved;
  const result = {all: async () => {reads++; return structuredClone(source.expected);},
    describe: async () => {descriptions++; return {columns: structuredClone(source.columns)};}};
  const execution = {ref, wait: async () => ({status: 'succeeded'}), result: () => result};
  const client = {newSubmission: value => (submissionRef = value),
    startSource: async () => {acceptedRuns = 1; return execution;}, attach: async () => execution,
    lookupSubmission: async () => ({kind: 'ready', submissionRef, admission: {ref}}), close: async () => {}};
  await exercisePublicQueryInput(async () => client, {}, {requestPrefix: 'receipt',
    observe: () => ({acceptedRuns, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0}),
    successes: [source], refusals: [], completedCase: item => {saved = item;}});
  assert.deepEqual(saved.ref, ref);
  assert.deepEqual(saved.observedResults.answer, {rows: source.expected, columns: source.columns});
  assert.notEqual(saved.observedResults.answer.rows, source.expected,
    'receipt rows come from the reader, not the authored oracle');
  assert.notEqual(saved.observedResults.answer.columns, source.columns);
  assert.equal(reads, 2, 'only the existing initial and attached reads');
  assert.equal(descriptions, 1, 'only the existing schema check');
});
