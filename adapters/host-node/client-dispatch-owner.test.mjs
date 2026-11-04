import {ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';
import {publicationOriginalFixture} from './fixtures/local-publication-original.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createNodeHostEntry} from './entry.mjs';
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {openFundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import {sourceFreeValuesPlan} from './local-values-plan.mjs';
import {inspect} from 'node:util';
import * as cancellationMoon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore, ledgerUsageSnapshotHasPendingResources} from '../host-common/runtime-core.mjs';
import {createInProcessExecutionSite, executionSiteDescription,
  installExecutionSites, prepareExecutionSitePolicy} from '../host-common/execution-sites.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
// Reuse the existing distribution-client gate for bounded two-source owners.
import './two-source-capture-boundaries.test.mjs';
import './two-source-public-host.test.mjs';
import './client-dispatch-observation.test.mjs';
import './embedded-local-operation-observation.test.mjs';

const stopControl = {runDefinitionRunId: () => 'fixture-run',
  runCancellationConfirmed: runtimeCore(cancellationMoon).publicationControl.runCancellationConfirmed};
const stopFacts = (cancellationRequested = false, stopped,
  runDefinition = {wire: 'definition'}) => {
  const requested = () => typeof cancellationRequested === 'function'
    ? cancellationRequested() : cancellationRequested;
  let frame = Object.freeze({cancellationRequested: requested(), revision: 1,
    runDefinition, physicalCloseConfirmed: false});
  const lookupRunDefinition = () => {
    if (frame.cancellationRequested !== requested()) {
      frame = Object.freeze({...frame, cancellationRequested: requested(),
        revision: frame.revision + 1});
    }
    return frame;
  };
  return {lookupRunDefinition, lookupReconciliationState: () => undefined,
    markPhysicalClose(ref, outcome, original) {
      assert.equal(original, lookupRunDefinition(), 'Stop consumes the same current Journal frame');
      assert.equal(frame.physicalCloseConfirmed, false);
      frame = Object.freeze({...frame, revision: frame.revision + 1,
        physicalCloseConfirmed: true});
      stopped?.push([ref, outcome]);
    }};
};

function inferDispatchFixture(runInfer, kind = 'infer') {
  const ref = {runDefinitionCid: 'infer-dispatch-owner'};
  const preparedProgram = {};
  const plan = {kind, runDefinition: {wire: 'definition'}};
  const stopped = [];
  let claims = 0, committed = false, cancellationRequested = false;
  const owner = installNodeClientDispatchOwner({
    moon: {clientProgramOpenSourceFreeLocalHost() {
      assert.fail('A model barrier must not open the Values fallback');
    }}, control: {runDefinitionRunId: () => 'infer-run',
      runCancellationConfirmed: runtimeCore(cancellationMoon).publicationControl.runCancellationConfirmed},
    journal: {reservePhysicalStart() { claims++; return true; },
      ...stopFacts(() => cancellationRequested, stopped, plan.runDefinition),
      markPreDispatchFailure: () => stopped.push([ref, 'not_started'])},
    store: {confirmCommittedIndex: async () => committed ? {} : undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true, planFor: () => plan,
    runPublished() { assert.fail('INFER must not use Relation dispatch'); },
    ...(kind === 'serialization' ? {runContent: runInfer} : {runInfer}),
    namespaceId: 'namespace-a',
  });
  const submission = {preparedProgram, principalId: 'owner', connection: {},
    requestId: 'infer-request'};
  const accepted = {ref, runDefinition: plan.runDefinition,
    dispatchReserved: false, cancellationRequested: false};
  const owned = {...owner, cancel(ref) {
    cancellationRequested = true;
    owner.cancel(ref);
  }};
  return {owner: owned, ref, preparedProgram, plan, stopped,
    claims: () => claims, commit: () => { committed = true; },
    start: () => owner.start(submission, {}, accepted, {})};
}

test('Content dispatch consumes the original checked plan and closes through the existing Run owner',
  async () => {
    let calls = 0, closes = 0;
    const physical = {async close() { closes++; }, cleanup: () => true,
      cleanupPending: () => false};
    const fixture = inferDispatchFixture(async context => {
      calls++;
      assert.equal(context.preparedProgram, fixture.preparedProgram);
      assert.equal(context.plan, fixture.plan);
      context.retainExecution(physical);
      fixture.commit();
    }, 'serialization');
    assert.equal(await fixture.start(), 'started');
    await fixture.owner.drain();
    assert.equal(calls, 1);
    assert.equal(closes, 1);
    assert.equal(fixture.claims(), 1);
    assert.deepEqual(fixture.stopped, [[fixture.ref, null]]);
  });

test('Content dispatch keeps a failed cleanup owner and never redispatches its producer',
  async () => {
    let calls = 0, released = false;
    const failure = new Error('ContentStoreFailed');
    const fixture = inferDispatchFixture(async ({retainExecution}) => {
      calls++;
      retainExecution({async close() { throw new Error('ContentCleanupPending'); },
        cleanup: () => released, cleanupPending: () => !released});
      throw failure;
    }, 'serialization');
    assert.equal(await fixture.start(), 'started');
    await fixture.owner.operation(fixture.ref);
    await assert.rejects(fixture.owner.drain(), error => {
      assert.equal(error.code, 'ClientDispatchCleanupPending');
      assert.deepEqual(error.failures[0].primary,
        {name: 'Error', code: undefined, message: 'ContentStoreFailed'});
      assert.notEqual(error.failures[0].primary, failure);
      assert(Object.isFrozen(error.failures[0].primary));
      return true;
    });
    assert.deepEqual(fixture.stopped, []);
    assert.equal(await fixture.start(), 'not_started');
    released = true;
    await fixture.owner.drain();
    assert.equal(calls, 1);
    assert.equal(fixture.claims(), 1);
    assert.deepEqual(fixture.stopped, [[fixture.ref, 'failed']]);
  });

test('Content dispatch refuses private-only completion without a committed Result index',
  async () => {
    const fixture = inferDispatchFixture(async ({retainExecution}) => {
      retainExecution({async close() {}, cleanup: () => true,
        cleanupPending: () => false});
    }, 'serialization');
    assert.equal(await fixture.start(), 'started');
    await fixture.owner.drain();
    assert.deepEqual(fixture.stopped, [[fixture.ref, 'failed']]);
    assert.equal(fixture.claims(), 1);
  });

test('model dispatch consumes its original plan and shares physical Run custody',
  async () => {
    let calls = 0, closes = 0;
    const physical = {async close() { closes++; }, cleanup: () => true,
      cleanupPending: () => false};
    const fixture = inferDispatchFixture(async context => {
      calls++;
      assert.equal(context.preparedProgram, fixture.preparedProgram);
      assert.equal(context.plan, fixture.plan);
      context.retainExecution(physical);
      fixture.commit();
    });
    assert.equal(await fixture.start(), 'started');
    await fixture.owner.drain();
    assert.equal(calls, 1);
    assert.equal(closes, 1);
    assert.equal(fixture.claims(), 1);
    assert.deepEqual(fixture.stopped, [[fixture.ref, null]]);
  });

test('model capture alone is not public success and cleanup never redispatches',
  async () => {
    let calls = 0, released = false;
    const failure = new Error('CaptureStoreFailed');
    const fixture = inferDispatchFixture(async ({retainExecution}) => {
      calls++;
      retainExecution({async close() { throw new Error('CleanupPending'); },
        cleanup: () => released, cleanupPending: () => !released});
      throw failure;
    });
    assert.equal(await fixture.start(), 'started');
    await fixture.owner.operation(fixture.ref);
    await assert.rejects(fixture.owner.drain(), error => {
      assert.equal(error.code, 'ClientDispatchCleanupPending');
      assert.deepEqual(error.failures[0].primary,
        {name: 'Error', code: undefined, message: 'CaptureStoreFailed'});
      assert.notEqual(error.failures[0].primary, failure);
      assert(Object.isFrozen(error.failures[0].primary));
      return true;
    });
    assert.equal(await fixture.start(), 'not_started');
    assert.deepEqual(fixture.stopped, []);
    released = true;
    await fixture.owner.drain();
    assert.equal(calls, 1);
    assert.equal(fixture.claims(), 1);
    assert.deepEqual(fixture.stopped, [[fixture.ref, 'failed']]);
  });

test('model dispatch cannot report private completion as a published Result',
  async () => {
    const fixture = inferDispatchFixture(async ({retainExecution}) => {
      retainExecution({async close() {}, cleanup: () => true,
        cleanupPending: () => false});
    });
    assert.equal(await fixture.start(), 'started');
    await fixture.owner.drain();
    assert.deepEqual(fixture.stopped, [[fixture.ref, 'failed']]);
  });

test('failed model Result Store cleanup releases its pin before execution reclamation',
  async () => {
    let calls = 0, storePending = true, recover = false, released = false;
    const events = [];
    const fixture = inferDispatchFixture(async ({retainExecution}) => {
      calls++;
      retainExecution({async close() {
        events.push('close');
        if (storePending) throw new Error('OutputStillPinned');
      }, cleanup() {
        events.push('reclaim');
        released = !storePending;
        return released;
      }, cleanupPending: () => !released});
      throw Object.assign(new Error('StoreResultFailure'), {
        cleanupPending: true,
        cleanupHandle: {status: () => ({pending: storePending}),
          async retry() {
            events.push('store');
            if (!recover) throw new Error('StoreStillStopping');
            storePending = false;
          }},
      });
    });
    await fixture.start();
    await fixture.owner.operation(fixture.ref);
    assert.deepEqual(events, ['close', 'store']);
    assert.deepEqual(fixture.stopped, []);
    recover = true;
    await fixture.owner.drain();
    assert.deepEqual(events, ['close', 'store', 'close', 'store', 'reclaim']);
    assert.deepEqual(fixture.stopped, [[fixture.ref, 'failed']]);
    assert.equal(calls, 1);
  });

test('missing model connection refuses before the physical start claim',
  async () => {
    const fixture = inferDispatchFixture(undefined);
    assert.equal(await fixture.start(), 'not_started');
    await fixture.owner.drain();
    assert.equal(fixture.claims(), 0);
    assert.deepEqual(fixture.stopped, [[fixture.ref, 'not_started']]);
  });

test('missing Content connection refuses before the physical start claim without Values fallback',
  async () => {
    const fixture = inferDispatchFixture(undefined, 'serialization');
    assert.equal(await fixture.start(), 'not_started');
    await fixture.owner.drain();
    assert.equal(fixture.claims(), 0);
    assert.deepEqual(fixture.stopped, [[fixture.ref, 'not_started']]);
  });

test('model dispatch delivers cancellation and retains custody until physical stop',
  async () => {
    // Both typed barriers share this same dispatch stop/cleanup boundary. No
    // separate Content cancellation projection or cleanup state is introduced.
    for (const kind of ['infer', 'serialization']) {
      let entered, stopped, calls = 0, cleanupCalls = 0;
      const started = new Promise(resolve => { entered = resolve; });
      const stop = new Promise(resolve => { stopped = resolve; });
      let physicallyStopped = false, aborted = false;
      const fixture = inferDispatchFixture(async ({retainExecution, signal}) => {
        calls++;
        retainExecution({async close() {
          await stop;
          physicallyStopped = true;
        }, cleanup() {
          cleanupCalls++;
          assert.equal(physicallyStopped, true);
          return true;
        }, cleanupPending: () => !physicallyStopped});
        signal.addEventListener('abort', () => { aborted = true; }, {once: true});
        entered();
        await stop;
        signal.throwIfAborted();
      }, kind);
      assert.equal(await fixture.start(), 'started');
      await started;
      fixture.owner.cancel(fixture.ref);
      assert.equal(aborted, true);
      assert.equal(cleanupCalls, 0);
      assert.deepEqual(fixture.stopped, []);
      assert.equal(await fixture.start(), 'not_started');
      stopped();
      await fixture.owner.drain();
      assert.equal(calls, 1);
      assert.equal(cleanupCalls, 1);
      assert.deepEqual(fixture.stopped, [[fixture.ref, 'cancelled']]);
    }
  });

test('diagnostic failure cannot stop Compute or bypass required ownership',
  async () => {
    for (const kind of ['throw', 'reject', 'pending']) {
      let starts = 0;
      let closes = 0;
      let retained = 0;
      const stopped = [];
      const ref = {runDefinitionCid: `diagnostic-${kind}`};
      const installedConfiguration = Object.freeze({snapshotStore: {}});
      const physical = {async close() { closes++; }, async cleanup() {},
        cleanupPending: () => false};
      const owner = installNodeClientDispatchOwner({
        moon: {clientProgramOpenSourceFreeLocalHost: () => ({}),
          clientProgramRequiresAcquisitionResultPublication: () => false},
        control: stopControl,
        journal: {reservePhysicalStart: () => true,
          ...stopFacts(false, stopped)},
        store: {confirmCommittedIndex: async () => ({})},
        startRun: async () => ({kind: 'reserved', ref}),
        hostConnection: () => true,
        observed: () => {
          if (kind === 'throw') throw new Error('SinkFailed');
          if (kind === 'reject') return Promise.reject(new Error('SinkFailed'));
          return new Promise(() => {});
        },
        planFor: () => ({runDefinition: {wire: 'definition'}}),
        computeConfigurations: {fixtureProvider: installedConfiguration},
        runPublished: async (_setup, _publication, options, _signal,
          _observer, retainExecution) => {
          assert.equal(options.fixtureProvider, installedConfiguration,
            'shared dispatch forwards the concrete adapter configuration unchanged');
          starts++;
          retainExecution(physical);
          retained++;
          return physical;
        }, namespaceId: 'namespace-a',
      });
      const accepted = {ref, runDefinition: {wire: 'definition'},
        dispatchReserved: false, cancellationRequested: false};
      await owner.start({preparedProgram: {}, principalId: 'owner',
        connection: {}, requestId: 'request-a'}, {}, accepted, {});
      await owner.drain();
      assert.equal(starts, 1);
      assert.equal(retained, 1);
      assert.equal(closes, 1);
      assert.deepEqual(stopped, [[ref, null]]);
      assert.equal(owner.operation(ref), undefined);
    }
  });

test('publication ownership survives a wrapped error and cleanup retry',
  async () => {
    const ref = {runDefinitionCid: 'wrapped-run'};
    let starts = 0;
    let closes = 0;
    let permitCleanup = false;
    let publicationReadable = false;
    const stopped = [];
    const failure = new Error('PublicationFailure');
    const wrapped = new Error('BoundaryFailure', {cause: failure});
    const physical = {
      async close() {
        closes++;
        if (!permitCleanup) throw new Error('CloseFailure');
      },
      async cleanup() {},
      cleanupPending: () => !permitCleanup,
    };
    const owner = installNodeClientDispatchOwner({
      moon: {clientProgramOpenSourceFreeLocalHost: () => ({}),
        clientProgramRequiresAcquisitionResultPublication: () => false},
      control: stopControl,
      journal: {reservePhysicalStart: () => true,
        ...stopFacts(false, stopped)},
      store: {confirmCommittedIndex: async () => {
        if (!publicationReadable) throw new Error('StoreObservationFailure');
        return undefined;
      }},
      startRun: async () => ({kind: 'reserved', ref}),
      hostConnection: () => true,
      observed: async () => {},
      planFor: () => ({runDefinition: {wire: 'definition'}}),
      runPublished: async (_setup, _publication, _options, _signal,
        _observer, retainExecution) => {
        starts++;
        retainExecution(physical);
        throw wrapped;
      },
      namespaceId: 'namespace-a',
    });
    const submission = {preparedProgram: {}, principalId: 'owner',
      connection: {}, requestId: 'wrapped-request'};
    const accepted = {ref, runDefinition: {wire: 'definition'},
      dispatchReserved: false, cancellationRequested: false};
    assert.equal(await owner.start(submission, {}, accepted, {}), 'started');
    await owner.operation(ref);
    assert.deepEqual(stopped, []);
    await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
    permitCleanup = true;
    await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
    assert.deepEqual(stopped, []);
    assert.notEqual(owner.operation(ref), undefined);
    publicationReadable = true;
    await owner.drain();
    assert.equal(starts, 1);
    assert.ok(closes >= 2);
    assert.deepEqual(stopped, [[ref, 'failed']]);
    assert.equal(owner.operation(ref), undefined);
  });

test('dispatch owner retains failed cleanup and retries without Compute',
  async () => {
    const ref = {runDefinitionCid: 'run-a'};
    let starts = 0;
    let closes = 0;
    let cleanups = 0;
    let permitCleanup = false;
    const stopped = [];
    const closeFailure = new Error('PhysicalCloseFailed');
    let closeFlight;
    const physical = {
      close() {
        closes++;
        return closeFlight ??= Promise.reject(closeFailure);
      },
      async cleanup() { cleanups++; return permitCleanup; },
      cleanupPending: () => !permitCleanup,
    };
    const owner = installNodeClientDispatchOwner({
      moon: {clientProgramOpenSourceFreeLocalHost: () => ({}),
        clientProgramRequiresAcquisitionResultPublication: () => false},
      control: stopControl,
      journal: {
        ...stopFacts(false, stopped),
        reservePhysicalStart: () => true,
      },
      store: {confirmCommittedIndex: async () => ({})},
      startRun: async () => ({kind: 'reserved', ref}),
      hostConnection: () => true,
      observed: async () => {},
      planFor: () => ({runDefinition: {wire: 'definition'}}),
      runPublished: async (_setup, _publication, _configuration,
        _signal, _faultInjection, retain) => {
        starts++;
        // Match the real publication runner's custody transfer before it
        // returns. A returned mock alone leaves the original setup unowned.
        retain(physical);
        return physical;
      },
      namespaceId: 'namespace-a',
    });
    const submission = {preparedProgram: {}, principalId: 'owner',
      connection: {}, requestId: 'request-a'};
    const accepted = {ref, runDefinition: {wire: 'definition'},
      dispatchReserved: false, cancellationRequested: false};
    assert.equal(await owner.start(submission, {}, accepted, {}), 'started');
    assert.equal(await owner.start(submission, {}, accepted, {}),
      'not_started');
    await owner.operation(ref);
    assert.equal(starts, 1);
    assert.deepEqual(stopped, []);
    for (let retry = 0; retry < 2; retry++) {
      await assert.rejects(owner.drain(), error => {
        assert.equal(error.code, 'ClientDispatchCleanupPending');
        assert.deepEqual(error.failures[0].close,
          {name: 'Error', code: undefined, message: 'PhysicalCloseFailed'},
          inspect(error.failures, {depth: 4, maxArrayLength: 5, maxStringLength: 200}));
        assert.notEqual(error.failures[0].close, closeFailure);
        assert(Object.isFrozen(error.failures[0].close));
        return true;
      });
      assert.notEqual(owner.operation(ref), undefined);
      assert.deepEqual(stopped, []);
    }
    assert.equal(cleanups, 4);
    permitCleanup = true;
    await owner.drain();
    assert.equal(starts, 1);
    assert.ok(closes >= 2);
    assert.equal(cleanups, 5);
    assert.deepEqual(stopped, [[ref, null]]);
    assert.equal(owner.operation(ref), undefined);
  });

test('Effect owner retains an unobserved start after callback failure',
  async () => {
    const ref = {runDefinitionCid: 'effect-claimed-before-callback'};
    let calls = 0;
    let observed = 0;
    const owner = installNodeClientDispatchOwner({});
    const run = ({beginPhysicalWork}) => {
      calls++;
      beginPhysicalWork();
      throw new Error('LostEffectOwner');
    };
    const first = owner.track(ref, {run,
      observeStopped: () => { observed++; }});
    await assert.rejects(first, {message: 'LostEffectOwner'});
    assert.equal(owner.track(ref, {run,
      observeStopped: () => { observed++; }}), first);
    await assert.rejects(owner.drain(), error => {
      assert.equal(error.code, 'ClientDispatchCleanupPending');
      assert.deepEqual(error.pendingRefs, [ref]);
      return true;
    });
    assert.equal(calls, 1);
    assert.equal(observed, 0);
    assert.equal(owner.live(ref), false);
    assert.equal(owner.operation(ref), first);
  });

test('Effect no-send failure is terminal only after physical cleanup',
  async () => {
    const ref = {runDefinitionCid: 'effect-no-send'};
    let cleanups = 0;
    let ready = false;
    const stopped = [];
    const owner = installNodeClientDispatchOwner({});
    const physical = {async close() {}, async cleanup() {
      cleanups++;
      return ready;
    }, cleanupPending: () => !ready};
    const operation = owner.track(ref, {run: ({retainExecution}) => {
      retainExecution(physical);
      return {status: 'failed_without_effect_dispatch'};
    }, observeStopped: outcome => stopped.push(outcome)});
    await assert.rejects(operation, {message: 'ClientDispatchCleanupPending'});
    assert.deepEqual(stopped, []);
    await assert.rejects(owner.drain(),
      {code: 'ClientDispatchCleanupPending'});
    assert.deepEqual(stopped, []);
    ready = true;
    await owner.drain();
    assert.ok(cleanups >= 3);
    assert.deepEqual(stopped, ['failed']);
    assert.equal(owner.operation(ref), undefined);
  });

test('Effect no-send report without a cleanup owner remains unresolved',
  async () => {
    const ref = {runDefinitionCid: 'effect-no-owner'};
    let observed = 0;
    const owner = installNodeClientDispatchOwner({});
    const operation = owner.track(ref, {run: ({beginPhysicalWork}) => {
      beginPhysicalWork();
      return {status: 'failed_without_effect_dispatch'};
    },
    observeStopped: () => { observed++; }});
    await assert.rejects(operation, {message: 'ClientDispatchStopUnknown'});
    await assert.rejects(owner.drain(),
      {code: 'ClientDispatchCleanupPending'});
    assert.equal(observed, 0);
    assert.equal(owner.operation(ref), operation);
  });

test('known failed Effect Set is terminal only after retained cleanup',
  async () => {
    const ref = {runDefinitionCid: 'effect-known-failed'};
    const stopped = [];
    let ready = false;
    let runs = 0;
    const owner = installNodeClientDispatchOwner({});
    const physical = {async close() {}, async cleanup() { return ready; },
      cleanupPending: () => !ready};
    const operation = owner.track(ref, {run: ({retainExecution}) => {
      runs++;
      retainExecution(physical);
      return {status: 'failed_effect_set'};
    }, observeStopped: outcome => stopped.push(outcome)});
    await assert.rejects(operation, {message: 'ClientDispatchCleanupPending'});
    assert.deepEqual(stopped, []);
    ready = true;
    await owner.drain();
    assert.equal(runs, 1);
    assert.deepEqual(stopped, ['failed']);
  });

test('Effect dispatch barrier gates both execution and refusal', async () => {
  const ref = {runDefinitionCid: 'effect-barrier'};
  let release;
  const barrier = new Promise(resolve => { release = resolve; });
  let started = 0;
  const stopped = [];
  const physical = {async close() {}, async cleanup() { return true; },
    cleanupPending: () => false};
  const owner = installNodeClientDispatchOwner({
    beforeDispatch: () => barrier});
  const flight = owner.track(ref, {
    run({beginPhysicalWork, retainExecution}) {
      started++;
      beginPhysicalWork();
      retainExecution(physical);
      return {status: 'failed_without_effect_dispatch'};
    }, observeStopped: value => stopped.push(value),
    barrierFailureOutcome: 'failed'});
  await Promise.resolve();
  assert.equal(started, 0);
  release();
  await flight;
  await owner.drain();
  assert.equal(started, 1);
  assert.deepEqual(stopped, ['failed']);

  let refusedCalls = 0;
  const denied = installNodeClientDispatchOwner({beforeDispatch() {
    refusedCalls++;
    throw new Error('ExecutionBarrierDenied');
  }});
  await assert.rejects(denied.track(ref, {
    run() { assert.fail('No Site I/O after a barrier refusal'); },
    observeStopped: value => stopped.push(value),
    barrierFailureOutcome: 'failed',
  }), {message: 'ExecutionBarrierDenied'});
  await denied.drain();
  assert.equal(refusedCalls, 1);
  assert.deepEqual(stopped, ['failed', 'failed']);

  let releaseCancelled;
  const cancellationBarrier = new Promise(resolve => {
    releaseCancelled = resolve;
  });
  const cancelled = installNodeClientDispatchOwner({
    beforeDispatch: () => cancellationBarrier, control: stopControl,
    journal: stopFacts(true), store: {confirmCommittedIndex: async () => undefined}});
  const cancelledFlight = cancelled.track(ref, {
    run() { assert.fail('Cancellation before the barrier cannot dispatch'); },
    observeStopped: value => stopped.push(value),
    barrierFailureOutcome: 'failed',
  });
  cancelled.cancel(ref);
  releaseCancelled();
  await assert.rejects(cancelledFlight, {message:
    'ClientRunCancellationRequested'});
  await cancelled.drain();
  assert.deepEqual(stopped, ['failed', 'failed', 'cancelled']);
});

// An acquiring dispatch whose source adapter returns no capture.
function acquiringOwner(open) {
  const ref = {runDefinitionCid: 'acquiring-run'};
  const stopped = [];
  let computes = 0;
  const access = {authorization: {}};
  const owner = installNodeClientDispatchOwner({
    // Stop-law scalar fixture: physical acquisition always throws below.
    // This ledger token is not Common capacity or a successful capture.
    moon: {clientProgramAcquisitionCount: () => 1,
      clientProgramRequiresAcquisitionResultPublication: () => false,
      clientProgramPrepareSingleCapturedLocalInstalledLedger: () => ({}),
      clientProgramMultiCapturedLedgerUsage: () => Array(ledgerUsageFields.length).fill(0n)},
    control: stopControl,
    journal: {reservePhysicalStart: () => true,
      ...stopFacts(false, stopped)},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    observed: async () => {},
    planFor: () => ({runDefinition: {wire: 'definition'}}),
    sourceProfile: {sourceAccess: access, admitsSource: source => source === 'fixture-source',
      ledgerCapacity: () => ({capacity: {}, transferBytes: 0n, executionBytes: 0n}), open},
    runPublished: async () => { computes++; },
    now: () => '2026-09-28T00:00:00.000Z',
    namespaceId: 'namespace-a',
  });
  const run = async () => {
    const accepted = {ref, runDefinition: {wire: 'definition'},
      dispatchReserved: false, cancellationRequested: false};
    assert.equal(await owner.start({preparedProgram: {}, principalId: 'owner',
      connection: {}, requestId: 'acquiring-request'}, {}, accepted,
    {preparedSourceAccess: access, preparedSource: {checkedSource: {sourceRef: 'fixture-source'}}}), 'started');
    await owner.operation(ref);
  };
  return {owner, ref, stopped, run, computes: () => computes};
}

test('a confirmed unstarted or stopped acquisition ends the Run and drains',
  async () => {
    const {acquisitionFailure} = await import(
      '../host-common/acquisition-outcome.mjs');
    for (const outcome of ['not_started', 'stopped']) {
      let opens = 0;
      const dispatch = acquiringOwner(async () => {
        opens++;
        throw acquisitionFailure(Object.assign(new Error('Denied'),
          {code: 'ExecutionAuthorizationDenied'}), outcome);
      });
      await dispatch.run();
      // The confirmed end is the Run's observed stop; nothing is left.
      assert.deepEqual(dispatch.stopped, [[dispatch.ref, 'failed']], outcome);
      await dispatch.owner.drain();
      assert.equal(dispatch.owner.operation(dispatch.ref), undefined);
      assert.equal(opens, 1);
      assert.equal(dispatch.computes(), 0);
    }
  });

test('an unknown acquisition end stays with its recovery owner', async () => {
  const {acquisitionFailure} = await import(
    '../host-common/acquisition-outcome.mjs');
  let released = false;
  let cleanups = 0;
  const recovery = {close: async () => {},
    cleanup: async () => { cleanups++; return released; },
    cleanupPending: () => !released};
  const dispatch = acquiringOwner(async () => {
    throw acquisitionFailure(new Error('TransportLost'), 'unknown', recovery);
  });
  await dispatch.run();
  // Until the recovery owner confirms release, the stop is not observed and
  // the Host keeps the owner instead of closing past it.
  assert.deepEqual(dispatch.stopped, []);
  await assert.rejects(dispatch.owner.drain(),
    {code: 'ClientDispatchCleanupPending'});
  assert.deepEqual(dispatch.stopped, []);
  released = true;
  await dispatch.owner.drain();
  assert.deepEqual(dispatch.stopped, [[dispatch.ref, 'failed']]);
  assert.ok(cleanups >= 2);
  assert.equal(dispatch.computes(), 0);
});

test('a wrapped acquisition error cannot hide an explicitly transferred owner',
  async () => {
    const {acquisitionFailure} = await import(
      '../host-common/acquisition-outcome.mjs');
    let opens = 0;
    let released = false;
    let closes = 0;
    const recovery = {async close() { closes++; },
      async cleanup() { return released; },
      cleanupPending: () => !released};
    const dispatch = acquiringOwner(async ({reportAcquisitionFailure}) => {
      opens++;
      const failure = acquisitionFailure(new Error('ReadLost'),
        'unknown', recovery);
      reportAcquisitionFailure(failure);
      throw new Error('AdapterBoundaryFailed', {cause: failure});
    });
    await dispatch.run();
    assert.deepEqual(dispatch.stopped, []);
    await assert.rejects(dispatch.owner.drain(),
      {code: 'ClientDispatchCleanupPending'});
    assert.equal(opens, 1);
    released = true;
    await dispatch.owner.drain();
    assert.deepEqual(dispatch.stopped, [[dispatch.ref, 'failed']]);
    assert.equal(opens, 1);
    assert.equal(dispatch.computes(), 0);
    assert.equal(closes, 3);
    await dispatch.owner.drain();
    assert.equal(closes, 3);
  });

test('a wrapped confirmed acquisition end still records its stop', async () => {
  const {acquisitionFailure} = await import(
    '../host-common/acquisition-outcome.mjs');
  const dispatch = acquiringOwner(async ({reportAcquisitionFailure}) => {
    const failure = acquisitionFailure(new Error('ReadDenied'), 'not_started');
    reportAcquisitionFailure(failure);
    throw new Error('AdapterBoundaryFailed', {cause: failure});
  });
  await dispatch.run();
  await dispatch.owner.drain();
  assert.deepEqual(dispatch.stopped, [[dispatch.ref, 'failed']]);
  assert.equal(dispatch.computes(), 0);
});

test('an acquisition failure without a stated end is never inferred stopped',
  async () => {
    const dispatch = acquiringOwner(async () => {
      throw new Error('NativeReadFailed');
    });
    await dispatch.run();
    assert.deepEqual(dispatch.stopped, []);
    await assert.rejects(dispatch.owner.drain(),
      {code: 'ClientDispatchCleanupPending'});
    await assert.rejects(dispatch.owner.drain(),
      {code: 'ClientDispatchCleanupPending'});
    assert.deepEqual(dispatch.stopped, []);
    assert.equal(dispatch.computes(), 0);
  });

// This regression uses a checked Values Program, the real entry/preflight and
// real setup stop/usage and Store capacity owner. The journal is a protocol
// double; no Compute contribution or provider may enter. This deliberately
// tiny synthetic Store is not public publication history or a production limit.
async function preflightDispatchFixture(t, {
  blocked, unowned = false, partialSiteInstallation = false, sanitize = false,
} = {}) {
  const [document, environmentWire, registry, contract] = await Promise.all([
    readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'),
    readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8'),
    readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'),
  ]);
  let funded, owner, physicalStore, directory;
  let setup, stopCalls = 0, stopped = 0, closeCalls = 0, closed = 0;
  let custodyTransfers = 0, capacityChecks = 0, originalFailure, retainedCleanupOwner;
  const cleanupFailure = new Error('exact setup cleanup pending');
  const siteFailure = new Error('second new Site create failed');
  let siteCreates = 0, siteCleanupBlocked = true, firstNewHandle;
  const siteTeardowns = [];
  const runtime = {...cancellationMoon,
    strategySiteCreate(...args) {
      siteCreates++;
      if (partialSiteInstallation && siteCreates === 3) throw siteFailure;
      const handle = cancellationMoon.strategySiteCreate(...args);
      if (partialSiteInstallation && siteCreates === 2) firstNewHandle = handle;
      return handle;
    },
    strategySiteBeginTeardown(handle) {
      siteTeardowns.push(handle);
      if (partialSiteInstallation && handle === firstNewHandle && siteCleanupBlocked) {
        throw cleanupFailure;
      }
      return cancellationMoon.strategySiteBeginTeardown(handle);
    },
    clientProgramOpenSourceFreeLocalHost(...args) {
      setup = cancellationMoon.clientProgramOpenSourceFreeLocalHost(...args);
      assert.ok(setup);
      return setup;
    },
    strategyHostStop(value) {
      assert.equal(value, setup); stopCalls++;
      if (blocked === 'stop') throw cleanupFailure;
      cancellationMoon.strategyHostStop(value); stopped++;
    },
    strategyHostCloseOutputs(value) {
      assert.equal(value, setup); closeCalls++;
      if (blocked === 'outputs') throw cleanupFailure;
      cancellationMoon.strategyHostCloseOutputs(value); closed++;
    },
    strategyHostUsage(value) {
      assert.equal(value, setup);
      const usage = [...cancellationMoon.strategyHostUsage(value)];
      // A synthetic outstanding byte tests the release barrier independently
      // of successful stop/output-close calls; all other usage stays real.
      if (blocked === 'usage') usage[ledgerUsageFields.findIndex(({name}) => name === 'reserved_retention_bytes')] = 1n;
      return usage;
    },
    strategyHostNext() { assert.fail('preflight refusal must not enter Compute'); },
  };
  const control = runtimeCore(runtime).publicationControl;
  const environment = runtime.clientProgramCheckEnvironment(environmentWire.trimEnd(),
    'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
    false, false, true, false, false, false, false);
  assert.ok(environment);
  t.after(async () => {
    if (owner !== undefined) {
      if (unowned && setup !== undefined) {
        // The original dispatch catch already stopped this SAME pending setup.
        // Its missing execution handoff still cannot certify a public stop.
        await owner.operation(ref);
        assert.equal(stopped, 1);
        assert.equal(closed, 1);
        assert.equal(ledgerUsageSnapshotHasPendingResources(runtimeCore(runtime).usage(setup)), false);
      } else await owner.drain();
    }
    await physicalStore?.close();
    await funded?.close();
    if (directory !== undefined) await rm(directory, {recursive: true});
  });
  funded = await openFundedClientPreparation({moon: runtime, environment});
  const preparedProgram = await funded.prepare(
    {kind: 'program', input: JSON.parse(document), parameters: null});
  const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
  const namespaceId = 'preflight-custody';
  const plan = sourceFreeValuesPlan({moon: runtime, control, preparedProgram, publicationOriginal: publicationOriginalFixture(runtime,preparedProgram),
    authorityScopeCid, namespaceId, storeAuthorityCid: `sha256:${'7'.repeat(64)}`,
    now: () => '2026-10-09T00:00:00.000Z'});
  const ref = {namespaceId, authorityScopeCid, runDefinitionCid: plan.runDefinition.identity};
  const state = {revision: 1, cancellationRequested: false,
    physicalCloseConfirmed: false, runDefinition: plan.runDefinition};
  const stops = [];
  const journal = {
    reservePhysicalStart() { state.revision++; return true; },
    lookupRunDefinition: () => state,
    lookupReconciliationState: () => undefined,
    markPhysicalClose(actual, outcome) {
      assert.deepEqual(actual, ref); state.physicalCloseConfirmed = true;
      state.observedTerminalOutcome = outcome; state.revision++; stops.push([actual, outcome]);
    },
    markPreDispatchFailure() { assert.fail('physical start was already reserved'); },
  };
  directory = await mkdtemp(join(tmpdir(), 'actql-preflight-custody-'));
  physicalStore = await openLocalPublicationStore({directory,
    storeAuthorityCid: `sha256:${'7'.repeat(64)}`, maxObjects: 20,
    capacityBytes: 512 * 1024 * 1024, maxObjectBytes: 10000000,
    maxContractNodes: 10000, maxContractDepth: 64}, control);
  const requirement = {objectCount: 19, requiredBytes: 190000000, maxObjectBytes: 10000000};
  await physicalStore.putBytes(Buffer.from('independent retained object A'));
  assert.equal(physicalStore.publicationCapacitySupports(requirement), true);
  if (!partialSiteInstallation) {
    await physicalStore.putBytes(Buffer.from('independent retained object B'));
  }
  assert.equal(physicalStore.status().objectCount, partialSiteInstallation ? 1 : 2);
  assert.equal(physicalStore.status().reservedObjects, 0);
  assert.equal(physicalStore.publicationCapacitySupports(requirement), partialSiteInstallation);
  const store = {...physicalStore,
    publicationCapacitySupports(actual) {
      capacityChecks++;
      assert.deepEqual(actual, requirement);
      return physicalStore.publicationCapacitySupports(actual);
    }};
  let existingSite, installationOptions = {};
  const contributions = partialSiteInstallation ? [{registration: {},
    run() { assert.fail('partial installation must not enter Compute'); }}] : [];
  if (partialSiteInstallation) {
    const site = key => createInProcessExecutionSite({key, generation: 1, runtimeRevision: 'fixture/1'});
    existingSite = site('existing');
    installExecutionSites(prepareExecutionSitePolicy({sites: [existingSite]}),
      contributions, runtimeCore(runtime).siteControl);
    installationOptions = {executionSitePolicy: prepareExecutionSitePolicy({
      sites: [existingSite, site('first-new'), site('second-new')],
    })};
  }
  const entry = createNodeHostEntry(async () => runtime, async () => contributions);
  const unownedFailure = Object.assign(new Error('unowned capacity-shaped error'),
    {code: 'RunPublicationCapacityUnsupported'});
  owner = installNodeClientDispatchOwner({moon: runtime, control, journal, store,
    namespaceId, registry, values: JSON.stringify(JSON.parse(contract).execution_contracts['REL.values']),
    startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
    planFor: () => plan,
    async runPublished(actualSetup, publication, options, signal, observer, retainOwner, tasks) {
      assert.equal(actualSetup, setup);
      if (unowned) throw unownedFailure;
      try {
        return await entry.runPublishedCapturedStrategy(actualSetup, publication,
          {...options, ...installationOptions}, signal, observer, cleanupOwner => {
            custodyTransfers++;
            assert.equal(custodyTransfers, 1);
            assert.equal(stopCalls, 0, 'transfer precedes either cleanup path');
            assert.equal(Object.hasOwn(cleanupOwner, 'completed'), false);
            assert.equal(Object.hasOwn(cleanupOwner, 'resultInventory'), false);
            assert.equal(Object.hasOwn(cleanupOwner, 'publishEffectFreeRun'), false);
            retainedCleanupOwner = cleanupOwner;
            retainOwner(cleanupOwner);
          }, tasks);
      } catch (error) {
        originalFailure = error;
        if (sanitize) throw new Error('outer boundary withheld error details');
        throw error;
      }
    },
  });
  return {owner, ref, state, stops, cleanupFailure,
    start: () => owner.start({preparedProgram, principalId: 'owner', connection: {},
      requestId: 'preflight-original'}, {}, {ref, runDefinition: plan.runDefinition,
      dispatchReserved: false, cancellationRequested: false}, {}),
    allowCleanup: () => { blocked = undefined; },
    counts: () => ({stopCalls, stopped, closeCalls, closed, custodyTransfers, capacityChecks}),
    failure: () => originalFailure,
    cleanupOwner: () => retainedCleanupOwner,
    siteFailure,
    allowSiteCleanup: () => { siteCleanupBlocked = false; },
    siteFacts: () => ({creates: siteCreates,
      onlyOriginalNewHandle: siteTeardowns.every(handle => handle === firstNewHandle),
      existingAccepting: executionSiteDescription(existingSite).accepting}),
    reenter: () => runInstalledStrategy({setup, runtime: {core: runtimeCore(runtime), contributions: []}}),
  };
}

test('partial Site installation transfers same cleanup custody even when its error is sanitized', async t => {
  const f = await preflightDispatchFixture(t, {partialSiteInstallation: true, sanitize: true});
  await f.start();
  await f.owner.operation(f.ref);
  const primary = f.failure();
  assert.equal(primary.primaryFailure.cause, f.siteFailure);
  assert.equal(primary.cleanupHandle, f.cleanupOwner());
  assert.equal(f.cleanupOwner().cleanupPending(), true);
  assert.deepEqual(f.stops, []);
  assert.equal(f.state.physicalCloseConfirmed, false);
  assert.deepEqual(f.siteFacts(), {creates: 3, onlyOriginalNewHandle: true, existingAccepting: true});
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.equal(f.counts().stopped, 1);
  assert.equal(f.counts().closed, 1);
  assert.equal(f.counts().custodyTransfers, 1);
  f.allowSiteCleanup();
  await f.owner.drain();
  assert.deepEqual(f.stops, [[f.ref, 'failed']]);
  assert.equal(f.state.physicalCloseConfirmed, true);
  assert.equal(f.cleanupOwner().cleanupPending(), false);
  assert.deepEqual(f.siteFacts(), {creates: 3, onlyOriginalNewHandle: true, existingAccepting: true});
  const counts = f.counts();
  await f.owner.drain();
  assert.deepEqual(f.counts(), counts);
  assert.equal(f.failure(), primary);
});

test('preflight setup custody confirms actual stop once without entering Compute', async t => {
  const f = await preflightDispatchFixture(t);
  assert.equal(await f.start(), 'started');
  await f.owner.operation(f.ref); await f.owner.drain();
  assert.equal(f.failure().code, 'RunPublicationCapacityUnsupported');
  assert.deepEqual(f.stops, [[f.ref, 'failed']]);
  assert.equal(f.state.physicalCloseConfirmed, true);
  assert.deepEqual(f.counts(), {stopCalls: 1, stopped: 1, closeCalls: 1,
    closed: 1, custodyTransfers: 1, capacityChecks: 1});
  await f.owner.drain();
  await f.cleanupOwner().close();
  assert.equal(await f.cleanupOwner().cleanup(), true);
  await assert.rejects(f.reenter(), {code: 'ReleasedStrategy'});
  assert.deepEqual(f.counts(), {stopCalls: 1, stopped: 1, closeCalls: 1,
    closed: 1, custodyTransfers: 1, capacityChecks: 1});
});

for (const blocked of ['stop', 'outputs', 'usage']) {
  test(`preflight ${blocked} failure retains its exact owner and primary until cleanup retry`, async t => {
    const f = await preflightDispatchFixture(t, {blocked});
    await f.start(); await f.owner.operation(f.ref);
    const primary = f.failure();
    assert.equal(primary.primaryFailure.code, 'RunPublicationCapacityUnsupported');
    assert.equal(primary.cause, primary.primaryFailure);
    if (blocked === 'usage') {
      assert.equal(primary.cleanupErrors.length, 1);
      assert.equal(primary.cleanupErrors[0].code, 'PublicationPreflightCleanupPending');
      assert.equal(f.counts().stopped, 1);
      assert.equal(f.counts().closed, 1);
    } else assert.deepEqual(primary.cleanupErrors, [f.cleanupFailure]);
    assert.equal(primary.cleanupHandle, f.cleanupOwner());
    assert.equal(f.cleanupOwner().status().pending, true);
    assert.equal(f.state.physicalCloseConfirmed, false);
    assert.deepEqual(f.stops, []);
    await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
    await assert.rejects(f.reenter(), {code: 'StrategyAlreadyRunning'});
    f.allowCleanup();
    await f.owner.drain();
    assert.deepEqual(f.stops, [[f.ref, 'failed']]);
    assert.equal(f.counts().stopped, 1);
    assert.equal(f.counts().closed, 1);
    assert.equal(f.counts().custodyTransfers, 1);
    assert.equal(f.counts().capacityChecks, 1);
    if (blocked !== 'stop') assert.equal(f.counts().stopCalls, 1);
    if (blocked === 'usage') assert.equal(f.counts().closeCalls, 1);
    const counts = f.counts();
    await f.owner.drain();
    await f.cleanupOwner().close();
    assert.equal(await f.cleanupOwner().cleanup(), true);
    assert.equal(f.cleanupOwner().status().pending, false);
    assert.deepEqual(f.counts(), counts, 'released custody cannot stop or close again');
    await assert.rejects(f.reenter(), {code: 'ReleasedStrategy'});
    assert.equal(f.failure(), primary, 'cleanup never replaces the original failure');
  });
}

test('an unowned capacity-shaped exception cannot certify physical stop', async t => {
  const f = await preflightDispatchFixture(t, {unowned: true});
  await f.start(); await f.owner.operation(f.ref);
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.equal(f.state.physicalCloseConfirmed, false);
  assert.deepEqual(f.stops, []);
  assert.equal(f.counts().custodyTransfers, 0);
  assert.equal(f.counts().capacityChecks, 0);
});

test('a rejected preflight custody handoff cannot stop or release its setup', async () => {
  // This isolated coordination control has no resource-bearing setup. The
  // real setup/Store controls above establish actual physical cleanup.
  const setup = {};
  const primary = new Error('independent preflight refusal');
  const rejection = new Error('receiver refused custody');
  let stops = 0, closes = 0, handoffs = 0, rejectedOwner;
  const core = {stop() { stops++; }, closeOutputs() { closes++; },
    usage: () => ({reservedTransferBytes: 0n, heldBytes: 0n,
      reservedRetentionBytes: 0n, reservedExecutionBytes: 0n})};
  await assert.rejects(runInstalledStrategy({
    setup,
    runtime: {
      core,
      contributions: [],
    },
    publication: {
      beforeCompute: () => { throw primary; },
    },
    cleanup: {
      retainPreflightCleanup: owner => {
        handoffs++; rejectedOwner = owner; throw rejection;
      },
    },
  }), error => {
      assert.equal(error.primaryFailure, primary);
      assert.equal(error.cause, primary);
      assert.deepEqual(error.cleanupErrors, [rejection]);
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle, undefined);
      return true;
    });
  assert.deepEqual({handoffs, stops, closes}, {handoffs: 1, stops: 0, closes: 0});
  assert.equal(rejectedOwner.status().pending, true);
  await assert.rejects(runInstalledStrategy({setup, runtime: {core, contributions: []}}), {code: 'StrategyAlreadyRunning'});
  assert.deepEqual({handoffs, stops, closes}, {handoffs: 1, stops: 0, closes: 0});
});

// Persist the independently exercised public byte-capacity counterexample in
// this existing Host gate. Children use the normal source Host entry, never
// test Run admission or patched package payloads. No new job/build is needed.
test('public byte-capacity refusal retains terminal identity after Host process restart',
  {timeout: 40000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-byte-capacity-'));
    let passed = false;
    t.after(async () => {
      if (passed) await rm(directory, {recursive: true});
      else console.error('Retained public byte-capacity failure evidence:', directory);
    });
    const child = 'import {connectEmbeddedLocal as connect} from ' +
      JSON.stringify(new URL('./embedded-local.mjs', import.meta.url).href) + ';\n' +
      'import {createHostObservationConnection, observationLimits} from ' +
      JSON.stringify(new URL('../host-common/observation.mjs', import.meta.url).href) + ';\n' + `// Registered source Host byte-capacity control. The independent normal-package
// receipt remains separate evidence; this is not an object-ceiling reproduction.
import assert from 'node:assert/strict';
import {mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {createHash} from 'node:crypto';

const [phase, directoryArgument, ...extra] = process.argv.slice(1);
assert.ok(['initial', 'restored'].includes(phase) && directoryArgument && extra.length === 0,
  'Usage: public-byte-capacity-control.mjs initial|restored <evidence-directory>');
const directory = resolve(directoryArgument);
if (phase === 'initial') await mkdir(directory);
const fiveText = "{\\n  \\"version\\": \\"actql/0.1\\",\\n  \\"id\\": \\"public-five-result-capacity-witness\\",\\n  \\"stages\\": [{\\n    \\"id\\": \\"numbers\\",\\n    \\"inputs\\": {},\\n    \\"steps\\": [{\\"values\\": {\\n      \\"schema\\": {\\"n\\": {\\"type\\": \\"number\\", \\"nullable\\": false}},\\n      \\"rows\\": [{\\"n\\": 7}, {\\"n\\": 11}]\\n    }, \\"as\\": \\"selected\\"}],\\n    \\"results\\": {\\"rows\\": {\\"from\\": \\"selected\\", \\"fields\\": [\\"n\\"]}}\\n  }, {\\n    \\"id\\": \\"projected\\",\\n    \\"inputs\\": {\\"incoming\\": {\\"result\\": {\\"stage\\": \\"numbers\\", \\"result\\": \\"rows\\"}}},\\n    \\"steps\\": [{\\"from\\": \\"incoming\\", \\"select\\": [\\"n\\"], \\"as\\": \\"selected\\"}],\\n    \\"results\\": {\\"rows\\": {\\"from\\": \\"selected\\", \\"fields\\": [\\"n\\"]}}\\n  }],\\n  \\"results\\": {\\n    \\"first\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"second\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"third\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"fourth\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"fifth\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}}\\n  }\\n}\\n";
const sixText = "{\\n  \\"version\\": \\"actql/0.1\\",\\n  \\"id\\": \\"public-six-result-byte-capacity-refusal\\",\\n  \\"stages\\": [{\\n    \\"id\\": \\"numbers\\",\\n    \\"inputs\\": {},\\n    \\"steps\\": [{\\"values\\": {\\n      \\"schema\\": {\\"n\\": {\\"type\\": \\"number\\", \\"nullable\\": false}},\\n      \\"rows\\": [{\\"n\\": 7}, {\\"n\\": 11}]\\n    }, \\"as\\": \\"selected\\"}],\\n    \\"results\\": {\\"rows\\": {\\"from\\": \\"selected\\", \\"fields\\": [\\"n\\"]}}\\n  }, {\\n    \\"id\\": \\"projected\\",\\n    \\"inputs\\": {\\"incoming\\": {\\"result\\": {\\"stage\\": \\"numbers\\", \\"result\\": \\"rows\\"}}},\\n    \\"steps\\": [{\\"from\\": \\"incoming\\", \\"select\\": [\\"n\\"], \\"as\\": \\"selected\\"}],\\n    \\"results\\": {\\"rows\\": {\\"from\\": \\"selected\\", \\"fields\\": [\\"n\\"]}}\\n  }],\\n  \\"results\\": {\\n    \\"first\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"second\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"third\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"fourth\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"fifth\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}},\\n    \\"sixth\\": {\\"from\\": {\\"stage\\": \\"projected\\", \\"result\\": \\"rows\\"}}\\n  }\\n}\\n";
const five = JSON.parse(fiveText), six = JSON.parse(sixText);
const fiveNames = ['first', 'second', 'third', 'fourth', 'fifth'];
const sixNames = ['first', 'second', 'third', 'fourth', 'fifth', 'sixth'];
assert.deepEqual(Object.keys(five.results), fiveNames);
assert.deepEqual(Object.keys(six.results), sixNames);
const hash = text => createHash('sha256').update(text).digest('hex');
const programHashes = {five: hash(fiveText), six: hash(sixText)};
const packageEntrances = {kind: 'registered source Host control; packed proof is separate'};
const count = (records, operation, event) => records.filter(record =>
  record.operation === operation && record.event === event).length;
const lifecycle = records => Object.fromEntries(['definition_admitted',
  'dispatch_reserved', 'physical_start_reserved', 'dispatch_failed']
  .map(event => [event, count(records, 'run', event)]));

async function withPublicHost(name, body) {
  const root = join(directory, name);
  const records = [], facts = [];
  const observation = createHostObservationConnection({
    include: ['check', 'run', 'compute', 'publication', 'cleanup'],
    deliver: record => { records.push(record); },
  });
  const client = await connect({mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: root, observation}});
  const flush = async () => {
    for (let i = 0; i < observationLimits.queueRecords * 2; i++) {
      const status = observation.status();
      if (status.queued === 0 && status.active === 0 && status.activeSegments === 0) break;
      await new Promise(resolve => setImmediate(resolve));
    }
    const status = observation.status();
    for (const key of ['queued', 'active', 'activeSegments', 'dropped',
      'budgetUnavailable', 'deliveryFailed', 'queueOverflow', 'limited']) {
      assert.equal(status[key], 0, \`complete public observation: \${key}\`);
    }
    assert.deepEqual(status.loss, {});
  };
  let result, primary, cleanupFailure;
  try { result = await body({client, root, records, facts, flush}); }
  catch (error) { primary = error; }
  try { await client.close(); }
  catch (error) { cleanupFailure = error; primary ??= error; }
  const observationStatus = observation.status();
  await writeFile(join(directory, \`\${phase}-\${name}-observations.json\`),
    JSON.stringify({label: 'public Local byte-capacity diagnostic', phase,
      programHashes, packageEntrances, facts, records, observationStatus,
      failure: primary && {name: primary.name, code: primary.code, message: primary.message},
      cleanupFailure: cleanupFailure && {name: cleanupFailure.name,
        code: cleanupFailure.code, message: cleanupFailure.message}}, null, 2) + '\\n', {flag: 'wx'});
  if (primary !== undefined) throw primary;
  assert.equal(observationStatus.closed, true);
  assert.equal(observationStatus.cleanupPending, false);
  for (const key of ['queued', 'active', 'dropped', 'deliveryFailed', 'budgetUnavailable']) {
    assert.equal(observationStatus[key], 0, \`closed observation: \${key}\`);
  }
  return result;
}

function assertFailed(state, runId) {
  assert.equal(state.status, 'failed');
  if (runId !== undefined) assert.equal(state.run_id, runId);
  assert.deepEqual(state.terminal_error,
    {code: 'ACTQL_E_UNPUBLISHED_RUN', message: 'Run ended before publication'});
  assert.deepEqual(state.next_action, {kind: 'none'});
  assert.equal(state.control.physical_stop, 'confirmed');
  assert.equal(state.control.cancellation_requested, false);
  assert.equal(state.result_available, false);
  assert.deepEqual(Object.keys(state.result_availability).sort(), [...sixNames].sort());
  for (const result of Object.values(state.result_availability)) {
    assert.equal(result.state, 'unavailable');
    assert.equal(result.reason, 'not_published');
  }
}

async function assertOriginalFailure({client, root, records, facts, flush}, original) {
  const before = lifecycle(records);
  const attached = await client.attach(original.ref);
  const state = await attached.status();
  facts.push({kind: 'attached', ref: attached.ref, state});
  assertFailed(state, original.runId);
  assert.equal(state.control.revision, original.controlRevision);
  const replayed = await client.start(six, {parameters: null, submissionRef: original.submissionRef});
  assert.deepEqual(replayed.ref, original.ref);
  const replayedState = await replayed.status();
  facts.push({kind: 'replayed', ref: replayed.ref, state: replayedState});
  assertFailed(replayedState, original.runId);
  assert.equal(replayedState.control.revision, original.controlRevision);
  const lookup = await client.lookupSubmission(original.submissionRef);
  facts.push({kind: 'original-submission-lookup', lookup});
  assert.equal(lookup.kind, 'ready');
  assert.deepEqual(lookup.submissionRef, original.submissionRef);
  assert.deepEqual(lookup.admission.ref, original.ref);
  await assert.rejects(attached.result('sixth').all(), {code: 'ResultAccessDenied'});
  await flush();
  assert.deepEqual(lifecycle(records), before,
    'attach/original replay/lookup add no Run, physical-start or failure attempt');
  assert.equal(count(records, 'compute', 'task_started'), 0);
  assert.equal(count(records, 'compute', 'task_completed'), 0);
  assert.equal(count(records, 'publication', 'result_committed'), 0);
  assert.deepEqual(await readdir(join(root, 'publication', 'objects')), [],
    'byte-capacity refusal publishes no Store object');
}

if (phase === 'initial') {
  const positive = await withPublicHost('five-results', async ({client, records, facts, flush}) => {
    const check = await client.check(five, {kind: 'program', scope: 'bound_input', parameters: null});
    facts.push({kind: 'authored-program-check', check});
    assert.equal(check.report.verdict, 'verified');
    await flush();
    assert.equal(count(records, 'run', 'definition_admitted'), 0);
    const execution = await client.start(five, {parameters: null,
      submissionRef: client.newSubmission({nonce: 'five-result-positive'})});
    const state = await execution.wait({signal: AbortSignal.timeout(60000)});
    facts.push({kind: 'initial', ref: execution.ref, state});
    assert.equal(state.status, 'succeeded');
    for (const name of fiveNames) {
      const rows = await execution.result(name).all();
      const description = await execution.result(name).describe();
      facts.push({kind: 'positive-result', name, rows, description});
      assert.deepEqual(rows, [{n: 7}, {n: 11}]);
      assert.deepEqual(description.columns,
        [{name: 'n', contract: {type: 'number', nullable: false}}]);
    }
    await flush();
    assert.ok(count(records, 'compute', 'task_started') > 0,
      'the positive witness proves the selected Compute observer is connected');
    return {ref: execution.ref, computeStarts: count(records, 'compute', 'task_started')};
  });
  const original = await withPublicHost('six-results', async context => {
    const {client, root, records, facts, flush} = context;
    assert.deepEqual(await readdir(join(root, 'publication', 'objects')), []);
    const check = await client.check(six, {kind: 'program', scope: 'bound_input', parameters: null});
    facts.push({kind: 'authored-program-check', check});
    assert.equal(check.report.verdict, 'verified', 'the authored six-Result Program is valid');
    await flush();
    assert.deepEqual(lifecycle(records), {definition_admitted: 0, dispatch_reserved: 0,
      physical_start_reserved: 0, dispatch_failed: 0});
    const submissionRef = client.newSubmission({nonce: 'six-result-byte-capacity-refusal'});
    const execution = await client.start(six, {parameters: null, submissionRef});
    const state = await execution.wait({signal: AbortSignal.timeout(60000)});
    facts.push({kind: 'initial', ref: execution.ref, submissionRef, state});
    assertFailed(state);
    await flush();
    assert.deepEqual(lifecycle(records), {definition_admitted: 1, dispatch_reserved: 1,
      physical_start_reserved: 1, dispatch_failed: 1});
    const original = {ref: execution.ref, submissionRef, runId: state.run_id,
      controlRevision: state.control.revision};
    await assertOriginalFailure(context, original);
    return original;
  });
  await writeFile(join(directory, 'original.json'), JSON.stringify({
    label: 'genuine-policy byte-capacity refusal; not object-limit reproduction',
    programHashes, positive, original}, null, 2) + '\\n', {flag: 'wx'});
} else {
  const saved = JSON.parse(await readFile(join(directory, 'original.json'), 'utf8'));
  assert.deepEqual(saved.programHashes, programHashes);
  await withPublicHost('six-results', async context => {
    await context.flush();
    assert.deepEqual(lifecycle(context.records), {definition_admitted: 0, dispatch_reserved: 0,
      physical_start_reserved: 0, dispatch_failed: 0});
    await assertOriginalFailure(context, saved.original);
  });
}
console.log(JSON.stringify({label: 'public Local byte-capacity diagnostic', phase,
  status: 'passed', directory, programHashes}));
`;
    for (const phase of ['initial', 'restored']) {
      const log = execFileSync(process.execPath, ['--input-type=module', '-e', child,
        phase, join(directory, 'evidence')], {timeout: 20000, encoding: 'utf8',
        stdio: 'pipe', maxBuffer: 1024 * 1024});
      const report = JSON.parse(log.trim().split('\n').at(-1));
      assert.equal(report.phase, phase);
      assert.equal(report.status, 'passed');
    }
    passed = true;
  });
