// Real Checkpoint authorization owners, including a callback that outlives its
// timeout. The Site composition cases below isolate cleanup from apply setup.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const tuple = {connection: 'reference', resource: 'records'};
const continuation = {runId: 'commit-cleanup', runDefinitionCid: cid('1'),
  unitId: 'effect', declaredResults: ['answer'], reviewWire: '{}',
  continuationWire: '{}', beforeDefer() { assert.fail('No deferred answer'); }};

async function fixture(t, decide) {
  const scratch = new URL('../../_build/effect-authorization-cleanup/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch.pathname, 'host-'));
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  const checkpoints = await installRemoteCheckpoints({root, namespaceId: 'local',
    authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
    realizationKey: 'source-free-values', environmentCid: cid('4'),
    contractControl: runtimeCore(moon).publicationControl,
    authorization: {accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'local',
      entries: [{entry_id: 'records', outcome: 'delegate', principal: {all: true},
        connection: {any_of: ['reference']}, resource: {any_of: ['records']},
        operation: {any_of: ['effect', 'read']}, exclusions: []}]}),
    decide, resumeAfterAnswer: false,
    reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
      principalId: 'reviewer', publicKey: pem(reviewer.publicKey)}],
    reviewReaders: ['reviewer'], hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}}});
  t.after(async () => { await checkpoints.close(); await rm(root, {recursive: true, force: true}); });
  return checkpoints.effectAuthorization(continuation);
}

for (const reason of ['timeout', 'abort']) {
  test(`Effect authorization retains its real commit callback after ${reason}`, async t => {
    let settle, started, decisionSignal, calls = 0;
    const pending = new Promise(resolve => { settle = resolve; });
    const entered = new Promise(resolve => { started = resolve; });
    const gate = await fixture(t, (_view, {signal}) => {
      calls++; decisionSignal = signal; started(); return pending;
    });
    t.after(async () => { settle({decision: 'unavailable'}); await new Promise(setImmediate); gate.close(); });
    const abort = new AbortController();
    if (reason === 'timeout') t.mock.timers.enable({apis: ['setTimeout']});
    const operation = gate.authorize('effect_commit', {...tuple, operation: 'effect'},
      {subjectCid: cid('2'), signal: abort.signal});
    await entered;
    if (reason === 'timeout') t.mock.timers.tick(30_000);
    else abort.abort();
    const decision = await operation;
    assert.equal(decision.action, 'failure');
    assert.equal(decision.reason, reason === 'timeout' ? 'timeout' : 'unavailable');
    assert.equal(decisionSignal.aborted, true);
    assert.equal(gate.close(), false, 'abort is not physical callback completion');
    assert.equal(gate.cleanupPending(), true);
    assert.equal(gate.cleanup(), false);
    await assert.rejects(gate.authorize('effect_commit', {...tuple, operation: 'effect'},
      {subjectCid: cid('2')}), {code: 'AuthorizationDecisionScopeClosed'});
    settle({decision: 'unavailable'});
    await new Promise(setImmediate);
    assert.equal(gate.cleanup(), true);
    assert.equal(gate.cleanupPending(), false);
    assert.equal(gate.close(), true);
    assert.equal(calls, 1, 'cleanup never opens another decision');
  });
}

for (const boundary of ['acquisition', 'effect_commit']) {
  test(`Effect authorization keeps the unfinished ${boundary} scope after its sibling closes`, async t => {
    let settle, started;
    const pending = new Promise(resolve => { settle = resolve; });
    const entered = new Promise(resolve => { started = resolve; });
    const gate = await fixture(t, view => {
      if (view.boundary !== boundary) return {decision: 'permit',
        subject: view.subject, authority: 'reviewer'};
      started(); return pending;
    });
    t.after(async () => { settle({decision: 'unavailable'}); await new Promise(setImmediate); gate.close(); });
    const other = boundary === 'acquisition' ? 'effect_commit' : 'acquisition';
    assert.equal((await gate.authorize(other, {...tuple,
      operation: other === 'acquisition' ? 'read' : 'effect'}, {subjectCid: cid('2')})).action,
    'dispatch');
    const operation = gate.authorize(boundary, {...tuple,
      operation: boundary === 'acquisition' ? 'read' : 'effect'}, {subjectCid: cid('2')});
    await entered;
    assert.equal(gate.close(), false);
    await assert.rejects(operation, {code: 'AuthorizationDecisionScopeClosed'});
    assert.equal(gate.cleanup(), false);
    settle({decision: 'unavailable'});
    await new Promise(setImmediate);
    assert.equal(gate.cleanup(), true);
    assert.equal(gate.cleanupPending(), false);
  });
}

for (const path of ['execute', 'resume']) {
for (const failure of ['none', 'read', 'commit']) {
  test(`installed Effect ${path} retains pending commit custody with ${failure} close failure`, async t => {
    let settle, started, custody, callbacks = 0;
    const pending = new Promise(resolve => { settle = resolve; });
    const entered = new Promise(resolve => { started = resolve; });
    const gate = await fixture(t, () => { callbacks++; started(); return pending; });
    t.after(async () => { settle({decision: 'unavailable'}); await new Promise(setImmediate); gate.close(); });
    // The real callback is already owned by this gate when the Site receives
    // it. Timer advancement only triggers the actual runtime's deadline.
    t.mock.timers.enable({apis: ['setTimeout']});
    const decision = gate.authorize('effect_commit', {...tuple, operation: 'effect'},
      {subjectCid: cid('2')});
    await entered;
    t.mock.timers.tick(30_000);
    assert.equal((await decision).reason, 'timeout');
    const calls = {close: 0, cleanup: 0, read: 0, physical: 0, dispose: 0};
    const retainedGate = {...gate, close() {
      if (++calls.close === 1 && failure === 'commit') throw new Error('CommitCloseUnavailable');
      return gate.close(); },
      cleanup() { calls.cleanup++; return gate.cleanup(); }};
    const targetReads = {prepare: async () => ({status: 'ready'}),
      enterComputation() {}, captureBinding: () => ({}), close() {
        if (++calls.read === 1 && failure === 'read') throw new Error('TargetCloseUnavailable');
      }};
    const physical = {close() {}, cleanup() { calls.physical++; return true; },
      cleanupPending: () => false};
    const store = {};
    const control = {runDefinitionRunId: () => 'commit-cleanup',
      effectComputationPreviewWire: () => '{}',
      effectComputationPreviewSemanticCid: () => cid('2')};
    const preview = {}, computation = {}, storedResults = {};
    const stage = {preview, computation, storedResults,
      apply: {moon, computation, preview}, receipt: {commonMoon: moon},
      publication: {execution: path === 'execute' ? physical : null,
        store, control, storedResults, computation, preview},
      scopes: [tuple], continuationWire: '{}', cleanupOwner: physical,
      dispose() { calls.dispose++; }};
    const site = createInstalledEffectSite({environmentWire: '{}',
      prepareCaptured: () => stage, prepareRecovered: () => stage});
    const ref = {runDefinitionCid: cid('1')};
    const stopped = [];
    const dispatch = installNodeClientDispatchOwner({});
    const operation = dispatch.track(ref, {
      observeStopped: outcome => stopped.push(outcome),
      run: context => site[path]({...context, moon, store, control, ref,
        targetReads: path === 'execute' ? targetReads : undefined,
        prepareTargetReads: path === 'resume' ? async () => targetReads : undefined,
        retained: {runDefinition: {}, resultNames: ['answer']},
        view: {runId: 'commit-cleanup', subject: {kind: 'run_unit', unit_id: 'effect'}},
        continuation: {version: 'actql-installed-effect-continuation/0.1',
          run_definition_cid: cid('1'), unit_id: 'effect', preview_cid: cid('2'),
          target_read_binding: {}, provider: {}},
        retainExecution(value) { custody = value; context.retainExecution(value); },
        openComputation: () => ({execution: physical, checkedHost: {}}),
        recoverCapture: async () => ({computation: {preview, computation, storedResults}}),
        checkpointJournal: {claimResume: () => ({action: 'claimed', claim: {}})},
        effectAuthorization: async () => retainedGate,
      }),
    });
    // These deliberately incomplete apply facts isolate the cleanup handoff.
    // They cannot dispatch, publish or substitute a fabricated runtime owner.
    await assert.rejects(operation, {code: 'InvalidCapturedEffectRunCompletion'});
    assert.deepEqual(stopped, [], 'a timed-out callback cannot be observed as stopped');
    assert.equal(custody.cleanupPending(), true);
    assert.equal(calls.physical, 0, 'reclamation waits for the original callback');
    assert.equal(calls.dispose, 0);
    assert.equal(dispatch.operation(ref), operation);
    await assert.rejects(dispatch.drain(), {code: 'ClientDispatchCleanupPending'});
    assert.deepEqual(stopped, []);
    settle({decision: 'unavailable'});
    await new Promise(setImmediate);
    // Captured and recovered Result custody both survive the callback. This
    // isolated fixture has no real captured owner, so neither path may claim
    // its payload release succeeded. The real Host fixture covers completion.
    await assert.rejects(dispatch.drain(), error =>
      error.code === 'ClientDispatchCleanupPending' &&
      error.failures[0].cleanup.code === 'InvalidCompletedEffectfulRunOwner');
    assert.deepEqual(stopped, []);
    assert.equal(custody.cleanupPending(), true);
    assert.equal(calls.dispose, 0);
    assert.equal(gate.cleanupPending(), false);
    assert.equal(calls.close, 1);
    assert.equal(calls.read, failure === 'read' ? 2 : 1,
      'only an unfinished close-only target gate may be retried');
    assert.equal(calls.physical, 1);
    assert.equal(callbacks, 1);
    const completedCloses = calls.close, completedCleanup = calls.cleanup;
    await custody.close();
    assert.equal(calls.close, completedCloses);
    assert.equal(calls.cleanup, completedCleanup);
  });
}
}
