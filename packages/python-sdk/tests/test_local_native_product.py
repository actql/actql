"""Independent output-slot/fault counters; no DLL or installed product proof."""
from ctypes import c_void_p
from threading import Thread
import unittest
from unittest.mock import patch

from test_local_native_control_custody import Function
from test_local_native_runtime import RuntimeFixture
from actql_sdk._local_native_product import _OriginalPackagedProductFunctions
from actql_sdk._local_native_runtime import _OriginalPackagedRuntimeError


class ProductFixture(RuntimeFixture):
    def __init__(self):
        super().__init__()
        self.product_events, self.product_facts = [], {}
        self.product_issue, self.product_op = 0, None
        self.product_wire = '{"metadata":"Ω😀\\n"}'
        self.product_length, self.product_unit = None, None
        self.product_fault = self.product_drop_fault = None
        self.product_drop_code = 0
        self.product_validate_code = 0
        self.product_reads = 0
        functions = {
            'observe_utf16_into': self.observe_product,
            'identity_into': lambda r, out: self.product_reply(5, r, out),
            'operation': lambda r: self.product_facts[r.value][0],
            'issue_family': lambda r: self.product_facts[r.value][1],
            'metadata_units': self.units,
            'metadata_unit_at': self.unit,
            'drop_reply': self.product_drop,
            'validate_originals': lambda r, h, p, v: self.product_validate_code,
        }
        for name, fn in functions.items():
            setattr(self.host._functions.library, 'actql_packaged_product_' + name, Function(fn))
        self.product = _OriginalPackagedProductFunctions(self.host._functions.library)
        self.original = self.capture()

    def product_reply(self, op, runtime, out):
        self.product_events.append(('reply', op, runtime.value))
        key = 5500 + len(self.product_facts)
        self.product_facts[key] = (op if self.product_op is None else self.product_op,
                                   self.product_issue)
        out._obj.value = key
        if self.product_fault: raise self.product_fault
        return 0

    def observe_product(self, runtime, root, rn, launcher, ln, platform, pn, ceiling, out):
        self.product_events.append(('observe', bytes(root).decode('utf-16-le'), rn,
            bytes(launcher).decode('utf-16-le'), ln,
            bytes(platform).decode('utf-16-le'), pn, ceiling))
        return self.product_reply(4, runtime, out)

    def units(self, reply):
        self.product_reads += 1
        return (len(self.product_wire.encode('utf-16-le')) // 2
                if self.product_length is None else self.product_length)

    def unit(self, reply, index):
        self.product_reads += 1
        if self.product_unit is not None: return self.product_unit
        raw = self.product_wire.encode('utf-16-le')
        return int.from_bytes(raw[2 * index:2 * index + 2], 'little')

    def product_drop(self, out, host, read, runtime):
        self.product_events.append(('drop', out._obj.value, host.value, read.value, runtime.value))
        if self.product_drop_code: return self.product_drop_code
        out._obj.value = None
        if self.product_drop_fault: raise self.product_drop_fault
        return 0

    def observe(self, **kw):
        return self.product.observe_members(self.original,
            **({'launcher_root': '/private/launcher/日本😀',
                'launcher_descriptor_sha256': 'a' * 64,
                'platform_descriptor_sha256': 'b' * 64,
                'diagnostic_ceiling': 128} | kw))


class OriginalProductTests(unittest.TestCase):
    def test_exact_metadata_uses_same_runtime_then_inner_and_outer_close_separately(self):
        f = ProductFixture(); r = f.original
        self.assertEqual(f.observe().operation, 4)
        self.assertEqual(f.product_events[0][1], '/private/launcher/日本😀')
        self.assertEqual(f.product.identity_wire(r), f.product_wire)
        self.assertEqual(f.product_events[-1][2:], (101, 701, 901))
        self.assertIsNone(r._product_reply.value)
        self.assertIs(f.read._runtime_original, r)
        self.assertFalse(f.read._closed)
        r.close(); self.assertFalse(f.read._closed); f.read.close()

    def test_all_native_known_issues_preserve_tags_and_allow_existing_cleanup(self):
        for issue in (1, 2, 3, 4, 5, 6, 8, 9):
            f = ProductFixture(); f.product_issue = issue
            with self.subTest(issue=issue), self.assertRaises(_OriginalPackagedRuntimeError) as got:
                f.observe()
            self.assertFalse(got.exception.unknown)
            self.assertEqual(got.exception.fact.issue_family, issue)
            self.assertIs(got.exception.cleanup_runtime, f.original)
            self.assertIsNone(f.original._product_reply.value)
            f.original.close(); f.read.close()

    def test_native_unknown_and_lost_output_response_keep_same_original_without_replay(self):
        for mode in ('unknown', 'lost'):
            f = ProductFixture()
            if mode == 'unknown': f.product_issue = 7
            else: f.product_fault = OSError('lost metadata response')
            with self.assertRaises(_OriginalPackagedRuntimeError) as got: f.observe()
            self.assertTrue(got.exception.unknown)
            self.assertIs(got.exception.cleanup_runtime, f.original)
            before = list(f.product_events)
            for call in (lambda: f.product.identity_wire(f.original), f.original.close):
                with self.assertRaises(_OriginalPackagedRuntimeError) as again: call()
                self.assertIs(again.exception, got.exception)
            self.assertEqual(f.product_events, before)
            self.assertIs(f.read._runtime_original, f.original)
            self.assertFalse(f.original._closed)

    def test_drop_response_loss_and_wrong_nominal_keep_unknown_and_outer_loan(self):
        for mode in ('cleared-then-lost', 'foreign'):
            f = ProductFixture()
            if mode == 'foreign': f.product_drop_code = -2
            else: f.product_drop_fault = OSError('lost data release')
            with self.assertRaises(_OriginalPackagedRuntimeError) as got:
                f.product.identity_wire(f.original)
            self.assertTrue(got.exception.unknown)
            self.assertEqual(f.original._product_reply.value is None, mode == 'cleared-then-lost')
            self.assertFalse(f.read._closed)
            with self.assertRaises(_OriginalPackagedRuntimeError): f.original.close()

    def test_wrong_response_tags_and_invalid_bounded_utf16_are_not_partial_success(self):
        for name, value in (('product_op', 4), ('product_issue', 10),
                            ('product_length', 0), ('product_length', 4097),
                            ('product_length', True), ('product_unit', -1),
                            ('product_unit', 65536), ('product_unit', True),
                            ('product_unit', 0xD800)):
            f = ProductFixture(); setattr(f, name, value)
            with self.subTest(name=name, value=value), self.assertRaises(_OriginalPackagedRuntimeError):
                f.product.identity_wire(f.original)
            self.assertIsNotNone(f.original._unknown)
            self.assertIsNotNone(f.original._product_reply.value)

    def test_foreign_original_is_rejected_before_any_metadata_copy(self):
        f = ProductFixture(); f.product_validate_code = -2
        with self.assertRaises(_OriginalPackagedRuntimeError) as got:
            f.product.identity_wire(f.original)
        self.assertTrue(got.exception.unknown)
        self.assertEqual(f.product_reads, 0)
        self.assertIsNotNone(f.original._product_reply.value)
        self.assertIs(f.read._runtime_original, f.original)

    def test_invalid_input_and_foreign_library_refuse_before_io_without_poison(self):
        f = ProductFixture()
        for kw in ({'launcher_root': '\ud800'}, {'launcher_root': 'a' * 4097},
                   {'launcher_descriptor_sha256': 'a'}, {'diagnostic_ceiling': True}):
            with self.assertRaises((ValueError, UnicodeError)): f.observe(**kw)
        other = ProductFixture()
        with self.assertRaises(ValueError): other.product.identity_wire(f.original)
        with self.assertRaises(ValueError): f.product._call(f.original, 99)
        self.assertEqual(f.product_events, []); self.assertIsNone(f.original._unknown)
        f.original.close(); f.read.close()

    def test_busy_thread_and_process_refuse_before_foreign_operation(self):
        f = ProductFixture(); f.host._busy = True
        with self.assertRaises(ValueError): f.observe()
        self.assertTrue(f.host._busy); f.host._busy = False
        errors = []
        def call():
            try: f.observe()
            except BaseException as error: errors.append(error)
        t = Thread(target=call); t.start(); t.join()
        self.assertIsInstance(errors[0], ValueError)
        with patch('actql_sdk._local_native_control_custody.getpid', return_value=-1):
            with self.assertRaises(ValueError): f.observe()
        self.assertEqual(f.product_events, []); self.assertIsNone(f.original._unknown)
        f.original.close()

    def test_pending_product_slot_blocks_ordinary_runtime_calls(self):
        f = ProductFixture(); f.original._product_reply = c_void_p(991)
        before = list(f.runtime_events)
        for call in (f.original.current, f.original.close, f.observe):
            with self.assertRaises(ValueError): call()
        self.assertEqual(f.runtime_events, before)
        self.assertEqual(f.product_events, [])
        self.assertEqual(f.original._product_reply.value, 991)

    def test_allocation_reentry_rechecks_retirement_before_foreign_call(self):
        f = ProductFixture()
        from actql_sdk import _local_native_product as module
        actual = module.byref
        def closed(value):
            f.original.close()
            return actual(value)
        with patch.object(module, 'byref', side_effect=closed):
            with self.assertRaises(ValueError): f.observe()
        self.assertEqual(f.product_events, []); self.assertIsNone(f.original._unknown)
        self.assertTrue(f.original._closed); self.assertFalse(f.host._busy)


if __name__ == '__main__':
    unittest.main()
