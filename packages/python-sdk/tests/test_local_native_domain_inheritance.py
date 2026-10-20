"""Original Native domain/FD inheritance with independent syscall/Owner doubles.

No actual worker, VM, complete funding or numerical profile is supplied.
"""
import asyncio
import os
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_native_domain_custody import _OriginalDomainError
from actql_sdk._local_native_live_channel import _OriginalLiveChannelCustody
from actql_sdk._local_worker_process import OriginalWorkerProcess, LocalWorkerProcessPending
from actql_sdk._local_worker_slot import OriginalWorkerSlot
from test_local_native_live_channel import ChannelFixture


class NativeDomainInheritanceTests(unittest.TestCase):
    def test_original_domain_is_bound_before_duplication_or_spawn(self):
        f = ChannelFixture(self, spawn=False)
        p = f.process
        self.assertIs(p._native_domain, f.domain)
        self.assertIs(f.domain._worker_process_original, p)
        self.assertEqual(p._native_material.scalars, f.material.values)
        self.assertIs(p._native_source, f.domain._descriptor)
        self.assertIsNone(p._native_duplicate)
        self.assertFalse(p._spawn_syscall_attempted)
        self.assertFalse(p._native_metadata_retired)
        self.assertEqual(sum(c[0] == 'reserve' for c in f.supplier.calls), 1)
        self.assertTrue(any(e[0] == 'project' for e in f.material.events))
        with self.assertRaises(ValueError): f.domain.close_after_stop()

    def test_low_original_fd_is_lifted_before_fd3_and_fd4_rewrites(self):
        for source in (3, 4):
            with self.subTest(source=source):
                f = ChannelFixture(self, before_process=lambda f: setattr(f.material.descriptor, 'value', source), spawn=False)
                with patch('actql_sdk._local_worker_process.os.posix_spawn', return_value=4321) as spawn:
                    f.process.spawn()
                actions = spawn.call_args.kwargs['file_actions']
                self.assertEqual(actions[:5], [
                    (os.POSIX_SPAWN_DUP2, 10, 3),
                    (os.POSIX_SPAWN_DUP2, 21, 0),
                    (os.POSIX_SPAWN_DUP2, 24, 1),
                    (os.POSIX_SPAWN_DUP2, 26, 2),
                    (os.POSIX_SPAWN_DUP2, 30, 4)])
                self.assertIn((os.POSIX_SPAWN_CLOSE, 30), actions)
                self.assertNotIn((os.POSIX_SPAWN_CLOSE, source), actions)
                self.assertTrue(f.process._native_duplicate.closed)
                self.assertFalse(f.domain._descriptor.closed or f.domain._descriptor.close_attempted)
                self.assertEqual(f.process._pid, 4321)
                self.assertFalse(f.process._native_metadata_retired)

    def test_foreign_funding_or_source_mutation_refuses_before_fd_acquisition(self):
        changes = (lambda f: setattr(f.funding, '_delegation', object()),
                   lambda f: setattr(f.domain._descriptor, 'value', 99),
                   lambda f: setattr(f.domain._descriptor, 'closed', True),
                   lambda f: setattr(f.domain, '_worker_process_original', object()))
        for change in changes:
            with self.subTest(change=change):
                f = ChannelFixture(self, spawn=False)
                change(f)
                with patch('actql_sdk._local_worker_process.os.posix_spawn') as spawn, \
                     patch('actql_sdk._local_worker_process.fcntl.fcntl') as dup:
                    with self.assertRaises(ValueError): f.process.spawn()
                spawn.assert_not_called(); dup.assert_not_called()
                self.assertFalse(f.process._spawn_syscall_attempted)

    def test_wrong_fd_identity_permissions_or_capacity_refuses_before_dup(self):
        baseline = dict(st_mode=stat.S_IFREG | 0o600, st_uid=os.geteuid(), st_size=65536, st_dev=2, st_ino=3)
        for change in ({'st_mode': stat.S_IFREG | 0o644}, {'st_mode': stat.S_IFIFO | 0o600},
                       {'st_uid': os.geteuid() + 1}, {'st_size': 65535}, {'st_dev': 7}, {'st_ino': 9}):
            with self.subTest(change=change):
                f = ChannelFixture(self, spawn=False)
                with patch('actql_sdk._local_worker_process.os.fstat', return_value=SimpleNamespace(**(baseline | change))), \
                     patch('actql_sdk._local_worker_process.fcntl.fcntl') as dup, \
                     patch('actql_sdk._local_worker_process.os.posix_spawn') as spawn:
                    with self.assertRaises(LocalWorkerProcessPending): f.process.spawn()
                dup.assert_not_called(); spawn.assert_not_called()
                self.assertIsNone(f.process._native_duplicate)
                self.assertFalse(f.process._spawn_syscall_attempted)

    def test_lost_duplication_keeps_unknown_and_forbids_reacquisition_or_retirement(self):
        f = ChannelFixture(self, spawn=False)
        with patch('actql_sdk._local_worker_process.fcntl.fcntl', side_effect=OSError('dup reply unknown')) as dup, \
             patch('actql_sdk._local_worker_process.os.posix_spawn') as spawn:
            with self.assertRaises(LocalWorkerProcessPending) as caught: f.process.spawn()
            self.assertIs(caught.exception.cleanup_process, f.process)
            with self.assertRaises(RuntimeError): f.process.spawn()
        dup.assert_called_once(); spawn.assert_not_called()
        self.assertTrue(f.process._native_dup_unknown)
        with self.assertRaises(LocalWorkerProcessPending): f.process.close_parent_descriptors()
        with self.assertRaises(ValueError): f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        with self.assertRaises(ValueError): f.domain.close_after_stop()
        self.assertFalse(f.process._native_metadata_retired)

    def test_duplicate_postcheck_failure_keeps_exact_fd_for_cleanup(self):
        f = ChannelFixture(self, spawn=False)
        good = SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=os.geteuid(), st_size=65536, st_dev=2, st_ino=3)
        wrong = SimpleNamespace(**(vars(good) | {'st_ino': 99}))
        with patch('actql_sdk._local_worker_process.os.fstat', side_effect=[good, wrong]), \
             patch('actql_sdk._local_worker_process.os.posix_spawn') as spawn:
            with self.assertRaises(LocalWorkerProcessPending): f.process.spawn()
        spawn.assert_not_called()
        original = f.process._native_duplicate
        self.assertEqual(original.value, 30)
        self.assertIn(original, f.process._descriptors)
        self.assertFalse(original.closed)
        f.process.close_parent_descriptors()
        self.assertTrue(original.closed)
        self.assertFalse(f.domain._descriptor.close_attempted)
        f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertTrue(f.process._native_metadata_retired)
        f.domain.close_after_stop()
        self.assertIsNone(f.domain._worker_process_original)

    def test_spawn_reply_loss_never_becomes_known_unstarted_cleanup(self):
        f = ChannelFixture(self, spawn=False)
        with patch('actql_sdk._local_worker_process.os.posix_spawn', side_effect=OSError('spawn outcome unknown')) as spawn:
            with self.assertRaises(LocalWorkerProcessPending): f.process.spawn()
            with self.assertRaises(RuntimeError): f.process.spawn()
        spawn.assert_called_once()
        f.process.close_parent_descriptors()
        self.assertTrue(f.process._spawn_syscall_attempted)
        self.assertIsNone(f.process._pid)
        with self.assertRaises(ValueError): f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        with self.assertRaises(ValueError): f.domain.close_after_stop()
        self.assertFalse(any(c[0] == 'settle' for c in f.supplier.calls))

    def test_duplicate_close_unknown_keeps_actual_child_and_same_fd(self):
        f = ChannelFixture(self, spawn=False)
        with patch('actql_sdk._local_worker_process.os.close', side_effect=lambda fd: (_ for _ in ()).throw(OSError('close lost')) if fd == 30 else None) as close:
            with self.assertRaises(LocalWorkerProcessPending): f.process.spawn()
            with self.assertRaises(LocalWorkerProcessPending): f.process.close_parent_descriptors()
            with self.assertRaises(LocalWorkerProcessPending): f.process.close_parent_descriptors()
        self.assertEqual(sum(c.args == (30,) for c in close.call_args_list), 1)
        self.assertEqual(f.process._pid, 4321)
        self.assertTrue(f.process._native_duplicate.close_attempted)
        self.assertFalse(f.process._native_duplicate.closed or f.process._parent_closed)
        with self.assertRaises(ValueError): f.domain.close_after_stop()

    def test_domain_remains_held_after_parent_close_until_original_channel_owner_ack(self):
        f = ChannelFixture(self)
        c = f.take()
        f.close_host_pipe()
        with self.assertRaises(ValueError): f.domain.close_after_stop()
        self.assertFalse(f.process._native_metadata_retired)
        c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertTrue(f.process._native_metadata_retired)
        self.assertFalse(f.domain._closed or f.domain._descriptor.closed)
        f.domain.close_after_stop()
        self.assertTrue(f.domain._closed)
        self.assertFalse(any(c[0] == 'settle' for c in f.supplier.calls))

    def test_unstarted_cleanup_needs_exact_nonboolean_owner_ack(self):
        f = ChannelFixture(self, spawn=False)
        f.process.close_parent_descriptors()
        for observed in (True, None, 4321):
            with self.assertRaises(ValueError): f.process._retire_unstarted_native_after_owner_ack(observed)
        f.supplier.deny_stop = True
        with self.assertRaises(LocalWorkerProcessPending): f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertFalse(f.process._native_metadata_retired)
        f = ChannelFixture(self, spawn=False)
        f.process.close_parent_descriptors()
        f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertTrue(f.process._native_metadata_retired)
        self.assertEqual(sum(c[0] == 'reserve' for c in f.supplier.calls), 1)
        self.assertFalse(any(c[0] == 'settle' for c in f.supplier.calls))

    def test_original_domain_cannot_be_consumed_by_another_process(self):
        f = ChannelFixture(self, spawn=False)
        slot = OriginalWorkerSlot(f.funding, '/installed/another-slot')
        with self.assertRaises(LocalWorkerProcessPending) as caught:
            OriginalWorkerProcess(f.funding, slot, executable='/installed/python',
                executable_image='/installed/python', executable_link=None,
                executable_bytes=8192, executable_sha256='a' * 64,
                environment=(('LANG', 'C.UTF-8'),))
        self.assertIs(f.domain._worker_process_original, f.process)
        self.assertIsNone(caught.exception.cleanup_process._native_domain)
        self.assertIsNone(f.process._native_duplicate)

    def test_registration_failure_before_dup_is_known_unstarted_and_no_raw_close(self):
        class Slots(list):
            def append(self, value): raise MemoryError('registration failed before syscall')
        f = ChannelFixture(self, spawn=False)
        f.process._descriptors = Slots()
        with patch('actql_sdk._local_worker_process.fcntl.fcntl') as dup:
            with self.assertRaises(LocalWorkerProcessPending): f.process.spawn()
        dup.assert_not_called()
        self.assertEqual(f.process._native_duplicate.value, -1)
        self.assertTrue(f.process._native_duplicate.closed)
        self.assertFalse(f.process._native_dup_unknown)
        f.process.close_parent_descriptors()
        f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertTrue(f.process._native_metadata_retired)

    def test_malformed_dup_result_never_closes_a_boolean_or_starts_a_child(self):
        for reported in (True, False, 4, -1, None):
            with self.subTest(reported=reported):
                f = ChannelFixture(self, spawn=False)
                with patch('actql_sdk._local_worker_process.fcntl.fcntl', return_value=reported), \
                     patch('actql_sdk._local_worker_process.os.close') as close, \
                     patch('actql_sdk._local_worker_process.os.posix_spawn') as spawn:
                    with self.assertRaises(LocalWorkerProcessPending): f.process.spawn()
                    with self.assertRaises(LocalWorkerProcessPending): f.process.close_parent_descriptors()
                spawn.assert_not_called()
                self.assertFalse(any(c.args[0] in (-1, 0, 1, 4) for c in close.call_args_list))
                self.assertTrue(f.process._native_dup_unknown)
                self.assertFalse(f.process._native_metadata_retired)

    def test_reentrant_duplicate_close_at_final_current_refuses_before_spawn(self):
        f = ChannelFixture(self, spawn=False)
        original = f.supplier.require_launch_originals
        def current(*args):
            original(*args)
            if f.process._stdin is not None: f.process._native_duplicate.close()
        f.supplier.require_launch_originals = current
        with patch('actql_sdk._local_worker_process.os.posix_spawn') as spawn:
            with self.assertRaises(LocalWorkerProcessPending): f.process.spawn()
        spawn.assert_not_called()
        self.assertFalse(f.process._spawn_syscall_attempted)
        f.process.close_parent_descriptors()
        f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertTrue(f.process._native_metadata_retired)

    def test_foreign_creator_thread_cannot_retire_domain_metadata(self):
        f = ChannelFixture(self, spawn=False)
        f.process.close_parent_descriptors()
        with patch('actql_sdk._local_worker_process.current_thread', return_value=object()):
            with self.assertRaises(ValueError): f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertFalse(f.process._native_metadata_retired)

    def test_cloned_channel_cannot_retire_original_process_domain(self):
        f = ChannelFixture(self)
        original = f.take()
        f.close_host_pipe()
        clone = _OriginalLiveChannelCustody.__new__(_OriginalLiveChannelCustody)
        for name in original.__slots__: setattr(clone, name, getattr(original, name))
        clone._closed = True
        with self.assertRaises(ValueError): f.process._retire_native_metadata(clone)
        self.assertFalse(f.process._native_metadata_retired)
        with self.assertRaises(ValueError): f.domain.close_after_stop()

    def test_lost_unstarted_owner_ack_is_sticky_without_second_callback(self):
        f = ChannelFixture(self, spawn=False)
        f.process.close_parent_descriptors()
        callback = f.supplier.require_scoped_stop
        def lost(*args):
            callback(*args)
            raise OSError('original cleanup adoption response lost')
        f.supplier.require_scoped_stop = lost
        with self.assertRaises(LocalWorkerProcessPending) as caught:
            f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertIs(caught.exception.cleanup_process, f.process)
        f.supplier.require_scoped_stop = callback
        with self.assertRaises(LocalWorkerProcessPending):
            f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertEqual(sum(c[0] == 'stop_scope' for c in f.supplier.calls), 1)
        with self.assertRaises(ValueError): f.domain.close_after_stop()
        self.assertFalse(f.process._native_metadata_retired)

    def test_reentrant_unstarted_owner_ack_cannot_repeat_adoption(self):
        f = ChannelFixture(self, spawn=False)
        f.process.close_parent_descriptors()
        calls = []
        def reenter(*args):
            calls.append(args)
            f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        f.supplier.require_scoped_stop = reenter
        with self.assertRaises(LocalWorkerProcessPending):
            f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        with self.assertRaises(LocalWorkerProcessPending):
            f.process._retire_unstarted_native_after_owner_ack(f.supplier.stop)
        self.assertEqual(len(calls), 1)
        self.assertFalse(f.process._native_retirement_inflight)
        self.assertFalse(f.process._native_metadata_retired)
        with self.assertRaises(ValueError): f.domain.close_after_stop()

    def test_constructor_material_loss_retains_same_partial_process(self):
        def fail(f): f.material.project_fault = OSError('original material lost')
        with self.assertRaises(LocalWorkerProcessPending) as caught:
            ChannelFixture(self, before_process=fail, spawn=False)
        p = caught.exception.cleanup_process
        f = self._live_channel_fixture
        self.assertIs(f.domain._worker_process_original, p)
        self.assertIs(p._native_domain, f.domain)
        self.assertIsNone(p._native_material)
        self.assertFalse(p._spawn_syscall_attempted)
        with self.assertRaises(_OriginalDomainError): p.spawn()
        with self.assertRaises(_OriginalDomainError): f.domain.close_after_stop()


if __name__ == '__main__':
    unittest.main()
