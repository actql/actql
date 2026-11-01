"""Physical validated-candidate custody, not semantic or durable acceptance."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class CommitExportCustodyTests(unittest.TestCase):
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
        state = {'reserve': 29, 'produce': 0, 'close': -9, 'cleanup_ready': False}
        wire = '{"index_entry":"e\u0301/~😀\\r\\n","request":"original","attempt":"original"}'.encode()

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'publication_commit_export')
            if name == 'reserve':
                self.assertEqual(args[:2], (23, 8))
                self.assertGreaterEqual(args[2], 2 * 1048576)
                self.assertEqual(core._inputs[8].payload, b'')
            if name == 'length':
                return len(wire)
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, parent, calls, state, wire

    def test_original_parent_and_current_configuration_are_forwarded(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        self.assertEqual(child.family, 'publication_commit_export')
        core.produce_publication_commit_export(child, 31)
        self.assertIn(('publication_commit_export', 'produce', (29, 31)), calls)
        self.assertIs(core._loans[7], parent)
        self.assertFalse(any(f in ('source', 'task', 'run', 'publication', 'store')
                             for f, _, _ in calls))

    def test_exact_core_bytes_are_cached_without_index_or_identity_reconstruction(self):
        core, parent, calls, _, wire = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core.produce_publication_commit_export(child, 31)
        self.assertEqual(core.read_publication_commit_export(child), wire)
        before = len(calls)
        self.assertIs(core.read_publication_commit_export(child),
                      core.read_publication_commit_export(child))
        self.assertEqual(len(calls), before)

    def test_foreign_copied_wrong_family_and_invalid_configuration_refuse_before_io(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        foreign, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: core.reserve_publication_commit_export(copy.copy(parent), cleanup=lambda: True),
            lambda: core.produce_publication_commit_export(copy.copy(child), 31),
            lambda: core.produce_publication_commit_export(parent, 31),
            lambda: core.produce_publication_commit_export(child, True),
            lambda: core.produce_publication_commit_export(child, 0),
            lambda: core.produce_publication_commit_export(child, 2**31),
            lambda: foreign.read_publication_commit_export(child),
            lambda: core.read_publication(child),
            lambda: core.close_result_binding(child),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_unfinished_or_refused_owner_does_not_become_empty_or_durable_success(self):
        core, parent, calls, state, _ = self.bridge()
        state['reserve'] = -2
        with self.assertRaises(LocalCoreError):
            core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        self.assertNotIn(8, core._inputs)
        self.assertEqual(core._loans, {7: parent})
        core, parent, calls, state, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        state['produce'] = -32
        with self.assertRaises(LocalCoreError):
            core.produce_publication_commit_export(child, 31)
        self.assertIs(core._loans[8], child)
        self.assertEqual(sum(name == 'produce' for _, name, _ in calls), 1)

    def test_failed_cleanup_keeps_same_child_and_original_parent_for_explicit_retry(self):
        core, parent, _, state, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: state['cleanup_ready'])
        core._closing = True
        self.assertFalse(core.close_publication_commit_export(child))
        self.assertIs(core._loans[8], child)
        self.assertIn(8, core._inputs)
        state['close'] = 0
        # Even a ready Owner mock cannot release failed physical cleanup.
        self.assertFalse(core.close_publication_commit_export(child))
        self.assertIs(core._loans[8], child)
        state['cleanup_ready'] = True
        self.assertTrue(core.close_publication_commit_export(child))
        self.assertIs(core._loans[7], parent)
        self.assertNotIn(8, core._inputs)
        with self.assertRaises(ValueError):
            core.read_publication_commit_export(child)

    def test_closing_refuses_new_export_and_production_without_cancelling_parent(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core._closing = True
        before = len(calls)
        for action in (
            lambda: core.reserve_publication_commit_export(parent, cleanup=lambda: True),
            lambda: core.produce_publication_commit_export(child, 31),
        ):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), before)
        self.assertIs(core._loans[7], parent)
