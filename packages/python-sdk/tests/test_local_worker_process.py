"""Spawn/wait syscall doubles; no actual child, Engine or stop settlement."""
import copy
import fcntl
import os
from pathlib import Path
import unittest
from unittest.mock import patch

from actql_sdk._local_worker_process import OriginalWorkerProcess, LocalWorkerProcessPending
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
import test_local_worker_slot as slot_fixture


class WorkerProcessTests(unittest.TestCase):
    def setUp(self):
        self.case = slot_fixture.WorkerSlotTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.funding, self.slot = self.case.funding, self.case.slot
        self.slot.open(); self.slot.try_acquire()
        self.case.fcntl_fcntl.side_effect = iter(range(11, 17))
        for name, options in [('_read_file', {}), ('os.pipe', {'side_effect': [(3, 4), (3, 4), (3, 4)]}),
                ('os.posix_spawn', {'return_value': 4321}), ('os.waitpid', {'return_value': (0, 0)})]:
            wrapper = patch('actql_sdk._local_worker_process.' + name, **options)
            value = wrapper.start(); self.addCleanup(wrapper.stop)
            setattr(self, name.replace('.', '_'), value)
        self.options = {'executable': Path('/installed/bin/python'), 'executable_bytes': 8192,
            'executable_sha256': 'a' * 64, 'environment': (('LANG', 'C.UTF-8'),)}
        self.process = OriginalWorkerProcess(self.funding, self.slot, **self.options)

    def assert_no_execution_ack(self):
        self.assertFalse(any(call[0] in ('settle', 'stop_scope', 'report', 'close')
            for call in self.case.case.supplier.calls))

    def test_missing_funding_or_selection_refuses_before_io(self):
        with self.assertRaises(LocalWorkerFundingUnavailable):
            OriginalWorkerProcess(None, self.slot, **self.options)
        for change in ({'environment': None}, {'environment': (('PATH', '/usr/bin'),)},
                {'environment': (('LANG', 'C'), ('LANG', 'C'))}, {'executable': Path('python')},
                {'executable_bytes': True}, {'executable_sha256': 'bad'}):
            with self.assertRaises(ValueError):
                OriginalWorkerProcess(self.funding, self.slot, **(self.options | change))
        self._read_file.assert_not_called(); self.os_pipe.assert_not_called(); self.os_posix_spawn.assert_not_called()

    def test_slot_is_consumed_once_by_same_original_funding(self):
        with self.assertRaises(ValueError): OriginalWorkerProcess(self.funding, self.slot, **self.options)
        self.os_posix_spawn.assert_not_called()

    def test_selected_executable_and_environment_are_exact_without_inheritance(self):
        with patch.dict(os.environ, {'SECRET': 'not-inherited', 'PATH': '/foreign'}, clear=True):
            self.process.spawn()
        self._read_file.assert_called_once_with(Path('/installed/bin/python'), maximum=8192,
            expected=8192, digest='a' * 64)
        args, options = self.os_posix_spawn.call_args
        self.assertEqual(args, ('/installed/bin/python',
            ('/installed/bin/python', '-I', '-m', 'actql_sdk._local_worker_entry'), {'LANG': 'C.UTF-8'}))
        self.assertEqual(options['setpgroup'], 0)
        self.assert_no_execution_ack()

    def test_stdio_lift_precedes_fd3_inheritance_and_closes_only_high_originals(self):
        self.process.spawn()
        actions = self.os_posix_spawn.call_args.kwargs['file_actions']
        self.assertEqual(actions[:4], [(os.POSIX_SPAWN_DUP2, 10, 3),
            (os.POSIX_SPAWN_DUP2, 11, 0), (os.POSIX_SPAWN_DUP2, 14, 1), (os.POSIX_SPAWN_DUP2, 16, 2)])
        self.assertEqual(actions[4:], [(os.POSIX_SPAWN_CLOSE, fd) for fd in range(11, 17)]
            + [(os.POSIX_SPAWN_CLOSE, 10)])
        self.assertTrue(all(call.args[1:] == (fcntl.F_DUPFD_CLOEXEC, 10)
            for call in self.case.fcntl_fcntl.call_args_list))

    def test_current_refusal_precedes_selected_executable_and_spawn(self):
        self.case.case.supplier.deny_launch = True
        with self.assertRaises(ValueError): self.process.spawn()
        self._read_file.assert_not_called(); self.os_pipe.assert_not_called(); self.os_posix_spawn.assert_not_called()

    def test_reentrant_cleanup_during_current_check_blocks_spawn(self):
        self.case.case.supplier.require_launch_originals = lambda *args: self.process.close_parent_descriptors()
        with self.assertRaises(ValueError): self.process.spawn()
        self._read_file.assert_not_called(); self.os_posix_spawn.assert_not_called()

    def test_reentrant_cleanup_at_final_current_check_preserves_registered_pipes(self):
        original = self.case.case.supplier.require_launch_originals
        def current(*args):
            original(*args)
            if self.process._stdin is not None: self.process.close_parent_descriptors()
        self.case.case.supplier.require_launch_originals = current
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        self.os_posix_spawn.assert_not_called()
        self.assertTrue(all(fd.closed for fd in self.process._descriptors))

    def test_dup_failure_keeps_both_original_pipe_ends_for_cleanup(self):
        self.case.fcntl_fcntl.side_effect = OSError('Dup failed')
        with self.assertRaises(LocalWorkerProcessPending) as caught: self.process.spawn()
        self.assertIs(caught.exception.cleanup_process, self.process)
        self.assertEqual([fd.value for fd in self.process._descriptors], [3, 4])
        self.process.close_parent_descriptors()
        self.assertTrue(all(fd.closed for fd in self.process._descriptors))
        self.os_posix_spawn.assert_not_called()

    def test_spawn_failure_never_retries_or_adopts_a_new_child(self):
        self.os_posix_spawn.side_effect = OSError('Spawn outcome unavailable')
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        with self.assertRaises(RuntimeError): self.process.spawn()
        self.os_posix_spawn.assert_called_once()
        self.process.close_parent_descriptors(); self.assert_no_execution_ack()

    def test_parent_close_failure_keeps_actual_child_and_retires_other_ends_once(self):
        def close(fd):
            if fd == 11: raise OSError('Original parent close unknown')
        self.case.os_close.side_effect = close
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        self.assertEqual(self.process._pid, 4321)
        for _ in range(2):
            with self.assertRaises(LocalWorkerProcessPending): self.process.close_parent_descriptors()
        self.assertEqual(sum(call.args == (11,) for call in self.case.os_close.call_args_list), 1)
        self.assertTrue(all(fd.closed for fd in self.process._descriptors if fd.value != 11))
        self.assertTrue(self.slot._closed); self.assertFalse(self.process._parent_closed)
        self.assert_no_execution_ack()

    def test_cleanup_before_spawn_blocks_launch_and_does_not_cancel(self):
        self.process.close_parent_descriptors(); self.process.close_parent_descriptors()
        with self.assertRaises(ValueError): self.process.spawn()
        self.os_posix_spawn.assert_not_called(); self.assert_no_execution_ack()

    def test_live_direct_child_has_no_exit_or_scoped_stop(self):
        self.process.spawn(); self.assertIsNone(self.process.observe_child_exit())
        self.os_waitpid.assert_called_once_with(4321, os.WNOHANG)
        self.assert_no_execution_ack()

    def test_direct_child_exit_is_original_cached_observation_only(self):
        self.process.spawn(); self.os_waitpid.return_value = (4321, 7 << 8)
        result = self.process.observe_child_exit()
        self.assertIs(self.process.observe_child_exit(), result)
        self.assertIs(result.owner, self.process); self.assertEqual(result.status, 7 << 8)
        self.os_waitpid.assert_called_once(); self.assert_no_execution_ack()
        with self.assertRaises(TypeError): copy.copy(result)

    def test_signalled_direct_child_does_not_generate_cleanup_or_run_ack(self):
        self.process.spawn(); self.os_waitpid.return_value = (4321, 6)
        self.assertEqual(self.process.observe_child_exit().status, 6)
        self.assert_no_execution_ack()

    def test_foreign_or_lost_wait_stays_unknown_without_second_wait(self):
        self.process.spawn(); self.os_waitpid.return_value = (9999, 0)
        for _ in range(2):
            with self.assertRaises(LocalWorkerProcessPending): self.process.observe_child_exit()
        self.os_waitpid.assert_called_once(); self.assertIsNone(self.process._exit)
        self.assert_no_execution_ack()

    def test_copied_process_cannot_use_original_physical_identity(self):
        with self.assertRaises(TypeError): copy.copy(self.process)
        with self.assertRaises(TypeError): copy.deepcopy(self.process)
        clone = OriginalWorkerProcess.__new__(OriginalWorkerProcess); clone.__dict__.update(self.process.__dict__)
        with self.assertRaises(ValueError): clone.spawn()
        self.os_posix_spawn.assert_not_called()

    def test_external_reaper_failure_is_sticky_unknown_without_signal_or_settlement(self):
        self.process.spawn(); self.os_waitpid.side_effect = ChildProcessError('Original child was reaped elsewhere')
        for _ in range(2):
            with self.assertRaises(LocalWorkerProcessPending): self.process.observe_child_exit()
        self.os_waitpid.assert_called_once(); self.assert_no_execution_ack()

    def test_malformed_spawn_identity_never_reaches_wait_or_a_second_spawn(self):
        self.os_posix_spawn.return_value = True
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        with self.assertRaises(LocalWorkerProcessPending): self.process.observe_child_exit()
        with self.assertRaises(RuntimeError): self.process.spawn()
        self.os_waitpid.assert_not_called(); self.os_posix_spawn.assert_called_once()
