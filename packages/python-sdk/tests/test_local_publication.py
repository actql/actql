"""Physical publication custody; semantic proofs come from the real Core gate."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class PublicationCustodyTests(unittest.TestCase):
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
        state = {'close': -9, 'advance': 0, 'progress': (0, 1, 3)}
        wire = b'{"captured_run":"exact Core wire e\xcc\x81/~\xf0\x9f\x98\x80"}'

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'publication')
            if name == 'reserve':
                self.assertEqual(args[:3], (23, 11, 8))
                self.assertGreaterEqual(args[3], 2 * 1048576)
                self.assertEqual(core._inputs[8].payload, b'')
                return 29
            if name in ('close', 'advance', 'advance_commit'):
                return state['advance' if name == 'advance_commit' else name]
            if name in ('progress', 'commit_progress'):
                return state['progress'][args[1]]
            if name == 'length':
                return len(wire)
            return 0

        core._call = original_byte_fixture_port(call)
        return core, source, request, calls, state, wire

    def test_original_configuration_and_quantum_are_forwarded_without_execution(self):
        core, source, request, calls, state, wire = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        core.prepare_publication(value, 31)
        progress = core.advance_publication(value, 37, 1)
        self.assertEqual((progress.ready, progress.work), (False, 1))
        self.assertIn(('publication', 'advance', (29, 37, 1)), calls)
        self.assertEqual(core.publication_work(value), 3)
        self.assertFalse(any(name == 'finish' for _, name, _ in calls))
        state['progress'] = (1, 1, 4)
        self.assertTrue(core.advance_publication(value, 37, 1).ready)
        core.finish_publication(value, 41)
        self.assertIn(('publication', 'finish', (29, 41)), calls)
        self.assertEqual(core.read_publication(value), wire)
        baseline = len(calls)
        self.assertIs(core.read_publication(value), core.read_publication(value))
        self.assertEqual(len(calls), baseline)
        self.assertTrue(all(family in ('publication', 'buffer') for family, _, _ in calls))

    def test_transport_retirement_keeps_original_semantic_loan_and_parent(self):
        core, source, request, calls, state, wire = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        self.assertEqual(core.read_publication(value), wire)
        original_call = core._call

        def call(family, name, *args):
            code = original_call(family, name, *args)
            if name == 'retire_output' and code == 0:
                self.assertEqual(core._cleanup(value.ticket), 0)
            return code

        core._call = original_byte_fixture_port(call)
        self.assertTrue(core.retire_publication_output(value))
        self.assertNotIn(value.ticket, core._inputs)
        self.assertIs(core._loans[value.ticket], value)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)
        with self.assertRaises(RuntimeError):
            core.read_publication(value)
        core.finish_publication(value, 31)
        self.assertTrue(core.retire_publication_output(value))
        state['close'] = 0
        self.assertTrue(core.close_publication(value))
        self.assertNotIn(value.ticket, core._loans)
        self.assertFalse(any(f in ('source', 'task', 'run') for f, _, _ in calls))

    def test_transport_retirement_failure_retains_exact_output_for_retry(self):
        core, source, request, calls, state, wire = self.bridge()
        ready = [False]
        cleanup_calls = []

        def cleanup():
            cleanup_calls.append(True)
            return ready[0]

        value = core.reserve_publication(source, request, cleanup=cleanup)
        core.read_publication(value)
        original_call = core._call
        core._call = original_byte_fixture_port(lambda family, name, *args: (
            core._cleanup(value.ticket) * -9 if name == 'retire_output'
            else original_call(family, name, *args)))
        core._closing = True
        self.assertFalse(core.retire_publication_output(value))
        self.assertIs(core._loans[value.ticket], value)
        self.assertEqual(core._inputs[value.ticket].payload, wire)
        ready[0] = True
        self.assertTrue(core.retire_publication_output(value))
        self.assertTrue(core.retire_publication_output(value))
        self.assertEqual(len(cleanup_calls), 2)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)

    def test_incomplete_transport_retirement_is_not_success(self):
        core, source, request, calls, state, wire = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        core._call = original_byte_fixture_port(lambda family, name, *args: -33)
        with self.assertRaises(LocalCoreError) as caught:
            core.retire_publication_output(value)
        self.assertEqual(caught.exception.code, -33)
        self.assertIs(core._loans[value.ticket], value)
        self.assertIn(value.ticket, core._inputs)

    def test_transport_retirement_refuses_copied_foreign_and_wrong_family_before_io(self):
        core, source, request, calls, state, wire = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        foreign, *_ = self.bridge()
        before = len(calls)
        for action in (
                lambda: core.retire_publication_output(copy.copy(value)),
                lambda: foreign.retire_publication_output(value),
                lambda: core.retire_publication_output(source)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_copied_foreign_wrong_kind_and_invalid_controls_fail_before_io(self):
        core, source, request, calls, _, _ = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        foreign, _, _, _, _, _ = self.bridge()
        baseline = len(calls)
        for action in (
                lambda: core.reserve_publication(copy.copy(source), request, cleanup=lambda: True),
                lambda: core.reserve_publication(source, copy.copy(request), cleanup=lambda: True),
                lambda: core.prepare_publication(copy.copy(value), 31),
                lambda: foreign.read_publication(value),
                lambda: core.read_material(value),
                lambda: core.read_publication(source),
                lambda: core.advance_publication(value, True, 1),
                lambda: core.advance_publication(value, 31, True),
                lambda: core.advance_publication(value, 31, 0),
                lambda: core.finish_publication(value, 2**31)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_failed_cleanup_preserves_original_loan_and_allows_close_while_closing(self):
        core, source, request, _, state, _ = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: False)
        core.prepare_publication(value, 31)
        core._closing = True
        self.assertFalse(core.close_publication(value))
        self.assertIs(core._loans[8], value)
        self.assertIn(8, core._inputs)
        state['close'] = 0
        self.assertTrue(core.close_publication(value))
        self.assertNotIn(8, core._loans)
        self.assertIs(core._loans[7], source)
        self.assertIs(core._loans[1], request)
        with self.assertRaises(ValueError):
            core.read_publication(value)

    def test_budget_refusal_retains_same_handle_and_previous_work(self):
        core, source, request, _, state, _ = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        core.prepare_publication(value, 31)
        state['advance'] = -32
        with self.assertRaises(LocalCoreError):
            core.advance_publication(value, 31, 1)
        self.assertIs(core._loans[8], value)
        self.assertEqual(core.publication_work(value), 3)
        self.assertEqual(core._inputs[8].payload, b'')

    def test_invalid_progress_never_becomes_completion(self):
        for progress in ((2, 1, 3), (1, 2, 3), (1, -1, 3)):
            core, source, request, _, state, _ = self.bridge()
            value = core.reserve_publication(source, request, cleanup=lambda: True)
            state['progress'] = progress
            with self.assertRaises(LocalCoreError):
                core.advance_publication(value, 31, 1)
            self.assertIs(core._loans[8], value)

    def test_closing_refuses_new_projection_and_production_before_io(self):
        core, source, request, calls, _, _ = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        core._closing = True
        baseline = len(calls)
        for action in (
                lambda: core.reserve_publication(source, request, cleanup=lambda: True),
                lambda: core.prepare_publication(value, 31),
                lambda: core.advance_publication(value, 31, 1),
                lambda: core.finish_publication(value, 31)):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_commit_validation_retains_original_handle_and_forwards_current_authority(self):
        core, source, request, calls, state, _ = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        core.prepare_publication_commit(value, request, 31)
        self.assertIn(('publication', 'prepare_commit', (29, 11, 31)), calls)
        progress = core.advance_publication_commit(value, 37, 1)
        self.assertEqual((progress.ready, progress.work), (False, 1))
        self.assertNotIn(('publication', 'finish_commit', (29, 37)), calls)
        state['progress'] = (1, 1, 4)
        self.assertTrue(core.advance_publication_commit(value, 41, 1).ready)
        core.finish_publication_commit(value, 43)
        self.assertIn(('publication', 'finish_commit', (29, 43)), calls)
        self.assertIs(core._loans[8], value)
        self.assertIs(core._loans[1], request)
        self.assertTrue(all(family == 'publication' for family, _, _ in calls))

    def test_commit_copied_inputs_and_invalid_controls_refuse_before_io(self):
        core, source, request, calls, _, _ = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        baseline = len(calls)
        for action in (
                lambda: core.prepare_publication_commit(value, copy.copy(request), 31),
                lambda: core.prepare_publication_commit(copy.copy(value), request, 31),
                lambda: core.prepare_publication_commit(value, request, True),
                lambda: core.advance_publication_commit(value, 31, 0),
                lambda: core.advance_publication_commit(value, 31, True),
                lambda: core.finish_publication_commit(source, 31)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        core._closing = True
        for action in (
                lambda: core.prepare_publication_commit(value, request, 31),
                lambda: core.advance_publication_commit(value, 31, 1),
                lambda: core.finish_publication_commit(value, 31)):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_commit_refusal_and_malformed_progress_never_become_durable_success(self):
        core, source, request, _, state, _ = self.bridge()
        value = core.reserve_publication(source, request, cleanup=lambda: True)
        state['advance'] = -32
        with self.assertRaises(LocalCoreError):
            core.advance_publication_commit(value, 31, 1)
        state['advance'] = 0
        for progress in ((2, 1, 3), (1, 2, 3), (1, -1, 3)):
            state['progress'] = progress
            with self.assertRaises(LocalCoreError):
                core.advance_publication_commit(value, 31, 1)
        self.assertIs(core._loans[8], value)
        self.assertIs(core._loans[1], request)
        state['close'] = -9
        self.assertFalse(core.close_publication(value))
        self.assertIs(core._loans[8], value)


if __name__ == '__main__':
    unittest.main()
