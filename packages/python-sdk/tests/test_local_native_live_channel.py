"""Independent Native reply/funding/syscall counters; actual worker and VM0."""
import asyncio
import copy
from contextlib import ExitStack
from dataclasses import replace
import os
from pathlib import Path
import pickle
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_native_live_channel import (
    _OriginalLiveChannelCustody, _OriginalLiveChannelFunctions, _OriginalLiveChannelError,
)
from actql_sdk._local_native_vm import _OriginalVMSpanData
from actql_sdk._local_worker_channel import OriginalWorkerPipeChannel
from actql_sdk._local_worker_process import OriginalWorkerProcess
from actql_sdk._local_worker_slot import OriginalWorkerSlot
from actql_sdk._local_worker_funding import LocalWorkerFundingUnavailable
from test_local_native_domain_material import MaterialFixture
from test_local_native_control_custody import Function
import test_local_worker_funding as funding_fixture
from test_local_worker_channel import Control


class ChannelFixture:
    def __init__(self, test, *, before_process=None, spawn=True):
        previous = getattr(test, '_live_channel_fixture', None)
        if previous is not None:
            previous._cleanup.close()
        test._live_channel_fixture = self
        self._cleanup = ExitStack()
        test.addCleanup(self._cleanup.close)
        self.material = MaterialFixture()
        self.domain = self.material.take()
        self.host = self.material.host
        case = funding_fixture.WorkerFundingTests(); case.setUp(); self._cleanup.callback(case.doCleanups)
        self.supplier = case.supplier
        # Configure opaque original carriers before the existing constructor
        # consumes this scalar supplier. This is deliberately not real funding.
        self.supplier.physical = self.supplier.delegation = self.domain
        self.supplier.ledger = self.host
        self.funding = case.prepare()
        self.slot = OriginalWorkerSlot(self.funding, '/installed/slot')
        if before_process is not None: before_process(self)
        self.process = OriginalWorkerProcess(self.funding, self.slot,
            executable='/installed/python', executable_image='/installed/python',
            executable_link=None, executable_bytes=8192, executable_sha256='a' * 64,
            environment=(('LANG', 'C.UTF-8'),))
        for name, options in (
                ('OriginalWorkerProcess._verify_executable', {}),
                ('OriginalWorkerSlot.inheritance_action', {'return_value': (os.POSIX_SPAWN_DUP2, 10, 3)}),
                ('OriginalWorkerSlot.close', {}),
                ('os.pipe', {'side_effect': [(11, 12), (13, 14), (15, 16)]}),
                ('os.posix_spawn', {'return_value': 4321}),
                ('fcntl.fcntl', {'side_effect': iter([30, *range(21, 27)])}),
                ('os.fstat', {'return_value': SimpleNamespace(st_mode=stat.S_IFREG | 0o600, st_uid=os.geteuid(), st_size=65536, st_dev=2, st_ino=3)}),
                ('os.close', {})):
            module = 'actql_sdk._local_worker_process.' if name.startswith(('OriginalWorkerProcess', 'os.')) else 'actql_sdk._local_worker_slot.'
            self._cleanup.enter_context(patch(module + name, **options))
        self.channel = OriginalWorkerPipeChannel(self.funding, self.process, Control())
        self.pipe = self.channel._pipe
        if spawn: self.process.spawn()
        self.events, self.facts = [], {}
        self.prepare_issue = 0
        self.issues = {}
        self.present = True
        self.native_state = 0
        self.native_capacities = (16777216, 2**53 + 1)
        self.native_limits = (2, 1, 1, 2**53 + 1, 0, 16777216)
        self.prepare_fault = self.originals_fault = self.finish_fault = self.drop_fault = None
        self.wrong_operation = None
        self.hook = None
        calls = {'prepare_into': self.prepare, 'bind_into': self.bind,
                 'operate_into': self.operate, 'report_into': self.report,
                 'originals_into': self.originals, 'drop_reply': self.drop,
                 'finish_retired_data': self.finish, 'finish_refused_prepare': self.refused,
                 'copy_state': self.state, 'copy_limits': self.limits, 'copy_capacities': self.capacities,
                 'operation': lambda p: self.facts[p.value][0],
                 'issue_family': lambda p: self.facts[p.value][1]}
        self.library = self.host._functions.library
        for name, call in calls.items():
            setattr(self.library, 'actql_live_channel_' + name, Function(call))
        self.functions = _OriginalLiveChannelFunctions(self.library)

    def result(self, slot, operation, issue):
        key = 700 + len(self.facts)
        self.facts[key] = (self.wrong_operation or operation, issue)
        slot._obj.value = key

    def prepare(self, host, domain, pid, read, write, nonce, reply):
        self.events.append(('prepare', host.value, domain.value, pid, read, write, nonce))
        self.result(reply, 1, self.prepare_issue)
        if self.hook: self.hook()
        if self.prepare_fault: raise self.prepare_fault
        return 0

    def originals(self, reply, host, domain, channel):
        self.events.append(('originals', reply.value))
        host._obj.value, domain._obj.value = 101, 301
        if self.present: channel._obj.value = 401
        if self.originals_fault: raise self.originals_fault
        return 0

    def operate(self, host, domain, channel, operation, reply):
        self.events.append(('operate', operation, host.value, domain.value, channel.value))
        self.result(reply, operation, self.issues.get(operation, 0))
        if self.hook: self.hook()
        return 0

    def bind(self, host, domain, channel, nonce, offset, size, reply):
        self.events.append(('bind', nonce, offset, size))
        self.result(reply, 2, self.issues.get(2, 0))
        return 0

    def report(self, host, domain, channel, *values):
        self.events.append(('report', values[:-1]))
        self.result(values[-1], 6, self.issues.get(6, 0))
        return 0

    def drop(self, reply, host, domain, channel):
        self.events.append(('drop', reply._obj.value))
        reply._obj.value = None
        if self.drop_fault: raise self.drop_fault
        return 0

    def finish(self, host, domain, channel, reply):
        self.events.append(('finish', host._obj.value, domain._obj.value, channel._obj.value))
        host._obj.value = domain._obj.value = channel._obj.value = reply._obj.value = None
        if self.finish_fault: raise self.finish_fault
        return 0

    def refused(self, host, domain, reply):
        self.events.append(('refused', host._obj.value, domain._obj.value))
        host._obj.value = domain._obj.value = reply._obj.value = None
        return 0

    def state(self, reply, host, domain, channel, out):
        out._obj.value = self.native_state
        return 0

    def limits(self, reply, host, domain, channel, out):
        out[:] = self.native_limits
        return 0

    def take(self):
        return _OriginalLiveChannelCustody._capture_original(self.domain, self.process,
            self.pipe, self.functions, nonce=7)

    def span(self, **changes):
        return replace(_OriginalVMSpanData(self.material.source.decode(), bytes([31]) * 32,
            self.material.values, 7, 4096, 16777216), **changes)

    def close_host_pipe(self):
        asyncio.run(self.channel.close_original())


    def capacities(self, reply, host, domain, channel, out):
        self.events.append(('capacities', reply.value))
        for i, value in enumerate(self.native_capacities): out[i] = value
        return 0

class OriginalLiveChannelTests(unittest.TestCase):
    def test_original_domain_funding_and_physical_descriptors_are_bound_once(self):
        f = ChannelFixture(self); c = f.take()
        self.assertEqual(f.events[0], ('prepare', 101, 301, 4321, 23, 22, 7))
        self.assertIs(f.domain._live_channel_original, c)
        self.assertIs(f.pipe._native_channel_original, c)
        self.assertEqual(c._channel.value, 401)
        with self.assertRaises(ValueError): f.take()
        self.assertEqual(sum(e[0] == 'prepare' for e in f.events), 1)

    def test_missing_original_or_wrong_funding_does_not_call_native(self):
        for name in ('_physical', '_ledger', '_delegation'):
            f = ChannelFixture(self); setattr(f.funding, name, object())
            with self.assertRaises(ValueError): f.take()
            self.assertEqual(f.events, [])

    def test_capture_loss_keeps_persistent_slots_and_same_carrier_without_retry(self):
        f = ChannelFixture(self); f.prepare_fault = OSError('lost native return')
        with self.assertRaises(_OriginalLiveChannelError) as caught: f.take()
        c = caught.exception.cleanup_channel
        self.assertTrue(caught.exception.unknown)
        self.assertIsNotNone(c._reply.value)
        self.assertIs(c._domain, f.domain)
        before = list(f.events)
        for action in (c.state, c.limits, c.admit, c.stop, lambda: c.report((0,) * 13)):
            with self.assertRaises(_OriginalLiveChannelError) as again: action()
            self.assertIs(again.exception, caught.exception)
        self.assertEqual(before, f.events)
        self.assertFalse(f.host._busy)

    def test_partial_extraction_retains_all_returned_native_aliases(self):
        f = ChannelFixture(self); f.originals_fault = MemoryError('capture interrupted')
        with self.assertRaises(_OriginalLiveChannelError) as caught: f.take()
        c = caught.exception.cleanup_channel
        self.assertEqual((c._host.value, c._native_domain.value, c._channel.value), (101, 301, 401))
        self.assertIsNotNone(c._reply.value)
        self.assertFalse(f.host._busy)

    def test_known_partial_capture_retains_native_handle_and_independent_process(self):
        f = ChannelFixture(self); f.prepare_issue = 6
        with self.assertRaises(_OriginalLiveChannelError) as caught: f.take()
        c = caught.exception.cleanup_channel
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(caught.exception.fact.issue_family, 6)
        self.assertEqual(c._channel.value, 401)
        self.assertFalse(f.process._parent_closed)
        self.assertFalse(f.domain._closed)

    def test_no_channel_refusal_retires_only_extra_managed_aliases(self):
        f = ChannelFixture(self); f.prepare_issue = 1; f.present = False
        with self.assertRaises(_OriginalLiveChannelError) as caught: f.take()
        c = caught.exception.cleanup_channel
        self.assertFalse(caught.exception.unknown)
        self.assertTrue(c._closed)
        self.assertIsNot(f.domain._live_channel_original, c)
        self.assertIsNotNone(f.domain._live_channel_original)
        self.assertFalse(f.domain._closed or f.funding._closed or f.process._parent_closed)
        self.assertEqual((c._host.value, c._native_domain.value, c._channel.value, c._reply.value), (None,) * 4)

    def test_success_with_missing_original_handle_is_unknown(self):
        f = ChannelFixture(self); f.present = False
        with self.assertRaises(_OriginalLiveChannelError) as caught: f.take()
        self.assertTrue(caught.exception.unknown)
        self.assertIsNotNone(caught.exception.cleanup_channel._reply.value)

    def test_post_current_revocation_retains_already_captured_channel(self):
        f = ChannelFixture(self)
        f.hook = lambda: setattr(f.supplier, 'deny_launch', True)
        with self.assertRaises(_OriginalLiveChannelError) as caught: f.take()
        self.assertTrue(caught.exception.unknown)
        self.assertEqual(caught.exception.cleanup_channel._channel.value, 401)
        self.assertEqual(sum(e[0] == 'prepare' for e in f.events), 1)

    def test_descriptor_or_pid_mutation_after_capture_is_unknown(self):
        for field in ('descriptor', 'pid'):
            f = ChannelFixture(self)
            f.hook = (lambda: setattr(f.process._stdout[0], 'value', 99)) if field == 'descriptor' else (lambda: setattr(f.process, '_pid', 9999))
            with self.assertRaises(_OriginalLiveChannelError) as caught: f.take()
            self.assertTrue(caught.exception.unknown)
            self.assertEqual(caught.exception.cleanup_channel._channel.value, 401)

    def test_original_vm_data_matches_owner_material_before_one_binding(self):
        f = ChannelFixture(self); c = f.take(); c.bind_original_vm(f.span())
        self.assertIn(('bind', 7, 4096, 16777216), f.events)
        with self.assertRaises(ValueError): c.bind_original_vm(f.span())
        self.assertEqual(sum(e[0] == 'bind' for e in f.events), 1)

    def test_foreign_vm_material_is_not_bound_or_repaired(self):
        for changes in ({'source': 'f' * 40}, {'recipe': b'x' * 32},
                        {'material': (1,) * 15}, {'nonce': 8}, {'nonce': True},
                        {'length': True}, {'material': (True,) * 15}):
            f = ChannelFixture(self); c = f.take()
            with self.assertRaises(ValueError): c.bind_original_vm(f.span(**changes))
            self.assertFalse(any(e[0] == 'bind' for e in f.events))

    def test_failed_binding_is_not_reissued_as_new_permission(self):
        f = ChannelFixture(self); c = f.take(); f.issues[2] = 6
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.bind_original_vm(f.span())
        self.assertFalse(caught.exception.unknown)
        with self.assertRaises(ValueError): c.bind_original_vm(f.span())
        self.assertEqual(sum(e[0] == 'bind' for e in f.events), 1)

    def test_original_admission_is_one_shot_without_new_funding_reserve(self):
        f = ChannelFixture(self); c = f.take(); before = len(f.supplier.calls)
        c.admit()
        with self.assertRaises(ValueError): c.admit()
        self.assertEqual(sum(e[:2] == ('operate', 3) for e in f.events), 1)
        self.assertFalse(any(x[0] in ('reserve', 'acquire') for x in f.supplier.calls[before:]))

    def test_typed_open_and_exact_int64_limits_are_only_data(self):
        f = ChannelFixture(self); c = f.take()
        self.assertEqual(c.state(), 0)
        self.assertEqual(c.limits(), f.native_limits)
        self.assertEqual(c.limits()[3], 2**53 + 1)
        self.assertFalse(any(x[0] in ('settle', 'stop_scope') for x in f.supplier.calls))

    def test_closing_is_observable_but_open_cannot_bypass_current_funding(self):
        f = ChannelFixture(self); c = f.take(); f.native_state = 1; f.funding._closing = True
        self.assertEqual(c.state(), 1)
        f.native_state = 0
        with self.assertRaises(LocalWorkerFundingUnavailable): c.state()
        with self.assertRaises(LocalWorkerFundingUnavailable): c.limits()

    def test_unknown_state_or_wrong_operation_keeps_refusal_not_success(self):
        for change in ('state', 'operation'):
            f = ChannelFixture(self); c = f.take()
            if change == 'state': f.native_state = -1
            else: f.wrong_operation = 8
            with self.assertRaises(_OriginalLiveChannelError) as caught: c.state()
            self.assertTrue(caught.exception.unknown)
            self.assertIsNotNone(c._reply.value)

    def test_same_owner_baseline_capacities_preserve_int64_without_deriving_quota(self):
        f = ChannelFixture(self)
        original = f.take()
        before = [call for call in f.supplier.calls if call[0] != 'launch_current']
        self.assertEqual(original.capacities(), (16777216, 2**53 + 1))
        self.assertEqual([e for e in f.events if e[:2] == ('operate', 9)],
                         [('operate', 9, 101, 301, 401)])
        self.assertEqual([call for call in f.supplier.calls if call[0] != 'launch_current'], before)

    def test_capacity_refusal_retains_same_original_without_zero_fallback(self):
        f = ChannelFixture(self)
        original = f.take()
        f.issues[9] = 1
        with self.assertRaises(_OriginalLiveChannelError) as caught: original.capacities()
        self.assertFalse(caught.exception.unknown)
        self.assertIs(caught.exception.cleanup_channel, original)
        self.assertNotIn('capacities', [e[0] for e in f.events])
        self.assertFalse(original._closed)
        self.assertIs(f.pipe._native_channel_original, original)

    def test_invalid_capacity_pair_is_unknown_and_never_reissued(self):
        for pair in ((0, 3), (16777216, 0), (16777216, -1), (16777216, 2**63 - 1)):
            with self.subTest(pair=pair):
                f = ChannelFixture(self)
                original = f.take()
                f.native_capacities = pair
                with self.assertRaises(_OriginalLiveChannelError) as caught: original.capacities()
                self.assertTrue(caught.exception.unknown)
                before = list(f.events)
                with self.assertRaises(_OriginalLiveChannelError): original.capacities()
                self.assertEqual(f.events, before)

    def test_capacity_postcheck_revocation_keeps_observed_original_unknown(self):
        f = ChannelFixture(self)
        original = f.take()
        f.hook = lambda: setattr(f.funding, '_closing', True)
        with self.assertRaises(_OriginalLiveChannelError) as caught: original.capacities()
        self.assertTrue(caught.exception.unknown)
        self.assertIs(f.domain._live_channel_original, original)
        self.assertNotEqual(original._channel.value, None)

    def test_complete_usage_is_forwarded_without_python_accounting(self):
        f = ChannelFixture(self); c = f.take(); usage = (1, 2, 3, 2**53 + 1, 5, 6, 7, 8, 9, 10, 11, 12, 13)
        c.report(usage)
        self.assertIn(('report', usage), f.events)
        f.issues[6] = 8
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.report((-1,) + usage[1:])
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(caught.exception.fact.issue_family, 8)

    def test_nonrepresentable_usage_does_not_reach_native(self):
        f = ChannelFixture(self); c = f.take()
        before = list(f.events)
        for value in ((0,) * 10, [0] * 13, (False,) * 13, (2**31,) + (0,) * 12,
                      (0,) * 3 + (2**63,) + (0,) * 9, (0,) * 12 + (2**31,)):
            with self.assertRaises(ValueError): c.report(value)
        self.assertEqual(f.events, before)

    def test_logical_stop_never_supplies_process_host_or_fd_cleanup(self):
        f = ChannelFixture(self); c = f.take(); c.stop()
        c.stop()
        self.assertEqual(sum(e[:2] == ('operate', 7) for e in f.events), 1)
        self.assertFalse(f.pipe._closed or f.process._parent_closed or f.channel._host_close_confirmed)
        with self.assertRaises(ValueError): c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertFalse(any(e[0] == 'finish' for e in f.events))

    def test_host_parent_fd_ack_and_same_scoped_owner_retire_only_channel_metadata(self):
        f = ChannelFixture(self); c = f.take(); f.close_host_pipe()
        c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertTrue(c._closed)
        self.assertIsNot(f.domain._live_channel_original, c)
        self.assertIsNot(f.pipe._native_channel_original, c)
        self.assertFalse(f.domain._closed or f.host._closed or f.funding._closed)
        self.assertEqual((c._host.value, c._native_domain.value, c._channel.value, c._reply.value), (None,) * 4)
        before = list(f.events); c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertEqual(f.events, before)
        self.assertFalse(any(x[0] == 'settle' for x in f.supplier.calls))

    def test_boolean_or_missing_cleanup_observations_never_reach_owner_retirement(self):
        f = ChannelFixture(self); c = f.take(); f.close_host_pipe()
        before = list(f.events)
        for observation in (True, 4321, None):
            with self.assertRaises(ValueError): c.retire_after_owner_ack(f.channel, observation)
        f.channel._host_close_confirmed = False
        with self.assertRaises(ValueError): c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertEqual(f.events, before)

    def test_scoped_stop_denial_keeps_same_carrier_and_does_not_settle(self):
        f = ChannelFixture(self); c = f.take(); f.close_host_pipe(); f.supplier.deny_stop = True
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertTrue(caught.exception.unknown)
        self.assertEqual(c._channel.value, 401)
        self.assertFalse(any(e[:2] == ('operate', 8) for e in f.events))

    def test_cleanup_postcheck_cannot_reuse_retracted_host_ack(self):
        f = ChannelFixture(self); c = f.take(); f.close_host_pipe()
        original = f.supplier.require_scoped_stop
        def changed(*args):
            original(*args); f.channel._host_close_confirmed = False
        f.supplier.require_scoped_stop = changed
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertTrue(caught.exception.unknown)
        self.assertFalse(any(e[:2] == ('operate', 8) for e in f.events))

    def test_lost_finish_retains_unknown_even_after_native_slots_clear(self):
        f = ChannelFixture(self); c = f.take(); f.close_host_pipe(); f.finish_fault = OSError('lost finish')
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertTrue(caught.exception.unknown)
        self.assertFalse(c._closed)
        self.assertEqual((c._host.value, c._native_domain.value, c._channel.value, c._reply.value), (None,) * 4)
        before = list(f.events)
        with self.assertRaises(_OriginalLiveChannelError): c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertEqual(f.events, before)

    def test_changed_funding_or_foreign_thread_refuses_before_more_callbacks(self):
        f = ChannelFixture(self); c = f.take(); before = list(f.events)
        with patch('actql_sdk._local_native_live_channel.current_thread', return_value=object()):
            with self.assertRaises(ValueError): c.state()
        f.funding._delegation = object()
        with self.assertRaises(ValueError): c.state()
        self.assertEqual(f.events, before)

    def test_copy_serialization_and_closed_clone_never_acquire_original_custody(self):
        f = ChannelFixture(self); c = f.take()
        for action in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): action(c)
        clone = _OriginalLiveChannelCustody.__new__(_OriginalLiveChannelCustody)
        for name in c.__slots__: setattr(clone, name, getattr(c, name))
        clone._closed = True
        with self.assertRaises(ValueError): clone.retire_after_owner_ack(f.channel, f.supplier.stop)

    def test_missing_matching_export_has_no_compatibility_fallback(self):
        with self.assertRaises(AttributeError): _OriginalLiveChannelFunctions(SimpleNamespace())


if __name__ == '__main__':
    unittest.main()
