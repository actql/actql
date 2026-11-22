// Checkpoint answers built by the Client and signed by the application's
// signer. The Host authenticates the caller, verifies each signature against
// its trusted reviewer keys and admits every answer on its own; the Client
// never evaluates accounts or holds a key.
import {createCheckpointAnswerCodec} from './internal/checkpoint-answer-construction.generated.mjs';
import {validAnswerEvidence, validAnswerResolution} from './internal/checkpoint-answer-contract.generated.mjs';
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
// Opaque JSON data opts into exact member names, like Core data_keys admission.
// The default artifact/identifier domain and its identities remain unchanged.
export function canonicalJson(value, {dataKeys = false} = {}) {
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
  if (Array.isArray(value)) return `[${value.map(item =>
    canonicalJson(item, {dataKeys})).join(',')}]`;
  if (typeof value !== 'object' ||
      Object.getPrototypeOf(value) !== Object.prototype) {
    throw new TypeError('InvalidCanonicalValue');
  }
  const entries = Object.entries(value)
    .filter(([, item]) => item !== undefined)
    .map(([key, item]) => {
      if (!wellFormed(key)) throw new TypeError('InvalidCanonicalText');
      return [dataKeys ? key : normalized(key), item];
    });
  if (new Set(entries.map(([key]) => key)).size !== entries.length) {
    throw new TypeError('CanonicalKeyCollision');
  }
  entries.sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  return `{${entries.map(([key, item]) =>
    `${JSON.stringify(key)}:${canonicalJson(item, {dataKeys})}`).join(',')}}`;
}

const hex = bytes => [...new Uint8Array(bytes)]
  .map(byte => byte.toString(16).padStart(2, '0')).join('');

export async function bytesCid(bytes) {
  return `sha256:${hex(await crypto.subtle.digest('SHA-256', bytes))}`;
}

export const contentCid = value =>
  bytesCid(encoder.encode(canonicalJson(value)));

// The existing resolve-item wire ceiling also bounds the maximum possible
// value-node count. Keep the SDK's existing JSON container-depth ceiling.
const candidateLimits = Object.freeze({maxWireBytes: 16384,
  maxNodes: 16384, maxDepth: 64});
const answerCodec = createCheckpointAnswerCodec({canonicalJson, bytesCid});

// Model and Effect reviews use the common self-addressed artifact identity. Legacy
// review envelopes retain their full-byte digest. Never strip an arbitrary
// field or accept a noncanonical encoding as a semantic-CID proof.
export async function reviewBytesMatchCid(bytes, artifactCid) {
  // Review transport already enforces its caller's byte ceiling. The wire
  // length also bounds every possible node/container; add no new profile cap.
  const extent = Math.max(2, bytes.byteLength);
  return answerCodec.reviewBytesMatchCid(bytes, artifactCid,
    {maxWireBytes: extent, maxNodes: extent, maxDepth: extent});
}

// `signer` is supplied by the application: {keyId, reviewerId,
// sign(bytes) -> Uint8Array | base64 string}. It signs the UTF-8 text of an
// unsigned artifact CID (the pinned Ed25519 preimage). The Client never sees
// the private key.
export function checkedSigner(signer) {
  if (signer === null || typeof signer !== 'object' ||
      !answerCodec.validSignerIds(signer.keyId, signer.reviewerId) ||
      typeof signer.sign !== 'function') {
    throw new TypeError('InvalidCheckpointSigner');
  }
  return signer;
}

async function signature(signer, text) {
  const signed = await signer.sign(encoder.encode(text));
  try { return answerCodec.encodeSignerSignature(signed); }
  catch (cause) {
    if (cause?.code !== 'InvalidField' || cause.field !== 'proof.signature') throw cause;
    throw new TypeError('InvalidCheckpointSignature');
  }
}

// One signed answer for one Checkpoint, from its listed safe metadata. An
// approval carries the evidence profile of this Checkpoint. Nothing covers
// another Checkpoint, and a whole-set approval does not promise atomic writes.
export async function signedAnswer(summary, decision, signer, decidedAt) {
  if (decision !== 'approved' && decision !== 'rejected') {
    throw new TypeError('InvalidCheckpointDecision');
  }
  // Capture the original callback before the generated codec captures the
  // bounded Summary and actor, all before its first asynchronous digest.
  const sourceSigner = checkedSigner(signer);
  const signBytes = sourceSigner.sign;
  signer = Object.freeze({keyId: sourceSigner.keyId,
    reviewerId: sourceSigner.reviewerId,
    authorityScopeCid: sourceSigner.authorityScopeCid,
    sign: bytes => signBytes.call(sourceSigner, bytes)});
  return constructSignedAnswer(summary, decision, signer, decidedAt);
}

// Error presentation keeps existing SDK names; it does not select a profile or
// admit a claim. The generated constructor owns every candidate decision.
function candidateError(cause) {
  let code = 'InvalidCheckpointAnswer';
  if (cause.code === 'UnsupportedProfile') {
    code = 'UnsupportedCheckpointAnswer';
  } else if (cause.field === 'authority_scope_cid') {
    code = 'EffectApprovalAuthorityScopeRequired';
  }
  return new TypeError(code, {cause});
}

// Private SDK continuation, not a package entry or an authority factory.
// Candidate construction consumes the same generated Common-owned recipe.
export async function signedAnswerFromAdmittedSummary(summary, decision, signer, decidedAt) {
  return constructSignedAnswer(summary, decision, signer, decidedAt);
}

async function constructSignedAnswer(summary, decision, signer, decidedAt) {
  let prepared;
  try {
    prepared = await answerCodec.prepareAnswerCandidate(summary, decision,
      {keyId: signer.keyId, reviewerId: signer.reviewerId,
        ...(signer.authorityScopeCid === undefined ? {} :
          {authorityScopeCid: signer.authorityScopeCid})}, decidedAt, candidateLimits);
  } catch (cause) { throw candidateError(cause); }
  const approvalPreimage = answerCodec.answerCandidateApprovalPreimage(prepared);
  const approvalSignature = approvalPreimage === undefined ? undefined :
    await signature(signer, approvalPreimage);
  const resolution = await answerCodec.prepareAnswerResolution(prepared, approvalSignature);
  return answerCodec.finishAnswerCandidate(resolution,
    await signature(signer, answerCodec.answerResolutionPreimage(resolution)));
}

// Compare an external original answer using its actual returned proof bytes.
// This constructs DATA for comparison only: no signer, reissue or verification
// authority is obtained from a proof. The Host keeps independent admission.
export async function checkpointAnswerMatches(answer, summary, decision) {
  try {
    const resolution = JSON.parse(answer.resolutionWire);
    if (!validAnswerResolution(resolution)) return false;
    const evidence = decision === 'approved' ? JSON.parse(answer.approvalEvidenceWire) : undefined;
    if (evidence !== undefined && !validAnswerEvidence(evidence)) return false;
    const approval = evidence?.compatibility_approval;
    const actor = {keyId: resolution.proof.key_id, reviewerId: resolution.actor,
      ...(approval?.authority_scope_cid === undefined ? {} :
        {authorityScopeCid: approval.authority_scope_cid})};
    const prepared = await answerCodec.prepareAnswerCandidate(summary, decision,
      actor, resolution.decided_at, candidateLimits);
    const stage = await answerCodec.prepareAnswerResolution(prepared, approval?.proof.signature);
    const expected = await answerCodec.finishAnswerCandidate(stage, resolution.proof.signature);
    return expected.checkpointCid === answer.checkpointCid &&
      expected.resolutionWire === answer.resolutionWire &&
      expected.approvalEvidenceWire === answer.approvalEvidenceWire;
  } catch { return false; }
}
