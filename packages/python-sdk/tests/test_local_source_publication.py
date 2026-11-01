"""Source projection facade custody; actual evidence is issued by real Core."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Compute, _Input
from local_abi_declaration_fixture import original_byte_fixture_port


class SourcePublicationCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        compute = _Compute(core._identity, 19)
        source = _Input(core._identity, 1, 23, 10)
        core._compute_loans = {19: compute}
        core._loans = {1: source}
        core._inputs = {}
        core._released = set()
        core._next_ticket = 2
        calls = []
        state = {'close': -9, 'advance': 0, 'finish': 0, 'progress': (0, 1, 3)}
        wire = b'{"logical":"exact Core wire","evidence":"exact Core wire"}'

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'source_publication')
            if name == 'reserve':
                self.assertEqual(args[:3], (19, 23, 2))
                self.assertGreaterEqual(args[3], 2 * 65536)
                return 29
            if name in ('close', 'advance', 'finish'):
                return state[name]
            if name == 'progress':
                return state['progress'][args[1]]
            if name == 'length':
                return len(wire)
            return 0

        core._call = original_byte_fixture_port(call)
        return core, compute, source, calls, state, wire

    def test_quantum_and_current_configuration_are_explicit_without_execution(self):
        core, compute, source, calls, state, wire = self.bridge()
        value = core.reserve_source_publication(compute, source, cleanup=lambda: False)
        core.prepare_source_publication(value, 31)
        progress = core.advance_source_publication(value, 1)
        self.assertEqual((progress.ready, progress.work), (False, 1))
        self.assertEqual(core.source_publication_work(value), 3)
        self.assertFalse(any(name == 'finish' for _, name, _ in calls))
        state['progress'] = (1, 1, 4)
        self.assertTrue(core.advance_source_publication(value, 1).ready)
        core.finish_source_publication(value, 37)
        self.assertIn(('source_publication', 'finish', (29, 37)), calls)
        self.assertEqual(core.read_source_publication(value), wire)
        baseline = len(calls)
        self.assertEqual(core.read_source_publication(value), wire)
        self.assertEqual(len(calls), baseline)
        self.assertTrue(all(family in ('source_publication', 'buffer')
                            for family, _, _ in calls))

    def test_copy_foreign_kind_and_invalid_quantum_are_rejected_before_io(self):
        core, compute, source, calls, _, _ = self.bridge()
        value = core.reserve_source_publication(compute, source, cleanup=lambda: True)
        foreign, _, _, _, _, _ = self.bridge()
        baseline = len(calls)
        for action in (lambda: core.reserve_source_publication(copy.copy(compute), source, cleanup=lambda: True),
                       lambda: core.prepare_source_publication(copy.copy(value), 31),
                       lambda: foreign.read_source_publication(value),
                       lambda: core.read_material(value),
                       lambda: core.advance_source_publication(value, True),
                       lambda: core.advance_source_publication(value, 0),
                       lambda: core.finish_source_publication(value, True)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_budget_refusal_and_cleanup_pending_preserve_same_handle(self):
        core, compute, source, _, state, _ = self.bridge()
        value = core.reserve_source_publication(compute, source, cleanup=lambda: False)
        core.prepare_source_publication(value, 31)
        state['advance'] = -32
        with self.assertRaises(LocalCoreError):
            core.advance_source_publication(value, 1)
        self.assertIs(core._loans[2], value)
        self.assertEqual(core.source_publication_work(value), 3)
        core._closing = True
        self.assertFalse(core.close_source_publication(value))
        self.assertIs(core._loans[2], value)
        state['close'] = 0
        self.assertTrue(core.close_source_publication(value))
        self.assertNotIn(2, core._loans)
        with self.assertRaises(ValueError):
            core.read_source_publication(value)


if __name__ == '__main__':
    unittest.main()
