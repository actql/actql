"""Original instance/Store VM span caller doubles; no actual Wasmtime/VM execution."""
from ctypes import c_void_p
from types import SimpleNamespace
import unittest

from actql_sdk._local_core import LocalCore
from actql_sdk._local_native_holding import NativeHoldingObservationError
import test_local_installed_image as fixture


class NativeVMSpanTests(unittest.TestCase):
    def setUp(self):
        self.case = fixture.InstalledImageTests(); self.case.setUp()
        self.holding, self.library = self.case._holding([(0, True)])
        self.store = object(); self.queries = []
        self.memory_type = fixture.Handle('vm_type', self.case.events)
        self.memory_type.is_64 = False; self.memory_type.is_shared = False
        self.memory_type.limits = SimpleNamespace(min=1, max=256)
        self.address = c_void_p(234)
        test = self
        class Memory:
            def type(self, store):
                test.queries.append(('type', store))
                return test.memory_type
            def data_ptr(self, store):
                test.queries.append(('pointer', store))
                return test.address
        self.runtime = SimpleNamespace(Memory=Memory)
        self.core = LocalCore.__new__(LocalCore)
        self.core._physical_holding = self.holding
        self.core._physical_vm_span = None
        self.core._physical_vm_type = None
        self.core._store = self.store
        self.core._exports = {'memory': Memory()}
        self.core._closed = False; self.core._retired = False; self.core._closing = False

    def test_original_instance_and_store_supply_fixed_vm_span_once(self):
        self.core._observe_original_vm_span(self.runtime)
        self.assertEqual(self.queries, [('type', self.store), ('pointer', self.store)])
        self.assertEqual(self.library.span_calls, [(123, 234, 16777216)])
        self.assertEqual(self.core._physical_vm_span, (234, 16777216))
        self.assertIsNone(self.core._physical_vm_type)
        with self.assertRaises(ValueError): self.core._observe_original_vm_span(self.runtime)
        self.assertEqual(len(self.queries), 2)

    def test_missing_or_foreign_export_refuses_before_pointer_and_membership(self):
        for memory in (None, object()):
            with self.subTest(memory=memory):
                self.core._exports = {'memory': memory}
                with self.assertRaises(ValueError): self.core._observe_original_vm_span(self.runtime)
        self.assertEqual(self.queries, [])
        self.assertEqual(self.library.span_calls, [])

    def test_unbounded_or_shared_or_memory64_type_refuses_without_vm_projection(self):
        for kind in ('max', 'shared', 'memory64', 'boolean_min'):
            with self.subTest(kind=kind):
                self.setUp()
                if kind == 'max': self.memory_type.limits.max = 257
                elif kind == 'shared': self.memory_type.is_shared = True
                elif kind == 'memory64': self.memory_type.is_64 = True
                else: self.memory_type.limits.min = True
                with self.assertRaises(ValueError): self.core._observe_original_vm_span(self.runtime)
                self.assertIs(self.core._physical_vm_type, self.memory_type)
                self.assertIsNone(self.core._physical_vm_span)
                self.assertEqual(self.library.span_calls, [])

    def test_foreign_or_unconfirmed_backing_keeps_original_type_for_cleanup(self):
        def deny(*args): return -1
        self.library.actql_owned_contains_live_span = deny
        with self.assertRaises(NativeHoldingObservationError):
            self.core._observe_original_vm_span(self.runtime)
        self.assertIs(self.core._physical_vm_type, self.memory_type)
        self.assertIsNone(self.core._physical_vm_span)
        self.assertIs(self.core._physical_holding, self.holding)

    def test_null_original_pointer_does_not_become_zero_byte_vm(self):
        self.address = c_void_p()
        with self.assertRaises(ValueError): self.core._observe_original_vm_span(self.runtime)
        self.assertIsNone(self.core._physical_vm_span)
        self.assertEqual(self.library.span_calls, [])

    def test_retired_closing_or_destroyed_store_never_queries_memory(self):
        for kind in ('closed', 'retired', 'closing', 'store'):
            with self.subTest(kind=kind):
                self.setUp()
                if kind == 'store': self.core._store = None
                else: setattr(self.core, '_' + kind, True)
                with self.assertRaises(ValueError): self.core._observe_original_vm_span(self.runtime)
                self.assertEqual(self.queries, [])

    def test_memory_type_cleanup_failure_is_retained_before_core_open(self):
        self.memory_type.failures = 1
        with self.assertRaises(OSError): self.core._observe_original_vm_span(self.runtime)
        self.assertIs(self.core._physical_vm_type, self.memory_type)
        self.assertEqual(self.core._physical_vm_span, (234, 16777216))
        self.assertFalse(self.core._closed)
