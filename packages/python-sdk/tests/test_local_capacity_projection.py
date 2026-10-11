"""Private capacity projection never admits a Run or starts physical I/O."""
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError


class CapacityProjectionTests(unittest.TestCase):
    def bridge(self, values):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._closing = False
        calls = []
        def call(family, name, configuration, field):
            calls.append((family, name, configuration, field))
            return values[field]
        core._call = call
        return core, calls

    def test_exact_owner_inventory_is_not_admission(self):
        core, calls = self.bridge([339000000, 536870912, 3000000])
        capacity = core.native_configuration_capacity(17)
        self.assertEqual((capacity.retained_bytes, capacity.execution_bytes,
                          capacity.transfer_bytes), (339000000, 536870912, 3000000))
        self.assertEqual(calls, [('source', 'capacity', 17, index) for index in range(3)])

    def test_missing_inventory_remains_failure_and_invalid_handles_do_not_cross_wasm(self):
        core, calls = self.bridge([-2, -2, -2])
        with self.assertRaises(LocalCoreError):
            core.native_configuration_capacity(17)
        baseline = len(calls)
        for handle in (True, 0, -1, '17'):
            with self.assertRaises(ValueError):
                core.native_configuration_capacity(handle)
        core._closing = True
        with self.assertRaises(ValueError):
            core.native_configuration_capacity(17)
        self.assertEqual(len(calls), baseline)
