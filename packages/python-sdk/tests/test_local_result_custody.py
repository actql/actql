"""Result facade custody; checked selection/export is tested by real Core."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Task
from local_abi_declaration_fixture import original_byte_fixture_port


class ResultCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        task = _Task(core._identity, 19)
        core._task_loans = {19: task}
        core._result_loans = {}
        core._loans = {}
        core._inputs = {}
        core._released = set()
        core._next_ticket = 1
        calls = []
        state = {'close': -9, 'produce': 0, 'final': 0}
        wire = '[{"e\u0301/~😀":"line\\r\\n","nullable":null}]'.encode('utf8')

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'result')
            if name == 'reserve':
                self.assertEqual(args, (19, 0))
                return 23
            if name == 'reserve_chunk':
                self.assertEqual(args[:2], (23, 1))
                self.assertGreaterEqual(args[2], 2 * 65_536)
                return 29
            if name == 'progress':
                return (0, 2)[args[1]]
            if name == 'inputs_ready':
                return -7
            if name == 'produce_chunk':
                return state['produce']
            if name == 'chunk_length':
                return len(wire)
            if name == 'chunk_final':
                return state['final']
            if name in ('close', 'close_chunk'):
                return state['close']
            return 0

        core._call = original_byte_fixture_port(call)
        return core, task, calls, state, wire

    def test_explicit_progress_and_repeated_chunk_read_do_not_advance_or_publish(self):
        core, task, calls, _, wire = self.bridge()
        result = core.reserve_result_export(task, 0)
        core.start_result_export(result)
        self.assertFalse(core.feed_result_export(result, 1))
        progress = core.advance_result_export(result, 1)
        self.assertEqual((progress.ready, progress.work), (False, 2))
        self.assertNotIn(('result', 'finish_preparation', (23,)), calls)
        core.finish_result_export_preparation(result)
        chunk = core.reserve_result_chunk(result, cleanup=lambda: False)
        self.assertEqual(core._inputs[1].payload, b'')
        core.produce_result_chunk(chunk)
        first = core.read_result_chunk(chunk)
        self.assertEqual(first, (wire, False))
        byte_reads = sum(family == 'buffer' for family, _, _ in calls)
        second = core.read_result_chunk(chunk)
        self.assertIs(first[0], second[0])
        self.assertEqual(sum(family == 'buffer' for family, _, _ in calls), byte_reads)
        self.assertEqual(sum(name == 'produce_chunk' for _, name, _ in calls), 1)
        self.assertTrue(all(family in ('result', 'buffer') for family, _, _ in calls))

    def test_copies_foreign_selection_and_wrong_output_family_are_rejected_before_io(self):
        core, task, calls, _, _ = self.bridge()
        with self.assertRaises(ValueError):
            core.reserve_result_export(copy.copy(task), 0)
        result = core.reserve_result_export(task, 0)
        chunk = core.reserve_result_chunk(result, cleanup=lambda: True)
        foreign, _, _, _, _ = self.bridge()
        baseline = len(calls)
        for action in (lambda: core.start_result_export(copy.copy(result)),
                       lambda: foreign.close_result_export(result),
                       lambda: core.feed_result_export(result, True),
                       lambda: core.advance_result_export(result, 0),
                       lambda: core.reserve_result_export(task, -1),
                       lambda: core.read_result_chunk(copy.copy(chunk)),
                       lambda: core.read_material(chunk)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_refusal_and_pending_cleanup_keep_exact_chunk_and_parent_for_retry(self):
        core, task, _, state, _ = self.bridge()
        result = core.reserve_result_export(task, 0)
        chunk = core.reserve_result_chunk(result, cleanup=lambda: False)
        state['produce'] = -4
        with self.assertRaises(LocalCoreError):
            core.produce_result_chunk(chunk)
        self.assertIs(core._loans[1], chunk)
        self.assertEqual(core._inputs[1].payload, b'')
        self.assertFalse(core.close_result_chunk(chunk))
        self.assertFalse(core.close_result_export(result))
        self.assertIs(core._result_loans[23], result)
        state['close'] = 0
        core._closing = True
        self.assertTrue(core.close_result_chunk(chunk))
        self.assertTrue(core.close_result_export(result))
        with self.assertRaises(ValueError):
            core.close_result_export(result)

    def test_unknown_final_marker_and_progress_are_never_success(self):
        core, task, _, state, _ = self.bridge()
        result = core.reserve_result_export(task, 0)
        chunk = core.reserve_result_chunk(result, cleanup=lambda: True)
        state['final'] = -33
        with self.assertRaises(LocalCoreError):
            core.read_result_chunk(chunk)
        self.assertIs(core._loans[1], chunk)
        original = core._call
        core._call = original_byte_fixture_port(lambda family, name, *args: -33 if name == 'progress' else original(family, name, *args))
        with self.assertRaises(LocalCoreError):
            core.advance_result_export(result, 1)


if __name__ == '__main__':
    unittest.main()
