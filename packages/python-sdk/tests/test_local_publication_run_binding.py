"""Private scalar Run routing, not actual Wasm, permission or Store ACK."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output, _PUBLICATION_SIGNATURES


class PublicationRunBindingTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity, core._lock, core._closing = object(), RLock(), False
        output = _Output(core._identity, 3, 17, 1048576, 'publication')
        core._loans = {3: output}
        calls, code = [], [0]
        def call(family, name, *args):
            calls.append((family, name, args))
            return code[0]
        core._call = call
        return core, output, calls, code

    def test_closed_signature_forwards_original_run_without_authority_fields(self):
        core, output, calls, _ = self.bridge()
        self.assertEqual(_PUBLICATION_SIGNATURES['validate_run'], ('i64 i32 i32 i32', 'i32'))
        self.assertIsNone(core.validate_publication_run(output, 23, 31))
        self.assertEqual(calls, [('publication', 'validate_run', (17, 23, 31))])
        self.assertIs(core._loans[3], output)

    def test_foreign_loan_and_invalid_run_or_configuration_refuse_before_io(self):
        core, output, calls, _ = self.bridge()
        for value, run, current in ((copy.copy(output), 23, 31), (output, True, 31),
                                    (output, 0, 31), (output, 2**31, 31),
                                    (output, 23, True), (output, 23, 0)):
            with self.assertRaises(ValueError):
                core.validate_publication_run(value, run, current)
        self.assertEqual(calls, [])

    def test_current_foreign_or_unfinished_owner_rejection_keeps_original_loan(self):
        core, output, calls, code = self.bridge()
        for error in (-2, -32, -35, -41):
            code[0] = error
            with self.assertRaises(LocalCoreError) as failed:
                core.validate_publication_run(output, 23, 31)
            self.assertEqual(failed.exception.code, error)
            self.assertIs(core._loans[3], output)
        self.assertEqual(len(calls), 4)
