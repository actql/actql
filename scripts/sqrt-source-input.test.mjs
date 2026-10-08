import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {sqrtSuccesses, sqrtRefusals, sqrtExecutionFailures} from './fixtures/sqrt-source-input.mjs';
import {exercisePublicQueryInput} from './fixtures/public-query-input.mjs';

const cases = new Map(sqrtSuccesses.map(item => [item.name, item]));
test('sqrt expectations retain independent finite values, typed NULLs and duplicate rows', () => {
  assert.deepEqual(cases.get('sqrt-finite-values').expected,
    [{zero: 0, fractional: 0.5, exact: 1.5, irrational: 1.4142135623730951}]);
  assert.deepEqual(cases.get('sqrt-finite-extremes').expected,
    [{tiny: 2.2227587494850775e-162, large: 1.3407807929942596e154}]);
  assert.deepEqual(cases.get('sqrt-sql-field').expected,
    [{id: 1, value: 2}, {id: 2, value: null}, {id: 3, value: 3}, {id: 3, value: 3}]);
  assert.deepEqual(cases.get('sqrt-pipe-field').expected, cases.get('sqrt-sql-field').expected);
  assert.deepEqual(cases.get('sqrt-literal-null').columns,
    ['value', 'typed_value'].map(name => ({name, contract: {type: 'number', nullable: true}})));
  assert.deepEqual(JSON.parse(cases.get('sqrt-json-control').text).stages[0].steps[1].derive.value,
    {sqrt: {literal: 9}});
  const all = [...sqrtSuccesses, ...sqrtRefusals, ...sqrtExecutionFailures];
  assert.equal(new Set(all.map(item => item.name)).size, all.length);
});

test('sqrt fixtures distinguish preparation refusal, demanded domain failure and lazy demand', () => {
  assert.equal(sqrtRefusals.length, 7);
  assert.equal(sqrtExecutionFailures.length, 3);
  assert.deepEqual(cases.get('sqrt-lazy-negative').expected, [{value: 7}]);
  assert.deepEqual(cases.get('sqrt-empty-negative').expected, []);
  assert.deepEqual(cases.get('sqrt-empty-negative').columns,
    ['id', 'value'].map(name => ({name, contract: {type: 'number', nullable: false}})));
  const rows = sqrtExecutionFailures.find(item => item.name === 'sqrt-negative-after-valid-row');
  assert.deepEqual(rows.sourceRows, [{id: 1, amount: 4}, {id: 2, amount: -1}]);
  assert.equal(rows.sourceReadSessionCount, 1);
  assert.ok(sqrtExecutionFailures.every(item => item.resultNames.length === 1));
});

test('sqrt corpus participates in normal packed execution and its narrow selection', async () => {
  const fixture = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  for (const [kind, group] of [['successes', 'sqrtSuccesses'], ['refusals', 'sqrtRefusals'],
    ['executionFailures', 'sqrtExecutionFailures']]) {
    assert.ok(fixture.includes(`scopeInputs.${kind}.push(...${group})`));
  }
  assert.ok(fixture.includes('sqrtOnly ? {successes: sqrtSuccesses'));
  assert.match(fixture, /const scopeOnly = [^;]*\bsqrtOnly\b/u);
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_SQRT_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/sqrt-source-input.mjs', 'sqrt-source-input.mjs']"));
  assert.match(driver, /const narrowPublicQuery = process\.argv\.some\(flag => \[[^;]*'--sqrt-only'/u);
  assert.ok(driver.includes("if (process.argv.includes('--sqrt-only')) return;"));
});

test('execution failures install authored rows without sending fixture metadata to the Client', async () => {
  const failures = ['sqrt-negative-after-valid-row', 'sqrt-demanded-operand']
    .map(name => sqrtExecutionFailures.find(item => item.name === name));
  let installed, acceptedRuns = 0, sourceReadSessions = 0, starts = 0, closed = 0;
  const prepared = [], executions = new Map();
  const denied = async () => { throw Object.assign(new Error('unpublished'), {code: 'ResultAccessDenied'}); };
  const client = {
    newSubmission: ({nonce}) => ({nonce}),
    async startSource(text, input) {
      starts++;
      assert.equal(Object.hasOwn(input, 'sourceRows'), false);
      assert.equal(input.format, 'sql');
      const failure = failures.find(item => item.text === text);
      assert.ok(failure);
      const key = input.submissionRef.nonce;
      if (executions.has(key)) return executions.get(key);
      assert.deepEqual(installed, failure.sourceRows);
      if (installed !== undefined) assert.ok(installed.some(row => row.amount < 0));
      acceptedRuns++;
      sourceReadSessions += failure.sourceReadSessionCount;
      const execution = {ref: {id: key}, async wait() { return {status: 'failed'}; },
        async status() { return {status: 'failed'}; }, result() { return {all: denied, describe: denied}; }};
      executions.set(key, execution);
      return execution;
    },
    async attach(ref) { return executions.get(ref.id); },
    async lookupSubmission(submissionRef) {
      return {kind: 'ready', submissionRef, admission: {ref: executions.get(submissionRef.nonce).ref}};
    },
    async close() { closed++; },
  };
  await exercisePublicQueryInput(async () => client, {}, {
    requestPrefix: 'sqrt-row-handoff', successes: [], refusals: [], executionFailures: failures,
    prepareCase(rows) { prepared.push(rows); installed = rows; },
    observe: () => ({acceptedRuns, sourceIo: sourceReadSessions, sourceReadSessions}),
  });
  assert.deepEqual(prepared, [failures[0].sourceRows, undefined]);
  assert.deepEqual({acceptedRuns, sourceReadSessions, starts, closed},
    {acceptedRuns: 2, sourceReadSessions: 1, starts: 4, closed: 1});
});
