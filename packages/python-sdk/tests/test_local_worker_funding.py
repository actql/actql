"""Mandatory funding/Owner port doubles only; no worker, Engine or quota proof."""
import copy
import unittest

from actql_sdk._local_core import LocalCoreResources
from actql_sdk._local_worker_funding import (OriginalWorkerFunding, _WorkerFundingSupplier,
    LocalWorkerFundingUnavailable, LocalWorkerFundingPending)
import test_local_distribution as distribution


class Supplier(_WorkerFundingSupplier):
    def __init__(self):
        super().__init__()
        self.physical, self.ledger, self.delegation, self.durable, self.stop = (object() for _ in range(5))
        self.calls = []; self.fail_durable = False; self.fail_close = False
        self.deny_launch = False; self.deny_stop = False; self.stop_ack = None
    def acquire_pre_spawn(self, components):
        self.calls.append(('acquire', components)); return self.physical
    def original_ledger(self, physical):
        self.calls.append(('ledger', physical)); return self.ledger
    def reserve_execution_delegation(self, ledger, limits, retained, execution):
        self.calls.append(('reserve', ledger, limits, retained, execution)); return self.delegation
    def preserve_original_delegation(self, physical, ledger, delegation):
        self.calls.append(('durable', physical, ledger, delegation))
        if self.fail_durable: raise OSError('Original durable write outcome is unknown')
        return self.durable
    def require_launch_originals(self, physical, ledger, delegation, durable):
        self.calls.append(('launch_current', physical, ledger, delegation, durable))
        if self.deny_launch: raise ValueError('Original current funding denied')
    def report_execution_delegation(self, ledger, delegation, usage):
        self.calls.append(('report', ledger, delegation, usage))
    def require_scoped_stop(self, physical, ledger, delegation, durable, observation):
        self.calls.append(('stop_scope', physical, ledger, delegation, durable, observation))
        if self.deny_stop or observation is not self.stop: raise ValueError('Foreign original stop')
        return self.stop_ack
    def settle_execution_delegation(self, ledger, delegation, final_usage):
        self.calls.append(('settle', ledger, delegation, final_usage))
    def close_original_funding(self, physical, ledger, delegation, durable):
        self.calls.append(('close', physical, ledger, delegation, durable))
        if self.fail_close: raise OSError('Original close is pending')


class WorkerFundingTests(unittest.TestCase):
    def setUp(self):
        self.case = distribution.LocalDistributionTests(); self.case.setUp()
        self.addCleanup(self.case.doCleanups)
        self.components = self.case.inspect(); self.supplier = Supplier()
        # Independent interface fixture, not an adopted product profile.
        self.limits = LocalCoreResources(1, 2, 3, 4, 5, 6)
    def prepare(self, **changes):
        options = {'limits': self.limits, 'retained': 5, 'execution': 6} | changes
        return OriginalWorkerFunding(self.components, self.supplier, **options)
    def test_missing_or_boolean_supplier_cannot_be_replaced_by_declared_numbers(self):
        for supplier in (None, True, object()):
            with self.assertRaises(LocalWorkerFundingUnavailable):
                OriginalWorkerFunding(self.components, supplier, limits=self.limits, retained=5, execution=6)
        self.assertEqual(self.supplier.calls, [])
    def test_missing_numeric_profile_refuses_before_any_acquire_or_reserve(self):
        for options in ({'limits': None}, {'retained': None}, {'execution': None}, {'execution': True}):
            with self.assertRaises(LocalWorkerFundingUnavailable): self.prepare(**options)
        self.assertEqual(self.supplier.calls, [])
    def test_original_funding_ledger_and_durable_custody_precede_launch(self):
        value = self.prepare(); value.require_launch()
        self.assertEqual([c[0] for c in self.supplier.calls], ['acquire', 'ledger', 'reserve', 'durable', 'launch_current'])
        self.assertEqual(self.supplier.calls[2], ('reserve', self.supplier.ledger, self.limits, 5, 6))
    def test_copied_carrier_or_reused_supplier_cannot_acquire_another_claim(self):
        value = self.prepare()
        with self.assertRaises(TypeError): copy.copy(value)
        with self.assertRaises(TypeError): copy.deepcopy(value)
        with self.assertRaises(TypeError): copy.copy(self.supplier)
        clone = OriginalWorkerFunding.__new__(OriginalWorkerFunding); clone.__dict__.update(value.__dict__)
        with self.assertRaises(ValueError): clone.require_launch()
        with self.assertRaises(ValueError): self.prepare()
        self.assertEqual(sum(c[0] == 'acquire' for c in self.supplier.calls), 1)
    def test_boolean_physical_funding_does_not_reach_common_reservation(self):
        self.supplier.physical = True
        with self.assertRaises(LocalWorkerFundingPending) as caught: self.prepare()
        value = caught.exception.cleanup_funding
        with self.assertRaises(LocalWorkerFundingUnavailable): value.require_launch()
        self.assertEqual([c[0] for c in self.supplier.calls], ['acquire'])
    def test_durable_unknown_keeps_original_refs_without_reserve_or_spawn_retry(self):
        self.supplier.fail_durable = True
        with self.assertRaises(LocalWorkerFundingPending) as caught: self.prepare()
        value = caught.exception.cleanup_funding
        self.assertIs(value._physical, self.supplier.physical)
        self.assertIs(value._delegation, self.supplier.delegation)
        with self.assertRaises(LocalWorkerFundingUnavailable): value.require_launch()
        value.close()
        self.assertEqual(sum(c[0] == 'reserve' for c in self.supplier.calls), 1)
        self.assertEqual(self.supplier.calls[-1], ('close', self.supplier.physical,
            self.supplier.ledger, self.supplier.delegation, None))
    def test_current_refusal_blocks_reporting_without_changing_custody(self):
        value = self.prepare(); self.supplier.deny_launch = True
        with self.assertRaises(ValueError): value.report(object())
        self.assertFalse(any(c[0] == 'report' for c in self.supplier.calls))
        self.assertIs(value._delegation, self.supplier.delegation)
    def test_usage_is_forwarded_to_common_with_original_ledger_and_delegation(self):
        value = self.prepare(); usage = object(); value.report(usage)
        self.assertEqual(self.supplier.calls[-1], ('report', self.supplier.ledger, self.supplier.delegation, usage))
    def test_boolean_pid_and_foreign_stop_cannot_settle(self):
        value = self.prepare()
        for observation in (True, 1234, None, {'stopped': True}, object()):
            with self.assertRaises(ValueError): value.settle_stopped(observation, final_usage=None)
        self.assertFalse(any(c[0] == 'settle' for c in self.supplier.calls))
    def test_truthy_stop_ack_is_not_owner_confirmation(self):
        value = self.prepare(); self.supplier.stop_ack = True
        with self.assertRaises(RuntimeError): value.settle_stopped(self.supplier.stop, final_usage=None)
        self.assertFalse(any(c[0] == 'settle' for c in self.supplier.calls))
    def test_unknown_final_usage_stays_none_for_common_conservative_settlement(self):
        value = self.prepare(); value.settle_stopped(self.supplier.stop, final_usage=None)
        self.assertEqual(self.supplier.calls[-1], ('settle', self.supplier.ledger, self.supplier.delegation, None))
        self.assertFalse(value._closed)  # Store/Provider/funding cleanup is separate.
    def test_failed_close_retains_same_carrier_and_success_is_not_repeated(self):
        value = self.prepare(); self.supplier.fail_close = True
        with self.assertRaises(OSError): value.close()
        self.assertFalse(value._closed); self.assertIs(value._physical, self.supplier.physical)
        with self.assertRaises(LocalWorkerFundingUnavailable): value.require_launch()
        self.supplier.fail_close = False; value.close(); value.close()
        self.assertEqual(sum(c[0] == 'close' for c in self.supplier.calls), 2)
        self.assertEqual(sum(c[0] == 'reserve' for c in self.supplier.calls), 1)
    def test_current_callback_close_cannot_return_launch_or_report_success(self):
        value = self.prepare()
        self.supplier.require_launch_originals = lambda *args: value.close()
        with self.assertRaises(ValueError): value.report(object())
        self.assertFalse(any(c[0] == 'report' for c in self.supplier.calls))
    def test_stop_callback_close_cannot_settle_a_retired_carrier(self):
        value = self.prepare()
        self.supplier.require_scoped_stop = lambda *args: value.close()
        with self.assertRaises(ValueError): value.settle_stopped(self.supplier.stop, final_usage=None)
        self.assertFalse(any(c[0] == 'settle' for c in self.supplier.calls))
    def test_close_callback_reentry_does_not_repeat_physical_close(self):
        value = self.prepare(); calls = []
        def closing(*args):
            calls.append(args); value.close()
        self.supplier.close_original_funding = closing
        with self.assertRaises(RuntimeError): value.close()
        self.assertEqual(len(calls), 1)
        self.assertFalse(value._closed)
