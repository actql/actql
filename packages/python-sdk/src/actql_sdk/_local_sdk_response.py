"""Original Local payload transport into the existing SDK JSONL reader."""
from __future__ import annotations

import asyncio as _asyncio
from collections.abc import AsyncGenerator, AsyncIterator, Callable
from contextlib import AbstractContextManager
from typing import TYPE_CHECKING

import httpx

from ._local_core import _Input
from ._local_sdk_payload_reader import OriginalSDKPayloadReader
from ._local_storage import LocalStorageCommitUnknown

if TYPE_CHECKING:
    from ._local_product import InstalledLocalHost
    from ._local_saved_read import OriginalSavedResultRead, _SavedRunControl


class LocalSDKResponseCleanupPending(RuntimeError):
    def __init__(self, stream: OriginalLocalSDKResponseStream) -> None:
        super().__init__('Original Local SDK response cleanup is pending')
        self.cleanup_stream = stream


class OriginalLocalSDKResponseStream(httpx.AsyncByteStream):
    """One original descriptor/sink/Store attempt, never a retry controller.

    The Host constructs the already validated reader under its original first
    preparation and selected capacity. A yielded chunk remains borrowed until
    the consumer advances; closing an iterator does not invent acceptance.
    The existing SDK EOF marker follows only independently observed saved
    terminal evidence. Sink completion or a precommit callback alone is not EOF.
    """
    def __init__(self, host: InstalledLocalHost, reader: OriginalSDKPayloadReader, *,
                 saved_read: OriginalSavedResultRead | None = None,
                 live_control: _SavedRunControl | None = None) -> None:
        if type(reader) is not OriginalSDKPayloadReader or reader._core is not host._core:
            raise ValueError('Foreign original Local SDK response reader')
        reader._nominal()
        if saved_read is not None:
            from ._local_saved_read import OriginalSavedResultRead
            if (type(saved_read) is not OriginalSavedResultRead or saved_read._host is not host
                    or saved_read._original is not saved_read
                    or not any(original is saved_read for original in host._saved_result_reads)):
                raise ValueError('Foreign original Saved response custody')
            # Partial construction may already be closing. Retaining the SAME
            # cleanup carrier requires nominal custody, never active permission.
        self._original = self
        self._host, self._reader = host, reader
        self._saved_read = saved_read
        self._live_control = live_control
        self._operation: Callable[[], AbstractContextManager[None]] | None = None
        self._terminal_current: Callable[[], None] | None = None
        self._payload_closed = False
        self._terminal_started = False
        self._reader_cancel_requested = False
        self._clock: _Input | None = None
        self._iterator: AsyncGenerator[bytes, None] | None = None
        self._closing = self._reading = self._attached = False
        self._closed = False
        host._response_streams.add(self)

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Local SDK response')
        self._host._nominal()

    def __aiter__(self) -> AsyncIterator[bytes]:
        self._nominal()
        if self._closing or self._iterator is not None:
            raise RuntimeError('Original Local SDK response is unavailable')
        self._iterator = self._chunks()
        return self._iterator

    def _bind_operation(self) -> None:
        self._nominal()
        if self._operation is not None or self._closing or self._iterator is not None:
            raise RuntimeError('Original Local response operation is unavailable')
        self._operation = self._host._core._capture_saved_read_operation()
        if self._saved_read is not None:
            self._terminal_current = self._saved_read._public_terminal_current(self._operation)
        elif self._live_control is not None:
            from ._local_saved_read import _public_run_current
            self._terminal_current = _public_run_current(self._host, self._live_control, self._operation)
        else:
            raise RuntimeError('Original Local response current control is unavailable')

    def _new_clock(self) -> _Input:
        if self._clock is not None:
            raise RuntimeError('Original Local SDK clock cleanup is pending')
        # This supplies physical time only. Core validates original availability,
        # current grant and immutable attempt; it issues no renewed permission.
        self._clock = self._host._original_sdk_delivery_clock()
        return self._clock

    def _close_clock(self) -> bool:
        if self._clock is not None:
            if not self._host._core.close_input(self._clock):
                return False
            self._host._inputs.remove(self._clock)
            self._clock = None
        return True

    def _check_transfer_current(self) -> None:
        saved_read = self._saved_read
        if saved_read is not None:
            if self._closing:
                raise RuntimeError('Original Local SDK response is closing')
            operation = self._operation or self._host._core._host_operation
            with operation():
                saved_read._check_transfer_current()
        elif self._live_control is not None:
            check = self._terminal_current
            if self._closing or check is None:
                raise RuntimeError('Original Local live response is unavailable')
            self._reader.check_transfer_current()
            check()

    async def _chunks(self) -> AsyncGenerator[bytes, None]:
        # Ordinary Saved preparation, bounded delivery and terminal recording
        # share one operation. The physical frame returns at backpressure.
        operation = self._operation or self._host._core._host_operation
        iterator = self._original_chunks()
        try:
            while True:
                with operation():
                    try:
                        payload = await anext(iterator)
                    except StopAsyncIteration:
                        return
                # The bounded original advance has returned its operation
                # frame. Give waiting controls a turn without confirming this
                # borrowed chunk or carrying a Core/Store lock across an await.
                await _asyncio.sleep(0)
                if self._closing:
                    raise RuntimeError('Original Local SDK response is closing')
                # The offered bytes or terminal marker can survive an await.
                self._check_transfer_current()
                yield payload
        finally:
            # The original generator only returns its iteration flag here.
            # Physical child retirement is the separate synchronous _close()
            # below; never carry a Core cleanup frame across an await.
            await iterator.aclose()

    async def _original_chunks(self) -> AsyncGenerator[bytes, None]:
        self._reading = True
        try:
            while True:
                self._nominal()
                if self._closing:
                    raise RuntimeError('Original Local SDK response is closing')
                clock = self._new_clock()
                output, payload = self._reader.offer(clock)
                # Backpressure keeps the same offered chunk/input/descriptor.
                # There is no sink confirmation if this yield is interrupted.
                yield payload
                if self._closing:
                    raise RuntimeError('Original Local SDK response is closing')
                self._reader.accept(output)
                if not self._close_clock():
                    raise LocalSDKResponseCleanupPending(self)
                descriptor = self._reader._reader
                if descriptor is None:
                    raise RuntimeError('Original Local SDK descriptor is unavailable')
                if descriptor.eof:
                    break
            clock = self._new_clock()
            storage = self._reader._storage
            self._terminal_started = True
            storage.persist_original_terminal(self._reader._request, clock)
            if self._closing:
                raise RuntimeError('Original Local SDK response is closing')
            # The same prevalidated terminal group received physical COMMIT
            # and Core confirmation. Unknown never reaches the terminal marker.
            yield b'\x1e'
        finally:
            self._reading = False

    def _request_reader_cancellation(self) -> None:
        self._nominal()
        if self._operation is not None and not self._closed and not self._terminal_started:
            self._reader_cancel_requested = True

    def _cancel_original_delivery(self) -> bool:
        # Stop the exact physical reader and return its unconfirmed offer
        # before opening the current terminal Store transaction.
        operation = self._operation
        if operation is None:
            raise RuntimeError('Original delivery cancellation has no operation')
        with self._host._core._host_cleanup():
            self._closing = True
            if self._reading:
                return False
            if self._saved_read is not None and not self._saved_read._begin_terminal_cleanup():
                return False
            if not self._reader.close() or not self._close_clock():
                return False
        self._terminal_started = True
        with operation():
            clock = self._new_clock()
            storage, request = self._reader._storage, self._reader._request
            try:
                storage.persist_original_terminal(request, clock, cancelled=True)
            except LocalStorageCommitUnknown as primary:
                try:
                    storage.observe_original_terminal(request, clock)
                except Exception as failed_lookup:
                    raise primary from failed_lookup
        return True

    def _close(self) -> bool:
        if (self._reader_cancel_requested and not self._terminal_started
                and not self._cancel_original_delivery()):
            return False
        with self._host._core._host_cleanup():
            return self._close_original()

    def _close_original(self) -> bool:
        """Release the original children only; no Run cancel or Store replay."""
        self._nominal()
        self._closing = True
        if self._closed:
            return True
        with self._host._core._lock:
            if self._reading:
                return False
            saved_read = self._saved_read
            if not self._payload_closed:
                # A trapped input export can still own the first output and
                # its clock borrow. Start terminal retirement on the same Saved
                # original before asking those children for their real closes.
                if saved_read is not None and not saved_read._begin_terminal_cleanup():
                    return False
                if not self._reader.close():
                    return False
                if not self._reader._storage.close_original_first(self._reader._request):
                    return False
                if not self._close_clock():
                    return False
                self._payload_closed = True
            # The response has returned its actual child loans. Retire this
            # SAME Saved operation now, rather than retaining its area until
            # Client close and blocking the next independently admitted read.
            if saved_read is not None:
                if not saved_read.close():
                    return False
                self._host._saved_result_reads.remove(saved_read)
                self._saved_read = None
            self._host._response_streams.discard(self)
            self._operation = None
            self._live_control = None
            self._terminal_current = None
            self._closed = True
            return True

    async def aclose(self) -> None:
        self._nominal()
        self._closing = True
        if self._iterator is not None:
            await self._iterator.aclose()
        if not self._close():
            raise LocalSDKResponseCleanupPending(self)
