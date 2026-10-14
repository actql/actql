"""Scalar slots/call counters; physical C/DLL acceptance is separate."""
import copy
from ctypes import c_uint64
import pickle
import unittest
from unittest.mock import patch
from test_local_native_control_custody import Function
from actql_sdk._local_native_domain_custody import _OriginalDomainMaterial
from actql_sdk._local_native_domain_borrow import (
    _OriginalDomainBorrow, _OriginalDomainBorrowError, _OriginalDomainBorrowFunctions,
)
from actql_sdk._local_worker_slot import _OriginalDescriptor
from types import SimpleNamespace


class BorrowFixture:
    def __init__(self):
        self.events = []
        self.open_code = self.close_code = 0
        self.open_fault = self.close_fault = self.enter_fault = None
        self.size = 256
        self.library = SimpleNamespace()
        for name, call in {
            'storage_bytes': lambda: self.size, 'storage_alignment': lambda: 8,
            'open': self.open, 'status': lambda p: self.event('status'),
            'enter': self.enter, 'leave': lambda p: self.event('leave'),
            'close': self.close, 'pointer': lambda p, out: 0,
        }.items():
            setattr(self.library, 'actql_native_domain_borrow_' + name, Function(call))
        self.functions = _OriginalDomainBorrowFunctions(self.library)
        self.descriptor = _OriginalDescriptor(12)
        self.material = _OriginalDomainMaterial('0' * 40, b'r' * 32,
            (1, 2, 3, 65536, 4096, 32768, 0, 16384, 1, 2, 1, 1, 3, 0, 16384))

    def event(self, name):
        self.events.append(name)
        return 0

    def open(self, pointer, size, fd, recipe, values):
        self.events.append(('open', pointer.value, size, fd, tuple(values)))
        if self.open_fault:
            raise self.open_fault
        return self.open_code

    def close(self, pointer):
        self.events.append(('close', pointer.value))
        if self.close_fault:
            raise self.close_fault
        return self.close_code

    def enter(self, pointer):
        self.events.append('enter')
        if self.enter_fault:
            raise self.enter_fault
        return 0

    def take(self):
        return _OriginalDomainBorrow._map_original(self.functions, self.descriptor, self.material)


class OriginalDomainBorrowTests(unittest.TestCase):
    def test_same_record_scope_cleanup_and_independent_fd(self):
        f = BorrowFixture(); b = f.take()
        self.assertEqual(b._pointer.value % 8, 0)
        self.assertIs(b._descriptor, f.descriptor)
        with b._scope():
            b.require_physical_current()
        b.close(); before = list(f.events); b.close()
        self.assertEqual(f.events, before)
        self.assertTrue(b._closed)
        self.assertFalse(f.descriptor.close_attempted)

    def test_known_partial_open_retains_original_record_for_cleanup(self):
        f = BorrowFixture(); f.open_code = -2
        with self.assertRaises(_OriginalDomainBorrowError) as caught:
            f.take()
        self.assertFalse(caught.exception.unknown)
        b = caught.exception.cleanup_borrow
        self.assertIs(b._descriptor, f.descriptor)
        b.close()
        self.assertEqual(sum(type(e) is tuple and e[0] == 'open' for e in f.events), 1)

    def test_lost_open_keeps_same_carrier_and_never_retries_or_closes(self):
        f = BorrowFixture(); f.open_fault = OSError('lost open')
        with self.assertRaises(_OriginalDomainBorrowError) as caught:
            f.take()
        b = caught.exception.cleanup_borrow; before = list(f.events)
        for action in (b.close, b.require_physical_current):
            with self.assertRaises(_OriginalDomainBorrowError) as again:
                action()
            self.assertIs(again.exception, caught.exception)
        self.assertEqual(f.events, before)
        self.assertFalse(f.descriptor.close_attempted)

    def test_known_close_failure_retries_only_same_record_without_reopen(self):
        f = BorrowFixture(); b = f.take(); address = b._pointer.value; f.close_code = -2
        with self.assertRaises(_OriginalDomainBorrowError) as caught:
            b.close()
        self.assertFalse(caught.exception.unknown)
        self.assertFalse(b._closed)
        with self.assertRaises(ValueError):
            b.require_physical_current()
        f.close_code = 0; b.close()
        self.assertEqual([e for e in f.events if type(e) is tuple and e[0] == 'close'],
                         [('close', address), ('close', address)])
        self.assertEqual(sum(type(e) is tuple and e[0] == 'open' for e in f.events), 1)

    def test_lost_close_is_sticky_even_if_native_retired_before_raise(self):
        f = BorrowFixture(); b = f.take(); f.close_fault = OSError('lost close')
        with self.assertRaises(_OriginalDomainBorrowError) as caught:
            b.close()
        before = list(f.events)
        with self.assertRaises(_OriginalDomainBorrowError) as again:
            b.close()
        self.assertIs(again.exception, caught.exception)
        self.assertEqual(f.events, before)
        self.assertFalse(b._closed)

    def test_native_valueerror_is_unknown_not_local_precondition_refusal(self):
        f = BorrowFixture(); b = f.take(); f.enter_fault = ValueError('foreign return lost')
        with self.assertRaises(_OriginalDomainBorrowError) as caught:
            with b._scope():
                self.fail('Unexpected scope')
        self.assertTrue(caught.exception.unknown)
        self.assertFalse(b._busy)

    def test_copy_serialization_foreign_process_and_cloned_shell_refuse(self):
        f = BorrowFixture(); b = f.take()
        for action in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError):
                action(b)
        clone = object.__new__(_OriginalDomainBorrow); clone.__dict__.update(b.__dict__)
        before = list(f.events)
        with self.assertRaises(ValueError):
            clone.close()
        with patch('actql_sdk._local_native_domain_borrow.getpid', return_value=b._process + 1):
            with self.assertRaises(ValueError):
                b.close()
        self.assertEqual(f.events, before)
        b.close()

    def test_invalid_descriptor_or_record_abi_does_not_map(self):
        f = BorrowFixture(); f.descriptor.close_attempted = True
        with self.assertRaises(ValueError):
            f.take()
        f.descriptor.close_attempted = False; f.size = 65537
        with self.assertRaises(ValueError):
            f.take()
        self.assertFalse(f.events)
