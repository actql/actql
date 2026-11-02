"""Original Local payload transport into the existing SDK JSONL reader."""
from __future__ import annotations

from collections.abc import AsyncGenerator, AsyncIterator
from typing import TYPE_CHECKING

import httpx

from ._local_core import _Input
from ._local_sdk_payload_reader import OriginalSDKPayloadReader

if TYPE_CHECKING:
    from ._local_product import InstalledLocalHost
    from ._local_saved_read import OriginalSavedResultRead


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
                 saved_read: OriginalSavedResultRead | None = None) -> None:
        if type(reader) is not OriginalSDKPayloadReader or reader._core is not host._core:
            raise ValueError('Foreign original Local SDK response reader')
        reader._nominal()
        if saved_read is not None:
            from ._local_saved_read import OriginalSavedResultRead
            if (type(saved_read) is not OriginalSavedResultRead or saved_read._host is not host
                    or not any(original is saved_read for original in host._saved_result_reads)):
                raise ValueError('Foreign original Saved response custody')
            saved_read._ensure_active()
        self._original = self
        self._host, self._reader = host, reader
        self._saved_read = saved_read
        self._payload_closed = False
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

    async def _chunks(self) -> AsyncGenerator[bytes, None]:
        # Each existing bounded delivery advance shares one allowance across
        # its private accept/offer calls. No budget is held across backpressure
        # or replenished by a private getter/callback.
        iterator = self._original_chunks()
        try:
            while True:
                with self._host._core._host_operation():
                    try:
                        payload = await anext(iterator)
                    except StopAsyncIteration:
                        return
                yield payload
        finally:
            with self._host._core._host_cleanup():
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
            storage.persist_original_terminal(self._reader._request, clock)
            if self._closing:
                raise RuntimeError('Original Local SDK response is closing')
            # The CAS helper returned only after a separate same-Store read of
            # the Core-validated saved receipt/head. Unknown never reaches here.
            yield b'\x1e'
        finally:
            self._reading = False

    def _close(self) -> bool:
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
            if not self._payload_closed:
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
            saved_read = self._saved_read
            if saved_read is not None:
                if not saved_read.close():
                    return False
                self._host._saved_result_reads.remove(saved_read)
                self._saved_read = None
            self._host._response_streams.discard(self)
            self._closed = True
            return True

    async def aclose(self) -> None:
        self._nominal()
        self._closing = True
        if self._iterator is not None:
            await self._iterator.aclose()
        if not self._close():
            raise LocalSDKResponseCleanupPending(self)
