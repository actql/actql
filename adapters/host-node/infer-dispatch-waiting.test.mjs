import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

// Physical supervisor boundary only. Common Checkpoint/Store admissions are
// explicit doubles; this does not establish public Model approval acceptance.
function fixture({checkpoint, failClose = false, changeObservation = false} = {}) {
  const ref = {runDefinitionCid: 'infer-definition'};
  const runDefinition = {wire: 'definition'};
  const stopped = [];
  const events = [];
  let waiting = checkpoint;
  let closes = 0;
  let recover = !failClose;
  let frame = Object.freeze({runDefinition, revision: 1,
    cancellationRequested: false, physicalCloseConfirmed: false});
  let stopInspections = 0, changedAtStore = false;
  const owner = installNodeClientDispatchOwner({
    moon: {}, control: {runDefinitionRunId: definition => {
        assert.equal(definition, runDefinition);
        return 'infer-run';
      }, runCancellationConfirmed(facts) {
        // This fixture never requests cancellation or creates dispatch records.
        assert.deepEqual(facts, {
          cancellationRequested: false, modelFenceRequired: false,
          modelFenced: false, unresolvedModelCalls: false,
          unresolvedEffects: false, reconciliationRequired: false,
          publicationCommitted: false, physicalStopConfirmed: true,
          cleanupConfirmed: true,
          revisionUnchanged: !changeObservation || stopInspections > 0,
        });
        stopInspections++;
        return false;
      }},
    journal: {
      reservePhysicalStart: () => true,
      lookupRunDefinition(ownerRef) {
        assert.equal(ownerRef, ref);
        return frame;
      },
      lookupReconciliationState(ownerRef) {
        assert.equal(ownerRef, ref);
        return undefined;
      },
      markPhysicalClose(ownerRef, outcome, originalFrame) {
        assert.equal(ownerRef, ref);
        assert.strictEqual(originalFrame, frame);
        assert.equal(frame.physicalCloseConfirmed, false);
        stopped.push(outcome);
        frame = Object.freeze({...frame, physicalCloseConfirmed: true});
      },
      markPreDispatchFailure: () => assert.fail('preparation already started'),
    },
    checkpoints: {journal: {inspect(cid) {
        assert.equal(cid, 'model-checkpoint');
        return waiting;
      }, discoverModelCallSets({runId, limit}) {
        assert.equal(runId, 'infer-run');
        assert.equal(limit, 1);
        return [];
      }, hasUnresolvedModelCalls(runId) {
        assert.equal(runId, 'infer-run');
        return false;
      }}, heldOrigin: () => false,
      acquisitionAccess: () => undefined, releaseAcquisition() {},
      effectRunState(runId, definitionCid) {
        assert.equal(runId, 'infer-run');
        assert.equal(definitionCid, ref.runDefinitionCid);
        return waiting;
      }},
    store: {async confirmCommittedIndex() {
      if (changeObservation && !changedAtStore) {
        changedAtStore = true;
        frame = Object.freeze({...frame, revision: frame.revision + 1});
      }
      return undefined;
    }},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    planFor: () => ({kind: 'infer', runDefinition}),
    namespaceId: 'namespace',
    observed: name => events.push(name),
    runInfer: async ({retainExecution}) => {
      retainExecution({async close() { closes++; }, cleanup: () => recover,
        cleanupPending: () => !recover});
      return {status: 'waiting_checkpoint', checkpoint: {checkpointCid: 'model-checkpoint'}};
    },
  });
  return {owner, ref, stopped, events, closes: () => closes,
    recover: () => { recover = true; },
    state: value => { waiting = value; },
    start: () => owner.start({preparedProgram: {}, principalId: 'owner',
      connection: {}, requestId: 'infer-request'}, {}, {ref,
      runDefinition, dispatchReserved: false,
      cancellationRequested: false}, {})};
}

const held = {kind: 'model_invocation', checkpointCid: 'model-checkpoint',
  runId: 'infer-run', runDefinitionCid: 'infer-definition', prepareAttemptId: null};

test('durable Model wait closes physical preparation without failing or publishing the Run', async () => {
  const f = fixture({checkpoint: held});
  assert.equal(await f.start(), 'started');
  await f.owner.drain();
  assert.deepEqual(f.stopped, [null]);
  assert.equal(f.events.includes('computed'), false);
  assert.equal(f.events.includes('dispatch_failed'), false);
  assert.equal(f.closes(), 1);
  assert.equal(f.owner.live(f.ref), false);
});

for (const [name, checkpoint] of [
  ['no committed Checkpoint', undefined],
  ['foreign Run', {...held, runId: 'foreign'}],
  ['foreign definition', {...held, runDefinitionCid: 'foreign'}],
  ['an acquisition prepare attempt', {...held, prepareAttemptId: 'foreign'}],
  ['Effect approval instead of Model approval', {...held, kind: 'effect_set'}],
]) {
  test(`an in-memory Model wait cannot substitute ${name}`, async () => {
    const f = fixture({checkpoint});
    await f.start();
    await f.owner.drain();
    assert.deepEqual(f.stopped, ['failed']);
    assert.equal(f.events.includes('dispatch_failed'), true);
    assert.equal(f.events.includes('computed'), false);
  });
}

test('Model wait retains physical cleanup responsibility until recovery', async () => {
  const f = fixture({checkpoint: held, failClose: true});
  await f.start();
  await f.owner.operation(f.ref);
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.deepEqual(f.stopped, []);
  f.recover();
  await f.owner.drain();
  assert.deepEqual(f.stopped, [null]);
  assert.equal(f.events.includes('computed'), false);
});

test('a changed Model stop observation retains cleanup until a fresh original inspection', async () => {
  const f = fixture({checkpoint: undefined, changeObservation: true});
  await f.start();
  const originalOperation = f.owner.operation(f.ref);
  await originalOperation;
  assert.deepEqual(f.stopped, [], 'a changed Journal frame cannot acknowledge stop');
  assert.equal(f.owner.live(f.ref), false, 'the operation settled, but cleanup is retained');
  assert.strictEqual(f.owner.operation(f.ref), originalOperation);
  await f.owner.drain();
  assert.deepEqual(f.stopped, ['failed']);
  assert.equal(f.events.includes('computed'), false);
  assert.equal(f.owner.operation(f.ref), undefined, 'only the confirmed stop retires the entry');
});
