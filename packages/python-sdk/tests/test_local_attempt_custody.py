"""Issued Native handle identity; physical facts do not decide Run outcomes."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input


class NativeAttemptCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        core._native_loans = {}
        core._native_observers = {}
        input = _Input(core._identity, 1, 13, 7)
        core._loans = {1: input}
        calls = []
        facts = [False, False, False]
        def call(family, name, *args):
            calls.append((family, name, args))
            if name == 'reserve_attempt':
                self.assertEqual((family, args), ('source', (11, 12, 13)))
                return 17
            if name in ('start', 'started'):
                self.assertIn(17, core._native_observers)
                return 0
            if name == 'completed':
                return -33
            if name == 'close_attempt':
                return -9 if core._native_stopped(17) or core._native_cleaned(17) else 0
            if name == 'close_event':
                return -9
            if name == 'accept':
                return 0
            raise AssertionError('Unexpected physical ABI invocation')
        core._call = call
        def reserve():
            return core.reserve_native_attempt(11, 12, input,
                settled=lambda: facts[0], stopped=lambda: facts[1], cleaned=lambda: facts[2])
        return core, input, calls, facts, reserve

    def test_callbacks_bind_before_start_and_live_until_core_retirement(self):
        core, input, calls, facts, reserve = self.bridge()
        loan = reserve()
        self.assertEqual(len(calls), 1)
        core.start_native_attempt(loan)
        self.assertFalse(core.native_source_completed(loan))
        observers = core._native_observers[loan.handle]
        facts[1] = True
        self.assertFalse(core.close_native_attempt(loan))
        self.assertIs(core._native_loans[loan.handle], loan)
        self.assertIs(core._native_observers[loan.handle], observers)
        facts[2] = True
        self.assertTrue(core.close_native_attempt(loan))
        self.assertNotIn(loan.handle, core._native_observers)
        self.assertIs(core._loans[input.ticket], input)
        with self.assertRaises(ValueError):
            core.start_native_attempt(loan)

    def test_copied_foreign_and_invalid_event_inputs_fail_before_io(self):
        core, input, calls, _, reserve = self.bridge()
        loan = reserve()
        foreign, _, _, _, _ = self.bridge()
        baseline = len(calls)
        for action in (lambda: core.start_native_attempt(copy.copy(loan)),
                       lambda: foreign.close_native_attempt(loan),
                       lambda: core.accept_native_event(loan, 4, copy.copy(input)),
                       lambda: core.accept_native_event(loan, True, input),
                       lambda: core.accept_native_event(loan, 7, input)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        core.accept_native_event(loan, 4, input)
        self.assertEqual(calls[-1], ('source', 'accept', (17, 4, 13)))
        self.assertFalse(core.close_native_event(loan))
        self.assertIs(core._native_loans[17], loan)

    def test_failed_completion_and_trapped_start_keep_same_attempt_without_retry(self):
        core, _, calls, _, reserve = self.bridge()
        loan = reserve()
        baseline = len(calls)
        attempts = []
        def trapped(*args):
            attempts.append(args)
            raise RuntimeError('Independent interrupted Core call')
        core._call = trapped
        with self.assertRaises(RuntimeError):
            core.start_native_attempt(loan)
        self.assertEqual(len(attempts), 1)
        self.assertIs(core._native_loans[17], loan)
        self.assertIn(17, core._native_observers)
        self.assertEqual(len(calls), baseline)
        core._call = lambda *_: -32
        with self.assertRaises(LocalCoreError):
            core.native_source_completed(loan)
        self.assertIs(core._native_loans[17], loan)

    def test_invalid_reservation_does_not_issue_a_handle(self):
        core, input, calls, _, _ = self.bridge()
        for config, start, cleaned in ((True, 12, lambda: True),
                                       (11, 0, lambda: True), (11, 12, False)):
            with self.assertRaises(ValueError):
                core.reserve_native_attempt(config, start, input,
                    settled=lambda: False, stopped=lambda: False, cleaned=cleaned)
        self.assertEqual(calls, [])
        self.assertEqual(core._native_loans, {})


if __name__ == '__main__':
    unittest.main()
