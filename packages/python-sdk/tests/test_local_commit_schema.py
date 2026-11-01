"""Original receipt schema transport facade; mocks do not prove actual Core access."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class CommitSchemaTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        parent = _Output(core._identity, 7, 23, 1048576, 'publication')
        core._loans = {7: parent}
        calls = []
        key = b'0123456789abcdef' * 4
        state = {'produce_schema': 0, 'close': -9, 'cleanup_ready': False}

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return key[args[1]]
            self.assertEqual(family, 'publication_commit_export')
            if name == 'reserve':
                self.assertEqual(args[:2], (23, 8))
                self.assertGreaterEqual(args[2], 2 * 1048576)
                return 29
            if name == 'length':
                return len(key)
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, parent, calls, state, key

    def test_forwards_original_child_and_current_configuration_without_store_io(self):
        core, parent, calls, _, key = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core.produce_publication_commit_schema(child, 31, 0, field='identity')
        self.assertEqual(calls[-1], ('publication_commit_export', 'produce_schema', (29, 31, 0, 0)))
        self.assertEqual(core.read_publication_commit_material(child), key)
        self.assertFalse(any(f in ('source', 'task', 'run', 'publication', 'store')
                             for f, _, _ in calls))
        self.assertIs(core._loans[7], parent)

    def test_copy_foreign_wrong_family_and_invalid_controls_refuse_before_io(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        foreign, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: core.produce_publication_commit_schema(copy.copy(child), 31, 0, field='identity'),
            lambda: core.produce_publication_commit_schema(parent, 31, 0, field='identity'),
            lambda: foreign.produce_publication_commit_schema(child, 31, 0, field='identity'),
            lambda: core.produce_publication_commit_schema(child, True, 0, field='identity'),
            lambda: core.produce_publication_commit_schema(child, 0, 0, field='identity'),
            lambda: core.produce_publication_commit_schema(child, 2**31, 0, field='identity'),
            lambda: core.produce_publication_commit_schema(child, 31, True, field='identity'),
            lambda: core.produce_publication_commit_schema(child, 31, -1, field='wire'),
            lambda: core.produce_publication_commit_schema(child, 31, 0, field='name'),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_core_refusal_retains_original_loans_without_automatic_retry(self):
        core, parent, calls, state, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        for code in (-2, -5, -32, -33):
            state['produce_schema'] = code
            before = len(calls)
            with self.assertRaises(LocalCoreError) as issue:
                core.produce_publication_commit_schema(child, 31, 0, field='identity')
            self.assertEqual(issue.exception.code, code)
            self.assertEqual(len(calls), before + 1)
            self.assertIs(core._loans[8], child)
            self.assertIs(core._loans[7], parent)

    def test_reuse_still_calls_core_for_current_authority(self):
        core, parent, calls, state, key = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core.produce_publication_commit_schema(child, 31, 0, field='identity')
        self.assertEqual(core.read_publication_commit_material(child), key)
        before = len(calls)
        state['produce_schema'] = -32
        with self.assertRaises(LocalCoreError):
            core.produce_publication_commit_schema(child, 32, 0, field='identity')
        self.assertEqual(calls[before:], [('publication_commit_export', 'produce_schema', (29, 32, 0, 0))])
        self.assertIs(core._loans[8], child)

    def test_failed_cleanup_keeps_same_handle_until_success(self):
        core, parent, _, state, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: state['cleanup_ready'])
        core.produce_publication_commit_schema(child, 31, 0, field='identity')
        core.read_publication_commit_material(child)
        self.assertFalse(core.close_publication_commit_export(child))
        self.assertIs(core._loans[8], child)
        self.assertIn(8, core._inputs)
        state['close'] = 0
        self.assertFalse(core.close_publication_commit_export(child))
        state['cleanup_ready'] = True
        self.assertTrue(core.close_publication_commit_export(child))
        self.assertIs(core._loans[7], parent)
        self.assertNotIn(8, core._inputs)
        with self.assertRaises(ValueError):
            core.read_publication_commit_material(child)

    def test_closing_refuses_projection_before_io_without_cancelling_run(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core._closing = True
        before = len(calls)
        with self.assertRaises(RuntimeError):
            core.produce_publication_commit_schema(child, 31, 0, field='identity')
        self.assertEqual(len(calls), before)
        self.assertIs(core._loans[7], parent)

    def test_raw_wire_field_uses_same_original_result_and_explicit_field(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core.produce_publication_commit_schema(child, 31, 2, field='wire')
        self.assertEqual(calls[-1], ('publication_commit_export', 'produce_schema', (29, 31, 2, 1)))
