import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientDispatchOwner,
  observeNodeRestoredModelStop, confirmNodeRunCancellation} from './client-dispatch-owner.mjs';
const commonDecision = runtimeCore(moon).publicationControl.runCancellationConfirmed;

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
  let confirmStop;
  const stop = new Promise(resolve => { confirmStop = resolve; });
  const owner = installNodeClientDispatchOwner({moon: {},
    control: {runDefinitionRunId: () => 'run', runCancellationConfirmed: commonDecision},
    journal: {reservePhysicalStart: () => true,
      lookupRunDefinition: () => ({cancellationRequested: facts.accepted,
        revision: facts.revision ?? 1, runDefinition: {wire: 'definition'},
        physicalCloseConfirmed: facts.physicalCloseConfirmed ?? false,
        observedTerminalOutcome: facts.observedTerminalOutcome ?? null}),
      lookupReconciliationState: () => facts.effectUnknown ? 'unknown Effect' : undefined,
      markPhysicalClose: (_ref, outcome) => {
        assert.equal(facts.physicalCloseConfirmed ?? false, false,
          'a racing observer already sealed the physical stop');
        observed.push(outcome);
      }},
    checkpoints: {heldOrigin: () => false, acquisitionAccess: () => undefined,
      releaseAcquisition() {},
      journal: {discoverModelCallSets: () => [{}],
        modelCancellationFenced: () => facts.fenced,
        hasUnresolvedModelCalls: () => facts.modelUnknown}},
    store: {confirmCommittedIndex: async () => {
      facts.inspectPublication?.(facts);
      return facts.published ? {} : undefined;
    }},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    planFor: () => ({kind: 'infer', runDefinition: {wire: 'definition'}}),
    runInfer: async ({retainExecution, signal}) => {
      retainExecution({async close() {
        if (facts.stopPending) await stop;
      }, cleanup: () => facts.cleanup,
        cleanupPending: () => !facts.cleanup});
      entered();
      await new Promise((_, reject) => signal.addEventListener('abort',
        () => reject(signal.reason), {once: true}));
    },
  });
  return {facts, owner, ref, ready, observed, confirmStop,
    start: () => owner.start({preparedProgram: {}, principalId: 'owner',
      requestId: 'request', connection: {}}, {}, {ref,
      runDefinition: {wire: 'definition'}, dispatchReserved: false,
      cancellationRequested: false}, {})};
}

for (const outcome of [null, 'cancelled']) {
  test(`normal Model stop preserves a racing ${outcome} physical observation`, async () => {
    const f = fixture({inspectPublication(facts) {
      facts.revision = 2;
      facts.physicalCloseConfirmed = true;
      facts.observedTerminalOutcome = outcome;
    }});
    await f.start(); await f.ready;
    f.owner.cancel(f.ref);
    await f.owner.drain();
    assert.deepEqual(f.observed, []);
  });
}

for (const changed of ['fence', 'lifecycle']) {
  test(`cancellation rereads Model ${changed} after publication inspection`, async () => {
    let fenced = true, status = 'running';
    const accepted = {cancellationRequested: true, revision: 1,
      runDefinition: {wire: 'original'}};
    assert.equal(await confirmNodeRunCancellation({
      ref: {runDefinitionCid: 'definition'},
      journal: {lookupRunDefinition: () => accepted,
        lookupReconciliationState: () => undefined},
      control: {runDefinitionRunId: () => 'run', runCancellationConfirmed: commonDecision},
      cleanupConfirmed: true, physicalStopConfirmed: true,
      checkpoints: {journal: {discoverModelCallSets: () => [{}],
        modelCancellationFenced: () => fenced,
        hasUnresolvedModelCalls: () => false, getRunState: () => ({status})}},
      store: {async confirmCommittedIndex() {
        if (changed === 'fence') fenced = false;
        else status = 'needs_reconciliation';
        return undefined;
      }},
    }), false);
  });
}

test('a changed cancellation revision retains the same stop owner for retry', async () => {
  let raced = false;
  const f = fixture({inspectPublication(facts) {
    if (raced) return;
    raced = true;
    facts.revision = 2;
  }});
  await f.start(); await f.ready;
  f.owner.cancel(f.ref);
  await f.owner.operation(f.ref);
  assert.deepEqual(f.observed, []);
  assert.notEqual(f.owner.operation(f.ref), undefined);
  await f.owner.drain();
  assert.deepEqual(f.observed, ['cancelled']);
  await f.owner.drain();
  assert.deepEqual(f.observed, ['cancelled']);
});

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

test('cancellation cannot terminate before physical stop acknowledgement', async () => {
  const f = fixture({stopPending: true});
  await f.start(); await f.ready;
  f.owner.cancel(f.ref);
  const draining = f.owner.drain();
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.observed, []);
  f.confirmStop();
  await draining;
  assert.deepEqual(f.observed, ['cancelled']);
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

for (const outcome of [null, 'cancelled']) {
  test(`restored Model stop preserves an immutable ${outcome} observation across an asynchronous inspection`, async () => {
    let retained = {cancellationRequested: true, revision: 1,
      runDefinition: {wire: 'original'}, physicalCloseConfirmed: false};
    const writes = [];
    const journal = {
      lookupRunDefinition: () => retained,
      lookupReconciliationState: () => undefined,
      markPhysicalClose(_ref, next) {
        writes.push(next);
        assert.equal(next, outcome, 'an earlier physical-stop observation is immutable');
      },
    };
    await observeNodeRestoredModelStop({ref: {runDefinitionCid: 'definition'},
      journal, control: {runDefinitionRunId: () => 'run', runCancellationConfirmed: commonDecision},
      checkpoints: {journal: {discoverModelCallSets: () => [{}],
        modelCancellationFenced: () => true, hasUnresolvedModelCalls: () => false}},
      cleanupConfirmed: true, physicalStopConfirmed: true,
      store: {async confirmCommittedIndex() {
        // Another confirmed observer commits during the asynchronous Store read.
        retained = {...retained, revision: 2, physicalCloseConfirmed: true,
          observedTerminalOutcome: outcome};
        return undefined;
      }},
    });
    assert.deepEqual(writes, [], 'restored cleanup must not rewrite a confirmed observation');
    assert.equal(retained.observedTerminalOutcome, outcome);
  });
}
