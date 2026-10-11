"""Opaque Compute configuration identity; Core alone admits captured inputs."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _NativeAttempt


class ComputeCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        input = _Input(core._identity, 1, 13, 128)
        attempt = _NativeAttempt(core._identity, 17)
        core._loans = {1: input}
        core._native_loans = {17: attempt}
        core._compute_loans = {}
        calls = []
        pending = [True]
        def call(family, name, *args):
            calls.append((family, name, args))
            self.assertEqual(family, 'compute')
            if name == 'reserve':
                self.assertEqual(args, (17, 13))
                return 19
            if name in ('configure', 'configured'):
                return 0
            if name == 'close':
                return -9 if pending[0] else 0
            raise AssertionError('Unexpected Core invocation')
        core._call = call
        return core, input, attempt, calls, pending

    def test_exact_configuration_survives_pending_retirement(self):
        core, input, attempt, calls, pending = self.bridge()
        compute = core.reserve_native_compute(attempt, input)
        core.configure_native_compute(compute)
        self.assertFalse(core.close_native_compute(compute))
        self.assertIs(core._compute_loans[19], compute)
        self.assertIs(core._native_loans[17], attempt)
        self.assertIs(core._loans[1], input)
        pending[0] = False
        core._closing = True
        self.assertTrue(core.close_native_compute(compute))
        baseline = len(calls)
        with self.assertRaises(ValueError):
            core.configure_native_compute(compute)
        self.assertEqual(len(calls), baseline)

    def test_copied_inputs_attempts_and_compute_fail_before_io(self):
        core, input, attempt, calls, _ = self.bridge()
        for source, config in ((copy.copy(attempt), input), (attempt, copy.copy(input))):
            with self.assertRaises(ValueError):
                core.reserve_native_compute(source, config)
        self.assertEqual(calls, [])
        compute = core.reserve_native_compute(attempt, input)
        foreign, _, _, _, _ = self.bridge()
        baseline = len(calls)
        for action in (lambda: core.configure_native_compute(copy.copy(compute)),
                       lambda: foreign.close_native_compute(compute)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_refused_configuration_keeps_original_handle_for_cleanup(self):
        core, input, attempt, _, _ = self.bridge()
        compute = core.reserve_native_compute(attempt, input)
        original = core._call
        def call(family, name, *args):
            if name == 'configured':
                return -32
            return original(family, name, *args)
        core._call = call
        with self.assertRaises(LocalCoreError):
            core.configure_native_compute(compute)
        self.assertIs(core._compute_loans[19], compute)
        self.assertFalse(core.close_native_compute(compute))


if __name__ == '__main__':
    unittest.main()
