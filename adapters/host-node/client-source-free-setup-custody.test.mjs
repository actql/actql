import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

function fixture({reserved = true, failCleanup = false, unresolved = false} = {}) {
  const ref = {runDefinitionCid: 'source-free-setup-custody'};
  const setup = {};
  const stops = [];
  let closes = 0, computes = 0, cancellation = false, revision = 1;
  let held, resume;
  const ready = new Promise(resolve => { held = resolve; });
  const barrier = new Promise(resolve => { resume = resolve; });
  let retry = !failCleanup;
  const owner = installNodeClientDispatchOwner({
    moon: {clientProgramOpenSourceFreeLocalHost: () => setup,
      strategyHostStop: value => assert.equal(value, setup),
      strategyHostCloseOutputs(value) {
        assert.equal(value, setup);
        closes++;
        if (!retry) throw new Error('SetupCleanupPending');
      },
      strategyHostUsage: () => Array(13).fill(0n)},
    control: {runDefinitionRunId: () => 'setup-run',
      runCancellationConfirmed: runtimeCore(moon).publicationControl.runCancellationConfirmed},
    journal: {reservePhysicalStart: () => reserved,
      lookupRunDefinition: () => ({cancellationRequested: cancellation,
        revision, runDefinition: {wire: 'definition'}, physicalCloseConfirmed: false}),
      lookupReconciliationState: () => unresolved ? {} : undefined,
      markPhysicalClose: (...args) => stops.push(args),
      markPreDispatchFailure() { assert.fail('Cancellation is not pre-dispatch failure'); }},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    planFor: () => ({kind: 'values'}),
    runPublished() { computes++; assert.fail('The cancelled setup must not enter Compute'); },
    async faultInjection(name) {
      if (name === 'physical_start_reserved') { held(); await barrier; }
    },
    namespaceId: 'setup-namespace',
  });
  const start = gate => owner.start({preparedProgram: {}, principalId: 'owner',
    connection: {}, requestId: 'setup-request'}, {},
  {ref, runDefinition: {wire: 'definition'}, dispatchReserved: false,
    cancellationRequested: false}, {}, undefined, gate);
  return {owner, ref, start, ready, resume, stops,
    closes: () => closes, computes: () => computes,
    retry: () => { retry = true; },
    cancel() { cancellation = true; revision++; owner.cancel(ref); }};
}

test('source-free setup is held across cancellation and failed cleanup until same-owner retry', async () => {
  const f = fixture({failCleanup: true});
  assert.equal(await f.start(), 'started');
  await f.ready;
  f.cancel(); f.resume();
  await f.owner.operation(f.ref);
  assert.deepEqual(f.stops, []);
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  f.retry();
  await f.owner.drain();
  assert.equal(f.computes(), 0);
  assert.deepEqual(f.stops, [[f.ref, 'cancelled']]);
  const closes = f.closes();
  await f.owner.drain();
  assert.equal(f.closes(), closes, 'released setup cannot be closed twice');
});

test('confirmed setup cleanup does not turn unresolved Effect responsibility into cancellation', async () => {
  const f = fixture({unresolved: true});
  await f.start(); await f.ready;
  f.cancel(); f.resume();
  await f.owner.operation(f.ref); await f.owner.drain();
  assert.equal(f.computes(), 0);
  assert.deepEqual(f.stops, [[f.ref, null]]);
});

for (const reason of ['reservation', 'resume-gate']) {
  test(`source-free setup is reclaimed when ${reason} refuses before physical start`, async () => {
    const f = fixture({reserved: reason !== 'reservation'});
    const result = await f.start(reason === 'resume-gate' ? {
      beforePhysicalStart() { throw new Error('ResumeNotCurrent'); },
    } : undefined);
    if (reason === 'reservation') assert.equal(result, 'not_started');
    else assert.equal(result.refused.message, 'ResumeNotCurrent');
    await f.owner.operation(f.ref); await f.owner.drain();
    assert.equal(f.closes(), 1);
    assert.equal(f.computes(), 0);
    assert.deepEqual(f.stops, [], 'no physical-start claim was committed');
  });
}
