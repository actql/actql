"""Actual caller/locks with explicit scalar/current ports; no Core/Run/ACK acceptance."""
import asyncio
import json
from threading import Event, RLock, current_thread
from types import MethodType, SimpleNamespace
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError
from actql_sdk._local_product import (
    InstalledLocalHost, LocalProductCleanupPending, _OriginalExecution,
    _OriginalCancellationStop, _LOCAL_SELECTION,
)
from actql_sdk._local_work import OriginalLocalWork


class CancellationStopInterestTests(unittest.TestCase):
    def fixture(self, interest, *, pending=False):
        host = object.__new__(InstalledLocalHost)
        run = SimpleNamespace(handle=71)
        compute = SimpleNamespace(start=SimpleNamespace(run=run), core=object())
        core = SimpleNamespace(_lock=RLock(), _task_loans={}, _host_retained_work=None)
        host._core, host._original = core, host
        host._tasks, host._projections, host._append_sources = [], [], {}
        host._pending_cancellation_write = None
        host._configuration = SimpleNamespace(handle=81, sdk=True)
        preflight, publisher = object(), object()
        host._source_free_computes = [compute]
        host._publication_preflights, host._publishers = [preflight], [publisher]
        host._runs = SimpleNamespace(_run=lambda value: self.assertIs(value, run),
                                     _compute=lambda value: self.assertIs(value, compute))
        current, projection, source = object(), object(), object()
        events = []
        callbacks = SimpleNamespace(failure=None)
        binding = SimpleNamespace(inspect=lambda callback: callback(current))
        installation = SimpleNamespace(_store=object(), _epoch=object(), binding=binding)
        host._active = lambda: installation
        host._checked_original_read = lambda entered, operation: operation()
        host._copy = lambda raw: source
        host._reserve = lambda acquire: acquire()
        host._close_projection = lambda value: events.append('projection-return') or True
        reference = {'namespaceId': 'scope', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'b' * 64}
        host._find_original_run_reference = lambda raw: SimpleNamespace(run=run)
        attempt = {'operation': 'cancel', 'attemptId': 'attempt-original'}
        cancel_ref = dict(reference, cancelId='cancel-original', expectedRevision=19)
        cancellation = {'ref': reference, 'cancelRef': cancel_ref, 'kind': 'accepted', 'revision': 20}
        response = {'kind': 'accepted', 'attemptRef': attempt, 'cancellation': cancellation}
        packet = json.dumps({'response': json.dumps(response), 'writes': []}).encode()
        body = {'connection': _LOCAL_SELECTION, 'ref': reference,
                'cancelId': 'cancel-original', 'expectedRevision': 19, 'attemptRef': attempt}
        core.reserve_submission_projection = lambda *args, **kwargs: projection
        core.produce_cancellation_append = lambda value, entered: events.append('produce')
        core.read_cancellation_append = lambda value, entered: packet

        def confirm(value, entered, **options):
            self.assertTrue(core._lock._is_owned())
            self.assertIs(value, projection)
            self.assertIs(entered, current)
            events.append('confirmed-original')
            return True

        core.confirm_cancellation_append = confirm
        core._owned_output = lambda value, family: self.assertIs(value, projection)
        core._host_current_ready = lambda value: callbacks
        core._check = LocalCore._check

        def scalar(family, name, *args):
            self.assertTrue(core._lock._is_owned())
            self.assertEqual((family, name), ('submission', 'cancellation_stop_interest'))
            self.assertEqual(args, (projection.handle, run.handle, current.handle))
            self.assertIn('confirmed-original', events)
            events.append('core-stop-observation')
            return interest

        # Opaque scalar/current ports are intentionally not actual constructor
        # or authority evidence. The production shim/caller remain imported.
        projection = SimpleNamespace(handle=91, ticket=92)
        current = SimpleNamespace(handle=82)
        core._call = scalar
        core.cancellation_stop_interest = MethodType(LocalCore.cancellation_stop_interest, core)
        original = _OriginalExecution(host, run, reference=object())
        first_drive, registered = Event(), Event()
        primary = LocalCoreError('task_drive', -35)
        task = SimpleNamespace(handle=101)
        selected = False
        drives = []

        def reserve(*args):
            nonlocal selected
            self.assertTrue(core._lock._is_owned())
            if selected:
                raise AssertionError('A cancelled original cannot reserve another task')
            selected = True
            core._task_loans[task.handle] = task
            return task

        def drive(value, quantum):
            self.assertTrue(core._lock._is_owned())
            self.assertIs(value, task)
            drives.append(value)
            if len(drives) == 1:
                first_drive.set()
                if not registered.wait(2):
                    raise AssertionError('Control interest was not registered')
                return False
            raise primary

        core.reserve_next_sdk_task, core.drive_task = reserve, drive
        core.close_native_compute = lambda value: events.append('seal-original-compute') or False
        core._owned_task = lambda value: self.assertIs(core._task_loans.get(value.handle), value)
        core.task_cleanup_continuation = lambda value: -1

        def close_task(value):
            events.append('close-original-task')
            if pending:
                return False
            del core._task_loans[value.handle]
            return True

        core.close_task = close_task
        host._execute_original_admitted_run = lambda value: host._execute_original_tasks(
            compute, preflight, publisher)
        work = OriginalLocalWork(original, owner=run)
        host._physical_work = [work]
        core._host_retained_work = (work,)
        return host, core, original, work, body, first_drive, registered, drives, events, primary

    def exercise(self, interest, *, pending=False):
        values = self.fixture(interest, pending=pending)
        host, core, original, work, body, first_drive, registered, drives, events, primary = values
        work.start()
        try:
            self.assertTrue(first_drive.wait(2))
            # Register before acquiring Core. The worker has already passed
            # its first normal gate; this is the stale-check/commit race.
            with work._control_turn():
                registered.set()
                with core._lock:
                    if interest < 0:
                        with self.assertRaises(LocalCoreError) as refused:
                            host._cancel_original(body)
                        self.assertEqual(refused.exception.code, interest)
                    else:
                        host._cancel_original(body)
            work._thread.join(3)
            self.assertFalse(work._thread.is_alive())
            return values
        finally:
            registered.set()
            work._thread.join(3)
            self.assertFalse(work._thread.is_alive())

    def test_confirmed_cancel_between_gate_and_next_drive_selects_same_original_retirement(self):
        host, core, original, work, body, _, _, drives, events, _ = self.exercise(1)
        self.assertIsNone(work._future.exception())
        self.assertEqual(len(drives), 1)
        self.assertIn('seal-original-compute', events)
        self.assertEqual(events.count('close-original-task'), 1)
        self.assertEqual(events.count('core-stop-observation'), 1)
        self.assertEqual(core._task_loans, {})
        self.assertTrue(work.stopped)
        # No Run-state/ACK port exists in this fixture. Only the original Core
        # unpublished-state family can determine terminal cancellation later.
        self.assertNotIn('run-state', events)

    def test_absent_cancel_interest_preserves_the_same_original_work_refusal(self):
        _, _, original, work, _, _, _, drives, _, primary = self.exercise(0)
        self.assertIs(work._future.exception(), primary)
        self.assertEqual(len(drives), 2)
        self.assertIsNone(getattr(original, 'stop_interest', None))

    def test_foreign_cancel_interest_preserves_original_failure_and_pending_projection(self):
        host, core, original, work, _, _, _, drives, events, primary = self.exercise(-35)
        self.assertIs(work._future.exception(), primary)
        self.assertEqual(len(drives), 2)
        self.assertIsNotNone(host._pending_cancellation_write)
        self.assertNotIn('projection-return', events)

    def test_pending_original_cleanup_remains_retained_and_never_becomes_cancelled_ack(self):
        host, core, original, work, _, _, _, drives, events, _ = self.exercise(1, pending=True)
        self.assertIsInstance(work._future.exception(), LocalProductCleanupPending)
        self.assertEqual(len(drives), 1)
        self.assertTrue(core._task_loans)
        self.assertEqual(events.count('close-original-task'), 1)

    def test_first_close_still_observes_debt_after_the_original_worker_stops(self):
        host, core, original, work, _, _, _, _, _, _ = self.exercise(1, pending=True)
        calls = []
        host.close = lambda: calls.append('first-close') or False
        with self.assertRaises(LocalProductCleanupPending):
            asyncio.run(host.aclose())
        self.assertEqual(calls, ['first-close'])
        self.assertTrue(core._task_loans)

    def test_entered_stop_gate_keeps_identity_without_scanning_unrelated_work(self):
        host, core, original, work, *_ = self.fixture(1)

        class UnrelatedWork:
            def __iter__(self):
                raise AssertionError('A quantum cannot enumerate unrelated physical work')

        host._physical_work = UnrelatedWork()
        original.stop_interest = object()
        # Explicit entered-worker/current-thread ports only: no physical Run
        # or stop acknowledgment is constructed by this gate component.
        work._thread = current_thread()
        with core._lock:
            with self.assertRaises(_OriginalCancellationStop) as selected:
                host._check_original_stop_interest(original.run)
            self.assertIs(selected.exception.original, original)
            host._check_original_stop_interest(object())
            work._owner = object()
            host._check_original_stop_interest(original.run)
            work._owner = original.run
            work._original = object()
            with self.assertRaisesRegex(ValueError, 'Copied original'):
                host._check_original_stop_interest(original.run)

    def pending_readback_fixture(self, *, other_live=False, pending_close=False):
        host, core, original, work, body, *rest = self.fixture(1)
        events = rest[-2]
        confirm_original = core.confirm_cancellation_append
        pending = core.reserve_submission_projection()
        primary = LocalCoreError('confirm_cancellation_append', -33)

        def uncertain(value, current, **options):
            self.assertIs(value, pending)
            raise primary

        core.confirm_cancellation_append = uncertain
        with self.assertRaises(LocalCoreError) as refused:
            host._cancel_original(body)
        self.assertIs(refused.exception, primary)
        self.assertIs(host._pending_cancellation_write, pending)
        core.confirm_cancellation_append = confirm_original
        reference = body['ref']
        other_ref = dict(reference, runDefinitionCid='sha256:' + 'c' * 64)
        other_run = SimpleNamespace(handle=72)
        other = _OriginalExecution(host, other_run, reference=object())
        if other_live:
            host._physical_work.append(OriginalLocalWork(other, owner=other_run))

        def locate(raw):
            selected = json.loads(raw)
            if selected == reference:
                return SimpleNamespace(run=original.run)
            if selected == other_ref and other_live:
                return SimpleNamespace(run=other_run)
            return None

        host._find_original_run_reference = locate
        host._runs._run = lambda value: self.assertTrue(
            value is original.run or value is other_run)
        scalar_original = core._call

        def scalar(family, name, *args):
            if args[1] != original.run.handle:
                events.append('foreign-stop-observation')
                return -35
            return scalar_original(family, name, *args)

        core._call = scalar
        host._copy = lambda raw: raw
        selections = {}

        def reserve(configuration, source, kind, **options):
            self.assertEqual(kind, 11)
            output = SimpleNamespace(handle=110 + len(selections), ticket=120 + len(selections))
            selections[output.ticket] = json.loads(source)
            return output

        core.reserve_submission_projection = reserve

        def read(output, current):
            selection = selections[output.ticket]
            return json.dumps({'kind': 'unknown', 'cancelRef': selection}).encode()

        core.produce_and_read_submission_lookup = read
        closes = []

        def close(output):
            closes.append(output)
            if output is pending and pending_close:
                return False
            return True

        host._close_projection = close
        return host, original, other, reference, other_ref, pending, events, closes, primary

    def test_pending_cancel_readback_preserves_unrelated_lookup_without_a_worker(self):
        host, original, _, reference, other_ref, pending, events, closes, _ = self.pending_readback_fixture()
        raw = host._lookup_original_cancellation(other_ref, 'other-cancel', 7)
        self.assertEqual(json.loads(raw)['cancelRef']['runDefinitionCid'], other_ref['runDefinitionCid'])
        self.assertIs(host._pending_cancellation_write, pending)
        self.assertIsNone(original.stop_interest)
        self.assertNotIn('confirmed-original', events)
        self.assertFalse(any(value is pending for value in closes))
        # The same Run with a different cancellation key is unrelated too.
        host._lookup_original_cancellation(reference, 'other-cancel', 19)
        self.assertIs(host._pending_cancellation_write, pending)
        self.assertNotIn('confirmed-original', events)

    def test_pending_cancel_readback_preserves_unrelated_live_run_lookup(self):
        host, original, other, _, other_ref, pending, events, closes, _ = self.pending_readback_fixture(other_live=True)
        raw = host._lookup_original_cancellation(other_ref, 'other-cancel', 7)
        self.assertEqual(json.loads(raw)['kind'], 'unknown')
        self.assertIs(host._pending_cancellation_write, pending)
        self.assertIsNone(original.stop_interest)
        self.assertIsNone(other.stop_interest)
        self.assertNotIn('foreign-stop-observation', events)
        self.assertFalse(any(value is pending for value in closes))

    def test_pending_cancel_readback_retains_same_original_stop_and_close_debt(self):
        host, original, other, reference, _, pending, events, closes, primary = self.pending_readback_fixture(
            other_live=True, pending_close=True)
        with self.assertRaises(LocalProductCleanupPending):
            host._lookup_original_cancellation(reference, 'cancel-original', 19)
        self.assertIs(host._pending_cancellation_write, pending)
        self.assertIs(original.stop_interest, pending)
        self.assertIsNone(other.stop_interest)
        self.assertEqual(events.count('core-stop-observation'), 1)
        self.assertIsInstance(primary, LocalCoreError)
        self.assertEqual(primary.code, -33)
        host._close_projection = lambda output: True
        host._lookup_original_cancellation(reference, 'cancel-original', 19)
        self.assertIsNone(host._pending_cancellation_write)
        self.assertIs(original.stop_interest, pending)
