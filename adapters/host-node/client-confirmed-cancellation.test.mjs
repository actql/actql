import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

// Terminal Host boundary with explicit journal/Store doubles. Each missing
// fact is independent of the others; an AbortSignal is never cancellation
// authority or evidence that an unknown provider outcome has settled.
function fixture(changes = {}) {
  const facts = {accepted: true, fenced: true, modelUnknown: false,
    effectUnknown: false, published: false, cleanup: true, ...changes};
  const ref = {runDefinitionCid: 'definition'};
  const observed = [];
  let entered;
  const ready = new Promise(resolve => { entered = resolve; });
  const owner = installNodeClientDispatchOwner({moon: {},
    control: {runDefinitionRunId: () => 'run'},
    journal: {reservePhysicalStart: () => true,
      lookupRunDefinition: () => ({cancellationRequested: facts.accepted,
        revision: 1, runDefinition: {wire: 'definition'}}),
      lookupReconciliationState: () => facts.effectUnknown ? 'unknown Effect' : undefined,
      markPhysicalClose: (_ref, outcome) => observed.push(outcome)},
    checkpoints: {heldOrigin: () => false, acquisitionAccess: () => undefined,
      releaseAcquisition() {},
      journal: {discoverModelCallSets: () => [{}],
        modelCancellationFenced: () => facts.fenced,
        hasUnresolvedModelCalls: () => facts.modelUnknown}},
    store: {confirmCommittedIndex: async () => facts.published ? {} : undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    planFor: () => ({kind: 'infer', runDefinition: {wire: 'definition'}}),
    runInfer: async ({retainExecution, signal}) => {
      retainExecution({async close() {}, cleanup: () => facts.cleanup,
        cleanupPending: () => !facts.cleanup});
      entered();
      await new Promise((_, reject) => signal.addEventListener('abort',
        () => reject(signal.reason), {once: true}));
    },
  });
  return {facts, owner, ref, ready, observed,
    start: () => owner.start({preparedProgram: {}, principalId: 'owner',
      requestId: 'request', connection: {}}, {}, {ref,
      runDefinition: {wire: 'definition'}, dispatchReserved: false,
      cancellationRequested: false}, {})};
}

for (const [name, changes] of [
  ['accepted current Run cancellation', {accepted: false}],
  ['durable send fence', {fenced: false}],
  ['settled Model calls', {modelUnknown: true}],
  ['settled Effects', {effectUnknown: true}],
]) {
  test(`physical stop alone cannot confirm cancellation without ${name}`, async () => {
    const f = fixture(changes);
    await f.start(); await f.ready;
    f.owner.cancel(f.ref);
    await f.owner.drain();
    assert.deepEqual(f.observed, [null]);
  });
}

test('a committed publication wins over the cancellation request', async () => {
  const f = fixture({published: true});
  await f.start(); await f.ready;
  f.owner.cancel(f.ref);
  await f.owner.drain();
  assert.deepEqual(f.observed, [null]);
});

test('cleanup pending cannot confirm cancellation; retry closes exactly once', async () => {
  const f = fixture({cleanup: false});
  await f.start(); await f.ready;
  f.owner.cancel(f.ref);
  await f.owner.operation(f.ref);
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.deepEqual(f.observed, []);
  f.facts.cleanup = true;
  await f.owner.drain();
  assert.deepEqual(f.observed, ['cancelled']);
  await f.owner.drain();
  assert.deepEqual(f.observed, ['cancelled']);
});
