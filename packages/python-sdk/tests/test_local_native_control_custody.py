"""Scalar call/slot fault counters, not C/Engine/installed runtime execution."""
import copy
from ctypes import c_void_p
import pickle
from types import SimpleNamespace
import unittest

from actql_sdk._local_native_control_custody import (
    _OriginalControlCustody, _OriginalControlError, _OriginalControlFunctions,
)


class Function:
    def __init__(self, call): self.call = call
    def __call__(self, *args): return self.call(*args)


class Fixture:
    def __init__(self):
        self.events = []
        self.replies = {11: (1, 0)}
        self.physically_closed = False
        self.close_fault = None
        self.capture_fault = None
        self.current_fault = None
        self.pending = False
        self.drop_fault = None
        self.reenter = None
        self.library = SimpleNamespace(
            actql_control_originals_into=Function(self.capture),
            actql_control_current_into=Function(self.current),
            actql_control_try_close_and_drop=Function(self.close),
            actql_control_drop_reply=Function(self.drop),
            actql_control_operation=Function(lambda p: self.replies[p.value][0]),
            actql_control_issue_family=Function(lambda p: self.replies[p.value][1]),
        )
        self.functions = _OriginalControlFunctions(self.library)

    def capture(self, reply, original, retained):
        self.events.append(('capture', reply.value))
        original._obj.value = 101
        retained._obj.value = 101
        if self.capture_fault: raise self.capture_fault
        return 0

    def drop(self, reply, original):
        self.events.append(('drop', reply._obj.value, original.value))
        reply._obj.value = None
        if self.drop_fault: raise self.drop_fault
        return 0

    def current(self, original, reply):
        self.events.append(('current', original.value))
        self.replies[12] = (3, 0)
        reply._obj.value = 12
        if self.current_fault: raise self.current_fault
        return 0

    def close(self, original, reply):
        self.events.append(('close', original._obj.value))
        if self.reenter: self.reenter()
        if self.pending:
            self.replies[13] = (4, 5)
            reply._obj.value = 13
            return -3
        if not self.physically_closed:
            self.physically_closed = True
            self.events.append(('physical_close', 101))
        original._obj.value = None
        if self.close_fault: raise self.close_fault
        return 0

    def take(self):
        slot = c_void_p(11)
        host = _OriginalControlCustody._take_original_reply(self.functions, slot)
        assert slot.value is None
        return host


class OriginalControlCustodyTests(unittest.TestCase):
    def test_same_original_references_close_via_core_without_transfer_or_provider_close(self):
        f = Fixture(); host = f.take()
        fact = host.current()
        self.assertEqual((fact.operation, fact.issue_family), (3, 0))
        self.assertFalse(hasattr(fact, 'execute'))
        host.close(); host.close()
        self.assertEqual(f.events.count(('physical_close', 101)), 1)
        self.assertEqual(f.events.count(('close', 101)), 2)
        self.assertTrue(host._closed)
        self.assertIs(host._functions.library, f.library)

    def test_response_loss_after_clearing_original_slot_preserves_retained_reference_and_is_sticky(self):
        f = Fixture(); host = f.take(); f.close_fault = OSError('lost close response')
        with self.assertRaises(_OriginalControlError) as observed: host.close()
        failure = observed.exception
        self.assertTrue(failure.unknown)
        self.assertIs(failure.cleanup_host, host)
        self.assertIsNone(host._original.value)
        self.assertEqual(host._retained.value, 101)
        self.assertFalse(host._closed)
        before = list(f.events)
        for _ in range(2):
            with self.assertRaises(_OriginalControlError) as retry: host.close()
            self.assertIs(retry.exception, failure)
        self.assertEqual(f.events, before)

    def test_known_pending_keeps_original_reply_and_retries_same_owner_after_stop(self):
        f = Fixture(); host = f.take(); f.pending = True
        with self.assertRaises(_OriginalControlError) as observed: host.close()
        self.assertFalse(observed.exception.unknown)
        self.assertEqual(observed.exception.fact.issue_family, 5)
        self.assertEqual(host._original.value, 101)
        self.assertEqual(host._retained.value, 101)
        self.assertEqual(host._reply.value, 13)
        self.assertFalse(f.physically_closed)
        f.pending = False
        host.close()
        self.assertEqual(f.events.count(('capture', 11)), 1)
        self.assertEqual(f.events.count(('physical_close', 101)), 1)

    def test_capture_response_loss_keeps_moved_incoming_and_both_original_slots(self):
        f = Fixture(); f.capture_fault = OSError('lost capture response'); slot = c_void_p(11)
        with self.assertRaises(_OriginalControlError) as observed:
            _OriginalControlCustody._take_original_reply(f.functions, slot)
        host = observed.exception.cleanup_host
        self.assertIsNone(slot.value)
        self.assertEqual(host._incoming.value, 11)
        self.assertEqual((host._original.value, host._retained.value), (101, 101))
        with self.assertRaises(_OriginalControlError): host.close()
        self.assertEqual(f.events, [('capture', 11)])

    def test_value_error_after_current_output_is_unknown_and_retains_same_reply(self):
        f = Fixture(); host = f.take(); f.current_fault = ValueError('lost current output')
        with self.assertRaises(_OriginalControlError) as observed: host.current()
        self.assertTrue(observed.exception.unknown)
        self.assertEqual(host._reply.value, 12)
        before = list(f.events)
        with self.assertRaises(_OriginalControlError): host.close()
        self.assertEqual(f.events, before)

    def test_data_drop_response_loss_never_reuses_cleared_reply_or_releases_host(self):
        f = Fixture(); host = f.take(); f.drop_fault = OSError('lost data drop')
        with self.assertRaises(_OriginalControlError): host.current()
        self.assertIsNone(host._reply.value)
        self.assertEqual(host._retained.value, 101)
        before = list(f.events)
        with self.assertRaises(_OriginalControlError): host.close()
        self.assertEqual(f.events, before)

    def test_copy_pickle_and_reentry_do_not_gain_another_call_scope(self):
        f = Fixture(); host = f.take()
        for action in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): action(host)
        def reenter():
            with self.assertRaises(ValueError): host.close()
        f.reenter = reenter
        host.close()
        self.assertEqual(f.events.count(('physical_close', 101)), 1)

    def test_boolean_fact_never_becomes_core_success(self):
        f = Fixture(); host = f.take()
        f.functions.issue.call = lambda p: False
        with self.assertRaises(_OriginalControlError) as observed: host.current()
        self.assertTrue(observed.exception.unknown)
        self.assertEqual(host._reply.value, 12)


if __name__ == '__main__': unittest.main()
