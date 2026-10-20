"""In-process response transport retained by the existing Core Buffer Owner."""
from __future__ import annotations

from collections.abc import AsyncGenerator, AsyncIterator
from typing import TYPE_CHECKING

import httpx

from ._local_core import _Input

if TYPE_CHECKING:
    from ._local_product import InstalledLocalHost


class LocalResponseCleanupPending(RuntimeError):
    def __init__(self, stream: OriginalLocalResponseStream) -> None:
        super().__init__('Original Local response cleanup is pending')
        self.cleanup_stream = stream


class OriginalLocalResponseStream(httpx.AsyncByteStream):
    """One bounded wire response loan, never an admission or execution authority.

    The Core owns its reservation/cleanup. A suspended iterator is physically
    stopped before its original input can close. Failure keeps this exact stream
    and ticket; neither close nor a retry starts/cancels a Run or resends I/O.
    """
    def __init__(self, host: InstalledLocalHost, raw: bytes, *, maximum: int = 8192) -> None:
        if (type(maximum) is not int or maximum not in (8192, 1048576)
                or type(raw) is not bytes or not 0 < len(raw) <= maximum):
            raise ValueError('Invalid bounded original Local response')
        self._original = self
        self._host = host
        self._loan: _Input | None = None
        self._iterator: AsyncGenerator[bytes, None] | None = None
        self._closing = False
        self._reading = False
        self._attached = False
        host._response_streams.add(self)
        with host._core._lock:
            self._loan = host._reserve(lambda: host._core.reserve_input(
                raw, cleanup=lambda: True,
                stopped=lambda _: self._closing and not self._reading))
            host._inputs.append(self._loan)
            for offset in range(0, len(raw), 16384):
                host._core.fill_input(self._loan, offset, min(16384, len(raw) - offset))
            host._core.seal_input(self._loan)

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Local response')
        self._host._nominal()

    def __aiter__(self) -> AsyncIterator[bytes]:
        self._nominal()
        if self._closing or self._iterator is not None or self._loan is None:
            raise RuntimeError('Original Local response is unavailable')
        self._iterator = self._chunks()
        return self._iterator

    async def _chunks(self) -> AsyncGenerator[bytes, None]:
        self._reading = True
        try:
            with self._host._core._lock:
                self._nominal()
                loan = self._loan
                if self._closing or loan is None:
                    raise RuntimeError('Original Local response is closing')
                self._host._core._owned_input(loan)
                raw = self._host._core._inputs[loan.ticket].payload
            for offset in range(0, len(raw), 16384):
                if self._closing:
                    raise RuntimeError('Original Local response is closing')
                yield raw[offset:offset + 16384]
        finally:
            self._reading = False

    def _close(self) -> bool:
        with self._host._core._host_cleanup():
            return self._close_original()

    def _close_original(self) -> bool:
        """Release only after the original iterator is physically stopped."""
        self._nominal()
        self._closing = True
        with self._host._core._lock:
            if self._reading:
                return False
            if self._loan is not None:
                if not self._host._core.close_input(self._loan):
                    return False
                self._host._inputs.remove(self._loan)
                self._loan = None
            self._host._response_streams.discard(self)
            return True

    async def aclose(self) -> None:
        self._nominal()
        self._closing = True
        if self._iterator is not None:
            # A running iterator's failure remains pending; do not claim that
            # coroutine cancellation alone physically stopped the stream.
            await self._iterator.aclose()
        if not self._close():
            raise LocalResponseCleanupPending(self)
