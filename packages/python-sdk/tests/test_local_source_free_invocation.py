"""Physical facade loans only; invocation and publication facts come from Core."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, _Compute, _Input, _Output, _RUN_INVOCATION_SIGNATURES,
)
from local_abi_declaration_fixture import original_byte_fixture_port


class SourceFreeInvocationCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        compute = _Compute(core._identity, 19)
        source = _Input(core._identity, 1, 23, 2)
        core._compute_loans = {19: compute}
        core._loans = {1: source}
        core._inputs = {}
        core._released = set()
        core._next_ticket = 2
        calls = []
        state = {'close_source_free': -9, 'prepare_source_free': 0}
        wire = b'{"observation":"original Core bytes","invocation":"original Core bytes"}'

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            if family in ('publication_preflight', 'publication'):
                self.assertEqual(name, 'reserve')
                self.assertEqual(args[:2], (29, 23))
                return 31 if family == 'publication_preflight' else 37
            self.assertEqual(family, 'run_invocation')
            if name == 'reserve_source_free':
                self.assertEqual(args[:3], (19, 23, 2))
                self.assertGreaterEqual(args[3], 2 * 65536)
                return 29
            if name == 'length_source_free':
                return len(wire)
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, compute, source, calls, state, wire

    def test_exact_closed_export_signatures(self):
        self.assertEqual(_RUN_INVOCATION_SIGNATURES, {
            'reserve_source_free': ('i64 i32 i32 i32 i64', 'i32'),
            'prepare_source_free': ('i64 i32 i32', 'i32'),
            'length_source_free': ('i64 i32', 'i32'),
            'close_source_free': ('i64 i32', 'i32'),
        })

    def test_original_compute_input_current_and_bytes_without_source_evidence(self):
        core, compute, source, calls, _, wire = self.bridge()
        value = core.reserve_source_free_invocation(compute, source, cleanup=lambda: False)
        core.prepare_source_free_invocation(value, 41)
        self.assertIn(('run_invocation', 'prepare_source_free', (29, 41)), calls)
        self.assertEqual(core.read_source_free_invocation(value), wire)
        self.assertIs(core._loans[1], source)
        self.assertIs(core._compute_loans[19], compute)
        self.assertTrue(all(f in ('run_invocation', 'buffer') for f, _, _ in calls))

    def test_both_existing_children_borrow_the_same_nominal_invocation(self):
        core, compute, source, _, _, _ = self.bridge()
        value = core.reserve_source_free_invocation(compute, source, cleanup=lambda: True)
        preflight = core.reserve_publication_preflight(value, source, cleanup=lambda: True)
        publication = core.reserve_publication(value, source, cleanup=lambda: True)
        self.assertEqual((preflight.handle, publication.handle), (31, 37))
        self.assertIs(core._loans[2], value)
        self.assertIs(core._loans[1], source)

    def test_copied_foreign_wrong_family_and_invalid_current_refuse_before_io(self):
        core, compute, source, calls, _, _ = self.bridge()
        value = core.reserve_source_free_invocation(compute, source, cleanup=lambda: True)
        foreign, _, _, _, _, _ = self.bridge()
        wrong = _Output(core._identity, 3, 30, 65536, 'material')
        core._loans[3] = wrong
        baseline = len(calls)
        for action in (
            lambda: core.reserve_source_free_invocation(copy.copy(compute), source, cleanup=lambda: True),
            lambda: core.reserve_source_free_invocation(compute, copy.copy(source), cleanup=lambda: True),
            lambda: core.prepare_source_free_invocation(copy.copy(value), 41),
            lambda: core.prepare_source_free_invocation(value, True),
            lambda: core.prepare_source_free_invocation(value, 0),
            lambda: core.prepare_source_free_invocation(value, 2**31),
            lambda: foreign.read_source_free_invocation(value),
            lambda: core.read_source_publication(value),
            lambda: core.close_source_publication(value),
            lambda: core.reserve_publication_preflight(copy.copy(value), source, cleanup=lambda: True),
            lambda: core.reserve_publication(wrong, source, cleanup=lambda: True),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_owner_refusal_retains_parents_without_retry_or_activation(self):
        core, compute, source, calls, state, _ = self.bridge()
        value = core.reserve_source_free_invocation(compute, source, cleanup=lambda: True)
        state['prepare_source_free'] = -32
        with self.assertRaises(LocalCoreError):
            core.prepare_source_free_invocation(value, 41)
        self.assertEqual(len([c for c in calls if c[1] == 'prepare_source_free']), 1)
        self.assertIs(core._loans[2], value)
        self.assertIs(core._loans[1], source)
        self.assertIs(core._compute_loans[19], compute)

    def test_close_failure_keeps_handle_and_blocks_new_work_until_same_handle_retry(self):
        core, compute, source, calls, state, _ = self.bridge()
        value = core.reserve_source_free_invocation(compute, source, cleanup=lambda: False)
        core._closing = True
        self.assertFalse(core.close_source_free_invocation(value))
        self.assertIs(core._loans[2], value)
        self.assertIn(2, core._inputs)
        baseline = len(calls)
        for action in (
            lambda: core.reserve_source_free_invocation(compute, source, cleanup=lambda: True),
            lambda: core.prepare_source_free_invocation(value, 41),
        ):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), baseline)
        state['close_source_free'] = 0
        self.assertTrue(core.close_source_free_invocation(value))
        self.assertNotIn(2, core._loans)
        self.assertIs(core._loans[1], source)
        self.assertIs(core._compute_loans[19], compute)
        with self.assertRaises(ValueError):
            core.read_source_free_invocation(value)


if __name__ == '__main__':
    unittest.main()
