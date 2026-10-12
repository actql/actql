// Fault-injected physical ports verify the actual installed caller's custody
// order. Core binding, one-shot claims and ledger census have separate actual
// Common/compiled Node tests; these fixture sizes are not a numerical profile.
import assert from 'node:assert/strict';
import test from 'node:test';
const {installNodeInferRun} = await import(process.env.ACTQL_ORIGINAL_CLEANUP_MODULE ??
  './installed-infer-run.mjs');

function fixture({startIssue, stopComplete = true, modelCleanupComplete = true} = {}) {
  const calls = [], active = {}, read = {}, scope = {}, compiled = {}, consumer = {};
  const preparedProgram = {}, graph = {};
  const runDefinition = {wire: '{"run_id":"original-cleanup"}'};
  const issue = {kind: 'OriginalFixtureBindingRefused'};
  let custody, physicalComplete = false, physicalPending = true, physicalFailure;
  let allowScope = true, stoppedRead = false, settledRead = false;
  let stop = stopComplete, modelCleanup = modelCleanupComplete;
  const moon = {
    clientProgramInferPlanBoundary: () => ({_0: 0}),
    clientProgramStartOriginalInferExecution() {
      calls.push('originalStart');
      return startIssue === undefined ? {$tag: 1, _0: active} : {$tag: 0, _0: startIssue};
    },
    clientProgramStartScopedInferExecution() {
      calls.push('unownedStart'); return {$tag: 1, _0: active};
    },
    clientProgramRequireInferCallEntry: () => ({$tag: 1, _0: undefined}),
    clientProgramBindInferQuantityCapacity: () => ({$tag: 0, _0: issue}),
    clientProgramCancelInferExecution() { calls.push('modelStopRequest'); },
    clientProgramInferExecutionStopped: () => stop,
    clientProgramAdvanceInferExecution: () => ({$tag: 1, _0: stop ? 'stopped' : 'waiting'}),
    clientProgramInferExecutionPollKind: value => value,
    clientProgramCleanupInferExecution() {
      calls.push('modelCleanup'); return {$tag: 1, _0: modelCleanup};
    },
  };
  const exact = (actualCompiled, definition, actualGraph) => {
    assert.equal(actualCompiled, compiled); assert.equal(definition, runDefinition);
    assert.equal(actualGraph, graph);
  };
  const control = {
    claimCheckedClientInferNodePreparationLayout(...args) {
      exact(...args); assert.equal(args[3], read); calls.push('claim'); return consumer;
    },
    startCheckedClientInferOriginalPreparation(...args) {
      assert.equal(args[0], compiled); assert.equal(args[1], runDefinition);
      assert.equal(args[8], consumer);
      return assertChecked(moon.clientProgramStartOriginalInferExecution());
    },
    stopCheckedClientInferOriginalReadPreparation(...args) {
      exact(...args); assert.equal(args[3], scope); assert.equal(args[4], read);
      calls.push('readStop'); stoppedRead = true;
    },
    settleCheckedClientInferOriginalReadPreparation(...args) {
      exact(...args); assert.equal(args[3], read); assert.equal(args[4], true);
      assert.equal(stoppedRead, true); assert.equal(physicalComplete, true);
      assert.equal(physicalPending, false); calls.push('readSettle'); settledRead = true;
    },
    finishCheckedClientInferOriginalReadScope(...args) {
      exact(...args); assert.equal(args[3], scope); assert.equal(args[4], true);
      assert.equal(settledRead, true); calls.push('scopeFinish'); return allowScope;
    },
  };
  function assertChecked(value) {
    if (value.$tag === 0) throw Object.assign(new Error('MoonBitHostFailure'),
      {code: 'MoonBitHostFailure', cause: value._0});
    return value._0;
  }
  const physicalCustody = {
    async close() {
      calls.push('physicalClose'); assert.equal(stoppedRead, true);
      if (physicalFailure !== undefined) throw physicalFailure;
      physicalPending = !physicalComplete; return physicalComplete;
    },
    async cleanup() {
      calls.push('physicalRetry'); assert.equal(stoppedRead, true);
      if (physicalFailure !== undefined) throw physicalFailure;
      physicalPending = !physicalComplete; return physicalComplete;
    },
    cleanupPending: () => physicalPending,
  };
  const originalPreparation = {compiled, runDefinition, control, read, scope, physicalCustody,
    readRetainedBytes: 7n, readExecutionBytes: 5n,
    modelRetainedBytes: 100n, modelExecutionBytes: 5n,
    nodeInstallation: {layout: {}, installation: {}, runtimeArtifactCid: 'runtime',
      layoutArtifactCid: 'layout', probability: undefined}};
  const plan = {compiled, runDefinition, inferGraph: graph};
  const selected = {graph, step: 0, provider() { assert.fail('no physical send'); },
    quantityCapacity: {limits: {tokens: 1n, costUnits: 0n, durationMs: 1n},
      perAttempt: {tokens: 1n, costUnits: 0n, durationMs: 1n}}};
  let discovered = [];
  const modelController = {discover: () => discovered,
    prime() { assert.fail('fresh original preparation cannot prime restored input'); },
    release(token) { assert.equal(token, undefined); },
    open() { assert.fail('a binding refusal cannot authorize a Model call'); }};
  const runInfer = installNodeInferRun({moon, core: {publicationControl: control},
    selections: new Map([[preparedProgram, selected]]), modelController});
  const input = {preparedProgram, plan, originalPreparation,
    signal: new AbortController().signal,
    retainExecution(value) { assert.equal(custody, undefined); custody = value; },
    beginPhysicalWork() { assert.fail('refused execution cannot begin physical work'); }};
  return {run: () => runInfer(input), input, issue, calls, originalPreparation,
    custody: () => custody,
    physical(complete, pending = !complete) { physicalComplete = complete; physicalPending = pending; },
    failPhysical(error) { physicalFailure = error; },
    scopeAllowed(value) { allowScope = value; },
    modelStopped(value) { stop = value; },
    modelClean(value) { modelCleanup = value; },
    existing(value) { discovered = value; }};
}

const typed = cause => error => error.code === 'MoonBitHostFailure' && error.cause === cause;

test('installed original cleanup retains the same physical read before read and whole Run retirement', async () => {
  const f = fixture();
  await assert.rejects(f.run(), typed(f.issue));
  assert.equal(f.calls.includes('unownedStart'), false);
  assert.equal(f.calls.filter(call => call === 'originalStart').length, 1);
  const custody = f.custody();
  assert.equal(await custody.close(), false);
  assert.equal(custody.cleanupPending(), true);
  assert.deepEqual(f.calls.slice(-3), ['modelCleanup', 'readStop', 'physicalClose']);
  assert.equal(f.calls.includes('readSettle'), false);
  f.physical(true); f.scopeAllowed(false);
  assert.equal(await custody.cleanup(), false);
  assert.deepEqual(f.calls.slice(-3), ['physicalRetry', 'readSettle', 'scopeFinish']);
  assert.equal(custody.cleanupPending(), true, 'read retirement is not whole-Run cleanup');
  f.scopeAllowed(true);
  assert.equal(await custody.cleanup(), true);
  assert.equal(custody.cleanupPending(), false);
  await custody.close(); await custody.cleanup();
  assert.equal(f.calls.filter(call => call === 'claim').length, 1);
  assert.equal(f.calls.filter(call => call === 'originalStart').length, 1);
  assert.equal(f.calls.filter(call => call === 'physicalClose').length, 1);
  assert.equal(f.calls.filter(call => call === 'physicalRetry').length, 1);
  assert.equal(f.calls.filter(call => call === 'readStop').length, 1);
  assert.equal(f.calls.filter(call => call === 'readSettle').length, 1);
  assert.equal(f.calls.filter(call => call === 'scopeFinish').length, 2);
});

test('installed original cleanup preserves a thrown close and retries only the same physical custody', async () => {
  const f = fixture(), failure = new Error('OriginalPhysicalCloseUnknown');
  await assert.rejects(f.run(), typed(f.issue));
  f.failPhysical(failure);
  await assert.rejects(f.custody().close(), error => error === failure);
  assert.equal(f.custody().cleanupPending(), true);
  assert.equal(f.calls.includes('readSettle'), false);
  f.failPhysical(undefined); f.physical(true);
  assert.equal(await f.custody().cleanup(), true);
  assert.deepEqual(f.calls.slice(-3), ['physicalRetry', 'readSettle', 'scopeFinish']);
  assert.equal(f.calls.filter(call => call === 'claim').length, 1);
  assert.equal(f.calls.filter(call => call === 'originalStart').length, 1);
});

test('installed original cleanup stops the never-constructed consumer without replaying start', async () => {
  const issue = {kind: 'OriginalCapacity', detail: 'NoModelAllocation'};
  const f = fixture({startIssue: issue});
  await assert.rejects(f.run(), typed(issue));
  f.physical(true);
  assert.equal(await f.custody().close(), true);
  assert.deepEqual(f.calls, ['claim', 'originalStart', 'readStop', 'physicalClose',
    'readSettle', 'scopeFinish']);
});

test('installed original cleanup does not turn cancellation or Model stop alone into physical release', async () => {
  const f = fixture({stopComplete: false, modelCleanupComplete: false});
  await assert.rejects(f.run(), typed(f.issue));
  await assert.rejects(f.custody().close(), /ClientDispatchCleanupPending/u);
  assert.equal(f.calls.includes('readStop'), false);
  f.modelStopped(true);
  assert.equal(await f.custody().cleanup(), false);
  assert.equal(f.calls.includes('readStop'), false, 'Model physical stop is not Model cleanup');
  f.modelClean(true);
  assert.equal(await f.custody().cleanup(), false);
  assert.equal(f.calls.includes('readStop'), true);
  assert.equal(f.calls.includes('readSettle'), false);
  f.physical(true);
  assert.equal(await f.custody().cleanup(), true);
});

test('installed original preparation rejects foreign, incomplete and restored custody before claim', async () => {
  for (const mutate of [
    f => { f.originalPreparation.control = {}; },
    f => { f.originalPreparation.compiled = {}; },
    f => { f.originalPreparation.runDefinition = {}; },
    f => { delete f.originalPreparation.scope; },
    f => { delete f.originalPreparation.read; },
    f => { delete f.originalPreparation.nodeInstallation; },
    f => { f.originalPreparation.physicalCustody.cleanupPending = undefined; },
    f => { f.input.acquiredInfer = {}; },
    f => { f.input.replay = true; },
  ]) {
    const f = fixture(); mutate(f);
    await assert.rejects(f.run(), /InvalidInstalledInferOriginalPreparation/u);
    assert.deepEqual(f.calls, []);
    assert.equal(f.custody(), undefined);
  }
  const f = fixture(); f.existing([{inventory: {taskIndex: 0}}]);
  await assert.rejects(f.run(), /RestoredInferOriginalPreparationUnavailable/u);
  assert.deepEqual(f.calls, []);
});

test('installed original cleanup requires physical cleanupPending false, not a fulfilled close alone', async () => {
  const f = fixture();
  await assert.rejects(f.run(), typed(f.issue));
  // A physical owner may finish its Promise but still retain cleanup custody.
  const child = f.originalPreparation.physicalCustody;
  child.close = async () => { f.calls.push('physicalClose'); return true; };
  assert.equal(await f.custody().close(), false);
  assert.equal(f.calls.includes('readSettle'), false);
  f.physical(true);
  assert.equal(await f.custody().cleanup(), true);
});

test('installed original cleanup coalesces concurrent close and retry through the same custody', async () => {
  const f = fixture();
  await assert.rejects(f.run(), typed(f.issue));
  let reached, complete;
  const entered = new Promise(resolve => { reached = resolve; });
  const child = f.originalPreparation.physicalCustody;
  child.close = () => {
    f.calls.push('physicalClose'); reached();
    return new Promise(resolve => { complete = resolve; });
  };
  const first = f.custody().close();
  await entered;
  assert.equal(f.custody().cleanup(), first);
  assert.equal(f.custody().close(), first);
  assert.equal(f.calls.includes('readSettle'), false);
  assert.equal(f.calls.includes('physicalRetry'), false);
  f.physical(true); complete(true);
  assert.equal(await first, true);
  assert.equal(f.custody().cleanup(), first);
  assert.equal(f.calls.filter(call => call === 'readSettle').length, 1);
  assert.equal(f.calls.filter(call => call === 'scopeFinish').length, 1);
});
