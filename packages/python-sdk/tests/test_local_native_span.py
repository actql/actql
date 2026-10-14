"""Native capacity/span status doubles; physical C fixture remains unexecuted."""
from ctypes import c_void_p, c_uint64, cast, POINTER
import unittest

from actql_sdk._local_native_holding import NativeHoldingObservationError
import test_local_installed_image as fixture


class NativeSpanTests(unittest.TestCase):
    def setUp(self):
        case = fixture.InstalledImageTests(); case.setUp()
        self.holding, self.library = case._holding([(0, True)])
        self.capacity = 123456; self.capacity_status = 0; self.span_status = 0
        self.calls = []
        def inspect(pointer, out):
            self.calls.append(('capacity', pointer.value))
            cast(out, POINTER(c_uint64))[0] = self.capacity
            return self.capacity_status
        def contains(pointer, address, length):
            self.calls.append(('span', pointer.value, address.value, length))
            return self.span_status
        self.library.actql_owned_capacity_bytes = inspect
        self.library.actql_owned_contains_live_span = contains

    def test_capacity_is_original_physical_observation_without_core_grant(self):
        self.assertEqual(self.holding._capacity_bytes(), 123456)
        self.assertIsNone(self.holding._core_identity)
        self.assertFalse(self.holding._transfer_attempted)
        self.assertEqual(self.calls, [('capacity', 123)])

    def test_zero_overflow_and_malformed_status_never_become_known_capacity(self):
        for amount, status in ((0, 0), (2**63, 0), (123456, -2), (123456, True)):
            with self.subTest(amount=amount, status=status):
                self.capacity, self.capacity_status = amount, status
                with self.assertRaises(NativeHoldingObservationError): self.holding._capacity_bytes()
                self.assertEqual(self.holding._pointer.value, 123)

    def test_span_uses_original_pointer_and_scope_without_new_transfer(self):
        identity = object()
        self.holding._bind_core(identity)
        self.holding._transfer_to_core(identity)
        self.holding._require_live_span(c_void_p(234), 16777216)
        self.assertEqual(self.calls, [('span', 123, 234, 16777216)])
        self.assertEqual(self.library.scope.events, [('enter', 123), ('leave', 123)])
        self.assertEqual(self.library.actql_owned_transfer.calls, [(123, 7, b'r' * 32)])

    def test_span_refusal_or_unknown_does_not_infer_membership_or_replace_lease(self):
        for status in (-1, -2, True, None):
            with self.subTest(status=status):
                self.span_status = status
                with self.assertRaises(NativeHoldingObservationError):
                    self.holding._require_live_span(c_void_p(234), 16777216)
                self.assertEqual(self.holding._pointer.value, 123)
                self.assertEqual(self.library.scope.depth, 0)

    def test_bad_span_shape_refuses_before_native_observation(self):
        for pointer, length in ((c_void_p(), 1), (234, 1), (c_void_p(234), 0),
                (c_void_p(234), True), (c_void_p(234), 2**63)):
            with self.subTest(pointer=pointer, length=length):
                with self.assertRaises(ValueError): self.holding._require_live_span(pointer, length)
        self.assertEqual(self.calls, [])

    def test_retired_original_holding_cannot_be_observed_again(self):
        self.holding.close()
        with self.assertRaises(ValueError): self.holding._capacity_bytes()
        with self.assertRaises(ValueError): self.holding._require_live_span(c_void_p(234), 1)
        self.assertEqual(self.calls, [])
