"""Independent scalar failure counters; actual DLL acceptance is separate."""
import copy
import unittest
from unittest.mock import patch
from test_local_native_domain_custody import DomainFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_domain_custody import (
    _OriginalDomainMaterialFunctions, _OriginalDomainMaterial, _OriginalDomainError,
)


class MaterialFixture(DomainFixture):
    def __init__(self):
        super().__init__()
        self.project_issue = 0
        self.project_fault = self.read_fault = None
        self.source = b'0123456789012345678901234567890123456789'
        self.values = (9007199254740993, 2, 3, 65536, 4096, 32768, 4096, 16384,
                       1, 2, 1, 1, 3, 0, 16384)
        self.host._functions.library.actql_domain_project_into = Function(self.project)
        self.host._functions.library.actql_domain_copy_material = Function(self.read)
        self.material_functions = _OriginalDomainMaterialFunctions(self.host._functions.library)

    def project(self, host, domain, reply):
        self.events.append(('project', host.value, domain.value))
        self.result(reply, 7, self.project_issue)
        if self.project_fault:
            raise self.project_fault
        return 0

    def read(self, reply, host, domain, source, recipe, scalars):
        self.events.append(('read', reply.value, host.value, domain.value))
        source[:] = self.source
        recipe[:] = bytes([31]) * 32
        scalars[:] = self.values
        if self.read_fault:
            raise self.read_fault
        return 0


class OriginalDomainMaterialTests(unittest.TestCase):
    def test_exact_int64_data_copy_is_not_original_custody(self):
        f = MaterialFixture(); d = f.take()
        m = d._project_original_material(f.material_functions)
        self.assertEqual(m, _OriginalDomainMaterial(f.source.decode(), bytes([31]) * 32, f.values))
        self.assertEqual(m.scalars[0], 2**53 + 1)
        self.assertEqual(copy.copy(m), m)
        before = list(f.events)
        with self.assertRaises(ValueError):
            d._project_original_material(copy.copy(m))
        self.assertEqual(f.events, before)
        d.close_after_stop()
        with self.assertRaises(ValueError):
            d._project_original_material(f.material_functions)
        self.assertFalse(f.descriptor.close_attempted)

    def test_known_owner_refusal_never_reads_material_or_loses_domain(self):
        f = MaterialFixture(); d = f.take(); f.project_issue = 4
        with self.assertRaises(_OriginalDomainError) as caught:
            d._project_original_material(f.material_functions)
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(caught.exception.fact.operation, 7)
        self.assertFalse(any(e[0] == 'read' for e in f.events))
        self.assertEqual(d._domain.value, 301)
        self.assertFalse(f.host._busy)
        d.close_after_stop()

    def test_lost_project_retains_original_reply_and_never_retries(self):
        f = MaterialFixture(); d = f.take(); f.project_fault = OSError('lost project')
        with self.assertRaises(_OriginalDomainError) as caught:
            d._project_original_material(f.material_functions)
        self.assertTrue(caught.exception.unknown)
        self.assertIsNotNone(d._reply.value)
        before = list(f.events)
        for action in (lambda: d._project_original_material(f.material_functions), d.current, d.close_after_stop):
            with self.assertRaises(_OriginalDomainError) as again:
                action()
            self.assertIs(again.exception, caught.exception)
        self.assertEqual(f.events, before)

    def test_partial_copy_failure_retains_original_material_reply(self):
        f = MaterialFixture(); d = f.take(); f.read_fault = OSError('lost copy')
        with self.assertRaises(_OriginalDomainError) as caught:
            d._project_original_material(f.material_functions)
        self.assertTrue(caught.exception.unknown)
        self.assertIsNotNone(d._reply.value)
        self.assertEqual(d._domain.value, 301)
        self.assertFalse(f.descriptor.close_attempted)
        self.assertFalse(f.host._busy)

    def test_current_postcheck_refusal_does_not_return_old_material(self):
        f = MaterialFixture(); d = f.take(); f.current_issue = 6
        with self.assertRaises(_OriginalDomainError) as caught:
            d._project_original_material(f.material_functions)
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(caught.exception.fact.operation, 2)
        self.assertTrue(any(e[0] == 'read' for e in f.events))
        self.assertIsNone(d._reply.value)
        self.assertFalse(d._closed)
        d.close_after_stop()

    def test_foreign_component_rejects_before_original_call(self):
        f = MaterialFixture(); d = f.take(); other = MaterialFixture()
        before = list(f.events)
        with self.assertRaises(ValueError):
            d._project_original_material(other.material_functions)
        self.assertEqual(f.events, before)
        d.close_after_stop()

    def test_wrong_scalar_encoding_is_unknown_not_zero_or_success(self):
        for value in (-1, 3):
            f = MaterialFixture(); d = f.take()
            values = list(f.values); values[8] = value; f.values = tuple(values)
            with self.assertRaises(_OriginalDomainError) as caught:
                d._project_original_material(f.material_functions)
            self.assertTrue(caught.exception.unknown)
            self.assertIsNotNone(d._reply.value)
            self.assertFalse(d._closed)

    def test_snapshot_allocation_failure_keeps_same_original_reply(self):
        f = MaterialFixture(); d = f.take()
        with patch('actql_sdk._local_native_domain_custody._OriginalDomainMaterial', side_effect=MemoryError('metadata')):
            with self.assertRaises(_OriginalDomainError) as caught:
                d._project_original_material(f.material_functions)
        self.assertTrue(caught.exception.unknown)
        self.assertIsNotNone(d._reply.value)
        self.assertFalse(f.host._busy)
