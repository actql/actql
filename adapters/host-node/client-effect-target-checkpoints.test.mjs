// Real Checkpoint gate/journal, encrypted continuation custody and SDK answers.
// Provider composition and packed Local/HTTPS acceptance are separate cases.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {effectTargetReadContinuation} from './effect-target-read-continuation.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {createInstalledEffectSite} from './installed-effect-site.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const reviewer = generateKeyPairSync('ed25519');
const host = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const configuration = canonicalJson({version: 'actql-execution-account-config/0.1',
  account_id: 'target-account', entries: [{entry_id: 'target-read', outcome: 'delegate',
    principal: {all: true}, connection: {any_of: ['crm']}, resource: {all: true},
    operation: {any_of: ['read']}, exclusions: []}]});
const inventory = ['Account', 'Contact'].map((resource, index) => ({
  readTuple: {connection: 'crm', resource, operation: 'read'},
  physicalBinding: {version: 'fixture-target/0.1', resource, mapping: cid(String(index + 1))},
}));
async function fixture(t, decisionOptions = {}) {
  const scratch = new URL('../../_build/client-effect-target-checkpoints/', import.meta.url);
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch.pathname, 'host-'));
  const opened = new Set();
  let clock = Date.parse('2026-10-04T00:00:00.000Z');
  const open = async (overrides = {}) => {
    const checkpoints = await installRemoteCheckpoints({root, namespaceId: 'local',
      authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
      realizationKey: 'source-free-values', environmentCid: cid('4'),
      effectTarget: {accountConfiguration: configuration,
        context: {principal: 'owner', contextCid: cid('5')}},
      contractControl: runtimeCore(moon).publicationControl, now: () => clock,
      authorization: {accountConfiguration: configuration, resumeAfterAnswer: false,
        ...decisionOptions,
        reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
          principalId: 'reviewer', publicKey: pem(reviewer.publicKey)}],
        reviewReaders: ['reviewer'], hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}},
      ...overrides});
    opened.add(checkpoints); return checkpoints;
  };
  const close = async checkpoints => { await checkpoints.close(); opened.delete(checkpoints); };
  t.after(async () => { for (const checkpoints of opened) await close(checkpoints);
    await rm(root, {recursive: true, force: true}); });
  const answer = async (checkpoints, id, decision = 'approved') => {
    const summary = (await checkpoints.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 20})).items.find(item => item.checkpointId === id);
    assert.equal(summary.kind, 'read_access');
    assert.equal(summary.requiredArtifact.type, 'read_scope');
    const item = await signedAnswer(summary, decision, {
      keyId: 'reviewer-key', reviewerId: 'reviewer', authorityScopeCid: cid('3'),
      sign: bytes => sign(null, bytes, reviewer.privateKey)}, new Date(clock).toISOString());
    const response = await checkpoints.resolve({principalId: 'reviewer', items: [item]});
    assert.equal(response.results[0].status, 'committed', JSON.stringify(response));
    const duplicate = await checkpoints.resolve({principalId: 'reviewer', items: [item]});
    assert.equal(duplicate.results[0].status, 'duplicate');
    return checkpoints.journal.inspect(summary.checkpointCid);
  };
  const owner = (checkpoints, resume, overrides = {}) => effectTargetReadContinuation({checkpoints,
    runId: 'target-run', runDefinitionCid: cid('6'), unitId: 'effect',
    declaredResults: ['answer'], principalId: 'owner',
    submission: {requestId: 'target-request', input: {format: 'json', text: '{}'}},
    inventory, resume, ...overrides});
  const claim = async (checkpoints, view) => {
    const claimed = checkpoints.journal.claimResume('target-run', {
      claimant: 'target-host', leaseMs: 60_000, binding: checkpoints.binding,
      preserveStarted: true, expectedCheckpointCid: view.checkpointCid});
    assert.equal(claimed.action, 'claimed', JSON.stringify(claimed));
    return {view, claim: claimed.claim,
      continuation: await checkpoints.effectTargetContinuation(view),
      assertCurrent: () => checkpoints.journal.admitResume(claimed.claim,
        {checkpointCid: view.checkpointCid})};
  };
  return {open, close, owner, answer, claim, advance(ms) { clock += ms; }};
}

test('two target approvals survive service restart and answer-response retry on the same Run', async t => {
  const f = await fixture(t);
  let checkpoints = await f.open();
  let owner = await f.owner(checkpoints);
  assert.equal((await owner.prepare()).status, 'waiting_checkpoint');
  assert.equal(checkpoints.effectRunState('target-run', cid('6')).status, 'waiting_checkpoint');
  assert.equal(checkpoints.journal.listRunCheckpoints().length, 1);
  owner.close(); await f.close(checkpoints);
  checkpoints = await f.open();
  const first = await f.answer(checkpoints, 'target-run-target-0');
  owner = await f.owner(checkpoints, await f.claim(checkpoints, first));
  assert.equal((await owner.prepare()).status, 'waiting_checkpoint');
  assert.equal(checkpoints.journal.currentResume(first.checkpointCid).state, 'completed');
  assert.equal(checkpoints.journal.hasStartedResume(first.checkpointCid), false);
  assert.equal(checkpoints.journal.listRunCheckpoints().length, 2);
  owner.close(); await f.close(checkpoints);
  checkpoints = await f.open();
  const second = await f.answer(checkpoints, 'target-run-target-1');
  owner = await f.owner(checkpoints, await f.claim(checkpoints, second));
  let ready;
  try { ready = await owner.prepare(); }
  catch (error) { t.diagnostic(JSON.stringify(error.authorization)); throw error; }
  assert.deepEqual(ready, {status: 'ready'});
  owner.enterComputation();
  assert.equal(checkpoints.journal.hasStartedResume(second.checkpointCid), true);
  const left = checkpointApprovalFacts(await owner.authorize(inventory[0].readTuple));
  const right = checkpointApprovalFacts(await owner.authorize(inventory[1].readTuple));
  assert.equal(left.checkpointCid, first.checkpointCid);
  assert.equal(right.checkpointCid, second.checkpointCid);
  assert.notEqual(left.checkpointCid, right.checkpointCid);
  left.assertCurrent(); right.assertCurrent();
  owner.close();
});

const effectProfile = (name, digit, outcome = 'delegate') => ({
  selectors: [{kind: 'update', target: `connector://crm/${name}`,
    mappingRef: `mapping:${name}`, mappingCid: cid(digit)}],
  authorization: {accountConfiguration: canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: name,
    entries: [{entry_id: 'read', outcome, principal: {all: true},
      connection: {any_of: ['crm']}, resource: {all: true},
      operation: {any_of: ['read']}, exclusions: []}]}),
  context: {principal: 'owner', contextCid: cid(digit)}},
});
const profileOptions = profile => ({effectTargetAuthority: profile.authorization,
  inventory: [{readTuple: inventory[0].readTuple, physicalBinding: {
    version: 'fixture-target/0.1', mapping: profile.selectors[0].mappingCid,
    resource: profile.selectors[0].target}}]});
const pluralOptions = profiles => ({effectTarget: undefined, effectTargets: profiles});

test('plural target authority routes allow, deny and delegate without probing an unused profile', async t => {
  const decisions = [];
  const f = await fixture(t, {decide(view) {
    decisions.push(view.subject);
    return {decision: 'permit', subject: view.subject, authority: 'reviewer'};
  }});
  const allow = effectProfile('allow-account', 'a', 'allow');
  const deny = effectProfile('deny-account', 'b', 'deny');
  const delegate = effectProfile('delegate-account', 'c');
  const unused = effectProfile('unused-account', 'd');
  const checkpoints = await f.open(pluralOptions([unused, deny, delegate, allow]));
  for (const profile of [allow, deny, delegate]) {
    const owner = await f.owner(checkpoints, undefined, {runId: profile.selectors[0].mappingRef,
      ...profileOptions(profile)});
    try {
      if (profile === deny) {
        await assert.rejects(owner.prepare(), {code: 'ExecutionAuthorizationDenied'});
      } else {
        assert.deepEqual(await owner.prepare(), {status: 'ready'});
        const facts = checkpointApprovalFacts(await owner.authorize(inventory[0].readTuple));
        assert.equal(facts.contextCid, profile.authorization.context.contextCid);
        assert.deepEqual(facts.physicalBindings, profileOptions(profile).inventory
          .map(item => item.physicalBinding));
        await assert.rejects(owner.authorize(inventory[1].readTuple),
          {code: 'EffectTargetBindingChanged'});
      }
    } finally { owner.close(); }
  }
  assert.deepEqual(decisions.map(subject => subject.account_id), ['delegate-account']);
  assert.equal(checkpoints.journal.listRunCheckpoints().length, 0);
});

test('plural target authority refuses missing, unknown and cloned tokens before any decision', async t => {
  let decisions = 0;
  const f = await fixture(t, {decide() { decisions++; assert.fail('No authority was selected'); }});
  const selected = effectProfile('selected', 'a');
  const other = effectProfile('other', 'b');
  const checkpoints = await f.open(pluralOptions([selected, other]));
  for (const authority of [undefined, {}, structuredClone(selected.authorization)]) {
    await assert.rejects(f.owner(checkpoints, undefined, {
      ...profileOptions(selected), effectTargetAuthority: authority}),
    {code: 'InvalidEffectTargetContinuation'});
  }
  assert.equal(decisions, 0);
  assert.equal(checkpoints.journal.listRunCheckpoints().length, 0);
});

test('plural target approval resumes after inventory reordering with one exact selected account', async t => {
  const f = await fixture(t);
  let selected = effectProfile('selected', 'a');
  let unused = effectProfile('unused', 'b', 'deny');
  let checkpoints = await f.open(pluralOptions([unused, selected]));
  const binding = checkpoints.binding.authorizationContextCid;
  let owner = await f.owner(checkpoints, undefined, profileOptions(selected));
  const waiting = await owner.prepare();
  assert.equal(waiting.status, 'waiting_checkpoint');
  const review = await checkpoints.reviewCheckpoint({principalId: 'reviewer',
    checkpointCid: waiting.checkpoint.checkpointCid, maxBytes: 256 * 1024});
  assert.equal(JSON.parse(Buffer.from(review.contentBase64, 'base64')).context_cid,
    selected.authorization.context.contextCid);
  owner.close(); await f.close(checkpoints);
  selected = effectProfile('selected', 'a');
  unused = effectProfile('unused', 'b', 'deny');
  checkpoints = await f.open(pluralOptions([selected, unused]));
  assert.equal(checkpoints.binding.authorizationContextCid, binding);
  const approved = await f.answer(checkpoints, 'target-run-target-0');
  owner = await f.owner(checkpoints, await f.claim(checkpoints, approved), profileOptions(selected));
  assert.deepEqual(await owner.prepare(), {status: 'ready'});
  const facts = checkpointApprovalFacts(await owner.authorize(inventory[0].readTuple));
  assert.equal(facts.contextCid, selected.authorization.context.contextCid);
  assert.equal(facts.checkpointCid, approved.checkpointCid);
  assert.equal(checkpoints.journal.listRunCheckpoints().length, 1);
  owner.enterComputation();
  assert.equal(checkpoints.journal.hasStartedResume(approved.checkpointCid), true);
  owner.close();
});

for (const changed of ['account', 'context', 'mapping']) {
  test(`changed plural target ${changed} invalidates a held resume before entry`, async t => {
    const f = await fixture(t);
    const selected = effectProfile('selected', 'a');
    const unused = effectProfile('unused', 'b', 'allow');
    let checkpoints = await f.open(pluralOptions([selected, unused]));
    const owner = await f.owner(checkpoints, undefined, profileOptions(selected));
    assert.equal((await owner.prepare()).status, 'waiting_checkpoint');
    owner.close();
    const approved = await f.answer(checkpoints, 'target-run-target-0');
    await f.close(checkpoints);
    const replacement = effectProfile('selected', 'a');
    if (changed === 'account') replacement.authorization.accountConfiguration =
      effectProfile('replacement-account', 'a').authorization.accountConfiguration;
    else if (changed === 'context') replacement.authorization.context.contextCid = cid('c');
    else replacement.selectors[0].mappingCid = cid('c');
    checkpoints = await f.open(pluralOptions([unused, replacement]));
    const claimed = checkpoints.journal.claimResume('target-run', {
      claimant: 'target-host', leaseMs: 60_000, binding: checkpoints.binding,
      preserveStarted: true, expectedCheckpointCid: approved.checkpointCid});
    assert.equal(claimed.action, 'invalidated');
    assert.equal(claimed.terminalErrorCode, 'ACTQL_E_RESUME_REVALIDATION_FAILED');
    assert.equal(checkpoints.journal.hasStartedResume(approved.checkpointCid), false);
  });
}

test('changed plural physical target binding refuses retained continuation before entry', async t => {
  const f = await fixture(t);
  const selected = effectProfile('selected', 'a');
  const checkpoints = await f.open(pluralOptions([selected, effectProfile('unused', 'b')]));
  const owner = await f.owner(checkpoints, undefined, profileOptions(selected));
  await owner.prepare(); owner.close();
  const approved = await f.answer(checkpoints, 'target-run-target-0');
  const resume = await f.claim(checkpoints, approved);
  const changed = profileOptions(selected);
  changed.inventory[0].physicalBinding.resource = 'replacement';
  await assert.rejects(f.owner(checkpoints, resume, changed), {code: 'EffectTargetBindingChanged'});
  assert.equal(checkpoints.journal.hasStartedResume(approved.checkpointCid), false);
});

test('plural target configuration and context are captured before the first installation await', async t => {
  const f = await fixture(t);
  const selected = effectProfile('selected', 'a', 'allow');
  const original = profileOptions(selected);
  const installation = f.open(pluralOptions([selected, effectProfile('unused', 'b')]));
  selected.authorization.accountConfiguration =
    effectProfile('replacement-account', 'c', 'deny').authorization.accountConfiguration;
  selected.authorization.context.contextCid = cid('c');
  selected.selectors[0].mappingCid = cid('d');
  const checkpoints = await installation;
  const owner = await f.owner(checkpoints, undefined, original);
  assert.deepEqual(await owner.prepare(), {status: 'ready'});
  const facts = checkpointApprovalFacts(await owner.authorize(inventory[0].readTuple));
  assert.equal(facts.contextCid, cid('a'));
  owner.close();
});

test('closing the Checkpoint owner closes every plural current authority and target scope', async t => {
  let decisions = 0;
  const f = await fixture(t, {decide() { decisions++; assert.fail('No decision after close'); }});
  const profiles = [effectProfile('first', 'a'), effectProfile('second', 'b'),
    effectProfile('third', 'c')];
  const checkpoints = await f.open(pluralOptions(profiles));
  const gates = [];
  for (const profile of profiles) gates.push(await checkpoints.effectTargetAuthorization({
    runId: 'target-run', runDefinitionCid: cid('6'), unitId: 'effect',
    inventoryCid: cid('7'), declaredResults: ['answer'],
    target: {index: 0, readTuple: inventory[0].readTuple,
      physicalBindings: [profileOptions(profile).inventory[0].physicalBinding]},
    effectTargetAuthority: profile.authorization, continuation: () => '{}',
    beforeDefer() { assert.fail('No deferral after close'); }}));
  await f.close(checkpoints);
  for (const gate of gates) {
    await assert.rejects(gate.current(), {code: 'AuthorizationDecisionScopeClosed'});
    await assert.rejects(gate.authorize(), {code: 'AuthorizationDecisionScopeClosed'});
    assert.equal(gate.cleanupPending(), false);
    assert.equal(gate.close(), true);
  }
  assert.equal(decisions, 0);
});

test('plural target installation rejects ambiguous and unbound Mapping ownership', async t => {
  const f = await fixture(t);
  const first = effectProfile('first', 'a');
  const second = effectProfile('second', 'b');
  for (const profiles of [[null], [{...first, selectors: []}],
    [first, {...second, authorization: first.authorization}],
    [first, {...second, selectors: first.selectors}],
    [first, {...second, selectors: [{...second.selectors[0], mappingCid: cid('a')}]}],
    [first, {...second, selectors: [{...second.selectors[0], mappingRef: 'mapping:first'}]}]]) {
    await assert.rejects(f.open(pluralOptions(profiles)), {code: 'InvalidRemoteHostEffectTargets'});
  }
  await assert.rejects(f.open({effectTargets: [first, second]}),
    {code: 'InvalidRemoteHostEffectTargets'});
});

test('an empty plural target-read inventory admits a Host without granting target access', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open(pluralOptions([]));
  await assert.rejects(f.owner(checkpoints), {code: 'InvalidEffectTargetContinuation'});
  assert.equal(checkpoints.journal.listRunCheckpoints().length, 0);
});

test('plural target authority count follows the common Mapping bound rather than Source or Set bounds', async t => {
  const f = await fixture(t);
  const profiles = Array.from({length: 257}, (_, index) => {
    const profile = effectProfile(`profile-${index}`, 'a', 'allow');
    profile.selectors[0].mappingCid = `sha256:${index.toString(16).padStart(64, '0')}`;
    return profile;
  });
  const checkpoints = await f.open(pluralOptions(profiles.slice(0, 129)));
  const selected = profiles[128];
  const owner = await f.owner(checkpoints, undefined, profileOptions(selected));
  assert.deepEqual(await owner.prepare(), {status: 'ready'});
  owner.close(); await f.close(checkpoints);
  await assert.rejects(f.open(pluralOptions(profiles)), {code: 'InvalidRemoteHostEffectTargets'});
});

test('multiple kinds and effect IDs for one owned Mapping retain one stable authority binding', async t => {
  const f = await fixture(t);
  const first = effectProfile('first', 'a');
  const second = effectProfile('second', 'b');
  let checkpoints = await f.open(pluralOptions([first, second]));
  const binding = checkpoints.binding.authorizationContextCid;
  await f.close(checkpoints);
  first.selectors.push({...first.selectors[0], kind: 'upsert'},
    {...first.selectors[0], effectId: 'save'}, {...first.selectors[0], effectId: 'save-again'});
  checkpoints = await f.open(pluralOptions([second, first]));
  assert.equal(checkpoints.binding.authorizationContextCid, binding);
});

test('singular target authorization preserves its original CID preimage', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  const hash = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
  const configurationCid = hash(configuration);
  // Independently ordered legacy envelope; no plural member is present.
  const preimage = JSON.stringify({account_id: 'target-account',
    configuration_cid: configurationCid, effect_target_authorization_binding: {
      configuration_cid: configurationCid, context_cid: cid('5')},
    principal: 'owner', source_configuration_cid: null});
  assert.equal(checkpoints.binding.authorizationContextCid, hash(preimage));
});

test('a rejected target answer never creates a resumable read', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  const owner = await f.owner(checkpoints);
  await owner.prepare(); owner.close();
  const view = await f.answer(checkpoints, 'target-run-target-0', 'rejected');
  assert.equal(checkpoints.journal.getRunState('target-run').status, 'cancelled');
  assert.equal(checkpoints.journal.currentResume(view.checkpointCid), undefined);
  assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), false);
});

test('an expired committed target approval cannot prepare another read or computation', async t => {
  const f = await fixture(t);
  const checkpoints = await f.open();
  const owner = await f.owner(checkpoints);
  await owner.prepare(); owner.close();
  const view = await f.answer(checkpoints, 'target-run-target-0');
  f.advance(24 * 60 * 60 * 1000 + 1);
  assert.equal(checkpoints.journal.committedApprovalAt(view.checkpointCid).current, false);
  await assert.rejects(f.owner(checkpoints), {code: 'ApprovalExpired'});
  assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), false);
});

for (const target of [0, 1]) {
  for (const approved of [false, true]) {
    test(`cancel target ${target} ${approved ? 'after approval before entry' : 'while waiting'} survives restart`, async t => {
      const f = await fixture(t);
      let checkpoints = await f.open();
      let owner = await f.owner(checkpoints);
      await owner.prepare();
      if (target === 1) {
        const first = await f.answer(checkpoints, 'target-run-target-0');
        owner.close();
        owner = await f.owner(checkpoints, await f.claim(checkpoints, first));
        await owner.prepare();
      }
      owner.close();
      let resume;
      if (approved) {
        const view = await f.answer(checkpoints, `target-run-target-${target}`);
        // Deterministic approval-committed/before-physical-entry barrier.
        // Even a claim obtained before cancellation must be fenced.
        resume = await f.claim(checkpoints, view);
        assert.equal(checkpoints.journal.getRunState('target-run').status, 'resuming');
        assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), false);
      }
      assert.equal(checkpoints.cancelEffectContinuation('target-run', cid('7')), false);
      assert.equal(checkpoints.cancelEffectContinuation('target-run', cid('6')), true);
      assert.equal(checkpoints.journal.getRunState('target-run').status, 'cancelled');
      if (resume !== undefined) assert.throws(resume.assertCurrent);
      await f.close(checkpoints);
      checkpoints = await f.open();
      assert.equal(checkpoints.effectRunState('target-run', cid('6')).status, 'cancelled');
      assert.equal(checkpoints.journal.activeRunCheckpoint('target-run'), undefined);
      assert.equal(checkpoints.cancelEffectContinuation('target-run', cid('6')), false);
      const claim = () => checkpoints.journal.claimResume('target-run', {
        claimant: 'restarted-host', leaseMs: 60_000, binding: checkpoints.binding,
        preserveStarted: true});
      if (!approved && target === 0) {
        assert.throws(claim, {code: 'ResumeIntentNotFound'});
      } else {
        assert.notEqual(claim().action, 'claimed');
      }
      for (const view of checkpoints.journal.listRunCheckpoints()) {
        assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), false);
      }
    });
  }
}

test('cancellation preserves an entered target continuation and its unknown observation across restart', async t => {
  const f = await fixture(t);
  let checkpoints = await f.open();
  let owner = await f.owner(checkpoints);
  await owner.prepare();
  const first = await f.answer(checkpoints, 'target-run-target-0');
  owner.close();
  owner = await f.owner(checkpoints, await f.claim(checkpoints, first));
  await owner.prepare();
  const second = await f.answer(checkpoints, 'target-run-target-1');
  owner.close();
  owner = await f.owner(checkpoints, await f.claim(checkpoints, second));
  assert.deepEqual(await owner.prepare(), {status: 'ready'});
  owner.enterComputation();
  assert.equal(checkpoints.cancelEffectContinuation('target-run', cid('6')), false);
  assert.equal(checkpoints.hasUnresolvedEffectTargetStart('target-run', cid('6')), true);
  assert.equal(checkpoints.hasUnresolvedSourceStart('target-run', cid('6')), false);
  owner.close();
  await f.close(checkpoints);
  checkpoints = await f.open();
  assert.equal(checkpoints.journal.getRunState('target-run').status, 'resuming');
  assert.equal(checkpoints.journal.activeRunCheckpoint('target-run').checkpointCid,
    second.checkpointCid);
  assert.equal(checkpoints.hasUnresolvedEffectTargetStart('target-run', cid('6')), true);
  assert.equal(checkpoints.cancelEffectContinuation('target-run', cid('6')), false);
  // Retention has not retired the original unknown continuation.
  assert.equal((await checkpoints.effectTargetContinuation(second)).pending_target, 1);
});


test('durable target approval preserves raw data and exact scope after restart', async t => {
  const f = await fixture(t);
  const text = 'e\u0301\r\nline\rreturn\n' + JSON.stringify({nested: 'e\u0301'});
  const submission = {requestId: 'target-request',
    input: {format: 'json', text: JSON.stringify({document: text})},
    parameters: {text}};
  const physicalBinding = {version: 'fixture-target/0.1', nested: {text}};
  const targets = [{readTuple: inventory[0].readTuple, physicalBinding}];
  let checkpoints = await f.open();
  let owner = await f.owner(checkpoints, undefined, {submission, inventory: targets});
  const waiting = await owner.prepare();
  const view = checkpoints.journal.inspect(waiting.checkpoint.checkpointCid);
  const review = await checkpoints.reviewCheckpoint({principalId: 'reviewer',
    checkpointCid: view.checkpointCid, maxBytes: 256 * 1024});
  const reviewBytes = Buffer.from(review.contentBase64, 'base64');
  assert.equal(review.artifactCid, `sha256:${createHash('sha256').update(reviewBytes).digest('hex')}`);
  const scope = JSON.parse(reviewBytes).scope;
  assert.deepEqual(scope.target.physicalBindings, [physicalBinding]);
  const scopePreimage = JSON.stringify({authority_scope_cid: cid('3'),
    inventory_cid: owner.inventoryCid, principal_id: 'owner',
    run_definition_cid: cid('6'), target: {index: 0,
      physicalBindings: [{nested: {text}, version: 'fixture-target/0.1'}],
      readTuple: {connection: 'crm', operation: 'read', resource: 'Account'}},
    unit_id: 'effect', version: 'actql-effect-target-read-scope/0.1'});
  assert.equal(view.requiredArtifact.cid,
    `sha256:${createHash('sha256').update(scopePreimage).digest('hex')}`);
  owner.close(); await f.close(checkpoints);
  checkpoints = await f.open();
  const saved = await checkpoints.effectTargetContinuation(view);
  assert.deepEqual(saved.submission, submission);
  assert.deepEqual(saved.targets[0].physicalBindings, [physicalBinding]);
  await f.answer(checkpoints, 'target-run-target-0');
  const resume = await f.claim(checkpoints, checkpoints.journal.inspect(view.checkpointCid));
  for (const change of ['submission', 'binding']) {
    const other = structuredClone({submission, inventory: targets});
    if (change === 'submission') other.submission.parameters.text = text.normalize('NFC');
    else other.inventory[0].physicalBinding.nested.text = text.normalize('NFC');
    await assert.rejects(f.owner(checkpoints, resume, other), {code: 'EffectTargetBindingChanged'});
    assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), false);
  }
  owner = await f.owner(checkpoints, resume, {submission, inventory: targets});
  assert.deepEqual(await owner.prepare(), {status: 'ready'});
  const approved = checkpointApprovalFacts(await owner.authorize(targets[0].readTuple));
  assert.deepEqual(approved.physicalBindings, [physicalBinding]);
  assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), false);
  owner.enterComputation();
  assert.equal(checkpoints.journal.hasStartedResume(view.checkpointCid), true);
  owner.close();
});


for (const variant of ['exact', 'legacy-ascii', 'legacy-nfc', 'legacy-decomposed',
  'exact-keys', 'legacy-keys']) {
  test(`separate-process target custody: ${variant}`, async t => {
    const scratch = new URL('../../_build/client-effect-target-checkpoints/', import.meta.url);
    await mkdir(scratch, {recursive: true});
    const root = await mkdtemp(join(scratch.pathname, 'process-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const fixture = new URL('./fixtures/effect-target-value-process.mjs', import.meta.url);
    const run = phase => JSON.parse(execFileSync(process.execPath,
      [fixture.pathname, phase, root, variant], {encoding: 'utf8', timeout: 30_000}));
    const captured = run('capture');
    const resumed = run('resume');
    assert.notEqual(captured.pid, resumed.pid);
    assert.deepEqual(resumed.saved, captured.saved);
    assert.deepEqual(resumed.review, captured.review);
    const original = ['legacy-ascii', 'legacy-keys'].includes(variant) ? 'plain\r\ntext'
      : variant === 'legacy-nfc' ? '\u00e9\r\ntext'
        : 'e\u0301\r\nline\rreturn\n' + JSON.stringify({nested: 'e\u0301'});
    const expected = variant === 'legacy-decomposed' ? original.normalize('NFC') : original;
    assert.equal(captured.saved.submission.parameters.text, expected);
    assert.equal(captured.saved.submission.input.text, JSON.stringify({document: expected}));
    assert.equal(resumed.refused, ['legacy-decomposed', 'legacy-keys'].includes(variant));
    if (variant === 'exact-keys') {
      const exact = {'é': 'composed', 'e\u0301': 'decomposed', '\r\n': 'CRLF', '\n': 'LF'};
      assert.deepEqual(captured.saved.submission.input.literal, exact);
      assert.deepEqual(captured.saved.targets[0].physicalBindings[0].json, exact);
      const review = JSON.parse(Buffer.from(captured.review.contentBase64, 'base64'));
      assert.deepEqual(review.scope.target.physicalBindings[0].json, exact);
    } else if (variant === 'legacy-keys') {
      assert.deepEqual(captured.saved.submission.input.literal, {'é\n': 'stable'});
    }
    assert.equal(resumed.sends, 0);
  });
}

test('pending target decision keeps dispatch custody after timeout and revocation', async t => {
  let settle;
  const pendingDecision = new Promise(resolve => { settle = resolve; });
  let started;
  const decisionStarted = new Promise(resolve => { started = resolve; });
  let decisionSignal;
  const f = await fixture(t, {decisionTimeoutMs: 5,
    decide(_view, {signal}) { decisionSignal = signal; started(); return pendingDecision; }});
  const checkpoints = await f.open();
  const targetReads = await f.owner(checkpoints);
  const site = createInstalledEffectSite({environmentWire: '{}',
    prepareCaptured() { assert.fail('No capture before target approval'); },
    prepareRecovered() { assert.fail('No repeated computation'); }});
  const dispatch = installNodeClientDispatchOwner({});
  const ref = {runDefinitionCid: cid('6')};
  const stopped = [];
  const operation = dispatch.track(ref, {observeStopped: outcome => stopped.push(outcome),
    run: context => site.execute({...context, targetReads,
      openComputation() { assert.fail('No computation before target approval'); }})});
  t.after(async () => { settle({decision: 'deny'}); await new Promise(setImmediate);
    await dispatch.drain(); });
  await decisionStarted;
  await assert.rejects(operation, {code: 'ExecutionAuthorizationDecisionFailed'});
  assert.equal(decisionSignal.aborted, true, 'revocation is immediate');
  assert.deepEqual(stopped, [], 'a timed-out callback still has physical custody');
  assert.notEqual(dispatch.operation(ref), undefined);
  assert.equal(targetReads.cleanupPending(), true);
  await assert.rejects(dispatch.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.deepEqual(stopped, []);
  settle({decision: 'deny'});
  await new Promise(setImmediate);
  await dispatch.drain();
  assert.equal(targetReads.cleanupPending(), false);
  assert.deepEqual(stopped, ['failed']);
  assert.equal(dispatch.operation(ref), undefined);
});
