import assert from 'node:assert/strict';
import {createHash, createPublicKey, generateKeyPairSync, sign, verify}
  from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as runtime from
  '../../_build/js/release/build/checkpoint_runtime_node/checkpoint_runtime_node.js';
import {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const T0 = Date.parse('2026-09-25T10:00:00.000Z');
const HOUR = 3_600_000;

// Test-side canonical JSON for ASCII fixtures: sorted keys, no whitespace.
// Cross-checked against the core below before any fixture relies on it.
const canonical = value => {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
};
const cidOf = value =>
  `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
const without = (value, ...keys) => Object.fromEntries(
  Object.entries(value).filter(([key]) => !keys.includes(key)));
// Run#resolution-admission: Ed25519 over the UTF-8 text of the unsigned CID
// (the CID of the artifact without its self CID and its signature member).
const unsignedCid = (artifact, selfField, signatureField) =>
  cidOf(without(artifact, selfField, signatureField));
const core = result => {
  const value = JSON.parse(result);
  assert.equal(value.ok, true, value.issue);
  return value;
};

const reviewers = {
  alice: {keyId: 'alice-key', ...generateKeyPairSync('ed25519')},
  bob: {keyId: 'bob-key', ...generateKeyPairSync('ed25519')},
  mallory: {keyId: 'mallory-key', ...generateKeyPairSync('ed25519')},
};
const host = {keyId: 'host-key', ...generateKeyPairSync('ed25519')};
const binding = {
  authorizationContextCid: cid('a'),
  environmentBindingCid: cid('b'),
};
const authorities = [
  {keyId: 'alice-key', reviewerId: 'alice'},
  {keyId: 'bob-key', reviewerId: 'bob'},
];

// Host authorization port: authenticates the reviewer signature over the
// core-computed unsigned Resolution CID with Host-trusted keys only (never
// with a key named by the submitted evidence).
let lastProofPreimage;
function authorizeResolution({resolutionWire, proofPreimage}) {
  const resolution = JSON.parse(resolutionWire);
  lastProofPreimage = proofPreimage;
  const trusted = Object.entries(reviewers)
    .find(([, reviewer]) => reviewer.keyId === resolution.proof.key_id);
  if (trusted === undefined) throw new Error('UntrustedKey');
  if (!verify(null, Buffer.from(proofPreimage, 'utf8'), trusted[1].publicKey,
    Buffer.from(resolution.proof.signature, 'base64'))) {
    throw new Error('BadSignature');
  }
  return {
    keyId: resolution.proof.key_id,
    reviewerId: trusted[0],
    authorityContextCid: cid('c'),
    policyCid: cid('d'),
    verifiedPreimage: proofPreimage,
  };
}

let attestations = 0;
function attestResolution(preimage) {
  attestations += 1;
  return {
    hostKeyId: host.keyId,
    signature: sign(null, Buffer.from(preimage, 'utf8'), host.privateKey)
      .toString('base64'),
  };
}

function signResolution(body, reviewer) {
  const key = reviewers[reviewer];
  body.proof = {
    scheme: 'ed25519-v1',
    key_id: key.keyId,
    signature: sign(null, Buffer.from(cidOf(body), 'utf8'), key.privateKey)
      .toString('base64'),
  };
  body.resolution_cid = cidOf(body);
  return body;
}

function hostAttestationVerifies(verified) {
  return verify(null,
    Buffer.from(unsignedCid(verified, 'verified_resolution_cid',
      'host_attestation'), 'utf8'),
    host.publicKey, Buffer.from(verified.host_attestation.signature, 'base64'));
}

function effectBody({
  runId = 'run-1', checkpointId = 'cp-1', unitId = 'unit-7',
  requirements = ['effect_scope_approved', 'partial_application_accepted'],
  expiresAt = '2026-09-26T10:00:00.000Z',
} = {}) {
  return {
    version: 'actql-execution-checkpoint/0.1',
    checkpoint_id: checkpointId,
    run_id: runId,
    run_definition_cid: cid('1'),
    continuation_state_cid: cid('2'),
    subject: {kind: 'run_unit', run_id: runId, unit_id: unitId,
      continuation: 'resume_unit'},
    phase: 'commit',
    kind: 'effect_set',
    required_artifact: {artifact_type: 'effect_set_preview',
      artifact_cid: cid('3')},
    review_projection_cid: cid('4'),
    requirements,
    reason_code: 'effect_review_required',
    human_summary: 'Apply two ticket updates',
    created_at: '2026-09-25T10:00:00.000Z',
    expires_at: expiresAt,
  };
}

function effectEvidence(checkpoint, approver = 'alice') {
  const attestation = {
    version: 'actql-approval-attestation/0.1',
    effect_preview_cid: checkpoint.required_artifact.artifact_cid,
    review_projection_cid: checkpoint.review_projection_cid,
    approver,
    approved_at: '2026-09-25T11:00:00.000Z',
    authority_scope_cid: cid('5'),
    claims: [...checkpoint.requirements],
    proof: {scheme: 'ed25519-v1', key_id: `${approver}-key`,
      signature: 'c2lnbmF0dXJl'},
  };
  attestation.attestation_cid = cidOf(attestation);
  return {
    version: 'actql-checkpoint-approval-evidence/0.1',
    kind: 'effect_set',
    checkpoint_cid: checkpoint.checkpoint_cid,
    review_projection_cid: checkpoint.review_projection_cid,
    compatibility_approval: attestation,
  };
}

function resolve(checkpoint, decision, {
  reviewer = 'alice', decidedAt = '2026-09-25T10:00:00.000Z', resolutionId,
} = {}) {
  const evidence = decision === 'approved' ?
    effectEvidence(checkpoint, reviewer) : undefined;
  const identity = checkpoint.subject.kind === 'run_unit' ?
    {run_id: checkpoint.run_id, run_definition_cid: checkpoint.run_definition_cid} :
    {prepare_attempt_id: checkpoint.subject.prepare_attempt_id};
  const body = {
    version: 'actql-checkpoint-resolution/0.1',
    resolution_id: resolutionId ?? `res-${reviewer}-${decision}`,
    checkpoint_id: checkpoint.checkpoint_id,
    checkpoint_cid: checkpoint.checkpoint_cid,
    ...identity,
    decision,
    actor: reviewer,
    decided_at: decidedAt,
    required_artifact_cid: checkpoint.required_artifact.artifact_cid,
    review_projection_cid: checkpoint.review_projection_cid,
    ...(evidence ? {approval_evidence_cid: cidOf(evidence)} : {}),
  };
  signResolution(body, reviewer);
  return {
    resolutionWire: JSON.stringify(body),
    approvalEvidenceWire: evidence ? JSON.stringify(evidence) : '',
  };
}

async function workspace(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-checkpoint-journal-'));
  const clock = {ms: T0};
  const opened = [];
  const open = (faults = {}) => {
    const journal = openSqliteCheckpointJournal(root, {
      runtime, expectedAuthorityScopeCid: cid('5'),
      authorizeResolution, attestResolution,
      now: () => clock.ms, faults,
    });
    opened.push(journal);
    return journal;
  };
  t.after(async () => {
    for (const journal of opened) journal.close();
    await rm(root, {recursive: true, force: true});
  });
  return {root, clock, open};
}

const persist = (journal, body = effectBody()) => journal.persistCheckpoint({
  body,
  priorStatus: 'running',
  declaredResults: ['tickets'],
  authorities,
  binding,
});

function stored(journal) {
  const database = new DatabaseSync(journal.path, {readOnly: true});
  try {
    return JSON.parse(database.prepare(
      'SELECT checkpoint_wire FROM checkpoints ORDER BY persisted_at',
    ).get().checkpoint_wire);
  } finally {
    database.close();
  }
}

function counts(path) {
  const database = new DatabaseSync(path, {readOnly: true});
  try {
    const count = table =>
      database.prepare(`SELECT count(*) AS n FROM ${table}`).get().n;
    return {
      runs: count('runs'), checkpoints: count('checkpoints'),
      resolutions: count('resolutions'), intents: count('resume_intents'),
      ...(count('preparations') > 0 ?
        {preparations: count('preparations')} : {}),
    };
  } finally {
    database.close();
  }
}

test('test canonical JSON agrees with the core Checkpoint identity', () => {
  const sealed = JSON.parse(runtime.checkpointSealBody(
    JSON.stringify(effectBody())));
  assert.equal(sealed.ok, true);
  assert.equal(sealed.checkpoint_cid, cidOf(effectBody()));
  assert.equal(sealed.checkpoint_wire,
    canonical({...effectBody(), checkpoint_cid: sealed.checkpoint_cid}));
});

test('persist, restart, approve, restart, claim, crash mid-claim, re-claim and complete once',
  async t => {
    const {clock, open} = await workspace(t);
    let journal = open();
    const waiting = persist(journal);
    assert.equal(waiting.runState.status, 'waiting_checkpoint');
    assert.deepEqual(waiting.runState.next_action,
      {kind: 'resolve_checkpoint', checkpoint_id: 'cp-1'});
    assert.equal(waiting.runState.checkpoint.checkpoint_cid,
      waiting.checkpointCid);
    journal.close();

    // Restart after commit, before the response was delivered.
    journal = open();
    assert.deepEqual(journal.getRunState('run-1').runState, waiting.runState);
    const [pending] = journal.listPending();
    assert.equal(pending.checkpointCid, waiting.checkpointCid);
    assert.deepEqual(pending.requiredArtifact,
      {type: 'effect_set_preview', cid: cid('3')});
    assert.equal(pending.reviewProjectionCid, cid('4'));
    assert.equal(pending.closure, 'open');
    // Nothing may be dispatched across the unresolved Checkpoint.
    assert.throws(() => journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 1000, binding}),
    {code: 'ResumeIntentNotFound'});
    assert.equal('authorities' in pending, false);
    assert.deepEqual(journal.inspect('cp-1'), pending);

    clock.ms = T0 + 2 * HOUR;
    const checkpoint = stored(journal);
    const approved = await journal.submitResolution({
      checkpointCid: waiting.checkpointCid, ...resolve(checkpoint, 'approved'),
    });
    assert.equal(approved.outcome, 'committed');
    assert.equal(approved.decision, 'approved');
    assert.equal(approved.runState.status, 'resuming');
    assert.equal(approved.runState.runState.next_action.kind, 'none');
    assert.equal('checkpoint' in approved.runState.runState, false);
    const verified = JSON.parse(approved.verifiedResolutionWire);
    assert.equal(verified.version, 'actql-verified-checkpoint-resolution/0.1');
    assert.equal(verified.host_attestation.host_key_id, 'host-key');
    assert.equal(verified.verified_resolution_cid,
      cidOf(without(verified, 'verified_resolution_cid')));
    // Both signatures cover the unsigned CID text computed by the core.
    assert.equal(hostAttestationVerifies(verified), true);
    assert.equal(core(runtime.verifiedAttestationPreimage(
      approved.verifiedResolutionWire)).preimage,
    unsignedCid(verified, 'verified_resolution_cid', 'host_attestation'));
    assert.equal(lastProofPreimage,
      unsignedCid(verified.resolution, 'resolution_cid', 'proof'));
    assert.equal(journal.listPending().length, 0);
    journal.close();

    // Restart after Resolution commit, before resume.
    journal = open();
    assert.equal(journal.getRunState('run-1').status, 'resuming');
    const first = journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 60_000, binding});
    assert.equal(first.action, 'claimed');
    assert.equal(first.claim.generation, 1);
    assert.equal(first.continuationStateCid, cid('2'));
    journal.close();

    // Restart mid-claim: the old lease still fences other claimants.
    journal = open();
    assert.deepEqual(journal.claimResume('run-1',
      {claimant: 'worker-b', leaseMs: 60_000, binding}), {action: 'busy'});
    clock.ms += 60_000;
    const second = journal.claimResume('run-1',
      {claimant: 'worker-b', leaseMs: 60_000, binding});
    assert.equal(second.action, 'claimed');
    assert.equal(second.claim.generation, 2);
    assert.throws(() => journal.completeResume(first.claim,
      {status: 'failed'}), {code: 'ResumeClaimStale'});
    assert.equal(journal.getRunState('run-1').status, 'resuming');

    const done = journal.completeResume(second.claim, {status: 'cancelled'});
    assert.equal(done.status, 'cancelled');
    assert.throws(() => journal.completeResume(second.claim,
      {status: 'failed'}), {code: 'ResumeClaimStale'});
    assert.deepEqual(journal.claimResume('run-1',
      {claimant: 'worker-c', leaseMs: 60_000, binding}),
    {action: 'completed'});
    assert.deepEqual(counts(journal.path),
      {runs: 1, checkpoints: 1, resolutions: 1, intents: 1});
  });

test('duplicate identical Resolution is idempotent across restart',
  async t => {
    const {open} = await workspace(t);
    let journal = open();
    const waiting = persist(journal);
    const answer = resolve(stored(journal), 'approved');
    const first = await journal.submitResolution({
      checkpointCid: waiting.checkpointCid, ...answer});
    journal.close();
    journal = open();
    const again = await journal.submitResolution({
      checkpointCid: waiting.checkpointCid, ...answer});
    assert.equal(again.outcome, 'duplicate');
    assert.equal(again.resolutionCid, first.resolutionCid);
    assert.equal(again.verifiedResolutionWire, first.verifiedResolutionWire);
    assert.equal(again.resumeIntentId, first.resumeIntentId);
    assert.equal(again.runState.version, first.runState.version);
    // A retried persist of the answered Checkpoint reports current state.
    const retried = persist(journal);
    assert.equal(retried.checkpointCid, waiting.checkpointCid);
    assert.equal(retried.runState.status, 'resuming');
    assert.equal(persist(journal).runState.status, 'resuming');
    assert.deepEqual(counts(journal.path),
      {runs: 1, checkpoints: 1, resolutions: 1, intents: 1});
  });

test('conflicting Resolutions admit exactly one winner', async t => {
  const {open} = await workspace(t);
  const journal = open();
  const waiting = persist(journal);
  const checkpoint = stored(journal);
  const approve = resolve(checkpoint, 'approved');
  const reject = resolve(checkpoint, 'rejected', {reviewer: 'bob'});
  // Two Host processes answer concurrently on the same store.
  const other = open();
  const results = await Promise.allSettled([
    journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...approve}),
    other.submitResolution({checkpointCid: waiting.checkpointCid, ...reject}),
  ]);
  const won = results.filter(result => result.status === 'fulfilled');
  const lost = results.filter(result => result.status === 'rejected');
  assert.equal(won.length, 1);
  assert.equal(lost.length, 1);
  assert.equal(lost[0].reason.code, 'CheckpointResolutionConflict');
  const winner = won[0].value;
  const state = journal.getRunState('run-1');
  assert.equal(state.status,
    winner.decision === 'approved' ? 'resuming' : 'cancelled');
  assert.equal(state.version, 2);
  assert.equal(counts(journal.path).resolutions, 1);
  assert.equal(counts(journal.path).intents,
    winner.decision === 'approved' ? 1 : 0);
  await assert.rejects(journal.submitResolution({
    checkpointCid: waiting.checkpointCid,
    ...(winner.decision === 'approved' ? reject : approve),
  }), {code: 'CheckpointResolutionConflict'});
  assert.equal(journal.getRunState('run-1').version, 2);
});

test('rejection cancels the Run without a resume intent', async t => {
  const {open} = await workspace(t);
  const journal = open();
  const waiting = persist(journal);
  const rejected = await journal.submitResolution({
    checkpointCid: waiting.checkpointCid,
    ...resolve(stored(journal), 'rejected'),
  });
  assert.equal(rejected.decision, 'rejected');
  assert.equal(rejected.resumeIntentId, null);
  assert.equal(rejected.runState.status, 'cancelled');
  assert.equal(
    'approval_evidence' in JSON.parse(rejected.verifiedResolutionWire), false);
  assert.throws(() => journal.claimResume('run-1',
    {claimant: 'worker-a', leaseMs: 1000, binding}),
  {code: 'ResumeIntentNotFound'});
  assert.equal(counts(journal.path).intents, 0);
});

test('stale claimants cannot renew or complete', async t => {
  const {clock, open} = await workspace(t);
  const journal = open();
  const waiting = persist(journal);
  await journal.submitResolution({checkpointCid: waiting.checkpointCid,
    ...resolve(stored(journal), 'approved')});
  const first = journal.claimResume('run-1',
    {claimant: 'worker-a', leaseMs: 1000, binding}).claim;
  const renewed = journal.renewResume(first, 5000);
  assert.equal(renewed.leaseExpiresMs, clock.ms + 5000);
  clock.ms += 5000;
  // Expired lease: the holder is stale even before anyone re-claims.
  assert.throws(() => journal.renewResume(first, 1000),
    {code: 'ResumeClaimStale'});
  assert.throws(() => journal.completeResume(first, {status: 'failed'}),
    {code: 'ResumeClaimStale'});
  const second = journal.claimResume('run-1',
    {claimant: 'worker-b', leaseMs: 1000, binding}).claim;
  assert.equal(second.generation, 2);
  assert.throws(() => journal.completeResume({...first, generation: 2},
    {status: 'failed'}), {code: 'ResumeClaimStale'});
  assert.throws(() => journal.completeResume(first, {status: 'failed'}),
    {code: 'ResumeClaimStale'});
  assert.equal(journal.getRunState('run-1').status, 'resuming');
  const runState = {
    version: 'actql-run-state/0.1',
    run_id: 'run-1',
    status: 'succeeded',
    updated_at: '2026-09-25T10:00:05.000Z',
    next_action: {kind: 'read_result', results: ['tickets']},
    result_available: true,
    result_availability: {tickets: {state: 'available',
      observed_at: '2026-09-25T10:00:05.000Z', reason: 'confirmed_present'}},
  };
  const done = journal.completeResume(second,
    {runStateWire: JSON.stringify(runState)});
  assert.equal(done.status, 'succeeded');
  assert.deepEqual(done.runState, runState);
});

test('expired Checkpoint cannot be approved and cancels the Run',
  async t => {
    const {clock, open} = await workspace(t);
    const journal = open();
    const waiting = persist(journal, effectBody({
      expiresAt: '2026-09-25T11:00:00.000Z'}));
    const answer = resolve(stored(journal), 'approved',
      {decidedAt: '2026-09-25T10:30:00.000Z'});
    clock.ms = T0 + HOUR;
    await assert.rejects(journal.submitResolution({
      checkpointCid: waiting.checkpointCid, ...answer,
    }), {code: 'CheckpointExpired'});
    assert.equal(journal.getRunState('run-1').status, 'cancelled');
    assert.equal(journal.inspect(waiting.checkpointCid).closure, 'expired');
    assert.deepEqual(journal.expire(), []);
    assert.equal(counts(journal.path).resolutions, 0);

    const other = persist(journal, effectBody({runId: 'run-2',
      expiresAt: '2026-09-25T12:00:00.000Z'}));
    clock.ms = T0 + HOUR + HOUR / 2;
    assert.deepEqual(journal.expire(), []);
    clock.ms = T0 + 2 * HOUR;
    assert.deepEqual(journal.expire(), [other.checkpointCid]);
    assert.equal(journal.getRunState('run-2').status, 'cancelled');
    assert.equal(journal.listPending().length, 0);
  });

test('crash before commit leaves no durable Checkpoint, Resolution or claim',
  async t => {
    const {open} = await workspace(t);
    const crash = step => { throw Object.assign(new Error(step), {code: step}); };
    let journal = open({beforeCommit: step =>
      step === 'persistCheckpoint' && crash('crash')});
    assert.throws(() => persist(journal), {code: 'crash'});
    journal.close();
    journal = open();
    assert.equal(journal.getRunState('run-1'), undefined);
    assert.equal(journal.listPending().length, 0);
    assert.deepEqual(counts(journal.path),
      {runs: 0, checkpoints: 0, resolutions: 0, intents: 0});
    const waiting = persist(journal);
    const answer = resolve(stored(journal), 'approved');
    journal.close();

    journal = open({beforeCommit: step =>
      step === 'submitResolution' && crash('crash')});
    await assert.rejects(journal.submitResolution({
      checkpointCid: waiting.checkpointCid, ...answer}), {code: 'crash'});
    journal.close();
    journal = open({beforeCommit: step =>
      step === 'claimResume' && crash('crash')});
    assert.equal(journal.getRunState('run-1').status, 'waiting_checkpoint');
    assert.equal(counts(journal.path).resolutions, 0);
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...answer});
    assert.throws(() => journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 1000, binding}), {code: 'crash'});
    journal.close();
    journal = open();
    // The rolled-back claim leaves the intent claimable at generation 1.
    const claimed = journal.claimResume('run-1',
      {claimant: 'worker-b', leaseMs: 1000, binding});
    assert.equal(claimed.claim.generation, 1);
  });

test('invalid or unauthorized Resolutions change nothing', async t => {
  const {open} = await workspace(t);
  const journal = open();
  const waiting = persist(journal);
  const checkpoint = stored(journal);
  const before = attestations;
  // Trusted key, but reviewer not in this Checkpoint's authority set.
  await assert.rejects(journal.submitResolution({
    checkpointCid: waiting.checkpointCid,
    ...resolve(checkpoint, 'approved', {reviewer: 'mallory'}),
  }), {code: 'InvalidResolution', cause: 'AuthorityNotPermitted'});
  // Tampered body fails Host authentication before admission.
  const answer = resolve(checkpoint, 'approved');
  const tampered = answer.resolutionWire.replace('res-alice', 'res-alicf');
  await assert.rejects(journal.submitResolution({
    checkpointCid: waiting.checkpointCid,
    resolutionWire: tampered,
    approvalEvidenceWire: answer.approvalEvidenceWire,
  }), {code: 'ResolutionAuthenticationFailed'});
  // Evidence bytes must hash to the authored approval_evidence_cid.
  await assert.rejects(journal.submitResolution({
    checkpointCid: waiting.checkpointCid,
    resolutionWire: answer.resolutionWire,
    approvalEvidenceWire: answer.approvalEvidenceWire.replace(
      '11:00:00.000Z', '11:00:00.001Z'),
  }), {code: 'InvalidResolution'});
  await assert.rejects(journal.submitResolution({
    checkpointCid: waiting.checkpointCid,
    resolutionWire: answer.resolutionWire,
  }), {code: 'InvalidResolution', cause: 'EvidenceRequired'});
  assert.equal(attestations, before);
  assert.equal(journal.getRunState('run-1').status, 'waiting_checkpoint');
  assert.equal(counts(journal.path).resolutions, 0);
  assert.throws(() => persist(journal, {...effectBody({runId: 'run-9'}),
    kind: 'run_scope'}), {code: 'InvalidCheckpoint'});
  assert.throws(() => journal.persistCheckpoint({
    body: effectBody({runId: 'run-9'}), priorStatus: 'resuming',
    declaredResults: ['tickets'], authorities, binding,
  }), {code: 'RunTransitionRejected'});
});

test('journal passes its trusted scope to common Effect admission', async t => {
  const {open} = await workspace(t);
  const journal = open();
  const waiting = persist(journal);
  const checkpoint = stored(journal);
  const answer = resolve(checkpoint, 'approved');
  const evidence = JSON.parse(answer.approvalEvidenceWire);
  evidence.compatibility_approval.authority_scope_cid = cid('8');
  evidence.compatibility_approval.attestation_cid = cidOf(
    Object.fromEntries(Object.entries(evidence.compatibility_approval)
      .filter(([key]) => key !== 'attestation_cid')));
  const resolution = JSON.parse(answer.resolutionWire);
  delete resolution.proof;
  delete resolution.resolution_cid;
  resolution.approval_evidence_cid = cidOf(evidence);
  signResolution(resolution, 'alice');
  await assert.rejects(journal.submitResolution({
    checkpointCid: waiting.checkpointCid,
    resolutionWire: JSON.stringify(resolution),
    approvalEvidenceWire: JSON.stringify(evidence),
  }), {code: 'InvalidResolution',
    cause: 'EvidenceMismatch("authority_scope_cid")'});
  assert.equal(journal.resolutionOf(waiting.checkpointCid), undefined);
});

test('changed binding fails the resumed Run before dispatch', async t => {
  const {open} = await workspace(t);
  const journal = open();
  const waiting = persist(journal);
  await journal.submitResolution({checkpointCid: waiting.checkpointCid,
    ...resolve(stored(journal), 'approved')});
  const result = journal.claimResume('run-1', {claimant: 'worker-a',
    leaseMs: 1000, binding: {...binding, environmentBindingCid: cid('e')}});
  assert.deepEqual(result, {action: 'invalidated', runStatus: 'failed',
    terminalErrorCode: 'ACTQL_E_RESUME_REVALIDATION_FAILED'});
  const state = journal.getRunState('run-1');
  assert.equal(state.status, 'failed');
  assert.equal(state.runState.terminal_error.code,
    'ACTQL_E_RESUME_REVALIDATION_FAILED');
  assert.deepEqual(state.runState.next_action, {kind: 'none'});
  assert.deepEqual(journal.claimResume('run-1',
    {claimant: 'worker-a', leaseMs: 1000, binding}), {action: 'completed'});
});

test('a resumed Run may pause again at its next Checkpoint', async t => {
  const {clock, open} = await workspace(t);
  let journal = open();
  const read = persist(journal, {
    ...effectBody(),
    checkpoint_id: 'cp-read',
    phase: 'preflight',
    kind: 'read_access',
    required_artifact: {artifact_type: 'read_scope', artifact_cid: cid('6')},
    requirements: ['invocation_scope_approved'],
  });
  const readCheckpoint = stored(journal);
  const approval = {
    version: 'actql-run-scope-approval/0.1',
    prepared_invocation_cid: cid('7'),
    review_projection_cid: readCheckpoint.review_projection_cid,
    claim: 'invocation_scope_approved',
    approver: 'alice',
    approved_at: '2026-09-25T11:00:00.000Z',
    expires_at: '2026-09-26T10:00:00.000Z',
    proof: {scheme: 'ed25519-v1', key_id: 'alice-key',
      signature: 'c2lnbmF0dXJl'},
  };
  approval.run_scope_approval_cid = cidOf(approval);
  const evidence = {
    version: 'actql-checkpoint-approval-evidence/0.1',
    kind: 'read_access',
    checkpoint_cid: readCheckpoint.checkpoint_cid,
    review_projection_cid: readCheckpoint.review_projection_cid,
    compatibility_approval: approval,
  };
  const body = {
    ...JSON.parse(resolve(readCheckpoint, 'rejected').resolutionWire),
    decision: 'approved',
    resolution_id: 'res-read',
    approval_evidence_cid: cidOf(evidence),
  };
  delete body.proof;
  delete body.resolution_cid;
  signResolution(body, 'alice');
  clock.ms = T0 + 2 * HOUR;
  await journal.submitResolution({checkpointCid: read.checkpointCid,
    resolutionWire: JSON.stringify(body),
    approvalEvidenceWire: JSON.stringify(evidence)});
  const {claim} = journal.claimResume('run-1',
    {claimant: 'worker-a', leaseMs: 60_000, binding});
  const next = journal.completeResume(claim, {checkpoint: {
    body: effectBody({checkpointId: 'cp-effect'}), authorities, binding,
  }});
  assert.equal(next.runState.status, 'waiting_checkpoint');
  assert.equal(next.runState.checkpoint.checkpoint_id, 'cp-effect');
  journal.close();
  journal = open();
  const pending = journal.listPending();
  assert.deepEqual(pending.map(item => item.checkpointId), ['cp-effect']);
  assert.equal(journal.inspect(read.checkpointCid).closure, 'resolved');
});

// Fixed vectors computed independently of product code
// (portability/corpus/checkpoint-resolution-signatures.json).
test('core signature preimages match the pinned Resolution vectors', () => {
  const corpus = JSON.parse(readFileSync(new URL(
    '../../portability/corpus/checkpoint-resolution-signatures.json',
    import.meta.url), 'utf8'));
  const spki = raw => createPublicKey({
    key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'),
      Buffer.from(raw, 'base64')]),
    format: 'der', type: 'spki',
  });
  assert.equal(corpus.cases.length, 3);
  for (const c of corpus.cases) {
    const wire = JSON.stringify(c.artifact);
    const {preimage} = core(c.kind === 'checkpoint_resolution' ?
      runtime.resolutionProofPreimage(wire) :
      runtime.verifiedAttestationPreimage(wire));
    assert.equal(preimage, c.expected_unsigned_cid, c.id);
    // The Host port verifies Ed25519 over exactly that text.
    const signature = Buffer.from(c.artifact[c.signature_field].signature,
      'base64');
    const key = spki(corpus.public_keys[c.key]);
    assert.equal(verify(null, Buffer.from(preimage, 'utf8'), key, signature),
      true, c.id);
    assert.equal(verify(null, Buffer.from(c.expected_self_cid, 'utf8'), key,
      signature), false, c.id);
    // A Resolution preimage is not accepted as a wrapper preimage.
    const other = JSON.parse(c.kind === 'checkpoint_resolution' ?
      runtime.verifiedAttestationPreimage(wire) :
      runtime.resolutionProofPreimage(wire));
    assert.equal(other.ok, false, c.id);
  }
});

function prepareBody({
  attemptId = 'attempt-1', checkpointId = 'cp-prep',
  expiresAt = '2026-09-26T10:00:00.000Z',
} = {}) {
  return {
    version: 'actql-execution-checkpoint/0.1',
    checkpoint_id: checkpointId,
    continuation_state_cid: cid('2'),
    subject: {kind: 'prepare_attempt', prepare_attempt_id: attemptId,
      continuation: 'start_run'},
    phase: 'preflight',
    kind: 'run_scope',
    required_artifact: {artifact_type: 'prepared_invocation',
      artifact_cid: cid('8')},
    review_projection_cid: cid('4'),
    requirements: ['invocation_scope_approved'],
    reason_code: 'run_scope_review_required',
    human_summary: 'Start the ticket sync',
    created_at: '2026-09-25T10:00:00.000Z',
    expires_at: expiresAt,
  };
}

function resolvePreparation(checkpoint, decision, {reviewer = 'alice',
  approvalExpiresAt = '2026-09-26T10:00:00.000Z'} = {}) {
  let evidence;
  if (decision === 'approved') {
    const approval = {
      version: 'actql-run-scope-approval/0.1',
      prepared_invocation_cid: checkpoint.required_artifact.artifact_cid,
      review_projection_cid: checkpoint.review_projection_cid,
      claim: 'invocation_scope_approved',
      approver: reviewer,
      approved_at: '2026-09-25T11:00:00.000Z',
      expires_at: approvalExpiresAt,
      proof: {scheme: 'ed25519-v1', key_id: `${reviewer}-key`,
        signature: 'c2lnbmF0dXJl'},
    };
    approval.run_scope_approval_cid = cidOf(approval);
    evidence = {
      version: 'actql-checkpoint-approval-evidence/0.1',
      kind: 'run_scope',
      checkpoint_cid: checkpoint.checkpoint_cid,
      review_projection_cid: checkpoint.review_projection_cid,
      compatibility_approval: approval,
    };
  }
  const body = signResolution({
    version: 'actql-checkpoint-resolution/0.1',
    resolution_id: `res-${reviewer}-${decision}`,
    checkpoint_id: checkpoint.checkpoint_id,
    checkpoint_cid: checkpoint.checkpoint_cid,
    prepare_attempt_id: checkpoint.subject.prepare_attempt_id,
    decision,
    actor: reviewer,
    decided_at: '2026-09-25T10:00:00.000Z',
    required_artifact_cid: checkpoint.required_artifact.artifact_cid,
    review_projection_cid: checkpoint.review_projection_cid,
    ...(evidence ? {approval_evidence_cid: cidOf(evidence)} : {}),
  }, reviewer);
  return {
    resolutionWire: JSON.stringify(body),
    approvalEvidenceWire: evidence ? JSON.stringify(evidence) : '',
  };
}

const persistPreparation = (journal, body = prepareBody()) =>
  journal.persistCheckpoint({
    body, declaredResults: ['tickets'], authorities, binding,
  });

test('a preparation Checkpoint is persisted without a Run until the Run is created',
  async t => {
    const {clock, open} = await workspace(t);
    let journal = open();
    const waiting = persistPreparation(journal);
    assert.equal(waiting.runId, null);
    assert.equal(waiting.prepareAttemptId, 'attempt-1');
    assert.equal('runState' in waiting, false);
    assert.equal(waiting.preparation.status, 'waiting_checkpoint');
    const checkpoint = stored(journal);
    assert.equal('run_id' in checkpoint, false);
    assert.equal('run_definition_cid' in checkpoint, false);
    assert.deepEqual(counts(journal.path), {runs: 0, checkpoints: 1,
      resolutions: 0, intents: 0, preparations: 1});
    const [pending] = journal.listPending();
    assert.equal(pending.checkpointCid, waiting.checkpointCid);
    assert.equal(pending.runId, null);
    assert.equal(pending.prepareAttemptId, 'attempt-1');
    // A preparation Checkpoint never names a prior Run status.
    assert.throws(() => journal.persistCheckpoint({
      body: prepareBody({attemptId: 'attempt-2'}), priorStatus: 'preparing',
      declaredResults: ['tickets'], authorities, binding,
    }), {code: 'RunTransitionRejected'});
    // A Resolution that names a Run is not bound to this subject.
    const wrong = JSON.parse(resolvePreparation(checkpoint, 'rejected')
      .resolutionWire);
    delete wrong.proof;
    delete wrong.resolution_cid;
    wrong.run_id = 'run-1';
    signResolution(wrong, 'alice');
    await assert.rejects(journal.submitResolution({
      checkpointCid: waiting.checkpointCid,
      resolutionWire: JSON.stringify(wrong),
    }), error => {
      assert.equal(error.code, 'InvalidResolution');
      assert.equal(error.issueCode, 'CheckpointBindingMismatch');
      assert.equal(error.cause, 'CheckpointBindingMismatch("run_id")');
      return true;
    });
    journal.close();

    journal = open();
    clock.ms = T0 + HOUR;
    const approved = await journal.submitResolution({
      checkpointCid: waiting.checkpointCid,
      ...resolvePreparation(checkpoint, 'approved'),
    });
    assert.equal(approved.decision, 'approved');
    assert.equal('runState' in approved, false);
    assert.equal(approved.preparation.status, 'resuming');
    assert.equal(typeof approved.resumeIntentId, 'string');
    assert.equal(counts(journal.path).runs, 0);
    assert.equal(JSON.parse(approved.verifiedResolutionWire).resolution
      .prepare_attempt_id, 'attempt-1');
    assert.equal(hostAttestationVerifies(
      JSON.parse(approved.verifiedResolutionWire)), true);
    journal.close();

    journal = open();
    const claimed = journal.claimPreparationResume('attempt-1',
      {claimant: 'worker-a', leaseMs: 60_000, binding});
    assert.equal(claimed.action, 'claimed');
    assert.equal(claimed.claim.prepareAttemptId, 'attempt-1');
    assert.equal(claimed.continuationStateCid, cid('2'));
    assert.equal(counts(journal.path).runs, 0);
    // The resumed preparation continuation creates the Run.
    const created = journal.completeResume(claimed.claim,
      {run: {runId: 'run-1', status: 'running'}});
    assert.equal(created.preparation.status, 'run_created');
    assert.equal(created.preparation.runId, 'run-1');
    assert.equal(created.runState.status, 'running');
    assert.deepEqual(Object.keys(created.runState.runState.result_availability),
      ['tickets']);
    assert.deepEqual(counts(journal.path), {runs: 1, checkpoints: 1,
      resolutions: 1, intents: 1, preparations: 1});
    assert.deepEqual(journal.claimPreparationResume('attempt-1',
      {claimant: 'worker-b', leaseMs: 1000, binding}), {action: 'completed'});

    // The created Run can pause at its own Run-unit Checkpoint.
    const unit = journal.persistCheckpoint({
      body: effectBody({checkpointId: 'cp-effect'}), priorStatus: 'running',
      declaredResults: ['tickets'], authorities, binding,
    });
    assert.equal(unit.runState.status, 'waiting_checkpoint');
    assert.equal(journal.getRunState('run-1').version, 2);
  });

test('failed revalidation of a preparation continuation creates no Run',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const waiting = persistPreparation(journal);
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...resolvePreparation(stored(journal), 'approved')});
    const result = journal.claimPreparationResume('attempt-1', {
      claimant: 'worker-a', leaseMs: 1000,
      binding: {...binding, authorizationContextCid: cid('e')},
    });
    assert.deepEqual(result, {action: 'invalidated', runCreated: false,
      terminalErrorCode: 'ACTQL_E_RESUME_REVALIDATION_FAILED'});
    const preparation = journal.getPreparation('attempt-1');
    assert.equal(preparation.status, 'ended');
    assert.equal(preparation.endReason, 'revalidation_failed');
    assert.equal(preparation.terminalErrorCode,
      'ACTQL_E_RESUME_REVALIDATION_FAILED');
    assert.deepEqual(journal.claimPreparationResume('attempt-1',
      {claimant: 'worker-a', leaseMs: 1000, binding}), {action: 'completed'});
    assert.equal(counts(journal.path).runs, 0);
  });

test('a rejected or expired preparation Checkpoint ends without a Run',
  async t => {
    const {clock, open} = await workspace(t);
    const journal = open();
    const waiting = persistPreparation(journal);
    const rejected = await journal.submitResolution({
      checkpointCid: waiting.checkpointCid,
      ...resolvePreparation(stored(journal), 'rejected'),
    });
    assert.equal(rejected.resumeIntentId, null);
    assert.equal(rejected.preparation.status, 'ended');
    assert.equal(rejected.preparation.endReason, 'rejected');
    assert.throws(() => journal.claimPreparationResume('attempt-1',
      {claimant: 'worker-a', leaseMs: 1000, binding}),
    {code: 'ResumeIntentNotFound'});

    const late = persistPreparation(journal, prepareBody({
      attemptId: 'attempt-2', expiresAt: '2026-09-25T11:00:00.000Z'}));
    clock.ms = T0 + HOUR;
    assert.deepEqual(journal.expire(), [late.checkpointCid]);
    assert.equal(journal.getPreparation('attempt-2').endReason, 'expired');
    assert.equal(journal.listPending().length, 0);
    assert.equal(counts(journal.path).runs, 0);
  });

test('an immediate answer persists no Checkpoint, waiting state or intent',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const body = effectBody();
    const subject = core(runtime.checkpointSealBody(JSON.stringify(body)));
    const checkpoint = JSON.parse(subject.checkpoint_wire);
    const permitted = await journal.admitImmediateResolution({
      body, authorities, ...resolve(checkpoint, 'approved'),
    });
    assert.equal(permitted.decision, 'approved');
    assert.equal(permitted.checkpointCid, subject.checkpoint_cid);
    const verified = JSON.parse(permitted.verifiedResolutionWire);
    assert.equal(verified.resolution.checkpoint_cid, subject.checkpoint_cid);
    assert.equal(hostAttestationVerifies(verified), true);
    assert.equal('resumeIntentId' in permitted, false);
    const rejected = await journal.admitImmediateResolution({
      body, authorities, ...resolve(checkpoint, 'rejected', {reviewer: 'bob'}),
    });
    assert.equal(rejected.decision, 'rejected');
    assert.deepEqual(counts(journal.path),
      {runs: 0, checkpoints: 0, resolutions: 0, intents: 0});
    assert.equal(journal.getRunState('run-1'), undefined);
    // Bound to the exact would-be body: another body is another subject.
    await assert.rejects(journal.admitImmediateResolution({
      body: {...body, review_projection_cid: cid('9')}, authorities,
      ...resolve(checkpoint, 'rejected'),
    }), {code: 'InvalidResolution'});
    await assert.rejects(journal.admitImmediateResolution({
      body, authorities: [{keyId: 'bob-key', reviewerId: 'bob'}],
      ...resolve(checkpoint, 'rejected'),
    }), {code: 'InvalidResolution', cause: 'AuthorityNotPermitted'});
  });

test('failed revalidation with unknown Effect outcomes needs reconciliation',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const waiting = persist(journal);
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...resolve(stored(journal), 'approved')});
    const result = journal.claimResume('run-1', {
      claimant: 'worker-a', leaseMs: 1000, unknownEffects: ['effect-1'],
      binding: {...binding, environmentBindingCid: cid('e')},
    });
    assert.equal(result.runStatus, 'needs_reconciliation');
    const state = journal.getRunState('run-1');
    assert.equal(state.status, 'needs_reconciliation');
    assert.deepEqual(state.runState.next_action,
      {kind: 'reconcile', effects: ['effect-1']});
    assert.equal(state.runState.terminal_error.code,
      'ACTQL_E_RESUME_REVALIDATION_FAILED');
  });

test('a batch answers each Checkpoint independently and never widens',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const waiting = ['attempt-a', 'attempt-b', 'attempt-c'].map(attemptId =>
      persistPreparation(journal, prepareBody({attemptId,
        checkpointId: `cp-${attemptId}`})));
    const [a, b, c] = waiting.map(item =>
      storedWire(journal, item.checkpointCid));
    const before = counts(journal.path);
    // Two valid approvals and one answer signed for Checkpoint a but
    // submitted for c: one authentication cannot cover another subject.
    const batch = await journal.submitResolutions([
      {checkpointCid: a.checkpoint_cid, ...resolvePreparation(a, 'approved')},
      {checkpointCid: c.checkpoint_cid, ...resolvePreparation(a, 'approved')},
      {checkpointCid: b.checkpoint_cid,
        ...resolvePreparation(b, 'approved', {reviewer: 'bob'})},
    ]);
    assert.deepEqual(batch.map(item => item.status),
      ['committed', 'invalid', 'committed']);
    assert.equal(batch[1].reason, 'InvalidResolution');
    assert.match(batch[1].detail, /Mismatch/);
    assert.notEqual(batch[0].resumeIntentId, batch[2].resumeIntentId);
    // The invalid item left its Checkpoint and preparation untouched.
    assert.equal(journal.getPreparation('attempt-c').status,
      'waiting_checkpoint');
    assert.equal(journal.inspect(c.checkpoint_cid).closure, 'open');
    assert.deepEqual(counts(journal.path), {...before, resolutions: 2,
      intents: 2});

    // Resubmitting an answered item is idempotent for that item only; a
    // conflicting answer to another answered item is refused.
    const again = await journal.submitResolutions([
      {checkpointCid: a.checkpoint_cid, ...resolvePreparation(a, 'approved')},
      {checkpointCid: b.checkpoint_cid, ...resolvePreparation(b, 'rejected',
        {reviewer: 'alice'})},
      {checkpointCid: c.checkpoint_cid, ...resolvePreparation(c, 'rejected')},
    ]);
    assert.deepEqual(again.map(item => item.status),
      ['duplicate', 'conflicting', 'committed']);
    assert.equal(again[0].resumeIntentId, batch[0].resumeIntentId);
    assert.equal(journal.getPreparation('attempt-c').endReason, 'rejected');
    assert.deepEqual(counts(journal.path), {...before, resolutions: 3,
      intents: 2});

    // Each approved continuation starts exactly once.
    let starts = 0;
    for (const attemptId of ['attempt-a', 'attempt-b']) {
      for (const claimant of ['worker-1', 'worker-2']) {
        const claimed = journal.claimPreparationResume(attemptId,
          {claimant, leaseMs: 60_000, binding});
        if (claimed.action === 'claimed') starts++;
        else assert.equal(claimed.action, 'busy');
      }
    }
    assert.equal(starts, 2);
  });

test('cancel closes a waiting Checkpoint without a Run or resume intent',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const waiting = persistPreparation(journal);
    const checkpoint = stored(journal);
    const cancelled = journal.cancelCheckpoint(waiting.checkpointCid);
    assert.equal(cancelled.outcome, 'cancelled');
    assert.equal(cancelled.prepareAttemptId, 'attempt-1');
    assert.deepEqual(journal.cancelCheckpoint('cp-prep'),
      {outcome: 'duplicate', checkpointCid: waiting.checkpointCid});
    const preparation = journal.getPreparation('attempt-1');
    assert.equal(preparation.status, 'ended');
    assert.equal(preparation.endReason, 'cancelled');
    assert.equal(journal.inspect(waiting.checkpointCid).closure, 'cancelled');
    assert.equal(journal.listPending().length, 0);
    await assert.rejects(journal.submitResolution({
      checkpointCid: waiting.checkpointCid,
      ...resolvePreparation(checkpoint, 'approved'),
    }), {code: 'CheckpointCancelled'});
    assert.throws(() => journal.claimPreparationResume('attempt-1',
      {claimant: 'worker-a', leaseMs: 1000, binding}),
    {code: 'ResumeIntentNotFound'});
    assert.deepEqual(counts(journal.path), {runs: 0, checkpoints: 1,
      resolutions: 0, intents: 0, preparations: 1});

    // A waiting Run-unit Checkpoint cancels its Run.
    const unit = persist(journal);
    journal.cancelCheckpoint(unit.checkpointCid);
    assert.equal(journal.getRunState('run-1').status, 'cancelled');
    // An answered Checkpoint is not cancelled.
    const other = persistPreparation(journal, prepareBody({
      attemptId: 'attempt-2', checkpointId: 'cp-2'}));
    await journal.submitResolution({checkpointCid: other.checkpointCid,
      ...resolvePreparation(storedWire(journal, other.checkpointCid),
        'rejected')});
    assert.equal(journal.cancelCheckpoint(other.checkpointCid).outcome,
      'not_open');
  });

test('a directly created Run exits through a checked transition', async t => {
  const {open} = await workspace(t);
  const journal = open();
  const created = journal.createRun({runId: 'run-allow',
    declaredResults: ['tickets']});
  assert.equal(created.status, 'running');
  assert.throws(() => journal.createRun({runId: 'run-allow',
    declaredResults: ['tickets']}), {code: 'RunAlreadyTracked'});
  assert.throws(() => journal.finishRun('run-allow', {status: 'succeeded',
    from: 'preparing'}), {code: 'RunStateConflict'});
  const finished = journal.finishRun('run-allow', {status: 'succeeded'});
  assert.equal(finished.status, 'succeeded');
  assert.equal(finished.runState.status, 'succeeded');
  assert.throws(() => journal.finishRun('run-allow', {status: 'failed'}),
    {code: 'RunStateConflict'});
});

function storedWire(journal, checkpointCid) {
  const database = new DatabaseSync(journal.path, {readOnly: true});
  try {
    return JSON.parse(database.prepare(
      'SELECT checkpoint_wire FROM checkpoints WHERE checkpoint_cid = ?',
    ).get(checkpointCid).checkpoint_wire);
  } finally {
    database.close();
  }
}

test('rejection, expiry and cancellation preserve unknown earlier Effect outcomes',
  async t => {
    const {clock, open} = await workspace(t);
    const journal = open();
    const reconcile = (runId, effects) => {
      const state = journal.getRunState(runId);
      assert.equal(state.status, 'needs_reconciliation');
      assert.equal(state.runState.checkpoint, undefined);
      assert.deepEqual(state.runState.next_action,
        {kind: 'reconcile', effects});
      assert.equal(state.runState.terminal_error, undefined);
    };

    // Rejection while earlier Effects are unknown: no resume intent, the
    // continuation is not dispatched and the unknown facts stay visible.
    const rejected = persist(journal);
    const answer = await journal.submitResolution({
      checkpointCid: rejected.checkpointCid,
      ...resolve(stored(journal), 'rejected'),
      unknownEffects: ['effect-2', 'effect-1'],
    });
    assert.equal(answer.decision, 'rejected');
    assert.equal(answer.resumeIntentId, null);
    assert.equal(answer.runState.status, 'needs_reconciliation');
    reconcile('run-1', ['effect-2', 'effect-1']);
    assert.equal(journal.inspect(rejected.checkpointCid).closure, 'resolved');
    assert.throws(() => journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 1000, binding}),
    {code: 'ResumeIntentNotFound'});
    // Identical redelivery is idempotent and changes nothing.
    const again = await journal.submitResolution({
      checkpointCid: rejected.checkpointCid,
      ...resolve(storedWire(journal, rejected.checkpointCid), 'rejected'),
      unknownEffects: ['effect-2', 'effect-1'],
    });
    assert.equal(again.outcome, 'duplicate');
    reconcile('run-1', ['effect-2', 'effect-1']);

    // Approval resumes the same Run with a resume intent; the Run owner
    // keeps its Effect facts.
    const approved = persist(journal, effectBody({runId: 'run-2',
      checkpointId: 'cp-2'}));
    const permit = await journal.submitResolution({
      checkpointCid: approved.checkpointCid,
      ...resolve(storedWire(journal, approved.checkpointCid), 'approved'),
      unknownEffects: ['effect-1'],
    });
    assert.equal(permit.runState.status, 'resuming');
    assert.notEqual(permit.resumeIntentId, null);

    // Cancellation with and without unknown Effects.
    const cancelledUnknown = persist(journal, effectBody({runId: 'run-3',
      checkpointId: 'cp-3'}));
    const cancelled = journal.cancelCheckpoint(cancelledUnknown.checkpointCid,
      {unknownEffects: ['effect-9']});
    assert.equal(cancelled.runStatus, 'needs_reconciliation');
    reconcile('run-3', ['effect-9']);
    const cancelledPlain = persist(journal, effectBody({runId: 'run-4',
      checkpointId: 'cp-4'}));
    assert.equal(journal.cancelCheckpoint(cancelledPlain.checkpointCid)
      .runStatus, 'cancelled');
    const plainState = journal.getRunState('run-4');
    assert.equal(plainState.status, 'cancelled');
    assert.deepEqual(plainState.runState.next_action, {kind: 'none'});
    assert.equal(counts(journal.path).intents, 1);

    // Expiry sweep: only the Run with unknown Effects needs reconciliation.
    const expiring = ['run-5', 'run-6'].map(runId => persist(journal,
      effectBody({runId, checkpointId: `cp-${runId}`,
        expiresAt: '2026-09-25T11:00:00.000Z'})));
    clock.ms = T0 + HOUR;
    assert.deepEqual(journal.expire({unknownEffects: runId =>
      runId === 'run-5' ? ['effect-5'] : []}).sort(),
    expiring.map(item => item.checkpointCid).sort());
    reconcile('run-5', ['effect-5']);
    assert.equal(journal.getRunState('run-6').status, 'cancelled');

    // Expiry found while answering uses the answer's unknown Effects.
    clock.ms = T0;
    const late = persist(journal, effectBody({runId: 'run-7',
      checkpointId: 'cp-7', expiresAt: '2026-09-25T11:00:00.000Z'}));
    const lateAnswer = resolve(storedWire(journal, late.checkpointCid),
      'rejected', {decidedAt: '2026-09-25T10:30:00.000Z'});
    clock.ms = T0 + HOUR;
    await assert.rejects(journal.submitResolution({
      checkpointCid: late.checkpointCid, ...lateAnswer,
      unknownEffects: ['effect-7'],
    }), {code: 'CheckpointExpired'});
    reconcile('run-7', ['effect-7']);
    assert.equal(journal.inspect(late.checkpointCid).closure, 'expired');
  });

test('unknown Effects are validated and never apply to a preparation',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const unit = persist(journal);
    for (const unknownEffects of [['effect-1', 'effect-1'], [''], 'effect-1']) {
      assert.throws(() => journal.cancelCheckpoint(unit.checkpointCid,
        {unknownEffects}), {code: 'InvalidUnknownEffects'});
      await assert.rejects(journal.submitResolution({
        checkpointCid: unit.checkpointCid,
        ...resolve(stored(journal), 'rejected'), unknownEffects,
      }), {code: 'InvalidUnknownEffects'});
    }
    assert.equal(journal.getRunState('run-1').status, 'waiting_checkpoint');
    const preparation = persistPreparation(journal);
    assert.throws(() => journal.cancelCheckpoint(preparation.checkpointCid,
      {unknownEffects: ['effect-1']}), {code: 'InvalidUnknownEffects'});
    await assert.rejects(journal.submitResolution({
      checkpointCid: preparation.checkpointCid,
      ...resolvePreparation(storedWire(journal, preparation.checkpointCid),
        'rejected'),
      unknownEffects: ['effect-1'],
    }), {code: 'InvalidUnknownEffects'});
    assert.equal(journal.getPreparation('attempt-1').status,
      'waiting_checkpoint');
    assert.deepEqual(counts(journal.path), {runs: 1, checkpoints: 2,
      resolutions: 0, intents: 0, preparations: 1});
  });

test('a decision-subject binding is stored next to its Checkpoint',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const bound = journal.persistCheckpoint({
      body: effectBody(), priorStatus: 'running', declaredResults: ['tickets'],
      authorities, binding, decisionSubjectCid: cid('9'),
    });
    const view = journal.inspect(bound.checkpointCid);
    assert.equal(view.decisionSubjectCid, cid('9'));
    // The sealed required artifact is the body's own, untouched.
    assert.equal(view.requiredArtifact.cid, cid('3'));
    // An idempotent retry must name the same binding.
    assert.throws(() => journal.persistCheckpoint({
      body: effectBody(), priorStatus: 'running', declaredResults: ['tickets'],
      authorities, binding, decisionSubjectCid: cid('8'),
    }), {code: 'CheckpointConflict'});
    assert.throws(() => journal.persistCheckpoint({
      body: effectBody({runId: 'run-2'}), priorStatus: 'running',
      declaredResults: ['tickets'], authorities, binding,
      decisionSubjectCid: 'not-a-cid',
    }), {code: 'InvalidDecisionSubjectBinding'});
    const unbound = persist(journal, effectBody({runId: 'run-3'}));
    assert.equal(journal.inspect(unbound.checkpointCid).decisionSubjectCid,
      null);
  });

test('a prior private layout without decision-subject storage is refused unchanged',
  async t => {
    const {open} = await workspace(t);
    const first = open();
    const waiting = persist(first);
    first.close();
    const database = new DatabaseSync(first.path);
    database.exec('ALTER TABLE checkpoints DROP COLUMN decision_subject_cid');
    database.prepare('UPDATE journal_metadata SET value = ? WHERE key = ?')
      .run('actql-checkpoint-journal/0.1', 'schema_version');
    const retained = database.prepare('SELECT checkpoint_wire FROM checkpoints WHERE checkpoint_cid = ?')
      .get(waiting.checkpointCid).checkpoint_wire;
    database.close();
    const before = readFileSync(first.path);
    assert.throws(() => open(), {code: 'UnsupportedCheckpointJournal'});
    assert.deepEqual(readFileSync(first.path), before);
    const unchanged = new DatabaseSync(first.path);
    assert.equal(unchanged.prepare('SELECT checkpoint_wire FROM checkpoints WHERE checkpoint_cid = ?')
      .get(waiting.checkpointCid).checkpoint_wire, retained);
    assert.equal(unchanged.prepare('PRAGMA table_info(checkpoints)').all()
      .some(column => column.name === 'decision_subject_cid'), false);
    unchanged.close();
  });

for (const admitted of [false, true]) {
test(`preparation refusal fences only an unsent Effect (admitted=${admitted})`,
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const waiting = persist(journal);
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...resolve(stored(journal), 'approved')});
    const first = journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 60_000, binding});
    if (admitted) journal.enterResumedDispatch(first.claim,
      {dispatchIdentity: 'effect-dispatch-a'});
    assert.throws(() => journal.refuseUnsentEffectResume(
      waiting.checkpointCid, cid('2')), {code: 'CheckpointRunMismatch'});
    assert.equal(journal.refuseUnsentEffectResume(
      waiting.checkpointCid, cid('1')).outcome,
    admitted ? 'admitted' : 'failed');
    assert.equal(journal.getRunState('run-1').status,
      admitted ? 'resuming' : 'failed');
    if (!admitted) assert.throws(() => journal.enterResumedDispatch(
      first.claim), {code: 'ResumeClaimStale'});
    journal.close();
    const reopened = open();
    assert.equal(reopened.refuseUnsentEffectResume(
      waiting.checkpointCid, cid('1')).outcome,
    admitted ? 'admitted' : 'not_resuming');
    assert.equal(reopened.getRunState('run-1').status,
      admitted ? 'resuming' : 'failed');
  });
}

test('cancellation fences an unsent resume but preserves admitted work',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const waiting = persist(journal);
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...resolve(stored(journal), 'approved')});
    const first = journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 60_000, binding});
    assert.equal(journal.cancelUnsentResume(waiting.checkpointCid).outcome,
      'cancelled');
    assert.equal(journal.getRunState('run-1').status, 'cancelled');
    assert.throws(() => journal.enterResumedDispatch(first.claim),
      {code: 'ResumeClaimStale'});
    assert.deepEqual(journal.claimResume('run-1',
      {claimant: 'worker-b', leaseMs: 60_000, binding}),
    {action: 'completed'});
    assert.equal(journal.cancelUnsentResume(waiting.checkpointCid).outcome,
      'not_resuming');
  });

test('cancellation does not terminalize an admitted unknown dispatch',
  async t => {
    const {open} = await workspace(t);
    const journal = open();
    const waiting = persist(journal);
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...resolve(stored(journal), 'approved')});
    const first = journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 60_000, binding});
    journal.enterResumedDispatch(first.claim,
      {dispatchIdentity: 'effect-dispatch-a'});
    assert.equal(journal.cancelUnsentResume(waiting.checkpointCid).outcome,
      'admitted');
    journal.close();
    const restarted = open();
    assert.equal(restarted.getRunState('run-1').status, 'resuming');
    assert.equal(restarted.cancelUnsentResume(waiting.checkpointCid).outcome,
      'admitted');
    assert.equal(restarted.currentResume(waiting.checkpointCid).state,
      'claimed');
  });

test('resumed dispatch admission reads the live claim and committed approval',
  async t => {
    const {clock, open} = await workspace(t);
    const journal = open();
    const waiting = journal.persistCheckpoint({
      body: effectBody(), priorStatus: 'running', declaredResults: ['tickets'],
      authorities, binding, decisionSubjectCid: cid('9'),
      requestedClaims: ['partial_application_accepted', 'effect_scope_approved'],
    });
    assert.deepEqual(journal.inspect(waiting.checkpointCid).requestedClaims,
      ['effect_scope_approved', 'partial_application_accepted']);
    assert.equal(journal.currentResume(waiting.checkpointCid), undefined);
    const approved = await journal.submitResolution({
      checkpointCid: waiting.checkpointCid,
      ...resolve(stored(journal), 'approved'),
    });
    const pending = journal.currentResume(waiting.checkpointCid);
    assert.equal(pending.intentId, approved.resumeIntentId);
    assert.equal(pending.state, 'pending');
    assert.equal(pending.generation, 0);
    assert.equal(pending.claimant, '');
    assert.equal(pending.resolutionCid, approved.resolutionCid);
    assert.equal(pending.decision, 'approved');

    // No claim, a guessed claim of the pending intent, or another intent
    // are not the live claim.
    for (const [claim, code] of [
      [undefined, 'ResumeNotClaimed'],
      [{runId: 'run-1'}, 'ResumeNotClaimed'],
      [{intentId: pending.intentId, claimant: 'worker-a', generation: 0},
        'ResumeClaimStale'],
      [{intentId: cid('f'), claimant: 'worker-a', generation: 1},
        'ResumeIntentNotFound'],
    ]) {
      assert.throws(() => journal.admitResume(claim), {code}, code);
      assert.throws(() => journal.enterResumedDispatch(claim), {code}, code);
    }
    const first = journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 1000, binding});
    const admission = journal.admitResume(first.claim,
      {checkpointCid: waiting.checkpointCid});
    assert.equal(admission.intentId, pending.intentId);
    assert.equal(admission.runId, 'run-1');
    assert.equal(admission.checkpointCid, waiting.checkpointCid);
    assert.equal(admission.resolutionCid, approved.resolutionCid);
    assert.equal(admission.verifiedResolutionCid,
      approved.verifiedResolutionCid);
    assert.equal(admission.claimant, 'worker-a');
    assert.equal(admission.generation, 1);
    assert.equal(admission.leaseExpiresMs, first.claim.leaseExpiresMs);
    assert.equal(admission.decisionSubjectCid, cid('9'));
    assert.equal(admission.requiredArtifactCid, cid('3'));
    assert.equal(admission.authority, 'alice');
    // Observed claims come from the committed evidence; an Effect Set
    // attestation has no expiry of its own.
    assert.deepEqual(admission.observedClaims,
      ['effect_scope_approved', 'partial_application_accepted']);
    assert.deepEqual(admission.requestedClaims,
      ['effect_scope_approved', 'partial_application_accepted']);
    assert.equal(admission.approvalExpiresAt, null);
    assert.throws(() => journal.admitResume(first.claim,
      {checkpointCid: cid('e')}), {code: 'ResumeIntentMismatch'});
    assert.throws(() => journal.admitResume({...first.claim, claimant: 'x'}),
      {code: 'ResumeClaimStale'});
    assert.throws(() => journal.admitResume({...first.claim, generation: 2}),
      {code: 'ResumeClaimStale'});

    // One protected dispatch start per claim generation.
    const entered = journal.enterResumedDispatch(first.claim,
      {checkpointCid: waiting.checkpointCid,
        resolutionCid: approved.resolutionCid});
    assert.equal(entered.generation, 1);
    assert.throws(() => journal.enterResumedDispatch(first.claim),
      {code: 'ResumeAdmissionConsumed'});
    // The lease expires: the old claimant is fenced out of every admission.
    clock.ms += 1000;
    assert.throws(() => journal.admitResume(first.claim),
      {code: 'ResumeClaimStale'});
    const second = journal.claimResume('run-1',
      {claimant: 'worker-b', leaseMs: 60_000, binding});
    assert.equal(second.claim.generation, 2);
    assert.throws(() => journal.enterResumedDispatch(first.claim),
      {code: 'ResumeClaimStale'});
    assert.throws(() => journal.enterResumedDispatch(second.claim,
      {resolutionCid: cid('e')}), {code: 'ResolutionNotCommitted'});
    // Generation 1 entered a protected dispatch with no durable identity
    // and never completed: generation 2 gets no fresh start and nothing to
    // reconcile.
    assert.throws(() => journal.enterResumedDispatch(second.claim),
      {code: 'PriorAdmissionUnresolved'});
    assert.throws(() => journal.enterResumedReconciliation(second.claim,
      {dispatchIdentity: 'dispatch-a'}), {code: 'PriorAdmissionUnresolved'});
    const current = journal.currentResume(waiting.checkpointCid);
    assert.equal(current.state, 'claimed');
    assert.equal(current.claimant, 'worker-b');
    assert.equal(current.generation, 2);
    // A completed intent admits nothing.
    journal.completeResume(second.claim, {status: 'cancelled'});
    assert.throws(() => journal.admitResume(second.claim),
      {code: 'ResumeClaimStale'});
  });

test('a lease handoff after an entered admission cannot admit a second start',
  async t => {
    const {clock, open, root} = await workspace(t);
    const journal = open();
    const waiting = journal.persistCheckpoint({
      body: effectBody(), priorStatus: 'running', declaredResults: ['tickets'],
      authorities, binding, decisionSubjectCid: cid('9'),
      requestedClaims: ['effect_scope_approved'],
    });
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...resolve(stored(journal), 'approved')});
    const at = {checkpointCid: waiting.checkpointCid};
    // Generation 1 enters its protected dispatch (durable identity
    // `dispatch-a`) and then its lease lapses without a completion.
    const first = journal.claimResume('run-1',
      {claimant: 'worker-a', leaseMs: 1000, binding});
    const entered = journal.enterResumedDispatch(first.claim,
      {...at, dispatchIdentity: 'dispatch-a'});
    assert.equal(entered.mode, 'start');
    assert.equal(entered.dispatchIdentity, 'dispatch-a');
    clock.ms += 1000;
    const second = journal.claimResume('run-1',
      {claimant: 'worker-b', leaseMs: 1000, binding});
    assert.equal(second.claim.generation, 2);
    // No fresh start, with or without an identity, after reopening too.
    let refused;
    try {
      journal.enterResumedDispatch(second.claim,
        {...at, dispatchIdentity: 'dispatch-b'});
    } catch (error) { refused = error; }
    assert.equal(refused?.code, 'PriorAdmissionUnresolved');
    assert.deepEqual({...refused.priorAdmission, admittedAt: undefined},
      {generation: 1, claimant: 'worker-a', admittedAt: undefined,
        dispatchIdentity: 'dispatch-a'});
    journal.close();
    const reopened = open();
    assert.throws(() => reopened.enterResumedDispatch(second.claim, at),
      {code: 'PriorAdmissionUnresolved'});
    // Reconciliation admits only the same durable dispatch identity.
    assert.throws(() => reopened.enterResumedReconciliation(second.claim, at),
      {code: 'ReconciliationIdentityRequired'});
    assert.throws(() => reopened.enterResumedReconciliation(second.claim,
      {...at, dispatchIdentity: 'dispatch-b'}),
    {code: 'ReconciliationIdentityMismatch'});
    const reconciled = reopened.enterResumedReconciliation(second.claim,
      {...at, dispatchIdentity: 'dispatch-a'});
    assert.equal(reconciled.mode, 'reconcile');
    assert.equal(reconciled.generation, 2);
    assert.equal(reconciled.dispatchIdentity, 'dispatch-a');
    assert.equal(reconciled.priorAdmission.generation, 1);
    // One entry per generation, reconciliation included.
    assert.throws(() => reopened.enterResumedReconciliation(second.claim,
      {...at, dispatchIdentity: 'dispatch-a'}),
    {code: 'ResumeAdmissionConsumed'});
    // A later generation still reconciles against the first start only.
    clock.ms += 1000;
    const third = reopened.claimResume('run-1',
      {claimant: 'worker-c', leaseMs: 1000, binding});
    assert.throws(() => reopened.enterResumedDispatch(third.claim, at),
      {code: 'PriorAdmissionUnresolved'});
    assert.equal(reopened.enterResumedReconciliation(third.claim,
      {...at, dispatchIdentity: 'dispatch-a'}).priorAdmission.generation, 1);
    // The durable admissions: one start, then reconciliations of it.
    const sqlite = new DatabaseSync(join(root, 'checkpoint-journal.sqlite3'),
      {readOnly: true});
    try {
      assert.deepEqual(sqlite.prepare(`SELECT generation, mode,
        dispatch_identity FROM resume_admissions ORDER BY generation`).all()
        .map(row => ({...row})), [
        {generation: 1, mode: 'start', dispatch_identity: 'dispatch-a'},
        {generation: 2, mode: 'reconcile', dispatch_identity: 'dispatch-a'},
        {generation: 3, mode: 'reconcile', dispatch_identity: 'dispatch-a'},
      ]);
    } finally { sqlite.close(); }
  });

test('reconciliation needs an earlier started admission', async t => {
  const {open} = await workspace(t);
  const journal = open();
  const waiting = journal.persistCheckpoint({
    body: effectBody(), priorStatus: 'running', declaredResults: ['tickets'],
    authorities, binding, decisionSubjectCid: cid('9'),
    requestedClaims: ['effect_scope_approved'],
  });
  await journal.submitResolution({checkpointCid: waiting.checkpointCid,
    ...resolve(stored(journal), 'approved')});
  const first = journal.claimResume('run-1',
    {claimant: 'worker-a', leaseMs: 1000, binding});
  assert.throws(() => journal.enterResumedReconciliation(first.claim,
    {dispatchIdentity: 'dispatch-a'}), {code: 'NoPriorAdmission'});
  assert.equal(journal.enterResumedDispatch(first.claim,
    {dispatchIdentity: 'dispatch-a'}).mode, 'start');
});

test('a resumed approval stops admitting new work at its own expiry',
  async t => {
    const {clock, open} = await workspace(t);
    const journal = open();
    const waiting = persistPreparation(journal);
    clock.ms = T0 + HOUR;
    // The permission lapses two hours after the answer, well before the
    // Checkpoint's own answer deadline and independently of any lease.
    await journal.submitResolution({checkpointCid: waiting.checkpointCid,
      ...resolvePreparation(stored(journal), 'approved',
        {approvalExpiresAt: '2026-09-25T13:00:00.000Z'})});
    const expiry = Date.parse('2026-09-25T13:00:00.000Z');
    clock.ms = expiry - 10_000;
    const {claim} = journal.claimPreparationResume('attempt-1',
      {claimant: 'worker-a', leaseMs: 60_000, binding});
    const admission = journal.admitResume(claim);
    assert.equal(admission.prepareAttemptId, 'attempt-1');
    assert.equal(admission.runId, null);
    assert.deepEqual(admission.observedClaims, ['invocation_scope_approved']);
    assert.equal(admission.approvalExpiresAt, '2026-09-25T13:00:00.000Z');
    clock.ms = expiry - 1;
    assert.equal(journal.admitResume(claim).generation, 1);
    // The exact expiry instant, with the lease still live.
    clock.ms = expiry;
    assert.throws(() => journal.admitResume(claim), {code: 'ApprovalExpired'});
    assert.throws(() => journal.enterResumedDispatch(claim),
      {code: 'ApprovalExpired'});
    // The historical Resolution is kept and the preparation still exits
    // through its owner.
    assert.equal(journal.resolutionOf(waiting.checkpointCid).decision,
      'approved');
    assert.equal(journal.getPreparation('attempt-1').status, 'resuming');
    assert.equal(journal.completeResume(claim, {status: 'failed'})
      .preparation.status, 'ended');
  });

test('the commit decision rereads trusted time after slow authentication',
  async t => {
    const {root, clock} = await workspace(t);
    const opened = [];
    t.after(() => { for (const journal of opened) journal.close(); });
    const slow = ({authorizeMs = 0, attestMs = 0}) => {
      const journal = openSqliteCheckpointJournal(root, {
        runtime, expectedAuthorityScopeCid: cid('5'),
        now: () => clock.ms,
        async authorizeResolution(request) {
          await new Promise(resolve => setImmediate(resolve));
          clock.ms += authorizeMs;
          return authorizeResolution(request);
        },
        async attestResolution(preimage) {
          await new Promise(resolve => setImmediate(resolve));
          clock.ms += attestMs;
          return attestResolution(preimage);
        },
      });
      opened.push(journal);
      return journal;
    };
    // The Checkpoint answer deadline passes during authentication: the
    // answer was decided in time but is not committed, and the waiting Run
    // closes as expired with no resume intent.
    const late = slow({authorizeMs: 2 * HOUR});
    const deadline = persist(late, effectBody({
      expiresAt: '2026-09-25T11:00:00.000Z'}));
    clock.ms = T0 + HOUR - 1000;
    await assert.rejects(late.submitResolution({
      checkpointCid: deadline.checkpointCid,
      ...resolve(stored(late), 'approved',
        {decidedAt: '2026-09-25T10:59:59.000Z'}),
    }), {code: 'CheckpointExpired'});
    assert.equal(late.inspect(deadline.checkpointCid).closure, 'expired');
    assert.equal(late.getRunState('run-1').status, 'cancelled');
    assert.equal(late.currentResume(deadline.checkpointCid), undefined);

    // The approval's own permission lapses during attestation: nothing is
    // committed and the Checkpoint keeps waiting within its deadline.
    clock.ms = T0 + 3 * HOUR;
    const lapsing = slow({attestMs: 2 * HOUR});
    const waiting = persistPreparation(lapsing, prepareBody({
      attemptId: 'attempt-9', checkpointId: 'cp-lapse'}));
    const database = new DatabaseSync(lapsing.path, {readOnly: true});
    const checkpoint = JSON.parse(database.prepare(
      'SELECT checkpoint_wire FROM checkpoints WHERE checkpoint_cid = ?',
    ).get(waiting.checkpointCid).checkpoint_wire);
    database.close();
    await assert.rejects(lapsing.submitResolution({
      checkpointCid: waiting.checkpointCid,
      ...resolvePreparation(checkpoint, 'approved',
        {approvalExpiresAt: '2026-09-25T14:00:00.000Z'}),
    }), {code: 'ApprovalExpired'});
    assert.equal(lapsing.inspect(waiting.checkpointCid).closure, 'open');
    assert.equal(lapsing.resolutionOf(waiting.checkpointCid), undefined);
    assert.equal(lapsing.getPreparation('attempt-9').status,
      'waiting_checkpoint');
    assert.equal(lapsing.currentResume(waiting.checkpointCid), undefined);
  });

test('a prior private layout without requested-claims storage is refused unchanged',
  async t => {
    const {open} = await workspace(t);
    const first = open();
    const waiting = persist(first);
    first.close();
    const database = new DatabaseSync(first.path);
    database.exec('ALTER TABLE checkpoints DROP COLUMN requested_claims_json');
    database.exec('DROP TABLE resume_admissions');
    database.prepare('UPDATE journal_metadata SET value = ? WHERE key = ?')
      .run('actql-checkpoint-journal/0.1', 'schema_version');
    const retained = database.prepare('SELECT checkpoint_wire FROM checkpoints WHERE checkpoint_cid = ?')
      .get(waiting.checkpointCid).checkpoint_wire;
    database.close();
    const before = readFileSync(first.path);
    assert.throws(() => open(), {code: 'UnsupportedCheckpointJournal'});
    assert.deepEqual(readFileSync(first.path), before);
    const unchanged = new DatabaseSync(first.path);
    assert.equal(unchanged.prepare('SELECT checkpoint_wire FROM checkpoints WHERE checkpoint_cid = ?')
      .get(waiting.checkpointCid).checkpoint_wire, retained);
    assert.equal(unchanged.prepare("SELECT name FROM sqlite_schema WHERE name = 'resume_admissions'").get(), undefined);
    unchanged.close();
  });

test('pending Checkpoints page by a stable cursor; resumable preparations and their Runs are listed',
  async t => {
    const {clock, open} = await workspace(t);
    const journal = open();
    const waiting = [];
    for (const index of [1, 2, 3]) {
      clock.ms += 1000;
      waiting.push(persistPreparation(journal, prepareBody({
        attemptId: `attempt-${index}`, checkpointId: `cp-prep-${index}`})));
    }
    const first = journal.listPending({limit: 2});
    assert.deepEqual(first.map(view => view.checkpointCid),
      waiting.slice(0, 2).map(view => view.checkpointCid));
    const second = journal.listPending({after: first.at(-1).cursor, limit: 2});
    assert.deepEqual(second.map(view => view.checkpointCid),
      [waiting[2].checkpointCid]);
    assert.deepEqual(journal.listPending({after: second.at(-1).cursor,
      limit: 2}), []);
    // The unpaged listing is unchanged: every waiting one, no cursor.
    assert.equal(journal.listPending().length, 3);
    assert.equal('cursor' in journal.listPending()[0], false);
    for (const bad of [{limit: 0}, {limit: 1001}, {after: 'x', limit: 1},
      {after: first[0].cursor}]) {
      assert.throws(() => journal.listPending(bad),
        {code: 'InvalidCheckpointPage'});
    }
    // Only an approved preparation with an uncompleted intent is resumable.
    assert.deepEqual(journal.listResumablePreparations(), []);
    const [approved, rejected] = [0, 1].map(index =>
      storedWire(journal, waiting[index].checkpointCid));
    await journal.submitResolution({checkpointCid: approved.checkpoint_cid,
      ...resolvePreparation(approved, 'approved')});
    await journal.submitResolution({checkpointCid: rejected.checkpoint_cid,
      ...resolvePreparation(rejected, 'rejected')});
    assert.deepEqual(journal.listResumablePreparations(), ['attempt-1']);
    assert.equal(journal.listPending().length, 1);
    const claimed = journal.claimPreparationResume('attempt-1',
      {claimant: 'host-a', leaseMs: 1000, binding});
    // A claimed but uncompleted intent stays a candidate (its claimant may
    // have died); the claim still decides who continues.
    assert.deepEqual(journal.listResumablePreparations(), ['attempt-1']);
    // Pages continue after the previous page's last attempt.
    assert.deepEqual(journal.listResumablePreparations({after: 'attempt-1'}),
      []);
    assert.deepEqual(journal.listPreparationRuns(), []);
    journal.completeResume(claimed.claim, {run: {runId: 'run-1',
      status: 'running'}});
    assert.deepEqual(journal.listResumablePreparations(), []);
    // The created Run keeps a durable execution duty until it ends.
    assert.deepEqual(journal.listPreparationRuns(),
      [{prepareAttemptId: 'attempt-1', runId: 'run-1'}]);
    assert.deepEqual(journal.listPreparationRuns({after: 'attempt-1'}), []);
    journal.finishRun('run-1', {status: 'succeeded'});
    assert.deepEqual(journal.listPreparationRuns(), []);
    assert.throws(() => journal.listResumablePreparations({limit: 0}),
      {code: 'InvalidResumableLimit'});
    assert.throws(() => journal.listPreparationRuns({limit: 0}),
      {code: 'InvalidPreparationRunPage'});
  });

test('a request cancellation is durable and ends or marks the preparation',
  async t => {
    const {clock, open} = await workspace(t);
    const journal = open();
    const [waiting, resuming, rejected] = ['a', 'b', 'c'].map(id => {
      clock.ms += 1000;
      return persistPreparation(journal, prepareBody({
        attemptId: `attempt-${id}`, checkpointId: `cp-${id}`}));
    });
    // Waiting: the Checkpoint closes as cancelled and the preparation ends
    // cancelled; a later answer is `cancelled`, never a resume.
    const first = journal.requestPreparationCancellation('attempt-a');
    assert.equal(first.outcome, 'accepted');
    assert.equal(first.preparation.status, 'ended');
    assert.equal(first.preparation.endReason, 'cancelled');
    assert.equal(first.preparation.cancelRequested, true);
    assert.equal(journal.inspect(waiting.checkpointCid).closure, 'cancelled');
    const late = await journal.submitResolutions([{
      checkpointCid: waiting.checkpointCid,
      ...resolvePreparation(storedWire(journal, waiting.checkpointCid),
        'approved')}]);
    assert.equal(late[0].status, 'cancelled');
    assert.deepEqual(journal.listResumablePreparations(), []);
    // Repeating it is idempotent.
    assert.equal(journal.requestPreparationCancellation('attempt-a').outcome,
      'already_requested');
    // Resuming (approved first): the durable request stays for the resume
    // owner; nothing else changes.
    await journal.submitResolution({checkpointCid: resuming.checkpointCid,
      ...resolvePreparation(storedWire(journal, resuming.checkpointCid),
        'approved')});
    const marked = journal.requestPreparationCancellation('attempt-b');
    assert.equal(marked.outcome, 'accepted');
    assert.equal(marked.preparation.status, 'resuming');
    assert.equal(marked.preparation.cancelRequested, true);
    assert.equal(journal.getPreparation('attempt-b').cancelRequested, true);
    assert.equal(journal.requestPreparationCancellation('attempt-b').outcome,
      'already_requested');
    // Ended otherwise: already terminal, unchanged.
    await journal.submitResolution({checkpointCid: rejected.checkpointCid,
      ...resolvePreparation(storedWire(journal, rejected.checkpointCid),
        'rejected')});
    const terminal = journal.requestPreparationCancellation('attempt-c');
    assert.equal(terminal.outcome, 'already_terminal');
    assert.equal(terminal.preparation.cancelRequested, false);
    assert.throws(() => journal.requestPreparationCancellation('attempt-x'),
      {code: 'PreparationNotFound'});
  });
