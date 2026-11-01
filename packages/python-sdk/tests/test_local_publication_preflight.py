"""Physical preflight loans; publication meaning remains in the real Core."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class PublicationPreflightCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        source = _Output(core._identity, 7, 23, 65536, 'source_publication')
        request = _Input(core._identity, 1, 11, 100)
        core._loans = {1: request, 7: source}
        calls = []
        state = {'prepare': 0, 'close': -9}
        wire = '{"request":"e\u0301/~😀\\r\\n","attempt":"exact Core bytes"}'.encode()

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'publication_preflight')
            if name == 'reserve':
                self.assertEqual(args[:3], (23, 11, 8))
                self.assertGreaterEqual(args[3], 2 * 1048576)
                self.assertEqual(core._inputs[8].payload, b'')
                return 29
            if name == 'length':
                return len(wire)
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, source, request, calls, state, wire

    def test_original_source_input_and_current_account_are_forwarded(self):
        core, source, request, calls, _, _ = self.bridge()
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        self.assertEqual((value.family, value.limit), ('publication_preflight', 1048576))
        core.prepare_publication_preflight(value, 31)
        self.assertIn(('publication_preflight', 'prepare', (29, 31)), calls)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)
        self.assertFalse(any(f in ('source', 'task', 'run', 'publication') for f, _, _ in calls))

    def test_output_is_original_bytes_without_intent_reconstruction(self):
        core, source, request, calls, _, wire = self.bridge()
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        core.prepare_publication_preflight(value, 31)
        self.assertEqual(core.read_publication_preflight(value), wire)
        before = len(calls)
        self.assertIs(core.read_publication_preflight(value), core.read_publication_preflight(value))
        self.assertEqual(len(calls), before)

    def test_foreign_copied_wrong_family_and_invalid_controls_refuse_before_io(self):
        core, source, request, calls, _, _ = self.bridge()
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        foreign, _, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: core.reserve_publication_preflight(copy.copy(source), request, cleanup=lambda: True),
            lambda: core.reserve_publication_preflight(source, copy.copy(request), cleanup=lambda: True),
            lambda: core.prepare_publication_preflight(copy.copy(value), 31),
            lambda: core.prepare_publication_preflight(value, True),
            lambda: core.prepare_publication_preflight(value, 0),
            lambda: core.prepare_publication_preflight(value, 2**31),
            lambda: foreign.read_publication_preflight(value),
            lambda: core.read_publication(value),
            lambda: core.close_source_publication(value),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_owner_refusal_retains_original_input_without_activation_or_retry(self):
        core, source, request, calls, state, _ = self.bridge()
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        state['prepare'] = -32
        with self.assertRaises(LocalCoreError):
            core.prepare_publication_preflight(value, 31)
        self.assertIs(core._loans[8], value)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)
        self.assertEqual(len([c for c in calls if c[1] == 'prepare']), 1)

    def test_cleanup_failure_keeps_same_handle_and_parent_while_closing(self):
        core, source, request, _, state, _ = self.bridge()
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: False)
        core._closing = True
        self.assertFalse(core.close_publication_preflight(value))
        self.assertIs(core._loans[8], value)
        self.assertIn(8, core._inputs)
        state['close'] = 0
        self.assertTrue(core.close_publication_preflight(value))
        self.assertNotIn(8, core._loans)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)
        with self.assertRaises(ValueError):
            core.read_publication_preflight(value)

    def test_closing_blocks_new_reservation_and_preparation_before_io(self):
        core, source, request, calls, _, _ = self.bridge()
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        core._closing = True
        before = len(calls)
        for action in (
            lambda: core.reserve_publication_preflight(source, request, cleanup=lambda: True),
            lambda: core.prepare_publication_preflight(value, 31),
        ):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), before)

    def test_output_retirement_keeps_semantic_loan_and_discards_transport_bytes(self):
        core, source, request, calls, state, wire = self.bridge()
        state['retire_output'] = 0
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        core.prepare_publication_preflight(value, 31)
        self.assertEqual(core.read_publication_preflight(value), wire)
        original_call = core._call

        def call(family, name, *args):
            code = original_call(family, name, *args)
            if name == 'retire_output' and code == 0:
                self.assertEqual(core._cleanup(value.ticket), 0)
            return code

        core._call = original_byte_fixture_port(call)
        self.assertTrue(core.retire_publication_preflight_output(value))
        self.assertNotIn(value.ticket, core._inputs)
        self.assertIs(core._loans[value.ticket], value)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)
        with self.assertRaises(RuntimeError):
            core.read_publication_preflight(value)
        core.prepare_publication_preflight(value, 31)
        self.assertFalse(any(f in ('source', 'task', 'run', 'publication')
                             for f, _, _ in calls))
        self.assertTrue(core.retire_publication_preflight_output(value))
        state['close'] = 0
        self.assertTrue(core.close_publication_preflight(value))
        self.assertNotIn(value.ticket, core._loans)
        self.assertNotIn(value.ticket, core._released)

    def test_output_retirement_pending_cleanup_retains_same_loan_for_retry(self):
        core, source, request, _, state, wire = self.bridge()
        ready = [False]
        cleanup_calls = []

        def cleanup():
            cleanup_calls.append(True)
            return ready[0]

        value = core.reserve_publication_preflight(source, request, cleanup=cleanup)
        core.prepare_publication_preflight(value, 31)
        core.read_publication_preflight(value)
        original_call = core._call
        state['retire_output'] = 0
        core._call = original_byte_fixture_port(lambda family, name, *args: (
            core._cleanup(value.ticket) * -9 if name == 'retire_output'
            else original_call(family, name, *args)))
        core._closing = True
        self.assertFalse(core.retire_publication_preflight_output(value))
        self.assertIs(core._loans[value.ticket], value)
        self.assertEqual(core._inputs[value.ticket].payload, wire)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)
        ready[0] = True
        self.assertTrue(core.retire_publication_preflight_output(value))
        self.assertEqual(len(cleanup_calls), 2)
        self.assertTrue(core.retire_publication_preflight_output(value))
        self.assertEqual(len(cleanup_calls), 2)
        self.assertIs(core._loans[value.ticket], value)

    def test_incomplete_retirement_is_a_refusal_not_cleanup_success(self):
        core, source, request, _, state, _ = self.bridge()
        state['retire_output'] = -33
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        with self.assertRaises(LocalCoreError) as caught:
            core.retire_publication_preflight_output(value)
        self.assertEqual(caught.exception.code, -33)
        self.assertIs(core._loans[value.ticket], value)
        self.assertIn(value.ticket, core._inputs)

    def test_copied_foreign_and_wrong_family_retirement_reject_before_io(self):
        core, source, request, calls, _, _ = self.bridge()
        value = core.reserve_publication_preflight(source, request, cleanup=lambda: True)
        foreign, _, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: core.retire_publication_preflight_output(copy.copy(value)),
            lambda: foreign.retire_publication_preflight_output(value),
            lambda: core.retire_publication_preflight_output(source),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)
