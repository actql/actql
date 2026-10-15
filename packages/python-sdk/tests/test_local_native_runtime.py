"""Independent slot/fault counters, not physical Runtime or installed proof."""
import copy
import pickle
from threading import Thread
import unittest
from unittest.mock import patch

from test_local_native_control_custody import Function
from test_local_native_original_read import ParentReadFixture
from actql_sdk._local_native_runtime import (
    _OriginalPackagedRuntimeCustody, _OriginalPackagedRuntimeFunctions,
    _OriginalPackagedRuntimeError,
)


class RuntimeFixture(ParentReadFixture):
    def __init__(self):
        super().__init__()
        self.runtime_events, self.runtime_facts = [], {}
        self.runtime_present, self.runtime_wrong_host, self.runtime_wrong_op = True, False, False
        self.runtime_issue = self.runtime_current_issue = self.runtime_close_issue = 0
        self.runtime_capture_fault = self.runtime_originals_fault = None
        self.runtime_call_fault = self.runtime_drop_fault = self.runtime_finish_fault = None
        functions = {
            'capture_utf16_into': self.capture_runtime,
            'originals_into': self.runtime_originals,
            'drop_reply': self.runtime_drop,
            'finish_closed_data': self.runtime_finish,
            'finish_refused_capture': self.runtime_refused,
            'current_into': lambda r, out: self.runtime_call(2, r, out),
            'close_into': lambda r, out: self.runtime_call(3, r, out),
            'operation': lambda r: self.runtime_facts[r.value][0],
            'issue_family': lambda r: self.runtime_facts[r.value][1],
        }
        for name, fn in functions.items():
            setattr(self.host._functions.library, 'actql_packaged_runtime_' + name, Function(fn))
        self.runtime_functions = _OriginalPackagedRuntimeFunctions(self.host._functions.library)
        self.read = self.parent_read()

    def runtime_result(self, out, op, issue):
        key = 3500 + len(self.runtime_facts)
        self.runtime_facts[key] = (99 if self.runtime_wrong_op else op, issue)
        out._obj.value = key

    def capture_runtime(self, h, r, a, an, b, bn, c, cn, d, dn, ceiling, out):
        self.runtime_events.append(('capture', h.value, r.value,
            bytes(a).decode('utf-16-le'), an, bn, cn, dn, ceiling))
        self.runtime_result(out, 1, self.runtime_issue)
        if self.runtime_capture_fault: raise self.runtime_capture_fault
        return 0

    def runtime_originals(self, reply, host, read, runtime):
        self.runtime_events.append(('originals', reply.value))
        host._obj.value = 999 if self.runtime_wrong_host else 101
        read._obj.value = 701
        if self.runtime_originals_fault: raise self.runtime_originals_fault
        runtime._obj.value = 901 if self.runtime_present else None
        return 0

    def runtime_call(self, op, runtime, out):
        self.runtime_events.append(('call', op, runtime.value))
        self.runtime_result(out, op, self.runtime_current_issue if op == 2 else self.runtime_close_issue)
        if self.runtime_call_fault: raise self.runtime_call_fault
        return 0

    def runtime_drop(self, reply, host, read, runtime):
        self.runtime_events.append(('drop', reply._obj.value))
        reply._obj.value = None
        if self.runtime_drop_fault: raise self.runtime_drop_fault
        return 0

    def runtime_finish(self, host, read, runtime, reply):
        self.runtime_events.append(('finish', host._obj.value, read._obj.value, runtime._obj.value))
        host._obj.value = read._obj.value = runtime._obj.value = reply._obj.value = None
        if self.runtime_finish_fault: raise self.runtime_finish_fault
        return 0

    def runtime_refused(self, host, read, reply):
        self.runtime_events.append(('refused', host._obj.value, read._obj.value))
        host._obj.value = read._obj.value = reply._obj.value = None
        return 0

    def capture(self, **kwargs):
        return _OriginalPackagedRuntimeCustody._capture_original(self.read, self.runtime_functions,
            **({'root_path': '/private/runtime/日本😀', 'source_sha': 'a' * 40,
                'platform': 'darwin-arm64', 'manifest_sha256': 'b' * 64,
                'diagnostic_ceiling': 65536} | kwargs))


class OriginalRuntimeTests(unittest.TestCase):
    def test_inner_close_clears_original_slots_without_parent_retirement(self):
        f = RuntimeFixture(); r = f.capture()
        self.assertEqual((r._host.value, r._original_read.value, r._runtime.value), (101, 701, 901))
        self.assertEqual(r.current().operation, 2)
        before = list(f.parent_events); r.close(); r.close()
        self.assertEqual(f.parent_events, before)
        self.assertFalse(f.read._closed)
        self.assertFalse(f.host._closed)
        self.assertTrue(r._closed)
        self.assertIsNone(r._runtime.value)
        self.assertIsNot(f.read._runtime_original, r)
        with self.assertRaises(ValueError): f.capture()
        with self.assertRaises(ValueError): r.current()
        f.read.close()

    def test_parent_close_and_scope_refuse_until_same_runtime_data_ack(self):
        f = RuntimeFixture(); r = f.capture(); before = list(f.parent_events)
        for call in (f.read.close, lambda: f.read.scope().__enter__(),
                     lambda: f.read.scope(cleanup=True).__enter__()):
            with self.assertRaises(ValueError): call()
        self.assertEqual(f.parent_events, before)
        r.close(); f.read.close()

    def test_known_partial_capture_retains_same_runtime_for_cleanup(self):
        f = RuntimeFixture(); f.runtime_issue = 9
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        r = caught.exception.cleanup_runtime
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(r._runtime.value, 901)
        self.assertIs(f.read._runtime_original, r)
        f.runtime_close_issue = 9
        with self.assertRaises(_OriginalPackagedRuntimeError): r.close()
        f.runtime_close_issue = 0; r.close()

    def test_no_runtime_known_refusal_drops_data_without_close_or_reissue(self):
        f = RuntimeFixture(); f.runtime_present = False; f.runtime_issue = 1
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        r = caught.exception.cleanup_runtime
        self.assertFalse(caught.exception.unknown); self.assertTrue(r._closed)
        self.assertIsNone(r._runtime.value)
        self.assertFalse(any(x[0] == 'call' for x in f.runtime_events))
        with self.assertRaises(ValueError): f.capture()
        f.read.close()

    def test_lost_capture_response_keeps_reply_and_registration_without_replay(self):
        f = RuntimeFixture(); f.runtime_capture_fault = OSError('lost capture response')
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        r = caught.exception.cleanup_runtime; before = list(f.runtime_events)
        self.assertTrue(caught.exception.unknown); self.assertIsNotNone(r._reply.value)
        self.assertIs(f.read._runtime_original, r)
        for action in (r.current, r.close):
            with self.assertRaises(_OriginalPackagedRuntimeError) as again: action()
            self.assertIs(again.exception, caught.exception)
        self.assertEqual(f.runtime_events, before)
        with self.assertRaises(ValueError): f.read.close()

    def test_partial_original_capture_keeps_written_slots_and_original_reply(self):
        f = RuntimeFixture(); f.runtime_originals_fault = MemoryError('lost original capture')
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        r = caught.exception.cleanup_runtime
        self.assertEqual((r._host.value, r._original_read.value), (101, 701))
        self.assertIsNone(r._runtime.value); self.assertIsNotNone(r._reply.value)
        self.assertFalse(f.host._busy)

    def test_lost_drop_response_is_sticky_even_after_slot_was_cleared(self):
        f = RuntimeFixture(); f.runtime_drop_fault = OSError('lost data response')
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        r = caught.exception.cleanup_runtime; before = list(f.runtime_events)
        self.assertTrue(caught.exception.unknown); self.assertIsNone(r._reply.value)
        self.assertEqual(r._runtime.value, 901)
        with self.assertRaises(_OriginalPackagedRuntimeError): r.close()
        self.assertEqual(f.runtime_events, before)

    def test_lost_close_reply_and_lost_final_slot_ack_never_acknowledge_cleanup(self):
        for where in ('call', 'finish'):
            f = RuntimeFixture(); r = f.capture()
            setattr(f, 'runtime_' + where + '_fault', OSError('lost close response'))
            with self.assertRaises(_OriginalPackagedRuntimeError) as caught: r.close()
            self.assertTrue(caught.exception.unknown); self.assertFalse(r._closed)
            self.assertIs(f.read._runtime_original, r)
            before = list(f.runtime_events)
            with self.assertRaises(_OriginalPackagedRuntimeError): r.close()
            self.assertEqual(f.runtime_events, before)

    def test_native_unknown_is_not_known_refusal_or_cleanup_permission(self):
        f = RuntimeFixture(); f.runtime_issue = 7
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        self.assertTrue(caught.exception.unknown)
        self.assertEqual(caught.exception.fact.issue_family, 7)
        before = list(f.runtime_events)
        with self.assertRaises(_OriginalPackagedRuntimeError): caught.exception.cleanup_runtime.close()
        self.assertEqual(f.runtime_events, before)

    def test_wrong_nominal_or_operation_response_keeps_unknown_original(self):
        for flag in ('runtime_wrong_host', 'runtime_wrong_op'):
            f = RuntimeFixture(); setattr(f, flag, True)
            with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
            self.assertTrue(caught.exception.unknown)
            self.assertIs(f.read._runtime_original, caught.exception.cleanup_runtime)

    def test_busy_and_thread_process_entry_refusal_do_not_register_or_poison(self):
        f = RuntimeFixture(); f.host._busy = True
        with self.assertRaises(ValueError): f.capture()
        self.assertIsNone(f.read._runtime_original); self.assertTrue(f.host._busy)
        f.host._busy = False; r = f.capture(); before = list(f.runtime_events); errors = []
        def current():
            try: r.current()
            except BaseException as e: errors.append(e)
        thread = Thread(target=current); thread.start(); thread.join()
        self.assertIsInstance(errors[0], ValueError)
        with patch('actql_sdk._local_native_control_custody.getpid', return_value=-1):
            with self.assertRaises(ValueError): r.current()
        self.assertEqual(f.runtime_events, before); self.assertIsNone(r._unknown)
        r.close()

    def test_outslot_allocation_failure_is_before_entry_and_registration(self):
        f = RuntimeFixture()
        with patch('actql_sdk._local_native_runtime.byref', side_effect=MemoryError('before FFI')):
            with self.assertRaises(MemoryError): f.capture()
        self.assertIsNone(f.read._runtime_original); self.assertFalse(f.host._busy)
        self.assertEqual(f.runtime_events, [])

    def test_parent_retired_during_preallocation_refuses_before_ffi(self):
        f = RuntimeFixture()
        from actql_sdk import _local_native_runtime as module
        actual = module.byref; once = [True]
        def callback(value):
            if once[0]: once[0] = False; f.read.close()
            return actual(value)
        with patch.object(module, 'byref', side_effect=callback):
            with self.assertRaises(ValueError): f.capture()
        self.assertEqual(f.runtime_events, []); self.assertFalse(f.host._busy)

    def test_runtime_retired_during_outslot_allocation_is_known_without_second_call(self):
        f = RuntimeFixture(); r = f.capture()
        from actql_sdk import _local_native_runtime as module
        actual = module.byref; once = [True]
        def callback(value):
            if once[0]: once[0] = False; r.close()
            return actual(value)
        with patch.object(module, 'byref', side_effect=callback):
            with self.assertRaises(ValueError): r.current()
        self.assertTrue(r._closed); self.assertIsNone(r._unknown)
        self.assertEqual(len([e for e in f.runtime_events if e[0] == 'call']), 1)

    def test_existing_domain_unknown_remains_its_original_refusal(self):
        f = RuntimeFixture(); r = f.capture(); original = f.read._domain._mark_unknown()
        before = list(f.runtime_events)
        with self.assertRaises(type(original)) as caught: r.current()
        self.assertIs(caught.exception, original)
        self.assertEqual(f.runtime_events, before); self.assertIsNone(r._unknown)
        g = RuntimeFixture(); other = g.capture(); g.read._domain._closed = True
        before = list(g.runtime_events)
        with self.assertRaises(ValueError): other.current()
        self.assertEqual(g.runtime_events, before); self.assertIsNone(other._unknown)

    def test_exact_unicode_input_invalid_scalar_copy_and_foreign_selection(self):
        f = RuntimeFixture()
        for kw in ({'source_sha': 'short'}, {'root_path': '\ud800'},
                   {'diagnostic_ceiling': True}, {'platform': 'x' * 33}):
            with self.subTest(kw=kw), self.assertRaises((ValueError, UnicodeError)): f.capture(**kw)
        self.assertEqual(f.runtime_events, []); self.assertIsNone(f.read._runtime_original)
        r = f.capture(); self.assertEqual(f.runtime_events[0][3], '/private/runtime/日本😀')
        for action in (lambda: copy.copy(r), lambda: copy.deepcopy(r), lambda: pickle.dumps(r)):
            with self.assertRaises(TypeError): action()
        other = RuntimeFixture()
        with self.assertRaises(ValueError):
            _OriginalPackagedRuntimeCustody._capture_original(other.read, f.runtime_functions,
                root_path='/runtime', source_sha='a' * 40, platform='darwin-arm64',
                manifest_sha256='b' * 64, diagnostic_ceiling=65536)
        r.close()


if __name__ == '__main__':
    unittest.main()
