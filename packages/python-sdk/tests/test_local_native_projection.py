"""Independent original-mapping projection doubles; no physical VM or funding."""
from ctypes import POINTER, c_uint64, cast
from unittest.mock import patch
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreInitializationError
from actql_sdk._local_native_holding import NativeHoldingObservationError
import test_local_native_vm_span as vm


class NativeProjectionTests(unittest.TestCase):
    def setUp(self):
        self.original = vm.NativeVMSpanTests(); self.original.setUp()
        self.core = self.original.core
        self.amount = 16777216 + 4096; self.status = 0; self.observations = []
        def capacity(pointer, out):
            self.observations.append(pointer.value)
            cast(out, POINTER(c_uint64))[0] = self.amount
            return self.status
        self.original.library.actql_owned_capacity_bytes = capacity

    def test_original_vm_is_counted_once_and_remaining_mapping_is_covered(self):
        self.core._observe_original_vm_span(self.original.runtime)
        self.core._validate_original_native_projection(4096)
        self.assertEqual(self.observations, [123])
        self.assertEqual(self.original.library.span_calls, [(123, 234, 16777216)])

    def test_missing_membership_refuses_before_subtraction_or_capacity_read(self):
        with self.assertRaises(ValueError): self.core._validate_original_native_projection(4096)
        self.assertEqual(self.observations, [])

    def test_mapping_larger_than_baseline_or_smaller_than_vm_is_rejected(self):
        self.core._observe_original_vm_span(self.original.runtime)
        for amount in (16777216 + 4097, 16777215):
            with self.subTest(amount=amount):
                self.amount = amount
                with self.assertRaises(ValueError): self.core._validate_original_native_projection(4096)
                self.assertIs(self.core._physical_holding, self.original.holding)

    def test_unavailable_capacity_is_not_zero_or_a_replacement_lease(self):
        self.core._observe_original_vm_span(self.original.runtime)
        for amount, status in ((0, 0), (2**63, 0), (16781312, -2), (16781312, True)):
            with self.subTest(amount=amount, status=status):
                self.amount, self.status = amount, status
                with self.assertRaises(NativeHoldingObservationError):
                    self.core._validate_original_native_projection(4096)
                self.assertIs(self.core._physical_holding, self.original.holding)

    def test_retired_store_or_invalid_baseline_never_reuses_vm_membership(self):
        self.core._observe_original_vm_span(self.original.runtime)
        for baseline in (0, True, -1, 2**63):
            with self.assertRaises(ValueError): self.core._validate_original_native_projection(baseline)
        self.core._store = None
        with self.assertRaises(ValueError): self.core._validate_original_native_projection(4096)
        self.assertEqual(self.observations, [])

    def test_underfunded_constructor_never_opens_root_and_retires_same_holding(self):
        case = self.original.case
        self.amount = 16777216 + 4097
        with patch.object(LocalCore, '_call', autospec=True) as call:
            with self.assertRaises(ValueError): case._construct_with_baseline(holding=self.original.holding)
        call.assert_not_called()
        self.assertIn(('close', 'store'), case.events)
        self.assertIn(('retire', 123), case.events)
        self.assertIsNone(self.original.holding._pointer.value)

    def test_projection_failure_keeps_same_cleanup_identity_on_retirement_failure(self):
        case = self.original.case
        self.amount = 16777216 + 4097
        self.original.holding._try_close.replies = [(-2, False), (0, True)]
        with self.assertRaises(LocalCoreInitializationError) as caught:
            case._construct_with_baseline(holding=self.original.holding)
        core = caught.exception.cleanup_core
        self.assertIs(core._physical_holding, self.original.holding)
        self.assertIsNone(core._store)
        self.assertIsNone(core._physical_vm_span)
        self.assertFalse(core._closed)
        self.assertTrue(core.close())
        self.assertEqual([e for e in case.events if e == ('close', 'store')], [('close', 'store')])
