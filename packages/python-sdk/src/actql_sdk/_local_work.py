"""One physical Host invocation; no Run state, outcome or cancellation Owner."""
from __future__ import annotations

import asyncio
from collections.abc import Callable
from concurrent.futures import Future
from threading import Thread


class OriginalLocalWork:
    """Retain the actual worker independently of the caller's coroutine/loop.

    Coroutine cancellation never proves physical stop, cancels a Run, or starts
    another invocation. The same Host retains all original Core/File/Store loans.
    This worker only calls the existing Owner-driven physical assembly once.
    """

    def __init__(self, invoke: Callable[[], None]) -> None:
        if not callable(invoke):
            raise ValueError('Invalid original Local physical invocation')
        self._original = self
        self._invoke = invoke
        self._future: Future[None] = Future()
        self._thread = Thread(target=self._run, name='actql-local-original-work', daemon=False)
        self._invoked = False

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Local physical invocation')

    def start(self) -> None:
        self._nominal()
        if self._invoked:
            raise RuntimeError('Original Local physical invocation already started')
        self._invoked = True
        # Mark the independent physical Future running before creating work;
        # cancellation of a loop wrapper cannot cancel this actual invocation.
        if not self._future.set_running_or_notify_cancel():
            raise RuntimeError('Original Local physical invocation is unavailable')
        try:
            self._thread.start()
        except BaseException as error:
            self._future.set_exception(error)
            raise

    def _run(self) -> None:
        try:
            self._invoke()
        except BaseException as error:
            self._future.set_exception(error)
        else:
            self._future.set_result(None)

    @property
    def stopped(self) -> bool:
        self._nominal()
        return self._invoked and self._future.done() and not self._thread.is_alive()

    async def wait(self) -> None:
        self._nominal()
        if not self._invoked:
            raise RuntimeError('Original Local physical invocation has not started')
        await self.wait_stopped()
        # Observe the independent physical outcome only after actual stop.
        # No loop-owned Future can acquire cancellation custody or retain an
        # unobserved exception when the original awaiting coroutine disappears.
        self._future.result()

    async def wait_stopped(self) -> None:
        """Observe actual worker termination only; do not interpret its outcome."""
        self._nominal()
        if not self._invoked:
            raise RuntimeError('Original Local physical invocation has not started')
        while not self.stopped:
            await asyncio.sleep(0.01)
