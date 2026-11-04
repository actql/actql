"""Application row schemas share the original reader, bounds and cleanup."""
import asyncio
from dataclasses import dataclass
import json
import unittest

import httpx
from pydantic import BaseModel, TypeAdapter, ValidationError
from actql_sdk import AsyncClient, Client, ClientError
from actql_sdk._reader import retained_value_bytes
from fixtures import PROFILE, reference, ready


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
            raise OSError('private cleanup detail')


class Handler:
    def __init__(self, raw=b'{"n":1}\n\x1e', fail_close=False):
        self.stream, self.operations = Stream(raw, fail_close), []

    def __call__(self, request):
        body = json.loads(request.content)
        operation = request.url.path.rsplit('/', 1)[1]
        self.operations.append(operation)
        if operation == 'connect':
            return httpx.Response(200, json=PROFILE)
        if operation == 'read':
            return httpx.Response(200, stream=self.stream)
        return httpx.Response(200, json=ready(body))


class AsyncSchemaTests(unittest.IsolatedAsyncioTestCase):
    async def open(self, raw=b'{"n":1}\n\x1e', fail_close=False):
        handler = Handler(raw, fail_close)
        client = await AsyncClient.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(handler))
        self.addAsyncCleanup(client.aclose)
        run = await client.start({}, submission_ref=reference())
        return client, run.result('answer'), handler

    async def test_pydantic_model_and_adapter_return_typed_values(self):
        for schema in (Row, TypeAdapter(Row)):
            _, result, handler = await self.open()
            values = await result.all(schema=schema)
            self.assertEqual(values, [Row(n=1)])
            self.assertIs(type(values[0]), Row)
            self.assertEqual(handler.operations, ['connect', 'submit-intent', 'read'])
            self.assertEqual(handler.stream.closes, 1)

    async def test_strict_refusal_preserves_error_attempt_and_counts(self):
        for raw in (b'{"n":"1"}\n\x1e', b'{"n":true}\n\x1e', b'{"n":1.0}\n\x1e'):
            _, result, handler = await self.open(raw)
            reader = result.rows(schema=Row)
            with self.assertRaises(ClientError) as caught:
                await reader.__anext__()
            error = caught.exception
            self.assertEqual(error.code, 'ResultSchemaMismatch')
            self.assertIsInstance(error.validation_error, ValidationError)
            self.assertEqual((error.attempt_id, error.rows_yielded), (reader.attempt_id, 0))
            self.assertEqual(handler.stream.closes, 1)
            self.assertEqual(handler.operations.count('read'), 1)

    async def test_partial_mismatch_yields_only_valid_prefix_without_resend(self):
        _, result, handler = await self.open(b'{"n":1}\n{"n":"secret"}\n\x1e')
        reader = result.rows(schema=Row)
        self.assertEqual(await reader.__anext__(), Row(n=1))
        with self.assertRaises(ClientError) as caught:
            await reader.__anext__()
        self.assertEqual(caught.exception.rows_yielded, 1)
        self.assertNotIn('secret', str(caught.exception))
        await reader.aclose()
        self.assertEqual(handler.operations, ['connect', 'submit-intent', 'read'])

    async def test_invalid_or_async_schema_refused_before_read(self):
        _, result, handler = await self.open()
        class AsyncSchema:
            async def validate_python(self, value, *, strict):
                return value
        for schema in (object(), lambda row: row, AsyncSchema()):
            with self.assertRaises(ClientError) as caught:
                result.rows(schema=schema)
            self.assertEqual(caught.exception.code, 'InvalidResultSchema')
        self.assertNotIn('read', handler.operations)

    async def test_async_result_from_sync_validator_is_not_a_row(self):
        _, result, handler = await self.open()
        class Schema:
            def validate_python(self, value, *, strict):
                async def deferred():
                    return value
                return deferred()
        reader = result.rows(schema=Schema())
        with self.assertRaises(ClientError) as caught:
            await reader.__anext__()
        self.assertEqual((caught.exception.code, reader.rows_yielded), ('InvalidResultSchema', 0))
        self.assertEqual(handler.stream.closes, 1)

    async def test_original_raw_limits_apply_before_validator(self):
        calls = []
        class Schema:
            def validate_python(self, value, *, strict):
                calls.append(value)
                return value
        for options in ({'max_row_wire_bytes': 2}, {'max_row_retained_value_bytes': 1}, {'max_wire_bytes': 2}):
            _, result, _ = await self.open()
            with self.assertRaises(ClientError):
                await result.all(schema=Schema(), **options)
        self.assertEqual(calls, [])

    async def test_all_counts_original_rows_even_if_validator_discards_them(self):
        class Schema:
            def validate_python(self, value, *, strict):
                return None
        for options in ({'max_rows': 1}, {'max_retained_value_bytes': retained_value_bytes({'n': 1})}):
            _, result, handler = await self.open(b'{"n":1}\n{"n":2}\n\x1e')
            with self.assertRaises(ClientError) as caught:
                await result.all(schema=Schema(), **options)
            self.assertEqual(caught.exception.code, 'ResultRetainedLimit')
            self.assertEqual(handler.stream.closes, 1)

    async def test_schema_does_not_supply_missing_transport_completion(self):
        _, result, _ = await self.open(b'{"n":1}\n')
        with self.assertRaises(ClientError) as caught:
            await result.all(schema=Row)
        self.assertEqual((caught.exception.code, caught.exception.rows_yielded), ('IncompleteResultStream', 1))

    async def test_failed_cleanup_keeps_same_reader_and_stream_for_retry(self):
        client, result, handler = await self.open(fail_close=True)
        reader = result.rows(schema=Row)
        self.assertEqual(await reader.__anext__(), Row(n=1))
        response = reader._response
        with self.assertRaises(ClientError) as caught:
            await reader.aclose()
        self.assertEqual(caught.exception.code, 'ReaderCleanupFailed')
        self.assertIn(reader, client._readers)
        self.assertIs(reader._response, response)
        await reader.aclose()
        self.assertNotIn(reader, client._readers)
        self.assertEqual(handler.stream.closes, 2)
        self.assertEqual(handler.operations.count('read'), 1)

    async def test_read_failure_and_cleanup_failure_are_both_preserved(self):
        for raw, schema, code in (
                (b'{"n":"invalid"}\n\x1e', Row, 'ResultSchemaMismatch'),
                (b'{"n":1}\n', None, 'IncompleteResultStream')):
            with self.subTest(code=code):
                client, result, handler = await self.open(raw, fail_close=True)
                reader = result.rows(schema=schema)
                with self.assertRaises(ClientError) as caught:
                    async for _ in reader:
                        pass
                failure = caught.exception
                self.assertEqual(failure.code, code)
                self.assertEqual(failure.cleanup_error.code, 'ReaderCleanupFailed')
                if schema is Row:
                    self.assertIsInstance(failure.validation_error, ValidationError)
                self.assertEqual(failure.attempt_id, reader.attempt_id)
                self.assertIn(reader, client._readers)
                self.assertIsNotNone(reader._response)
                await reader.aclose()
                self.assertNotIn(reader, client._readers)
                self.assertEqual(handler.stream.closes, 2)
                self.assertEqual(handler.operations.count('read'), 1)

    async def test_all_preserves_read_failure_when_context_cleanup_also_fails(self):
        client, result, handler = await self.open(b'{"n":"invalid"}\n\x1e')
        cleanup_pending = True

        async def close():
            handler.stream.closes += 1
            if cleanup_pending:
                raise OSError('private persistent cleanup detail')

        handler.stream.aclose = close
        try:
            with self.assertRaises(ClientError) as caught:
                await result.all(schema=Row)
            failure = caught.exception
            self.assertEqual(failure.code, 'ResultSchemaMismatch')
            self.assertIsInstance(failure.validation_error, ValidationError)
            self.assertEqual(failure.cleanup_error.code, 'ReaderCleanupFailed')
            self.assertEqual(failure.cleanup_error.cleanup_error.code, 'ReaderCleanupFailed')
            self.assertEqual(len(client._readers), 1)
            reader = next(iter(client._readers))
            self.assertEqual(failure.attempt_id, reader.attempt_id)
            self.assertIsNotNone(reader._response)
            self.assertEqual(handler.operations.count('read'), 1)
            cleanup_pending = False
            await reader.aclose()
            self.assertNotIn(reader, client._readers)
            self.assertEqual(handler.stream.closes, 3)
        finally:
            cleanup_pending = False
            await client.aclose()

    async def test_reader_context_preserves_body_failure_and_cancellation(self):
        for primary in (ClientError('ApplicationStopped'), asyncio.CancelledError()):
            with self.subTest(primary=type(primary).__name__):
                client, result, handler = await self.open()
                cleanup_pending = True

                async def close():
                    handler.stream.closes += 1
                    if cleanup_pending:
                        raise OSError('private pending cleanup detail')

                handler.stream.aclose = close
                reader = result.rows()
                try:
                    with self.assertRaises(type(primary)) as caught:
                        async with reader:
                            await reader.__anext__()
                            raise primary
                    self.assertIs(caught.exception, primary)
                    self.assertEqual(primary.cleanup_error.code, 'ReaderCleanupFailed')
                    self.assertIn(reader, client._readers)
                    self.assertIsNotNone(reader._response)
                    cleanup_pending = False
                    await reader.aclose()
                    self.assertNotIn(reader, client._readers)
                    self.assertEqual(handler.operations.count('read'), 1)
                finally:
                    cleanup_pending = False
                    await client.aclose()

    async def test_cancellation_is_not_replaced_by_cleanup_failure(self):
        client, result, handler = await self.open(fail_close=True)
        entered = asyncio.Event()
        async def chunks(_response, _limit):
            entered.set()
            await asyncio.Event().wait()
            yield b''
        client._chunks = chunks
        reader = result.rows()
        reading = asyncio.create_task(reader.__anext__())
        await entered.wait()
        reading.cancel()
        with self.assertRaises(asyncio.CancelledError) as caught:
            await reading
        self.assertEqual(caught.exception.cleanup_error.code, 'ReaderCleanupFailed')
        self.assertEqual(caught.exception.attempt_id, reader.attempt_id)
        await reader.aclose()
        self.assertEqual(handler.stream.closes, 2)

    async def test_validation_keeps_null_omission_unicode_and_custom_result(self):
        @dataclass
        class Value:
            original: dict
        seen = []
        class Schema:
            def validate_python(self, value, *, strict):
                seen.append(strict)
                return Value(value)
        _, result, _ = await self.open('{"null":null,"text":"😀é\\r\\n"}\n\u001e'.encode())
        values = await result.all(schema=Schema())
        self.assertEqual(seen, [True])
        self.assertEqual(values[0].original, {'null': None, 'text': '😀é\r\n'})
        self.assertNotIn('absent', values[0].original)


class SyncSchemaTests(unittest.TestCase):
    def test_sync_uses_same_model_validator_and_attempt_cleanup(self):
        handler = Handler()
        with Client.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(handler)) as client:
            result = client.start({}, submission_ref=reference()).result('answer')
            with result.rows(schema=Row) as reader:
                self.assertEqual(next(reader), Row(n=1))
                self.assertEqual(reader.rows_yielded, 1)
        self.assertEqual(handler.stream.closes, 1)
        self.assertEqual(handler.operations, ['connect', 'submit-intent', 'read'])

    def test_sync_strict_mismatch_and_event_loop_refusal(self):
        handler = Handler(b'{"n":false}\n\x1e')
        with Client.connect('https://host.invalid/', 'token', transport=httpx.MockTransport(handler)) as client:
            result = client.start({}, submission_ref=reference()).result('answer')
            with self.assertRaises(ClientError) as caught:
                result.all(schema=Row)
            self.assertEqual(caught.exception.code, 'ResultSchemaMismatch')
            async def inside_loop():
                with self.assertRaises(ClientError) as error:
                    result.rows(schema=Row)
                self.assertEqual(error.exception.code, 'SyncClientInRunningEventLoop')
            asyncio.run(inside_loop())
        self.assertEqual(handler.operations.count('read'), 1)
