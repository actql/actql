"""One physical Host invocation; no Run state, outcome or cancellation Owner."""
from __future__ import annotations

import asyncio
from collections.abc import Callable, Iterator
from concurrent.futures import Future
from contextlib import contextmanager
from threading import Condition, Thread, current_thread


class OriginalLocalWork:
    """Retain the actual worker independently of the caller's coroutine/loop.

    Coroutine cancellation never proves physical stop, cancels a Run, or starts
    another invocation. The same Host retains all original Core/File/Store loans.
    This worker only calls the existing Owner-driven physical assembly once.
    """

    def __init__(self, invoke: Callable[[], None], *,
                 on_exit: Callable[[OriginalLocalWork], None] | None = None,
                 owner: object | None = None) -> None:
        if not callable(invoke) or (on_exit is not None and not callable(on_exit)):
            raise ValueError('Invalid original Local physical invocation')
        self._original = self
        self._invoke = invoke
        self._owner = owner
        self._on_exit = on_exit
        self._exit_error: BaseException | None = None
        self._cleanup_error: BaseException | None = None
        self._start_error: BaseException | None = None
        self._creation_refused = False
        self._future: Future[None] = Future()
        self._thread = Thread(target=self._run, name='actql-local-original-work', daemon=False)
        self._invoked = False
        # Fixed physical-worker scaffolding beside its Thread/Future. No
        # individual operation, callback, grant or wait queue is retained here.
        self._control_condition = Condition()
        self._control_waiters = 0

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Local physical invocation')

    @contextmanager
    def _control_turn(self) -> Iterator[None]:
        """Register scheduling interest only; the original Core still decides.

        The Condition lock is never retained while acquiring Core or awaiting.
        Cancellation and every other exit withdraw the same registered turn.
        """
        self._nominal()
        with self._control_condition:
            self._control_waiters += 1
        try:
            yield
        finally:
            with self._control_condition:
                self._control_waiters -= 1
                self._control_condition.notify_all()

    def _yield_to_control(self) -> None:
        """Only this physical worker waits, after releasing Core and its reader.

        Test and wait share the same Condition as withdrawal/notification, so a
        withdrawal before entry sees zero and a later one wakes the worker.
        No sleep occurs on the ordinary no-waiter path. This is not Run pause,
        cancellation, a new scheduler or physical cleanup acknowledgement.
        """
        self._nominal()
        if current_thread() is not self._thread:
            return
        with self._control_condition:
            while self._control_waiters:
                self._control_condition.wait()

    def start(self) -> None:
        self._nominal()
        if self._invoked:
            raise RuntimeError('Original Local physical invocation already started')
        self._invoked = True
        # Mark the independent physical Future running before creating work;
        # cancellation of a loop wrapper cannot cancel this actual invocation.
        try:
            if not self._future.set_running_or_notify_cancel():
                raise RuntimeError('Original Local physical invocation is unavailable')
            self._thread.start()
        except BaseException as error:
            self._start_error = error
            # For this owned fresh CPython Thread, a RuntimeError with no
            # native identity is a rejected creation. Other failures may have
            # created a child: keep its actual Future and custody untouched.
            if (type(error) is RuntimeError and self._thread.ident is None
                    and not self._thread.is_alive()):
                self._creation_refused = True
                try:
                    if self._on_exit is not None:
                        self._on_exit(self)
                except BaseException as cleanup:
                    self._exit_error = cleanup
                if not self._future.done():
                    self._future.set_exception(error)
            raise

    def _run(self) -> None:
        failure: BaseException | None = None
        try:
            self._invoke()
        except BaseException as error:
            failure = error
        try:
            if self._on_exit is not None:
                self._on_exit(self)
        except BaseException as error:
            # Keep the original physical cause separate from scope retirement.
            # Neither formatting nor replacement of either error is necessary.
            self._exit_error = error
            if failure is None:
                failure = error
        if failure is not None:
            self._future.set_exception(failure)
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
        if self._creation_refused and self._start_error is not None:
            raise self._start_error
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
