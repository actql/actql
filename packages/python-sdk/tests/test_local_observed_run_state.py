"""Nominal scalar transport only; no actual Wasm, Run status or Store ACK."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, _Input, _Output,
    LOCAL_CORE_ABI, _PUBLICATION_COMMIT_EXPORT_SIGNATURES,
)


class ObservedRunStateTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        source = _Input(core._identity, 3, 17, 47)
        output = _Output(core._identity, 4, 19, 1048576, 'publication_commit_export')
        core._loans = {3: source, 4: output}
        calls = []
        status = [0]
        def call(family, name, *args):
            calls.append((family, name, args))
            return status[0]
        core._call = call
        return core, source, output, calls, status

    def test_closed_signature_and_original_handles_are_forwarded(self):
        core, source, output, calls, _ = self.bridge()
        self.assertEqual(LOCAL_CORE_ABI, 70)
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['produce_run_state'],
                         ('i64 i32 i32 i32', 'i32'))
        self.assertIsNone(core.produce_publication_observed_run_state(output, source, 23))
        self.assertEqual(calls, [('publication_commit_export', 'produce_run_state', (19, 17, 23))])
        self.assertIs(core._loans[3], source)
        self.assertIs(core._loans[4], output)

    def test_copies_foreign_loans_and_invalid_current_refuse_before_abi(self):
        core, source, output, calls, _ = self.bridge()
        for candidate, input_value, current in (
            (copy.copy(output), source, 23), (output, copy.copy(source), 23),
            (output, _Input(object(), 3, 17, 47), 23),
            (output, source, True), (output, source, 0), (output, source, 2**31),
        ):
            with self.assertRaises(ValueError):
                core.produce_publication_observed_run_state(candidate, input_value, current)
        self.assertEqual(calls, [])

    def test_owner_denial_unknown_unfinished_and_cleanup_failures_keep_same_loans(self):
        for code in (-35, -36, -32, -33, -9, -30):
            core, source, output, calls, status = self.bridge()
            status[0] = code
            with self.assertRaises(LocalCoreError) as error:
                core.produce_publication_observed_run_state(output, source, 23)
            self.assertEqual(error.exception.code, code)
            self.assertIs(core._loans[3], source)
            self.assertIs(core._loans[4], output)
            self.assertEqual(len(calls), 1)

    def test_boolean_status_and_closing_never_become_an_observation(self):
        core, source, output, calls, status = self.bridge()
        # Exercise the shared scalar validator rather than replacing it with
        # the transport double used for exact-handle assertions above.
        del core._call
        core._closed = core._retired = core._invoking = False
        core._store = None
        core._nonce = 1
        core._exports = {'actql_publication_commit_export_produce_run_state':
                         lambda *_: status[0]}
        for value in (True, False, None, 0.0):
            status[0] = value
            with self.assertRaisesRegex(RuntimeError, 'Invalid Local Core scalar response'):
                core.produce_publication_observed_run_state(output, source, 23)
        baseline = len(calls)
        core._closing = True
        with self.assertRaises(RuntimeError):
            core.produce_publication_observed_run_state(output, source, 23)
        self.assertEqual(len(calls), baseline)
