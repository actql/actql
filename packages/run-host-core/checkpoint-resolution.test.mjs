import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign, verify} from 'node:crypto';
import test from 'node:test';
import {checkpointSealBody, checkpointExpiredAt, resolutionProofPreimage,
  resolutionAdmit, resolutionDecide, verifiedAttestationPreimage,
  resumedApprovalAt, effectResumeClaimDecide, resumeFenceDecide,
  runTransitionAllowed, resumeCompletionAllowed, effectSettlementCompletionAllowed}
  from '@actql/run-host-core/checkpoints';

// Independent ASCII fixture identities, verified against the actual Owner.
const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']' :
  value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
    .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const fixed = character => 'sha256:' + character.repeat(64);
const core = wire => {const value = JSON.parse(wire); assert.equal(value.ok, true, value.issue); return value;};
const at = '2026-09-25T11:00:00.000Z';
const reviewer = generateKeyPairSync('ed25519');
const host = generateKeyPairSync('ed25519');
const body = {
  version: 'actql-execution-checkpoint/0.1', checkpoint_id: 'effect-review',
  run_id: 'original-run', run_definition_cid: fixed('1'), continuation_state_cid: fixed('2'),
  subject: {kind: 'run_unit', run_id: 'original-run', unit_id: 'compute', continuation: 'resume_unit'},
  phase: 'commit', kind: 'effect_set',
  required_artifact: {artifact_type: 'effect_set_preview', artifact_cid: fixed('3')},
  review_projection_cid: fixed('4'), requirements: ['effect_scope_approved'],
  reason_code: 'effect_review_required', human_summary: 'Update identity 3',
  created_at: '2026-09-25T10:00:00.000Z', expires_at: '2026-09-26T10:00:00.000Z',
};
const sealed = core(checkpointSealBody(JSON.stringify(body)));
const checkpoint = JSON.parse(sealed.checkpoint_wire);
const authorities = JSON.stringify([{key_id: 'reviewer-key', reviewer_id: 'alice'}]);
const signature = (value, key) => sign(null, Buffer.from(value), key).toString('base64');

function resolution(decision = 'approved', id = 'answer') {
  const attestation = {version: 'actql-approval-attestation/0.1',
    effect_preview_cid: body.required_artifact.artifact_cid,
    review_projection_cid: body.review_projection_cid, approver: 'alice',
    approved_at: at, authority_scope_cid: fixed('5'), claims: [...body.requirements]};
  attestation.proof = {scheme: 'ed25519-v1', key_id: 'reviewer-key',
    signature: signature(cid(attestation), reviewer.privateKey)};
  attestation.attestation_cid = cid(attestation);
  const evidence = {version: 'actql-checkpoint-approval-evidence/0.1', kind: 'effect_set',
    checkpoint_cid: checkpoint.checkpoint_cid, review_projection_cid: body.review_projection_cid,
    compatibility_approval: attestation};
  const answer = {version: 'actql-checkpoint-resolution/0.1', resolution_id: id,
    checkpoint_id: body.checkpoint_id, checkpoint_cid: checkpoint.checkpoint_cid,
    run_id: body.run_id, run_definition_cid: body.run_definition_cid, decision,
    actor: 'alice', decided_at: at, required_artifact_cid: body.required_artifact.artifact_cid,
    review_projection_cid: body.review_projection_cid,
    ...(decision === 'approved' ? {approval_evidence_cid: cid(evidence)} : {})};
  const preimage = cid(answer);
  answer.proof = {scheme: 'ed25519-v1', key_id: 'reviewer-key',
    signature: signature(preimage, reviewer.privateKey)};
  answer.resolution_cid = cid(answer);
  const wire = JSON.stringify(answer);
  const actual = core(resolutionProofPreimage(wire)).preimage;
  assert.equal(actual, preimage);
  assert.equal(verify(null, Buffer.from(actual), reviewer.publicKey,
    Buffer.from(answer.proof.signature, 'base64')), true);
  const unsignedApproval = {...attestation};
  delete unsignedApproval.proof;
  delete unsignedApproval.attestation_cid;
  assert.equal(verify(null, Buffer.from(cid(unsignedApproval)), reviewer.publicKey,
    Buffer.from(attestation.proof.signature, 'base64')), true);
  const authentication = JSON.stringify({key_id: 'reviewer-key', reviewer_id: 'alice',
    expected_authority_scope_cid: fixed('5'), authority_context_cid: fixed('6'),
    policy_cid: fixed('7'), proof_preimage: actual});
  return {wire, evidenceWire: decision === 'approved' ? JSON.stringify(evidence) : '', authentication};
}

function decide(answer, closure = 'open', savedCid = '', unknown = [], verifiedAt = at) {
  const admission = core(resolutionAdmit(sealed.checkpoint_wire, answer.wire,
    answer.evidenceWire, answer.authentication, authorities, verifiedAt));
  const proof = signature(admission.attestation_preimage, host.privateKey);
  const decided = core(resolutionDecide(sealed.checkpoint_wire, answer.wire,
    answer.evidenceWire, answer.authentication, authorities, verifiedAt, 'host-key', proof,
    closure, savedCid, JSON.stringify(unknown)));
  const preimage = core(verifiedAttestationPreimage(decided.verified_resolution_wire)).preimage;
  assert.equal(preimage, admission.attestation_preimage);
  assert.equal(verify(null, Buffer.from(preimage), host.publicKey, Buffer.from(proof, 'base64')), true);
  return decided;
}

test('formal Resolution APIs retain the original Run and signed approval', () => {
  assert.equal(sealed.checkpoint_cid, cid(body));
  const decided = decide(resolution());
  assert.equal(decided.action, 'commit');
  assert.equal(decided.decision, 'approved');
  assert.equal(decided.run_status, 'resuming');
  assert.equal(typeof decided.resume_intent_id, 'string');
  assert.equal(JSON.parse(decided.verified_resolution_wire).resolution.run_id, 'original-run');
  const approval = core(resumedApprovalAt(decided.verified_resolution_wire, at));
  assert.equal(approval.checkpoint_cid, sealed.checkpoint_cid);
  assert.deepEqual(approval.claims, ['effect_scope_approved']);
  assert.equal(approval.current, true);
});

test('the Owner decides duplicate and conflicting answers against saved closure', () => {
  const answer = resolution();
  const first = decide(answer);
  assert.equal(decide(answer, 'resolved', first.resolution_cid).action, 'duplicate');
  assert.equal(decide(resolution('approved', 'other-answer'), 'resolved', first.resolution_cid).action, 'conflict');
  const rejected = decide(resolution('rejected'), 'open', '', ['unknown-effect']);
  assert.equal(rejected.run_status, 'needs_reconciliation');
  assert.equal(rejected.resume_intent_id, null);
});

test('foreign authority and changed evidence are refused; expiry prevents commit', () => {
  const answer = resolution();
  assert.equal(JSON.parse(resolutionAdmit(sealed.checkpoint_wire, answer.wire,
    answer.evidenceWire, answer.authentication, '[]', at)).ok, false);
  const changed = JSON.parse(answer.evidenceWire);
  changed.compatibility_approval.authority_scope_cid = fixed('8');
  assert.equal(JSON.parse(resolutionAdmit(sealed.checkpoint_wire, answer.wire,
    JSON.stringify(changed), answer.authentication, authorities, at)).ok, false);
  assert.equal(core(checkpointExpiredAt(sealed.checkpoint_wire, '2026-09-26T10:00:01.000Z')).expired, true);
  // Admission checks the signed decision window. Commit separately checks
  // verification time and closure; admission alone is not permission to resume.
  const late = '2026-09-26T10:00:01.000Z';
  assert.equal(decide(answer, 'open', '', [], late).action, 'expired');
  assert.equal(decide(answer, 'expired').action, 'expired');
});

test('Effect continuation preserves claim generation, stale fences and settlement', () => {
  const intent = {state: 'pending', generation: 0, lease_expires_ms: 0, claimant: ''};
  const binding = {authorization_context_cid: fixed('a'), environment_binding_cid: fixed('b')};
  const bound = JSON.stringify(binding);
  const claim = core(effectResumeClaimDecide(JSON.stringify(intent), 'holder', 1000, 1000, bound, bound, false));
  assert.equal(claim.action, 'claim');
  assert.equal(claim.generation, 1);
  const owned = {...intent, state: 'claimed', generation: claim.generation,
    lease_expires_ms: claim.lease_expires_ms, claimant: 'holder'};
  assert.equal(core(resumeFenceDecide(JSON.stringify(owned), 'holder', 1, 1999)).action, 'current');
  assert.equal(core(resumeFenceDecide(JSON.stringify(owned), 'holder', 0, 1999)).action, 'stale');
  assert.equal(core(resumeFenceDecide(JSON.stringify(owned), 'holder', 1, 2000)).action, 'stale');
  const changed = JSON.stringify({...binding, authorization_context_cid: fixed('c')});
  assert.equal(core(effectResumeClaimDecide(JSON.stringify(intent), 'holder', 1000, 1000,
    bound, changed, false)).action, 'settlement');
  assert.equal(core(effectResumeClaimDecide(JSON.stringify(intent), 'holder', 1000, 1000,
    bound, bound, true)).action, 'settlement');
  assert.equal(resumeCompletionAllowed('running'), false);
  assert.equal(resumeCompletionAllowed('succeeded'), true);
  assert.equal(effectSettlementCompletionAllowed('needs_reconciliation'), true);
  assert.equal(effectSettlementCompletionAllowed('succeeded'), false);
  assert.equal(runTransitionAllowed('waiting_checkpoint', 'succeeded'), false);
});
