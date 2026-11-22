"""Existing Checkpoint artifact preimages, signed by an application callback."""
from dataclasses import dataclass
import inspect
from collections.abc import Callable
from ._errors import ClientError
from ._values import bytes_cid, canonical_bytes
from ._checkpoint_answer_codec import create_checkpoint_answer_codec, CheckpointCandidateError

# Existing resolve-item wire ceiling; every value node consumes wire bytes.
# Keep the SDK JSON depth ceiling and use no Local engine or process.
_CANDIDATE_LIMITS = {'maxWireBytes': 16384, 'maxNodes': 16384, 'maxDepth': 64}
_ANSWER_CODEC = create_checkpoint_answer_codec(canonical_bytes, bytes_cid)


@dataclass(frozen=True)
class Signer:
    key_id: str
    reviewer_id: str
    sign: Callable
    authority_scope_cid: str | None = None


def capture_signer(signer):
    if (not isinstance(signer, Signer) or not callable(signer.sign)
            or not _ANSWER_CODEC.valid_signer_ids(signer.key_id, signer.reviewer_id)):
        raise ClientError('InvalidCheckpointSigner')
    return Signer(signer.key_id, signer.reviewer_id, signer.sign, signer.authority_scope_cid)


async def _signature(signer, cid):
    signed = signer.sign(cid.encode('utf-8'))
    if inspect.isawaitable(signed):
        signed = await signed
    try:
        return _ANSWER_CODEC.encode_signer_signature(signed)
    except CheckpointCandidateError:
        raise ClientError('InvalidCheckpointSignature') from None


def review_bytes_match_cid(raw, cid):
    # Retain the existing Python JSON node/depth policy. Review transport owns
    # its caller's byte ceiling; this is identity DATA, never Host admission.
    return _ANSWER_CODEC.review_bytes_match_cid(raw, cid, {
        'maxWireBytes': max(2, memoryview(raw).nbytes), 'maxNodes': 100000, 'maxDepth': 64})


def _candidate_error(cause):
    # Presentation only: profile, shape and claim admission stay generated.
    code = ('UnsupportedCheckpointAnswer' if cause.code == 'UnsupportedProfile' else
            'EffectApprovalAuthorityScopeRequired' if cause.field == 'authority_scope_cid' else
            'InvalidCheckpointAnswer')
    return ClientError(code, cause=cause)


async def signed_answer(summary, decision, signer, decided_at):
    signer = capture_signer(signer)
    if decision not in ('approved', 'rejected'):
        raise ClientError('InvalidCheckpointDecision')
    actor = {'keyId': signer.key_id, 'reviewerId': signer.reviewer_id}
    if signer.authority_scope_cid is not None:
        actor['authorityScopeCid'] = signer.authority_scope_cid
    try:
        # The generated codec owns a bounded Summary/actor snapshot before the
        # first awaited application signature. No duplicate document policy.
        prepared = _ANSWER_CODEC.prepare_answer_candidate(
            summary, decision, actor, decided_at, _CANDIDATE_LIMITS)
    except CheckpointCandidateError as cause:
        raise _candidate_error(cause) from cause
    preimage = _ANSWER_CODEC.answer_candidate_approval_preimage(prepared)
    approval_signature = None if preimage is None else await _signature(signer, preimage)
    resolution = _ANSWER_CODEC.prepare_answer_resolution(prepared, approval_signature)
    proof = await _signature(signer, _ANSWER_CODEC.answer_resolution_preimage(resolution))
    return _ANSWER_CODEC.finish_answer_candidate(resolution, proof)
