"""Private physical Intent loans; every record decision stays in Core."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output


class PayloadRecordCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        request = _Output(core._identity, 7, 23, 65536, 'payload_request')
        observation = _Input(core._identity, 1, 11, 300)
        core._loans = {7: request, 1: observation}
        state = {'reserve': 29, 'produce': 0, 'validate': 0, 'begin': 0,
                 'confirm': 0, 'close': -9, 'cleanup_ready': False}
        wire = b'{"revision":"0","state":"intent","original":"e\xcc\x81/~"}'
        calls = []

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'payload_record')
            if name == 'reserve':
                self.assertEqual(args[:2], (23, 8))
                self.assertGreaterEqual(args[2], 2 * 65536)
            if name == 'length':
                return state.get('length', len(wire))
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = call
        return core, request, observation, calls, state, wire

    def test_original_request_current_context_and_physical_input_are_forwarded(self):
        core, request, observation, calls, _, wire = self.bridge()
        record = core.reserve_payload_record(request, cleanup=lambda: True)
        core.produce_payload_record(record, 31)
        self.assertEqual(core.read_payload_record(record, 37), wire)
        core.begin_payload_record(record, 41)
        core.confirm_payload_record(record, observation, 43)
        self.assertIn(('payload_record', 'confirm', (29, 11, 43)), calls)
        self.assertFalse(any(f in ('run', 'source', 'task', 'publication') for f, _, _ in calls))

    def test_cached_bytes_still_recheck_current_authority(self):
        core, request, _, calls, state, wire = self.bridge()
        record = core.reserve_payload_record(request, cleanup=lambda: True)
        self.assertEqual(core.read_payload_record(record, 31), wire)
        copies = sum(f == 'buffer' for f, _, _ in calls)
        self.assertIs(core.read_payload_record(record, 37), core._inputs[8].payload)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copies)
        state['validate'] = -32
        with self.assertRaises(LocalCoreError):
            core.read_payload_record(record, 41)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copies)

    def test_repeated_begin_and_bad_observation_are_not_physical_write_permission(self):
        core, request, observation, calls, state, _ = self.bridge()
        record = core.reserve_payload_record(request, cleanup=lambda: True)
        core.begin_payload_record(record, 31)
        state['begin'] = -33
        with self.assertRaises(LocalCoreError):
            core.begin_payload_record(record, 31)
        state['confirm'] = -32
        with self.assertRaises(LocalCoreError):
            core.confirm_payload_record(record, observation, 31)
        self.assertIs(core._loans[8], record)
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)

    def test_copies_foreign_family_and_invalid_controls_fail_before_io(self):
        core, request, observation, calls, _, _ = self.bridge()
        record = core.reserve_payload_record(request, cleanup=lambda: True)
        before = len(calls)
        for action in (
            lambda: core.reserve_payload_record(copy.copy(request), cleanup=lambda: True),
            lambda: core.produce_payload_record(copy.copy(record), 31),
            lambda: core.read_payload_record(request, 31),
            lambda: core.begin_payload_record(record, True),
            lambda: core.confirm_payload_record(record, copy.copy(observation), 31),
            lambda: core.confirm_payload_record(record, observation, 0),
            lambda: core.close_payload_request(record),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_pending_close_keeps_original_handle_and_allocation_for_confirmation(self):
        core, request, observation, _, state, _ = self.bridge()
        record = core.reserve_payload_record(request, cleanup=lambda: state['cleanup_ready'])
        core.begin_payload_record(record, 31)
        core._closing = True
        self.assertFalse(core.close_payload_record(record))
        core.confirm_payload_record(record, observation, 31)
        state['close'] = 0
        self.assertFalse(core.close_payload_record(record))
        self.assertIs(core._loans[8], record)
        state['cleanup_ready'] = True
        self.assertTrue(core.close_payload_record(record))
        self.assertIs(core._loans[7], request)
        self.assertIs(core._loans[1], observation)
        with self.assertRaises(ValueError):
            core.close_payload_record(record)

    def test_capacity_refusal_and_closing_never_create_another_record(self):
        core, request, _, calls, state, _ = self.bridge()
        state['reserve'] = -4
        with self.assertRaises(LocalCoreError):
            core.reserve_payload_record(request, cleanup=lambda: True)
        self.assertNotIn(8, core._inputs)
        core._closing = True
        before = len(calls)
        with self.assertRaises(RuntimeError):
            core.reserve_payload_record(request, cleanup=lambda: True)
        self.assertEqual(len(calls), before)

    def test_saved_parent_reservation_preserves_original_family_and_read_only_core_refusal(self):
        core, _, _, calls, state, wire = self.bridge()
        parent = _Output(core._identity, 7, 23, 65536, 'submission_lookup')
        core._loans[7] = parent
        record = core.reserve_saved_payload_record(parent, cleanup=lambda: True)
        core.produce_payload_record(record, 31)
        self.assertEqual(core.read_payload_record(record, 31), wire)
        state['begin'] = -2
        with self.assertRaises(LocalCoreError):
            core.begin_payload_record(record, 31)
        self.assertIs(core._loans[8], record)
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)

    def test_saved_record_reservation_rejects_wrong_family_and_copy_before_ffi(self):
        core, request, _, calls, _, _ = self.bridge()
        before = len(calls)
        with self.assertRaises(ValueError):
            core.reserve_saved_payload_record(request, cleanup=lambda: True)
        parent = _Output(core._identity, 7, 23, 65536, 'submission_lookup')
        core._loans[7] = parent
        with self.assertRaises(ValueError):
            core.reserve_saved_payload_record(copy.copy(parent), cleanup=lambda: True)
        self.assertEqual(len(calls), before)
