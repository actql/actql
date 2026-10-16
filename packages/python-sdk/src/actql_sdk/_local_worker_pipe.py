"""Bounded nonblocking I/O on one original worker's owned parent descriptors.

No request is retried, no Run state is kept and no child is started here. The
installed funding supplier must already cover parent I/O/loop/buffer lifetimes.
The 65536-byte physical step bound is not a numerical product funding profile.
"""
from __future__ import annotations

import asyncio
import os

from ._local_worker_funding import OriginalWorkerFunding, LocalWorkerFundingUnavailable
from ._local_worker_process import OriginalWorkerProcess, LocalWorkerProcessPending
from ._local_worker_slot import _OriginalDescriptor


class LocalWorkerPipePending(RuntimeError):
    """Same process, FD, partial bytes and original funding remain owned."""

    def __init__(self, pipe: OriginalWorkerPipe) -> None:
        self.cleanup_pipe = pipe
        super().__init__('Original Local worker pipe is unconfirmed')


class OriginalWorkerPipe:
    """Physical byte steps for the thin Client/Wire channel, not a protocol.

    Cancellation or any post-I/O failure retains the exact bytes/progress and
    blocks further I/O. A parent close can retire only its own descriptors. It
    never terminates/cancels a Run, settles funding, or acknowledges child FD or
    Store cleanup. No physical thread, second Root or inherited environment.
    """

    def __init__(self, funding: OriginalWorkerFunding | None, process: OriginalWorkerProcess) -> None:
        if type(funding) is not OriginalWorkerFunding:
            raise LocalWorkerFundingUnavailable('Original worker pipe funding is unavailable')
        if type(process) is not OriginalWorkerProcess or process._funding is not funding:
            raise ValueError('Foreign original worker pipe process')
        self._original = self
        self._native_channel_original: object | None = None
        self._control_header_original: object | None = None
        self._parent_ends: tuple[tuple[str, _OriginalDescriptor, int], ...] | None = None
        self._parent_pid: int | None = None
        self._funding, self._process = funding, process
        self._prepare_attempted = False
        self._prepared = False
        self._active = False
        self._closing = False
        self._closed = False
        self._unknown: BaseException | None = None
        self._write_payload: bytes | None = None
        self._written: int | None = None
        self._read_payload: bytes | None = None
        self._readiness: tuple[asyncio.AbstractEventLoop, int, asyncio.Future[None], bool] | None = None
        self._readiness_remove_attempted = False
        self._readiness_failure: BaseException | None = None
        process._bind_parent_pipe(self)

    def __copy__(self) -> OriginalWorkerPipe:
        raise TypeError('Original Local worker pipe cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> OriginalWorkerPipe:
        raise TypeError('Original Local worker pipe cannot be copied')

    def _nominal(self) -> None:
        if (self._original is not self or self._process._parent_pipe_consumer is not self
                or self._closing or self._closed):
            raise ValueError('Foreign or closing original worker pipe')
        self._process._launchable()
        if self._unknown is not None:
            raise LocalWorkerPipePending(self) from self._unknown

    def _require_original_ends(self, *, allow_retired: bool = False) -> None:
        if self._parent_ends is None:
            return
        if self._process._pid != self._parent_pid:
            raise ValueError('Original worker child identity changed before pipe I/O')
        for kind, original, number in self._parent_ends:
            pair = getattr(self._process, '_' + kind)
            actual = None if pair is None else pair[1 if kind == 'stdin' else 0]
            if (actual is not original or original._original is not original
                    or type(original.value) is not int or original.value != number
                    or not any(d is original for d in self._process._descriptors)
                    or not allow_retired and (original.closed or original.close_attempted)):
                raise ValueError('Original worker parent descriptor changed')

    def _freeze_original_ends(self) -> None:
        if self._parent_ends is not None:
            self._require_original_ends()
            return
        process = self._process
        if type(process._pid) is not int or process._pid <= 0:
            raise ValueError('Original worker child is unavailable')
        ends = []
        for kind in ('stdin', 'stdout', 'stderr'):
            pair = getattr(process, '_' + kind)
            value = None if pair is None else pair[1 if kind == 'stdin' else 0]
            if (type(value) is not _OriginalDescriptor or value._original is not value
                    or value.closed or value.close_attempted or type(value.value) is not int
                    or not 0 <= value.value <= 2**31 - 1
                    or not any(d is value for d in process._descriptors)):
                raise ValueError('Original worker parent descriptor is unavailable')
            ends.append((kind, value, value.value))
        self._parent_pid, self._parent_ends = process._pid, tuple(ends)

    def _current(self) -> None:
        self._nominal()
        self._funding.require_launch()
        self._nominal()
        # The trusted current callback may revoke or replace physical custody.
        # Recheck the same pre-callback originals before a syscall, not after it.
        self._require_original_ends()

    def prepare(self) -> None:
        """Select nonblocking flags once; partial failure keeps original FDs."""
        self._nominal()
        if self._prepare_attempted:
            raise RuntimeError('Original worker pipe preparation was already attempted')
        self._freeze_original_ends()
        self._current()
        self._prepare_attempted = True
        try:
            for kind in ('stdin', 'stdout', 'stderr'):
                descriptor = self._process._borrow_parent_pipe(self, kind)
                try:
                    os.set_blocking(descriptor.value, False)
                    self._current()
                finally:
                    self._process._return_parent_pipe(self)
            self._prepared = True
        except BaseException as failure:
            self._unknown = failure
            raise LocalWorkerPipePending(self) from failure

    async def _ready(self, descriptor: int, *, writing: bool) -> None:
        loop = asyncio.get_running_loop()
        future: asyncio.Future[None] = loop.create_future()
        def observed() -> None:
            if not future.done():
                future.set_result(None)
        register = loop.add_writer if writing else loop.add_reader
        remove = loop.remove_writer if writing else loop.remove_reader
        # Register before awaiting; the process retains this descriptor borrow
        # until this invocation ends. Loop cancellation removes only readiness.
        if self._readiness is not None:
            raise RuntimeError('Original worker readiness remains unconfirmed')
        self._readiness = (loop, descriptor, future, writing)
        self._readiness_remove_attempted = False
        primary: BaseException | None = None
        try:
            register(descriptor, observed)
            await future
        except BaseException as failure:
            primary = failure
            raise
        finally:
            self._readiness_remove_attempted = True
            try:
                if remove(descriptor) is not True:
                    raise RuntimeError('Original worker readiness removal is unconfirmed')
                self._readiness = None
            except BaseException as failure:
                self._readiness_failure = failure
                if primary is None:
                    raise

    async def write(self, payload: bytes) -> int:
        """One physical write step; a partial count is not operation acceptance."""
        if type(payload) is not bytes or not 0 < len(payload) <= 65536:
            raise ValueError('Invalid bounded original worker write')
        self._current()
        if not self._prepared or self._active:
            raise ValueError('Original worker pipe is not ready for a write')
        descriptor = self._process._borrow_parent_pipe(self, 'stdin')
        self._active = True
        self._write_payload, self._written = payload, None
        try:
            while True:
                self._current()
                try:
                    written = os.write(descriptor.value, payload)
                except BlockingIOError:
                    await self._ready(descriptor.value, writing=True)
                    continue
                # Publish observed bytes before the current callback can fail.
                self._written = written
                if type(written) is not int or not 0 < written <= len(payload):
                    raise RuntimeError('Original worker write progress is unavailable')
                self._current()
                self._write_payload = None
                return written
        except BaseException as failure:
            self._unknown = failure
            raise
        finally:
            self._active = False
            self._process._return_parent_pipe(self)

    async def read(self, maximum: int, *, diagnostic: bool = False) -> bytes:
        """One bounded physical read; empty bytes are only observed pipe EOF."""
        if type(maximum) is not int or not 0 < maximum <= 65536 or type(diagnostic) is not bool:
            raise ValueError('Invalid bounded original worker read')
        self._current()
        if not self._prepared or self._active:
            raise ValueError('Original worker pipe is not ready for a read')
        descriptor = self._process._borrow_parent_pipe(self, 'stderr' if diagnostic else 'stdout')
        self._active = True
        try:
            while True:
                self._current()
                try:
                    raw = os.read(descriptor.value, maximum)
                except BlockingIOError:
                    await self._ready(descriptor.value, writing=False)
                    continue
                self._read_payload = raw
                if type(raw) is not bytes or len(raw) > maximum:
                    raise RuntimeError('Original worker read bytes are unavailable')
                self._current()
                return raw
        except BaseException as failure:
            self._unknown = failure
            raise
        finally:
            self._active = False
            self._process._return_parent_pipe(self)

    def close_parent(self) -> None:
        """Retire only parent descriptor copies, preserving unknown originals."""
        if self._original is not self:
            raise ValueError('Foreign original worker pipe')
        if self._closed:
            return
        self._closing = True
        if self._readiness is not None:
            # Do not remove a raw-number watch again after an ambiguous return.
            # Only retirement of this same original loop disposes that watch.
            if not self._readiness[0].is_closed():
                raise LocalWorkerPipePending(self) from self._readiness_failure
            self._readiness = None
        try:
            # A changed raw number is not the original descriptor to close.
            # Keep the same process/pipe responsibility instead of closing it.
            self._require_original_ends(allow_retired=True)
            self._process.close_parent_descriptors()
        except (LocalWorkerProcessPending, RuntimeError, ValueError) as failure:
            raise LocalWorkerPipePending(self) from failure
        self._closed = True
