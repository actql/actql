"""Physical Result binding loans; semantic binding is owned by the Core."""
import copy
import hashlib
import json
from pathlib import Path
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output
from local_abi_declaration_fixture import original_byte_fixture_port


class ResultBindingCustodyTests(unittest.TestCase):
    def test_independent_payload_and_schema_facts_are_fixed(self):
        root = Path(__file__).resolve().parents[3]
        facts = json.loads((root / 'scripts/fixtures/python-local-result-storage-binding.json').read_text())
        self.assertEqual(facts['payload'], '[{"next":5}]')
        self.assertEqual(facts['byte_count'], len(facts['payload'].encode('utf-8')))
        self.assertEqual(facts['physical_sha256'], hashlib.sha256(facts['payload'].encode('utf-8')).hexdigest())
        self.assertEqual(facts['result_schema_cid'], 'sha256:' + hashlib.sha256(facts['schema'].encode('utf-8')).hexdigest())
        self.assertEqual(facts['row_count'], 1)
        self.assertEqual(facts['result_fields'], ['next'])

    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 9
        parent = _Output(core._identity, 3, 17, 1048576, 'publication')
        observations = _Input(core._identity, 5, 23, 256)
        core._loans = {3: parent, 5: observations}
        calls = []
        state = {'produce': 0, 'close': -9}
        wire = '{"note":"e\u0301/~😀\\r\\n","nullable":null}'.encode()

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return wire[args[1]]
            self.assertEqual(family, 'result_binding')
            if name == 'reserve':
                self.assertEqual(args[:4], (17, 0, 23, 9))
                self.assertGreaterEqual(args[4], 2 * 65536)
                self.assertEqual(core._inputs[9].payload, b'')
                return 29
            if name == 'length':
                return len(wire)
            if name == 'close' and state['close'] == 0:
                core._inputs.pop(9)
            return state[name]

        core._call = original_byte_fixture_port(call)
        return core, parent, observations, calls, state, wire

    def test_original_parent_observations_and_current_configuration_are_forwarded(self):
        core, parent, observations, calls, _, _ = self.bridge()
        value = core.reserve_result_binding(parent, 0, observations, cleanup=lambda: True)
        self.assertEqual((value.family, value.limit), ('result_binding', 65536))
        core.produce_result_binding(value, 31)
        self.assertIn(('result_binding', 'produce', (29, 31)), calls)
        self.assertIs(core._loans[3], parent)
        self.assertIs(core._loans[5], observations)
        self.assertFalse(any(family in ('run', 'task', 'source', 'publication')
                             for family, _, _ in calls))

    def test_exact_core_bytes_are_read_without_semantic_reconstruction(self):
        core, parent, observations, calls, _, wire = self.bridge()
        value = core.reserve_result_binding(parent, 0, observations, cleanup=lambda: True)
        core.produce_result_binding(value, 31)
        self.assertEqual(core.read_result_binding(value), wire)
        before = len(calls)
        self.assertIs(core.read_result_binding(value), core.read_result_binding(value))
        self.assertEqual(len(calls), before)

    def test_foreign_copied_wrong_family_and_invalid_controls_refuse_before_io(self):
        core, parent, observations, calls, _, _ = self.bridge()
        value = core.reserve_result_binding(parent, 0, observations, cleanup=lambda: True)
        foreign, _, _, _, _, _ = self.bridge()
        before = len(calls)
        actions = (
            lambda: core.reserve_result_binding(copy.copy(parent), 0, observations, cleanup=lambda: True),
            lambda: core.reserve_result_binding(parent, 0, copy.copy(observations), cleanup=lambda: True),
            lambda: core.reserve_result_binding(parent, True, observations, cleanup=lambda: True),
            lambda: core.reserve_result_binding(parent, -1, observations, cleanup=lambda: True),
            lambda: core.reserve_result_binding(parent, 2**31, observations, cleanup=lambda: True),
            lambda: core.produce_result_binding(copy.copy(value), 31),
            lambda: core.produce_result_binding(value, True),
            lambda: core.produce_result_binding(value, 0),
            lambda: foreign.read_result_binding(value),
            lambda: core.read_publication(value),
            lambda: core.read_result_binding(parent),
        )
        for action in actions:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_owner_refusal_keeps_original_loan_without_execution_or_retry(self):
        core, parent, observations, calls, state, _ = self.bridge()
        value = core.reserve_result_binding(parent, 0, observations, cleanup=lambda: True)
        state['produce'] = -32
        with self.assertRaises(LocalCoreError):
            core.produce_result_binding(value, 31)
        self.assertIs(core._loans[9], value)
        self.assertIs(core._loans[3], parent)
        self.assertIs(core._loans[5], observations)
        self.assertEqual(len([c for c in calls if c[1] == 'produce']), 1)

    def test_cleanup_retry_retains_same_child_and_parents_while_closing(self):
        core, parent, observations, _, state, _ = self.bridge()
        value = core.reserve_result_binding(parent, 0, observations, cleanup=lambda: False)
        core._closing = True
        self.assertFalse(core.close_result_binding(value))
        self.assertIs(core._loans[9], value)
        self.assertIn(9, core._inputs)
        state['close'] = 0
        self.assertTrue(core.close_result_binding(value))
        self.assertNotIn(9, core._loans)
        self.assertIs(core._loans[3], parent)
        self.assertIs(core._loans[5], observations)
        with self.assertRaises(ValueError):
            core.read_result_binding(value)

    def test_closing_refuses_reservation_and_generation_before_io(self):
        core, parent, observations, calls, _, _ = self.bridge()
        value = core.reserve_result_binding(parent, 0, observations, cleanup=lambda: True)
        core._closing = True
        before = len(calls)
        for action in (
            lambda: core.reserve_result_binding(parent, 0, observations, cleanup=lambda: True),
            lambda: core.produce_result_binding(value, 31),
        ):
            with self.assertRaises(RuntimeError):
                action()
        self.assertEqual(len(calls), before)
