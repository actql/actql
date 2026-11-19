"""Core-lock contention must not occupy the asynchronous Client's event loop."""
import asyncio
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event, Thread
import unittest
from unittest.mock import patch

from actql_sdk._local_product import InstalledLocalHost, _LOCAL_SELECTION
from actql_sdk._local_work import OriginalLocalWork
from actql_sdk._values import wire_bytes
import test_local_product_operation_port as operation_fixture
import test_local_sdk_results as result_fixture


class AsyncOperationLockTests(unittest.IsolatedAsyncioTestCase):
    async def test_continuing_result_worker_allows_actual_same_run_control_with_real_lock(self):
        with TemporaryDirectory(prefix='actql-control-continuing-') as directory:
            fixture = result_fixture.SDKResultAssemblyTests()
            self.addCleanup(fixture.doCleanups)
            admitted = []
            accept = InstalledLocalHost._accept_original

            def original_admission(*args, **kwargs):
                value = accept(*args, **kwargs)
                admitted.append(value)
                return value

            with patch.object(InstalledLocalHost, '_accept_original', new=original_admission):
                host, core, compute, preflight, publisher, _, _ = fixture.host(Path(directory))
            results = host._execute_original_tasks(compute, preflight, publisher)
            run = compute.start.run
            self.assertEqual(len(admitted), 1)
            self.assertIs(admitted[0][0], run)
            saved = admitted[0][1]  # SAME actual admission, before the fixture's claim row.
            host._register_original_run_reference(run, saved)
            previous = core._call
            feeds, observed = [], []
            started = Event()

            def call(family, name, *args):
                value = previous(family, name, *args)
                if (family, name) == ('result', 'feed'):
                    feeds.append(args[0])
                    started.set()
                if (family, name) == ('result', 'inputs_ready') and len(feeds) < 256:
                    return -7  # Finite original scalar cursor still needs input.
                return value

            core._call = call
            core._invoking = False  # Existing non-executable scalar fixture's idle state.
            work = OriginalLocalWork(lambda: host._capture_original_results(compute, preflight, results),
                on_exit=core._finish_work_operation, owner=run)
            host._physical_work.append(work)
            core._retain_work_operation(work)
            scope = core._host_retained_work
            refusal = ValueError('UnOfferedOriginalControlObservation')

            def selected(*_):
                observed.append((len(feeds), core._host_retained_work is scope))
                raise refusal

            with patch.object(host, '_select_original_run', side_effect=selected):
                work.start()
                try:
                    self.assertTrue(await asyncio.to_thread(started.wait, 1))
                    with self.assertRaises(ValueError) as failed:
                        await asyncio.wait_for(host.open('status', wire_bytes({
                            'connection': _LOCAL_SELECTION, 'ref': json.loads(saved)['ref']})), 10)
                    self.assertIs(failed.exception, refusal)
                    self.assertEqual(len(observed), 1)
                    self.assertGreater(observed[0][0], 0)
                    self.assertLess(observed[0][0], 256,
                        'Control acquired only after the continuously progressing worker finished')
                    self.assertTrue(observed[0][1], 'The control must borrow the SAME original work scope')
                finally:
                    await asyncio.wait_for(work.wait(), 20)
            self.assertEqual(len(feeds), 256)
            self.assertEqual(set(feeds), {results[0].handle})
            self.assertFalse(host._result_chunks)
            self.assertTrue(host.close())

    async def test_base_exception_releases_the_same_thread_lock_without_an_operation(self):
        class OriginalRefusal(BaseException):
            pass
        with TemporaryDirectory(prefix='actql-control-exception-') as directory:
            fixture = operation_fixture.LocalOperationPortTests()
            self.addCleanup(fixture.doCleanups)
            host, core, _, _ = fixture.host(Path(directory))
            refusal = OriginalRefusal()
            with patch.object(host, '_profile', side_effect=refusal):
                with self.assertRaises(OriginalRefusal) as failed:
                    await host._open_operation('connect', {})
            self.assertIs(failed.exception, refusal)
            acquired = []

            def probe():
                held = core._lock.acquire(blocking=False)
                acquired.append(held)
                if held:
                    core._lock.release()

            other = Thread(target=probe)
            other.start()
            other.join(1)
            self.assertFalse(other.is_alive())
            self.assertEqual(acquired, [True])
            self.assertFalse(host._response_streams)
            self.assertTrue(host.close())

    async def contended(self, operation, *, cancel_wait=False, active=False, failure_type=ValueError):
        with TemporaryDirectory(prefix='actql-control-lock-') as directory:
            fixture = operation_fixture.LocalOperationPortTests()
            self.addCleanup(fixture.doCleanups)
            host, core, _, admission = fixture.host(Path(directory))
            reference = json.loads(admission)['ref']
            body = {'connection': _LOCAL_SELECTION, 'ref': reference}
            if operation == 'cancel':
                body |= {'cancelId': 'original-cancel', 'expectedRevision': 0,
                         'attemptRef': {'operation': 'cancel', 'attemptId': 'original-attempt'}}
            entered, release, expired, finish = Event(), Event(), Event(), Event()

            def hold():
                with core._lock:
                    entered.set()
                    if not release.wait(2):
                        expired.set()
                if active and not finish.wait(2):
                    expired.set()

            work = None
            original_scope = None
            if active:
                # The scalar Core fixture has no guest invocation engine. Its
                # idle invocation flag is the same constructor state used by
                # the existing SDK read/operation fixtures, not a grant.
                core._invoking = False
                # Same original admission entry as the existing SDKStart
                # assembly, not a fabricated Run or a public normal acceptance.
                reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
                run, saved = host._accept_original(reference,
                    operation_fixture.input_fixture.INTENT, run_id='original-run')
                self.assertIsNotNone(run)
                host._register_original_run_reference(run, saved)
                body['ref'] = json.loads(saved)['ref']
                work = OriginalLocalWork(hold, on_exit=core._finish_work_operation, owner=run)
                host._physical_work.append(work)
                core._retain_work_operation(work)
                original_scope = core._host_retained_work
                work.start()
                holder = work._thread
            else:
                holder = Thread(target=hold)
                holder.start()
            self.assertTrue(await asyncio.to_thread(entered.wait, 1))
            refusal = failure_type('UnOfferedOriginalControlReference')

            async def request():
                # The imported Host entry is real. Its terminal operation port
                # refuses, without a fabricated Run/status/cancel observation.
                # The assembly fixture's scalar ABI does not implement these
                # operation bodies; this is only acquisition/cancellation law.
                with self.assertRaises(failure_type) as failed:
                    await host.open(operation, wire_bytes(body))
                self.assertIs(failed.exception, refusal)

            port = ('_select_original_run' if active else '_read_original_reference') \
                if operation == 'status' else '_cancel_original'
            with patch.object(host, port, side_effect=refusal) as selected:
                pending = asyncio.create_task(request())
                try:
                    await asyncio.sleep(0.02)
                    self.assertFalse(expired.is_set(), 'Core-lock acquisition blocked the event loop')
                    self.assertFalse(pending.done(), 'An unacquired Core lock cannot run the operation')
                    if active:
                        self.assertEqual(work._control_waiters, 1)
                        self.assertFalse(host.close(), 'Close cannot erase an active control turn')
                        self.assertEqual(work._control_waiters, 1)
                    if cancel_wait:
                        pending.cancel()
                        with self.assertRaises(asyncio.CancelledError):
                            await pending
                        selected.assert_not_called()
                        self.assertFalse(host._response_streams)
                        if active:
                            self.assertEqual(work._control_waiters, 0)
                finally:
                    release.set()
                    try:
                        if not active:
                            await asyncio.to_thread(holder.join, 1)
                            self.assertFalse(holder.is_alive())
                        if not pending.done():
                            await asyncio.wait_for(pending, 2)
                        elif not pending.cancelled():
                            pending.result()
                        if active:
                            self.assertEqual(work._control_waiters, 0)
                            self.assertIs(core._host_retained_work, original_scope)
                            self.assertFalse(host.close(), 'A control call cannot retire the active worker')
                    finally:
                        finish.set()
                        if work is not None:
                            await asyncio.wait_for(work.wait(), 2)
                if not cancel_wait:
                    selected.assert_called_once()
            self.assertTrue(core._lock.acquire(blocking=False), 'No abandoned waiter owns the RLock')
            core._lock.release()
            self.assertTrue(host.close())

    async def test_status_waits_for_the_original_lock_without_blocking_the_event_loop(self):
        await self.contended('status')

    async def test_cancel_waits_for_the_original_lock_without_blocking_the_event_loop(self):
        await self.contended('cancel')

    async def test_cancelled_status_wait_does_not_select_or_retain_an_operation(self):
        await self.contended('status', cancel_wait=True)

    async def test_cancelled_cancel_wait_does_not_select_or_retain_an_operation(self):
        await self.contended('cancel', cancel_wait=True)

    async def test_active_same_run_status_borrows_the_original_scope_after_lock_wait(self):
        await self.contended('status', active=True)

    async def test_active_same_run_cancel_borrows_the_original_scope_after_lock_wait(self):
        await self.contended('cancel', active=True)

    async def test_cancelled_active_status_withdraws_the_same_work_turn_before_acquiring(self):
        await self.contended('status', active=True, cancel_wait=True)

    async def test_cancelled_active_cancel_withdraws_the_same_work_turn_before_acquiring(self):
        await self.contended('cancel', active=True, cancel_wait=True)

    async def test_active_base_exception_withdraws_turn_and_releases_core_with_original_scope(self):
        class OriginalRefusal(BaseException):
            pass
        await self.contended('status', active=True, failure_type=OriginalRefusal)

    async def test_actual_close_while_waiting_refuses_before_the_operation_body(self):
        with TemporaryDirectory(prefix='actql-control-closed-wait-') as directory:
            fixture = operation_fixture.LocalOperationPortTests()
            self.addCleanup(fixture.doCleanups)
            host, core, _, _ = fixture.host(Path(directory))
            entered, release = Event(), Event()
            failures = []

            def close_original():
                try:
                    with core._lock:
                        entered.set()
                        if not release.wait(2):
                            raise TimeoutError('Original close was not released')
                        self.assertTrue(host.close())
                except BaseException as error:
                    failures.append(error)

            other = Thread(target=close_original)
            other.start()
            self.assertTrue(await asyncio.to_thread(entered.wait, 1))
            with patch.object(host, '_profile', wraps=host._profile) as profile:
                pending = asyncio.create_task(host._open_operation('connect', {}))
                try:
                    await asyncio.sleep(0.02)
                    self.assertFalse(pending.done())
                finally:
                    release.set()
                    await asyncio.to_thread(other.join, 1)
                self.assertFalse(other.is_alive())
                self.assertEqual(failures, [])
                with self.assertRaisesRegex(ValueError, 'Host is unavailable'):
                    await pending
                profile.assert_not_called()


if __name__ == '__main__':
    unittest.main()
