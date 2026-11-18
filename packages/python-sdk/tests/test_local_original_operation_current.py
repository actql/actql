"""Same-operation file/SQLite custody counters; explicit Core port, not authority."""
from types import SimpleNamespace
import asyncio
from threading import Event
import unittest

from actql_sdk._local_core import _NORMAL_HOST_OPERATION_FUEL
import test_local_host_binding as original_binding
from actql_sdk._local_work import OriginalLocalWork


class OriginalOperationCurrentTests(unittest.TestCase):
    def fixture(self):
        values = original_binding.OriginalHostBindingTests.fixture(self)
        _, store, core, _, _, _, _, calls, _, _, binding = values
        core._ordinary_host = True
        core._host_fuel_phase = None
        core._host_initial_claimed = False
        core._host_operation_sequence = 0
        core._host_operation_id = 0
        core._invoking = core._retired = False
        fuel = []
        core._store = SimpleNamespace(set_fuel=fuel.append)
        calls.clear()
        return store, core, calls, binding, fuel

    def test_cancelled_wait_retains_same_operation_until_original_worker_exits(self):
        _, core, _, binding, fuel = self.fixture()
        entered, resume, inspected = Event(), Event(), Event()
        observed = []

        def invoke():
            entered.set()
            if not resume.wait(2):
                raise TimeoutError('Original worker was not resumed')
            with core._lock:
                binding.inspect(lambda current: observed.append((
                    core._host_operation_id, current, core._journal_callbacks(current.ticket).reader)))
            inspected.set()

        async def submit_and_cancel_wait():
            with core._host_operation():
                original = core._host_operation_id
                work = OriginalLocalWork(invoke, on_exit=core._finish_work_operation)
                core._retain_work_operation(work)
                work.start()
                self.assertTrue(entered.wait(1))
                waiter = asyncio.create_task(work.wait())
                await asyncio.sleep(0)
                waiter.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await waiter
            return original, work

        original, work = asyncio.run(submit_and_cancel_wait())
        try:
            self.assertFalse(work.stopped)
            self.assertEqual(core._host_operation_id, original)
            with self.assertRaises(RuntimeError):
                core._finish_work_operation(work)
            self.assertEqual(core._host_operation_id, original)
            with self.assertRaises(RuntimeError):
                with core._host_operation():
                    self.fail('A live original worker cannot obtain replacement fuel')
            resume.set()
            asyncio.run(work.wait())
            self.assertTrue(inspected.is_set())
            self.assertEqual(len(observed), 1)
            self.assertEqual(observed[0][:2], (original, binding._current))
            with self.assertRaises(ValueError):
                observed[0][2].current()
            self.assertEqual(core._host_operation_id, 0)
            self.assertIsNone(core._host_fuel_phase)
            self.assertEqual(fuel, [_NORMAL_HOST_OPERATION_FUEL])
        finally:
            resume.set()
            asyncio.run(work.wait_stopped())

    def test_worker_completion_cannot_end_a_later_outer_operation(self):
        _, core, _, _, fuel = self.fixture()
        original_context = core._host_operation()
        original_context.__enter__()
        try:
            original = core._host_operation_id
            work = OriginalLocalWork(lambda: None, on_exit=core._finish_work_operation)
            core._retain_work_operation(work)
            work.start()
            asyncio.run(work.wait())
            self.assertEqual(core._host_operation_id, 0)
            with core._host_operation():
                later = core._host_operation_id
                self.assertGreater(later, original)
                later_context = core._host_operation_scope
                original_context.__exit__(None, None, None)
                self.assertEqual(core._host_operation_id, later)
                self.assertIs(core._host_operation_scope, later_context)
            self.assertEqual(core._host_operation_id, 0)
        finally:
            original_context.__exit__(None, None, None)
        self.assertEqual(fuel, [_NORMAL_HOST_OPERATION_FUEL] * 2)

    def test_same_operation_cannot_hide_new_adoption_member_between_original_readers(self):
        from actql_sdk._local_storage import LocalStorageError
        store, core, calls, binding, _ = self.fixture()
        original_call = core._call
        def selected(family, operation, *args):
            if family == 'current' and operation in ('bind', 'validate'):
                callbacks = core._journal_callbacks(binding._current.ticket)
                rows = []
                callbacks.reader.scan_after('client_local_adoption', '',
                    lambda row: rows.append(row))
                callbacks.reader.scan_after('client_local_adoption', 'adoption',
                    lambda row: rows.append(row))
                if rows[0] is None or rows[0][0] != 'adoption' or rows[1] is not None:
                    raise LocalStorageError('Original complete adoption singleton changed')
            return original_call(family, operation, *args)
        core._call = selected
        original_input, original_current = binding._input, binding._current
        with core._host_operation():
            binding.inspect(lambda _: None)
            self.assertEqual(store.compare_exchange(store.namespaced_key(
                'client_local_adoption', 'extra'), None, b'foreign singleton member'), 0)
            with self.assertRaises(LocalStorageError):
                binding.inspect(lambda _: None)
            self.assertIsNone(binding._bound_operation)
        self.assertIs(core._loans[original_input.ticket], original_input)
        self.assertIs(core._loans[original_current.ticket], original_current)

    def test_metadata_requires_same_verified_frame_and_cleanup_keeps_full_checks(self):
        _, core, _, binding, fuel = self.fixture()
        saved = []
        def metadata(current):
            core._invoking = True
            try:
                return core._journal_current_operation(current.ticket)
            finally:
                core._invoking = False
        def consume(current):
            operation = core._host_operation_id
            callbacks = core._journal_callbacks(current.ticket)
            reader = callbacks.reader
            self.assertIs(binding._observed_reader, reader)
            self.assertEqual(metadata(current), operation)
            self.assertEqual(core._journal_current_operation(current.ticket), -41)
            with core._host_cleanup():
                self.assertEqual(core._host_cleanup_depth, 1)
                self.assertEqual(metadata(current), 0)
            self.assertEqual(core._host_cleanup_depth, 0)
            self.assertEqual(metadata(current), operation)
            self.assertEqual(fuel, [_NORMAL_HOST_OPERATION_FUEL])
            saved.append(reader)
        with core._host_operation():
            binding.inspect(consume)
        self.assertIsNone(binding._observed_reader)
        self.assertEqual(core._host_operation_id, 0)
        with self.assertRaises(ValueError):
            binding._require_observation_frame(core, binding._current, saved[0])

    def test_equal_current_loan_copy_cannot_supply_original_frame_or_ready_cache(self):
        from dataclasses import replace
        _, core, _, binding, _ = self.fixture()
        original = binding._current
        def consume(current):
            core._loans[current.ticket] = replace(current)
            core._invoking = True
            try:
                self.assertEqual(core._journal_current_operation(current.ticket), -41)
            finally:
                core._invoking = False
                core._loans[current.ticket] = original
        with core._host_operation():
            with self.assertRaises(ValueError):
                binding.inspect(consume)
            self.assertIsNone(binding._bound_operation)
            self.assertIsNone(binding._observed_reader)
        self.assertIs(core._loans[original.ticket], original)

    def test_operation_change_or_consumer_failure_spends_binding_and_retains_originals(self):
        for mode in ('operation', 'failure'):
            with self.subTest(mode=mode):
                _, core, _, binding, _ = self.fixture()
                current, source = binding._current, binding._input
                def consume(_):
                    if mode == 'operation':
                        core._host_operation_id += 1
                    else:
                        raise RuntimeError('original consumer failure')
                with core._host_operation():
                    with self.assertRaises((ValueError, RuntimeError)):
                        binding.inspect(consume)
                    self.assertIsNone(binding._bound_operation)
                    self.assertIsNone(binding._observed_reader)
                self.assertEqual(core._host_operation_id, 0)
                self.assertIs(core._loans[current.ticket], current)
                self.assertIs(core._loans[source.ticket], source)

    def test_same_existing_operation_reuses_bound_original_but_every_reader_remains_current(self):
        store, core, calls, binding, fuel = self.fixture()
        frames, actions = [], []
        changes = store._connection.total_changes
        original_current, original_input = binding._current, binding._input

        def consume(current):
            self.assertIs(current, original_current)
            callbacks = core._journal_callbacks(current.ticket)
            reader = callbacks.reader
            frames.append(reader)
            self.assertIs(reader.owner, store)
            self.assertEqual(callbacks.check_current(), 0)
            seen = []
            reader.read('client_local_adoption', 'adoption', lambda row: seen.append(row))
            self.assertEqual(seen[0][1].payload, b'original-journal')
            self.assertEqual(callbacks.check_current(), 0)
            actions.append('complete')

        with core._host_operation():
            operation = core._host_operation_id
            for _ in range(3):
                binding.inspect(consume)
            selected = [name for family, name, _ in calls if family == 'current']
            # No cached permission or reader: only this original completed
            # binding is reused across its three actual physical transactions.
            self.assertEqual(selected, ['bind', 'validate'])
            self.assertGreater(operation, 0)
            self.assertIs(core._loans[original_input.ticket], original_input)
            self.assertIs(core._loans[original_current.ticket], original_current)
            self.assertEqual(core._host_operation_id, operation)
            with self.assertRaises(RuntimeError):
                with core._host_operation():
                    self.fail('Same-instance reentry cannot create a reusable operation')
        self.assertEqual(core._host_operation_id, 0)
        self.assertEqual(len({id(frame) for frame in frames}), 3)
        for frame in frames:
            with self.assertRaises(ValueError):
                frame.current()
        self.assertEqual(actions, ['complete'] * 3)
        self.assertEqual(store._connection.total_changes, changes)
        self.assertEqual(fuel, [_NORMAL_HOST_OPERATION_FUEL])
        calls.clear()
        with core._host_operation():
            self.assertGreater(core._host_operation_id, operation)
            binding.inspect(consume)
        self.assertEqual([name for family, name, _ in calls if family == 'current'],
                         ['bind', 'validate'])
        self.assertEqual(fuel, [_NORMAL_HOST_OPERATION_FUEL] * 2)
