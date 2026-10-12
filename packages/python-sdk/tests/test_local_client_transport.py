"""Independent direct-port fixtures; no actual Wasm, installed Host or E2E claim."""
import asyncio
import json
import unittest
from unittest.mock import patch

import httpx
from actql_sdk import AsyncClient, Client, ClientError
from actql_sdk._values import thaw
from fixtures import PROFILE, ready, reference

LOCAL_PROFILE = PROFILE | {'mode': 'local', 'owner': 'local'}


class DirectHost:
    def __init__(self, respond):
        self.respond = respond
        self.requests = []
        self.closes = 0
        self.close_error = None

    async def open(self, operation, payload):
        self.requests.append((operation, payload))
        return self.respond(operation, json.loads(payload))

    async def aclose(self):
        self.closes += 1
        if self.close_error is not None:
            raise self.close_error


class LocalClientTransportTests(unittest.IsolatedAsyncioTestCase):
    async def test_local_negotiation_uses_closed_wire_without_http_endpoint_or_token(self):
        host = DirectHost(lambda operation, body: httpx.Response(200, json=LOCAL_PROFILE))
        with patch('actql_sdk._async.httpx.AsyncClient', side_effect=AssertionError('HTTP client created')):
            client = await AsyncClient._connect_local(host)
            self.assertEqual(thaw(client.profile), LOCAL_PROFILE)
            self.assertFalse(hasattr(client, '_endpoint'))
            self.assertFalse(hasattr(client, '_token'))
            self.assertEqual(json.loads(host.requests[0][1]), {'connection': {
                'mode': 'local', 'owner': 'local', 'durability': 'durable',
                'consentRefs': [], 'runners': []}})
            self.assertEqual(dict(client.new_submission(nonce='original')), reference())
            await client.aclose()
        self.assertEqual(host.closes, 1)
        self.assertEqual([operation for operation, _ in host.requests], ['connect'])

    async def test_remote_or_unknown_profile_is_rejected_and_original_host_closed(self):
        for profile in (PROFILE, LOCAL_PROFILE | {'extra': None},
                        LOCAL_PROFILE | {'durability': 'volatile'}):
            with self.subTest(profile=profile):
                host = DirectHost(lambda *_: httpx.Response(200, json=profile))
                with self.assertRaisesRegex(ClientError, 'InvalidHostProfile'):
                    await AsyncClient._connect_local(host)
                self.assertEqual(host.closes, 1)

    async def test_submit_response_loss_is_unknown_and_never_resent(self):
        failure = OSError('Original in-process response lost')
        def respond(operation, body):
            if operation == 'connect':
                return httpx.Response(200, json=LOCAL_PROFILE)
            raise failure
        host = DirectHost(respond)
        client = await AsyncClient._connect_local(host)
        ref = client.new_submission(nonce='original')
        with self.assertRaises(ClientError) as raised:
            await client.start_source('SELECT 1', format='sql', submission_ref=ref)
        self.assertEqual(raised.exception.code, 'SubmissionUnknown')
        self.assertEqual(raised.exception.submission_ref, ref)
        self.assertEqual([operation for operation, _ in host.requests], ['connect', 'submit-intent'])
        await client.aclose()

    async def test_ready_and_malformed_outcome_use_same_sdk_model_and_validator(self):
        for malformed in (False, True):
            with self.subTest(malformed=malformed):
                def respond(operation, body):
                    if operation == 'connect':
                        return httpx.Response(200, json=LOCAL_PROFILE)
                    value = ready(body)
                    if malformed:
                        value['extra'] = None
                    return httpx.Response(200, json=value)
                host = DirectHost(respond)
                client = await AsyncClient._connect_local(host)
                try:
                    request = client.start_source('SELECT 1', format='sql', submission_ref=reference())
                    if malformed:
                        with self.assertRaisesRegex(ClientError, 'SubmissionUnknown'):
                            await request
                    else:
                        result = await request
                        self.assertEqual(result.ref['runDefinitionCid'], 'sha256:' + 'd' * 64)
                        self.assertIs(result._client, client)
                finally:
                    await client.aclose()
                self.assertFalse(any(operation == 'cancel' for operation, _ in host.requests))

    async def test_failed_local_close_keeps_same_host_for_explicit_retry(self):
        host = DirectHost(lambda *_: httpx.Response(200, json=LOCAL_PROFILE))
        client = await AsyncClient._connect_local(host)
        host.close_error = OSError('Original physical cleanup pending')
        with self.assertRaisesRegex(ClientError, 'ClientCleanupFailed'):
            await client.aclose()
        self.assertIs(client._transport, host)
        host.close_error = None
        await client.aclose()
        self.assertEqual(host.closes, 2)
        self.assertEqual([operation for operation, _ in host.requests], ['connect'])


class SyncLocalClientTransportTests(unittest.TestCase):
    def test_same_async_model_and_sync_close_without_remote_assembly(self):
        host = DirectHost(lambda operation, body: httpx.Response(200,
            json=LOCAL_PROFILE if operation == 'connect' else ready(body)))
        runner = asyncio.Runner()
        client = Client(runner, runner.run(AsyncClient._connect_local(host)))
        with client:
            result = client.start_source('SELECT 1', format='sql', submission_ref=client.new_submission(nonce='original'))
            self.assertEqual(result.ref['runDefinitionCid'], 'sha256:' + 'd' * 64)
        self.assertEqual(host.closes, 1)
        self.assertEqual([operation for operation, _ in host.requests], ['connect', 'submit-intent'])


if __name__ == '__main__':
    unittest.main()
