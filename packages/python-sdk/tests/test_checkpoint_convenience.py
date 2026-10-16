"""Public convenience delegates original metadata/signatures/resolve; no grants."""
import asyncio
from copy import deepcopy
import json
import unittest
from unittest.mock import patch

import httpx
from actql_sdk import AsyncClient, Client, ClientError, Signer
from fixtures import PROFILE
from test_checkpoints import SUMMARY


class Peer:
    def __init__(self):
        self.operations = []
        self.signatures = []
        self.lookup = {'items': [deepcopy(SUMMARY)]}
        self.loss = None

    async def handle(self, request):
        operation = request.url.path.rsplit('/', 1)[1]
        body = json.loads(request.content)
        self.operations.append((operation, body))
        if operation == 'connect':
            return httpx.Response(200, json=PROFILE)
        if operation == self.loss:
            raise httpx.ReadError('Original reply unavailable')
        if operation == 'checkpoints':
            return httpx.Response(200, json=self.lookup)
        assert operation == 'resolve'
        answer, = body['items']
        resolution = json.loads(answer['resolutionWire'])
        return httpx.Response(200, json={'results': [{'checkpointCid': answer['checkpointCid'],
            'status': 'committed', 'decision': resolution['decision'],
            'resolutionCid': resolution['resolution_cid']}]})

    def signer(self, reviewer='alice'):
        def sign(raw):
            self.signatures.append((reviewer, raw))
            return bytes(64)
        return Signer('alice-key', reviewer, sign)


class CheckpointConvenienceTests(unittest.IsolatedAsyncioTestCase):
    async def client(self, peer, **options):
        result = await AsyncClient.connect('https://host.invalid/', 'token',
            transport=httpx.MockTransport(peer.handle), **options)
        self.addAsyncCleanup(result.aclose)
        return result

    async def test_approve_uses_exact_original_summary_and_captured_configured_signer(self):
        peer = Peer()
        signer = peer.signer()
        client = await self.client(peer, signer=signer)
        # A caller cannot replace the captured callback after configuration.
        object.__setattr__(signer, 'sign', lambda _: self.fail('Replaced signer'))
        result = await client.approve(SUMMARY['checkpointId'])
        self.assertEqual(result['results'][0]['decision'], 'approved')
        self.assertEqual([op for op, _ in peer.operations], ['connect', 'checkpoints', 'resolve'])
        request = peer.operations[1][1]
        self.assertEqual({k: request[k] for k in ('after', 'limit', 'checkpointId')},
            {'after': '', 'limit': 1, 'checkpointId': SUMMARY['checkpointId']})
        self.assertNotIn('signer', request)
        resolution = json.loads(result['signed'][0]['resolutionWire'])
        self.assertEqual(resolution['checkpoint_cid'], SUMMARY['checkpointCid'])
        self.assertEqual(resolution['required_artifact_cid'], SUMMARY['requiredArtifact']['cid'])
        self.assertEqual(resolution['review_projection_cid'], SUMMARY['reviewProjectionCid'])
        self.assertEqual(resolution['actor'], 'alice')
        self.assertEqual(len(peer.signatures), 2)

    async def test_reject_uses_same_original_resolve_and_no_approval_evidence(self):
        peer = Peer()
        client = await self.client(peer, signer=peer.signer())
        result = await client.reject(SUMMARY['checkpointId'])
        self.assertEqual(result['results'][0]['decision'], 'rejected')
        self.assertEqual(result['signed'][0]['approvalEvidenceWire'], '')
        self.assertEqual(len(peer.signatures), 1)

    async def test_explicit_resolution_can_use_or_override_configured_signer(self):
        peer = Peer()
        client = await self.client(peer, signer=peer.signer())
        items = [{'checkpoint': SUMMARY, 'decision': 'rejected'}]
        default = await client.resolve_checkpoints(items)
        override = await client.resolve_checkpoints(items, signer=peer.signer('bob'))
        self.assertEqual(json.loads(default['signed'][0]['resolutionWire'])['actor'], 'alice')
        self.assertEqual(json.loads(override['signed'][0]['resolutionWire'])['actor'], 'bob')
        self.assertEqual([op for op, _ in peer.operations], ['connect', 'resolve', 'resolve'])

    async def test_invalid_id_and_missing_signer_refuse_before_lookup_or_signature(self):
        peer = Peer()
        client = await self.client(peer, signer=peer.signer())
        for value in (None, True, 1, '', 'x' * 257, 'a\n', '\ud800'):
            with self.subTest(value=repr(value)), self.assertRaises(ClientError):
                await client.approve(value)
        unsigned = await self.client(peer)
        with self.assertRaises(ClientError) as failure:
            await unsigned.reject(SUMMARY['checkpointId'])
        self.assertEqual(failure.exception.code, 'InvalidCheckpointSigner')
        self.assertEqual([op for op, _ in peer.operations], ['connect', 'connect'])
        self.assertEqual(peer.signatures, [])

    async def test_invalid_configured_signer_has_no_transport_or_local_host(self):
        with patch('actql_sdk._async.httpx.AsyncHTTPTransport', side_effect=AssertionError('No transport')):
            with self.assertRaises(ClientError) as failure:
                await AsyncClient.connect('https://host.invalid/', 'token', signer=True)
        self.assertEqual(failure.exception.code, 'InvalidCheckpointSigner')
        with patch('actql_sdk._local_product.InstalledLocalHost.installed', side_effect=AssertionError('No Host')):
            with self.assertRaises(ClientError) as failure:
                await AsyncClient.open(signer=True)
        self.assertEqual(failure.exception.code, 'InvalidCheckpointSigner')

    async def test_absent_and_uncorrelated_lookup_never_signs_or_resolves(self):
        peer = Peer()
        client = await self.client(peer, signer=peer.signer())
        for value in ({'items': []}, {'items': [SUMMARY | {'checkpointId': 'foreign'}]},
                      {'items': [SUMMARY], 'next': 'another-page'}, {'items': [SUMMARY, SUMMARY]}):
            peer.lookup = value
            with self.subTest(value=value), self.assertRaises(ClientError) as failure:
                await client.approve(SUMMARY['checkpointId'])
            self.assertIn(failure.exception.code, ('CheckpointNotPending',
                'InvalidHostCheckpointLookup', 'InvalidHostCheckpointPage'))
        self.assertEqual(peer.signatures, [])
        self.assertEqual([op for op, _ in peer.operations], ['connect'] + ['checkpoints'] * 4)

    async def test_lookup_reply_loss_does_not_sign_retry_or_enter_resolution(self):
        peer = Peer(); peer.loss = 'checkpoints'
        client = await self.client(peer, signer=peer.signer())
        with self.assertRaises(ClientError):
            await client.approve(SUMMARY['checkpointId'])
        self.assertEqual(peer.signatures, [])
        self.assertEqual([op for op, _ in peer.operations], ['connect', 'checkpoints'])

    async def test_resolution_reply_loss_retains_original_signed_wires_without_resend(self):
        peer = Peer(); peer.loss = 'resolve'
        client = await self.client(peer, signer=peer.signer())
        with self.assertRaises(ClientError) as failure:
            await client.approve(SUMMARY['checkpointId'])
        self.assertEqual(failure.exception.code, 'ResolutionUnknown')
        self.assertEqual(dict(failure.exception.signed[0]), peer.operations[-1][1]['items'][0])
        self.assertEqual([op for op, _ in peer.operations], ['connect', 'checkpoints', 'resolve'])
        self.assertEqual(len(peer.signatures), 2)

    async def test_cancel_during_application_signer_has_no_resolve_or_fake_ack(self):
        peer = Peer(); entered = asyncio.Event()
        async def sign(_):
            entered.set()
            await asyncio.Future()
        client = await self.client(peer, signer=Signer('key', 'alice', sign))
        pending = asyncio.create_task(client.approve(SUMMARY['checkpointId']))
        await entered.wait()
        pending.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await pending
        self.assertEqual([op for op, _ in peer.operations], ['connect', 'checkpoints'])

    async def test_failed_close_keeps_signer_custody_until_same_cleanup_retry(self):
        peer = Peer()
        class Transport(httpx.AsyncBaseTransport):
            def __init__(self): self.closes = 0
            async def handle_async_request(self, request): return await peer.handle(request)
            async def aclose(self):
                self.closes += 1
                if self.closes == 1: raise RuntimeError('Original cleanup pending')
        transport = Transport()
        client = await AsyncClient.connect('https://host.invalid/', 'token',
            signer=peer.signer(), transport=transport)
        with self.assertRaises(ClientError):
            await client.aclose()
        self.assertIsNotNone(client._signer)
        with self.assertRaises(ClientError) as failure:
            await client.reject(SUMMARY['checkpointId'])
        self.assertEqual(failure.exception.code, 'ClientClosed')
        await client.aclose()
        self.assertIsNone(client._signer)
        await client.aclose()
        self.assertEqual(transport.closes, 2)


class SyncCheckpointConvenienceTests(unittest.TestCase):
    def test_sync_uses_same_configured_signer_and_async_resolve(self):
        for decision in ('approve', 'reject'):
            with self.subTest(decision=decision):
                peer = Peer()
                with Client.connect('https://host.invalid/', 'token', signer=peer.signer(),
                        transport=httpx.MockTransport(peer.handle)) as client:
                    result = getattr(client, decision)(SUMMARY['checkpointId'])
                self.assertEqual(result['results'][0]['decision'],
                                 'approved' if decision == 'approve' else 'rejected')
                self.assertEqual([op for op, _ in peer.operations], ['connect', 'checkpoints', 'resolve'])
