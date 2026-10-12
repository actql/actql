// Adapter delegation only. Real Identity, original Ledger and seal retirement
// are exercised by the focused Common caller tests, not these explicit ports.
import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeInferOperation} from './infer-operation.mjs';
import {createInferIoNotification, claimInferIoNotification} from './infer-io-notification.mjs';
import {checked} from '../host-common/runtime-result.mjs';

function fixture() {
  const active = {}, read = {}, compiled = {}, runDefinition = {};
  const calls = [];
  let stopped = false, refusal;
  const moon = {
    clientProgramStartScopedInferExecution: () => ({$tag: 1, _0: active}),
    clientProgramBindInferOriginalPreparation(owner, original, retained, execution) {
      calls.push(['preparation', owner, original, retained, execution]);
      return refusal === undefined ? {$tag: 1, _0: undefined} : {$tag: 0, _0: refusal};
    },
    clientProgramCancelInferExecution: owner => { assert.equal(owner, active); stopped = true; },
    clientProgramAdvanceInferExecution: owner => {
      assert.equal(owner, active); calls.push(['advance']);
      return {$tag: 1, _0: 'stopped'};
    },
    clientProgramInferExecutionPollKind: value => value,
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: owner => {
      assert.equal(owner, active); calls.push(['cleanup']);
      return {$tag: 1, _0: true};
    },
  };
  const operation = openNodeInferOperation({moon, provider: {},
    preparedProgram: {}, step: 0, graph: {}, registry: '', values: '',
    fragment: '', ordered: ''});
  const control = {bindCheckedClientInferRun(actualCompiled, owner, definition) {
    assert.equal(actualCompiled, compiled); assert.equal(owner, active);
    assert.equal(definition, runDefinition); calls.push(['bindRun']);
  }};
  return {operation, active, read, compiled, runDefinition, control, calls,
    refuse: value => { refusal = value; }};
}

test('original preparation delegates exact opaque read after original Run binding without advancing', async () => {
  const f = fixture();
  f.operation.bindRun(f.control, f);
  f.operation.bindOriginalPreparation(f.read, 100n, 5n);
  assert.deepEqual(f.calls, [['bindRun'], ['preparation', f.active, f.read, 100n, 5n]]);
  assert.equal('ledger' in f.operation, false);
  assert.equal('startup' in f.operation, false);
  await f.operation.close();
});

test('original preparation typed refusal is preserved without a retry or replacement owner', async () => {
  const f = fixture(), cause = {kind: 'OriginalCapacity', detail: 'ForeignRun'};
  f.operation.bindRun(f.control, f);
  f.refuse(cause);
  assert.throws(() => f.operation.bindOriginalPreparation(f.read, 100n, 5n), error =>
    error.code === 'MoonBitHostFailure' && error.cause === cause);
  assert.deepEqual(f.calls, [['bindRun'], ['preparation', f.active, f.read, 100n, 5n]]);
  await f.operation.close();
  assert.equal(f.calls.filter(call => call[0] === 'preparation').length, 1);
  assert.equal(f.calls.filter(call => call[0] === 'cleanup').length, 1);
});

function fundedFixture(available = true, startIssue) {
  const calls = [], active = {}, read = {}, consumer = {}, compiled = {}, runDefinition = {}, graph = {}, scope = {};
  let stopped = false, claimed = false;
  const moon = {
    clientProgramClaimInferOriginalPreparation(...args) {
      calls.push(['claim', ...args]);
      if (!available || claimed) return {$tag: 0, _0: 'SpentClaim'};
      claimed = true;
      return {$tag: 1, _0: consumer};
    },
    clientProgramStartOriginalInferExecution(...args) {
      calls.push(['start', ...args]);
      return startIssue === undefined ? {$tag: 1, _0: active} : {$tag: 0, _0: startIssue};
    },
    clientProgramCancelInferExecution: () => { stopped = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ({$tag: 1, _0: true}),
  };
  const originalPreparation = {read, scope, compiled, runDefinition, readRetainedBytes: 7n,
    readExecutionBytes: 5n, modelRetainedBytes: 100n, modelExecutionBytes: 5n};
  const options = {moon, preparedProgram: {}, step: 2, graph, registry: 'registry',
    values: 'values', fragment: 'fragment', ordered: 'ordered', provider: {}, originalPreparation};
  return {options, originalPreparation, calls, graph, consumer, active};
}

test('funded start claims original envelope before Core allocation and keeps distinct Model grant', async () => {
  const f = fundedFixture();
  const operation = openNodeInferOperation(f.options);
  assert.deepEqual(f.calls[0], ['claim', f.originalPreparation.read,
    f.originalPreparation.compiled, f.originalPreparation.runDefinition, f.graph, 7n, 5n]);
  assert.deepEqual(f.calls[1], ['start', f.options.preparedProgram, 2, f.graph,
    'registry', 'values', f.options.provider, f.originalPreparation.compiled,
    f.originalPreparation.runDefinition, f.consumer, 7n, 5n, 100n, 5n,
    'fragment', 'ordered']);
  assert.equal('ledger' in operation, false);
  assert.equal('startup' in operation, false);
  await operation.close();
});

test('funded start refuses original envelope without opening or replacing an execution', () => {
  const f = fundedFixture(false);
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 'SpentClaim');
  assert.equal(f.calls.length, 1);
});

test('funded start preserves Core recheck refusal and never falls back to unowned start', () => {
  const cause = {kind: 'OriginalCapacity', detail: 'ChangedOriginalState'};
  const f = fundedFixture(true, cause);
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === cause);
  assert.equal(f.calls.length, 2);
});

test('funded start duplicate claim refuses before a second IO notification is consumed', async () => {
  const f = fundedFixture();
  const firstIo = createInferIoNotification(), secondIo = createInferIoNotification();
  f.options.ioNotification = firstIo;
  const operation = openNodeInferOperation(f.options);
  f.options.ioNotification = secondIo;
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 'SpentClaim');
  assert.equal(f.calls.filter(call => call[0] === 'start').length, 1);
  // Actual notifier remains unclaimed: refusal occurred before this allocation
  // site's claim, rather than closing/replacing a second Core operation later.
  claimInferIoNotification(secondIo).close();
  await operation.close();
});

test('funded start does not reinterpret restored or malformed installation as fresh funding', () => {
  for (const mutate of [
    f => { f.options.restoredInput = {}; },
    f => { f.originalPreparation.readRetainedBytes = 0n; },
    f => { f.originalPreparation.readExecutionBytes = -1n; },
    f => { f.originalPreparation.modelRetainedBytes = 1; },
  ]) {
    const f = fundedFixture(); mutate(f);
    assert.throws(() => openNodeInferOperation(f.options), /InvalidInferOriginalPreparation/u);
    assert.equal(f.calls.length, 0);
  }
});

function nodeLayoutFixture(issue) {
  const f = fundedFixture();
  let claimed = false;
  const selected = {layout: {}, installation: {}, runtimeArtifactCid: 'runtime',
    layoutArtifactCid: 'layout', probability: undefined};
  f.originalPreparation.nodeInstallation = selected;
  f.originalPreparation.control = {
    claimCheckedClientInferNodePreparationLayout(...args) {
      f.calls.push(['layoutClaim', ...args]);
      if (issue !== undefined || claimed) return checked({$tag: 0, _0: issue ?? 'SpentClaim'});
      claimed = true;
      return f.consumer;
    },
    startCheckedClientInferOriginalPreparation(compiled, definition, ...args) {
      assert.equal(compiled, f.originalPreparation.compiled);
      assert.equal(definition, f.originalPreparation.runDefinition);
      return checked(f.options.moon.clientProgramStartOriginalInferExecution(
        ...args.slice(0, 6), compiled, definition, ...args.slice(6)));
    },
  };
  return {...f, selected};
}

test('installed layout delegates authenticated original control before IO and reuses its same consumer', async () => {
  const f = nodeLayoutFixture();
  const operation = openNodeInferOperation(f.options);
  assert.deepEqual(f.calls[0], ['layoutClaim', f.originalPreparation.compiled,
    f.originalPreparation.runDefinition, f.graph, f.originalPreparation.read, f.selected]);
  assert.deepEqual(f.calls[1], ['start', f.options.preparedProgram, 2, f.graph,
    'registry', 'values', f.options.provider,
    f.originalPreparation.compiled, f.originalPreparation.runDefinition,
    f.consumer, 7n, 5n, 100n, 5n, 'fragment', 'ordered']);
  assert.equal(f.calls.some(call => call[0] === 'claim'), false);
  await operation.close();
});

test('installed layout refusal and duplicate claim never fall back or consume a second IO notifier', async () => {
  for (const issue of ['Unavailable', 'RuntimeMismatch', 'PreparationMismatch']) {
    const f = nodeLayoutFixture(issue);
    const io = createInferIoNotification();
    f.options.ioNotification = io;
    assert.throws(() => openNodeInferOperation(f.options), error =>
      error.code === 'MoonBitHostFailure' && error.cause === issue);
    assert.equal(f.calls.length, 1);
    claimInferIoNotification(io).close();
  }
  const f = nodeLayoutFixture();
  const operation = openNodeInferOperation(f.options);
  const io = createInferIoNotification();
  f.options.ioNotification = io;
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === 'SpentClaim');
  assert.equal(f.calls.filter(call => call[0] === 'start').length, 1);
  claimInferIoNotification(io).close();
  await operation.close();
});

test('installed layout requires explicit selected facts and original control without a legacy fallback', () => {
  for (const mutate of [
    f => { f.originalPreparation.nodeInstallation = undefined; },
    f => { delete f.originalPreparation.nodeInstallation.installation; },
    f => { f.originalPreparation.nodeInstallation.extra = true; },
    f => { delete f.originalPreparation.control; },
  ]) {
    const f = nodeLayoutFixture(); mutate(f);
    assert.throws(() => openNodeInferOperation(f.options), /InvalidInferOriginalPreparationLayout/u);
    assert.equal(f.calls.length, 0);
  }
});

test('original Model park adapter delegates the same active and scope without advancing', async () => {
  const f = fundedFixture();
  const park = Object.freeze({});
  f.options.moon.clientProgramParkInferOriginalModelResources = (active, scope) => {
    f.calls.push(['park', active, scope]);
    return {$tag: 1, _0: park};
  };
  f.options.moon.clientProgramInferOriginalModelResourceParkCurrent = (active, scope, original) => {
    f.calls.push(['current', active, scope, original]);
    return original === park ? park : undefined;
  };
  const operation = openNodeInferOperation(f.options);
  assert.strictEqual(operation.parkOriginalResources(), park);
  assert.deepEqual(f.calls.at(-1), ['park', f.active, f.originalPreparation.scope]);
  const originalScope = f.originalPreparation.scope;
  f.originalPreparation.scope = {};
  assert.strictEqual(operation.originalResourceParkCurrent(park), park);
  assert.deepEqual(f.calls.at(-1), ['current', f.active, originalScope, park]);
  assert.equal(operation.originalResourceParkCurrent({...park}), undefined);
  assert.equal(f.calls.some(call => call[0] === 'advance'), false);
  await operation.close();
  assert.equal(operation.originalResourceParkCurrent(park), undefined);
  assert.throws(() => operation.parkOriginalResources(), /InferOriginalModelParkUnavailable/u);
});

test('original Model park has no unowned or missing-port fallback and preserves typed refusal', async () => {
  const unowned = fixture();
  assert.throws(() => unowned.operation.parkOriginalResources(), /InferOriginalModelParkUnavailable/u);
  await unowned.operation.close();
  const missing = fundedFixture();
  const noPort = openNodeInferOperation(missing.options);
  assert.throws(() => noPort.parkOriginalResources(), /InferOriginalModelParkUnavailable/u);
  await noPort.close();
  const f = fundedFixture();
  const issue = {kind: 'InvalidAdvance'};
  f.options.moon.clientProgramParkInferOriginalModelResources = () => ({$tag: 0, _0: issue});
  const operation = openNodeInferOperation(f.options);
  assert.throws(() => operation.parkOriginalResources(), error =>
    error.code === 'MoonBitHostFailure' && error.cause === issue);
  await operation.close();
});
