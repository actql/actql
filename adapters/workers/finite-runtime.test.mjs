import assert from 'node:assert/strict';
import test from 'node:test';
import {buildFiniteConformance} from './build.mjs';
import {createTestRuntime} from './runtime.mjs';
import {runFiniteCase} from './finite-runtime-fixture.mjs';

const transport = value => JSON.parse(JSON.stringify(value,
  (_, item) => typeof item === 'bigint' ? String(item) : item));
let bundle;
async function onBoth(inputs, inspect) {
  bundle ??= buildFiniteConformance();
  const {source} = await bundle;
  let outbound = 0;
  const runtime = createTestRuntime(source, {onOutbound: () => outbound++});
  try {
    for (const input of inputs) {
      const node = transport(await runFiniteCase(input));
      const response = await runtime.dispatchFetch('http://worker.test/', {
        method: 'POST', body: JSON.stringify(input),
      });
      assert.equal(response.status, 200, await response.clone().text());
      const worker = await response.json();
      assert.deepEqual(worker, node, 'Node and workerd must execute the same original-owner boundary');
      inspect(worker, input);
    }
    assert.equal(outbound, 0, 'finite execution must not perform outbound I/O');
  } finally { await runtime.dispose(); }
}

function released(value) {
  assert.equal(value.released, true);
  assert.deepEqual(value.scopedUsage.slice(4), ['0', '0', '0', '0']);
  assert.deepEqual(value.finalUsage, value.scopedUsage, 'safety cleanup must not hide scoped retention');
  assert.deepEqual(value.authorizationResources, {
    retainedDecisions: 0, scopeDecisions: 0, inFlightDecisions: 0, scopeInFlightDecisions: 0,
  });
}

// Expectations are written from the authored input and Relation contract;
// neither rows nor schema expectations come from product-generated output.
test('finite public entry prepares and executes one original Values Run on Node and workerd', async () => {
  await onBoth([
    {rows: [{id: 1}, {id: 2}]},
    {rows: [{id: 4}, {id: 3}, {id: 4}, {id: 2}]},
    {rows: []},
    {rows: [{id: null}, {id: 3}, {id: null}], nullable: true},
    {rows: [{id: 2}], hashSeed: 2147483647},
  ], (value, input) => {
    assert.equal(value.status, 'completed', JSON.stringify(value));
    assert.equal(value.openedFinished, false, 'fresh source-free task zero is not completed');
    assert.equal(value.finishedAtConsumption, true, 'actual task-zero completion establishes finished');
    assert.equal(value.finishedAfterExecution, true, 'resource close preserves established completion');
    assert.deepEqual(value.rows, input.rows);
    assert.deepEqual(value.schema, {id: {type: 'number', nullable: input.nullable ?? false}});
    assert.deepEqual(value.completedTasks, [0]);
    assert.equal(value.sites.length, 1);
    assert.deepEqual(value.sites[0], {key: 'in-process-default', generation: 0,
      runtimeRevision: 'actql-in-process-site/0.1'});
    assert.equal(value.consumed, 1);
    assert.equal(value.counters.evaluations, 1);
    assert.equal(value.counters.protectedDispatches, 1);
    assert.equal(value.counters.coveredOperations, 0);
    assert.equal(value.duplicateOpen, 'WorkersFiniteRunAlreadyOpened');
    assert.equal(value.duplicateExecution, 'WorkersFiniteExecutionAlreadyStarted');
    assert.deepEqual(value.openedUsage, value.duplicateOpenUsage);
    assert.ok(BigInt(value.finalUsage[0]) >= BigInt(value.openedUsage[0]));
    assert.equal(value.finalUsage[1], '1');
    released(value);
  });
});

test('finite protected activation denies explicit and missing Account authority before attempts', async () => {
  await onBoth([{outcome: 'deny'}, {outcome: 'missing'}], (value, input) => {
    assert.equal(value.status, 'failed');
    assert.equal(value.phase, 'execution');
    assert.equal(value.openedFinished, false);
    assert.ok(value.codes.includes('ExecutionAuthorizationDenied'), JSON.stringify(value));
    assert.ok(value.codes.includes(input.outcome === 'deny'
      ? 'ACTQL_E_ACCOUNT_DENIED' : 'ACTQL_E_ACCOUNT_CONFIG_INVALID'));
    assert.equal(value.consumed, 0);
    assert.equal(value.counters.evaluations, 1);
    assert.equal(value.counters.deniedBeforeDispatch, 1);
    assert.equal(value.counters.protectedDispatches, 0);
    assert.equal(value.finalUsage[1], '0');
    assert.equal(value.cleanupPending, false);
    released(value);
  });
});

test('finite cancellation before activation never starts a physical attempt', async () => {
  await onBoth([{cancel: 'preaborted'}, {cancel: 'immediate'}], value => {
    assert.equal(value.status, 'failed');
    assert.equal(value.consumed, 0);
    assert.equal(value.finalUsage[1], '0');
    assert.equal(value.cleanupPending, false);
    released(value);
  });
});

test('finite capacity refusal and consumer failure retain cleanup without a replacement Run', async () => {
  await onBoth([{maxRows: 0}, {consumeFailure: true}], (value, input) => {
    assert.equal(value.status, 'failed');
    assert.equal(value.duplicateOpen, 'WorkersFiniteRunAlreadyOpened');
    assert.equal(value.consumed, input.consumeFailure ? 1 : 0);
    assert.equal(value.cleanupPending, false);
    if (input.consumeFailure) assert.ok(value.codes.includes('finite consumer failure'));
    else assert.equal(value.finalUsage[1], '0');
    released(value);
  });
});

test('canonical direct close releases retained finite task zero before scoped cleanup', async () => {
  await onBoth([{directClose: true}], value => {
    assert.equal(value.status, 'completed', JSON.stringify(value));
    assert.ok(BigInt(value.beforeClose[5]) > 0n, 'task zero must retain a physical output before close');
    assert.deepEqual(value.afterClose.slice(4), ['0', '0', '0', '0']);
    assert.equal(value.outputAfterClose, false);
    released(value);
  });
});

test('concurrent finite original Runs retain independent results and cancellation in one Worker', async () => {
  bundle ??= buildFiniteConformance();
  const runtime = createTestRuntime((await bundle).source);
  try {
    const response = await runtime.dispatchFetch('http://worker.test/', {
      method: 'POST', body: JSON.stringify([
        {rows: [{id: 7}], cancel: 'immediate'}, {rows: [{id: 8}, {id: 8}]},
      ]),
    });
    assert.equal(response.status, 200, await response.clone().text());
    const [cancelled, completed] = await response.json();
    assert.equal(cancelled.status, 'failed');
    assert.equal(cancelled.finalUsage[1], '0');
    assert.equal(completed.status, 'completed');
    assert.deepEqual(completed.rows, [{id: 8}, {id: 8}]);
    released(cancelled);
    released(completed);
  } finally { await runtime.dispose(); }
});
