"""Thin worker/Wire component tests; physical process and Common Owner0."""
import asyncio
import copy
import unittest
import httpx

from actql_sdk._local_worker_driver import (_OriginalWorkerChannel, OriginalWorkerDriver,
    LocalWorkerDriverPending)
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
import test_local_worker_funding as funding_fixture

PAYLOAD = b'{"connection":{"mode":"local","owner":"local","durability":"durable","consentRefs":[],"runners":[]}}'


class Channel(_OriginalWorkerChannel):
    def __init__(self, funding):
        super().__init__(funding)
        self.calls = []; self.start_error = None; self.exchange_error = None
        self.close_error = None; self.current_error = None; self.current_hook = None
        self.start_ack = None; self.response = httpx.Response(200, json={'independent': True})
    async def start_original(self):
        self.calls.append(('start',))
        if self.start_error: raise self.start_error
        return self.start_ack
    def require_current_original(self):
        self.calls.append(('current',))
        if self.current_hook: self.current_hook()
        if self.current_error: raise self.current_error
    async def exchange_original(self, operation, payload):
        self.calls.append(('exchange', operation, payload))
        if self.exchange_error: raise self.exchange_error
        return self.response
    async def close_original(self):
        self.calls.append(('close',))
        if self.close_error: raise self.close_error


class WorkerDriverTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.case = funding_fixture.WorkerFundingTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.funding = self.case.prepare(); self.channel = Channel(self.funding)
        self.driver = OriginalWorkerDriver(self.funding, lambda original: self.channel)
    async def test_missing_funding_refuses_before_channel_factory(self):
        calls = []
        with self.assertRaises(LocalWorkerFundingUnavailable):
            OriginalWorkerDriver(None, lambda original: calls.append(original))
        self.assertEqual(calls, [])
    async def test_start_once_and_forward_exact_local_wire_without_response_reinterpretation(self):
        await self.driver.start()
        self.channel.response = httpx.Response(503, json={'independent': 'not a success'})
        response = await self.driver.open('connect', PAYLOAD)
        self.assertIs(response, self.channel.response)
        self.assertEqual(response.status_code, 503)
        self.assertIn(('exchange', 'connect', PAYLOAD), self.channel.calls)
        with self.assertRaises(RuntimeError): await self.driver.start()
        self.assertEqual(self.channel.calls.count(('start',)), 1)
    async def test_unstarted_and_unknown_start_cannot_exchange_or_restart(self):
        with self.assertRaises(LocalWorkerFundingUnavailable): await self.driver.open('connect', PAYLOAD)
        self.channel.start_error = OSError('Original child start reply lost')
        with self.assertRaises(LocalWorkerDriverPending) as caught: await self.driver.start()
        self.assertIs(caught.exception.cleanup_driver, self.driver)
        with self.assertRaises(RuntimeError): await self.driver.start()
        with self.assertRaises(LocalWorkerFundingUnavailable): await self.driver.open('connect', PAYLOAD)
        self.assertFalse(any(c[0] == 'exchange' for c in self.channel.calls))
    async def test_truthy_start_return_never_becomes_ready(self):
        self.channel.start_ack = True
        with self.assertRaises(LocalWorkerDriverPending): await self.driver.start()
        self.assertFalse(self.driver._ready)
    async def test_wrong_duplicate_oversized_and_mutable_requests_reject_before_channel(self):
        await self.driver.start()
        bad = [bytearray(PAYLOAD), b'{"connection":null,"connection":null}',
               b'x' * 1048577, PAYLOAD.replace(b'local', b'remote')]
        for payload in bad:
            with self.assertRaises((ValueError, TypeError)): await self.driver.open('connect', payload)
        with self.assertRaises(ValueError): await self.driver.open('unknown-operation', PAYLOAD)
        self.assertFalse(any(c[0] == 'exchange' for c in self.channel.calls))
    async def test_response_loss_is_one_exchange_and_original_refs_remain(self):
        await self.driver.start(); self.channel.exchange_error = OSError('Lost original operation reply')
        with self.assertRaises(OSError): await self.driver.open('connect', PAYLOAD)
        self.assertEqual(sum(c[0] == 'exchange' for c in self.channel.calls), 1)
        self.assertIs(self.driver._funding, self.funding)
        self.assertFalse(any(c[0] == 'settle' for c in self.case.supplier.calls))
    async def test_current_denial_does_not_send_and_post_denial_does_not_return_response(self):
        await self.driver.start(); self.channel.current_error = ValueError('Current original denied')
        with self.assertRaises(ValueError): await self.driver.open('connect', PAYLOAD)
        self.assertFalse(any(c[0] == 'exchange' for c in self.channel.calls))
        self.channel.current_error = None
        def revoke():
            if any(c[0] == 'exchange' for c in self.channel.calls): raise ValueError('Revoked after exchange')
        self.channel.current_hook = revoke
        with self.assertRaises(ValueError): await self.driver.open('connect', PAYLOAD)
        self.assertIs(self.driver._channel.response, self.channel.response)  # Channel retains custody.
    async def test_coroutine_cancellation_is_not_restart_stop_or_run_cancel(self):
        await self.driver.start(); self.channel.exchange_error = asyncio.CancelledError()
        with self.assertRaises(asyncio.CancelledError): await self.driver.open('connect', PAYLOAD)
        self.assertEqual(self.channel.calls.count(('start',)), 1)
        self.assertFalse(any(c[0] in ('settle', 'close') for c in self.case.supplier.calls))
    async def test_host_close_ack_is_retained_when_funding_cleanup_fails(self):
        await self.driver.start(); self.case.supplier.fail_close = True
        with self.assertRaises(LocalWorkerDriverPending) as caught: await self.driver.aclose()
        self.assertIs(caught.exception.cleanup_driver, self.driver)
        self.assertFalse(self.driver._closed)
        with self.assertRaises(ValueError): await self.driver.open('connect', PAYLOAD)
        self.case.supplier.fail_close = False; await self.driver.aclose(); await self.driver.aclose()
        self.assertEqual(self.channel.calls.count(('close',)), 1)
        self.assertEqual(sum(c[0] == 'close' for c in self.case.supplier.calls), 2)
    async def test_channel_close_unknown_retains_funding_without_settlement(self):
        await self.driver.start(); self.channel.close_error = OSError('Original close unknown')
        with self.assertRaises(LocalWorkerDriverPending): await self.driver.aclose()
        self.assertFalse(self.driver._closed)
        self.assertFalse(any(c[0] in ('settle', 'close') for c in self.case.supplier.calls))
    async def test_foreign_channel_factory_failure_does_not_close_foreign_custody(self):
        other = funding_fixture.WorkerFundingTests(); other.setUp(); self.addCleanup(other.doCleanups)
        foreign = Channel(other.prepare())
        fresh = funding_fixture.WorkerFundingTests(); fresh.setUp(); self.addCleanup(fresh.doCleanups)
        with self.assertRaises(LocalWorkerDriverPending) as caught:
            OriginalWorkerDriver(fresh.prepare(), lambda original: foreign)
        await caught.exception.cleanup_driver.aclose()
        self.assertEqual(foreign.calls, [])
    async def test_copied_driver_and_reused_channel_cannot_start(self):
        with self.assertRaises(TypeError): copy.copy(self.driver)
        with self.assertRaises(TypeError): copy.deepcopy(self.driver)
        with self.assertRaises(TypeError): copy.copy(self.channel)
        clone = OriginalWorkerDriver.__new__(OriginalWorkerDriver); clone.__dict__.update(self.driver.__dict__)
        with self.assertRaises(ValueError): await clone.start()
        with self.assertRaises(ValueError): OriginalWorkerDriver(self.funding, lambda original: self.channel)
        self.assertEqual(self.channel.calls, [])
