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
