"""Physical facts stay separate; these tests do not certify Source completion."""
import asyncio
import unittest

from actql_sdk._local_core import LocalCore


class NativeObservationTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._native_observers = {}
        return core

    def test_unknown_attempt_never_acknowledges_any_fact(self):
        core = self.bridge()
        self.assertEqual(core._native_settled(17), 1)
        self.assertEqual(core._native_stopped(17), 1)
        self.assertEqual(core._native_cleaned(17), 1)

    def test_stop_does_not_imply_commit_or_cleanup(self):
        core = self.bridge()
        core._native_observers[17] = (lambda: False, lambda: True, lambda: False)
        self.assertEqual(core._native_settled(17), 1)
        self.assertEqual(core._native_stopped(17), 0)
        self.assertEqual(core._native_cleaned(17), 1)

    def test_commit_does_not_imply_cleanup_or_stop(self):
        core = self.bridge()
        core._native_observers[17] = (lambda: True, lambda: False, lambda: False)
        self.assertEqual(core._native_settled(17), 0)
        self.assertEqual(core._native_stopped(17), 1)
        self.assertEqual(core._native_cleaned(17), 1)

    def test_exceptions_and_truthy_values_keep_same_observer_for_retry(self):
        core = self.bridge()
        attempts = []
        def cleaned():
            attempts.append('cleanup')
            if len(attempts) == 1:
                raise OSError('cleanup pending')
            return True
        observers = (lambda: 1, lambda: 'stopped', cleaned)
        core._native_observers[17] = observers
        self.assertEqual(core._native_settled(17), 1)
        self.assertEqual(core._native_stopped(17), 1)
        self.assertEqual(core._native_cleaned(17), 1)
        self.assertIs(core._native_observers[17], observers)
        self.assertEqual(core._native_cleaned(17), 0)
        self.assertEqual(attempts, ['cleanup', 'cleanup'])

    def test_coroutine_cancellation_is_not_physical_stop(self):
        core = self.bridge()
        def cancelled():
            raise asyncio.CancelledError()
        core._native_observers[17] = (cancelled, cancelled, cancelled)
        self.assertEqual(core._native_settled(17), 1)
        self.assertEqual(core._native_stopped(17), 1)
        self.assertEqual(core._native_cleaned(17), 1)


if __name__ == '__main__':
    unittest.main()
