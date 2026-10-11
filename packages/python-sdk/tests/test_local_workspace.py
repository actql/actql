"""Physical workspace loans require exact identity and keep pending custody."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError


class WorkspaceCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._next_ticket = 1
        calls = []
        ready = [False, False]
        def call(family, name, *args):
            calls.append((family, name, args))
            if name == 'reserve':
                self.assertEqual((family, args), ('workspace', (1, 128)))
                self.assertEqual(core._inputs[1].payload, b'')
                return 19
            if name == 'close':
                if core._stopped(1, 19) != 0:
                    return -9
                return 0 if core._cleanup(1) == 0 else -9
            raise AssertionError('Unexpected physical ABI invocation')
        core._call = call
        return core, calls, ready

    def test_same_loan_survives_stop_and_cleanup_pending(self):
        core, calls, ready = self.bridge()
        cleanup = []
        loan = core.reserve_workspace(128, stopped=lambda: ready[0],
            cleanup=lambda: cleanup.append('cleanup') or ready[1])
        self.assertFalse(core.close_workspace(loan))
        self.assertEqual(cleanup, [])
        ready[0] = True
        self.assertFalse(core.close_workspace(loan))
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertEqual(core._inputs[loan.ticket].payload, b'')
        ready[1] = True
        core._closing = True
        self.assertTrue(core.close_workspace(loan))
        self.assertEqual(cleanup, ['cleanup', 'cleanup'])
        self.assertEqual(core._loans, {})
        self.assertEqual(core._released, set())
        baseline = len(calls)
        with self.assertRaises(ValueError):
            core.close_workspace(loan)
        self.assertEqual(len(calls), baseline)

    def test_copies_foreign_and_wrong_family_loans_fail_before_io(self):
        core, calls, ready = self.bridge()
        loan = core.reserve_workspace(128, stopped=lambda: ready[0], cleanup=lambda: ready[1])
        foreign, _, _ = self.bridge()
        baseline = len(calls)
        for action in (lambda: core.close_workspace(copy.copy(loan)),
                       lambda: foreign.close_workspace(loan),
                       lambda: core.close_input(loan),
                       lambda: core.read_material(loan),
                       lambda: core.fill_input(loan, 0, 1)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_refusal_does_not_leave_an_unissued_physical_registration(self):
        core, _, _ = self.bridge()
        core._call = lambda *_: -4
        with self.assertRaises(LocalCoreError):
            core.reserve_workspace(128, stopped=lambda: False, cleanup=lambda: False)
        self.assertEqual(core._inputs, {})
        self.assertEqual(core._loans, {})


if __name__ == '__main__':
    unittest.main()
