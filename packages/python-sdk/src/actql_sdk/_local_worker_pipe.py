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

    def _current(self) -> None:
        self._nominal()
        self._funding.require_launch()
        self._nominal()

    def prepare(self) -> None:
        """Select nonblocking flags once; partial failure keeps original FDs."""
        self._current()
        if self._prepare_attempted:
            raise RuntimeError('Original worker pipe preparation was already attempted')
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
            self._process.close_parent_descriptors()
        except (LocalWorkerProcessPending, RuntimeError) as failure:
            raise LocalWorkerPipePending(self) from failure
        self._closed = True
