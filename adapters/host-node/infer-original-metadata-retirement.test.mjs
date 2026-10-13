import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as turn} from 'node:timers/promises';
import {openNodeInferOperation} from './infer-operation.mjs';

// The operation/cleanup adapter is real. Checked Run, Ledger and Core ACK are
// explicit doubles; these observations prove reference retirement, not a
// numerical profile, public funding, heap/RSS bound or immediate collection.
function fixture() {
  const state = {stopped: false, allowed: false, failure: undefined, cleanups: 0};
  const active = {}, consumer = {}, scope = {};
  const metadataInstallation = Object.freeze({marker: 'Original e\u0301\r\n'});
  const nodeInstallation = Object.freeze({layout: {}, installation: {},
    runtimeArtifactCid: 'runtime', layoutArtifactCid: 'layout', probability: undefined});
  const definition = Object.freeze({identity: 'original-definition', wire: 'Original e\u0301\r\n'});
  const control = {
    claimCheckedClientInferNodePreparationLayout: () => consumer,
    startCheckedClientInferOriginalPreparation: () => active,
    runDefinitionRunId: () => 'original-run',
  };
  const refs = {metadataInstallation: new WeakRef(metadataInstallation),
    nodeInstallation: new WeakRef(nodeInstallation), definition: new WeakRef(definition),
    control: new WeakRef(control)};
  const operation = openNodeInferOperation({provider: {},
    originalPreparation: {read: {}, scope, compiled: {}, runDefinition: definition,
      control, metadataInstallation, nodeInstallation,
      readRetainedBytes: 7n, readExecutionBytes: 5n,
      modelRetainedBytes: 100n, modelExecutionBytes: 5n},
    moon: {
      clientProgramCancelInferExecution() {},
      clientProgramInferExecutionStopped: () => state.stopped,
      clientProgramCleanupInferExecution() {
        state.cleanups++;
        if (state.failure !== undefined) return {$tag: 0, _0: state.failure};
        return {$tag: 1, _0: state.allowed};
      },
    }});
  return {operation, state, refs};
}

async function collected(refs) {
  assert.equal(typeof global.gc, 'function', 'Run with the existing --expose-gc diagnostic');
  for (let step = 0; step < 24; step++) {
    await turn();
    global.gc();
    await turn();
    if (refs.every(ref => ref.deref() === undefined)) return true;
  }
  return false;
}

test('original metadata selection remains borrowed through stop and failed cleanup, then retires',
  {timeout: 5000}, async () => {
    const f = fixture();
    const refs = Object.values(f.refs);
    assert.equal(f.operation.cleanup(), false);
    assert.equal(f.state.cleanups, 0, 'stop request is not a Core retirement ACK');
    f.state.stopped = true;
    assert.equal(f.operation.cleanup(), false);
    assert.equal(await collected(refs), false);
    assert.ok(refs.every(ref => ref.deref() !== undefined));
    f.state.failure = Object.freeze({kind: 'OriginalCleanupPending'});
    assert.throws(() => f.operation.cleanup(), error =>
      error.code === 'MoonBitHostFailure' && error.cause === f.state.failure);
    assert.ok(refs.every(ref => ref.deref() !== undefined));
    f.state.failure = undefined;
    f.state.allowed = true;
    assert.equal(f.operation.cleanup(), true);
    assert.equal(f.operation.originalResourceScope(), undefined);
    assert.throws(() => f.operation.originalMetadataAcquisition({}),
      {code: 'InferOriginalMetadataAcquisitionUnavailable'});
    assert.equal(await collected(refs), true,
      'An escaped retired operation must not retain installation/control/Run metadata');
    const cleanups = f.state.cleanups;
    assert.equal(f.operation.cleanup(), true);
    assert.equal(f.state.cleanups, cleanups);
  });

test('metadata alias retirement does not mutate a separately escaped installation borrow',
  {timeout: 5000}, async () => {
    const f = fixture();
    const escaped = f.refs.metadataInstallation.deref();
    f.state.stopped = true;
    f.state.allowed = true;
    assert.equal(f.operation.cleanup(), true);
    assert.equal(await collected([f.refs.nodeInstallation, f.refs.definition, f.refs.control]), true);
    assert.equal(f.refs.metadataInstallation.deref(), escaped);
    assert.equal(escaped.marker, 'Original e\u0301\r\n');
    assert.ok(Object.isFrozen(escaped));
  });
