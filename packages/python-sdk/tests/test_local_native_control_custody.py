"""Scalar call/slot fault counters, not C/Engine/installed runtime execution."""
import copy
from ctypes import c_void_p
import pickle
import os
from threading import current_thread
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_native_control_custody import (
    _OriginalControlCustody, _OriginalControlError, _OriginalControlFunctions,
)
from actql_sdk._local_native_initial_custody import (
    _OriginalPythonNativeInitial, _PythonNativeInitialPending,
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
            actql_control_acquire_fd_into=Function(self.acquire_fd),
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

    def acquire_fd(self, original, descriptor, reply):
        self.events.append(('acquire_fd', original.value, descriptor))
        self.replies[14] = (2, 0)
        reply._obj.value = 14
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
    def python_initial(self, fixture):
        # ABI-port fixture only: no actual Native Runtime, allocator original
        # or operational supplier is issued by these controlled callbacks.
        value = _OriginalPythonNativeInitial.__new__(_OriginalPythonNativeInitial)
        value._original = value
        value._process, value._thread = os.getpid(), current_thread()
        value._functions = SimpleNamespace(library=fixture.library,
            restore=Function(lambda _: fixture.events.append(('restore_initial',)) or 1))
        value._control_host = None
        value._initial = SimpleNamespace(require_cleanup_service=lambda: None)
        value._slot = c_void_p(99)
        value._busy = value._call_failed = value._unknown = value._restored = False
        value._pending = _PythonNativeInitialPending(value)
        return value

    def prepare(self, fixture, **changes):
        arguments = dict(source='a' * 40, recipe=b'r' * 32, generation=1, size=65536,
                         work=2, attempts=1, holdings=1, transfer=0, retained=0,
                         execution=65536, envelope=4096)
        arguments.update(changes)
        return _OriginalControlCustody._prepare_original(fixture.functions, **arguments)

    def preparation(self, fixture, *, fault=None):
        def call(source, units, recipe, count, generation, size, work, attempts,
                 holdings, transfer, retained, execution, envelope, reply):
            self.assertEqual((''.join(map(chr, source)), units, bytes(recipe), count),
                             ('a' * 40, 40, b'r' * 32, 32))
            fixture.events.append(('prepare', generation, size))
            reply._obj.value = 11
            if fault is not None:
                raise fault
            return 0
        fixture.library.actql_control_prepare_utf16_into = Function(call)

    def test_preparation_uses_original_owner_before_actual_fd_acquisition(self):
        f = Fixture(); self.preparation(f)
        host = self.prepare(f)
        self.assertEqual(f.events[:2], [('prepare', 1, 65536), ('capture', 11)])
        self.assertFalse(host._acquire_started)
        self.assertIsNone(host._borrowed_fd)
        host.close()
        self.assertTrue(host._closed)

    def test_python_host_keeps_initial_until_both_original_host_references_close(self):
        f = Fixture(); self.preparation(f)
        initial = self.python_initial(f)
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current'):
            host = self.prepare(f, _python_initial=initial)
            self.assertIs(initial._control_host, host)
            self.assertIs(host._python_initial_original, initial)
            with self.assertRaises(_PythonNativeInitialPending):
                initial.restore_default()
            self.assertNotIn(('restore_initial',), f.events)
            f.pending = True
            with self.assertRaises(_OriginalControlError):
                host.close()
            with self.assertRaises(_PythonNativeInitialPending):
                initial.restore_default()
            self.assertFalse(host._closed)
            f.pending = False
            host.close()
            initial.restore_default()
            self.assertTrue(initial._restored)
            self.assertEqual(f.events.count(('physical_close', 101)), 1)
            self.assertEqual(f.events.count(('restore_initial',)), 1)
            # Closing/refusing one Host is not a fresh startup baseline.
            with self.assertRaisesRegex(ValueError, 'already attempted'):
                self.prepare(f, _python_initial=initial)
            self.assertEqual(sum(x[0] == 'prepare' for x in f.events), 1)

    def test_python_lost_host_preparation_retains_initial_and_same_partial_reply(self):
        f = Fixture(); self.preparation(f, fault=OSError('lost Host preparation'))
        initial = self.python_initial(f)
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current'):
            with self.assertRaises(_OriginalControlError) as failure:
                self.prepare(f, _python_initial=initial)
            host = failure.exception.cleanup_host
            self.assertIs(initial._control_host, host)
            self.assertEqual(host._incoming.value, 11)
            with self.assertRaises(_PythonNativeInitialPending):
                initial.restore_default()
            with self.assertRaises(_OriginalControlError):
                host.close()
            self.assertEqual(f.events, [('prepare', 1, 65536)])

    def test_python_host_rejects_foreign_component_and_unavailable_current_before_prepare(self):
        f = Fixture(); self.preparation(f)
        initial = self.python_initial(Fixture())
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current') as current:
            with self.assertRaisesRegex(ValueError, 'Foreign original Python'):
                self.prepare(f, _python_initial=initial)
            current.assert_not_called()
        initial = self.python_initial(f)
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current',
                          side_effect=ValueError('Original Runtime unavailable')):
            with self.assertRaisesRegex(ValueError, 'Runtime unavailable'):
                self.prepare(f, _python_initial=initial)
        self.assertEqual(f.events, [])
        self.assertIsNone(initial._control_host)

    def test_python_normal_current_failure_keeps_same_host_cleanup(self):
        f = Fixture(); self.preparation(f)
        initial = self.python_initial(f)
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current'):
            host = self.prepare(f, _python_initial=initial)
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current',
                          side_effect=ValueError('Original normal current changed')):
            with self.assertRaisesRegex(ValueError, 'normal current changed'):
                host.current()
            # Same original cleanup does not revive normal current or invoke
            # another prepare/acquire merely to dispose of retained references.
            host.close()
        self.assertTrue(host._closed)
        self.assertNotIn(('current', 101), f.events)
        self.assertEqual(f.events.count(('physical_close', 101)), 1)

    def test_lost_preparation_keeps_same_reply_and_never_calls_acquire_or_capture(self):
        f = Fixture(); primary = OSError('lost prepare reply'); self.preparation(f, fault=primary)
        with self.assertRaises(_OriginalControlError) as observed:
            self.prepare(f)
        host = observed.exception.cleanup_host
        self.assertIs(observed.exception.__cause__, primary)
        self.assertEqual(host._incoming.value, 11)
        self.assertIsNone(host._original.value)
        self.assertEqual(f.events, [('prepare', 1, 65536)])
        with self.assertRaises(_OriginalControlError) as retry:
            host.close()
        self.assertIs(retry.exception, observed.exception)
        self.assertEqual(f.events, [('prepare', 1, 65536)])

    def test_preparation_data_rejects_bool_and_foreign_source_before_call(self):
        f = Fixture(); self.preparation(f)
        for changes in ({'source': 'g' * 40}, {'work': True}, {'generation': False},
                        {'size': 2**63}, {'recipe': b'r' * 31}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.prepare(f, **changes)
        self.assertEqual(f.events, [])

    def test_missing_preparation_abi_and_slot_failure_do_not_call_native(self):
        f = Fixture()
        with self.assertRaises(AttributeError):
            self.prepare(f)
        self.preparation(f)
        with patch('actql_sdk._local_native_control_custody._new_control_slots', side_effect=MemoryError):
            with self.assertRaises(MemoryError):
                self.prepare(f)
        self.assertEqual(f.events, [])

    def test_typed_refused_preparation_drops_only_empty_original_data(self):
        f = Fixture(); self.preparation(f); f.replies[11] = (1, 1)
        with self.assertRaises(_OriginalControlError) as observed:
            self.prepare(f)
        host = observed.exception.cleanup_host
        self.assertFalse(observed.exception.unknown)
        self.assertTrue(host._closed)
        self.assertIsNone(host._incoming.value)
        self.assertEqual(f.events, [('prepare', 1, 65536), ('drop', 11, None)])
        host.close()

    def test_refusal_with_inconsistent_partial_reply_is_unknown_and_kept(self):
        f = Fixture(); self.preparation(f); f.replies[11] = (1, 1)
        f.functions.drop.call = lambda *_: -2
        with self.assertRaises(_OriginalControlError) as observed:
            self.prepare(f)
        host = observed.exception.cleanup_host
        self.assertTrue(observed.exception.unknown)
        self.assertEqual(host._incoming.value, 11)
        self.assertFalse(host._closed)

    def test_lost_original_reply_keeps_carrier_when_late_error_metadata_is_unavailable(self):
        f = Fixture(); slot = c_void_p(11)
        primary = OSError('lost original capture response')
        f.capture_fault = primary
        original = f.functions.originals.call
        unavailable = patch('actql_sdk._local_native_control_custody._OriginalControlError',
                            side_effect=MemoryError('late error metadata'))

        def capture_then_lose(*args):
            unavailable.start()
            return original(*args)

        f.functions.originals.call = capture_then_lose
        try:
            with self.assertRaises(_OriginalControlError) as observed:
                _OriginalControlCustody._take_original_reply(f.functions, slot)
        finally:
            unavailable.stop()
        failure = observed.exception
        host = failure.cleanup_host
        self.assertTrue(failure.unknown)
        self.assertIs(failure.__cause__, primary)
        self.assertIsNone(slot.value)
        self.assertEqual((host._incoming.value, host._original.value, host._retained.value),
                         (11, 101, 101))
        self.assertFalse(host._closed)
        before = list(f.events)
        with self.assertRaises(_OriginalControlError) as retry: host.close()
        self.assertIs(retry.exception, failure)
        self.assertEqual(f.events, before)

    def test_slot_allocation_failure_keeps_caller_owned_input_without_native_calls(self):
        f = Fixture(); slot = c_void_p(11)
        primary = MemoryError('injected Python slot metadata allocation')
        with patch('actql_sdk._local_native_control_custody._new_control_slots', side_effect=primary):
            with self.assertRaises(MemoryError) as observed:
                _OriginalControlCustody._take_original_reply(f.functions, slot)
        self.assertIs(observed.exception, primary)
        self.assertEqual(slot.value, 11)
        self.assertEqual(f.events, [])

    def test_scope_capture_failure_keeps_caller_owned_input_before_native_calls(self):
        f = Fixture(); slot = c_void_p(11)
        primary = MemoryError('injected Python bootstrap scope allocation')
        with patch('actql_sdk._local_native_control_custody.getpid', side_effect=primary):
            with self.assertRaises(MemoryError) as observed:
                _OriginalControlCustody._take_original_reply(f.functions, slot)
        self.assertIs(observed.exception, primary)
        self.assertEqual(slot.value, 11, 'Caller still owns the original reply on pre-move failure')
        self.assertEqual(f.events, [])

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
        before = list(f.events)
        with patch('actql_sdk._local_native_control_custody.getpid', return_value=host._process + 1):
            with self.assertRaises(ValueError): host.close()
        self.assertEqual(f.events, before)
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
