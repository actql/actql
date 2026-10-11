// Adapter delegation only. Real Identity, original Ledger and seal retirement
// are exercised by the focused Common caller tests, not these explicit ports.
import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeInferOperation} from './infer-operation.mjs';

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
  const calls = [], active = {}, read = {}, compiled = {}, runDefinition = {}, graph = {};
  let stopped = false;
  const moon = {
    clientProgramInferOriginalPreparationAvailable(...args) {
      calls.push(['probe', ...args]); return available;
    },
    clientProgramStartOriginalInferExecution(...args) {
      calls.push(['start', ...args]);
      return startIssue === undefined ? {$tag: 1, _0: active} : {$tag: 0, _0: startIssue};
    },
    clientProgramCancelInferExecution: () => { stopped = true; },
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCleanupInferExecution: () => ({$tag: 1, _0: true}),
  };
  const originalPreparation = {read, compiled, runDefinition, readRetainedBytes: 7n,
    readExecutionBytes: 5n, modelRetainedBytes: 100n, modelExecutionBytes: 5n};
  const options = {moon, preparedProgram: {}, step: 2, graph, registry: 'registry',
    values: 'values', fragment: 'fragment', ordered: 'ordered', provider: {}, originalPreparation};
  return {options, originalPreparation, calls, graph};
}

test('funded start probes original envelope before Core allocation and keeps distinct Model grant', async () => {
  const f = fundedFixture();
  const operation = openNodeInferOperation(f.options);
  assert.deepEqual(f.calls[0], ['probe', f.originalPreparation.read,
    f.originalPreparation.compiled, f.originalPreparation.runDefinition, f.graph, 7n, 5n]);
  assert.deepEqual(f.calls[1], ['start', f.options.preparedProgram, 2, f.graph,
    'registry', 'values', f.options.provider, f.originalPreparation.compiled,
    f.originalPreparation.runDefinition, f.originalPreparation.read, 7n, 5n, 100n, 5n,
    'fragment', 'ordered']);
  assert.equal('ledger' in operation, false);
  assert.equal('startup' in operation, false);
  await operation.close();
});

test('funded start refuses original envelope without opening or replacing an execution', () => {
  const f = fundedFixture(false);
  assert.throws(() => openNodeInferOperation(f.options), /InferOriginalPreparationUnavailable/u);
  assert.equal(f.calls.length, 1);
});

test('funded start preserves Core recheck refusal and never falls back to unowned start', () => {
  const cause = {kind: 'OriginalCapacity', detail: 'ChangedOriginalState'};
  const f = fundedFixture(true, cause);
  assert.throws(() => openNodeInferOperation(f.options), error =>
    error.code === 'MoonBitHostFailure' && error.cause === cause);
  assert.equal(f.calls.length, 2);
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
