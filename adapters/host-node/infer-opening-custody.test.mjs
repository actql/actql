// Adapter fault injection uses explicit Core/Store ports. The real dispatch
// supervisor must retain the actual returned Infer owner, not replay opening.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as cancellationMoon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {installNodeInferRun} from './installed-infer-run.mjs';

for (const [boundary, immediateCleanup] of [
  ...['call-entry', 'send-mask', 'quantity', 'suffix', 'preflight', 'egress'].map(name => [name, false]),
  ['quantity', true],
]) {
  test(`installed INFER transfers the original input owner before failed ${boundary} binding${immediateCleanup ? ' with immediate cleanup' : ''}`, async () => {
    const cause = {boundary, refusal: 'FixtureAdmissionRefused'};
    const active = {}, preparedProgram = {}, graph = {};
    const ref = {runDefinitionCid: 'opening-definition'};
    const plan = {kind: 'infer', inferGraph: graph, runDefinition: {wire: '{"run_id":"opening-run"}'}};
    const token = {available: true, snapshot: {binding: 'binding', rows: [],
      descriptorWire: 'descriptor', callScopeSnapshotWire: '{"sources":[]}'}};
    const record = {inventory: {taskIndex: 0}};
    let started = 0, stopConfirmed = immediateCleanup, cleanupAllowed = immediateCleanup, reclaimed = false;
    let releases = 0, bindings = 0;
    const stopped = [];
    const bind = name => {
      bindings++;
      return name === boundary ? {$tag: 0, _0: cause} : {$tag: 1, _0: undefined};
    };
    const moon = {
      clientProgramInferPlanBoundary: () => ({_0: 0}),
      clientProgramStartRestoredInferInput() { started++; return {$tag: 1, _0: active}; },
      clientProgramRequireInferCallEntry: () => bind('call-entry'),
      clientProgramRestrictInferSendSlots: () => bind('send-mask'),
      clientProgramBindInferQuantityCapacity: () => bind('quantity'),
      clientProgramBindInferComputeSuffix: () => bind('suffix'),
      clientProgramBindInferPhysicalPreflight: () => bind('preflight'),
      clientProgramBindInferEgress: () => bind('egress'),
      clientProgramCancelInferExecution(value) { assert.equal(value, active); },
      clientProgramAdvanceInferExecution(value) {
        assert.equal(value, active);
        return {$tag: 1, _0: stopConfirmed ? 'stopped' : 'waiting'};
      },
      clientProgramInferExecutionPollKind: value => value,
      clientProgramInferExecutionStopped: () => stopConfirmed,
      clientProgramCleanupInferExecution(value) {
        assert.equal(value, active);
        reclaimed = cleanupAllowed;
        return {$tag: 1, _0: reclaimed};
      },
    };
    const control = {runDefinitionRunId: () => 'opening-run',
      runCancellationConfirmed: runtimeCore(cancellationMoon).publicationControl.runCancellationConfirmed};
    const modelController = {discover: () => [record], prime: async () => token,
      state: () => ({slots: []}), savedScope: () => ({}),
      release(actual) {
        assert.equal(actual, token);
        assert.equal(reclaimed, true, 'cannot evict before actual Core cleanup');
        if (token.available) { token.available = false; releases++; }
      },
      open() { assert.fail('binding refusal cannot authorize Model dispatch'); },
    };
    const selected = {graph, step: 0, provider() { assert.fail('provider must not run'); },
      computeSuffix: {}, physicalPreflight() { assert.fail('preflight must not execute'); },
      egressAdmission: {}, quantityCapacity: {
        limits: {tokens: 1n, costUnits: 0n, durationMs: 1n},
        perAttempt: {tokens: 1n, costUnits: 0n, durationMs: 1n}}};
    const runInfer = installNodeInferRun({moon, core: {publicationControl: control},
      selections: new Map([[preparedProgram, selected]]), modelController});
    const owner = installNodeClientDispatchOwner({moon, control,
      journal: {reservePhysicalStart: () => true,
        lookupRunDefinition: () => ({cancellationRequested: false, revision: 1,
          runDefinition: plan.runDefinition}), lookupReconciliationState: () => undefined,
        markPhysicalClose: (...args) => stopped.push(args),
        markPreDispatchFailure() { assert.fail('an input owner already exists'); }},
      store: {confirmCommittedIndex: async () => undefined},
      startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
      planFor: () => plan, runInfer, namespaceId: 'opening-namespace'});
    await owner.start({preparedProgram, principalId: 'owner', connection: {}, requestId: 'opening-request'},
      {}, {ref, runDefinition: plan.runDefinition, dispatchReserved: false, cancellationRequested: false}, {});
    await owner.operation(ref);
    if (immediateCleanup) {
      await owner.drain();
      assert.equal(started, 1);
      assert.equal(releases, 1);
      assert.deepEqual(stopped, [[ref, 'failed']]);
      return;
    }
    const assertPending = error => {
      assert.equal(error.code, 'ClientDispatchCleanupPending');
      assert.equal(error.failures[0].primary.code, 'MoonBitHostFailure');
      assert.equal(error.failures[0].primary.cause, cause);
      return true;
    };
    await assert.rejects(owner.drain(), assertPending);
    const originalBindings = bindings;
    assert.equal(token.available, true);
    assert.deepEqual(stopped, []);
    stopConfirmed = true;
    await assert.rejects(owner.drain(), assertPending);
    assert.equal(releases, 0, 'physical stop alone does not release retained input');
    cleanupAllowed = true;
    await owner.drain();
    assert.equal(releases, 1);
    assert.equal(started, 1);
    assert.equal(bindings, originalBindings, 'cleanup cannot replay a rejected binding');
    assert.deepEqual(stopped, [[ref, 'failed']]);
  });
}
