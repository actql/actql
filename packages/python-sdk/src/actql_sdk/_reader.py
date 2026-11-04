"""Bounded rows with one retained delivery attempt and explicit local cleanup."""
import asyncio
import inspect
import uuid
from . import _wire as wire
from ._errors import ClientError
from ._values import Observation, decode_json, snapshot, thaw, wire_bytes


def retained_value_bytes(value):
    nodes = 0
    def visit(item):
        nonlocal nodes
        nodes += 1
        if type(item) is list:
            for child in item:
                visit(child)
        elif type(item) is dict:
            for key, child in item.items():
                nodes += 1
                visit(key)
                visit(child)
    visit(value)
    return len(wire_bytes(value)) + nodes * 64


def tighter(value, maximum):
    if value is None:
        return maximum
    if not wire.valid(value, {'type': 'integer', 'minimum': 1, 'maximum': maximum}):
        raise ClientError('InvalidReadLimit')
    return int(value)


def _row_validator(schema):
    """Capture one synchronous application validator; never import an engine or schema library."""
    if schema is None:
        return None
    validate = getattr(schema, 'model_validate', None)
    if not callable(validate):
        validate = getattr(schema, 'validate_python', None)
    if not callable(validate) or inspect.iscoroutinefunction(validate):
        raise ClientError('InvalidResultSchema')
    return validate


def _capture_rows(profile, *, schema=None, max_wire_bytes=None, max_row_wire_bytes=None,
                  max_row_retained_value_bytes=None):
    """Capture the existing row contract before a lazy caller performs I/O."""
    limits = profile['limits']
    return ({'wire': tighter(max_wire_bytes, limits['maxReadWireBytes']),
             'row_wire': tighter(max_row_wire_bytes, limits['maxRowWireBytes']),
             'row_retained': tighter(max_row_retained_value_bytes, limits['maxRowRetainedValueBytes'])},
            _row_validator(schema))


class AsyncResult:
    def __init__(self, run, name):
        self._run, self._name = run, name

    def rows(self, *, schema=None, max_wire_bytes=None, max_row_wire_bytes=None, max_row_retained_value_bytes=None):
        return AsyncReader(self, *_capture_rows(self._run._client.profile, schema=schema,
            max_wire_bytes=max_wire_bytes, max_row_wire_bytes=max_row_wire_bytes,
            max_row_retained_value_bytes=max_row_retained_value_bytes))

    async def all(self, *, max_rows=None, max_retained_value_bytes=None, **read_options):
        limits = self._run._client.profile['limits']
        rows = tighter(max_rows, limits['maxRows'])
        size = tighter(max_retained_value_bytes, limits['maxRetainedValueBytes'])
        return await self._all(rows, size, _capture_rows(self._run._client.profile, **read_options))

    async def _all(self, rows, size, captured):
        result, retained = [], 0
        async with AsyncReader(self, *captured) as reader:
            async for row in reader:
                retained += reader._last_retained_bytes
                if len(result) >= rows or retained > size:
                    raise ClientError('ResultRetainedLimit', attempt_id=reader.attempt_id, rows_yielded=reader.rows_yielded)
                result.append(row)
        return result

    async def delivery_attempt(self, attempt_id):
        body = {'ref': thaw(self._run.ref), 'resultName': self._name, 'attemptId': attempt_id}
        value = await self._run._client._request('delivery-attempt', body)
        if not self._valid_delivery(value, attempt_id):
            raise ClientError('InvalidHostDeliveryAttempt')
        return Observation(value)

    def _valid_delivery(self, value, attempt_id):
        if value == {'kind': 'not_found'}:
            return True
        if type(value) is not dict or set(value) != {'kind', 'attempt', 'record', 'hostReleaseReceipt'} or value['kind'] != 'found':
            return False
        attempt, record, receipt = value['attempt'], value['record'], value['hostReleaseReceipt']
        if (not wire.valid(attempt, 'delivery_attempt') or attempt['attempt_id'] != attempt_id
                or attempt['run_definition_cid'] != self._run.ref['runDefinitionCid'] or attempt['result_name'] != self._name):
            return False
        if record is None:
            return receipt is None
        if (not wire.valid(record, 'delivery_record') or record['delivery_attempt_cid'] != attempt['delivery_attempt_cid']
                or (record['sequence'] > 0) != ('prior_record_cid' in record)
                or record['state'] != 'succeeded' and 'result_delivery_receipt_cid' in record):
            return False
        if record['state'] != 'succeeded':
            return receipt is None
        return (wire.valid(receipt, 'result_delivery_receipt')
                and record['result_delivery_receipt_cid'] == receipt['result_delivery_receipt_cid']
                and record['confirmed_byte_count'] == receipt['delivered_byte_count']
                and record['delivered_sha256'] == receipt['delivered_sha256']
                and all(attempt[key] == receipt[key] for key in ('run_definition_cid', 'result_manifest_cid',
                        'result_name', 'result_artifact_cid', 'serialization_contract_cid')))


class AsyncReader:
    def __init__(self, result, limits, validate=None):
        self._result, self._limits, self._validate = result, limits, validate
        self._last_retained_bytes = 0
        self._attempt_id = str(uuid.uuid4())
        self._rows_yielded = 0
        self._response = None
        self._closed = False
        self._started = False
        self._iterator = None
        self._advance = None

    @property
    def attempt_id(self):
        return self._attempt_id

    @property
    def rows_yielded(self):
        return self._rows_yielded

    async def __aenter__(self):
        if self._closed:
            raise ClientError('ReaderClosed')
        return self

    async def __aexit__(self, _type, failure, _traceback):
        try:
            await self.aclose()
        except ClientError as cleanup:
            if failure is None:
                raise
            # Context exit may retry a failed read's response cleanup. Keep
            # that original failure and every cleanup failure on the same reader.
            cleanup.cleanup_error = getattr(failure, 'cleanup_error', None)
            failure.cleanup_error = cleanup

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self._closed:
            raise StopAsyncIteration
        if self._iterator is None:
            self._iterator = self._iterate()
        if self._advance is not None and not self._advance.done():
            raise ClientError('ReaderAdvanceInProgress')
        self._advance = asyncio.create_task(self._iterator.__anext__())
        try:
            return await self._advance
        except ClientError as failure:
            self._result._run._client._redact_connection_failure(failure)
            raise

    async def aclose(self):
        self._closed = True
        if self._advance is not None and self._advance is not asyncio.current_task():
            pending = not self._advance.done()
            if pending:
                self._advance.cancel()
            try:
                await self._advance
            except (asyncio.CancelledError, StopAsyncIteration):
                pass
            except ClientError as error:
                self._result._run._client._redact_connection_failure(error)
                if pending and error.code == 'ReaderCleanupFailed':
                    raise
        try:
            if self._iterator is not None and self._advance is not asyncio.current_task():
                await self._iterator.aclose()
            await self._release()
        except ClientError as failure:
            self._result._run._client._redact_connection_failure(failure)
            raise

    async def _release(self):
        if self._response is not None:
            try:
                await self._result._run._client._close_response(self._response)
            except Exception:
                raise ClientError('ReaderCleanupFailed', attempt_id=self.attempt_id, rows_yielded=self.rows_yielded) from None
            self._response = None
        self._result._run._client._readers.discard(self)

    async def delivery_attempt(self):
        return await self._result.delivery_attempt(self.attempt_id)

    async def _iterate(self):
        if self._started:
            raise ClientError('ReadAttemptAlreadyStarted')
        self._started = True
        run, client = self._result._run, self._result._run._client
        client._readers.add(self)
        buffer = bytearray()
        count = 0
        failure = None
        try:
            self._response = await client._open('read', {'ref': thaw(run.ref), 'resultName': self._result._name,
                                                'format': 'jsonl', 'attemptId': self.attempt_id})
            if self._closed:
                return
            async for chunk in client._chunks(self._response, min(8192, self._limits['row_wire'])):
                if self._closed:
                    return
                count += len(chunk)
                if count > self._limits['wire']:
                    raise ClientError('ResultWireLimit')
                buffer.extend(chunk)
                while b'\n' in buffer:
                    boundary = buffer.index(10)
                    raw = bytes(buffer[:boundary])
                    del buffer[:boundary + 1]
                    if len(raw) > self._limits['row_wire']:
                        raise ClientError('ResultRowWireLimit')
                    row = decode_json(raw)
                    if type(row) is not dict:
                        raise ClientError('InvalidResultFrame')
                    retained = retained_value_bytes(row)
                    if retained > self._limits['row_retained']:
                        raise ClientError('ResultRowRetainedLimit')
                    value = row
                    if self._validate is not None:
                        try:
                            value = self._validate(row, strict=True)
                        except Exception as error:
                            raise ClientError('ResultSchemaMismatch', validation_error=error) from None
                        if inspect.isawaitable(value):
                            if inspect.iscoroutine(value):
                                value.close()
                            raise ClientError('InvalidResultSchema')
                    # Application-created typed objects do not replace the original
                    # decoded-row accounting or confer a completed delivery receipt.
                    self._last_retained_bytes = retained
                    self._rows_yielded += 1
                    yield value
                    if self._closed:
                        return
                if len(buffer) > self._limits['row_wire']:
                    raise ClientError('ResultRowWireLimit')
            if buffer != b'\x1e':
                raise ClientError('IncompleteResultStream')
        except asyncio.CancelledError as error:
            if self._closed:
                return
            failure = error
            failure.attempt_id, failure.rows_yielded = self.attempt_id, self.rows_yielded
            raise
        except ClientError as error:
            failure = error
            failure.attempt_id, failure.rows_yielded = self.attempt_id, self.rows_yielded
            raise failure from None
        except Exception:
            failure = ClientError('ReadOutcomeUnknown', attempt_id=self.attempt_id, rows_yielded=self.rows_yielded)
            raise failure from None
        finally:
            self._closed = True
            try:
                await self._release()
            except ClientError as cleanup:
                if failure is None:
                    raise
                # Preserve the original read/cancellation and the same pending
                # response. A cleanup failure supplies no resend permission.
                failure.cleanup_error = cleanup
