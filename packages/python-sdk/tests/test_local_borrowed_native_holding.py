"""Same-record integration counters; no actual Store or Wasmtime here."""
import unittest
from ctypes import c_void_p
from test_local_native_domain_borrow import BorrowFixture
from actql_sdk._local_native_holding import (
    _NativeHoldingLease, NativeHoldingRetirementError, NativeHoldingInitializationError,
)
from actql_sdk._local_core import LocalCore
from test_local_native_control_custody import Function


class BorrowedNativeHoldingTests(unittest.TestCase):
    def test_move_scope_span_and_retirement_use_one_original_record(self):
        f = BorrowFixture(); b = f.take(); h = _NativeHoldingLease._from_original_borrow(b)
        identity = object(); h._bind_core(identity); h._transfer_to_core(identity)
        self.assertEqual(h._capacity_bytes(), 16384)
        h._require_live_span(c_void_p(4096), 16)
        with self.assertRaises(ValueError):
            with b._scope():
                self.fail('Borrow moved twice')
        with self.assertRaises(ValueError):
            b.close()
        h.close(); h.close()
        self.assertTrue(b._closed)
        self.assertIsNone(h._pointer.value)
        self.assertFalse(f.descriptor.close_attempted)
        self.assertEqual(sum(e == 'claim_holding' for e in f.events), 1)
        self.assertEqual(sum(e == 'transfer_holding' for e in f.events), 1)

    def test_success_without_cleared_slot_is_unknown_and_not_closed(self):
        f = BorrowFixture(); b = f.take(); h = _NativeHoldingLease._from_original_borrow(b)
        f.functions.close_holding = Function(lambda record, slot: 0)
        with self.assertRaises(Exception):
            h.close()
        self.assertIsNotNone(b._unknown)
        self.assertFalse(b._closed)
        self.assertEqual(h._pointer.value, 123)

    def test_second_holding_refuses_without_claim_or_early_cleanup(self):
        f = BorrowFixture(); b = f.take(); h = _NativeHoldingLease._from_original_borrow(b)
        before = list(f.events)
        with self.assertRaises(ValueError):
            _NativeHoldingLease._from_original_borrow(b)
        self.assertEqual(f.events, before)
        self.assertIs(b._holding_consumer, h)
        h.close()

    def test_lost_claim_keeps_same_holding_borrow_and_fd(self):
        f = BorrowFixture(); b = f.take(); f.claim_fault = OSError('claim return lost')
        with self.assertRaises(NativeHoldingInitializationError) as caught:
            _NativeHoldingLease._from_original_borrow(b)
        h = caught.exception.cleanup_holding
        self.assertIs(h._borrow, b)
        self.assertIs(b._holding_consumer, h)
        self.assertEqual(h._pointer.value, 123)
        before = list(f.events)
        with self.assertRaises(Exception):
            h.close()
        self.assertEqual(f.events, before)
        self.assertFalse(f.descriptor.close_attempted)

    def test_known_retirement_failure_keeps_pointer_and_same_retry(self):
        f = BorrowFixture(); b = f.take(); h = _NativeHoldingLease._from_original_borrow(b)
        f.close_code = -2
        with self.assertRaises(NativeHoldingRetirementError):
            h.close()
        self.assertEqual(h._pointer.value, 123)
        self.assertFalse(b._closed)
        f.close_code = 0; h.close()
        self.assertTrue(b._closed)
        self.assertEqual(sum(e == 'claim_holding' for e in f.events), 1)

    def test_core_dispose_does_not_repeat_store_after_holding_pending(self):
        f = BorrowFixture(); b = f.take(); h = _NativeHoldingLease._from_original_borrow(b)
        # Exercise the actual cleanup caller, with independently counted Store.
        core = object.__new__(LocalCore)
        core._physical_holding = h
        core._native_scope = h._scope
        events = []
        class Store:
            def close(self):
                events.append('store')
        core._store = Store()
        core._physical_vm_span = object()
        core._physical_image = None
        core._inputs = {}; core._loans = {}; core._released = set()
        core._native_observers = {}; core._native_loans = {}; core._compute_loans = {}
        core._task_loans = {}; core._result_loans = {}; core._closed = False
        f.close_code = -2
        with self.assertRaises(NativeHoldingRetirementError):
            core._dispose()
        self.assertEqual(events, ['store'])
        self.assertIsNone(core._store)
        self.assertIs(core._physical_holding, h)
        self.assertFalse(core._closed)
        f.close_code = 0; core._dispose()
        self.assertEqual(events, ['store'])
        self.assertTrue(core._closed)
        self.assertIsNone(core._physical_holding)
