import asyncio
from copy import deepcopy
import json
import math
import unittest
from pathlib import Path
from typing import get_type_hints, is_typeddict
import httpx
from actql_sdk import (AsyncClient, Client, ClientError, Observation, get_check_input,
                        get_submission_input, get_submission_check_observation, resolve_check_location,
                        resolve_check_text_range, explain_check_reason)
from actql_sdk import _types, _wire as wire
from actql_sdk._diagnostics import bind_check
from actql_sdk._values import canonical_bytes, content_cid, snapshot, wire_bytes, decode_json
from fixtures import ADMISSION, EPOCH, PROFILE, SELECTED, REVISION, check_report, ready, reference


class ValueTests(unittest.TestCase):
    def test_existing_independent_checkpoint_preimages_and_cids(self):
        vectors = json.loads((Path(__file__).resolve().parents[3] / 'spec/fixtures/remote-effect-checkpoint-vectors.json').read_text())
        self.assertGreater(len(vectors['vectors']), 0)
        for vector in vectors['vectors']:
            with self.subTest(name=vector['name']):
                self.assertEqual(canonical_bytes(vector['body']).decode(), vector['canonical'])
                self.assertEqual(content_cid(vector['body']), vector['cid'])

    def test_values_preserve_absence_null_unicode_and_order(self):
        value = {'missing-example': {}, 'null-example': None, 'e\u0301': ['\r\n', 'é', 'e\u0301']}
        self.assertEqual(snapshot(value), value)
        self.assertEqual(wire_bytes(value), b'{"missing-example":{},"null-example":null,"e\xcc\x81":["\\r\\n","\xc3\xa9","e\xcc\x81"]}')

    def test_unrepresentable_numbers_and_surrogates_are_rejected(self):
        for value in [9007199254740992, math.inf, math.nan, -0.0, '\ud800', {'\ud800': 1}]:
            with self.subTest(value=repr(value)), self.assertRaises(ClientError):
                snapshot(value)

    def test_cycles_and_custom_objects_are_rejected(self):
        cycle = []
        cycle.append(cycle)
        for value in [cycle, object(), (1, 2), {1: 'key'}]:
            with self.assertRaises(ClientError):
                snapshot(value)

    def test_duplicate_and_negative_zero_response_is_rejected(self):
        for raw in [b'{"a":1,"a":2}', b'{"a":-0}', b'{"a":-0.0}', b'{"a":NaN}', b'{"a":"\\ud800"}']:
            with self.assertRaises(ClientError):
                decode_json(raw)

    def test_large_binary64_values_are_not_rounded_or_rejected_as_metadata(self):
        self.assertEqual(decode_json(b'{"value":9007199254740992}'), {'value': 9007199254740992.0})
        with self.assertRaises(ClientError):
            decode_json(b'{"value":9007199254740993}')
        self.assertFalse(wire.valid(9007199254740992.0, {'type': 'integer'}))

    def test_shortest_binary64_integer_spelling_roundtrips_without_metadata_relaxation(self):
        number = float.fromhex('0x1p+63')
        for value, raw in [(number, b'{"n":9223372036854776000}'),
                           (-number, b'{"n":-9223372036854776000}')]:
            self.assertEqual(wire_bytes({'n': value}), raw)
            decoded = decode_json(raw)['n']
            self.assertIs(type(decoded), float)
            self.assertEqual(decoded.hex(), value.hex())
            self.assertFalse(wire.valid(decoded, {'type': 'integer'}))
        for raw in [b'{"n":9223372036854776001}', b'{"n":9007199254740993}']:
            with self.assertRaises(ClientError):
                decode_json(raw)

    def test_canonical_identity_domains_remain_distinct(self):
        self.assertEqual(canonical_bytes({'e\u0301': 'e\u0301\r\n'}), b'{"\xc3\xa9":"e\xcc\x81\\r\\n"}')
        self.assertEqual(canonical_bytes({'e\u0301': 1}, data_keys=True), b'{"e\xcc\x81":1}')
        with self.assertRaises(ClientError):
            canonical_bytes({'é': 1, 'e\u0301': 2})
        self.assertEqual(canonical_bytes({'\ue000': 2, '😀': 1}, data_keys=True), '{"😀":1,"\ue000":2}'.encode())

    def test_wire_matches_ecmascript_integer_key_order_and_numbers(self):
        self.assertEqual(wire_bytes({'10': 1.0, '2': 1e-7, '01': 1e20, '😀': 1e21}),
                         '{"2":1e-7,"10":1,"01":100000000000000000000,"😀":1e+21}'.encode())


class ContractTests(unittest.TestCase):
    def test_closed_schema_rejects_foreign_fields_and_bool_integers(self):
        self.assertTrue(wire.negotiated(PROFILE, 'profile', SELECTED))
        self.assertFalse(wire.negotiated(PROFILE | {'unexpected': 1}, 'profile', SELECTED))
        self.assertFalse(wire.valid(EPOCH | {'notBefore': False}, 'submission_epoch'))
        self.assertFalse(wire.valid(1, {'const': True}))
        self.assertFalse(wire.valid('２０２６', {'type': 'string', 'pattern': r'^\d{4}$'}))

    def test_generated_dtos_resolve_all_forward_annotations(self):
        found = 0
        for value in vars(_types).values():
            if is_typeddict(value):
                get_type_hints(value, vars(_types))
                found += 1
        self.assertGreater(found, 100)

    def test_connection_and_epoch_correlations_are_checked(self):
        self.assertFalse(wire.negotiated(PROFILE | {'owner': 'local'}, 'profile', SELECTED))
        self.assertFalse(wire.negotiated(PROFILE | {'durability': 'volatile'}, 'profile', SELECTED))
        self.assertFalse(wire.submission_ref(reference('e\u0301')))
        self.assertFalse(wire.epoch(EPOCH | {'expiresAt': EPOCH['notBefore']}))

    def test_template_parameters_even_null_are_invalid_requests(self):
        body = {'connection': SELECTED, 'kind': 'program', 'input': {}, 'scope': 'template_only'}
        self.assertTrue(wire.valid_body('check', body))
        for parameters in [None, {}]:
            self.assertFalse(wire.valid_body('check', body | {'parameters': parameters}))

    def test_pins_location_revision_and_scope_relationships_are_checked(self):
        original = check_report()
        self.assertTrue(wire.check_outcome(original))
        self.assertFalse(wire.check_outcome(original | {'report': {key: value for key, value in original['report'].items() if key != 'runnable'}}))
        self.assertFalse(wire.check_outcome(original | {'report': original['report'] | {'runnable': False}}))
        for mutate in ['pin', 'revision', 'position', 'classification']:
            value = deepcopy(original)
            if mutate == 'pin': value['reason_schema_cid'] = 'sha256:' + '0' * 64
            if mutate == 'revision': value['report']['reasons'][0]['location']['revision'] = 'rev:' + '2' * 64
            if mutate == 'position': value['report']['reasons'][0]['location']['end_byte'] = 11
            if mutate == 'classification': value['report']['verdict'] = 'verified'
            with self.subTest(mutate=mutate):
                self.assertFalse(wire.check_outcome(value))
        for field, rejected in (
            ('reason_schema_cid', 'sha256:0d677186f7f4c10c906372124a89eb0a5169fc9a4ecaf97535715ba1815778ac'),
            ('outcome_schema_cid', 'sha256:2cb5ef23a94213780dc377fa9260b9fcfde1e9f7341063bd37cd7a7676aab10f'),
            ('outcome_schema_cid', 'sha256:8963bb2355a4bd563f01695dcc7fc2900b15a219d7afd56375e127322bf9e03a'),
            ('outcome_schema_cid', 'sha256:' + '0' * 64),
        ):
            with self.subTest(rejected_schema_pin=field, cid=rejected):
                self.assertFalse(wire.check_outcome(original | {field: rejected}))


class DiagnosticTests(unittest.TestCase):
    def test_utf8_utf16_crlf_and_eof(self):
        text = 'a😀\r\nbé'
        body = {'kind': 'text', 'scope': 'bound_input', 'input': {'text': text, 'format': 'sql'}, 'parameters': None}
        observation = bind_check(check_report(start=1, end=5), body)
        location = observation['report']['reasons'][0]['location']
        self.assertEqual(resolve_check_location(observation, location)['text'], '😀')
        self.assertEqual(resolve_check_text_range(observation, location), {'start': {'line': 0, 'character': 1}, 'end': {'line': 0, 'character': 3}})
        for at, expected in [(7, {'line': 1, 'character': 0}), (10, {'line': 1, 'character': 2})]:
            current = dict(location, start_byte=at, end_byte=at)
            self.assertEqual(resolve_check_text_range(observation, current)['start'], expected)
        self.assertIsNone(resolve_check_text_range(observation, dict(location, start_byte=6, end_byte=6)))

    def test_invalid_utf8_boundary_is_not_admitted(self):
        with self.assertRaises(ClientError):
            bind_check(check_report(start=2, end=5), {'kind': 'text', 'input': {'text': 'a😀\r\nbé'}, 'parameters': None})

    def test_copies_changed_revision_and_input_do_not_get_custody(self):
        body = {'kind': 'program', 'input': {'é/~': None}, 'parameters': None}
        observation = bind_check(check_report(kind='program', byte_length=13, pointer='/é~1~0'), body)
        location = observation['report']['reasons'][0]['location']
        self.assertIsNotNone(resolve_check_location(observation, location))
        self.assertIsNone(get_check_input(Observation(observation.to_dict()), 'program'))
        current = dict(get_check_input(observation, 'program'))
        current['revision'] = 'rev:' + '2' * 64
        self.assertIsNone(resolve_check_location(observation, location, current))
        current['revision'] = REVISION
        current['value'] = {'é/~': 1}
        self.assertIsNone(resolve_check_location(observation, location, current))
        body['input']['é/~'] = 'changed'
        self.assertIsNone(get_check_input(observation, 'program')['value']['é/~'])

    def test_missing_pointer_is_rejected_but_null_and_parent_exist(self):
        body = {'kind': 'program', 'input': {'x': None}, 'parameters': None}
        for pointer in ['', '/x']:
            self.assertIsNotNone(bind_check(check_report(kind='program', byte_length=10, pointer=pointer), body))
        for pointer in ['/missing', '/x/child', '/x~2']:
            with self.assertRaises(ClientError):
                bind_check(check_report(kind='program', byte_length=10, pointer=pointer), body)

    def test_advice_is_english_and_does_not_echo_private_values(self):
        advice = explain_check_reason({'code': 'expression_type_mismatch', 'facts': {'expected_type': 'number', 'secret': 'do-not-print'}})
        self.assertEqual(advice['summary'], 'An expression argument must have number type.')
        self.assertNotIn('do-not-print', str(advice))


    def test_variant_only_presentation_does_not_require_a_default(self):
        advice = explain_check_reason({'code': 'binding_json_invalid', 'facts': {
            'document': 'parameters', 'issue': 'invalid_unicode', 'secret': 'do-not-print'}})
        self.assertEqual(advice['kind'], 'known')
        self.assertEqual(advice['summary'], 'The binding JSON contains invalid Unicode text.')
        self.assertNotIn('do-not-print', str(advice))
        with self.assertRaises(TypeError):
            advice['kind'] = 'completed'

    def test_unmatched_variant_without_default_is_only_unknown_advice(self):
        advice = explain_check_reason({'code': 'binding_json_invalid', 'facts': {
            'document': 'foreign', 'issue': 'private-do-not-print'}})
        self.assertEqual(advice, {'kind': 'unknown',
            'summary': 'No supported explanation is available for this reason.'})
        self.assertNotIn('private-do-not-print', str(advice))
        self.assertIsNone(get_check_input(advice, 'parameters'))


class AsyncBoundaryTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.requests = []
        self.next_reply = None
        async def handler(request):
            body = json.loads(request.content)
            operation = request.url.path.rsplit('/', 1)[1]
            self.requests.append((operation, body))
            if operation == 'connect': return httpx.Response(200, json=PROFILE)
            if self.next_reply is not None: return await self.next_reply(operation, body)
            return httpx.Response(200, json=ready(body))
        self.client = await AsyncClient.connect('https://host.invalid/', 'fixture-token', transport=httpx.MockTransport(handler))

    async def asyncTearDown(self):
        await self.client.aclose()

    async def test_submission_snapshot_is_captured_before_credentials_or_await(self):
        program = {'value': 'e\u0301'}
        pending = self.client.start(program, submission_ref=self.client.new_submission(nonce='original'), attempt_id='attempt-1')
        program['value'] = 'changed'
        run = await pending
        self.assertEqual(self.requests[-1][1]['input'], {'value': 'e\u0301'})
        self.assertEqual(get_submission_input(run)['input'], {'value': 'e\u0301'})
        self.assertEqual(run.ref, ADMISSION['ref'])

    async def test_lost_submission_reply_retains_identity_without_retry(self):
        async def lost(operation, body): raise httpx.ReadError('secret transport details')
        self.next_reply = lost
        with self.assertRaises(ClientError) as error:
            await self.client.start({}, submission_ref=reference(), attempt_id='lost-attempt')
        self.assertEqual(error.exception.code, 'SubmissionUnknown')
        self.assertEqual(error.exception.submission_ref, reference())
        self.assertEqual(error.exception.attempt_ref['attemptId'], 'lost-attempt')
        self.assertEqual([item[0] for item in self.requests], ['connect', 'submit-intent'])
        self.assertNotIn('secret', str(error.exception))

    async def test_wrong_attempt_or_authority_is_unknown(self):
        async def wrong(operation, body):
            answer = ready(body)
            answer['attemptRef'] = {'operation': 'submit', 'attemptId': 'wrong'}
            return httpx.Response(200, json=answer)
        self.next_reply = wrong
        with self.assertRaises(ClientError) as error:
            await self.client.start({}, submission_ref=reference())
        self.assertEqual(error.exception.code, 'SubmissionUnknown')

    async def test_original_rejection_diagnostics_are_bound_without_resubmission(self):
        async def rejected(operation, body):
            return httpx.Response(200, json={'kind': 'recorded', 'attemptRef': body['attemptRef'], 'outcome': {
                'kind': 'not_accepted', 'submissionRef': body['submissionRef'], 'intentCid': body['intentCid'],
                'problem': {'code': 'ClientProgramInvalidInput', 'classification': 'invalid_input'},
                'checkObservation': check_report(start=1, end=5)}})
        self.next_reply = rejected
        with self.assertRaises(ClientError) as error:
            await self.client.start_source('a😀\r\nbé', format='sql', submission_ref=reference())
        self.assertEqual(error.exception.code, 'SubmissionNotAccepted')
        observation = get_submission_check_observation(error.exception)
        self.assertEqual(get_check_input(observation, 'source')['text'], 'a😀\r\nbé')
        self.assertIsNone(get_submission_check_observation(ClientError(error.exception.code)))
        self.assertEqual(len(self.requests), 2)

    async def test_check_and_sync_loop_rejection_do_not_send(self):
        with self.assertRaises(ClientError):
            self.client.check({}, kind='program', scope='template_only', parameters=None)
        for options in [{'format': None}, {'parameter_declarations': None}]:
            with self.assertRaises(ClientError):
                self.client.check({}, kind='program', scope='template_only', **options)
        with self.assertRaises(ClientError):
            self.client.check('SELECT 1 AS n', kind='text', scope='bound_input', format='sql', parameter_declarations=None)
        with self.assertRaises(ClientError) as error:
            Client.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(lambda request: self.fail('Unexpected I/O')))
        self.assertEqual(error.exception.code, 'SyncClientInRunningEventLoop')
        self.assertEqual(len(self.requests), 1)

    async def test_client_close_does_not_cancel_or_retry(self):
        await self.client.aclose()
        await self.client.aclose()
        self.assertEqual([item[0] for item in self.requests], ['connect'])

    async def test_bounded_read_and_missing_completion_marker(self):
        run = await self.client.start({}, submission_ref=reference())
        async def read(operation, body): return httpx.Response(200, content=b'{"n":1}\n\x1e')
        self.next_reply = read
        self.assertEqual(await run.result('answer').all(max_rows=1), [{'n': 1}])
        async def incomplete(operation, body): return httpx.Response(200, content=b'{"n":1}\n')
        self.next_reply = incomplete
        with self.assertRaises(ClientError) as error:
            await run.result('answer').all()
        self.assertEqual(error.exception.code, 'IncompleteResultStream')
        self.assertEqual(error.exception.rows_yielded, 1)

    async def test_close_interrupts_blocked_reader_without_cancel_or_resend(self):
        run = await self.client.start({}, submission_ref=reference())
        entered = asyncio.Event()
        class Stream(httpx.AsyncByteStream):
            closes = 0
            async def __aiter__(self):
                entered.set()
                await asyncio.Event().wait()
                yield b'not reached'
            async def aclose(self):
                self.closes += 1
        stream = Stream()
        async def read(operation, body): return httpx.Response(200, stream=stream)
        self.next_reply = read
        reader = run.result('answer').rows()
        advance = asyncio.create_task(reader.__anext__())
        await asyncio.wait_for(entered.wait(), 1)
        with self.assertRaises(ClientError) as error:
            await reader.__anext__()
        self.assertEqual(error.exception.code, 'ReaderAdvanceInProgress')
        await asyncio.wait_for(self.client.aclose(), 1)
        with self.assertRaises(StopAsyncIteration):
            await advance
        await reader.aclose()
        self.assertEqual(stream.closes, 1)
        self.assertEqual([item[0] for item in self.requests], ['connect', 'submit-intent', 'read'])

    async def test_failed_reader_cleanup_retries_same_stream_once(self):
        run = await self.client.start({}, submission_ref=reference())
        class Stream(httpx.AsyncByteStream):
            closes = 0
            async def __aiter__(self): yield b'{"n":1}\n\x1e'
            async def aclose(self):
                self.closes += 1
                if self.closes == 1: raise OSError('close failed')
        stream = Stream()
        async def read(operation, body): return httpx.Response(200, stream=stream)
        self.next_reply = read
        reader = run.result('answer').rows()
        self.assertEqual(await reader.__anext__(), {'n': 1})
        with self.assertRaises(ClientError) as error:
            await reader.aclose()
        self.assertEqual(error.exception.code, 'ReaderCleanupFailed')
        self.assertIn(reader, self.client._readers)
        self.assertIsNotNone(reader._response)
        await reader.aclose()
        await reader.aclose()
        self.assertEqual(stream.closes, 2)
        self.assertNotIn(reader, self.client._readers)
        self.assertEqual([item[0] for item in self.requests], ['connect', 'submit-intent', 'read'])

    async def test_client_transport_cleanup_failure_is_retryable(self):
        class Transport(httpx.MockTransport):
            closes = 0
            async def aclose(self):
                self.closes += 1
                if self.closes == 1: raise OSError('close failed')
        transport = Transport(lambda request: httpx.Response(200, json=PROFILE))
        client = await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
        with self.assertRaises(ClientError) as error:
            await client.aclose()
        self.assertEqual(error.exception.code, 'ClientCleanupFailed')
        await client.aclose()
        await client.aclose()
        self.assertEqual(transport.closes, 2)

    async def test_close_during_credential_wait_prevents_submission_io(self):
        entered, resume = asyncio.Event(), asyncio.Event()
        async def credential():
            entered.set()
            await resume.wait()
            return 'fixture-token'
        self.client._token = credential
        pending = asyncio.create_task(self.client.start({}, submission_ref=reference()))
        await asyncio.wait_for(entered.wait(), 1)
        await self.client.aclose()
        resume.set()
        with self.assertRaises(ClientError) as error:
            await pending
        self.assertEqual(error.exception.code, 'SubmissionNotSent')
        self.assertEqual([item[0] for item in self.requests], ['connect'])

    async def test_failed_connect_retains_cleanup_handle(self):
        class Transport(httpx.MockTransport):
            closes = 0
            async def aclose(self):
                self.closes += 1
                if self.closes == 1: raise OSError('close failed')
        transport = Transport(lambda request: httpx.Response(200, json={'unknown': 'invalid profile'}))
        with self.assertRaises(ClientError) as error:
            await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
        self.assertEqual(error.exception.code, 'ClientConnectionCleanupFailed')
        self.assertEqual(error.exception.original_error.code, 'InvalidHostProfile')
        self.assertEqual(error.exception.cleanup_error.code, 'ClientCleanupFailed')
        cleanup = error.exception.cleanup_client
        with self.assertRaises(ClientError):
            cleanup.new_submission()
        await cleanup.aclose()
        await cleanup.aclose()
        self.assertEqual(transport.closes, 2)

    async def test_cancel_loss_uses_original_cancel_reference(self):
        run = await self.client.start({}, submission_ref=reference())
        async def lost(operation, body): raise httpx.ReadError('lost')
        self.next_reply = lost
        with self.assertRaises(ClientError) as error:
            await run.cancel(cancel_id='cancel-original', expected_revision=3, attempt_id='cancel-attempt')
        self.assertEqual(error.exception.code, 'CancellationUnknown')
        self.assertEqual(error.exception.cancel_ref['expectedRevision'], 3)
        self.assertEqual(error.exception.cancel_ref['cancelId'], 'cancel-original')
        self.assertEqual([item[0] for item in self.requests], ['connect', 'submit-intent', 'cancel'])


class SyncBoundaryTests(unittest.TestCase):
    def test_failed_cleanup_keeps_private_runner_for_explicit_retry(self):
        requests = []
        class Transport(httpx.MockTransport):
            closes = 0
            async def aclose(self):
                self.closes += 1
                if self.closes == 1: raise OSError('close failed')
        def handler(request):
            requests.append(request.url.path.rsplit('/', 1)[1])
            return httpx.Response(200, json=PROFILE)
        transport = Transport(handler)
        client = Client.connect('https://host.invalid/', 'token', transport=transport)
        with self.assertRaises(ClientError) as error:
            client.close()
        self.assertEqual(error.exception.code, 'ClientCleanupFailed')
        client.close()
        client.close()
        self.assertEqual(transport.closes, 2)
        self.assertEqual(requests, ['connect'])

    def test_failed_connect_keeps_sync_cleanup_facade(self):
        class Transport(httpx.MockTransport):
            closes = 0
            async def aclose(self):
                self.closes += 1
                if self.closes == 1: raise OSError('close failed')
        transport = Transport(lambda request: httpx.Response(200, json={}))
        with self.assertRaises(ClientError) as error:
            Client.connect('https://host.invalid/', 'token', transport=transport)
        self.assertIsInstance(error.exception.cleanup_client, Client)
        error.exception.cleanup_client.close()
        error.exception.cleanup_client.close()
        self.assertEqual(transport.closes, 2)

    def test_shared_receipts_and_bounded_rows(self):
        requests = []
        def handler(request):
            operation = request.url.path.rsplit('/', 1)[1]
            body = json.loads(request.content)
            requests.append(operation)
            if operation == 'connect': return httpx.Response(200, json=PROFILE)
            if operation == 'read': return httpx.Response(200, content=b'{"n":1}\n\x1e')
            return httpx.Response(200, json=ready(body))
        with Client.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(handler)) as client:
            run = client.start({}, submission_ref=client.new_submission(nonce='original'))
            with run.result('answer').rows() as rows:
                self.assertEqual(list(rows), [{'n': 1}])
        self.assertEqual(requests, ['connect', 'submit-intent', 'read'])


class ConnectionCleanupTests(unittest.TestCase):
    def test_failed_async_negotiation_retains_cleanup_client(self):
        async def exercise():
            class Transport(httpx.MockTransport):
                closes = 0
                async def aclose(self):
                    self.closes += 1
                    if self.closes == 1:
                        raise OSError('transient close failure')
            requests = []
            def reply(request):
                requests.append(request.url.path)
                return httpx.Response(200, json={})
            transport = Transport(reply)
            with self.assertRaises(ClientError) as caught:
                await AsyncClient.connect('https://host.invalid/', 'token', transport=transport)
            failure = caught.exception
            self.assertEqual(failure.code, 'ClientConnectionCleanupFailed')
            self.assertEqual(failure.original_error.code, 'InvalidHostProfile')
            self.assertEqual(failure.cleanup_error.code, 'ClientCleanupFailed')
            await failure.cleanup_client.aclose()
            await failure.cleanup_client.aclose()
            self.assertEqual(transport.closes, 2)
            self.assertEqual(requests, ['/actql/client/0.1/connect'])
        asyncio.run(exercise())

    def test_failed_sync_negotiation_keeps_its_runner_for_cleanup(self):
        class Transport(httpx.MockTransport):
            closes = 0
            async def aclose(self):
                self.closes += 1
                if self.closes == 1:
                    raise OSError('transient close failure')
        requests = []
        def reply(request):
            requests.append(request.url.path)
            return httpx.Response(200, json={})
        transport = Transport(reply)
        with self.assertRaises(ClientError) as caught:
            Client.connect('https://host.invalid/', 'token', transport=transport)
        failure = caught.exception
        self.assertEqual(failure.code, 'ClientConnectionCleanupFailed')
        self.assertEqual(failure.original_error.code, 'InvalidHostProfile')
        self.assertIsInstance(failure.cleanup_client, Client)
        failure.cleanup_client.close()
        failure.cleanup_client.close()
        self.assertEqual(transport.closes, 2)
        self.assertEqual(requests, ['/actql/client/0.1/connect'])
