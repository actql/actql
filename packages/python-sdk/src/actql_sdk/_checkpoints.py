"""Existing Checkpoint artifact preimages, signed by an application callback."""
import base64
from dataclasses import dataclass
import hashlib
import inspect
import re
from collections.abc import Callable
from ._errors import ClientError
from ._values import canonical_bytes, content_cid, decode_json, snapshot, thaw
from ._wire import valid


@dataclass(frozen=True)
class Signer:
    key_id: str
    reviewer_id: str
    sign: Callable
    authority_scope_cid: str | None = None


def capture_signer(signer):
    if (not isinstance(signer, Signer) or not callable(signer.sign)
            or any(type(name) is not str or re.fullmatch(r'[A-Za-z0-9._:-]{1,128}', name) is None
                   for name in (signer.key_id, signer.reviewer_id))):
        raise ClientError('InvalidCheckpointSigner')
    return Signer(signer.key_id, signer.reviewer_id, signer.sign, signer.authority_scope_cid)


async def _signature(signer, cid):
    signed = signer.sign(cid.encode('utf-8'))
    if inspect.isawaitable(signed):
        signed = await signed
    if type(signed) is str:
        try:
            raw = base64.b64decode(signed, validate=True)
        except ValueError:
            raise ClientError('InvalidCheckpointSignature') from None
        if base64.b64encode(raw).decode('ascii') != signed:
            raise ClientError('InvalidCheckpointSignature')
    elif type(signed) is bytes:
        raw = signed
    else:
        raise ClientError('InvalidCheckpointSignature')
    if len(raw) != 64:
        raise ClientError('InvalidCheckpointSignature')
    return base64.b64encode(raw).decode('ascii')


def review_bytes_match_cid(raw, cid):
    if 'sha256:' + hashlib.sha256(raw).hexdigest() == cid:
        return True
    try:
        value = decode_json(raw)
        if (value.get('version') != 'actql-run-review-projection/0.1'
                or value.get('review_projection_cid') != cid or canonical_bytes(value) != raw):
            return False
        return content_cid({key: item for key, item in value.items() if key != 'review_projection_cid'}) == cid
    except (ClientError, AttributeError):
        return False


async def signed_answer(summary, decision, signer, decided_at):
    summary = snapshot(thaw(summary))
    signer = capture_signer(signer)
    if decision not in ('approved', 'rejected'):
        raise ClientError('InvalidCheckpointDecision')
    if not valid(summary, 'checkpoint_summary'):
        raise ClientError('InvalidCheckpointAnswer')
    subject, artifact = summary['subject'], summary['requiredArtifact']
    preparation = summary['kind'] in ('run_scope', 'read_access') and subject['kind'] == 'prepare_attempt'
    acquired_read = (summary['kind'] == 'read_access' and summary['phase'] == 'preflight'
                     and subject['kind'] == 'run_unit' and artifact['type'] == 'read_scope')
    effect = (summary['kind'] == 'effect_set' and summary['phase'] == 'commit'
              and subject['kind'] == 'run_unit' and artifact['type'] == 'effect_set_preview')
    model = (summary['kind'] == 'model_invocation' and summary['phase'] == 'preflight'
             and subject['kind'] == 'run_unit' and artifact['type'] == 'model_invocation_scope'
             and valid(summary.get('preparedInvocationCid'), {'type': 'string', 'pattern': '^sha256:[0-9a-f]{64}$'})
             and summary['requirements'] == ['invocation_scope_approved'])
    if not (preparation or acquired_read or effect or model) or not model and 'preparedInvocationCid' in summary:
        raise ClientError('UnsupportedCheckpointAnswer')
    evidence = None
    if decision == 'approved':
        if effect:
            if not valid(signer.authority_scope_cid, {'type': 'string', 'pattern': '^sha256:[0-9a-f]{64}$'}):
                raise ClientError('EffectApprovalAuthorityScopeRequired')
            if ('effect_scope_approved' not in summary['requirements'] or
                    any(claim not in ('effect_scope_approved', 'partial_application_accepted') for claim in summary['requirements'])):
                raise ClientError('UnsupportedEffectApprovalClaims')
            approval = {'version': 'actql-approval-attestation/0.1', 'effect_preview_cid': artifact['cid'],
                'review_projection_cid': summary['reviewProjectionCid'], 'authority_scope_cid': signer.authority_scope_cid,
                'claims': summary['requirements'], 'approver': signer.reviewer_id, 'approved_at': decided_at}
        else:
            approval = {'version': 'actql-run-scope-approval/0.1',
                'prepared_invocation_cid': summary['preparedInvocationCid'] if model else artifact['cid'],
                'review_projection_cid': summary['reviewProjectionCid'], 'claim': 'invocation_scope_approved',
                'approver': signer.reviewer_id, 'approved_at': decided_at, 'expires_at': summary['expiresAt']}
        approval['proof'] = {'scheme': 'ed25519-v1', 'key_id': signer.key_id, 'signature': await _signature(signer, content_cid(approval))}
        approval['attestation_cid' if effect else 'run_scope_approval_cid'] = content_cid(approval)
        evidence = {'version': 'actql-checkpoint-approval-evidence/0.1', 'kind': summary['kind'],
                    'checkpoint_cid': summary['checkpointCid'], 'review_projection_cid': summary['reviewProjectionCid'],
                    'compatibility_approval': approval}
    body = {'version': 'actql-checkpoint-resolution/0.1',
            'resolution_id': 'resolution-' + summary['checkpointId'] + '-' + decision,
            'checkpoint_id': summary['checkpointId'], 'checkpoint_cid': summary['checkpointCid'],
            'decision': decision, 'actor': signer.reviewer_id, 'decided_at': decided_at,
            'required_artifact_cid': artifact['cid'], 'review_projection_cid': summary['reviewProjectionCid']}
    if effect or acquired_read or model:
        body.update(run_id=subject['runId'], run_definition_cid=subject['runDefinitionCid'])
    else:
        body['prepare_attempt_id'] = subject['prepareAttemptId']
    if evidence is not None:
        body['approval_evidence_cid'] = content_cid(evidence)
    body['proof'] = {'scheme': 'ed25519-v1', 'key_id': signer.key_id, 'signature': await _signature(signer, content_cid(body))}
    body['resolution_cid'] = content_cid(body)
    return {'checkpointCid': summary['checkpointCid'], 'resolutionWire': canonical_bytes(body).decode('utf-8'),
            'approvalEvidenceWire': '' if evidence is None else canonical_bytes(evidence).decode('utf-8')}
