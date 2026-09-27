import assert from 'node:assert/strict';
import test from 'node:test';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

test('publication ownership survives a wrapped error and cleanup retry',
  async () => {
    const ref = {runDefinitionCid: 'wrapped-run'};
    let starts = 0;
    let closes = 0;
    let permitCleanup = false;
    const stopped = [];
    const failure = new Error('PublicationFailure');
    const wrapped = new Error('BoundaryFailure', {cause: failure});
    const physical = {
      async close() {
        closes++;
        if (!permitCleanup) throw new Error('CloseFailure');
      },
      async cleanup() {},
      cleanupPending: () => false,
    };
    const owner = installNodeClientDispatchOwner({
      moon: {clientProgramOpenSourceFreeLocalHost: () => ({})},
      control: {},
      journal: {reservePhysicalStart: () => true,
        markPhysicalClose: (...args) => stopped.push(args)},
      store: {confirmCommittedIndex: async () => undefined},
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
    const physical = {
      async close() {
        closes++;
        if (!permitCleanup) throw new Error('PhysicalCloseFailed');
      },
      async cleanup() { cleanups++; },
      cleanupPending: () => false,
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
    await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
    permitCleanup = true;
    await owner.drain();
    assert.equal(starts, 1);
    assert.ok(closes >= 2);
    assert.equal(cleanups, 1);
    assert.deepEqual(stopped, [[ref, null]]);
    assert.equal(owner.operation(ref), undefined);
  });
