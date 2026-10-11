"""Task facade keeps existing Core decisions; it evaluates no Program rows."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Compute


class TaskCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        compute = _Compute(core._identity, 17)
        core._compute_loans = {17: compute}
        core._task_loans = {}
        calls = []
        pending = [True]
        def call(family, name, *args):
            calls.append((family, name, args))
            self.assertEqual(family, 'task')
            if name == 'reserve':
                self.assertEqual(args, (17, 13))
                return 19
            if name == 'close':
                return -9 if pending[0] else 0
            if name == 'inputs_ready':
                return -7 if pending[0] else 0
            if name == 'progress':
                return [0, 1, 6, 8][args[1]]
            return 0
        core._call = call
        return core, compute, calls, pending

    def test_explicit_quantum_and_owner_progress_are_not_task_or_run_success(self):
        core, compute, calls, pending = self.bridge()
        task = core.reserve_task(compute, 13)
        core.start_task(task)
        self.assertFalse(core.feed_task(task, 1))
        pending[0] = False
        self.assertTrue(core.feed_task(task, 2))
        progress = core.advance_task(task, 3)
        self.assertEqual((progress.complete, progress.waiting, progress.progress, progress.work),
                         (False, True, 6, 8))
        self.assertIn(('task', 'advance', (19, 3)), calls)
        self.assertNotIn(('task', 'complete', (19,)), calls)
        core.prepare_task_finalization(task)
        core.advance_task(task, 4, finalization=True)
        core.complete_task(task)
        self.assertIn(('task', 'advance_finalization', (19, 4)), calls)

    def test_foreign_copied_and_invalid_quantum_fail_before_io(self):
        core, compute, calls, _ = self.bridge()
        with self.assertRaises(ValueError):
            core.reserve_task(copy.copy(compute), 13)
        task = core.reserve_task(compute, 13)
        foreign, _, _, _ = self.bridge()
        baseline = len(calls)
        for action in (lambda: core.start_task(copy.copy(task)),
                       lambda: foreign.close_task(task),
                       lambda: core.feed_task(task, True),
                       lambda: core.advance_task(task, 0),
                       lambda: core.advance_task(task, 2**31)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_pending_close_keeps_original_task_and_parent_for_retry(self):
        core, compute, _, pending = self.bridge()
        task = core.reserve_task(compute, 13)
        self.assertFalse(core.close_task(task))
        self.assertIs(core._task_loans[19], task)
        self.assertIs(core._compute_loans[17], compute)
        pending[0] = False
        core._closing = True
        self.assertTrue(core.close_task(task))
        with self.assertRaises(ValueError):
            core.close_task(task)

    def test_failed_owner_progress_does_not_become_partial_success(self):
        core, compute, _, _ = self.bridge()
        task = core.reserve_task(compute, 13)
        original = core._call
        def call(family, name, *args):
            if name == 'progress':
                return -33
            return original(family, name, *args)
        core._call = call
        with self.assertRaises(LocalCoreError):
            core.advance_task(task, 1)
        self.assertIs(core._task_loans[19], task)


if __name__ == '__main__':
    unittest.main()
