"""Private name projection custody; no physical file or publisher authority."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class PayloadNameCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        record = _Output(core._identity, 7, 23, 65536, 'payload_record')
        core._loans = {7: record}
        state = {'reserve': 29, 'produce': 0, 'validate': 0, 'close': -9, 'ready': False}
        wire = b'{"record_revision":"3","staging_name":"stage-original","object_name":"payload-original"}'
        calls = []

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'payload_names')
            if name == 'reserve':
                self.assertEqual(args[:2], (23, 8))
                self.assertGreaterEqual(args[2], 2 * 1024)
            if name == 'length':
                return state.get('length', len(wire))
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, record, calls, state, wire

    def test_original_record_current_configuration_and_exact_bytes_are_preserved(self):
        core, record, calls, _, wire = self.bridge()
        names = core.reserve_payload_names(record, cleanup=lambda: True)
        core.produce_payload_names(names, 31)
        self.assertEqual(core.read_payload_names(names, 37), wire)
        self.assertIn(('payload_names', 'produce', (29, 31)), calls)
        self.assertIn(('payload_names', 'validate', (29, 37)), calls)
        self.assertFalse(any(f in ('run', 'source', 'task', 'publication') for f, _, _ in calls))

    def test_cached_bytes_require_current_authorization_without_another_copy(self):
        core, record, calls, state, wire = self.bridge()
        names = core.reserve_payload_names(record, cleanup=lambda: True)
        self.assertEqual(core.read_payload_names(names, 31), wire)
        copies = sum(f == 'buffer' for f, _, _ in calls)
        self.assertIs(core.read_payload_names(names, 37), core._inputs[8].payload)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copies)
        state['validate'] = -32
        with self.assertRaises(LocalCoreError):
            core.read_payload_names(names, 41)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copies)

    def test_foreign_copies_family_and_controls_refuse_before_io(self):
        core, record, calls, _, _ = self.bridge()
        names = core.reserve_payload_names(record, cleanup=lambda: True)
        before = len(calls)
        for action in (lambda: core.reserve_payload_names(copy.copy(record), cleanup=lambda: True),
                       lambda: core.produce_payload_names(copy.copy(names), 31),
                       lambda: core.read_payload_names(record, 31),
                       lambda: core.produce_payload_names(names, True),
                       lambda: core.read_payload_names(names, 0),
                       lambda: core.close_payload_record(names)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_pending_close_keeps_original_parent_and_same_cleanup_allocation(self):
        core, record, _, state, _ = self.bridge()
        names = core.reserve_payload_names(record, cleanup=lambda: state['ready'])
        core._closing = True
        self.assertFalse(core.close_payload_names(names))
        self.assertIs(core._loans[8], names)
        state['close'] = 0
        self.assertFalse(core.close_payload_names(names))
        state['ready'] = True
        self.assertTrue(core.close_payload_names(names))
        self.assertIs(core._loans[7], record)
        with self.assertRaises(ValueError):
            core.close_payload_names(names)

    def test_invalid_lengths_refuse_before_reading_any_byte(self):
        core, record, calls, state, _ = self.bridge()
        names = core.reserve_payload_names(record, cleanup=lambda: True)
        for length in (-1, 1025):
            state['length'] = length
            with self.assertRaises((LocalCoreError, ValueError)):
                core.read_payload_names(names, 31)
        self.assertFalse(any(f == 'buffer' for f, _, _ in calls))

    def test_capacity_refusal_or_closing_never_acquires_a_projection(self):
        core, record, calls, state, _ = self.bridge()
        state['reserve'] = -4
        with self.assertRaises(LocalCoreError):
            core.reserve_payload_names(record, cleanup=lambda: True)
        self.assertNotIn(8, core._inputs)
        core._closing = True
        before = len(calls)
        with self.assertRaises(RuntimeError):
            core.reserve_payload_names(record, cleanup=lambda: True)
        self.assertEqual(len(calls), before)


if __name__ == '__main__':
    unittest.main()
