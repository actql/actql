"""Spawn/wait syscall doubles; no actual child, Engine or stop settlement."""
import copy
import fcntl
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from actql_sdk._local_worker_process import OriginalWorkerProcess, LocalWorkerProcessPending
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
import test_local_worker_slot as slot_fixture

_VERIFY_EXECUTABLE = OriginalWorkerProcess._verify_executable


class WorkerProcessTests(unittest.TestCase):
    def setUp(self):
        self.case = slot_fixture.WorkerSlotTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.funding, self.slot = self.case.funding, self.case.slot
        self.slot.open(); self.slot.try_acquire()
        self.case.fcntl_fcntl.side_effect = iter(range(11, 17))
        for name, options in [('OriginalWorkerProcess._verify_executable', {}), ('os.pipe', {'side_effect': [(3, 4), (3, 4), (3, 4)]}),
                ('os.posix_spawn', {'return_value': 4321}), ('os.waitpid', {'return_value': (0, 0)})]:
            wrapper = patch('actql_sdk._local_worker_process.' + name, **options)
            value = wrapper.start(); self.addCleanup(wrapper.stop)
            setattr(self, name.replace('.', '_'), value)
        self._read_file = self.OriginalWorkerProcess__verify_executable
        self.options = {'executable': '/installed/bin/python', 'executable_bytes': 8192,
            'executable_sha256': 'a' * 64, 'executable_image': '/installed/bin/python',
            'executable_link': None, 'environment': (('LANG', 'C.UTF-8'),)}
        self.process = OriginalWorkerProcess(self.funding, self.slot, **self.options)

    def assert_no_execution_ack(self):
        self.assertFalse(any(call[0] in ('settle', 'stop_scope', 'report', 'close')
            for call in self.case.case.supplier.calls))

    def test_missing_funding_or_selection_refuses_before_io(self):
        with self.assertRaises(LocalWorkerFundingUnavailable):
            OriginalWorkerProcess(None, self.slot, **self.options)
        for change in ({'environment': None}, {'environment': (('PATH', '/usr/bin'),)},
                {'environment': (('LANG', 'C'), ('LANG', 'C'))}, {'executable': 'python'},
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
        self._read_file.assert_called_once_with()
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

    def test_spawn_current_callback_cannot_reenter_original_spawn_or_preparation(self):
        original = self.case.case.supplier.require_launch_originals
        entered = False
        def current(*args):
            nonlocal entered
            original(*args)
            if not entered:
                entered = True
                with self.assertRaises(RuntimeError): self.process.spawn()
                with self.assertRaises(RuntimeError): self.process.prepare_original_descriptors()
        self.case.case.supplier.require_launch_originals = current
        self.process.spawn()
        self.os_posix_spawn.assert_called_once()
        self.assertEqual(self.os_pipe.call_count, 3)
        self.assert_no_execution_ack()

    def test_prepare_descriptors_is_not_spawn_and_launch_reuses_original_pairs(self):
        self.process.prepare_original_descriptors()
        pairs = (self.process._stdin, self.process._stdout, self.process._stderr)
        self.assertEqual(self.os_pipe.call_count, 3)
        self.assertTrue(self.process._descriptors_prepared)
        self.assertFalse(self.process._spawn_attempted)
        self.assertIsNone(self.process._pid)
        self.os_posix_spawn.assert_not_called()
        with self.assertRaises(RuntimeError): self.process.prepare_original_descriptors()
        self.process.spawn()
        self.assertEqual((self.process._stdin, self.process._stdout, self.process._stderr), pairs)
        self.assertEqual(self.os_pipe.call_count, 3)
        self.assertEqual(self._read_file.call_count, 2)
        with self.assertRaises(RuntimeError): self.process.prepare_original_descriptors()
        self.assert_no_execution_ack()

    def test_preparation_current_callback_cannot_reenter_prepare_or_spawn(self):
        original = self.case.case.supplier.require_launch_originals
        entries = []
        def current(*args):
            original(*args)
            if self.process._descriptor_prepare_active:
                entries.append(True)
                with self.assertRaises(RuntimeError): self.process.prepare_original_descriptors()
                with self.assertRaises(RuntimeError): self.process.spawn()
        self.case.case.supplier.require_launch_originals = current
        self.process.prepare_original_descriptors()
        self.assertTrue(entries)
        self.assertFalse(self.process._descriptor_prepare_active)
        self.assertFalse(self.process._spawn_attempted)
        self.assertEqual(self.os_pipe.call_count, 3)
        self.os_posix_spawn.assert_not_called()
        self.assert_no_execution_ack()

    def test_prepared_descriptor_cleanup_prevents_launch_without_new_pipes(self):
        self.process.prepare_original_descriptors()
        self.process.close_parent_descriptors()
        with self.assertRaises(ValueError): self.process.spawn()
        with self.assertRaises(ValueError): self.process.prepare_original_descriptors()
        self.assertEqual(self.os_pipe.call_count, 3)
        self.os_posix_spawn.assert_not_called()
        self.assert_no_execution_ack()

    def test_partial_descriptor_preparation_is_original_pending_without_retry(self):
        self.os_pipe.side_effect = [(3, 4), OSError('Second pipe unavailable')]
        with self.assertRaises(LocalWorkerProcessPending) as caught:
            self.process.prepare_original_descriptors()
        self.assertIs(caught.exception.cleanup_process, self.process)
        originals = tuple(self.process._descriptors)
        # The first pair retains both closed low FDs and both live lifted
        # originals. The failed second os.pipe produced no descriptors.
        self.assertEqual([fd.value for fd in originals], [3, 4, 11, 12])
        self.assertEqual([fd.closed for fd in originals], [True, True, False, False])
        with self.assertRaises(RuntimeError): self.process.prepare_original_descriptors()
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        self.assertEqual(self.os_pipe.call_count, 2)
        self.assertEqual(tuple(self.process._descriptors), originals)
        self.process.close_parent_descriptors()
        self.assertTrue(all(fd.closed for fd in originals))
        self.os_posix_spawn.assert_not_called()
        self.assert_no_execution_ack()

    def test_prepared_executable_revalidation_failure_retains_original_descriptors(self):
        self.process.prepare_original_descriptors()
        originals = tuple(self.process._descriptors)
        self._read_file.side_effect = ValueError('Selected executable changed')
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        with self.assertRaises(RuntimeError): self.process.spawn()
        self.assertEqual(tuple(self.process._descriptors), originals)
        self.assertEqual(self.os_pipe.call_count, 3)
        self.process.close_parent_descriptors()
        self.assertTrue(all(fd.closed for fd in originals))
        self.os_posix_spawn.assert_not_called()
        self.assert_no_execution_ack()

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

    def test_parent_close_reentry_keeps_unknown_end_without_repeating_close(self):
        self.process.spawn()
        def close(fd):
            if fd == 12: self.process.close_parent_descriptors()
        self.case.os_close.side_effect = close
        with self.assertRaises(LocalWorkerProcessPending): self.process.close_parent_descriptors()
        with self.assertRaises(LocalWorkerProcessPending): self.process.close_parent_descriptors()
        self.assertEqual(sum(call.args == (12,) for call in self.case.os_close.call_args_list), 1)
        self.assertFalse(self.process._parent_close_inflight)
        self.assertTrue(all(fd.closed for fd in self.process._descriptors if fd.value != 12))
        self.assert_no_execution_ack()

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


class WorkerExecutableTests(unittest.TestCase):
    def setUp(self):
        self.case = WorkerProcessTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.process = self.case.process
        # Fixed independent SHA256 of three ASCII bytes, not product output.
        self.process._executable_bytes = 3
        self.process._executable_sha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
        self.case._read_file.side_effect = lambda: _VERIFY_EXECUTABLE(self.process)
        self.status = SimpleNamespace(st_mode=0o100755, st_dev=7, st_ino=13,
            st_size=3, st_mtime_ns=1, st_ctime_ns=2)
        self.case.case.os_fstat.side_effect = lambda fd: self.status
        wrapper = patch('actql_sdk._local_worker_process.os.read', side_effect=[b'abc', b''])
        self.read = wrapper.start(); self.addCleanup(wrapper.stop)

    def test_bounded_original_fd_read_and_exact_digest_then_close(self):
        _VERIFY_EXECUTABLE(self.process)
        self.case.case.os_open.assert_called_with(Path('/installed/bin/python'),
            os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        self.assertEqual([call.args for call in self.read.call_args_list], [(4, 3), (4, 1)])
        self.assertTrue(self.process._descriptors[0].closed)
        self.case.os_posix_spawn.assert_not_called()

    def test_metadata_failure_registers_and_closes_original_fd(self):
        self.case.case.os_fstat.side_effect = OSError('Original fstat failed')
        with self.assertRaises(OSError): _VERIFY_EXECUTABLE(self.process)
        self.assertEqual(len(self.process._descriptors), 1)
        self.assertTrue(self.process._descriptors[0].closed); self.read.assert_not_called()

    def test_incomplete_read_or_trailing_byte_never_spawns(self):
        self.read.side_effect = [b'abc', b'x']
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        self.case.os_pipe.assert_not_called(); self.case.os_posix_spawn.assert_not_called()
        self.assertTrue(self.process._descriptors[0].closed)

    def test_changed_fd_metadata_rejects_before_pipe_or_spawn(self):
        changed = SimpleNamespace(**vars(self.status)); changed.st_ctime_ns = 3
        self.case.case.os_fstat.side_effect = [self.status, changed]
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        self.case.os_pipe.assert_not_called(); self.case.os_posix_spawn.assert_not_called()

    def test_bad_digest_and_close_unknown_preserve_both_original_failures(self):
        self.read.side_effect = [b'abd', b'']
        self.case.case.os_close.side_effect = OSError('Original executable close Unknown')
        with self.assertRaises(LocalWorkerProcessPending) as caught: self.process.spawn()
        self.assertIsInstance(caught.exception.__cause__, ValueError)
        descriptor = self.process._descriptors[0]
        self.assertIsInstance(descriptor.close_failure, OSError)
        before = len(self.case.case.os_close.call_args_list)
        for _ in range(2):
            with self.assertRaises(LocalWorkerProcessPending): self.process.close_parent_descriptors()
        # Slot's moved descriptor retires once; the ambiguous executable FD
        # number is never closed again, even if the kernel has reused it.
        self.assertEqual(len(self.case.case.os_close.call_args_list), before + 1)
        self.case.os_posix_spawn.assert_not_called(); self.case.assert_no_execution_ack()

    def test_verified_bytes_with_unknown_close_cannot_spawn_or_reclose_executable(self):
        def close(fd):
            if fd == 4: raise OSError('Original executable close Unknown')
        self.case.case.os_close.side_effect = close
        with self.assertRaises(LocalWorkerProcessPending): self.process.spawn()
        for _ in range(2):
            with self.assertRaises(LocalWorkerProcessPending): self.process.close_parent_descriptors()
        self.assertEqual(sum(call.args == (4,) for call in self.case.case.os_close.call_args_list), 2)
        # One previous slot-open temporary close, one executable close.
        self.assertTrue(self.case.slot._closed)
        self.case.os_posix_spawn.assert_not_called(); self.case.assert_no_execution_ack()


class WorkerInterpreterSelectionTests(unittest.TestCase):
    def setUp(self):
        self.case = WorkerExecutableTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.process = self.case.process
        self.process._executable = Path('/installed/venv/bin/python')
        self.process._executable_image = Path('/installed/runtime/bin/python3.12')
        self.process._executable_link = '/installed/runtime/bin/python3.12'
        self.link_status = SimpleNamespace(st_mode=0o120755, st_dev=7, st_ino=15,
            st_mtime_ns=1, st_ctime_ns=2)
        self.case.case.case.os_lstat.side_effect = lambda path: self.link_status
        wrapper = patch('actql_sdk._local_worker_process.os.readlink', return_value=self.process._executable_link)
        self.readlink = wrapper.start(); self.addCleanup(wrapper.stop)

    def test_selected_image_is_checked_without_replacing_venv_launch_path(self):
        _VERIFY_EXECUTABLE(self.process)
        self.case.case.case.os_open.assert_called_with(Path('/installed/runtime/bin/python3.12'),
            os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        self.assertEqual(self.process._executable, Path('/installed/venv/bin/python'))
        self.assertEqual(self.process._launch_identity, (7, 15, 1, 2))

    def test_image_missing_and_implicit_link_mapping_refuse_at_selection(self):
        case = self.case.case
        for changes in ({'executable_image': None}, {'executable_image': 'relative'},
                {'executable_image': '/different/python', 'executable_link': None},
                {'executable_link': '/unrelated/python'}, {'executable_link': True}):
            with self.assertRaises(ValueError):
                OriginalWorkerProcess(case.funding, case.slot, **(case.options | changes))
        case.os_posix_spawn.assert_not_called()

    def test_changed_link_target_refuses_before_opening_image(self):
        self.readlink.return_value = '/unrelated/python'
        before = self.case.case.case.os_open.call_count
        with self.assertRaises(ValueError): _VERIFY_EXECUTABLE(self.process)
        self.assertEqual(self.case.case.case.os_open.call_count, before)
        self.case.case.os_posix_spawn.assert_not_called()

    def test_replaced_same_target_link_identity_refuses(self):
        self.process._verify_launch_original(); self.link_status.st_ino = 16
        with self.assertRaises(ValueError): self.process._verify_launch_original()
        self.case.case.os_posix_spawn.assert_not_called()

    def test_regular_file_cannot_replace_selected_link(self):
        self.link_status.st_mode = 0o100755
        with self.assertRaises(ValueError): self.process._verify_launch_original()
        self.readlink.assert_not_called()

    def test_link_metadata_change_after_image_read_refuses_at_spawn_boundary(self):
        _VERIFY_EXECUTABLE(self.process); self.link_status.st_ctime_ns = 3
        with self.assertRaises(ValueError): self.process._verify_launch_original()
        self.assertTrue(self.process._descriptors[0].closed)
        self.case.case.os_posix_spawn.assert_not_called()

    def test_spawn_keeps_selected_venv_path_and_checks_original_image(self):
        slot = self.case.case.case
        slot.os_lstat.side_effect = lambda path: self.link_status if path == self.process._executable else slot.named
        slot.os_fstat.side_effect = lambda fd: slot.status if fd == 10 else self.case.status
        self.process.spawn()
        args = self.case.case.os_posix_spawn.call_args.args
        self.assertEqual(args[0], '/installed/venv/bin/python')
        self.assertEqual(args[1][0], '/installed/venv/bin/python')
        self.assertEqual(self.process._executable_image, Path('/installed/runtime/bin/python3.12'))
        self.case.case.assert_no_execution_ack()
