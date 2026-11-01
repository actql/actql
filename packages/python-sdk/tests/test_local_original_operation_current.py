"""Same-operation file/SQLite custody counters; explicit Core port, not authority."""
from types import SimpleNamespace
import unittest

from actql_sdk._local_core import _NORMAL_HOST_OPERATION_FUEL
import test_local_host_binding as original_binding


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
