// Checkpoint answers built by the Client and signed by the application's
// signer. The Host authenticates the caller, verifies each signature against
// its trusted reviewer keys and admits every answer on its own; the Client
// never evaluates accounts or holds a key.
const encoder = new TextEncoder();

function wellFormed(value) {
  for (let i = 0; i < value.length; i++) {
    const unit = value.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      const next = value.charCodeAt(++i);
      if (!(next >= 0xdc00 && next <= 0xdfff)) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) return false;
  }
  return true;
}

function normalized(value) {
  if (!wellFormed(value)) {
    throw new TypeError('InvalidCanonicalText');
  }
  return value.normalize('NFC').replace(/\r\n?/gu, '\n');
}

// Canonical JSON of the pinned Checkpoint artifacts: sorted keys, no
// whitespace, NFC/LF object member names, preserved data strings, finite numbers.
export function canonicalJson(value) {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number') {
    if (!Number.isFinite(value) || Object.is(value, -0)) {
      throw new TypeError('InvalidCanonicalNumber');
    }
    return JSON.stringify(value);
  }
  if (typeof value === 'string') {
    if (!wellFormed(value)) throw new TypeError('InvalidCanonicalText');
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (typeof value !== 'object' ||
      Object.getPrototypeOf(value) !== Object.prototype) {
    throw new TypeError('InvalidCanonicalValue');
  }
  const entries = Object.entries(value)
    .filter(([, item]) => item !== undefined)
    .map(([key, item]) => [normalized(key), item]);
  if (new Set(entries.map(([key]) => key)).size !== entries.length) {
    throw new TypeError('CanonicalKeyCollision');
  }
  entries.sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  return `{${entries.map(([key, item]) =>
    `${JSON.stringify(key)}:${canonicalJson(item)}`).join(',')}}`;
}

const hex = bytes => [...new Uint8Array(bytes)]
  .map(byte => byte.toString(16).padStart(2, '0')).join('');

export async function bytesCid(bytes) {
  return `sha256:${hex(await crypto.subtle.digest('SHA-256', bytes))}`;
}

export const contentCid = value =>
  bytesCid(encoder.encode(canonicalJson(value)));

const base64 = bytes => {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
};

// `signer` is supplied by the application: {keyId, reviewerId,
// sign(bytes) -> Uint8Array | base64 string}. It signs the UTF-8 text of an
// unsigned artifact CID (the pinned Ed25519 preimage). The Client never sees
// the private key.
export function checkedSigner(signer) {
  const name = /^[A-Za-z0-9._:-]{1,128}$/u;
  if (signer === null || typeof signer !== 'object' ||
      !name.test(signer.keyId ?? '') || !name.test(signer.reviewerId ?? '') ||
      typeof signer.sign !== 'function') {
    throw new TypeError('InvalidCheckpointSigner');
  }
  return signer;
}

async function signature(signer, text) {
  const signed = await signer.sign(encoder.encode(text));
  if (typeof signed === 'string' &&
      /^[A-Za-z0-9+/]+={0,2}$/u.test(signed)) return signed;
  if (signed instanceof Uint8Array && signed.byteLength === 64) {
    return base64(signed);
  }
  throw new TypeError('InvalidCheckpointSignature');
}

// One signed answer for one Checkpoint, from its listed safe metadata. An
// approval carries the evidence profile of this Checkpoint. Nothing covers
// another Checkpoint, and a whole-set approval does not promise atomic writes.
export async function signedAnswer(summary, decision, signer, decidedAt) {
  if (decision !== 'approved' && decision !== 'rejected') {
    throw new TypeError('InvalidCheckpointDecision');
  }
  // Own the public data and callback before the first asynchronous digest or
  // signature. A caller cannot relabel an answer while its signer is waiting.
  summary = JSON.parse(canonicalJson(summary));
  const sourceSigner = checkedSigner(signer);
  const signBytes = sourceSigner.sign;
  signer = Object.freeze({keyId: sourceSigner.keyId,
    reviewerId: sourceSigner.reviewerId,
    authorityScopeCid: sourceSigner.authorityScopeCid,
    sign: bytes => signBytes.call(sourceSigner, bytes)});
  const preparation = ['run_scope', 'read_access'].includes(summary?.kind) &&
    summary.subject?.kind === 'prepare_attempt';
  const effect = summary?.kind === 'effect_set' &&
    summary.phase === 'commit' && summary.subject?.kind === 'run_unit' &&
    summary.requiredArtifact?.type === 'effect_set_preview';
  if (!preparation && !effect) {
    // Run acceptance and a held source read of a request before its Run
    // share the run-scope approval profile. Other kinds carry their own
    // evidence profiles (for example an Effect Set attestation).
    throw new TypeError('UnsupportedCheckpointAnswer');
  }
  let evidence;
  if (decision === 'approved') {
    if (effect && !/^sha256:[0-9a-f]{64}$/u.test(
      signer.authorityScopeCid ?? '')) {
      throw new TypeError('EffectApprovalAuthorityScopeRequired');
    }
    if (effect && (!Array.isArray(summary.requirements) ||
        !summary.requirements.includes('effect_scope_approved') ||
        summary.requirements.some(claim => !['effect_scope_approved',
          'partial_application_accepted'].includes(claim)))) {
      throw new TypeError('UnsupportedEffectApprovalClaims');
    }
    const approval = effect ? {
      version: 'actql-approval-attestation/0.1',
      effect_preview_cid: summary.requiredArtifact.cid,
      review_projection_cid: summary.reviewProjectionCid,
      authority_scope_cid: signer.authorityScopeCid,
      claims: [...summary.requirements],
      approver: signer.reviewerId, approved_at: decidedAt,
    } : {
      version: 'actql-run-scope-approval/0.1',
      prepared_invocation_cid: summary.requiredArtifact.cid,
      review_projection_cid: summary.reviewProjectionCid,
      claim: 'invocation_scope_approved',
      approver: signer.reviewerId,
      approved_at: decidedAt,
      expires_at: summary.expiresAt,
    };
    approval.proof = {scheme: 'ed25519-v1', key_id: signer.keyId,
      signature: await signature(signer, await contentCid(approval))};
    approval[effect ? 'attestation_cid' : 'run_scope_approval_cid'] =
      await contentCid(approval);
    evidence = {
      version: 'actql-checkpoint-approval-evidence/0.1',
      kind: summary.kind,
      checkpoint_cid: summary.checkpointCid,
      review_projection_cid: summary.reviewProjectionCid,
      compatibility_approval: approval,
    };
  }
  const body = {
    version: 'actql-checkpoint-resolution/0.1',
    resolution_id: `resolution-${summary.checkpointId}-${decision}`,
    checkpoint_id: summary.checkpointId,
    checkpoint_cid: summary.checkpointCid,
    ...(effect ? {run_id: summary.subject.runId,
      run_definition_cid: summary.subject.runDefinitionCid} :
      {prepare_attempt_id: summary.subject.prepareAttemptId}),
    decision,
    actor: signer.reviewerId,
    decided_at: decidedAt,
    required_artifact_cid: summary.requiredArtifact.cid,
    review_projection_cid: summary.reviewProjectionCid,
    ...(evidence === undefined ? {} :
      {approval_evidence_cid: await contentCid(evidence)}),
  };
  body.proof = {scheme: 'ed25519-v1', key_id: signer.keyId,
    signature: await signature(signer, await contentCid(body))};
  body.resolution_cid = await contentCid(body);
  return Object.freeze({
    checkpointCid: summary.checkpointCid,
    resolutionWire: canonicalJson(body),
    approvalEvidenceWire: evidence === undefined ? '' : canonicalJson(evidence),
  });
}
