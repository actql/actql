"""Physical worker lifetime without a Run or cancellation state machine."""
import asyncio
import copy
from threading import Event
import unittest
from unittest.mock import Mock

from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending
from actql_sdk._local_work import OriginalLocalWork


class LocalWorkTests(unittest.TestCase):
    def test_control_turn_withdrawn_before_worker_entry_cannot_lose_a_wakeup(self):
        finished = Event()
        owner = object()
        work = OriginalLocalWork(lambda: (work._yield_to_control(), finished.set()), owner=owner)
        with work._control_turn():
            self.assertEqual(work._control_waiters, 1)
        work.start()
        self.assertTrue(finished.wait(1))
        asyncio.run(asyncio.wait_for(work.wait(), 2))
        self.assertIs(work._owner, owner)
        self.assertEqual(work._control_waiters, 0)

    def test_worker_waits_for_both_original_control_turns_and_base_exception_withdraws(self):
        entered, finished = Event(), Event()
        owner = object()

        def invoke():
            entered.set()
            work._yield_to_control()
            finished.set()

        work = OriginalLocalWork(invoke, owner=owner)
        original = BaseException('original control failure')
        with self.assertRaises(BaseException) as failed:
            with work._control_turn():
                with work._control_turn():
                    work.start()
                    self.assertTrue(entered.wait(1))
                    self.assertFalse(finished.wait(0.02))
                    self.assertEqual(work._control_waiters, 2)
                self.assertFalse(finished.wait(0.02))
                self.assertEqual(work._control_waiters, 1)
                raise original
        self.assertIs(failed.exception, original)
        self.assertTrue(finished.wait(1))
        asyncio.run(asyncio.wait_for(work.wait(), 2))
        self.assertIs(work._owner, owner)
        self.assertEqual(work._control_waiters, 0)

    def test_worker_failure_keeps_original_owner_and_cause_after_control_handoff(self):
        original = RuntimeError('original producer failure')
        owner = object()
        entered = Event()

        def invoke():
            entered.set()
            work._yield_to_control()
            raise original

        work = OriginalLocalWork(invoke, owner=owner)
        with work._control_turn():
            work.start()
            self.assertTrue(entered.wait(1))
        with self.assertRaises(RuntimeError) as failed:
            asyncio.run(asyncio.wait_for(work.wait(), 2))
        self.assertIs(failed.exception, original)
        self.assertIs(work._owner, owner)
        self.assertEqual(work._control_waiters, 0)

    def test_original_invocation_runs_once_and_copies_have_no_custody(self):
        invoke = Mock()
        work = OriginalLocalWork(invoke)
        with self.assertRaises(RuntimeError):
            asyncio.run(work.wait())
        with self.assertRaises(ValueError):
            copy.copy(work).start()
        work.start()
        asyncio.run(work.wait())
        invoke.assert_called_once_with()
        self.assertTrue(work.stopped)
        with self.assertRaises(RuntimeError):
            work.start()

    def test_cancelled_wait_and_closed_loop_do_not_stop_or_repeat_physical_work(self):
        entered, release = Event(), Event()
        calls = []
        def invoke():
            calls.append('original')
            entered.set()
            if not release.wait(2):
                raise TimeoutError('Test worker was not released')
        work = OriginalLocalWork(invoke)
        work.start()
        try:
            self.assertTrue(entered.wait(1))
            async def cancel_wait():
                task = asyncio.create_task(work.wait())
                await asyncio.sleep(0)
                task.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await task
            asyncio.run(cancel_wait())
            self.assertFalse(work.stopped)
            self.assertTrue(work._thread.is_alive())
            self.assertFalse(work._future.cancelled())
        finally:
            release.set()
            asyncio.run(work.wait_stopped())
        # A new loop observes the same physical outcome, without re-invoking it.
        asyncio.run(work.wait())
        self.assertEqual(calls, ['original'])

    def test_worker_failure_remains_original_exception_and_cleanup_only_waits_for_stop(self):
        error = RuntimeError('Original physical operation is unknown')
        def invoke():
            raise error
        work = OriginalLocalWork(invoke)
        work.start()
        asyncio.run(work.wait_stopped())
        with self.assertRaises(RuntimeError) as failed:
            asyncio.run(work.wait())
        self.assertIs(failed.exception, error)
        self.assertTrue(work.stopped)
        with self.assertRaises(RuntimeError):
            work.start()

    def test_retirement_failure_preserves_original_physical_cause_without_formatting(self):
        class OriginalFailure(RuntimeError):
            def __str__(self):
                raise AssertionError('Original physical cause must remain opaque')
        original = OriginalFailure()
        retirement = RuntimeError('Original operation retirement is pending')
        observed = []

        def invoke():
            raise original

        def finish(work):
            observed.append(work)
            raise retirement

        work = OriginalLocalWork(invoke, on_exit=finish)
        work.start()
        asyncio.run(work.wait_stopped())
        with self.assertRaises(OriginalFailure) as failed:
            asyncio.run(work.wait())
        self.assertIs(failed.exception, original)
        self.assertIs(work._exit_error, retirement)
        self.assertEqual(observed, [work])
        self.assertTrue(work.stopped)

    def test_host_close_cannot_touch_core_loans_before_actual_worker_stop(self):
        release = Event()
        work = OriginalLocalWork(lambda: release.wait(2))
        work.start()
        host = object.__new__(InstalledLocalHost)
        host._original = host
        host._state_observing = False
        host._physical_work = [work]
        # There is intentionally no Core/Store on this fixture: early close
        # must return pending before it can reach any resource cleanup.
        try:
            self.assertFalse(host.close())
        finally:
            release.set()
            asyncio.run(work.wait_stopped())

    def test_async_close_retains_same_host_after_cleanup_failure_without_reinvocation(self):
        invoke = Mock()
        work = OriginalLocalWork(invoke)
        work.start()
        host = object.__new__(InstalledLocalHost)
        host._original = host
        host._physical_work = [work]
        host.close = Mock(side_effect=[False, True])
        with self.assertRaises(LocalProductCleanupPending) as failed:
            asyncio.run(host.aclose())
        self.assertIs(failed.exception.cleanup_host, host)
        asyncio.run(host.aclose())
        self.assertEqual(host.close.call_count, 2)
        invoke.assert_called_once_with()


if __name__ == '__main__':
    unittest.main()
