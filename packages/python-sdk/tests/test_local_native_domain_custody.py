"""Independent slot/call counters only; actual DLL acceptance is separate."""
import copy
import pickle
import unittest
from unittest.mock import patch
from test_local_native_backing_custody import BackingFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody
from actql_sdk._local_native_domain_custody import (
    _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainError,
)
from actql_sdk._local_worker_slot import _OriginalDescriptor


class DomainFixture:
    def __init__(self):
        self.backing = BackingFixture()
        self.host = self.backing.host
        self.scope = _OriginalBackingCustody._borrow_original(self.host, self.backing.functions)
        self.descriptor = _OriginalDescriptor(12)
        self.events, self.facts = [], {}
        self.prepare_issue = self.current_issue = self.close_issue = 0
        self.present = True
        self.prepare_fault = self.capture_fault = self.finish_fault = None
        self.wrong_operation = None
        self.live = False
        calls = {'prepare_into':self.prepare, 'originals_into':self.originals,
                 'drop_reply':self.drop, 'finish_closed_data':self.finish,
                 'finish_refused_prepare':self.refused,
                 'operation':lambda p:self.facts[p.value][0],
                 'issue_family':lambda p:self.facts[p.value][1]}
        for operation, name in ((2,'current'),(3,'transfer'),(4,'enter'),(5,'leave'),(6,'close')):
            calls[name+'_into'] = lambda h,d,r,op=operation:self.call(op,h,d,r)
        for name, call in calls.items():
            setattr(self.host._functions.library, 'actql_domain_'+name, Function(call))
        self.functions = _OriginalDomainFunctions(self.host._functions.library)

    def result(self, slot, op, issue):
        key = 500 + len(self.facts)
        self.facts[key] = (self.wrong_operation or op, issue)
        slot._obj.value = key

    def prepare(self, host, scope, fd, size, work, attempts, holdings, transfer, retained, execution, reply):
        self.events.append(('prepare',host.value,scope.value,fd))
        self.live = self.present
        self.result(reply,1,self.prepare_issue)
        if self.prepare_fault:raise self.prepare_fault
        return 0

    def originals(self, reply, host, domain):
        self.events.append(('capture',reply.value))
        host._obj.value=101
        if self.live:domain._obj.value=301
        if self.capture_fault:raise self.capture_fault
        return 0

    def drop(self, reply, host, domain):
        self.events.append(('drop',reply._obj.value))
        reply._obj.value=None
        return 0

    def refused(self, host, reply):
        self.events.append(('refused',host._obj.value))
        host._obj.value=reply._obj.value=None
        return 0

    def call(self, op, host, domain, reply):
        self.events.append(('call',op,host.value,domain.value))
        issue = self.current_issue if op==2 else self.close_issue if op==6 else 0
        self.result(reply,op,issue)
        return 0

    def finish(self, host, domain, reply):
        self.events.append(('finish',host._obj.value,domain._obj.value))
        host._obj.value=domain._obj.value=reply._obj.value=None
        self.live=False
        if self.finish_fault:raise self.finish_fault
        return 0

    def take(self):
        return _OriginalDomainCustody._prepare_original(self.host,self.scope,self.descriptor,self.functions,
            size=65536,work=2,attempts=1,holdings=1,transfer=3,retained=0,execution=65536)


class OriginalDomainCustodyTests(unittest.TestCase):
    def test_original_slots_and_independent_descriptor_survive_until_owner_cleanup(self):
        f=DomainFixture();d=f.take()
        self.assertIs(d._descriptor,f.descriptor)
        self.assertIs(d._scope,f.scope)
        self.assertEqual(d.current().operation,2)
        d.transfer()
        with d._physical_scope():pass
        d.close_after_stop();before=list(f.events);d.close_after_stop()
        self.assertEqual(f.events,before)
        self.assertTrue(d._closed)
        self.assertFalse(f.descriptor.close_attempted)
        self.assertFalse(f.scope._closed)
        self.assertFalse(f.host._closed)

    def test_response_loss_keeps_original_reply_fd_and_forbids_every_retry(self):
        f=DomainFixture();f.prepare_fault=OSError('lost prepare')
        with self.assertRaises(_OriginalDomainError) as r:f.take()
        d=r.exception.cleanup_domain
        self.assertTrue(r.exception.unknown)
        self.assertIs(d._descriptor,f.descriptor)
        self.assertIsNotNone(d._reply.value)
        before=list(f.events)
        for action in (d.current,d.transfer,d.close_after_stop):
            with self.assertRaises(_OriginalDomainError) as again:action()
            self.assertIs(again.exception,r.exception)
        self.assertEqual(f.events,before)

    def test_capture_failure_preserves_both_original_owned_slots(self):
        f=DomainFixture();f.capture_fault=MemoryError('lost capture')
        with self.assertRaises(_OriginalDomainError) as r:f.take()
        d=r.exception.cleanup_domain
        self.assertEqual((d._host.value,d._domain.value),(101,301))
        self.assertIsNotNone(d._reply.value)
        self.assertFalse(f.host._busy)

    def test_known_partial_prepare_requires_same_original_cleanup(self):
        f=DomainFixture();f.prepare_issue=6
        with self.assertRaises(_OriginalDomainError) as r:f.take()
        d=r.exception.cleanup_domain
        self.assertFalse(r.exception.unknown)
        self.assertEqual(d._domain.value,301)
        d.close_after_stop()
        self.assertTrue(d._closed)
        self.assertEqual(sum(e[0]=='prepare' for e in f.events),1)

    def test_no_domain_refusal_only_drops_original_data(self):
        f=DomainFixture();f.prepare_issue=1;f.present=False
        with self.assertRaises(_OriginalDomainError) as r:f.take()
        d=r.exception.cleanup_domain
        self.assertFalse(r.exception.unknown)
        self.assertTrue(d._closed)
        self.assertEqual((d._host.value,d._domain.value,d._reply.value),(None,None,None))
        self.assertFalse(any(e[0]=='call' for e in f.events))

    def test_pending_close_is_explicit_same_handle_retry(self):
        f=DomainFixture();d=f.take();f.close_issue=5
        with self.assertRaises(_OriginalDomainError) as r:d.close_after_stop()
        self.assertFalse(r.exception.unknown)
        self.assertEqual(d._domain.value,301)
        self.assertIsNotNone(d._reply.value)
        f.close_issue=0;d.close_after_stop()
        self.assertTrue(d._closed)

    def test_lost_finish_with_cleared_slots_stays_unknown_without_second_close(self):
        f=DomainFixture();d=f.take();f.finish_fault=OSError('lost finish')
        with self.assertRaises(_OriginalDomainError) as r:d.close_after_stop()
        self.assertTrue(r.exception.unknown)
        self.assertFalse(d._closed)
        self.assertEqual((d._host.value,d._domain.value,d._reply.value),(None,None,None))
        before=list(f.events)
        with self.assertRaises(_OriginalDomainError):d.close_after_stop()
        self.assertEqual(f.events,before)

    def test_wrong_operation_never_becomes_current_success(self):
        f=DomainFixture();d=f.take();f.wrong_operation=6
        with self.assertRaises(_OriginalDomainError) as r:d.current()
        self.assertTrue(r.exception.unknown)
        self.assertIsNotNone(d._reply.value)

    def test_copy_foreign_component_and_closed_fd_cannot_gain_custody(self):
        f=DomainFixture();d=f.take()
        for action in (copy.copy,copy.deepcopy,pickle.dumps):
            with self.assertRaises(TypeError):action(d)
        other=DomainFixture();before=list(f.events)
        with self.assertRaises(ValueError):
            _OriginalDomainCustody._prepare_original(f.host,f.scope,f.descriptor,other.functions,
                size=65536,work=2,attempts=1,holdings=1,transfer=3,retained=0,execution=65536)
        f.descriptor.close_attempted=True
        with self.assertRaises(ValueError):f.take()
        self.assertEqual(f.events,before)

    def test_pre_call_metadata_failure_does_not_consume_an_original(self):
        f=DomainFixture();before=list(f.events)
        with patch('actql_sdk._local_native_domain_custody._new_domain_slots',side_effect=MemoryError('metadata')):
            with self.assertRaises(MemoryError):f.take()
        self.assertEqual(f.events,before)
        self.assertFalse(f.host._busy)
