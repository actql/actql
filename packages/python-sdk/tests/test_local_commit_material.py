"""Original material transport facade; mocks are not actual Core acceptance."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class CommitMaterialCustodyTests(unittest.TestCase):
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
        # Independent raw bytes, not copied from a product contract or decoder.
        wire = '{"e\u0301/~😀":"e\u0301\\r\\n😀","nullable":null,"n":1}'.encode('utf-8')
        state = {'count': 14, 'produce_material': 0, 'close': -9,
                 'cleanup_ready': False}

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'publication_commit_export')
            if name == 'reserve':
                self.assertEqual(args[:2], (23, 8))
                self.assertGreaterEqual(args[2], 2 * 1048576)
                return 29
            if name == 'length':
                return len(wire)
            if name == 'close' and state['close'] == 0:
                return 0 if core._cleanup(8) == 0 else -9
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, parent, calls, state, wire

    def test_bounded_field_retains_same_original_parent_and_actual_copy_reservation(self):
        core, parent, calls, state, _ = self.bridge()
        previous = core._call
        def call(family, name, *args):
            if (family, name) == ('publication_commit_export', 'reserve_bounded'):
                calls.append((family, name, args))
                self.assertEqual(args[:3], (parent.handle, 8, 71))
                self.assertGreaterEqual(args[3], 142)
                self.assertLess(args[3], 4096)
                return 29
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        output = core.reserve_publication_commit_export(parent, cleanup=lambda: True, maximum=71)
        self.assertEqual(output.limit, 71)
        self.assertIs(core._loans[8], output)
        self.assertIs(core._loans[parent.ticket], parent)
        self.assertFalse(core.close_publication_commit_export(output))
        self.assertIs(core._loans[8], output)
        state['close'], state['cleanup_ready'] = 0, True
        self.assertTrue(core.close_publication_commit_export(output))
        self.assertIs(core._loans[parent.ticket], parent)

    def test_invalid_field_bounds_refuse_before_ticket_or_physical_callback(self):
        core, parent, calls, _, _ = self.bridge()
        for maximum in (True, 0, -1, 1048577, 1.5):
            with self.assertRaises(ValueError):
                core.reserve_publication_commit_export(parent, cleanup=lambda: True, maximum=maximum)
        self.assertEqual(calls, [])
        self.assertEqual(core._next_ticket, 8)
        self.assertEqual(core._inputs, {})

    def test_count_uses_original_parent_and_current_configuration_without_execution(self):
        core, parent, calls, _, _ = self.bridge()
        self.assertEqual(core.publication_commit_material_count(parent, 31), 14)
        self.assertEqual(calls, [('publication_commit_export', 'count', (23, 31))])
        self.assertIs(core._loans[7], parent)

    def test_unknown_refused_and_malformed_count_never_become_empty_success(self):
        core, parent, _, state, _ = self.bridge()
        for count in (-2, -5, -32, 0, 7, True, 2**31):
            state['count'] = count
            with self.assertRaises(LocalCoreError) as issue:
                core.publication_commit_material_count(parent, 31)
            self.assertEqual(issue.exception.code,
                             count if type(count) is int and count < 0 else -33)
            self.assertIs(core._loans[7], parent)

    def test_each_field_forwards_exact_ordinal_and_control_without_reconstruction(self):
        for field, number in [('wire', 0), ('name', 1), ('identity_field', 2), ('identity', 3)]:
            core, parent, calls, _, _ = self.bridge()
            child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
            core.produce_publication_commit_material(child, 31, 13, field=field)
            self.assertIn(('publication_commit_export', 'produce_material', (29, 31, 13, number)), calls)
            self.assertFalse(any(f in ('source', 'task', 'run', 'publication', 'store')
                                 for f, _, _ in calls))

    def test_original_raw_bytes_preserve_unicode_null_absence_and_line_escapes(self):
        core, parent, calls, _, wire = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core.produce_publication_commit_material(child, 31, 8)
        result = core.read_publication_commit_material(child)
        self.assertEqual(result, wire)
        self.assertIn('e\u0301/~😀'.encode(), result)
        self.assertIn(b'"nullable":null', result)
        self.assertNotIn(b'"absent"', result)
        self.assertIn(b'\\r\\n', result)
        before = len(calls)
        self.assertIs(core.read_publication_commit_material(child), result)
        self.assertEqual(len(calls), before)

    def test_invalid_copied_foreign_controls_refuse_before_io(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        foreign, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: core.publication_commit_material_count(copy.copy(parent), 31),
            lambda: core.publication_commit_material_count(child, 31),
            lambda: foreign.publication_commit_material_count(parent, 31),
            lambda: core.publication_commit_material_count(parent, True),
            lambda: core.produce_publication_commit_material(copy.copy(child), 31, 0),
            lambda: core.produce_publication_commit_material(parent, 31, 0),
            lambda: core.produce_publication_commit_material(child, 0, 0),
            lambda: core.produce_publication_commit_material(child, 2**31, 0),
            lambda: core.produce_publication_commit_material(child, 31, True),
            lambda: core.produce_publication_commit_material(child, 31, -1),
            lambda: core.produce_publication_commit_material(child, 31, 2**31),
            lambda: core.produce_publication_commit_material(child, 31, 0, field='unknown'),
            lambda: core.produce_publication_commit_material(child, 31, 0, field=[]),
            lambda: foreign.read_publication_commit_material(child),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_core_refusal_does_not_release_child_retarget_or_retry(self):
        core, parent, calls, state, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        # Core owns original view/current access and immutable projection rules.
        for code in (-32, -33, -5):
            state['produce_material'] = code
            before = len(calls)
            with self.assertRaises(LocalCoreError) as issue:
                core.produce_publication_commit_material(child, 31, 14)
            self.assertEqual(issue.exception.code, code)
            self.assertEqual(len(calls), before + 1)
            self.assertIs(core._loans[8], child)
            self.assertIs(core._loans[7], parent)

    def test_cleanup_failure_keeps_same_child_parent_and_bytes_until_retry(self):
        core, parent, _, state, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: state['cleanup_ready'])
        core.produce_publication_commit_material(child, 31, 0)
        core.read_publication_commit_material(child)
        core._closing = True
        self.assertFalse(core.close_publication_commit_export(child))
        self.assertIs(core._loans[8], child)
        self.assertIn(8, core._inputs)
        state['close'] = 0
        self.assertFalse(core.close_publication_commit_export(child))
        self.assertIs(core._loans[8], child)
        state['cleanup_ready'] = True
        self.assertTrue(core.close_publication_commit_export(child))
        self.assertIs(core._loans[7], parent)
        self.assertNotIn(8, core._inputs)
        with self.assertRaises(ValueError):
            core.read_publication_commit_material(child)

    def test_closing_refuses_count_and_projection_without_cancelling_parent(self):
        core, parent, calls, _, _ = self.bridge()
        child = core.reserve_publication_commit_export(parent, cleanup=lambda: True)
        core._closing = True
        before = len(calls)
        for action in (
            lambda: core.publication_commit_material_count(parent, 31),
            lambda: core.produce_publication_commit_material(child, 31, 0),
        ):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), before)
        self.assertIs(core._loans[7], parent)
