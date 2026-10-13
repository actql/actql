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
      runtimeRevision: 'actql-in-process-site/0.1', accepting: true});
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
    else {
      // Local row-capacity refusal occurs after the original attempt starts.
      // A refused output releases physical resources, not the charged attempt.
      assert.equal(value.phase, 'execution');
      assert.equal(value.finalUsage[1], '1');
      assert.equal(value.counters.evaluations, 1);
      assert.equal(value.counters.protectedDispatches, 1);
      assert.equal(value.outputAfterFailure, false);
      assert.equal(value.finishedAfterFailure, false);
    }
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


test('original serialized materials and live canonical export survive the same Node/workerd owner boundary', async () => {
  await onBoth([
    {restoreMaterials: true, exportMeasurement: true, rows: [{id: 7}, {id: null}, {id: 7}], nullable: true},
    {restoreMaterials: true, exportMeasurement: true, rows: []},
  ], value => {
    assert.equal(value.status, 'completed', JSON.stringify(value));
    assert.equal(value.materialsChecks.originalIdentity, value.materialsChecks.restoredIdentity);
    assert.equal(value.materialsChecks.malformed, 'MoonBitHostFailure');
    assert.equal(value.materialsChecks.wrongIdentity, 'MoonBitHostFailure');
    assert.equal(value.materialsChecks.foreignPreparation, 'InvalidWorkersFiniteInstallation');
    assert.equal(value.materialsChecks.duplicateAdmission, 'WorkersFiniteRunAlreadyOpened');
    assert.deepEqual(value.exportRows, value.rows);
    assert.equal(value.measurement.rowCount, value.rows.length);
    assert.deepEqual(value.measurement.columnRows, [value.rows.length]);
    assert.deepEqual(value.measurement.columnNullRows, [value.rows.filter(row => row.id === null).length]);
    assert.equal(value.exportIdentity.rows, value.measurement.rowCount);
    assert.equal(value.measurementFrozen, true);
    assert.equal(value.measurementBeforeFinish, 'MoonBitHostFailure');
    assert.equal(value.measurementAfterCancel, 'MoonBitHostFailure');
    released(value);
  });
});


test('durable Site JSON roundtrips and custody actions remain owned on Node and workerd', async () => {
  await onBoth([{durableRecords: true}], value => {
    for (const name of ['initialMatch', 'plannedMatch', 'unchangedAfterRefusal',
      'initialIdentityMatches', 'originalWireMatches', 'restoredWireMatches', 'unchangedAfterStaleCommit']) {
      assert.equal(value[name], true, name);
    }
    assert.equal(value.outputRequestMatches, true);
    assert.deepEqual(value.outputProjection, value.outputIntentInput);
    assert.match(value.managedExecutionProfileCid, /^sha256:[0-9a-f]{64}$/);
    assert.equal(value.expectedRevision, 0);
    assert.equal(value.initialRevision, 0);
    assert.equal(value.restoredRevision, 5);
    assert.deepEqual(value.actions, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    for (const name of ['refusedCommit', 'refusedAdmission', 'refusedStaleCommit',
      'refusedConsumedCommit', 'collision', 'releasedCustody', 'malformed', 'unknownField']) {
      assert.equal(value[name], 'MoonBitHostFailure', name);
    }
  });
});
