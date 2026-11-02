// Actual authorization, encrypted evidence and SQLite Checkpoint Owners.
// The original Client stop projection is an explicit double here; the paired
// MoonBit capture tests exercise its real nominal Run/Preview binding.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, rm, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as checkpoint from '../../_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {authorizationDispatchFacts} from '../host-common/authorization-gate.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalJson, createLocalAuthorizationGate} from './local-account-config.mjs';
import {physicalLocal} from '../connectors/local/test/fixtures/file-store-authorization.mjs';
import {signedAnswer} from '../../packages/sdk/checkpoints.mjs';
import {checkpointEffectReviewDouble} from './fixtures/checkpoint-effect-review.fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const tuple = {connection: 'reference', resource: 'records', operation: 'effect'};
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});

async function fixture(t, {outcome = 'allow', decide, originalRun = false,
  deferAdvanceMs = 0, scope = tuple} = {}) {
  const rootBase = new URL('../../_build/requested-effect-checkpoints/', import.meta.url);
  await mkdir(rootBase, {recursive: true});
  const root = await mkdtemp(join(rootBase.pathname, 'host-'));
  const reviewer = generateKeyPairSync('ed25519');
  const host = generateKeyPairSync('ed25519');
  const original = Object.freeze({});
  const runDefinition = Object.freeze({identity: cid('1')});
  const clock = Date.parse('2026-10-17T00:00:00.000Z');
  let sample = clock;
  const continuationWire = canonicalJson({request: 'original',
    requested_stop: {intent_cid: cid('6')}});
  let retained = 0;
  let current = true;
  const services = new Set();
  const gates = new Set();
  const control = {...runtimeCore(moon).publicationControl,
    runDefinitionLifetime(value, expectedCid) {
      assert.strictEqual(value, runDefinition);
      assert.equal(expectedCid, runDefinition.identity);
      return {createdAt: new Date(clock).toISOString(),
        validUntil: new Date(clock + 60_000).toISOString()};
    },
    requestedEffectStopIntentCid(value) { assert.equal(value, original); return cid('6'); },
    requestedEffectStopLifetime(value) {
      assert.equal(value, original);
      return {createdAt: new Date(clock).toISOString(),
        validUntil: new Date(clock + 60_000).toISOString()};
    },
    sealRequestedEffectStop(value, bodyWire, continuation, limits) {
      assert.equal(value, original, 'only the original opaque stop is accepted');
      assert.equal(continuation, continuationWire);
      assert.ok(limits.maxWireBytes > 0);
      const body = JSON.parse(bodyWire);
      assert.equal(body.run_id, 'requested-run');
      assert.equal(body.run_definition_cid, cid('1'));
      assert.equal(body.subject.unit_id, 'effect');
      assert.equal(body.required_artifact.artifact_cid, cid('2'));
      assert.equal(body.reason_code, 'user_requested_stop');
      const sealed = JSON.parse(checkpoint.checkpointSealBody(bodyWire));
      assert.equal(sealed.ok, true, JSON.stringify(sealed));
      return sealed.checkpoint_wire;
    }};
  const accountConfiguration = canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'local',
    entries: [{entry_id: 'write', outcome, principal: {all: true},
      connection: {any_of: [scope.connection]}, resource: {any_of: [scope.resource]},
      operation: {any_of: [scope.operation]}, exclusions: []}]});
  const open = async () => {
    const installed = await installRemoteCheckpoints({root,
      namespaceId: 'local', authorityScopeCid: cid('3'), ownerPrincipal: 'owner',
      siteKey: 'local', realizationKey: 'source-free-values', environmentCid: cid('4'),
      contractControl: control, now: () => sample,
      authorization: {accountConfiguration,
      decide, resumeAfterAnswer: false,
      reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
        principalId: 'reviewer', publicKey: pem(reviewer.publicKey)}],
      reviewReaders: ['reviewer'],
      hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)}}});
    services.add(installed);
    return installed;
  };
  const options = () => ({runId: 'requested-run', runDefinitionCid: cid('1'),
    ...(originalRun ? {runDefinition} : {}),
    unitId: 'effect', declaredResults: ['answer'], reviewWire: '{"preview":"original"}',
    projectReview: checkpointEffectReviewDouble(control,cid('2')),
    continuationWire, requestedStop: original,
    assertRequestedStopCurrent() {
      if (!current) throw Object.assign(new Error('OriginalRetired'), {code: 'OriginalRetired'});
    }, async beforeDefer() { retained++; sample += deferAdvanceMs; }});
  const gate = async (installed, changed = {}) => {
    const result = await installed.effectAuthorization({...options(), ...changed});
    gates.add(result);
    return result;
  };
  const approve = async installed => {
    const summary = (await installed.listCheckpoints({principalId: 'reviewer',
      after: '', limit: 10})).items[0];
    const answer = await signedAnswer(summary, 'approved', {keyId: 'reviewer-key',
      reviewerId: 'reviewer', authorityScopeCid: cid('3'),
      sign: bytes => sign(null, bytes, reviewer.privateKey)}, new Date(clock).toISOString());
    const result = await installed.resolve({principalId: 'reviewer', items: [answer]});
    assert.equal(result.results[0].status, 'committed', JSON.stringify(result));
    return {summary, claim: installed.journal.claimResume('requested-run', {
      claimant: 'same-host', leaseMs: 1000, binding: installed.binding})};
  };
  const close = async installed => { await installed.close(); services.delete(installed); };
  t.after(async () => {
    for (const owned of gates) owned.close();
    for (const installed of services) await close(installed);
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') t.diagnostic(`Original requested-stop journal retained: ${root}`);
    else await rm(root, {recursive: true, force: true});
  });
  return {open, close, gate, approve, options, original, accountConfiguration,
    retained: () => retained, advance(ms) { sample += ms; }, retire() { current = false; }};
}

test('exact pending lookup selects only the same original ID without a paging search', async t => {
  const f = await fixture(t), installed = await f.open(), gate = await f.gate(installed);
  await gate.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  const [summary] = (await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10})).items;
  const select = checkpointId => installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 1, checkpointId});
  assert.deepEqual(await select(summary.checkpointId), {items: [summary]});
  assert.deepEqual(await select('not-an-original-id'), {items: []});
  assert.deepEqual(await select(summary.checkpointCid), {items: []}, 'CID fallback cannot become an ID match');
  for (const changed of [{after: 'foreign-cursor'}, {limit: 2}, {checkpointId: null}, {checkpointId: true}, {checkpointId: undefined}]) {
    await assert.rejects(installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 1,
      checkpointId: summary.checkpointId, ...changed}), {code: 'InvalidCheckpointLookup'});
  }
  assert.equal(installed.journal.listRunCheckpoints().length, 1, 'lookup creates no nominal replacement');
});

test('exact pending lookup retains the existing principal and Host scope refusal', async t => {
  const f = await fixture(t), installed = await f.open(), gate = await f.gate(installed);
  await gate.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  const [summary] = (await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10})).items;
  await assert.rejects(installed.listCheckpoints({principalId: 'foreign', after: '', limit: 1,
    checkpointId: summary.checkpointId}), {code: 'CheckpointListDenied'});
  const foreign = await fixture(t), other = await foreign.open();
  assert.deepEqual(await other.listCheckpoints({principalId: 'reviewer', after: '', limit: 1,
    checkpointId: summary.checkpointId}), {items: []});
});

test('exact pending lookup does not reissue an approved original or disclose it as waiting', async t => {
  const f = await fixture(t), installed = await f.open(), gate = await f.gate(installed);
  await gate.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  const {summary} = await f.approve(installed);
  assert.deepEqual(await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 1,
    checkpointId: summary.checkpointId}), {items: []});
  assert.equal(installed.journal.listRunCheckpoints().length, 1);
  assert.equal(f.retained(), 1);
});

test('exact pending lookup rechecks the original after asynchronous metadata projection', async t => {
  const f = await fixture(t), installed = await f.open(), gate = await f.gate(installed);
  await gate.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  const [summary] = (await installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 10})).items;
  const pending = installed.listCheckpoints({principalId: 'reviewer', after: '', limit: 1,
    checkpointId: summary.checkpointId});
  assert.equal(installed.journal.cancelCheckpoint(summary.checkpointCid).outcome, 'cancelled');
  assert.deepEqual(await pending, {items: []});
});

test('requested first Effect stops Account Allow and resumes the same journal without granting permission', async t => {
  const f = await fixture(t);
  let installed = await f.open();
  const before = await f.gate(installed);
  const waiting = await before.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  assert.equal(waiting.action, 'waiting');
  assert.equal(waiting.reason, 'user_requested_stop');
  assert.equal(authorizationDispatchFacts(waiting), undefined);
  assert.equal(f.retained(), 1);
  assert.equal(installed.journal.listRunCheckpoints().length, 1);
  before.close();
  await f.close(installed);
  installed = await f.open();
  const {claim} = await f.approve(installed);
  const after = await f.gate(installed, {beforeDefer() { assert.fail('No recapture on resume'); }});
  const options = {subjectCid: cid('2'), resumption: {claim}};
  const allowed = await after.resume('effect_commit', tuple, options);
  assert.equal(allowed.action, 'dispatch');
  assert.equal(allowed.basis, 'account_allow');
  assert.equal(allowed.admission, undefined, 'Account permission is not a review grant');
  assert.equal(authorizationDispatchFacts(allowed).principal, 'owner');
  const admission = after.continuationAdmission(options.resumption, options.subjectCid);
  assert.equal(admission.checkpointCid, waiting.checkpoint.checkpointCid);
  admission.enter('same-effect-set');
  assert.throws(() => admission.enter('second-effect-set'), {code: 'ResumeAdmissionConsumed'});
  assert.equal(f.retained(), 1);
  assert.equal(installed.journal.listRunCheckpoints().length, 1,
    'the requested stop remains durably fulfilled rather than being reissued');
});

test('requested first Effect approval cannot answer a current Delegate request', async t => {
  let permit = true;
  let asks = 0;
  const f = await fixture(t, {outcome: 'delegate', decide: view => {
    asks++;
    return permit ? {decision: 'permit', subject: view.subject, authority: 'reviewer', claims: []}
      : {decision: 'unavailable'};
  }});
  const installed = await f.open();
  const first = await f.gate(installed);
  assert.equal((await first.authorize('effect_commit', tuple, {subjectCid: cid('2')})).reason,
    'user_requested_stop');
  const {claim} = await f.approve(installed);
  first.close();
  permit = false;
  const resumed = await f.gate(installed);
  const refused = await resumed.resume('effect_commit', tuple,
    {subjectCid: cid('2'), resumption: {claim}});
  assert.notEqual(refused.action, 'dispatch');
  assert.equal(authorizationDispatchFacts(refused), undefined);
  assert.equal(asks, 2, 'the actual Host decision is asked, not reconstructed from review claims');
  assert.equal(installed.journal.hasStartedResume(claim.checkpointCid), false);
});

for (const requestedStop of [false, true]) {
  test(`delegated Effect expiry preserves the original Run deadline: requestedStop=${requestedStop}`, async t => {
    const f = await fixture(t, {outcome: 'delegate', originalRun: true});
    const installed = await f.open();
    const gate = await f.gate(installed, requestedStop ? {} :
      {requestedStop: undefined, assertRequestedStopCurrent: undefined});
    const result = await gate.authorize('effect_commit', tuple, {subjectCid: cid('2')});
    assert.equal(result.action, 'waiting');
    const [view] = installed.journal.listRunCheckpoints();
    assert.equal(view.reasonCode, 'delegated_decision_deferred');
    assert.equal(Date.parse(view.expiresAt), Date.parse('2026-10-17T00:01:00.000Z') - 1);
    assert.equal(installed.journal.listRunCheckpoints().length, 1);
    assert.equal(f.retained(), 1);
  });
  test(`delegated Effect refuses an empty original Run window: requestedStop=${requestedStop}`, async t => {
    const f = await fixture(t, {outcome: 'delegate', originalRun: true,
      deferAdvanceMs: 59_999});
    const installed = await f.open();
    const gate = await f.gate(installed, requestedStop ? {} :
      {requestedStop: undefined, assertRequestedStopCurrent: undefined});
    const refused = await gate.authorize('effect_commit', tuple, {subjectCid: cid('2')});
    assert.equal(refused.action, 'failure');
    assert.equal(refused.detail, 'CheckpointNotPersisted');
    assert.equal(refused.error.code, 'RequestedEffectStopLifetimeUnavailable');
    assert.equal(authorizationDispatchFacts(refused), undefined);
    assert.equal(installed.journal.listRunCheckpoints().length, 0);
    assert.equal(f.retained(), 1, 'same capture is retained, never renewed');
  });
}

test('requested first Effect retains genuine delegated review and Account Deny behavior', async t => {
  for (const outcome of ['delegate', 'deny']) {
    const f = await fixture(t, {outcome});
    const installed = await f.open();
    const gate = await f.gate(installed);
    const result = await gate.authorize('effect_commit', tuple, {subjectCid: cid('2')});
    assert.equal(result.action, outcome === 'deny' ? 'deny' : 'waiting');
    const checkpoints = installed.journal.listRunCheckpoints();
    assert.equal(checkpoints.length, outcome === 'deny' ? 0 : 1);
    if (outcome === 'delegate') {
      assert.equal(checkpoints[0].reasonCode, 'delegated_decision_deferred');
      const {claim} = await f.approve(installed);
      const after = await f.gate(installed);
      const resumed = await after.resume('effect_commit', tuple,
        {subjectCid: cid('2'), resumption: {claim}});
      assert.equal(resumed.action, 'dispatch');
      assert.equal(resumed.basis, 'resumed');
      assert.equal(typeof resumed.admission.enter, 'function');
    }
  }
});

test('requested first Effect rejects foreign Preview and retired original before ownership entry', async t => {
  const f = await fixture(t);
  const installed = await f.open();
  const first = await f.gate(installed);
  await first.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  const {claim} = await f.approve(installed);
  const after = await f.gate(installed);
  await assert.rejects(after.resume('effect_commit', tuple,
    {subjectCid: cid('9'), resumption: {claim}}), {code: 'RequestedEffectStopBindingChanged'});
  f.retire();
  await assert.rejects(after.resume('effect_commit', tuple,
    {subjectCid: cid('2'), resumption: {claim}}), {code: 'OriginalRetired'});
  assert.equal(installed.journal.hasStartedResume(claim.checkpointCid), false);
});


test('requested-stop approval without a held claim cannot enter protected dispatch', async t => {
  const f = await fixture(t), installed = await f.open(), first = await f.gate(installed);
  await first.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  const {claim} = await f.approve(installed);
  const resumed = await f.gate(installed);
  let protectedDispatches = 0;
  await assert.rejects(async () => {
    const permission = await resumed.resume('effect_commit', tuple, {subjectCid: cid('2')});
    assert.equal(permission.action, 'dispatch');
    resumed.continuationAdmission(undefined, cid('2')).enter('effect-set');
    protectedDispatches++;
  }, {code: 'ResumeNotClaimed'});
  assert.throws(() => resumed.continuationAdmission(undefined, cid('2')), {code: 'ResumeNotClaimed'});
  assert.equal(protectedDispatches, 0);
  assert.equal(installed.journal.hasStartedResume(claim.checkpointCid), false);
});

test('requested-stop claim expiry after permission selection prevents admission entry', async t => {
  const f = await fixture(t), installed = await f.open(), first = await f.gate(installed);
  await first.authorize('effect_commit', tuple, {subjectCid: cid('2')});
  const {claim} = await f.approve(installed);
  const resumed = await f.gate(installed), options = {subjectCid: cid('2'), resumption: {claim}};
  const permission = await resumed.resume('effect_commit', tuple, options);
  assert.equal(permission.action, 'dispatch');
  assert.equal(permission.basis, 'account_allow');
  const admission = resumed.continuationAdmission(options.resumption, options.subjectCid);
  f.advance(1001); // Original claim lease is 1000 ms, original Run remains live.
  let protectedDispatches = 0;
  assert.throws(() => {admission.enter('effect-set'); protectedDispatches++;}, {code: 'ResumeClaimStale'});
  assert.equal(protectedDispatches, 0);
  assert.equal(installed.journal.hasStartedResume(claim.checkpointCid), false);
  assert.throws(() => resumed.continuationAdmission(options.resumption, options.subjectCid), {code: 'ResumeClaimStale'});
});


// This composes the actual compiled Account gate, durable Checkpoint claim,
// and Local driver/native Files. The stop projection and Run/Content domain
// ports remain explicit fixtures; this is not managed public STORE acceptance.
for (const outcome of ['allow', 'delegate']) {
test(`approved ${outcome} reaches the real Local grant after original claim entry`,
  {skip: process.platform !== 'linux' || process.arch !== 'x64'
    ? 'Physical Files fixture requires Linux x64; common checkpoint cases remain enabled' : false}, async t => {
  const scope = {connection: 'local', resource: 'files', operation: 'effect'};
  const f = await fixture(t, {scope, outcome}), installed = await f.open(), first = await f.gate(installed);
  const authorization = await createLocalAuthorizationGate({
    accountConfiguration: f.accountConfiguration, principal: 'owner'});
  t.after(() => authorization.close());
  const physical = await physicalLocal(t, authorization, {subjectCid: cid('2')});
  const grant = decision => physical.grant(decision);
  const waiting = await first.authorize('effect_commit', scope, {subjectCid: cid('2')});
  assert.equal(waiting.action, 'waiting');
  assert.throws(() => grant(waiting), {code: 'LocalStoreNotAuthorized'});
  const {claim} = await f.approve(installed), resumed = await f.gate(installed);
  const options = {subjectCid: cid('2'), resumption: {claim}};
  const permission = await resumed.resume('effect_commit', scope, options);
  assert.equal(permission.basis, outcome === 'allow' ? 'account_allow' : 'resumed');
  const admission = permission.admission ??
    resumed.continuationAdmission(options.resumption, options.subjectCid);
  admission.enter('original-local-effect-set');
  const issued = grant(permission);
  await physical.send(issued);
  assert.deepEqual(await readFile(join(physical.directory, 'result.txt')), physical.bytes);
  assert.equal(physical.renames(), 1);
  await assert.rejects(physical.send(issued), {code: 'ForeignLocalStoreUse'});
  assert.equal(physical.renames(), 1);
  assert.throws(() => admission.enter('replacement-effect-set'), {code: 'ResumeAdmissionConsumed'});
  assert.throws(() => grant({...permission}), {code: 'LocalStoreNotAuthorized'});
});
}
