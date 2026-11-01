"""Closed live-child ABI and missing-supplier refusals; no actual VM/worker."""
from ctypes import c_void_p
import unittest

from actql_sdk._local_core import LocalCore, LOCAL_CORE_ABI, _IMPORT_SIGNATURES, _BUFFER_SIGNATURES
from actql_sdk._local_native_holding import NativeHoldingObservationError
import test_local_installed_image as fixture
from local_abi_declaration_fixture import assert_current_local_abi


class LiveImportBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.case = fixture.InstalledImageTests(); self.case.setUp()

    def test_closed_original_import_signatures_include_i64_nonce_and_usage(self):
        expected = {
            'execution_child_admit': ('i64', 'i32'),
            'execution_child_current': ('i64', 'i32'),
            'execution_child_limit': ('i64 i32', 'i64'),
            'execution_child_capacity': ('i64 i32', 'i64'),
            'execution_child_report': ('i64 i32 i32 i32 i64 i64 i64 i64 i64 i64 i64 i32 i32 i32', 'i32'),
            'execution_child_stop': ('i64', 'i32'),
        }
        self.assertEqual({k: v for k, v in _IMPORT_SIGNATURES.items()
                          if k.startswith('execution_child_')}, expected)
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_BUFFER_SIGNATURES['open_live'], ('i64 i64 i32 i32', 'i32'))
        self.assertEqual(_BUFFER_SIGNATURES['report_live'], ('i64', 'i32'))
        self.assertEqual(_BUFFER_SIGNATURES['stop_live'], ('i64', 'i32'))

    def test_raw_diagnostic_core_cannot_supply_a_live_parent(self):
        core = LocalCore.__new__(LocalCore)
        core._physical_vm_observation = None
        for args in ((), (0,), (1,), tuple(range(10))):
            self.assertEqual(core._unavailable_execution_child(object(), 1, *args), -42)

    def original(self):
        holding, library = self.case._holding([(0, True)])
        core, calls = self.case._construct_with_baseline(holding=holding)
        memory = self.case.memory
        class Caller(self.case.wasmtime.Caller):
            def _context(self): return c_void_p(345)
            def get(self, name): return memory if name == 'memory' else None
        return core, library, calls, Caller()

    def test_same_observed_vm_still_has_no_admit_capacity_report_or_stop_grant(self):
        core, library, calls, caller = self.original()
        for args in ((), (0,), (1,), tuple(range(10))):
            self.assertEqual(core._unavailable_execution_child(caller, core._nonce, *args), -42)
        self.assertEqual([name for name, _ in calls], ['open'])
        self.assertFalse(core._closing)
        self.assertIs(core._physical_holding._library, library)

    def test_copied_nonce_does_not_bypass_original_caller_validation(self):
        core, _, calls, caller = self.original()
        for actual, nonce in ((object(), core._nonce), (caller, core._nonce + 1)):
            with self.assertRaises(ValueError): core._unavailable_execution_child(actual, nonce)
        self.assertEqual([name for name, _ in calls], ['open'])

    def test_foreign_backing_error_remains_physical_not_unavailable_success(self):
        core, library, _, caller = self.original()
        library.actql_owned_contains_live_span = lambda *args: -3
        with self.assertRaises(NativeHoldingObservationError):
            core._unavailable_execution_child(caller, core._nonce)
        self.assertIsNotNone(core._physical_holding)

    def test_closing_same_original_remains_missing_supplier_and_retired_refuses(self):
        core, _, _, caller = self.original()
        core._closing = True
        self.assertEqual(core._unavailable_execution_child(caller, core._nonce), -42)
        core._retired = True
        with self.assertRaises(ValueError): core._unavailable_execution_child(caller, core._nonce)


if __name__ == '__main__':
    unittest.main()
