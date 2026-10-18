"""Independent review preimages exercise integrity, never approval authority."""
import base64
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import unittest

import httpx
from actql_sdk import AsyncClient, ClientError
from actql_sdk._checkpoints import review_bytes_match_cid
from fixtures import PROFILE

VECTOR = json.loads((Path(__file__).resolve().parents[3] / 'scripts/fixtures/'
                     'real-cross-connector-review-vector.json').read_text())


def canonical(value):
    # Literal BMP keys: independent JSON ordering preserves every DATA key.
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def digest(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def seal(body):
    cid = digest(canonical(body))
    return canonical(body | {'review_projection_cid': cid}), cid


def effect_body():
    return {key: value for key, value in deepcopy(VECTOR['body']).items()
            if key != 'review_projection_cid'}


class EffectReviewIntegrityTests(unittest.IsolatedAsyncioTestCase):
    async def exchange(self, raw, cid, *, summary=True):
        operations, credentials = [], []
        checkpoint = deepcopy(VECTOR['expected']['checkpoint'])
        checkpoint.update(checkpointId='original-effect', checkpointCid='sha256:' + 'c' * 64,
                          reviewProjectionCid=cid, createdAt='2026-10-18T00:00:00.000Z',
                          expiresAt='2026-10-19T00:00:00.000Z', humanSummary='Original review')

        def token():
            credentials.append('original-token')
            return 'original-token'

        async def handler(request):
            operation = request.url.path.rsplit('/', 1)[1]
            operations.append(operation)
            if operation == 'connect':
                return httpx.Response(200, json=PROFILE)
            self.assertEqual(operation, 'checkpoint-review')
            self.assertEqual(json.loads(request.content)['checkpointCid'], checkpoint['checkpointCid'])
            return httpx.Response(200, json={'kind': 'review', 'checkpointCid': checkpoint['checkpointCid'],
                'artifactCid': cid, 'byteLength': len(raw), 'contentBase64': base64.b64encode(raw).decode()})

        try:
            async with await AsyncClient.connect('https://fixture.invalid/', token,
                    transport=httpx.MockTransport(handler)) as client:
                return await client.review_checkpoint(checkpoint if summary else checkpoint['checkpointCid'])
        finally:
            # No signer, resolve, replay or extra transport call accompanies integrity admission/refusal.
            self.assertEqual(operations, ['connect', 'checkpoint-review'])
            self.assertEqual(credentials, ['original-token', 'original-token'])

    async def test_public_effect_review_accepts_original_self_cid_not_complete_byte_digest(self):
        raw, cid = seal(effect_body())
        self.assertEqual(cid, 'sha256:6cd2cd48d097dd6e9fee106e3d35be530e1b29191dd3a60ef1d648425abb175f')
        self.assertEqual(cid, VECTOR['body']['review_projection_cid'])
        self.assertNotEqual(digest(raw), cid)
        review = await self.exchange(raw, cid)
        self.assertEqual(review['bytes'], raw)
        self.assertEqual(review['artifact_cid'], cid)

    async def test_public_effect_integrity_preserves_distinct_unicode_and_newline_data_keys(self):
        body = effect_body()
        # This is an integrity-only extension of literal display DATA, not an issued Preview.
        body['displayed_rows'][0]['intended_changes']['value']['data'] = {
            'e\u0301': 1, 'é': 2, 'line\r\n': 'raw\r\n'}
        raw, cid = seal(body)
        review = await self.exchange(raw, cid)
        self.assertEqual(review['bytes'], raw)
        self.assertEqual(json.loads(raw)['displayed_rows'][0]['intended_changes']['value']['data'],
                         {'e\u0301': 1, 'é': 2, 'line\r\n': 'raw\r\n'})

    async def test_effect_integrity_refuses_normalized_data_key_substitution(self):
        body = effect_body()
        body['displayed_rows'][0]['intended_changes']['value']['data'] = {'e\u0301\r\n': 1}
        _, cid = seal(body)
        body['displayed_rows'][0]['intended_changes']['value']['data'] = {'é\n': 1}
        with self.assertRaises(ClientError) as failure:
            await self.exchange(canonical(body | {'review_projection_cid': cid}), cid)
        self.assertEqual(failure.exception.code, 'ReviewIntegrityFailed')

    async def test_noncanonical_effect_bytes_refuse_without_resend(self):
        raw, cid = seal(effect_body())
        with self.assertRaises(ClientError) as failure:
            await self.exchange(raw + b' ', cid)
        self.assertEqual(failure.exception.code, 'ReviewIntegrityFailed')

    async def test_modified_original_effect_body_refuses_without_resend(self):
        body = effect_body()
        _, cid = seal(body)
        body['displayed_permissions'].append('different-permission')
        with self.assertRaises(ClientError) as failure:
            await self.exchange(canonical(body | {'review_projection_cid': cid}), cid)
        self.assertEqual(failure.exception.code, 'ReviewIntegrityFailed')

    async def test_effect_self_field_must_match_requested_original_cid(self):
        raw, cid = seal(effect_body())
        self.assertFalse(review_bytes_match_cid(raw, 'sha256:' + 'f' * 64))
        # The bare preimage itself has exactly this full-byte digest; preserve
        # that legacy integrity path rather than treating it as semantic admission.
        self.assertTrue(review_bytes_match_cid(canonical(effect_body()), cid))
        self.assertFalse(review_bytes_match_cid(canonical(effect_body()) + b' ', cid))

    async def test_unknown_projection_cannot_claim_semantic_self_identity(self):
        raw, cid = seal(effect_body() | {'version': 'unregistered-review'})
        self.assertFalse(review_bytes_match_cid(raw, cid))

    async def test_duplicate_json_members_cannot_claim_semantic_self_identity(self):
        raw, cid = seal(effect_body())
        duplicate = b'{"version":"actql-review-projection/0.1",' + raw[1:]
        self.assertFalse(review_bytes_match_cid(duplicate, cid))

    async def test_model_keeps_original_identifier_key_domain(self):
        raw, cid = seal({'version': 'actql-run-review-projection/0.1', 'data': 'e\u0301\r\n'})
        self.assertTrue(review_bytes_match_cid(raw, cid))
        raw, cid = seal({'version': 'actql-run-review-projection/0.1', 'e\u0301': 1, 'é': 2})
        self.assertFalse(review_bytes_match_cid(raw, cid))

    async def test_legacy_full_byte_integrity_remains_distinct(self):
        raw = canonical({'legacy': 'exact bytes'})
        review = await self.exchange(raw, digest(raw), summary=False)
        self.assertEqual(review['bytes'], raw)
