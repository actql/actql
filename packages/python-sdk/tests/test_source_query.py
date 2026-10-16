"""Lazy caller vectors over the real Remote codec/Result reader, transport doubles.

These do not prove the Host's checked-Effect inventory or ordinary Local funding.
"""
import asyncio
from copy import copy, deepcopy
import hashlib
import json
import pickle
import unittest

import httpx
import rfc8785
from pydantic import BaseModel

from actql_sdk import AsyncClient, Client, ClientError, get_submission_input
from fixtures import PROFILE, reference, ready
from test_wait_since import state


def available():
    return {'state': 'available', 'observed_at': '2026-10-17T00:00:00.000Z',
            'reason': 'confirmed_present'}


def success():
    return state() | {'result_available': True, 'result_availability': {'answer': available()}}


class Row(BaseModel):
    n: int


class Stream(httpx.AsyncByteStream):
    def __init__(self, raw, fail_close=False):
        self.raw, self.fail_close, self.closes = raw, fail_close, 0

    async def __aiter__(self):
        yield self.raw

    async def aclose(self):
        self.closes += 1
        if self.fail_close and self.closes == 1:
            raise OSError('Original response cleanup pending')


class Peer:
    def __init__(self, raw=b'{"n":1}\n{"n":2}\n\x1e'):
        self.requests, self.streams = [], []
        self.reply = success()
        self.raw, self.loss, self.fail_close = raw, None, False
        self.entered, self.release = None, None
        self.credentials = 0
        self.admission = None

    def token(self):
        self.credentials += 1
        return 'original-token'

    async def handle(self, request):
        operation = request.url.path.rsplit('/', 1)[-1]
        body = json.loads(request.content)
        self.requests.append((operation, body))
        if operation == self.loss:
            raise httpx.ReadError('Original response lost')
        if operation == 'connect': return httpx.Response(200, json=PROFILE)
        if operation == 'submit-intent':
            if self.entered is not None:
                self.entered.set()
                await self.release.wait()
            return httpx.Response(200, json=ready(body) if self.admission is None else self.admission(body))
        if operation == 'wait': return httpx.Response(200, json=self.reply)
        if operation == 'read':
            stream = Stream(self.raw, self.fail_close)
            self.streams.append(stream)
            return httpx.Response(200, stream=stream)
        raise AssertionError('Unexpected operation: ' + operation)

    def operations(self):
        return [operation for operation, _ in self.requests]


class AsyncQueryTests(unittest.IsolatedAsyncioTestCase):
    async def client(self, peer):
        client = await AsyncClient.connect('https://host.invalid/', peer.token,
            transport=httpx.MockTransport(peer.handle))
        self.addAsyncCleanup(client.aclose)
        return client

    async def test_unused_query_and_reader_close_have_no_submit_or_coroutine(self):
        peer = Peer(); client = await self.client(peer)
        query = client.sql('SELECT 1 AS n')
        self.assertIsNone(query.execution)
        reader = query.rows()
        self.assertIsNone(reader.attempt_id)
        async with reader: pass
        with self.assertRaises(StopAsyncIteration): await reader.__anext__()
        self.assertEqual(peer.operations(), ['connect'])
        self.assertEqual(peer.credentials, 1)
        with self.assertRaises(ClientError) as failure: await reader.delivery_attempt()
        self.assertEqual(failure.exception.code, 'ReadAttemptNotStarted')

    async def test_lazy_same_captured_intent_and_one_submit_for_repeated_reads(self):
        peer = Peer(); client = await self.client(peer)
        params = {'value': {'n': 1}}
        declarations = {'value': {'type': 'json'}}
        original = reference('original-query')
        query = client.sql('SELECT @value AS n', params, submission_ref=original,
                           attempt_id='original-attempt', parameter_declarations=declarations)
        captured = get_submission_input(query)
        params['value']['n'] = 999; declarations['value']['type'] = 'changed'; original['nonce'] = 'changed'
        self.assertEqual(peer.operations(), ['connect'])
        values = await query.all()
        self.assertEqual(values, [{'n': 1}, {'n': 2}])
        self.assertEqual(await query.all(), values)
        self.assertEqual(peer.operations(), ['connect', 'submit-intent', 'wait', 'read', 'read'])
        body = peer.requests[1][1]
        self.assertEqual(body['readOnly'], True)
        self.assertEqual(body['parameters'], {'value': {'n': 1}})
        self.assertEqual(body['input']['parameterDeclarations'], {'value': {'type': 'json'}})
        self.assertEqual(body['submissionRef']['nonce'], 'original-query')
        self.assertEqual(body['attemptRef']['attemptId'], 'original-attempt')
        intent = {key: body[key] for key in ('kind', 'input', 'parameters', 'readOnly')}
        expected = 'sha256:' + hashlib.sha256(rfc8785.dumps({
            'version': 'actql-submitted-intent/0.1', 'intent': intent})).hexdigest()
        self.assertEqual(body['intentCid'], expected)
        self.assertEqual(dict(captured), dict(get_submission_input(query.execution)))
        self.assertNotEqual(peer.requests[3][1]['attemptId'], peer.requests[4][1]['attemptId'])
        self.assertEqual(peer.requests[2][1]['since'], None)
        self.assertEqual(peer.requests[2][1]['until'], 'terminal')
        self.assertTrue(all(stream.closes == 1 for stream in peer.streams))

    async def test_aql_and_explicit_named_result_share_existing_result_selection(self):
        peer = Peer(); peer.reply['result_availability']['other'] = available()
        client = await self.client(peer)
        query = client.aql('FROM source |> LIMIT 2', request_id='chosen-original', result='other')
        await query.all()
        self.assertEqual(peer.requests[1][1]['input']['format'], 'aql')
        self.assertEqual(peer.requests[1][1]['submissionRef']['nonce'], 'chosen-original')
        self.assertEqual(peer.requests[-1][1]['resultName'], 'other')

    async def test_concurrent_consumers_join_original_admission_and_wait(self):
        peer = Peer(); peer.entered, peer.release = asyncio.Event(), asyncio.Event()
        client = await self.client(peer); query = client.sql('SELECT 1 AS n')
        first = asyncio.create_task(query.all())
        await peer.entered.wait()
        second = asyncio.create_task(query.all())
        await asyncio.sleep(0)
        self.assertEqual(peer.operations(), ['connect', 'submit-intent'])
        peer.release.set()
        self.assertEqual(await first, await second)
        self.assertEqual(peer.operations().count('submit-intent'), 1)
        self.assertEqual(peer.operations().count('wait'), 1)
        self.assertEqual(peer.operations().count('read'), 2)

    async def test_original_query_cannot_be_copied_or_serialized(self):
        peer = Peer(); client = await self.client(peer); query = client.sql('SELECT 1')
        for copier in (copy, deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): copier(query)
        self.assertEqual(peer.operations(), ['connect'])

    async def test_submission_loss_keeps_original_unknown_and_never_resends(self):
        peer = Peer(); peer.loss = 'submit-intent'; client = await self.client(peer)
        query = client.sql('SELECT 1', request_id='unknown-original', attempt_id='unknown-attempt')
        failures = []
        for _ in range(2):
            with self.assertRaises(ClientError) as failure: await query.all()
            failures.append(failure.exception)
        self.assertIs(failures[0], failures[1])
        self.assertEqual(failures[0].code, 'SubmissionUnknown')
        self.assertEqual(failures[0].submission_ref['nonce'], 'unknown-original')
        self.assertEqual(get_submission_input(failures[0])['readOnly'], True)
        self.assertIsNone(query.execution)
        self.assertEqual(peer.operations(), ['connect', 'submit-intent'])

    async def test_wait_loss_keeps_original_execution_and_no_poll_resume_cancel(self):
        peer = Peer(); peer.loss = 'wait'; client = await self.client(peer)
        query = client.sql('SELECT 1', request_id='wait-original')
        failures = []
        for _ in range(2):
            with self.assertRaises(ClientError) as failure: await query.all()
            failures.append(failure.exception)
        self.assertIs(failures[0], failures[1])
        self.assertEqual(failures[0].code, 'QueryObservationUnknown')
        self.assertIs(failures[0].execution, query.execution)
        self.assertEqual(failures[0].original_error.code, 'ClientTransportUnknown')
        self.assertEqual(get_submission_input(failures[0])['submissionRef']['nonce'], 'wait-original')
        self.assertEqual(peer.operations(), ['connect', 'submit-intent', 'wait'])

    async def test_cancel_after_submit_entry_retains_attempt_without_second_send(self):
        peer = Peer(); peer.entered, peer.release = asyncio.Event(), asyncio.Event()
        client = await self.client(peer)
        query = client.sql('SELECT 1', request_id='cancel-original', attempt_id='cancel-attempt')
        pending = asyncio.create_task(query.all()); await peer.entered.wait(); pending.cancel()
        with self.assertRaises(asyncio.CancelledError) as failure: await pending
        self.assertEqual(failure.exception.submission_ref['nonce'], 'cancel-original')
        self.assertEqual(failure.exception.attempt_ref['attemptId'], 'cancel-attempt')
        with self.assertRaises(asyncio.CancelledError) as again: await query.all()
        self.assertIs(failure.exception, again.exception)
        self.assertEqual(peer.operations(), ['connect', 'submit-intent'])

    async def test_held_admission_is_not_waited_restarted_or_read(self):
        peer = Peer()
        peer.admission = lambda body: {'kind': 'recorded', 'attemptRef': body['attemptRef'],
            'outcome': {'kind': 'held', 'submissionRef': body['submissionRef'],
                'intentCid': body['intentCid'], 'held': {'kind': 'held',
                    'requestId': body['submissionRef']['nonce'], 'prepareAttemptId': 'held-attempt',
                    'state': 'resuming', 'durability': 'durable', 'lookupExpiresAt': '2026-10-18T00:00:00.000Z'}}}
        client = await self.client(peer); query = client.sql('SELECT 1')
        with self.assertRaises(ClientError) as failure: await query.all()
        self.assertEqual(failure.exception.code, 'RequestHeld')
        with self.assertRaises(ClientError): await query.all()
        self.assertEqual(peer.operations(), ['connect', 'submit-intent'])

    async def test_failed_cancelled_or_unknown_state_never_reads_or_reconciles(self):
        for status in ('failed', 'cancelled', 'needs_reconciliation'):
            peer = Peer(); peer.reply = state(status=status)
            if status == 'needs_reconciliation':
                peer.reply['next_action'] = {'kind': 'reconcile_run', 'reason': 'execution_unknown'}
            client = await self.client(peer); query = client.sql('SELECT 1')
            with self.subTest(status=status), self.assertRaises(ClientError) as failure:
                await query.all()
            self.assertIn(failure.exception.code, ('ExecutionUnsuccessful', 'ExecutionBlocked'))
            self.assertIs(failure.exception.execution, query.execution)
            self.assertEqual(failure.exception.observation.status, status)
            self.assertEqual(peer.operations(), ['connect', 'submit-intent', 'wait'])

    async def test_result_absence_ambiguity_unknown_name_and_unavailability_do_not_read(self):
        cases = [({}, None, 'ResultSelectionRequired'),
            ({'a': available(), 'b': available()}, None, 'ResultSelectionRequired'),
            ({'a': available()}, 'b', 'UnknownResultName'),
            ({'answer': {'state': 'unknown', 'observed_at': '2026-10-17T00:00:00.000Z',
                         'reason': 'store_query_failed'}}, None, 'ResultUnavailable')]
        for names, selected, code in cases:
            peer = Peer(); peer.reply['result_availability'] = names; peer.reply['result_available'] = bool(names)
            client = await self.client(peer); query = client.sql('SELECT 1', result=selected)
            with self.subTest(code=code), self.assertRaises(ClientError) as failure: await query.all()
            self.assertEqual(failure.exception.code, code)
            self.assertEqual(peer.operations(), ['connect', 'submit-intent', 'wait'])

    async def test_arguments_refuse_before_submission_credentials_or_reader(self):
        peer = Peer(); client = await self.client(peer)
        for invoke in (lambda: client.sql('SELECT 1', []), lambda: client.sql('SELECT 1', result=''),
                       lambda: client.sql('SELECT 1', submission_ref=reference(), request_id='other'),
                       lambda: client.sql('SELECT 1', result='bad\n'),
                       lambda: client.sql('SELECT 1', stop_before='commit')):
            with self.assertRaises((ClientError, TypeError)): invoke()
        query = client.sql('SELECT 1')
        for invoke in (lambda: query.all(max_rows=True), lambda: query.rows(schema=object()),
                       lambda: query.all(max_wire_bytes=0), lambda: query.rows(max_row_wire_bytes=1025)):
            with self.assertRaises(ClientError): invoke()
        self.assertEqual((peer.operations(), peer.credentials), (['connect'], 1))

    async def test_reader_prefix_interrupt_and_cleanup_retry_keep_original_reader(self):
        peer = Peer(); peer.fail_close = True; client = await self.client(peer)
        query = client.sql('SELECT 1'); reader = query.rows(schema=Row)
        self.assertEqual(await reader.__anext__(), Row(n=1))
        self.assertEqual(reader.rows_yielded, 1)
        original = reader._reader; response = original._response
        with self.assertRaises(ClientError) as failure: await reader.aclose()
        self.assertEqual(failure.exception.code, 'ReaderCleanupFailed')
        self.assertIs(reader._reader, original); self.assertIs(original._response, response)
        self.assertIn(original, client._readers)
        await reader.aclose()
        self.assertNotIn(original, client._readers)
        self.assertEqual(peer.streams[0].closes, 2)
        self.assertEqual(peer.operations(), ['connect', 'submit-intent', 'wait', 'read'])
        with self.assertRaises(StopAsyncIteration): await reader.__anext__()

    async def test_strict_schema_and_original_retained_limits(self):
        peer = Peer(); client = await self.client(peer)
        query = client.sql('SELECT 1')
        with self.assertRaises(ClientError) as failure: await query.all(schema=Row, max_rows=1)
        self.assertEqual(failure.exception.code, 'ResultRetainedLimit')
        self.assertEqual(peer.streams[0].closes, 1)
        self.assertEqual(peer.operations().count('submit-intent'), 1)
        self.assertEqual(await query.all(schema=Row), [Row(n=1), Row(n=2)])
        self.assertEqual(peer.operations().count('submit-intent'), 1)
        peer.raw = b'{"n":true}\n\x1e'
        with self.assertRaises(ClientError) as failure: await query.all(schema=Row)
        self.assertEqual(failure.exception.code, 'ResultSchemaMismatch')
        self.assertEqual(peer.operations().count('submit-intent'), 1)

    async def test_schema_callback_is_captured_before_lazy_admission(self):
        peer = Peer(); client = await self.client(peer); query = client.sql('SELECT 1')
        class Schema:
            def validate_python(self, value, *, strict):
                self_outer.assertTrue(strict)
                return ('original', value['n'])
        self_outer = self; schema = Schema(); collection = query.all(schema=schema)
        schema.validate_python = lambda *args, **kwargs: self.fail('Replaced callback')
        self.assertEqual(await collection, [('original', 1), ('original', 2)])

    async def test_client_close_prevents_unused_or_selected_query_io(self):
        peer = Peer(); client = await self.client(peer)
        unused = client.sql('SELECT 1'); selected = client.sql('SELECT 2')
        await selected.all(); before = list(peer.operations()); await client.aclose()
        for query in (unused, selected):
            with self.assertRaises(ClientError): await query.all()
        self.assertEqual(peer.operations(), before)


class SyncQueryTests(unittest.TestCase):
    def test_sync_lazy_rows_and_all_use_same_runner_and_original_submission(self):
        peer = Peer()
        with Client.connect('https://host.invalid/', peer.token,
                transport=httpx.MockTransport(peer.handle)) as client:
            query = client.aql('FROM source |> LIMIT 2', request_id='sync-query')
            self.assertEqual(peer.operations(), ['connect'])
            with query.rows(schema=Row) as reader:
                self.assertIsNone(reader.attempt_id)
                self.assertEqual(next(reader), Row(n=1))
            self.assertIsNotNone(query.execution)
            self.assertEqual(query.execution.ref, query._query.execution.ref)
            self.assertEqual(query.all(schema=Row), [Row(n=1), Row(n=2)])
            self.assertEqual(get_submission_input(query)['readOnly'], True)
            for copier in (copy, deepcopy, pickle.dumps):
                with self.assertRaises(TypeError): copier(query)
            async def inside():
                with self.assertRaises(ClientError) as failure: query.rows()
                self.assertEqual(failure.exception.code, 'SyncClientInRunningEventLoop')
            asyncio.run(inside())
        self.assertEqual(peer.operations(), ['connect', 'submit-intent', 'wait', 'read', 'read'])
        self.assertTrue(all(stream.closes == 1 for stream in peer.streams))

    def test_sync_close_of_unused_query_never_submits(self):
        peer = Peer()
        with Client.connect('https://host.invalid/', peer.token,
                transport=httpx.MockTransport(peer.handle)) as client:
            query = client.sql('SELECT 1'); reader = query.rows(); reader.close()
        self.assertEqual(peer.operations(), ['connect'])
