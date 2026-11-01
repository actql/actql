"""Bounded physical replay loans; Core owns Result identity and completion."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class PayloadChunkCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        request = _Output(core._identity, 7, 23, 65536, 'payload_request')
        core._loans = {7: request}
        state = {'reserve': 29, 'produce': 0, 'validate': 0,
                 'final': 1, 'close': -9, 'cleanup_ready': False}
        wire = '[{"n":null,"text":"é\\r\\n/~😀"}]'.encode('utf-8')
        calls = []

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'payload_request':
                self.assertEqual(name, 'start_replay')
                return 0
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'payload_chunk')
            if name == 'reserve':
                self.assertEqual(args[:2], (23, 8))
                self.assertGreaterEqual(args[2], 2 * 65536)
                self.assertEqual(core._inputs[8].payload, b'')
            if name == 'length':
                return state.get('length', len(wire))
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, request, calls, state, wire

    def test_same_original_request_and_current_configuration_are_forwarded(self):
        core, request, calls, state, wire = self.bridge()
        core.start_payload_replay(request, 31)
        chunk = core.reserve_payload_chunk(request, cleanup=lambda: True)
        core.produce_payload_chunk(chunk, 37)
        core.produce_payload_chunk(chunk, 37)
        self.assertEqual(core.read_payload_chunk(chunk, 41), (wire, True))
        self.assertIn(('payload_request', 'start_replay', (23, 31)), calls)
        self.assertEqual(sum(name == 'produce' for _, name, _ in calls), 2)
        self.assertIn(('payload_chunk', 'validate', (29, 41)), calls)
        self.assertIs(core._loans[7], request)
        self.assertFalse(any(f in ('source', 'task', 'run', 'publication', 'store')
                             for f, _, _ in calls))

    def test_cached_bytes_revalidate_current_custody_without_another_copy(self):
        core, request, calls, state, wire = self.bridge()
        chunk = core.reserve_payload_chunk(request, cleanup=lambda: True)
        first, _ = core.read_payload_chunk(chunk, 31)
        copied = sum(f == 'buffer' for f, _, _ in calls)
        second, _ = core.read_payload_chunk(chunk, 37)
        self.assertIs(first, second)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copied)
        state['validate'] = -32
        with self.assertRaises(LocalCoreError) as caught:
            core.read_payload_chunk(chunk, 41)
        self.assertEqual(caught.exception.code, -32)
        self.assertEqual(sum(f == 'buffer' for f, _, _ in calls), copied)
        self.assertIs(core._loans[8], chunk)

    def test_invalid_final_marker_and_refusal_do_not_become_eof_or_empty_success(self):
        core, request, calls, state, wire = self.bridge()
        chunk = core.reserve_payload_chunk(request, cleanup=lambda: True)
        state['produce'] = -32
        with self.assertRaises(LocalCoreError):
            core.produce_payload_chunk(chunk, 31)
        self.assertIs(core._loans[8], chunk)
        state['final'] = -33
        with self.assertRaises(LocalCoreError) as caught:
            core.read_payload_chunk(chunk, 31)
        self.assertEqual(caught.exception.code, -33)
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)

    def test_nonfinal_chunk_and_oversized_projection_preserve_bounded_custody(self):
        core, request, calls, state, wire = self.bridge()
        chunk = core.reserve_payload_chunk(request, cleanup=lambda: True)
        state['length'] = 65537
        with self.assertRaises(LocalCoreError) as caught:
            core.read_payload_chunk(chunk, 31)
        self.assertEqual(caught.exception.code, 65537)
        self.assertFalse(any(f == 'buffer' for f, _, _ in calls))
        self.assertIs(core._loans[8], chunk)
        self.assertEqual(core._inputs[8].payload, b'')
        state['length'] = len(wire)
        state['final'] = 0
        self.assertEqual(core.read_payload_chunk(chunk, 37), (wire, False))

    def test_cleanup_failure_retains_same_chunk_and_parent_until_explicit_retry(self):
        core, request, calls, state, wire = self.bridge()
        chunk = core.reserve_payload_chunk(request,
                                           cleanup=lambda: state['cleanup_ready'])
        core.read_payload_chunk(chunk, 31)
        core._closing = True
        self.assertFalse(core.close_payload_chunk(chunk))
        state['close'] = 0
        self.assertFalse(core.close_payload_chunk(chunk))
        self.assertIs(core._loans[8], chunk)
        self.assertEqual(core._inputs[8].payload, wire)
        state['cleanup_ready'] = True
        self.assertTrue(core.close_payload_chunk(chunk))
        self.assertNotIn(8, core._inputs)
        self.assertNotIn(8, core._loans)
        self.assertIs(core._loans[7], request)
        with self.assertRaises(ValueError):
            core.close_payload_chunk(chunk)

    def test_foreign_copied_wrong_family_and_invalid_controls_refuse_before_io(self):
        core, request, calls, state, wire = self.bridge()
        chunk = core.reserve_payload_chunk(request, cleanup=lambda: True)
        foreign, *_ = self.bridge()
        before = len(calls)
        actions = [lambda: core.start_payload_replay(copy.copy(request), 31),
                   lambda: core.reserve_payload_chunk(copy.copy(request), cleanup=lambda: True),
                   lambda: core.produce_payload_chunk(copy.copy(chunk), 31),
                   lambda: core.read_payload_chunk(request, 31),
                   lambda: foreign.read_payload_chunk(chunk, 31),
                   lambda: core.close_payload_chunk(copy.copy(chunk))]
        for control in (True, 0, -1, 2**31):
            actions.extend([lambda control=control: core.start_payload_replay(request, control),
                            lambda control=control: core.produce_payload_chunk(chunk, control),
                            lambda control=control: core.read_payload_chunk(chunk, control)])
        for action in actions:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_capacity_refusal_and_closing_never_advance_original_request(self):
        core, request, calls, state, wire = self.bridge()
        state['reserve'] = -4
        with self.assertRaises(LocalCoreError):
            core.reserve_payload_chunk(request, cleanup=lambda: True)
        self.assertNotIn(8, core._inputs)
        self.assertEqual(core._loans, {7: request})
        core._closing = True
        before = len(calls)
        for action in (lambda: core.start_payload_replay(request, 31),
                       lambda: core.reserve_payload_chunk(request, cleanup=lambda: True)):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), before)
