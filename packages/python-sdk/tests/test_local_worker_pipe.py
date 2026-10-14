"""Original pipe syscall/loop doubles; actual worker/Common resources remain0."""
import asyncio
import copy
import unittest
from unittest.mock import patch

from actql_sdk._local_worker_pipe import OriginalWorkerPipe, LocalWorkerPipePending
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
import test_local_worker_process as process_fixture


class ReadinessLoop:
    def __init__(self, loop):
        self.loop = loop; self.calls = []; self.immediate = True; self.remove_ack = True; self.closed = False
        self.registered = asyncio.Event()
    def create_future(self): return self.loop.create_future()
    def add_reader(self, fd, callback):
        self.calls.append(('reader', fd)); self.registered.set()
        if self.immediate: callback()
    def add_writer(self, fd, callback):
        self.calls.append(('writer', fd)); self.registered.set()
        if self.immediate: callback()
    def remove_reader(self, fd): self.calls.append(('remove_reader', fd)); return self.remove_ack
    def remove_writer(self, fd): self.calls.append(('remove_writer', fd)); return self.remove_ack
    def is_closed(self): return self.closed


class WorkerPipeTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.case = process_fixture.WorkerProcessTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.process, self.funding = self.case.process, self.case.funding
        self.process.spawn()
        for name, options in [('os.set_blocking', {}), ('os.write', {'return_value': 2}),
                ('os.read', {'return_value': b'abc'})]:
            wrapper = patch('actql_sdk._local_worker_pipe.' + name, **options)
            value = wrapper.start(); self.addCleanup(wrapper.stop)
            setattr(self, name.replace('.', '_'), value)
        self.pipe = OriginalWorkerPipe(self.funding, self.process)
    def assert_no_execution_ack(self): self.case.assert_no_execution_ack()

    async def test_missing_or_foreign_funding_refuses_without_pipe_io(self):
        with self.assertRaises(LocalWorkerFundingUnavailable): OriginalWorkerPipe(None, self.process)
        with self.assertRaises(ValueError): OriginalWorkerPipe(self.funding, object())
        self.os_set_blocking.assert_not_called(); self.os_write.assert_not_called(); self.os_read.assert_not_called()

    async def test_exact_process_has_one_pipe_consumer(self):
        with self.assertRaises(ValueError): OriginalWorkerPipe(self.funding, self.process)
        self.os_set_blocking.assert_not_called()

    async def test_prepare_uses_only_owned_parent_ends_without_another_spawn(self):
        self.pipe.prepare()
        self.assertEqual([c.args for c in self.os_set_blocking.call_args_list], [(12, False), (13, False), (15, False)])
        self.assertEqual(self.case.os_posix_spawn.call_count, 1)
        with self.assertRaises(RuntimeError): self.pipe.prepare()
        self.assert_no_execution_ack()

    async def test_partial_flag_failure_keeps_same_process_without_repreparation(self):
        self.os_set_blocking.side_effect = [None, OSError('Flag state unknown')]
        with self.assertRaises(LocalWorkerPipePending) as caught: self.pipe.prepare()
        self.assertIs(caught.exception.cleanup_pipe, self.pipe)
        with self.assertRaises(LocalWorkerPipePending): self.pipe.prepare()
        self.assertEqual(self.os_set_blocking.call_count, 2)
        self.pipe.close_parent(); self.assert_no_execution_ack()

    async def test_bounds_and_mutability_refuse_before_syscalls(self):
        self.pipe.prepare()
        for value in (b'', b'x' * 65537, bytearray(b'x')):
            with self.assertRaises(ValueError): await self.pipe.write(value)
        for value in (0, True, 65537):
            with self.assertRaises(ValueError): await self.pipe.read(value)
        self.os_write.assert_not_called(); self.os_read.assert_not_called()

    async def test_partial_write_count_is_physical_only_and_exact_bytes_are_used(self):
        self.pipe.prepare(); raw = b'abcdef'
        self.assertEqual(await self.pipe.write(raw), 2)
        self.os_write.assert_called_once_with(12, raw)
        self.assertIsNone(self.pipe._write_payload)
        self.assertFalse(self.process._parent_pipe_borrowed); self.assert_no_execution_ack()

    async def test_nonblocking_write_waits_on_same_fd_and_never_creates_a_thread(self):
        self.pipe.prepare(); self.os_write.side_effect = [BlockingIOError(), 2]
        loop = ReadinessLoop(asyncio.get_running_loop())
        with patch('actql_sdk._local_worker_pipe.asyncio.get_running_loop', return_value=loop):
            self.assertEqual(await self.pipe.write(b'ab'), 2)
        self.assertEqual(loop.calls, [('writer', 12), ('remove_writer', 12)])
        self.assertIsNone(self.pipe._readiness); self.assertEqual(self.case.os_posix_spawn.call_count, 1)

    async def test_bounded_read_and_diagnostic_read_use_original_different_ends(self):
        self.pipe.prepare()
        self.assertEqual(await self.pipe.read(4), b'abc')
        self.assertEqual(await self.pipe.read(4, diagnostic=True), b'abc')
        self.assertEqual([c.args for c in self.os_read.call_args_list], [(13, 4), (15, 4)])
        self.assert_no_execution_ack()

    async def test_eof_is_not_stop_close_cancel_or_settlement(self):
        self.pipe.prepare(); self.os_read.return_value = b''
        self.assertEqual(await self.pipe.read(4), b'')
        self.assertFalse(self.process._parent_closed); self.assertIsNone(self.process._exit)
        self.assert_no_execution_ack()

    async def test_post_write_revocation_keeps_actual_partial_count_and_blocks_resend(self):
        self.pipe.prepare()
        def wrote(fd, raw):
            self.case.case.case.supplier.deny_launch = True
            return 2
        self.os_write.side_effect = wrote
        with self.assertRaises(ValueError): await self.pipe.write(b'abcd')
        self.assertEqual(self.pipe._written, 2); self.assertEqual(self.pipe._write_payload, b'abcd')
        self.case.case.case.supplier.deny_launch = False
        with self.assertRaises(LocalWorkerPipePending): await self.pipe.write(b'abcd')
        self.os_write.assert_called_once(); self.assert_no_execution_ack()

    async def test_post_read_revocation_retains_original_bytes_without_redelivery(self):
        self.pipe.prepare()
        def read(fd, limit):
            self.case.case.case.supplier.deny_launch = True
            return b'abc'
        self.os_read.side_effect = read
        with self.assertRaises(ValueError): await self.pipe.read(4)
        self.assertEqual(self.pipe._read_payload, b'abc')
        self.case.case.case.supplier.deny_launch = False
        with self.assertRaises(LocalWorkerPipePending): await self.pipe.read(4)
        self.os_read.assert_called_once()

    async def test_coroutine_cancellation_retains_same_funding_and_original_write(self):
        self.pipe.prepare(); self.os_write.side_effect = BlockingIOError()
        loop = ReadinessLoop(asyncio.get_running_loop()); loop.immediate = False
        with patch('actql_sdk._local_worker_pipe.asyncio.get_running_loop', return_value=loop):
            task = asyncio.create_task(self.pipe.write(b'original'))
            await loop.registered.wait(); task.cancel()
            with self.assertRaises(asyncio.CancelledError): await task
        self.assertEqual(self.pipe._write_payload, b'original')
        self.assertIsNone(self.pipe._written); self.assertFalse(self.process._parent_pipe_borrowed)
        with self.assertRaises(LocalWorkerPipePending): await self.pipe.write(b'original')
        self.os_write.assert_called_once(); self.assert_no_execution_ack()

    async def test_close_during_wait_keeps_borrow_until_original_io_ends(self):
        self.pipe.prepare(); self.os_read.side_effect = BlockingIOError()
        loop = ReadinessLoop(asyncio.get_running_loop()); loop.immediate = False
        with patch('actql_sdk._local_worker_pipe.asyncio.get_running_loop', return_value=loop):
            task = asyncio.create_task(self.pipe.read(4)); await loop.registered.wait()
            before = self.case.case.os_close.call_count
            with self.assertRaises(LocalWorkerPipePending): self.pipe.close_parent()
            self.assertEqual(self.case.case.os_close.call_count, before)
            self.assertTrue(self.process._parent_pipe_borrowed)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError): await task
        self.pipe.close_parent(); self.pipe.close_parent()
        self.assertTrue(self.process._parent_closed); self.assert_no_execution_ack()

    async def test_unknown_readiness_removal_preserves_loop_and_forbids_raw_remove_retry(self):
        self.pipe.prepare(); self.os_read.side_effect = [BlockingIOError(), b'abc']
        loop = ReadinessLoop(asyncio.get_running_loop()); loop.remove_ack = False
        with patch('actql_sdk._local_worker_pipe.asyncio.get_running_loop', return_value=loop):
            with self.assertRaises(RuntimeError): await self.pipe.read(4)
        with self.assertRaises(LocalWorkerPipePending): self.pipe.close_parent()
        self.assertEqual(loop.calls, [('reader', 13), ('remove_reader', 13)])
        self.assertIsNotNone(self.pipe._readiness)
        # Retirement of this same loop clears only the original readiness watch.
        # It is still not child/Store/Run/FD cleanup evidence.
        loop.closed = True; self.pipe.close_parent()
        self.assertTrue(self.process._parent_closed); self.assert_no_execution_ack()

    async def test_copied_pipe_cannot_use_original_process_or_descriptors(self):
        with self.assertRaises(TypeError): copy.copy(self.pipe)
        with self.assertRaises(TypeError): copy.deepcopy(self.pipe)
        clone = OriginalWorkerPipe.__new__(OriginalWorkerPipe); clone.__dict__.update(self.pipe.__dict__)
        with self.assertRaises(ValueError): clone.prepare()
        self.os_set_blocking.assert_not_called()
