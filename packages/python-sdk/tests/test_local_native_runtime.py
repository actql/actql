"""Independent slot/fault counters, not physical Runtime or installed proof."""
import copy
import pickle
from threading import Thread
import unittest
from unittest.mock import patch

from test_local_native_control_custody import Function
from test_local_native_original_read import ParentReadFixture
from test_local_native_host_resources import PairFixture
from actql_sdk._local_native_runtime_abi import BINDING_VERSION, BINDING_SHA256
from actql_sdk._local_native_runtime import (
    _OriginalPackagedRuntimeCustody, _OriginalPackagedRuntimeFunctions,
    _OriginalPackagedRuntimeError,
)


class RuntimeCalls:
    def install_runtime_calls(self):
        self.runtime_events, self.runtime_facts = [], {}
        self.runtime_present, self.runtime_wrong_host, self.runtime_wrong_op = True, False, False
        self.runtime_issue = self.runtime_current_issue = self.runtime_close_issue = 0
        self.runtime_capture_fault = self.runtime_originals_fault = None
        self.runtime_call_fault = self.runtime_drop_fault = self.runtime_finish_fault = None
        functions = {
            'binding_version': lambda: BINDING_VERSION,
            'binding_byte': lambda index: BINDING_SHA256.encode('ascii')[index],
            'capture_utf16_into': self.capture_runtime,
            'capture_host_resources_utf16_into': self.capture_runtime_pair,
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

    def capture_runtime_pair(self, h, r, resources, a, an, b, bn, c, cn, d, dn, ceiling, out):
        self.runtime_events.append(('capture_pair', h.value, r.value, resources.value,
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


class RuntimeFixture(RuntimeCalls, ParentReadFixture):
    def __init__(self):
        ParentReadFixture.__init__(self)
        self.install_runtime_calls()
        self.read = self.parent_read()


class PairRuntimeFixture(RuntimeCalls, PairFixture):
    def __init__(self):
        PairFixture.__init__(self)
        self.install_runtime_calls()
        self.read = self.r
        self.resources = self.pair()


class OriginalRuntimeTests(unittest.TestCase):
    def test_stale_binding_refuses_before_original_operation(self):
        f = RuntimeFixture()
        f.host._functions.library.actql_packaged_runtime_binding_version = Function(lambda: 0)
        with self.assertRaisesRegex(ValueError, 'Native Runtime binding'):
            _OriginalPackagedRuntimeFunctions(f.host._functions.library)
        self.assertEqual(f.runtime_events, [])
        self.assertIsNone(f.read._runtime_original)

    def test_different_compiled_declaration_refuses_before_original_operation(self):
        f = RuntimeFixture()
        f.host._functions.library.actql_packaged_runtime_binding_byte = Function(lambda _: ord('0'))
        with self.assertRaisesRegex(ValueError, 'Native Runtime binding'):
            _OriginalPackagedRuntimeFunctions(f.host._functions.library)
        self.assertEqual(f.runtime_events, [])
        self.assertIsNone(f.read._runtime_original)

    def test_same_width_utf16_roles_keep_independent_meaning(self):
        f = RuntimeFixture()
        observed = []
        original = f.capture_runtime
        def capture(h, r, a, an, b, bn, c, cn, d, dn, ceiling, out):
            observed.append((bytes(a).decode('utf-16-le'), bytes(b).decode('utf-16-le'),
                             bytes(c).decode('utf-16-le'), bytes(d).decode('utf-16-le')))
            return original(h, r, a, an, b, bn, c, cn, d, dn, ceiling, out)
        f.host._functions.library.actql_packaged_runtime_capture_utf16_into = Function(capture)
        f.runtime_functions = _OriginalPackagedRuntimeFunctions(f.host._functions.library)
        r = f.capture()
        self.assertEqual(observed, [('/private/runtime/日本😀', 'a' * 40, 'darwin-arm64', 'b' * 64)])
        r.close()
        f.read.close()

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




class OriginalHostPairRuntimeTests(unittest.TestCase):
    def test_capture_uses_the_same_bound_pair_without_direct_read_or_second_claim(self):
        f = PairRuntimeFixture()
        f.resources.claim_read(123, 456)
        pair_before = list(f.pair_events)
        runtime = f.capture()
        self.assertIs(runtime._resources, f.resources)
        self.assertIs(runtime._read, f.r)
        self.assertEqual([x[:4] for x in f.runtime_events if x[0] == 'capture_pair'],
                         [('capture_pair', 101, 701, 801)])
        self.assertFalse(any(x[0] == 'capture' for x in f.runtime_events))
        self.assertEqual(f.pair_events, pair_before)
        self.assertIsNone(f.resources._phase)
        self.assertFalse(f.r._scope_open)
        runtime.current()
        runtime.close()
        self.assertFalse(f.resources._closed or f.r._closed or f.s._closed)
        self.assertEqual(len([x for x in f.pair_events if x[0] == 'claim']), 1)

    def test_active_or_retired_pair_refuses_before_runtime_registration_and_foreign_calls(self):
        f = PairRuntimeFixture()
        with f.resources.scope('sqlite'):
            with self.assertRaises(ValueError): f.capture()
        self.assertEqual(f.runtime_events, [])
        self.assertIsNone(f.r._runtime_original)
        f.resources.close()
        with self.assertRaises(ValueError): f.capture()
        self.assertEqual(f.runtime_events, [])
        self.assertIsNone(f.r._runtime_original)

    def test_unrelated_domain_cannot_fall_back_to_the_direct_read_entry(self):
        f = PairRuntimeFixture()
        foreign_read = f.parent_read()
        with self.assertRaises(ValueError):
            _OriginalPackagedRuntimeCustody._capture_original(foreign_read, f.runtime_functions,
                root_path='/unopened/runtime', source_sha='a'*40, platform='darwin-arm64',
                manifest_sha256='b'*64, diagnostic_ceiling=65536)
        self.assertEqual(f.runtime_events, [])
        self.assertIsNone(foreign_read._runtime_original)

    def test_known_pair_refusal_keeps_the_original_native_issue_and_parent_custody(self):
        f = PairRuntimeFixture()
        f.runtime_issue = 10
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        runtime = caught.exception.cleanup_runtime
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(caught.exception.fact.issue_family, 10)
        self.assertIs(runtime._resources, f.resources)
        self.assertIs(f.r._runtime_original, runtime)
        self.assertFalse(f.resources._closed or runtime._closed)
        self.assertFalse(any(x[0] == 'capture' for x in f.runtime_events))
        runtime.close()
        self.assertFalse(f.resources._closed)

    def test_lost_pair_capture_reply_keeps_partial_slots_and_never_calls_direct_capture(self):
        f = PairRuntimeFixture()
        f.runtime_capture_fault = RuntimeError('lost pair capture response')
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        runtime = caught.exception.cleanup_runtime
        self.assertTrue(caught.exception.unknown)
        self.assertIs(runtime._resources, f.resources)
        self.assertIs(f.r._runtime_original, runtime)
        self.assertIsNotNone(runtime._reply.value)
        before = list(f.runtime_events)
        with self.assertRaises(_OriginalPackagedRuntimeError): runtime.close()
        with self.assertRaises(ValueError): f.capture()
        self.assertEqual(f.runtime_events, before)
        self.assertFalse(f.resources._closed)

    def test_original_imported_unknown_stays_sticky_with_the_same_pair(self):
        f = PairRuntimeFixture()
        f.runtime_issue = 7
        with self.assertRaises(_OriginalPackagedRuntimeError) as caught: f.capture()
        runtime = caught.exception.cleanup_runtime
        self.assertTrue(caught.exception.unknown)
        self.assertEqual(caught.exception.fact.issue_family, 7)
        self.assertIs(runtime._resources, f.resources)
        before = list(f.runtime_events)
        with self.assertRaises(_OriginalPackagedRuntimeError): runtime.current()
        self.assertEqual(f.runtime_events, before)
        self.assertFalse(f.resources._closed)


if __name__ == '__main__':
    unittest.main()
