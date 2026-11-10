import {createHash, generateKeyPairSync, sign} from 'node:crypto';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256')
  .update(canonical(value)).digest('hex');
const fixed = value => 'sha256:' + value.repeat(64);

// Independent, side-effect-free approval fixture. Private signing keys remain
// in memory; no real reviewer role, Provider send or deployment is installed.
export function nativeResolutionFixture(checkpointWire, {
  decision = 'approved', resolutionId = 'native-original-resolution',
  reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519'),
  singleClaim = false,
} = {}) {
  if (!['approved', 'rejected'].includes(decision)) throw new Error('Invalid fixture decision');
  // Only the independent default fixture may select its one-claim variant.
  // Never rewrite requirements from an actual compiled Checkpoint reference.
  if (typeof singleClaim !== 'boolean' || (singleClaim && checkpointWire != null)) {
    throw new Error('Invalid self-contained fixture claim selection');
  }
  const body = {
    version: 'actql-execution-checkpoint/0.1',
    checkpoint_id: 'native-resolution-checkpoint',
    run_id: 'native-resolution-run',
    run_definition_cid: fixed('1'),
    continuation_state_cid: fixed('2'),
    subject: {kind: 'run_unit', run_id: 'native-resolution-run',
      unit_id: 'unit-1', continuation: 'resume_unit'},
    phase: 'commit', kind: 'effect_set',
    required_artifact: {artifact_type: 'effect_set_preview', artifact_cid: fixed('3')},
    review_projection_cid: fixed('4'),
    requirements: singleClaim ? ['effect_scope_approved']
      : ['effect_scope_approved', 'partial_application_accepted'],
    reason_code: 'effect_review_required', human_summary: 'Review one scoped update',
    created_at: '2026-10-10T00:00:00.000Z', expires_at: '2026-10-11T00:00:00.000Z',
  };
  const checkpoint = checkpointWire ? JSON.parse(checkpointWire)
    : {...body, checkpoint_cid: cid(body)};
  checkpointWire ??= canonical(checkpoint);
  const timestamp = new Date(Date.parse(checkpoint.created_at) + 60000).toISOString();
  const requirements = checkpoint.requirements;
  const approval = {
    version: 'actql-approval-attestation/0.1',
    effect_preview_cid: checkpoint.required_artifact.artifact_cid,
    review_projection_cid: checkpoint.review_projection_cid,
    approver: 'native-reviewer', approved_at: timestamp,
    authority_scope_cid: fixed('5'), claims: requirements,
  };
  const proof = (value, keyId) => ({scheme: 'ed25519-v1', key_id: keyId,
    signature: sign(null, Buffer.from(cid(value)), reviewer.privateKey).toString('base64')});
  const signedApproval = {...approval, proof: proof(approval, 'reviewer-key')};
  const evidence = {
    version: 'actql-checkpoint-approval-evidence/0.1', kind: 'effect_set',
    checkpoint_cid: checkpoint.checkpoint_cid,
    review_projection_cid: checkpoint.review_projection_cid,
    compatibility_approval: {...signedApproval, attestation_cid: cid(signedApproval)},
  };
  const resolution = {
    version: 'actql-checkpoint-resolution/0.1', resolution_id: resolutionId,
    checkpoint_id: checkpoint.checkpoint_id, checkpoint_cid: checkpoint.checkpoint_cid,
    run_id: checkpoint.run_id, run_definition_cid: checkpoint.run_definition_cid,
    decision, actor: 'native-reviewer', decided_at: timestamp,
    required_artifact_cid: checkpoint.required_artifact.artifact_cid,
    review_projection_cid: checkpoint.review_projection_cid,
    ...(decision === 'approved' ? {approval_evidence_cid: cid(evidence)} : {}),
  };
  const signed = {...resolution, proof: proof(resolution, 'reviewer-key')};
  const resolutionWire = JSON.stringify({...signed, resolution_cid: cid(signed)});
  // Independent protocol fixture, not an Owner return copied into expected
  // state. The consuming common and Native Owners must admit these facts.
  const authorization = {
    version: 'actql-checkpoint-resolution-authorization-evidence/0.1',
    resolution_cid: cid(signed), checkpoint_cid: checkpoint.checkpoint_cid,
    authority_context_cid: fixed('6'), key_id: 'reviewer-key',
  };
  const wrapper = {
    version: 'actql-verified-checkpoint-resolution/0.1',
    resolution: {...signed, resolution_cid: cid(signed)},
    authorization_evidence: authorization, authorization_evidence_cid: cid(authorization),
    verified_by_policy_cid: fixed('7'), verified_reviewer_id: 'native-reviewer',
    authorization_context_cid: fixed('6'), requirements, verified_at: timestamp,
    ...(decision === 'approved' ? {approval_evidence: evidence} : {}),
  };
  const signature = sign(null, Buffer.from(cid(wrapper)), host.privateKey).toString('base64');
  const attested = {...wrapper,
    host_attestation: {scheme: 'ed25519-v1', host_key_id: 'host-key', signature}};
  const verifiedWire = canonical({...attested, verified_resolution_cid: cid(attested)});
  return {
    ACTQL_REQUIRE_NATIVE_EFFECT_RESOLUTION_TESTS: '1',
    ACTQL_TEST_EFFECT_WRONG_PUBLIC_KEY: generateKeyPairSync('ed25519')
      .publicKey.export({type: 'spki', format: 'pem'}),
    ACTQL_TEST_EFFECT_CHECKPOINT_WIRE: checkpointWire,
    ACTQL_TEST_EFFECT_RESOLUTION_WIRE: resolutionWire,
    ACTQL_TEST_EFFECT_VERIFIED_WIRE: verifiedWire,
    ACTQL_TEST_EFFECT_HOST_PUBLIC_KEY: host.publicKey.export({type: 'spki', format: 'pem'}),
  };
}
