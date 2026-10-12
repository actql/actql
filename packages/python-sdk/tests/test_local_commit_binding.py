"""Mock Core binding/current checks; not physical Wasm or publisher acceptance."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_commit_projection import OriginalCommitProjection
from actql_sdk._local_core import LocalCore, LocalCoreError, _Output


class CommitBindingTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        publication = _Output(core._identity, 7, 23, 1048576, 'publication')
        record = _Output(core._identity, 8, 29, 65536, 'payload_record')
        core._loans = {7: publication, 8: record}
        core._inputs = {}
        calls, state = [], {'code': 0}
        def call(family, name, *args):
            calls.append((family, name, args))
            self.assertEqual((family, name), ('publication_commit_export', 'validate_payload_binding'))
            return state['code']
        core._call = call
        caller = OriginalCommitProjection(core, publication, 31, cleanup=lambda: True)
        return core, publication, record, caller, calls, state

    def test_read_only_validation_forwards_two_original_handles_and_distinct_indexes(self):
        core, publication, record, caller, calls, _ = self.bridge()
        caller.validate_payload_binding(record, 2, 7)
        self.assertEqual(calls, [('publication_commit_export', 'validate_payload_binding', (23, 29, 31, 2, 7))])
        self.assertEqual(caller.pending_outputs, ())
        self.assertIs(core._loans[7], publication)
        self.assertIs(core._loans[8], record)
        self.assertEqual(set(core._loans), {7, 8})
        self.assertEqual(core._inputs, {})

    def test_copied_foreign_wrong_family_handles_refuse_before_io(self):
        core, publication, record, caller, calls, _ = self.bridge()
        foreign, foreign_pub, foreign_record, _, _, _ = self.bridge()
        for action in (
            lambda: caller.validate_payload_binding(copy.copy(record), 0, 0),
            lambda: caller.validate_payload_binding(publication, 0, 0),
            lambda: caller.validate_payload_binding(foreign_record, 0, 0),
            lambda: core.validate_publication_commit_payload_binding(copy.copy(publication), record, 31, 0, 0),
            lambda: core.validate_publication_commit_payload_binding(foreign_pub, record, 31, 0, 0),
            lambda: foreign.validate_publication_commit_payload_binding(publication, record, 31, 0, 0),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(calls, [])

    def test_bool_negative_overflow_indexes_and_configuration_refuse_before_io(self):
        core, publication, record, caller, calls, _ = self.bridge()
        for value in (True, -1, 2**31, 1.5, '0', None):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    caller.validate_payload_binding(record, value, 0)
                with self.assertRaises(ValueError):
                    caller.validate_payload_binding(record, 0, value)
        for configuration in (True, 0, -1, 2**31):
            with self.assertRaises(ValueError):
                core.validate_publication_commit_payload_binding(publication, record, configuration, 0, 0)
        self.assertEqual(calls, [])

    def test_owner_denial_unknown_closed_and_mismatch_keep_same_custody_without_retry(self):
        core, publication, record, caller, calls, state = self.bridge()
        for code in (-2, -3, -5, -32, -33, -35, -36):
            state['code'] = code
            before = len(calls)
            with self.assertRaises(LocalCoreError) as error:
                caller.validate_payload_binding(record, 0, 0)
            self.assertEqual(error.exception.code, code)
            self.assertEqual(len(calls), before + 1)
            self.assertIs(core._loans[7], publication)
            self.assertIs(core._loans[8], record)
            self.assertEqual(caller.pending_outputs, ())

    def test_success_is_revalidated_and_does_not_cache_authority(self):
        core, publication, record, caller, calls, state = self.bridge()
        caller.validate_payload_binding(record, 0, 1)
        state['code'] = -32
        with self.assertRaises(LocalCoreError):
            caller.validate_payload_binding(record, 0, 1)
        self.assertEqual(len(calls), 2)
        self.assertIs(core._loans[7], publication)
        self.assertIs(core._loans[8], record)

    def test_closing_and_outstanding_output_refuse_validation_without_releasing_parents(self):
        core, publication, record, caller, calls, _ = self.bridge()
        output = _Output(core._identity, 9, 43, 1048576, 'publication_commit_export')
        core._loans[9] = output
        caller._outputs.append(output)
        with self.assertRaises(RuntimeError):
            caller.validate_payload_binding(record, 0, 0)
        self.assertEqual(calls, [])
        self.assertEqual(caller.pending_outputs, (output,))
        caller._outputs.clear()
        core._closing = True
        with self.assertRaises(RuntimeError):
            caller.validate_payload_binding(record, 0, 0)
        self.assertEqual(calls, [])
        self.assertIs(core._loans[7], publication)
        self.assertIs(core._loans[8], record)

    def test_success_does_not_implicitly_close_cancel_publish_or_ack(self):
        _, _, record, caller, calls, _ = self.bridge()
        self.assertIsNone(caller.validate_payload_binding(record, 0, 0))
        self.assertEqual([name for _, name, _ in calls], ['validate_payload_binding'])
        self.assertFalse(caller._closing)
        self.assertEqual(caller.pending_outputs, ())

    def test_export_exception_keeps_core_closing_and_original_handles_without_replay(self):
        core, publication, record, caller, _, _ = self.bridge()
        core._closed = False
        core._retired = False
        core._invoking = False
        core._store = object()
        core._nonce = 47
        physical_calls = []
        def fail(*args):
            physical_calls.append(args)
            raise OSError('Original Core invocation acknowledgement lost')
        core._exports = {'actql_publication_commit_export_validate_payload_binding': fail}
        core._call = LocalCore._call.__get__(core)
        with self.assertRaises(OSError):
            caller.validate_payload_binding(record, 0, 0)
        self.assertTrue(core._closing)
        self.assertFalse(core._invoking)
        self.assertIs(core._loans[7], publication)
        self.assertIs(core._loans[8], record)
        self.assertEqual(caller.pending_outputs, ())
        with self.assertRaises(RuntimeError):
            caller.validate_payload_binding(record, 0, 0)
        self.assertEqual(len(physical_calls), 1)
