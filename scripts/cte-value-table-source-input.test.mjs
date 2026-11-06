import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {cteValueTableSuccesses, cteValueTableRefusals, cteValueTableJoinControl}
  from './fixtures/cte-value-table-source-input.mjs';
import {exercisePublicQueryInput} from './fixtures/public-query-input.mjs';
import {createCteValueTableReceipts} from './fixtures/cte-value-table-receipts.mjs';

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
  assert.ok(driver.includes("['scripts/fixtures/cte-value-table-receipts.mjs', 'cte-value-table-receipts.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_CTE_VALUE_TABLE_ONLY = '1'"));
  for (const mode of ['local', 'remote']) {
    assert.ok(driver.includes(`'cte-value-table-receipts.${mode}.json'`));
  }
});

test('verified case receipts survive the case block and finish at transport completion', async () => {
  const source = cteValueTableSuccesses[1];
  const ref = {runId: 'actual-run'};
  let reads = 0, descriptions = 0, acceptedRuns = 0, submissionRef, saved;
  const files = new Map();
  const receipts = createCteValueTableReceipts('local', async (name, text) => {
    files.set(name, JSON.parse(text));
  });
  const result = {all: async () => {reads++; return structuredClone(source.expected);},
    describe: async () => {descriptions++; return {columns: structuredClone(source.columns)};}};
  const execution = {ref, wait: async () => ({status: 'succeeded'}), result: () => result};
  const client = {newSubmission: value => (submissionRef = value),
    startSource: async () => {acceptedRuns = 1; return execution;}, attach: async () => execution,
    lookupSubmission: async () => ({kind: 'ready', submissionRef, admission: {ref}}), close: async () => {}};
  {
    await exercisePublicQueryInput(async () => client, {}, {requestPrefix: 'receipt',
      observe: () => ({acceptedRuns, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0}),
      successes: [source], refusals: [], completedCase: async item => {
        saved = item;
        await receipts.record(item);
      }});
  }
  const path = 'cte-value-table-receipts.local.json';
  assert.equal(files.get(path).complete, false, 'an individual case is not transport completion');
  await receipts.complete();
  assert.deepEqual(files.get(path), {version: 'actql-cte-value-table-acceptance/0.1', mode: 'local',
    complete: true, cases: [{mode: 'local', name: source.name, ref,
      submissionRef: {nonce: 'receipt-' + source.name},
      results: {main: {rows: source.expected, columns: source.columns}},
      beforeSubmit: {acceptedRuns: 0, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0},
      beforeRead: {acceptedRuns: 1, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0},
      afterReplay: {acceptedRuns: 1, sourceIo: 0, sourceReads: 0, sourceReadSessions: 0}}]});
  assert.deepEqual(saved.ref, ref);
  assert.deepEqual(saved.submissionRef, {nonce: 'receipt-' + source.name});
  assert.deepEqual(saved.observedResults.main, {rows: source.expected, columns: source.columns});
  assert.notEqual(saved.observedResults.main.rows, source.expected,
    'receipt rows come from the reader, not the authored oracle');
  assert.notEqual(saved.observedResults.main.columns, source.columns);
  assert.equal(reads, 2, 'only the existing initial and attached reads');
  assert.equal(descriptions, 1, 'only the existing schema check');
});

test('receipt write failure stays a failure and empty transports manufacture no report', async () => {
  let writes = 0;
  const failure = new Error('fixture disk failure');
  const receipts = createCteValueTableReceipts('remote', async () => {writes++; throw failure;});
  await receipts.complete();
  assert.equal(writes, 0);
  await assert.rejects(receipts.record({name: 'cte-value-table-observed', ref: {runId: 'actual'},
    observedResults: {answer: {rows: [], columns: []}}, beforeSubmit: {}, beforeRead: {}}),
    error => error === failure);
  await assert.rejects(receipts.complete(), error => error === failure);
  assert.equal(writes, 2);
});

test('combined transport receipts preserve each actual observation mode', async () => {
  let report;
  const receipts = createCteValueTableReceipts('both', async (name, text) => {
    assert.equal(name, 'cte-value-table-receipts.both.json');
    report = JSON.parse(text);
  });
  for (const mode of ['local', 'remote']) {
    await receipts.record({name: 'cte-value-table-observed', ref: {runId: mode},
      submissionRef: {nonce: 'original-' + mode},
      observedResults: {answer: {rows: [], columns: []}}, beforeSubmit: {}, beforeRead: {}}, mode);
  }
  await receipts.complete();
  assert.equal(report.complete, true);
  assert.deepEqual(report.cases.map(item => item.mode), ['local', 'remote']);
  assert.deepEqual(report.cases.map(item => item.ref), [{runId: 'local'}, {runId: 'remote'}]);
  assert.deepEqual(report.cases.map(item => item.submissionRef), [
    {nonce: 'original-local'}, {nonce: 'original-remote'}]);
});
