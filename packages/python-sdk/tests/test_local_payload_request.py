"""Physical request loan custody; Core determines Result and payload identity."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class PayloadRequestCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        parent = _Output(core._identity, 7, 23, 1048576, 'publication')
        request = _Input(core._identity, 1, 11, 300)
        core._loans = {7: parent, 1: request}
        calls = []
        state = {'reserve': 29, 'produce': 0, 'close': -9, 'cleanup_ready': False}
        wire = '{"original":"e\u0301/~😀\\r\\n","max_bytes":"11","row_count":"1"}'.encode()

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'payload_request')
            if name == 'reserve':
                self.assertEqual(args[:4], (23, 0, 11, 8))
                self.assertGreaterEqual(args[4], 2 * 65536)
                self.assertEqual(core._inputs[8].payload, b'')
            if name == 'length':
                return len(wire)
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, parent, request, calls, state, wire

    def test_original_parent_input_index_and_current_configuration_are_forwarded(self):
        core, parent, request, calls, _, _ = self.bridge()
        child = core.reserve_payload_request(parent, 0, request, cleanup=lambda: True)
        self.assertEqual(child.family, 'payload_request')
        core.produce_payload_request(child, 31)
        self.assertIn(('payload_request', 'produce', (29, 31)), calls)
        self.assertIs(core._loans[7], parent)
        self.assertIs(core._loans[1], request)
        self.assertFalse(any(f in ('source', 'task', 'run', 'publication', 'store')
                             for f, _, _ in calls))

    def test_exact_core_wire_is_cached_without_payload_identity_reconstruction(self):
        core, parent, request, calls, _, wire = self.bridge()
        child = core.reserve_payload_request(parent, 0, request, cleanup=lambda: True)
        core.produce_payload_request(child, 31)
        self.assertEqual(core.read_payload_request(child), wire)
        before = len(calls)
        self.assertIs(core.read_payload_request(child), core.read_payload_request(child))
        self.assertEqual(len(calls), before)

    def test_foreign_copied_wrong_family_and_invalid_controls_refuse_before_io(self):
        core, parent, request, calls, _, _ = self.bridge()
        child = core.reserve_payload_request(parent, 0, request, cleanup=lambda: True)
        foreign, _, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: core.reserve_payload_request(copy.copy(parent), 0, request, cleanup=lambda: True),
            lambda: core.reserve_payload_request(parent, 0, copy.copy(request), cleanup=lambda: True),
            lambda: core.reserve_payload_request(parent, True, request, cleanup=lambda: True),
            lambda: core.reserve_payload_request(parent, -1, request, cleanup=lambda: True),
            lambda: core.reserve_payload_request(parent, 2**31, request, cleanup=lambda: True),
            lambda: core.produce_payload_request(copy.copy(child), 31),
            lambda: core.produce_payload_request(parent, 31),
            lambda: core.produce_payload_request(child, True),
            lambda: core.produce_payload_request(child, 0),
            lambda: core.produce_payload_request(child, 2**31),
            lambda: foreign.read_payload_request(child),
            lambda: core.read_publication(child),
            lambda: core.close_result_binding(child),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_owner_refusal_does_not_become_empty_or_durable_success(self):
        core, parent, request, _, state, _ = self.bridge()
        state['reserve'] = -2
        with self.assertRaises(LocalCoreError):
            core.reserve_payload_request(parent, 0, request, cleanup=lambda: True)
        self.assertNotIn(8, core._inputs)
        self.assertEqual(core._loans, {7: parent, 1: request})
        core, parent, request, calls, state, _ = self.bridge()
        child = core.reserve_payload_request(parent, 0, request, cleanup=lambda: True)
        state['produce'] = -32
        with self.assertRaises(LocalCoreError):
            core.produce_payload_request(child, 31)
        self.assertIs(core._loans[8], child)
        self.assertEqual(sum(name == 'produce' for _, name, _ in calls), 1)

    def test_failed_cleanup_retains_same_child_parent_and_input_for_explicit_retry(self):
        core, parent, request, _, state, _ = self.bridge()
        child = core.reserve_payload_request(parent, 0, request,
                                             cleanup=lambda: state['cleanup_ready'])
        core._closing = True
        self.assertFalse(core.close_payload_request(child))
        self.assertIs(core._loans[8], child)
        self.assertIn(8, core._inputs)
        state['close'] = 0
        self.assertFalse(core.close_payload_request(child))
        self.assertIs(core._loans[8], child)
        state['cleanup_ready'] = True
        self.assertTrue(core.close_payload_request(child))
        self.assertIs(core._loans[7], parent)
        self.assertIs(core._loans[1], request)
        self.assertNotIn(8, core._inputs)
        with self.assertRaises(ValueError):
            core.read_payload_request(child)

    def test_closing_refuses_new_request_and_production_without_cancelling_parent(self):
        core, parent, request, calls, _, _ = self.bridge()
        child = core.reserve_payload_request(parent, 0, request, cleanup=lambda: True)
        core._closing = True
        before = len(calls)
        for action in (
            lambda: core.reserve_payload_request(parent, 0, request, cleanup=lambda: True),
            lambda: core.produce_payload_request(child, 31),
        ):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), before)
        self.assertIs(core._loans[7], parent)
        self.assertIs(core._loans[1], request)
