"""Driver/process/pipe assembly with Owner/syscall doubles; actual worker0."""
import asyncio
import copy
import unittest
from unittest.mock import patch
import httpx

from actql_sdk import AsyncClient
from actql_sdk._local_worker_channel import OriginalWorkerPipeChannel, _InstalledWorkerControl
from actql_sdk._local_worker_driver import OriginalWorkerDriver, LocalWorkerDriverPending
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
from actql_sdk._local_worker_process import OriginalWorkerProcess
from actql_sdk._local_worker_slot import OriginalWorkerSlot
import test_local_worker_process as process_fixture
from test_local_worker_driver import PAYLOAD
from fixtures import PROFILE


class Control(_InstalledWorkerControl):
    def __init__(self):
        super().__init__(); self.bootstrap = object(); self.calls = []
        self.start_ack = None; self.close_ack = None; self.start_error = None; self.close_error = None
        profile = copy.deepcopy(PROFILE); profile.update(mode='local', owner='local')
        self.response = httpx.Response(200, json=profile); self.responses = []
        self.current_hook = None; self.exchange_error = None; self.bootstrap_hook = None
    def prepare_original_bootstrap(self, process):
        self.calls.append(('bootstrap', process))
        if self.bootstrap_hook: self.bootstrap_hook()
        return self.bootstrap
    async def start_original_host(self, process, pipe, bootstrap):
        self.calls.append(('start', process, pipe, bootstrap))
        if self.start_error: raise self.start_error
        return self.start_ack
    def require_current_original(self, process):
        self.calls.append(('current', process))
        if self.current_hook: self.current_hook()
    async def exchange_original_wire(self, process, pipe, operation, payload):
        self.calls.append(('exchange', process, pipe, operation, payload))
        # The original control keeps response custody before the parent await.
        self.responses.append(self.response)
        if self.exchange_error: raise self.exchange_error
        return self.response
    async def close_original_host(self, process, pipe, bootstrap):
        self.calls.append(('close', process, pipe, bootstrap))
        if self.close_error: raise self.close_error
        return self.close_ack


class WorkerChannelTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.case = process_fixture.WorkerProcessTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.funding = self.case.funding
        # The assembly starts its own untouched original slot, not an already
        # spawned scalar process. FD/kernel calls remain the existing doubles.
        self.case.case.fcntl_fcntl.side_effect = iter(range(20, 27))
        self.slot = OriginalWorkerSlot(self.funding, str(self.case.case.path))
        self.process = OriginalWorkerProcess(self.funding, self.slot, **self.case.options)
        wrapper = patch('actql_sdk._local_worker_pipe.os.set_blocking')
        self.set_blocking = wrapper.start(); self.addCleanup(wrapper.stop)
        self.control = Control()
        self.channel = OriginalWorkerPipeChannel(self.funding, self.process, self.control)
        self.driver = OriginalWorkerDriver(self.funding, lambda _: self.channel)
    def assert_no_execution_ack(self): self.case.assert_no_execution_ack()

    async def test_missing_control_refuses_before_spawn_or_slot_io(self):
        before = self.case.case.os_open.call_count
        with self.assertRaises(LocalWorkerFundingUnavailable):
            OriginalWorkerPipeChannel(self.funding, self.process, None)
        self.assertEqual(self.case.case.os_open.call_count, before)
        self.case.os_posix_spawn.assert_not_called()

    async def test_non_nominal_bootstrap_refuses_before_slot_and_spawn(self):
        self.control.bootstrap = True; before = self.case.case.os_open.call_count
        with self.assertRaises(LocalWorkerDriverPending): await self.driver.start()
        self.assertEqual(self.case.case.os_open.call_count, before)
        self.case.os_posix_spawn.assert_not_called(); self.assert_no_execution_ack()

    async def test_funding_retirement_during_bootstrap_blocks_physical_start(self):
        self.control.bootstrap_hook = self.funding.close
        with self.assertRaises(LocalWorkerDriverPending): await self.driver.start()
        self.case.os_posix_spawn.assert_not_called()

    async def test_existing_sdk_connect_uses_one_original_process_and_channel(self):
        await self.driver.start()
        client = await AsyncClient._connect_local(self.driver)
        self.assertIs(self.control.calls[0][1], self.process)
        self.assertEqual(self.control.calls[0][0], 'bootstrap')
        self.assertEqual(self.case.os_posix_spawn.call_count, 1)
        self.assertIn(('exchange', self.process, self.channel._pipe, 'connect', PAYLOAD), self.control.calls)
        await client.aclose()
        self.assertTrue(self.process._parent_closed)
        self.assertEqual(sum(c[0] == 'close' for c in self.control.calls), 1)
        # Funding retirement is the separate original supplier pass, not
        # inferred by the assembly from Host ACK or parent descriptor close.
        self.assertEqual(sum(c[0] == 'close' for c in self.case.case.case.supplier.calls), 1)
        self.assertFalse(any(c[0] in ('stop_scope', 'settle') for c in self.case.case.case.supplier.calls))

    async def test_lost_start_reply_keeps_original_bootstrap_process_and_no_restart(self):
        self.control.start_error = OSError('Original startup reply lost')
        with self.assertRaises(LocalWorkerDriverPending): await self.driver.start()
        self.assertEqual(self.process._pid, 4321); self.assertIs(self.channel._bootstrap, self.control.bootstrap)
        with self.assertRaises(RuntimeError): await self.driver.start()
        self.case.os_posix_spawn.assert_called_once(); self.assert_no_execution_ack()

    async def test_truthy_start_ack_is_not_ready(self):
        self.control.start_ack = True
        with self.assertRaises(LocalWorkerDriverPending): await self.driver.start()
        self.assertFalse(self.driver._ready); self.assertFalse(self.channel._ready)

    async def test_post_current_failure_keeps_response_and_blocks_second_exchange(self):
        await self.driver.start()
        def current():
            if self.control.responses: raise ValueError('Original current revoked')
        self.control.current_hook = current
        with self.assertRaises(ValueError): await self.driver.open('connect', PAYLOAD)
        self.assertIs(self.control.responses[0], self.control.response)
        self.control.current_hook = None
        with self.assertRaises(ValueError): await self.driver.open('connect', PAYLOAD)
        self.assertEqual(sum(c[0] == 'exchange' for c in self.control.calls), 1)
        self.assert_no_execution_ack()

    async def test_caller_cancellation_does_not_start_another_exchange_or_cancel_run(self):
        await self.driver.start(); self.control.exchange_error = asyncio.CancelledError()
        with self.assertRaises(asyncio.CancelledError): await self.driver.open('connect', PAYLOAD)
        self.control.exchange_error = None
        with self.assertRaises(ValueError): await self.driver.open('connect', PAYLOAD)
        self.assertIs(self.control.responses[0], self.control.response)
        self.assert_no_execution_ack()

    async def test_host_close_ack_is_not_repeated_after_parent_descriptor_unknown(self):
        await self.driver.start()
        def close(fd):
            if fd == 22: raise OSError('Original parent descriptor close unknown')
        self.case.case.os_close.side_effect = close
        for _ in range(2):
            with self.assertRaises(LocalWorkerDriverPending): await self.driver.aclose()
        self.assertEqual(sum(c[0] == 'close' for c in self.control.calls), 1)
        self.assertEqual(sum(c.args == (22,) for c in self.case.case.os_close.call_args_list), 1)
        self.assertFalse(self.channel._closed); self.assertFalse(self.driver._closed)
        self.assert_no_execution_ack()
