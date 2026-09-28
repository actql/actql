import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

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
        }, tenantId: 'tenant-a',
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
      tenantId: 'tenant-a',
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
      tenantId: 'tenant-a',
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
    moon: {clientProgramPrepareQueryAcquisition: () => ({$tag: 1})},
    control: {},
    journal: {reservePhysicalStart: () => true,
      markPhysicalClose: (...args) => stopped.push(args)},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    observed: async () => {},
    planFor: () => ({runDefinition: {wire: 'definition'}}),
    sourceProfile: {sourceAccess: access, open},
    runPublished: async () => { computes++; },
    now: () => '2026-09-28T00:00:00.000Z',
    tenantId: 'tenant-a',
  });
  const run = async () => {
    const accepted = {ref, runDefinition: {wire: 'definition'},
      dispatchReserved: false, cancellationRequested: false};
    assert.equal(await owner.start({preparedProgram: {}, principalId: 'owner',
      connection: {}, requestId: 'acquiring-request'}, {}, accepted,
    {preparedSourceAccess: access, preparedSource: {}}), 'started');
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
