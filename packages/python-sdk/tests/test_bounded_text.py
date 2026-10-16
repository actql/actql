"""Manual Remote ingress uses the registered whole-string noncontrol class.

This closes the helper left behind by the machine-schema correction. It does
not change arbitrary schema regex semantics or infer permission from an ID.
"""
import json
import unittest

import httpx
from actql_sdk import AsyncClient, ClientError
from actql_sdk import _wire as wire
from fixtures import ADMISSION, PROFILE, SELECTED


class BoundedTextTests(unittest.TestCase):
    def test_independent_whole_string_noncontrol_vectors(self):
        vectors = [('', False), ('ordinary', True), (' ', True), ('日本😀', True),
            ('x\u2028', True), ('x\u2029', True), ('a\nb', False), ('x\n', False),
            ('x\r', False), ('x\r\n', False), ('x\0', False), ('x\x7f', False),
            ('\n', False)]
        for value, expected in vectors:
            with self.subTest(value=repr(value)):
                self.assertIs(wire.bounded_text(value), expected)
        for value in (None, False, True, 1, [], {}):
            with self.subTest(value=value): self.assertFalse(wire.bounded_text(value))
        self.assertTrue(wire.bounded_text('x' * 256))
        self.assertFalse(wire.bounded_text('x' * 257))
        self.assertTrue(wire.bounded_text('x' * 512, 512))
        self.assertFalse(wire.bounded_text('x' * 513, 512))

    def test_actual_read_packet_rejects_terminal_control_without_global_regex_change(self):
        body = {'connection': SELECTED, 'ref': ADMISSION['ref'], 'resultName': 'answer',
                'format': 'jsonl', 'attemptId': 'original-attempt'}
        self.assertTrue(wire.valid_body('read', body))
        for key in ('resultName', 'attemptId'):
            for suffix in ('\n', '\r', '\0', '\x7f'):
                with self.subTest(key=key, suffix=repr(suffix)):
                    self.assertFalse(wire.valid_body('read', body | {key: body[key] + suffix}))
        # The correction is to this registered class, not every schema pattern.
        self.assertTrue(wire.valid('x\n', {'type': 'string', 'pattern': '^x$'}))


class PublicIngressTests(unittest.IsolatedAsyncioTestCase):
    async def test_result_and_cancel_ids_refuse_before_credentials_or_transport(self):
        requests, credentials = [], []
        def token():
            credentials.append(True); return 'original-token'
        def handle(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            requests.append((operation, json.loads(request.content)))
            return httpx.Response(200, json=PROFILE if operation == 'connect' else ADMISSION)
        async with await AsyncClient.connect('https://host.invalid/', token,
                transport=httpx.MockTransport(handle)) as client:
            run = await client.attach(ADMISSION['ref'])
            for suffix in ('\n', '\r', '\0', '\x7f'):
                with self.subTest(suffix=repr(suffix)), self.assertRaises(ClientError):
                    run.result('answer' + suffix)
                with self.subTest(suffix=repr(suffix)), self.assertRaises(ClientError):
                    run.cancel(cancel_id='original' + suffix)
            for name in (' ', '日本😀', 'x\u2028', 'x\u2029'):
                self.assertIsNotNone(run.result(name))
        self.assertEqual([operation for operation, _ in requests], ['connect', 'attach'])
        self.assertEqual(len(credentials), 2)
