import asyncio
import base64
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import unittest
from unittest.mock import patch
import httpx
from actql_sdk import AsyncClient, ClientError, Signer
from actql_sdk._checkpoints import review_bytes_match_cid
from fixtures import PROFILE

CID = lambda digit: 'sha256:' + digit * 64
SUMMARY = {'checkpointId': 'prepare-a-preparation', 'checkpointCid': CID('c'), 'kind': 'run_scope', 'phase': 'preflight',
           'subject': {'kind': 'prepare_attempt', 'prepareAttemptId': 'prepare-a', 'requestId': 'saved-a'},
           'requiredArtifact': {'type': 'prepared_invocation', 'cid': CID('d')}, 'reviewProjectionCid': CID('e'),
           'requirements': ['invocation_scope_approved'], 'createdAt': '2026-09-26T00:00:00.000Z',
           'expiresAt': '2026-09-27T00:00:00.000Z', 'humanSummary': 'Run on site-a'}


def independent_cid(value):
    # Every key here is ASCII. These fixed artifacts do not use the product codec.
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


class CheckpointTests(unittest.IsolatedAsyncioTestCase):
    async def test_resolution_owns_summary_signer_and_exact_independent_preimages(self):
        requests, preimages = [], []
        summary = deepcopy(SUMMARY)
        async def sign(raw):
            preimages.append(raw)
            await asyncio.sleep(0)
            return bytes(64)
        async def handler(request):
            operation = request.url.path.rsplit('/', 1)[1]
            body = json.loads(request.content)
            requests.append((operation, body))
            if operation == 'connect': return httpx.Response(200, json=PROFILE)
            resolution = json.loads(body['items'][0]['resolutionWire'])
            return httpx.Response(200, json={'results': [{'checkpointCid': CID('c'), 'status': 'committed',
                'decision': 'approved', 'resolutionCid': resolution['resolution_cid']}]})
        with patch('actql_sdk._async.datetime') as clock:
            clock.now.return_value = datetime(2026, 9, 26, 1, tzinfo=timezone.utc)
            async with await AsyncClient.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(handler)) as client:
                pending = client.resolve_checkpoints([{'checkpoint': summary, 'decision': 'approved'}],
                                                      signer=Signer('alice-key', 'alice', sign))
                summary['checkpointId'] = 'changed-after-call'
                answer = await pending
        item = answer['signed'][0]
        actual = json.loads(item['resolutionWire'])
        evidence = json.loads(item['approvalEvidenceWire'])
        at = '2026-09-26T01:00:00.000Z'
        approval = {'version': 'actql-run-scope-approval/0.1', 'prepared_invocation_cid': CID('d'),
            'review_projection_cid': CID('e'), 'claim': 'invocation_scope_approved', 'approver': 'alice',
            'approved_at': at, 'expires_at': '2026-09-27T00:00:00.000Z'}
        self.assertEqual(preimages[0], independent_cid(approval).encode())
        proof = {'scheme': 'ed25519-v1', 'key_id': 'alice-key', 'signature': base64.b64encode(bytes(64)).decode()}
        approval['proof'] = proof
        approval['run_scope_approval_cid'] = independent_cid(approval)
        expected_evidence = {'version': 'actql-checkpoint-approval-evidence/0.1', 'kind': 'run_scope',
            'checkpoint_cid': CID('c'), 'review_projection_cid': CID('e'), 'compatibility_approval': approval}
        self.assertEqual(evidence, expected_evidence)
        resolution = {'version': 'actql-checkpoint-resolution/0.1', 'resolution_id': 'resolution-prepare-a-preparation-approved',
            'checkpoint_id': 'prepare-a-preparation', 'checkpoint_cid': CID('c'), 'prepare_attempt_id': 'prepare-a',
            'decision': 'approved', 'actor': 'alice', 'decided_at': at, 'required_artifact_cid': CID('d'),
            'review_projection_cid': CID('e'), 'approval_evidence_cid': independent_cid(expected_evidence)}
        self.assertEqual(preimages[1], independent_cid(resolution).encode())
        resolution['proof'] = proof
        resolution['resolution_cid'] = independent_cid(resolution)
        self.assertEqual(actual, resolution)
        self.assertEqual([operation for operation, _ in requests], ['connect', 'resolve'])

    async def test_resolution_response_loss_keeps_signed_wire_without_retry(self):
        requests = []
        async def handler(request):
            operation = request.url.path.rsplit('/', 1)[1]
            body = json.loads(request.content)
            requests.append((operation, body))
            if operation == 'connect': return httpx.Response(200, json=PROFILE)
            raise httpx.ReadError('private transport failure')
        async with await AsyncClient.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(handler)) as client:
            with self.assertRaises(ClientError) as error:
                await client.resolve_checkpoints([{'checkpoint': SUMMARY, 'decision': 'rejected'}],
                                                 signer=Signer('alice-key', 'alice', lambda raw: bytes(64)))
        self.assertEqual(error.exception.code, 'ResolutionUnknown')
        self.assertEqual(error.exception.signed[0]['resolutionWire'], requests[-1][1]['items'][0]['resolutionWire'])
        self.assertEqual(error.exception.signed[0]['approvalEvidenceWire'], '')
        self.assertEqual(len(requests), 2)

    async def test_short_signature_is_rejected_before_io(self):
        operations = []
        async def handler(request):
            operations.append(request.url.path.rsplit('/', 1)[1])
            return httpx.Response(200, json=PROFILE)
        async with await AsyncClient.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(handler)) as client:
            with self.assertRaises(ClientError) as error:
                await client.resolve_checkpoints([{'checkpoint': SUMMARY, 'decision': 'rejected'}],
                                                 signer=Signer('alice-key', 'alice', lambda raw: bytes(63)))
        self.assertEqual(error.exception.code, 'InvalidCheckpointSignature')
        self.assertEqual(operations, ['connect'])

    async def test_review_integrity_does_not_accept_arbitrary_self_cid(self):
        body = {'version': 'actql-run-review-projection/0.1', 'data': 'e\u0301\r\n'}
        cid = independent_cid(body)
        encoded = json.dumps(body | {'review_projection_cid': cid}, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
        self.assertTrue(review_bytes_match_cid(encoded, cid))
        self.assertFalse(review_bytes_match_cid(encoded + b' ', cid))
        self.assertFalse(review_bytes_match_cid(encoded, CID('a')))
