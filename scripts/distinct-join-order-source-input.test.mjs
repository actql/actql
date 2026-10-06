import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {exercisePublicQueryInput} from './fixtures/public-query-input.mjs';
import {distinctJoinOrderSuccesses as successes, distinctJoinOrderRefusals as refusals,
  distinctJoinOrderExecutionFailures as failures} from './fixtures/distinct-join-order-source-input.mjs';

test('DISTINCT JOIN fixtures distinguish alias and input meanings independently', () => {
  assert.deepEqual(successes.find(x => x.name.endsWith('sql-alias-collision')).expected,
    [{amount: null}, {amount: -1}, {amount: -2}]);
  assert.deepEqual(successes.find(x => x.name.endsWith('selected-qualified-input')).expected,
    [{score: 1}, {score: 2}, {score: null}]);
  const program = JSON.parse(successes[0].text);
  const steps = program.stages[1].steps;
  assert.deepEqual(steps[3], {distinct: ['amount']});
  assert.deepEqual(steps[4], {derive: {sort_only: {negate: {field: 'amount'}}}});
  assert.deepEqual(program.stages[1].inputs.l, program.stages[1].inputs.r);
  const empty = successes.find(x => x.name.endsWith('typed-empty'));
  assert.deepEqual(empty.expected, []);
  assert.deepEqual(empty.columns, [{name: 'amount', contract: {type: 'number', nullable: true}}]);
  assert.equal(successes.length, 7);
  assert.equal(refusals.length, 3);
  assert.equal(failures.length, 1);
});

test('DISTINCT JOIN corpus participates exactly once in normal public acceptance', async () => {
  const text = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  for (const group of ['Successes', 'Refusals', 'ExecutionFailures']) {
    assert.equal(text.split(`.push(...distinctJoinOrder${group});`).length - 1, 1);
  }
  const harness = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(harness.includes("runtimeEnvironment.ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY = '1'"));
  assert.ok(harness.includes("['scripts/fixtures/distinct-join-order-source-input.mjs', 'distinct-join-order-source-input.mjs']"));
});


test('execution-failure acceptance installs authored rows without sending them as Client options', async () => {
  const prepared = [];
  const options = [];
  const counters = {acceptedRuns: 0, sourceIo: 0, sourceReadSessions: 0};
  const ref = {runDefinitionCid: 'fixture.failed'};
  const execution = {ref,
    wait: async () => ({status: 'failed'}),
    status: async () => ({status: 'failed'}),
    result: () => ({
      all: async () => {throw Object.assign(new Error('ResultAccessDenied'), {code: 'ResultAccessDenied'});},
      describe: async () => {throw Object.assign(new Error('ResultAccessDenied'), {code: 'ResultAccessDenied'});},
    }),
  };
  const requests = new Set();
  let closed = false;
  const client = {
    async aql(text, input) {
      options.push(input);
      if (!requests.has(input.requestId)) {
        requests.add(input.requestId);
        counters.acceptedRuns++;
        counters.sourceIo++;
        counters.sourceReadSessions++;
      }
      return execution;
    },
    attach: async () => execution,
    lookupRequest: async () => ({ref}),
    close() {closed = true;},
  };
  await exercisePublicQueryInput(async () => client, {}, {
    requestPrefix: 'failure-row-installation',
    successes: [], refusals: [], executionFailures: failures,
    prepareCase: async rows => prepared.push(rows),
    observe: () => ({...counters}),
  });
  assert.deepEqual(prepared, [failures[0].sourceRows]);
  assert.ok(prepared[0].some(row => row.amount === 2));
  assert.equal(options.length, 2, 'same-request replay is checked');
  assert.ok(options.every(input => !Object.hasOwn(input, 'sourceRows')));
  assert.equal(counters.acceptedRuns, 1);
  assert.equal(counters.sourceReadSessions, 1);
  assert.equal(closed, true);
});
