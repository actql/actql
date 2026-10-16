"""Independent Workspace URI and real SDK operation vectors, no Local runtime."""
import asyncio
import json
import traceback
import unittest

import httpx

from actql_sdk import AsyncClient, Client, ClientError, get_submission_input
from actql_sdk._connection import NO_TOKEN, remote_connection
from fixtures import PROFILE, ready
from test_source_query import success

VALID = [
    ('actql://EXAMPLE.test/workspace', 'https://example.test/', 'workspace', None),
    ('ACTQL://example.test:443/Case-Sensitive', 'https://example.test/', 'Case-Sensitive', None),
    ('actql://example.test:8443/w', 'https://example.test:8443/', 'w', None),
    ('actql://example.test/%E6%9D%B1%E4%BA%AC%20workspace', 'https://example.test/', '東京 workspace', None),
    ('actql://example.test/a%253Ab', 'https://example.test/', 'a%3Ab', None),
    ('actql://example.test/space%3Fname%23suffix', 'https://example.test/', 'space?name#suffix', None),
    ('actql://localhost/local', 'https://localhost/', 'local', None),
    ('actql://[0:0:0:0:0:0:0:1]:8443/local', 'https://[::1]:8443/', 'local', None),
    ('actql://127.1/w', 'https://127.0.0.1/', 'w', None),
    ('actql://0x7f000001/w', 'https://127.0.0.1/', 'w', None),
    ('actql://0177.0.0.1/w', 'https://127.0.0.1/', 'w', None),
    ('actql://faß.de/w', 'https://xn--fa-hia.de/', 'w', None),
    ('actql://token:raw%2540%3A%2F%3F%23@example.test/workspace', 'https://example.test/', 'workspace', 'raw%40:/?#'),
    ('actql://token:caf%C3%A9@example.test/w', 'https://example.test/', 'w', 'café'),
]
INVALID = [
    'actql://example.test', 'actql://example.test/', 'actql://example.test/a/b',
    'actql://example.test/a/../b', 'actql://example.test/.',
    'actql://example.test/%2e%2e', 'actql://example.test/a%2Fb',
    'actql://example.test/a%5Cb', 'actql://example.test/a%00b',
    'actql://example.test/%ff', 'actql://example.test/a%2',
    'actql://example.test/a?sslmode=require', 'actql://example.test/a#b',
    'actql://example.test/white space', 'actql://example.test/a\n',
    'actql://example.test/a\r', 'actql://example.test/a\ud800',
    'actql://example.test/%ED%A0%80', 'actql://%65xample.test/a',
    'actql://example.test:70000/a', 'actql://[not-ipv6]/a',
    'actql://token:DO_NOT_DISCLOSE@example.test/a?token=hidden',
    'actql://token:DO_NOT_DISCLOSE@example.test@other.test/a',
    'actql://person:DO_NOT_DISCLOSE@example.test/a',
    'actql://to%6Ben:DO_NOT_DISCLOSE@example.test/a',
    'actql://token:DO_NOT_DISCLOSE:tail@example.test/a',
    'actql://token:DO_NOT_DISCLOSE%0d%0a@example.test/a',
    'actql://token:DO_NOT_DISCLOSE%20tail@example.test/a',
    'actql://token:DO_NOT_DISCLOSE%GG@example.test/a',
    'actql://token:%E6%9D%B1%E4%BA%AC@example.test/a',
    'actql://token:@example.test/a', 'actql://@example.test/a',
    'actql://token:DO_NOT_DISCLOSE@/a', 'actql://token:DO_NOT_DISCLOSE@a\\b/a',
    'actql://example.test/' + 'a' * 257,
    'actql://token:' + 'a' * 8193 + '@example.test/a',
    'actql://token:' + '%61' * 6000 + '@example.test/a',
]


class ParserTests(unittest.TestCase):
    def test_independent_targets_decode_once_and_remain_network_origins(self):
        for uri, origin, workspace, token in VALID:
            with self.subTest(uri=uri):
                result = remote_connection(uri, NO_TOKEN, None)
                self.assertEqual(result, (origin, NO_TOKEN if token is None else token, workspace, True))

    def test_invalid_inputs_have_no_credential_bearing_context_cause_or_diagnostics(self):
        for uri in INVALID:
            with self.subTest(uri=uri), self.assertRaises(ClientError) as failure:
                remote_connection(uri, NO_TOKEN, None)
            error = failure.exception
            self.assertEqual(error.code, 'InvalidConnectionString')
            self.assertIsNone(error.__cause__); self.assertIsNone(error.__context__)
            for diagnostic in [str(error), repr(error), repr(vars(error)), ''.join(traceback.format_exception(error))]:
                self.assertNotIn('DO_NOT_DISCLOSE', diagnostic)

    def test_workspace_utf16_bound_not_python_scalar_count(self):
        for workspace in ('a' * 256, '😀' * 128, 'a\u2028\u2029 b'):
            from urllib.parse import quote
            self.assertEqual(remote_connection('actql://example.test/' + quote(workspace), NO_TOKEN, None)[2], workspace)
        from urllib.parse import quote
        with self.assertRaises(ClientError):
            remote_connection('actql://example.test/' + quote('😀' * 129), NO_TOKEN, None)

    def test_conflicting_credential_and_workspace_selections_never_have_precedence(self):
        for token in ('secret', None, lambda: self.fail('No getter')):
            with self.assertRaises(ClientError) as failure:
                remote_connection('actql://token:secret@example.test/w', token, None)
            self.assertEqual(failure.exception.code, 'ConflictingConnectionCredentials')
        for workspace in ('w', 'other'):
            with self.assertRaises(ClientError) as failure:
                remote_connection('actql://example.test/w', 'secret', workspace)
            self.assertEqual(failure.exception.code, 'ConflictingConnectionWorkspace')

    def test_node_only_http_opt_in_is_unavailable_without_downgrade_or_node(self):
        with self.assertRaises(ClientError) as failure:
            remote_connection('actql://localhost:8080/w?transport=http', lambda: self.fail('No getter'), None)
        self.assertEqual(failure.exception.code, 'LoopbackHttpUnavailable')
        for host in ('example.test', 'localhost.', '127.1', '0x7f000001', '127.000.0.1', '[::ffff:127.0.0.1]'):
            with self.subTest(host=host), self.assertRaises(ClientError) as failure:
                remote_connection('actql://' + host + '/w?transport=http', 'secret', None)
            self.assertEqual(failure.exception.code, 'InvalidConnectionString')
        for query in ('', 'transport=HTTP', 'Transport=http', 'transport=https', 'transport=http&other=x'):
            with self.subTest(query=query), self.assertRaises(ClientError) as failure:
                remote_connection('actql://localhost/w?' + query, 'secret', None)
            self.assertEqual(failure.exception.code, 'InvalidConnectionString')


class RemoteTests(unittest.IsolatedAsyncioTestCase):
    async def test_original_workspace_is_asserted_on_every_operation_and_not_derived_from_run(self):
        requests = []; calls = 0
        async def token():
            nonlocal calls
            calls += 1; return 'original-token'
        def handler(request):
            body = json.loads(request.content); operation = request.url.path.rsplit('/', 1)[-1]
            requests.append((operation, body))
            self.assertEqual(str(request.url).split('/actql/')[0], 'https://host.invalid:8443')
            self.assertEqual(request.headers['authorization'], 'Bearer original-token')
            self.assertEqual(body['connection']['workspaceId'], 'Case-Sensitive')
            self.assertNotIn('actql://', json.dumps(body)); self.assertNotIn('original-token', json.dumps(body))
            if operation == 'connect': return httpx.Response(200, json=PROFILE | {'workspaceId': 'Case-Sensitive'})
            if operation == 'submit-intent': return httpx.Response(200, json=ready(body))
            if operation == 'wait': return httpx.Response(200, json=success())
            if operation == 'read': return httpx.Response(200, content=b'{"n":1}\n\x1e')
            raise AssertionError(operation)
        async with await AsyncClient.connect('actql://HOST.invalid:8443/Case-Sensitive', token,
                transport=httpx.MockTransport(handler)) as client:
            query = client.sql('SELECT 1'); self.assertEqual(await query.all(), [{'n': 1}])
            self.assertNotIn('workspaceId', get_submission_input(query))
            self.assertEqual(client.profile['workspaceId'], 'Case-Sensitive')
        self.assertEqual([op for op, _ in requests], ['connect', 'submit-intent', 'wait', 'read'])
        self.assertEqual(calls, 4)

    async def test_embedded_credential_is_header_only_and_exact_latin1(self):
        def handler(request):
            self.assertIn((b'authorization', b'Bearer caf\xe9'), request.headers.raw)
            self.assertNotIn('token:', str(request.url)); self.assertNotIn('caf', request.content.decode())
            return httpx.Response(200, json=PROFILE | {'workspaceId': 'w'})
        async with await AsyncClient.connect('actql://token:caf%C3%A9@host.invalid/w',
                transport=httpx.MockTransport(handler)) as client:
            self.assertNotIn('caf', repr(client.profile))

    async def test_profile_target_mismatch_is_not_retried_without_assertion(self):
        requests = []
        def handler(request):
            requests.append(request); return httpx.Response(200, json=PROFILE | {'workspaceId': 'other'})
        with self.assertRaises(ClientError) as failure:
            await AsyncClient.connect('actql://token:secret@host.invalid/w', transport=httpx.MockTransport(handler))
        self.assertEqual(failure.exception.code, 'InvalidHostProfile')
        self.assertEqual(len(requests), 1)

    async def test_invalid_selection_precedes_transport_getter_or_engine(self):
        calls = []
        def getter(): calls.append('credential'); return 'secret'
        def handler(request): calls.append('transport'); raise AssertionError('No send')
        for uri in INVALID + ['actql://localhost/w?transport=http']:
            with self.subTest(uri=uri), self.assertRaises(ClientError):
                await AsyncClient.connect(uri, getter, transport=httpx.MockTransport(handler))
        self.assertEqual(calls, [])

    async def test_lost_original_connect_does_not_strip_assertion_or_resend(self):
        requests = []
        def handler(request):
            requests.append(json.loads(request.content)); raise httpx.ReadError('secret-bearing cause')
        with self.assertRaises(ClientError) as failure:
            await AsyncClient.connect('actql://token:secret@host.invalid/w', transport=httpx.MockTransport(handler))
        self.assertEqual(failure.exception.code, 'ClientTransportUnknown')
        self.assertEqual(len(requests), 1); self.assertEqual(requests[0]['connection']['workspaceId'], 'w')
        self.assertNotIn('secret-bearing', repr(vars(failure.exception)))


class SyncTests(unittest.TestCase):
    def test_existing_runner_consumes_the_same_embedded_credential_and_target(self):
        def handler(request):
            self.assertEqual(json.loads(request.content)['connection']['workspaceId'], 'w')
            return httpx.Response(200, json=PROFILE | {'workspaceId': 'w'})
        with Client.connect('actql://token:secret@host.invalid/w', transport=httpx.MockTransport(handler)) as client:
            self.assertEqual(client.profile['workspaceId'], 'w')


if __name__ == '__main__': unittest.main()
