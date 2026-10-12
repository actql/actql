"""Original snapshot loan forwarding; mocked scalar Core is not Wasm acceptance."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _Output


class PayloadSnapshotTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        record = _Output(core._identity, 7, 23, 65536, 'payload_record')
        observation = _Input(core._identity, 8, 29, 300)
        core._loans = {7: record, 8: observation}
        calls, state = [], {'code': 0}
        def call(family, name, *args):
            calls.append((family, name, args))
            return state['code']
        core._call = call
        return core, record, observation, calls, state

    def test_readonly_check_forwards_original_record_input_and_current_configuration(self):
        core, record, observation, calls, _ = self.bridge()
        core.validate_payload_snapshot(record, observation, 31)
        self.assertEqual(calls, [('payload_record', 'validate_snapshot', (23, 29, 31))])
        self.assertIs(core._loans[7], record)
        self.assertIs(core._loans[8], observation)

    def test_copied_foreign_and_wrong_family_loans_refuse_before_io(self):
        core, record, observation, calls, _ = self.bridge()
        _, foreign_record, foreign_input, _, _ = self.bridge()
        for original, facts in ((copy.copy(record), observation), (foreign_record, observation), (observation, observation), (record, copy.copy(observation)), (record, foreign_input), (record, record)):
            with self.assertRaises(ValueError):
                core.validate_payload_snapshot(original, facts, 31)
        self.assertEqual(calls, [])

    def test_closed_and_invalid_configuration_refuse_without_cleanup(self):
        core, record, observation, calls, _ = self.bridge()
        for config in (True, 0, -1, 2**31, '31', None):
            with self.assertRaises(ValueError):
                core.validate_payload_snapshot(record, observation, config)
        core._closing = True
        with self.assertRaises(RuntimeError):
            core.validate_payload_snapshot(record, observation, 31)
        self.assertEqual(calls, [])
        self.assertIs(core._loans[8], observation)

    def test_owner_malformed_denied_unknown_and_closed_codes_keep_both_loans(self):
        core, record, observation, calls, state = self.bridge()
        for code in (-2, -5, -31, -32, -33, -35, -36):
            state['code'] = code
            before = len(calls)
            with self.assertRaises(LocalCoreError) as error:
                core.validate_payload_snapshot(record, observation, 31)
            self.assertEqual(error.exception.code, code)
            self.assertEqual(len(calls), before + 1)
            self.assertIs(core._loans[7], record)
            self.assertIs(core._loans[8], observation)

    def test_success_is_not_a_cached_permission_or_commit_ack(self):
        core, record, observation, calls, state = self.bridge()
        core.validate_payload_snapshot(record, observation, 31)
        state['code'] = -32
        with self.assertRaises(LocalCoreError):
            core.validate_payload_snapshot(record, observation, 31)
        self.assertEqual(calls, [('payload_record', 'validate_snapshot', (23, 29, 31))] * 2)
        self.assertEqual(set(core._loans), {7, 8})
