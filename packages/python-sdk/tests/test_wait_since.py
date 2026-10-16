"""Independent current-wire wait consumers; no Host/Run producer simulation."""
import asyncio
import json
import unittest

import httpx

from actql_sdk import AsyncClient, Client, ClientError, RunState
from actql_sdk import _wire as wire
from fixtures import ADMISSION, PROFILE, SELECTED


def state(revision=8, status='succeeded'):
    return {'version': 'actql-run-state/0.1', 'run_id': 'wait-original',
            'revision': revision, 'status': status,
            'updated_at': '2026-10-16T10:00:00.000Z',
            'next_action': {'kind': 'none'}, 'result_available': False,
            'result_availability': {},
            'control': {'revision': 2, 'cancellation_requested': False,
                        'physical_stop': 'unknown'}}


class BodyTests(unittest.TestCase):
    def test_closed_wait_uses_the_state_revision_domain(self):
        body = {'connection': SELECTED, 'ref': ADMISSION['ref'], 'until': None, 'since': None}
        for value in [None, 0, 7, 9007199254740991]:
            with self.subTest(since=value):
                self.assertTrue(wire.valid_body('wait', body | {'since': value}))
        for value in [True, False, -1, -0.0, 0.5, '7', 9007199254740992]:
            with self.subTest(since=repr(value)):
                self.assertFalse(wire.valid_body('wait', body | {'since': value}))
        self.assertFalse(wire.valid_body('wait', {key: value for key, value in body.items() if key != 'since'}))
        self.assertFalse(wire.valid_body('wait', body | {'extra': None}))
        self.assertFalse(wire.valid_body('wait', body | {'until': False}))


class WaitAsyncTests(unittest.IsolatedAsyncioTestCase):
    async def connect(self, reply=None):
        self.requests = []
        self.credentials = 0
        self.reply = state() if reply is None else reply
        def token():
            self.credentials += 1
            return 'fixture-token'
        def handler(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            self.requests.append((operation, json.loads(request.content)))
            if operation == 'connect': return httpx.Response(200, json=PROFILE)
            if operation == 'attach': return httpx.Response(200, json=ADMISSION)
            if isinstance(self.reply, BaseException): raise self.reply
            if isinstance(self.reply, httpx.Response): return self.reply
            return httpx.Response(200, json=self.reply)
        self.client = await AsyncClient.connect('https://host.invalid/', token,
            transport=httpx.MockTransport(handler))
        self.addAsyncCleanup(self.client.aclose)
        return await self.client.attach(ADMISSION['ref'])

    async def test_omission_is_null_and_explicit_zero_is_not_omission(self):
        run = await self.connect()
        for options, expected in [({}, None), ({'since': None}, None), ({'since': 0}, 0)]:
            observed = await run.wait(**options)
            self.assertIsInstance(observed, RunState)
            self.assertEqual(observed.revision, 8)
            self.assertEqual(self.requests[-1][1], {'connection': SELECTED,
                'ref': ADMISSION['ref'], 'until': None, 'since': expected})
        self.assertEqual([operation for operation, _ in self.requests], ['connect', 'attach', 'wait', 'wait', 'wait'])

    async def test_until_and_since_forward_once_without_status_poll(self):
        run = await self.connect()
        result = await run.wait(until='checkpoint', since=7)
        self.assertEqual(result.revision, 8)
        self.assertEqual(result.control['revision'], 2)
        self.assertEqual(self.requests[-1][1]['until'], 'checkpoint')
        self.assertEqual(self.requests[-1][1]['since'], 7)
        self.assertEqual([operation for operation, _ in self.requests], ['connect', 'attach', 'wait'])

    async def test_invalid_since_refuses_before_credentials_or_transport(self):
        run = await self.connect()
        before = (len(self.requests), self.credentials)
        for value in [True, False, -1, -0.0, 1.5, '7', 9007199254740992]:
            with self.subTest(since=repr(value)), self.assertRaises(ClientError):
                await run.wait(since=value)
            self.assertEqual((len(self.requests), self.credentials), before)

    async def test_same_and_older_state_revision_are_not_success(self):
        run = await self.connect()
        for revision in [7, 6]:
            self.reply = state(revision)
            with self.subTest(revision=revision), self.assertRaises(ClientError) as error:
                await run.wait(since=7)
            self.assertEqual(error.exception.code, 'InvalidHostRunState')
        self.assertEqual([operation for operation, _ in self.requests], ['connect', 'attach', 'wait', 'wait'])

    async def test_newer_running_state_does_not_satisfy_wait(self):
        run = await self.connect(state(8, 'running'))
        with self.assertRaises(ClientError) as error: await run.wait(since=7)
        self.assertEqual(error.exception.code, 'InvalidHostRunState')
        self.assertEqual(len(self.requests), 3)

    async def test_control_revision_does_not_replace_state_revision(self):
        run = await self.connect(state(7) | {'control': {'revision': 99,
            'cancellation_requested': True, 'physical_stop': 'unknown'}})
        with self.assertRaises(ClientError): await run.wait(since=7)
        self.reply = state(8)
        observed = await run.wait(since=7)
        self.assertEqual((observed.revision, observed.control['revision']), (8, 2))
        self.assertEqual(observed.control['physical_stop'], 'unknown')

    async def test_timeout_and_future_revision_are_original_host_refusals(self):
        run = await self.connect()
        for code, since in [('WaitTimeout', 7), ('InvalidWaitRevision', 9007199254740991)]:
            self.reply = httpx.Response(409, json={'code': code})
            with self.subTest(code=code), self.assertRaises(ClientError) as error:
                await run.wait(since=since)
            self.assertEqual(error.exception.code, code)
            self.assertEqual(self.requests[-1][1]['since'], since)
        self.assertEqual([operation for operation, _ in self.requests], ['connect', 'attach', 'wait', 'wait'])
        self.assertIsNone(run._latest_control)

    async def test_transport_response_loss_is_not_retried_or_cancelled(self):
        run = await self.connect(httpx.ReadError('lost reply'))
        with self.assertRaises(ClientError) as error: await run.wait(since=7)
        self.assertEqual(error.exception.code, 'ClientTransportUnknown')
        self.assertEqual([operation for operation, _ in self.requests], ['connect', 'attach', 'wait'])
        self.assertIsNone(run._latest_control)

    async def test_closed_client_does_not_dispatch_wait(self):
        run = await self.connect()
        await self.client.aclose()
        with self.assertRaises(ClientError) as error: await run.wait(since=7)
        self.assertEqual(error.exception.code, 'ClientClosed')
        self.assertEqual([operation for operation, _ in self.requests], ['connect', 'attach'])

    async def test_coroutine_cancel_does_not_request_run_cancellation(self):
        entered = asyncio.Event()
        requests = []
        async def handler(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            requests.append(operation)
            if operation == 'connect': return httpx.Response(200, json=PROFILE)
            if operation == 'attach': return httpx.Response(200, json=ADMISSION)
            entered.set()
            await asyncio.Event().wait()
        async with await AsyncClient.connect('https://host.invalid/', 'fixture-token',
                transport=httpx.MockTransport(handler)) as client:
            run = await client.attach(ADMISSION['ref'])
            pending = asyncio.create_task(run.wait(since=7))
            await asyncio.wait_for(entered.wait(), 1)
            pending.cancel()
            with self.assertRaises(asyncio.CancelledError): await pending
            self.assertIsNone(run._latest_control)
        self.assertEqual(requests, ['connect', 'attach', 'wait'])


class WaitSyncTests(unittest.TestCase):
    def test_sync_facade_forwards_the_same_closed_request(self):
        requests = []
        def handler(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            requests.append((operation, json.loads(request.content)))
            return httpx.Response(200, json=PROFILE if operation == 'connect'
                else ADMISSION if operation == 'attach' else state())
        with Client.connect('https://host.invalid/', 'fixture-token',
                transport=httpx.MockTransport(handler)) as client:
            run = client.attach(ADMISSION['ref'])
            self.assertEqual(run.wait(since=7).revision, 8)
            self.assertEqual(requests[-1][1]['since'], 7)
        self.assertEqual([operation for operation, _ in requests], ['connect', 'attach', 'wait'])

    def test_sync_same_revision_is_not_completed_or_retried(self):
        requests = []
        def handler(request):
            operation = request.url.path.rsplit('/', 1)[-1]
            requests.append(operation)
            return httpx.Response(200, json=PROFILE if operation == 'connect'
                else ADMISSION if operation == 'attach' else state(7))
        with Client.connect('https://host.invalid/', 'fixture-token',
                transport=httpx.MockTransport(handler)) as client:
            with self.assertRaises(ClientError): client.attach(ADMISSION['ref']).wait(since=7)
        self.assertEqual(requests, ['connect', 'attach', 'wait'])
