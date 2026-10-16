"""Original Memory/borrow projection doubles; actual provider conformance is separate."""
from ctypes import c_void_p
from dataclasses import replace
import unittest

from actql_sdk._local_native_domain_borrow import _OriginalDomainBorrowError
from actql_sdk._local_native_holding import _NativeHoldingLease
from test_local_native_control_custody import Function
from test_local_native_domain_borrow import BorrowFixture
import test_local_installed_image as image_fixture


class NativeVMExtentTests(unittest.TestCase):
    def setUp(self):
        self.f = BorrowFixture()
        values = list(self.f.material.scalars); values[7] = values[14] = 16777216 + 8192
        self.f.material = replace(self.f.material, scalars=tuple(values))
        def capacity(record, out):
            out._obj.value = 16777216 + 4096
            return 0
        self.f.functions.capacity = Function(capacity)
        self.borrow = self.f.take()
        self.holding = _NativeHoldingLease._from_original_borrow(self.borrow)
        self.case = image_fixture.InstalledImageTests(); self.case.setUp()
        self.core, self.calls = self.case._construct_with_baseline(holding=self.holding)
        self.observation = self.core._physical_vm_observation

    def offsets(self):
        return [item for item in self.f.events if type(item) is tuple and item[0] == 'span_offset']

    def test_original_observed_vm_projects_only_relative_payload_data(self):
        value = self.observation._project_original_span()
        self.assertEqual((value.source, value.recipe, value.material),
                         (self.f.material.source, b'r' * 32, self.f.material.scalars))
        self.assertEqual((value.offset, value.length, value.nonce), (4096, 16777216, self.core._nonce))
        self.assertEqual(self.offsets(), [('span_offset', self.borrow._pointer.value, 123, 234, 16777216)])
        self.assertIs(self.core._physical_holding, self.holding)
        self.assertIs(self.holding._borrow, self.borrow)
        self.assertEqual([name for name, _ in self.calls], ['open'])

    def test_raw_nonborrowed_membership_cannot_project_a_live_child(self):
        holding, _ = self.case._holding([(0, True)])
        core, _ = self.case._construct_with_baseline(holding=holding)
        with self.assertRaises(ValueError): core._physical_vm_observation._project_original_span()
        self.assertEqual(self.offsets(), [])

    def test_known_refusal_preserves_the_same_original_without_success_data(self):
        self.f.functions.span_offset = Function(lambda *args: -3)
        with self.assertRaises(_OriginalDomainBorrowError) as caught:
            self.observation._project_original_span()
        self.assertIs(caught.exception.cleanup_borrow, self.borrow)
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(caught.exception.code, -3)
        self.assertIs(self.core._physical_holding, self.holding)
        self.assertFalse(self.borrow._closed)

    def test_lost_or_invalid_reply_is_sticky_and_does_not_requery(self):
        calls = []
        def fail(*args):
            calls.append('span')
            raise ValueError('independent physical reply lost')
        self.f.functions.span_offset = Function(fail)
        with self.assertRaises(_OriginalDomainBorrowError) as caught:
            self.observation._project_original_span()
        self.assertTrue(caught.exception.unknown)
        with self.assertRaises(_OriginalDomainBorrowError): self.observation._project_original_span()
        self.assertEqual(calls, ['span'])
        self.assertIs(self.core._physical_holding, self.holding)
        self.assertFalse(self.f.descriptor.close_attempted)

    def test_out_of_original_payload_reply_never_becomes_a_vm_extent(self):
        for invalid in (0, 8193, 2**63):
            with self.subTest(invalid=invalid):
                self.setUp()
                def bad(record, holding, address, length, out):
                    out._obj.value = invalid
                    return 0
                self.f.functions.span_offset = Function(bad)
                with self.assertRaises(_OriginalDomainBorrowError) as caught:
                    self.observation._project_original_span()
                self.assertTrue(caught.exception.unknown)
                self.assertIs(self.core._physical_holding, self.holding)

    def test_changed_original_material_during_projection_is_rejected_after_call(self):
        original = self.borrow._material
        def change(record, holding, address, length, out):
            out._obj.value = 4096
            self.borrow._material = replace(original, source='1' * 40)
            return 0
        self.f.functions.span_offset = Function(change)
        with self.assertRaises(ValueError): self.observation._project_original_span()
        self.assertIs(self.core._physical_holding, self.holding)
        self.assertIs(self.holding._borrow, self.borrow)

    def test_foreign_consumer_never_calls_the_physical_projection(self):
        with self.assertRaises(ValueError):
            self.borrow._holding_span_offset(object(), c_void_p(123), c_void_p(234), 16777216)
        self.assertEqual(self.offsets(), [])

    def test_closing_and_retired_originals_refuse_new_projection(self):
        for state in ('_closing', '_retired'):
            with self.subTest(state=state):
                self.setUp(); setattr(self.core, state, True)
                with self.assertRaises(ValueError): self.observation._project_original_span()
                self.assertEqual(self.offsets(), [])


if __name__ == '__main__':
    unittest.main()
