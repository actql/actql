"""Private original allocation write loans; semantic decisions stay in Core."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class PayloadAllocationCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        request = _Output(core._identity, 7, 23, 65536, 'payload_record')
        observation = _Input(core._identity, 1, 11, 300)
        core._loans = {7: request, 1: observation}
        state = {'reserve': 29, 'produce': 0, 'validate': 0, 'begin': 0,
                 'confirm': 0, 'close': -9, 'cleanup_ready': False}
        wire = b'{"allocation_body":"alloc-original-1","expected_revision":null,"namespace":"publication_payload_allocation"}'
        calls = []

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'payload_allocation')
            if name == 'reserve':
                self.assertEqual(args[:3], (23, 1, 8))
                self.assertGreaterEqual(args[3], 2 * 65536)
            if name == 'length':
                return state.get('length', len(wire))
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, request, observation, calls, state, wire

    def test_original_request_current_context_and_physical_input_are_forwarded(self):
        core, request, observation, calls, _, wire = self.bridge()
        record = core.reserve_payload_allocation(request, 1, cleanup=lambda: True)
        core.produce_payload_allocation(record, observation, 31)
        self.assertEqual(core.read_payload_allocation(record, 37), wire)
        core.begin_payload_allocation(record, 41)
        core.confirm_payload_allocation(record, observation, 43)
        self.assertIn(('payload_allocation', 'produce', (29, 11, 31)), calls)
        self.assertIn(('payload_allocation', 'confirm', (29, 11, 43)), calls)
        self.assertFalse(any(f in ('run', 'source', 'task', 'publication') for f, _, _ in calls))

    def test_allocation_requires_original_actual_store_observation(self):
        core, request, observation, calls, _, _ = self.bridge()
        record = core.reserve_payload_allocation(request, 1, cleanup=lambda: True)
        with self.assertRaises(ValueError):
            core.produce_payload_allocation(record, None, 31)
        core.produce_payload_allocation(record, observation, 31)
        self.assertIn(('payload_allocation', 'produce', (29, 11, 31)), calls)

    def test_owned_selection_preserves_the_original_observation(self):
        core, request, observation, calls, _, _ = self.bridge()
        original_call = core._call
        def call(family, name, *args):
            if family == 'payload_allocation' and name == 'reserve':
                calls.append((family, name, args))
                self.assertEqual(args[:3], (23, 2, 8))
                return 29
            return original_call(family, name, *args)
        core._call = original_byte_fixture_port(call)
        record = core.reserve_payload_allocation(request, 2, cleanup=lambda: True)
        core.produce_payload_allocation(record, observation, 31)
        self.assertIn(('payload_allocation', 'produce', (29, 11, 31)), calls)

    def test_invalid_transition_selection_fails_before_ticket_or_io(self):
        core, request, _, calls, _, _ = self.bridge()
        for kind in (True, False, 0, 3, 1.0, '1', None):
            with self.assertRaises(ValueError):
                core.reserve_payload_allocation(request, kind, cleanup=lambda: True)
        self.assertEqual(calls, [])
        self.assertEqual(core._next_ticket, 8)
        self.assertEqual(core._inputs, {})

    def test_cached_bytes_still_recheck_current_authority(self):
        core, request, _, calls, state, wire = self.bridge()
        record = core.reserve_payload_allocation(request, 1, cleanup=lambda: True)
        self.assertEqual(core.read_payload_allocation(record, 31), wire)
        copies = sum(f == 'buffer' for f, _, _ in calls)
        self.assertIs(core.read_payload_allocation(record, 37), core._inputs[8].payload)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copies)
        state['validate'] = -32
        with self.assertRaises(LocalCoreError):
            core.read_payload_allocation(record, 41)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copies)

    def test_repeated_begin_and_bad_observation_are_not_physical_write_permission(self):
        core, request, observation, calls, state, _ = self.bridge()
        record = core.reserve_payload_allocation(request, 1, cleanup=lambda: True)
        core.begin_payload_allocation(record, 31)
        state['begin'] = -33
        with self.assertRaises(LocalCoreError):
            core.begin_payload_allocation(record, 31)
        state['confirm'] = -32
        with self.assertRaises(LocalCoreError):
            core.confirm_payload_allocation(record, observation, 31)
        self.assertIs(core._loans[8], record)
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)

    def test_copies_foreign_family_and_invalid_controls_fail_before_io(self):
        core, request, observation, calls, _, _ = self.bridge()
        record = core.reserve_payload_allocation(request, 1, cleanup=lambda: True)
        before = len(calls)
        for action in (
            lambda: core.reserve_payload_allocation(copy.copy(request), 1, cleanup=lambda: True),
            lambda: core.produce_payload_allocation(copy.copy(record), observation, 31),
            lambda: core.read_payload_allocation(request, 31),
            lambda: core.begin_payload_allocation(record, True),
            lambda: core.produce_payload_allocation(record, copy.copy(observation), 31),
            lambda: core.confirm_payload_allocation(record, copy.copy(observation), 31),
            lambda: core.confirm_payload_allocation(record, observation, 0),
            lambda: core.close_payload_record(record),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_pending_close_keeps_original_handle_and_allocation_for_confirmation(self):
        core, request, observation, _, state, _ = self.bridge()
        record = core.reserve_payload_allocation(request, 1, cleanup=lambda: state['cleanup_ready'])
        core.begin_payload_allocation(record, 31)
        core._closing = True
        self.assertFalse(core.close_payload_allocation(record))
        core.confirm_payload_allocation(record, observation, 31)
        state['close'] = 0
        self.assertFalse(core.close_payload_allocation(record))
        self.assertIs(core._loans[8], record)
        state['cleanup_ready'] = True
        self.assertTrue(core.close_payload_allocation(record))
        self.assertIs(core._loans[7], request)
        self.assertIs(core._loans[1], observation)
        with self.assertRaises(ValueError):
            core.close_payload_allocation(record)

    def test_capacity_refusal_and_closing_never_create_another_record(self):
        core, request, _, calls, state, _ = self.bridge()
        state['reserve'] = -4
        with self.assertRaises(LocalCoreError):
            core.reserve_payload_allocation(request, 1, cleanup=lambda: True)
        self.assertNotIn(8, core._inputs)
        core._closing = True
        before = len(calls)
        with self.assertRaises(RuntimeError):
            core.reserve_payload_allocation(request, 1, cleanup=lambda: True)
        self.assertEqual(len(calls), before)
