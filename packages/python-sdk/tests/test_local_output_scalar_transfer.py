"""Original output scalar transport; explicit buffer ports are not installed acceptance."""
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output, _PhysicalInput


class OriginalOutputScalarTransferTests(unittest.TestCase):
    def bridge(self, payload=b'\x00\x01\x7f\x80\xff\r\ne\xcc\x81/~\xf0\x9f\x98\x80'):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        core._inputs = {8: _PhysicalInput(b'', lambda: True, lambda _: True)}
        core._released = set()
        output = _Output(core._identity, 8, 23, 1048576, 'material')
        core._loans = {8: output}
        calls = []
        state = {'refusal': None, 'cleanup_ready': False}

        def call(family, name, *args):
            calls.append((family, name, args))
            if (family, name) == ('material', 'length'):
                self.assertEqual(args, (23,))
                return len(payload)
            if (family, name) == ('buffer', 'read_packed'):
                handle, start, count = args
                self.assertEqual(handle, 23)
                self.assertTrue(0 <= start <= len(payload))
                self.assertTrue(1 <= count <= 7 and start + count <= len(payload))
                if state['refusal'] is not None:
                    return state['refusal']
                # Independent little-endian integer oracle over original bytes.
                return sum(payload[start + offset] * 256**offset for offset in range(count))
            if (family, name) == ('buffer', 'byte'):
                self.fail('The selected output caller must not fall back to one FFI call per byte')
            if (family, name) == ('material', 'close'):
                if not state['cleanup_ready']:
                    return -9
                return core._cleanup(output.ticket)
            self.fail('Unexpected Core operation')

        core._call = call
        return core, output, calls, state, payload

    def test_same_original_bytes_use_bounded_seven_byte_scalars_and_keep_original_output(self):
        core, output, calls, state, payload = self.bridge()
        actual = core.read_material(output)
        self.assertEqual(actual, payload)
        transfers = [entry for entry in calls if entry[:2] == ('buffer', 'read_packed')]
        self.assertEqual([entry[2] for entry in transfers], [(23, 0, 7), (23, 7, 7), (23, 14, 2)])
        self.assertIs(core._loans[8], output)
        before = len(calls)
        self.assertIs(core.read_material(output), actual)
        self.assertEqual(len(calls), before)
        self.assertFalse(core.close_material(output))
        self.assertIs(core._loans[8], output)
        state['cleanup_ready'] = True
        self.assertTrue(core.close_material(output))
        self.assertNotIn(8, core._loans)

    def test_refused_or_out_of_range_scalar_keeps_original_loan_without_partial_cached_payload(self):
        for refusal in (-5, 2**56):
            core, output, calls, state, _ = self.bridge()
            state['refusal'] = refusal
            with self.assertRaises(LocalCoreError):
                core.read_material(output)
            self.assertIs(core._loans[8], output)
            self.assertEqual(core._inputs[8].payload, b'')
            self.assertFalse(any(name == 'close' for _, name, _ in calls))

    def test_empty_output_issues_no_transfer_and_foreign_output_refuses_before_ffi(self):
        core, output, calls, _, _ = self.bridge(b'')
        self.assertEqual(core.read_material(output), b'')
        self.assertEqual(calls, [('material', 'length', (23,))])
        foreign, _, _, _, _ = self.bridge()
        with self.assertRaises(ValueError):
            foreign.read_material(output)
