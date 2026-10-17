"""Original pre-spawn/frame transport counters; no actual child/VM/funding."""
import copy
from ctypes import c_void_p
import unittest
from unittest.mock import patch

from actql_sdk._local_native_live_channel import (
    _OriginalLiveChannelCustody, _OriginalLivePreparationFunctions, _OriginalLiveChannelError,
)
from test_local_native_live_channel import ChannelFixture
from test_local_native_control_custody import Function


class PreparationFixture(ChannelFixture):
    def __init__(self, test):
        super().__init__(test, spawn=False)
        self.frame_present = True
        self.frame_issue = 0
        self.frame_issues = {}
        self.frame_fault = self.frame_finish_fault = None
        self.child_fault = None
        self.frame_hook = None
        functions = {
            'actql_live_channel_prepare_before_spawn_into': self.before,
            'actql_live_channel_bind_child_into': self.child,
            'actql_channel_ledger_prepare_into': self.frame_prepare,
            'actql_channel_ledger_operate_into': self.frame_operate,
            'actql_channel_ledger_originals_into': self.frame_originals,
            'actql_channel_ledger_operation': lambda p: self.facts[p.value][0],
            'actql_channel_ledger_issue_family': lambda p: self.facts[p.value][1],
            'actql_channel_ledger_copy_limits': self.frame_limits,
            'actql_channel_ledger_drop_reply': self.frame_drop,
            'actql_channel_ledger_finish_retired_data': self.frame_finish,
        }
        for name, call in functions.items(): setattr(self.library, name, Function(call))
        self.preparation_functions = _OriginalLivePreparationFunctions(self.library)

    def before(self, host, domain, read, write, nonce, reply):
        self.events.append(('before', read, write, nonce))
        self.result(reply, 10, self.prepare_issue)
        if self.hook: self.hook()
        if self.prepare_fault: raise self.prepare_fault
        return 0

    def child(self, host, domain, channel, pid, reply):
        self.events.append(('child', pid))
        self.result(reply, 11, self.issues.get(11, 0))
        if self.child_fault: raise self.child_fault
        return 0

    def frame_prepare(self, host, domain, channel, reply):
        self.events.append(('frame_prepare', host.value, domain.value, channel.value))
        self.result(reply, 1, self.frame_issue)
        if self.frame_fault: raise self.frame_fault
        return 0

    def frame_originals(self, reply, host, domain, channel, frame):
        host._obj.value, domain._obj.value, channel._obj.value = 101, 301, 401
        if self.frame_present: frame._obj.value = 501
        self.events.append(('frame_originals', frame._obj.value))
        return 0

    def frame_operate(self, host, domain, channel, frame, operation, retained, execution, reply):
        self.events.append(('frame_operate', frame.value, operation, retained, execution))
        self.result(reply, operation, self.frame_issues.get(operation, 0))
        if self.frame_hook: self.frame_hook()
        return 0

    def frame_limits(self, reply, host, domain, channel, frame, out):
        out[:] = self.native_limits
        return 0

    def frame_drop(self, reply, host, domain, channel, frame):
        self.events.append(('frame_drop', reply._obj.value))
        reply._obj.value = None
        return 0

    def frame_finish(self, host, domain, channel, frame, reply, retired):
        # Independent expected protocol, not product-derived counts.
        assert self.facts[retired.value] == (8, 0)
        assert self.facts[reply._obj.value] == ((8, 0) if frame._obj.value is not None else (1, self.frame_issue))
        self.events.append(('frame_finish', frame._obj.value))
        for slot in (host, domain, channel, frame, reply): slot._obj.value = None
        if self.frame_finish_fault: raise self.frame_finish_fault
        return 0

    def take_prepared(self):
        return _OriginalLiveChannelCustody._prepare_original(self.domain, self.process,
            self.pipe, self.preparation_functions, nonce=7)

    def prepare(self):
        self.process.prepare_original_descriptors()
        return self.take_prepared()


class OriginalChannelPreparationTests(unittest.TestCase):
    def test_missing_exports_do_not_fall_back_to_legacy_post_spawn(self):
        f = PreparationFixture(self)
        del f.library.actql_channel_ledger_prepare_into
        with self.assertRaises(AttributeError): _OriginalLivePreparationFunctions(f.library)
        self.assertEqual(f.events, [])

    def test_prepare_requires_original_prepared_descriptors_and_never_spawns(self):
        f = PreparationFixture(self)
        with self.assertRaises(ValueError): f.take_prepared()
        self.assertEqual(f.events, [])
        c = f.prepare()
        self.assertIsNone(f.process._pid)
        self.assertFalse(f.process._spawn_syscall_attempted)
        self.assertFalse(f.process._native_duplicate.closed)
        self.assertIn(('before', 23, 22, 7), f.events)
        self.assertEqual(c._channel.value, 401)
        with self.assertRaises(ValueError): f.take_prepared()
        self.assertEqual(sum(e[0] == 'before' for e in f.events), 1)
        with self.assertRaises(ValueError): c.admit()
        with self.assertRaises(ValueError): c.bind_original_vm(f.span())
        self.assertFalse(any(e[0] == 'bind' for e in f.events))

    def test_same_actual_spawn_pid_binds_once_before_vm_dispatch(self):
        f = PreparationFixture(self); c = f.prepare()
        with self.assertRaises(ValueError): c.bind_original_child()
        f.process.spawn()
        # No resource/control call treats the changed phase as already bound.
        with self.assertRaises(ValueError): c.require_original_frame_current()
        c.bind_original_child()
        self.assertTrue(c._child_bound)
        self.assertIn(('child', 4321), f.events)
        with self.assertRaises(ValueError): c.bind_original_child()
        c.bind_original_vm(f.span())
        self.assertEqual(sum(e[0] == 'child' for e in f.events), 1)

    def test_lost_spawn_reply_never_guesses_or_binds_a_child(self):
        f = PreparationFixture(self); c = f.prepare()
        with patch('actql_sdk._local_worker_process.os.posix_spawn', side_effect=OSError('Lost spawn')):
            with self.assertRaises(RuntimeError): f.process.spawn()
        with self.assertRaises(ValueError): c.bind_original_child()
        with self.assertRaises(ValueError): c.stop()
        self.assertFalse(any(e[0] == 'child' for e in f.events))
        self.assertIs(f.domain._live_channel_original, c)

    def test_lost_child_binding_is_same_unknown_with_no_retry(self):
        f = PreparationFixture(self); c = f.prepare(); f.process.spawn()
        f.child_fault = OSError('Lost binding')
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.bind_original_child()
        self.assertTrue(caught.exception.unknown)
        self.assertIs(caught.exception.cleanup_channel, c)
        with self.assertRaises(ValueError): c.bind_original_child()
        self.assertEqual(sum(e[0] == 'child' for e in f.events), 1)
        self.assertEqual(c._channel.value, 401)

    def test_busy_entry_refusal_does_not_poison_original_or_take_busy(self):
        f = PreparationFixture(self); f.process.prepare_original_descriptors()
        f.host._busy = True
        with self.assertRaises(ValueError): f.take_prepared()
        self.assertTrue(f.host._busy)
        self.assertIsNone(f.domain._live_channel_original)
        self.assertIsNone(f.pipe._native_channel_original)
        self.assertEqual(f.events, [])
        f.host._busy = False
        c = f.take_prepared()
        self.assertIsNone(c._unknown)

    def test_frame_uses_same_aliases_and_common_limits_not_python_ledger(self):
        f = PreparationFixture(self); c = f.prepare()
        before = [v for v in f.supplier.calls if v[0] != 'launch_current']
        c.prepare_original_frame(); c.start_original_frame()
        c.reserve_original_bootstrap(retained=17, execution=2**53 + 1)
        c.require_original_frame_current(); c.require_original_bootstrap_current()
        self.assertEqual(c.original_frame_limits(), f.native_limits)
        self.assertEqual(c.original_frame_limits()[3], 2**53 + 1)
        c.report_original_frame(); c.stop_original_frame()
        self.assertEqual([v for v in f.supplier.calls if v[0] != 'launch_current'], before)
        self.assertIn(('frame_operate', 501, 3, 17, 2**53 + 1), f.events)
        self.assertFalse(c._closed)
        self.assertFalse(any(e[0] in ('finish', 'frame_finish') for e in f.events))
        with self.assertRaises(ValueError): c.prepare_original_frame()

    def test_nonrepresentable_resource_amounts_refuse_before_native(self):
        f = PreparationFixture(self); c = f.prepare(); c.prepare_original_frame()
        for values in ({'retained': True, 'execution': 1}, {'retained': 0, 'execution': True},
                {'retained': -1, 'execution': 1}, {'retained': 0, 'execution': 0},
                {'retained': 0, 'execution': 2**63}, {'retained': 1.0, 'execution': 1}):
            before = list(f.events)
            with self.assertRaises(ValueError): c.reserve_original_bootstrap(**values)
            self.assertEqual(f.events, before)

    def test_partial_known_frame_refusal_keeps_original_cleanup_carrier(self):
        f = PreparationFixture(self); c = f.prepare(); f.frame_issue = 9
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.prepare_original_frame()
        self.assertFalse(caught.exception.unknown)
        self.assertEqual(c._frame.value, 501)
        self.assertIs(f.domain._live_channel_original, c)
        with self.assertRaises(ValueError): c.prepare_original_frame()

    def test_child_unknown_is_not_known_refusal_or_zero_limits(self):
        f = PreparationFixture(self); c = f.prepare(); c.prepare_original_frame()
        f.frame_issues[5] = 10
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.original_frame_limits()
        self.assertTrue(caught.exception.unknown)
        before = list(f.events)
        with self.assertRaises(_OriginalLiveChannelError): c.report_original_frame()
        self.assertEqual(f.events, before)
        self.assertIsNotNone(c._frame_reply.value)

    def test_frame_alias_mutation_in_callback_is_unknown_before_success(self):
        f = PreparationFixture(self); c = f.prepare(); c.prepare_original_frame()
        f.frame_hook = lambda: setattr(c._frame, 'value', 999)
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.require_original_frame_current()
        self.assertTrue(caught.exception.unknown)
        self.assertEqual(c._frame.value, 999)
        self.assertIs(f.domain._live_channel_original, c)

    def test_retirement_requires_original_acks_and_both_typed_native_results(self):
        f = PreparationFixture(self); c = f.prepare(); c.prepare_original_frame(); c.start_original_frame()
        before = list(f.events)
        with self.assertRaises(ValueError): c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertEqual(f.events, before)
        f.close_host_pipe()
        c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertTrue(c._closed)
        self.assertTrue(f.process._native_metadata_retired)
        self.assertIsNone(f.process._pid)
        self.assertLess(f.events.index(('frame_operate', 501, 8, 0, 0)),
                        next(i for i, e in enumerate(f.events) if e[:2] == ('operate', 8)))
        self.assertLess(f.events.index(('frame_finish', 501)),
                        next(i for i, e in enumerate(f.events) if e[0] == 'finish'))
        before = list(f.events)
        c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertEqual(f.events, before)

    def test_no_frame_known_refusal_needs_original_channel_retire_before_alias_release(self):
        f = PreparationFixture(self); c = f.prepare(); f.frame_present = False; f.frame_issue = 9
        with self.assertRaises(_OriginalLiveChannelError): c.prepare_original_frame()
        self.assertIsNotNone(c._frame_reply.value)
        f.close_host_pipe(); c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertIn(('frame_finish', None), f.events)
        self.assertFalse(any(e[:3] == ('frame_operate', 501, 8) for e in f.events))

    def test_lost_alias_retirement_response_keeps_unknown_even_when_slots_clear(self):
        f = PreparationFixture(self); c = f.prepare(); c.prepare_original_frame()
        f.close_host_pipe(); f.frame_finish_fault = OSError('Retirement reply lost')
        with self.assertRaises(_OriginalLiveChannelError) as caught: c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertTrue(caught.exception.unknown)
        self.assertIsNone(c._frame.value)
        self.assertFalse(c._closed)
        self.assertFalse(f.process._native_metadata_retired)
        self.assertIs(f.domain._live_channel_original, c)
        before = list(f.events)
        with self.assertRaises(_OriginalLiveChannelError): c.retire_after_owner_ack(f.channel, f.supplier.stop)
        self.assertEqual(f.events, before)

    def test_copied_record_cannot_capture_child_or_use_frame(self):
        f = PreparationFixture(self); c = f.prepare()
        with self.assertRaises(TypeError): copy.copy(c)
        clone = _OriginalLiveChannelCustody.__new__(_OriginalLiveChannelCustody)
        for name in c.__slots__: setattr(clone, name, getattr(c, name))
        with self.assertRaises(ValueError): clone.prepare_original_frame()
        self.assertFalse(any(e[0] == 'frame_prepare' for e in f.events))
