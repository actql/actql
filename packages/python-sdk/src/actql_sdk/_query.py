"""Lazy short queries compose the original submission, Run and Result owners.

Responsibility: invoke one captured read-only submission and select its Result.
Inputs: the Client's admitted packet and an optional explicit Result name.
Identity: the original submission/attempt survives observation loss and copies
are refused; this caller never issues a second submission after entry.
Ownership: readers are the existing Result readers, held through local cleanup.
Synchronization: one caller lock joins concurrent consumption of this handle.
Failure: held, Unknown and non-success states retain their original evidence.
Cancellation: cancelling consumption neither cancels a Run nor authorizes resend.
Resources: the existing negotiated read and retained-value limits apply.
Extension: the Common readOnly restriction, not this module, rejects Effects.
Verification: lazy/cancellation/read-boundary and installed Remote cases.
"""
import asyncio

from ._errors import ClientError
from ._reader import AsyncReader, _capture_rows, tighter


class AsyncQuery:
    """One lazy original query; each explicit read has its own delivery attempt."""
    def __init__(self, client, body, result_name):
        self._client, self._body, self._name = client, body, result_name
        self._lock = asyncio.Lock()
        self._entered = False
        self._result = None
        self._failure = None
        self._execution = None
        self._state = None

    def __copy__(self):
        raise TypeError('OriginalQueryNotCopyable')

    def __deepcopy__(self, memo):
        raise TypeError('OriginalQueryNotCopyable')

    def __reduce_ex__(self, protocol):
        raise TypeError('OriginalQueryNotSerializable')

    @property
    def execution(self):
        return self._execution

    def _error(self, code, cause=None):
        from ._async import _submission_inputs
        from ._values import freeze, snapshot
        error = ClientError(code, execution=self._execution, observation=self._state,
                            original_error=cause, submission_ref=freeze(snapshot(self._body['submissionRef'])),
                            attempt_ref=freeze(snapshot(self._body['attemptRef'])))
        _submission_inputs[error] = freeze(snapshot(self._body))
        return error

    async def _select(self):
        async with self._lock:
            if self._entered:
                if self._failure is not None:
                    raise self._failure
                return self._result
            self._entered = True
            try:
                # The Client captured readOnly in this same original packet.
                # There is no second check/preparation, polling or resubmission.
                self._execution = await self._client._start(self._body)
                try:
                    self._state = await self._execution.wait(until='terminal')
                except ClientError as failure:
                    raise self._error('QueryObservationUnknown', failure) from None
                state = self._state
                if state.status != 'succeeded':
                    code = ('ExecutionUnsuccessful' if state.status in ('failed', 'cancelled')
                            else 'ExecutionBlocked' if state.status in
                            ('waiting_checkpoint', 'needs_reconciliation')
                            else 'ExecutionPending')
                    raise self._error(code)
                names = state.result_availability
                name = self._name
                if name is None:
                    if len(names) != 1:
                        raise self._error('ResultSelectionRequired')
                    name = next(iter(names))
                if name not in names:
                    raise self._error('UnknownResultName')
                if names[name]['state'] != 'available':
                    raise self._error('ResultUnavailable')
                self._result = self._execution.result(name)
            except BaseException as failure:
                # Includes cancellation after entry: keep the original identity,
                # never reinterpret loss of an observation as permission to send.
                self._failure = failure
                if isinstance(failure, asyncio.CancelledError):
                    from ._values import freeze, snapshot
                    failure.submission_ref = freeze(snapshot(self._body['submissionRef']))
                    failure.attempt_ref = freeze(snapshot(self._body['attemptRef']))
                raise
            return self._result

    def rows(self, **read_options):
        return AsyncQueryReader(self, _capture_rows(self._client.profile, **read_options))

    def all(self, *, max_rows=None, max_retained_value_bytes=None, **read_options):
        limits = self._client.profile['limits']
        rows = tighter(max_rows, limits['maxRows'])
        size = tighter(max_retained_value_bytes, limits['maxRetainedValueBytes'])
        captured = _capture_rows(self._client.profile, **read_options)
        return self._all(rows, size, captured)

    async def _all(self, rows, size, captured):
        result = await self._select()
        return await result._all(rows, size, captured)


class AsyncQueryReader:
    """Defer construction to the same Result reader, without owning a Run."""
    def __init__(self, query, captured):
        self._query, self._captured = query, captured
        self._reader = None
        self._open_lock = asyncio.Lock()
        self._closed = False

    @property
    def attempt_id(self):
        return None if self._reader is None else self._reader.attempt_id

    @property
    def rows_yielded(self):
        return 0 if self._reader is None else self._reader.rows_yielded

    async def __aenter__(self):
        if self._closed:
            raise ClientError('ReaderClosed')
        return self

    async def __aexit__(self, *exc):
        await self.aclose()

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self._closed:
            raise StopAsyncIteration
        async with self._open_lock:
            if self._closed:
                raise StopAsyncIteration
            if self._reader is None:
                result = await self._query._select()
                if self._closed:
                    raise StopAsyncIteration
                self._reader = AsyncReader(result, *self._captured)
        return await self._reader.__anext__()

    async def aclose(self):
        self._closed = True
        async with self._open_lock:
            if self._reader is not None:
                # Failed cleanup retains that exact reader and response. Its
                # Client also retains it once the original read has started.
                await self._reader.aclose()

    async def delivery_attempt(self):
        if self._reader is None:
            raise ClientError('ReadAttemptNotStarted')
        return await self._reader.delivery_attempt()
