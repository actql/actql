"""Native slot kernel-call doubles only; no actual file, process or stop ACK."""
import copy
import errno
import fcntl
import os
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_worker_slot import OriginalWorkerSlot, LocalWorkerSlotPending
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
import test_local_worker_funding as funding_fixture


class WorkerSlotTests(unittest.TestCase):
    def setUp(self):
        self.case = funding_fixture.WorkerFundingTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.funding = self.case.prepare()
        self.path = Path('/installed-private-original/slot')
        self.status = SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=os.geteuid(), st_dev=7, st_ino=11)
        self.named = SimpleNamespace(**vars(self.status))
        for name, options in [('os.open', {'return_value': 4}), ('os.fstat', {'side_effect': lambda fd: self.status}),
                ('os.lstat', {'side_effect': lambda path: self.named}), ('os.close', {}),
                ('fcntl.fcntl', {'return_value': 10}), ('fcntl.flock', {})]:
            wrapper = patch('actql_sdk._local_worker_slot.' + name, **options)
            value = wrapper.start(); self.addCleanup(wrapper.stop)
            setattr(self, name.replace('.', '_'), value)
        self.slot = OriginalWorkerSlot(self.funding, str(self.path))
    def test_missing_funding_and_unselected_path_refuse_without_kernel_io(self):
        with self.assertRaises(LocalWorkerFundingUnavailable): OriginalWorkerSlot(None, self.path)
        with self.assertRaises(ValueError): OriginalWorkerSlot(self.funding, Path('relative'))
        self.os_open.assert_not_called()
    def test_private_original_open_registers_same_descriptors_and_never_reopens(self):
        self.slot.open()
        self.os_open.assert_called_once_with(self.path,
            os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
        self.fcntl_fcntl.assert_called_once_with(4, fcntl.F_DUPFD_CLOEXEC, 10)
        self.os_close.assert_called_once_with(4)
        with self.assertRaises(RuntimeError): self.slot.open()
    def test_unsafe_file_failure_retains_original_descriptor_for_close(self):
        self.status.st_mode = stat.S_IFREG | 0o644
        with self.assertRaises(LocalWorkerSlotPending) as caught: self.slot.open()
        self.assertIs(caught.exception.cleanup_slot, self.slot)
        self.os_close.assert_not_called()
        self.slot.close(); self.os_close.assert_called_once_with(4)
    def test_duplication_failure_closes_only_original_descriptor_without_reopen(self):
        self.fcntl_fcntl.side_effect = OSError('Original duplication failed')
        with self.assertRaises(LocalWorkerSlotPending): self.slot.open()
        self.slot.close(); self.slot.close()
        self.os_close.assert_called_once_with(4)
        self.os_open.assert_called_once()
    def test_unknown_temporary_close_never_recloses_reused_number(self):
        self.os_close.side_effect = [OSError('Original close outcome unknown'), None]
        with self.assertRaises(LocalWorkerSlotPending): self.slot.open()
        with self.assertRaises(ValueError): self.slot.try_acquire()
        with self.assertRaises(LocalWorkerSlotPending): self.slot.close()
        with self.assertRaises(LocalWorkerSlotPending): self.slot.close()
        self.assertEqual([call.args for call in self.os_close.call_args_list], [(4,), (10,)])
        self.assertFalse(self.slot._closed)
    def test_busy_physical_lock_is_not_acquired_or_a_run_permission(self):
        self.slot.open(); self.fcntl_flock.side_effect = BlockingIOError(errno.EWOULDBLOCK, 'busy')
        self.assertFalse(self.slot.try_acquire())
        with self.assertRaises(ValueError): self.slot.inheritance_action()
    def test_replaced_named_file_refuses_before_lock_or_inheritance(self):
        self.slot.open(); self.named.st_ino = 12
        with self.assertRaises(ValueError): self.slot.try_acquire()
        self.fcntl_flock.assert_not_called()
    def test_held_current_description_supplies_only_os_fd3_action(self):
        self.slot.open(); self.assertTrue(self.slot.try_acquire())
        self.assertEqual(self.slot.inheritance_action(), (os.POSIX_SPAWN_DUP2, 10, 3))
        self.assertEqual(self.os_open.call_count, 1)
    def test_parent_close_does_not_unlock_unlink_or_settle_and_success_is_not_repeated(self):
        self.slot.open(); self.slot.try_acquire(); self.slot.close(); self.slot.close()
        self.assertEqual([call.args for call in self.os_close.call_args_list], [(4,), (10,)])
        self.assertFalse(any(call.args[1] == fcntl.LOCK_UN for call in self.fcntl_flock.call_args_list))
        self.assertFalse(any(c[0] in ('settle', 'close') for c in self.case.supplier.calls))
    def test_parent_close_unknown_blocks_new_work_and_second_raw_close(self):
        self.slot.open(); self.os_close.side_effect = OSError('Parent close unknown')
        with self.assertRaises(LocalWorkerSlotPending): self.slot.close()
        with self.assertRaises(LocalWorkerSlotPending): self.slot.close()
        with self.assertRaises(ValueError): self.slot.try_acquire()
        self.assertEqual(sum(call.args == (10,) for call in self.os_close.call_args_list), 1)
        self.assertFalse(self.slot._closed)
    def test_copied_slot_and_funding_callback_retirement_cannot_touch_kernel(self):
        with self.assertRaises(TypeError): copy.copy(self.slot)
        with self.assertRaises(TypeError): copy.deepcopy(self.slot)
        self.case.supplier.require_launch_originals = lambda *args: self.funding.close()
        with self.assertRaises(ValueError): self.slot.open()
        self.os_open.assert_not_called()
