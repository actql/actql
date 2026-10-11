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
