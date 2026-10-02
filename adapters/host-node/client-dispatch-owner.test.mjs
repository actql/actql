import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
// Reuse the existing distribution-client gate for bounded two-source owners.
import './two-source-capture-boundaries.test.mjs';
import './two-source-public-host.test.mjs';

function inferDispatchFixture(runInfer) {
  const ref = {runDefinitionCid: 'infer-dispatch-owner'};
  const preparedProgram = {};
  const plan = {kind: 'infer', runDefinition: {wire: 'definition'}};
  const stopped = [];
  let claims = 0, committed = false;
  const owner = installNodeClientDispatchOwner({
    moon: {clientProgramOpenSourceFreeLocalHost() {
      assert.fail('A model barrier must not open the Values fallback');
    }}, control: {},
    journal: {reservePhysicalStart() { claims++; return true; },
      markPhysicalClose: (...args) => stopped.push(args),
      markPreDispatchFailure: () => stopped.push([ref, 'not_started'])},
    store: {confirmCommittedIndex: async () => committed ? {} : undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true, planFor: () => plan,
    runPublished() { assert.fail('INFER must not use Relation dispatch'); },
    runInfer, namespaceId: 'namespace-a',
  });
  const submission = {preparedProgram, principalId: 'owner', connection: {},
    requestId: 'infer-request'};
  const accepted = {ref, runDefinition: plan.runDefinition,
    dispatchReserved: false, cancellationRequested: false};
  return {owner, ref, preparedProgram, plan, stopped,
    claims: () => claims, commit: () => { committed = true; },
    start: () => owner.start(submission, {}, accepted, {})};
}

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
      assert.equal(error.failures[0].primary, failure);
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

test('model dispatch delivers cancellation and retains custody until physical stop',
  async () => {
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
    });
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
  });

test('diagnostic failure cannot stop Compute or bypass required ownership',
  async () => {
    for (const kind of ['throw', 'reject', 'pending']) {
      let starts = 0;
      let closes = 0;
      let retained = 0;
      const stopped = [];
      const ref = {runDefinitionCid: `diagnostic-${kind}`};
      const physical = {async close() { closes++; }, async cleanup() {},
        cleanupPending: () => false};
      const owner = installNodeClientDispatchOwner({
        moon: {clientProgramOpenSourceFreeLocalHost: () => ({})},
        control: {},
        journal: {reservePhysicalStart: () => true,
          markPhysicalClose: (...args) => stopped.push(args)},
        store: {confirmCommittedIndex: async () => ({})},
        startRun: async () => ({kind: 'reserved', ref}),
        hostConnection: () => true,
        observed: () => {
          if (kind === 'throw') throw new Error('SinkFailed');
          if (kind === 'reject') return Promise.reject(new Error('SinkFailed'));
          return new Promise(() => {});
        },
        planFor: () => ({runDefinition: {wire: 'definition'}}),
        runPublished: async (_setup, _publication, _options, _signal,
          _observer, retainExecution) => {
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
      moon: {clientProgramOpenSourceFreeLocalHost: () => ({})},
      control: {},
      journal: {reservePhysicalStart: () => true,
        markPhysicalClose: (...args) => stopped.push(args)},
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
      moon: {clientProgramOpenSourceFreeLocalHost: () => ({})},
      control: {},
      journal: {
        reservePhysicalStart: () => true,
        markPhysicalClose: (...args) => stopped.push(args),
      },
      store: {confirmCommittedIndex: async () => ({})},
      startRun: async () => ({kind: 'reserved', ref}),
      hostConnection: () => true,
      observed: async () => {},
      planFor: () => ({runDefinition: {wire: 'definition'}}),
      runPublished: async () => { starts++; return physical; },
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
        assert.equal(error.failures[0].close, closeFailure);
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
    beforeDispatch: () => cancellationBarrier});
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
    moon: {clientProgramAcquisitionCount: () => 1},
    control: {},
    journal: {reservePhysicalStart: () => true,
      markPhysicalClose: (...args) => stopped.push(args)},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    observed: async () => {},
    planFor: () => ({runDefinition: {wire: 'definition'}}),
    sourceProfile: {sourceAccess: access, admitsSource: source => source === 'fixture-source', open},
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
