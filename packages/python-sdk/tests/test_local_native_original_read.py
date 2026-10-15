"""Independent slot/fault counters; these never prove actual Core admission."""
import copy
import pickle
from threading import Thread
import unittest
from unittest.mock import patch

from test_local_native_sqlite_custody import SqliteFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_original_read import (
    _OriginalParentReadCustody, _OriginalParentReadFunctions, _OriginalParentReadError,
)


class ParentReadFixture(SqliteFixture):
    def __init__(self):
        super().__init__()
        self.parent_events, self.parent_facts = [], {}
        self.parent_issue = self.parent_current_issue = self.parent_close_issue = 0
        self.parent_enter_issue = self.parent_leave_issue = 0
        self.parent_present = True
        self.parent_prepare_fault = self.parent_capture_fault = None
        self.parent_drop_fault = self.parent_finish_fault = None
        self.parent_call_fault = None
        self.parent_wrong_operation = self.parent_wrong_host = False
        calls = {'prepare_into':self.parent_prepare, 'originals_into':self.parent_originals,
                 'drop_reply':self.parent_drop, 'finish_closed_data':self.parent_finish,
                 'finish_refused_prepare':self.parent_refused,
                 'operation':lambda r:self.parent_facts[r.value][0],
                 'issue_family':lambda r:self.parent_facts[r.value][1]}
        for op,name in ((2,'current'),(3,'enter'),(4,'leave'),(5,'cleanup'),(6,'close')):
            calls[name+'_into'] = lambda h,o,r,op=op:self.parent_call(op,h,o,r)
        for name,call in calls.items():
            setattr(self.host._functions.library,'actql_parent_read_'+name,Function(call))
        self.parent_functions = _OriginalParentReadFunctions(self.host._functions.library)

    def parent_result(self, out, op, issue):
        key=2400+len(self.parent_facts)
        self.parent_facts[key]=(99 if self.parent_wrong_operation else op,issue)
        out._obj.value=key

    def parent_prepare(self,h,d,bh,be,w,rh,re,out):
        self.parent_events.append(('prepare',h.value,d.value,bh,be,w,rh,re))
        self.parent_result(out,1,self.parent_issue)
        if self.parent_prepare_fault:raise self.parent_prepare_fault
        return 0

    def parent_originals(self,r,h,d,o):
        self.parent_events.append(('capture',r.value))
        h._obj.value=999 if self.parent_wrong_host else 101
        d._obj.value=301;o._obj.value=701 if self.parent_present else None
        if self.parent_capture_fault:raise self.parent_capture_fault
        return 0

    def parent_drop(self,r,h,d,o):
        self.parent_events.append(('drop',r._obj.value))
        r._obj.value=None
        if self.parent_drop_fault:raise self.parent_drop_fault
        return 0

    def parent_call(self,op,h,o,r):
        self.parent_events.append(('call',op,h.value,o.value))
        issue={2:self.parent_current_issue,3:self.parent_enter_issue,
               4:self.parent_leave_issue,5:self.parent_enter_issue,6:self.parent_close_issue}[op]
        self.parent_result(r,op,issue)
        if self.parent_call_fault:raise self.parent_call_fault
        return 0

    def parent_finish(self,h,d,o,r):
        self.parent_events.append(('finish',h._obj.value,d._obj.value,o._obj.value))
        h._obj.value=d._obj.value=o._obj.value=r._obj.value=None
        if self.parent_finish_fault:raise self.parent_finish_fault
        return 0

    def parent_refused(self,h,d,r):
        self.parent_events.append(('refused',h._obj.value,d._obj.value))
        h._obj.value=d._obj.value=r._obj.value=None
        return 0

    def parent_read(self,d=None,**kw):
        if d is None:d=self.take()
        return _OriginalParentReadCustody._prepare_original(d,self.parent_functions,
            **({'bootstrap_retained':1,'bootstrap_execution':2,'workspace_execution':3,
                'read_retained':4,'read_execution':5}|kw))


class OriginalParentReadTests(unittest.TestCase):
    def test_joined_original_scope_and_cleanup_keep_parent_and_independent_fd(self):
        f=ParentReadFixture();d=f.take();r=f.parent_read(d)
        self.assertIs(d._parent_read_original,r)
        with self.assertRaises(ValueError):d.close_after_stop()
        self.assertEqual(r.current().operation,2)
        with r.scope():
            self.assertTrue(r._scope_open)
            self.assertEqual(r.current().operation,2)
        self.assertFalse(r._scope_open)
        r.close();before=list(f.parent_events);r.close()
        self.assertEqual(f.parent_events,before)
        self.assertTrue(r._closed);self.assertFalse(d._closed)
        self.assertFalse(f.descriptor.close_attempted)
        with self.assertRaises(ValueError):f.parent_read(d)
        with self.assertRaises(ValueError):r.current()
        d.close_after_stop();self.assertIsNone(d._parent_read_original)

    def test_partial_prepare_keeps_original_for_known_cleanup_retry(self):
        f=ParentReadFixture();d=f.take();f.parent_issue=11
        with self.assertRaises(_OriginalParentReadError) as e:f.parent_read(d)
        r=e.exception.cleanup_read;self.assertFalse(e.exception.unknown)
        self.assertIs(d._parent_read_original,r);self.assertEqual(r._original.value,701)
        f.parent_close_issue=5
        with self.assertRaises(_OriginalParentReadError) as pending:r.close()
        self.assertFalse(pending.exception.unknown)
        f.parent_close_issue=0;r.close();d.close_after_stop()
        self.assertEqual(sum(x[0]=='prepare' for x in f.parent_events),1)

    def test_no_carrier_refusal_drops_data_without_parent_or_fd_retirement(self):
        f=ParentReadFixture();d=f.take();f.parent_present=False;f.parent_issue=1
        with self.assertRaises(_OriginalParentReadError) as e:f.parent_read(d)
        r=e.exception.cleanup_read;self.assertFalse(e.exception.unknown)
        self.assertTrue(r._closed);self.assertFalse(d._closed)
        self.assertFalse(f.descriptor.close_attempted)
        self.assertEqual(sum(x[0]=='refused' for x in f.parent_events),1)
        d.close_after_stop()

    def test_lost_prepare_keeps_registered_slot_and_never_resends(self):
        f=ParentReadFixture();d=f.take();f.parent_prepare_fault=OSError('lost after Native')
        with self.assertRaises(_OriginalParentReadError) as e:f.parent_read(d)
        r=e.exception.cleanup_read;self.assertTrue(e.exception.unknown)
        self.assertIsNotNone(r._reply.value);self.assertIs(d._parent_read_original,r)
        before=list(f.parent_events)
        for call in (r.current,r.close,r.leave_scope):
            with self.assertRaises(_OriginalParentReadError) as again:call()
            self.assertIs(again.exception,e.exception)
        with self.assertRaises(ValueError):d.close_after_stop()
        self.assertEqual(f.parent_events,before)

    def test_capture_or_drop_response_loss_keeps_exact_original_slots(self):
        for field in ('parent_capture_fault','parent_drop_fault'):
            with self.subTest(field=field):
                f=ParentReadFixture();d=f.take();setattr(f,field,MemoryError('lost data response'))
                with self.assertRaises(_OriginalParentReadError) as e:f.parent_read(d)
                r=e.exception.cleanup_read;self.assertTrue(e.exception.unknown)
                self.assertEqual((r._host.value,r._native_domain.value,r._original.value),(101,301,701))
                before=list(f.parent_events)
                with self.assertRaises(_OriginalParentReadError):r.close()
                self.assertEqual(f.parent_events,before)

    def test_explicit_native_unknown_is_not_a_known_refusal_or_another_attempt(self):
        f=ParentReadFixture();d=f.take();f.parent_issue=9
        with self.assertRaises(_OriginalParentReadError) as e:f.parent_read(d)
        r=e.exception.cleanup_read;self.assertTrue(e.exception.unknown)
        self.assertEqual(e.exception.fact.issue_family,9)
        before=list(f.parent_events)
        with self.assertRaises(_OriginalParentReadError) as again:r.close()
        self.assertIs(again.exception,e.exception);self.assertEqual(f.parent_events,before)

    def test_finish_response_loss_with_null_slots_is_not_a_cleanup_ack(self):
        f=ParentReadFixture();d=f.take();r=f.parent_read(d);f.parent_finish_fault=OSError('lost finish')
        with self.assertRaises(_OriginalParentReadError) as e:r.close()
        self.assertTrue(e.exception.unknown);self.assertFalse(r._closed)
        self.assertTrue(all(s.value is None for s in (r._host,r._native_domain,r._original,r._reply)))
        self.assertIs(d._parent_read_original,r);before=list(f.parent_events)
        with self.assertRaises(_OriginalParentReadError):r.close()
        with self.assertRaises(ValueError):d.close_after_stop()
        self.assertEqual(f.parent_events,before)

    def test_lost_enter_retains_original_without_automatic_leave_or_close(self):
        f=ParentReadFixture();r=f.parent_read();f.parent_call_fault=OSError('lost enter')
        with self.assertRaises(_OriginalParentReadError):
            with r.scope():self.fail('unconfirmed enter must not yield')
        self.assertFalse(r._scope_open);before=list(f.parent_events)
        with self.assertRaises(_OriginalParentReadError):r.close()
        self.assertEqual(f.parent_events,before)
        self.assertEqual([e[1] for e in f.parent_events if e[0]=='call'],[3])

    def test_lost_leave_keeps_scope_responsibility_without_second_leave(self):
        f=ParentReadFixture();r=f.parent_read()
        with self.assertRaises(_OriginalParentReadError):
            with r.scope():f.parent_call_fault=OSError('lost leave')
        self.assertTrue(r._scope_open);before=list(f.parent_events)
        with self.assertRaises(_OriginalParentReadError):r.leave_scope()
        self.assertEqual(f.parent_events,before)

    def test_known_leave_refusal_allows_only_explicit_same_scope_retry(self):
        f=ParentReadFixture();r=f.parent_read()
        with self.assertRaises(_OriginalParentReadError) as e:
            with r.scope():f.parent_leave_issue=6
        self.assertFalse(e.exception.unknown);self.assertTrue(r._scope_open)
        before=list(f.parent_events)
        with self.assertRaises(ValueError):r.close()
        self.assertEqual(f.parent_events,before)
        f.parent_leave_issue=0;r.leave_scope();r.close()
        self.assertFalse(r._scope_open);self.assertTrue(r._closed)

    def test_cleanup_scope_preserves_managed_primary_failure_and_original_leave(self):
        f=ParentReadFixture();r=f.parent_read();primary=ValueError('managed original failure')
        with self.assertRaises(ValueError) as e:
            with r.scope(cleanup=True):raise primary
        self.assertIs(e.exception,primary);self.assertFalse(r._scope_open)
        self.assertEqual([x[1] for x in f.parent_events if x[0]=='call'],[5,4])
        r.close()

    def test_close_or_reenter_inside_scope_refuses_before_any_native_call(self):
        f=ParentReadFixture();r=f.parent_read()
        with r.scope():
            before=list(f.parent_events)
            for call in (r.close,lambda:r._call(3),lambda:r._call(5)):
                with self.assertRaises(ValueError):call()
            self.assertEqual(f.parent_events,before);self.assertIsNone(r._unknown)
        r.close()

    def test_busy_prepare_and_calls_preserve_registration_and_existing_cleanup(self):
        for prepared in (False,True):
            with self.subTest(prepared=prepared):
                f=ParentReadFixture();d=f.take();r=f.parent_read(d) if prepared else None
                before=list(f.parent_events);f.host._busy=True
                with self.assertRaises(ValueError):
                    if r is None:f.parent_read(d)
                    else:r.close()
                self.assertTrue(f.host._busy);self.assertIs(d._parent_read_original,r)
                self.assertEqual(f.parent_events,before);f.host._busy=False
                if r is None:r=f.parent_read(d)
                r.close();d.close_after_stop()

    def test_thread_or_process_refusal_is_not_a_new_unknown_or_registration(self):
        for prepared in (False,True):
            f=ParentReadFixture();d=f.take();r=f.parent_read(d) if prepared else None
            before=list(f.parent_events);errors=[]
            def foreign():
                try:
                    if r is None:f.parent_read(d)
                    else:r.close()
                except BaseException as error:errors.append(error)
            t=Thread(target=foreign);t.start();t.join(2);self.assertFalse(t.is_alive())
            self.assertEqual([type(e) for e in errors],[ValueError])
            with patch('actql_sdk._local_native_control_custody.getpid',return_value=-1):
                with self.assertRaises(ValueError):
                    if r is None:f.parent_read(d)
                    else:r.current()
            self.assertIs(d._parent_read_original,r);self.assertEqual(f.parent_events,before)
            if r is None:r=f.parent_read(d)
            self.assertIsNone(r._unknown);r.close();d.close_after_stop()

    def test_reentrant_close_does_not_steal_busy_or_poison_the_original(self):
        f=ParentReadFixture();r=f.parent_read()
        def current(h,o,out):
            before=list(f.parent_events)
            with self.assertRaises(ValueError):r.close()
            self.assertTrue(f.host._busy);self.assertEqual(f.parent_events,before)
            return f.parent_call(2,h,o,out)
        f.parent_functions.current=Function(current)
        r.current();self.assertIsNone(r._unknown);r.close()

    def test_parent_unknown_is_returned_unchanged_without_child_mutation(self):
        f=ParentReadFixture();d=f.take();r=f.parent_read(d)
        error=d._mark_unknown();before=list(f.parent_events)
        with self.assertRaises(type(error)) as e:r.close()
        self.assertIs(e.exception,error);self.assertIsNone(r._unknown)
        self.assertEqual(f.parent_events,before)

    def test_slot_allocation_failure_is_before_entry_registration_or_native(self):
        f=ParentReadFixture();d=f.take()
        with patch('actql_sdk._local_native_original_read.byref',side_effect=MemoryError('slots')):
            with self.assertRaises(MemoryError):f.parent_read(d)
        self.assertIsNone(d._parent_read_original);self.assertEqual(f.parent_events,[])
        r=f.parent_read(d);before=list(f.parent_events)
        with patch('actql_sdk._local_native_original_read.byref',side_effect=MemoryError('slots')):
            with self.assertRaises(MemoryError):r.current()
        self.assertEqual(f.parent_events,before);self.assertIsNone(r._unknown);r.close()

    def test_domain_retired_during_preallocation_is_rechecked_without_registration(self):
        from ctypes import byref
        f=ParentReadFixture();d=f.take();done=[]
        def retire(value):
            if not done:done.append(True);d.close_after_stop()
            return byref(value)
        with patch('actql_sdk._local_native_original_read.byref',side_effect=retire):
            with self.assertRaises(ValueError):f.parent_read(d)
        self.assertTrue(d._closed);self.assertIsNone(d._parent_read_original)
        self.assertEqual(f.parent_events,[]);self.assertFalse(f.host._busy)

    def test_same_domain_sqlite_and_parent_read_are_not_interchangeable_purposes(self):
        f=ParentReadFixture();d=f.take();r=f.parent_read(d)
        with self.assertRaises(ValueError):f.sqlite(d)
        self.assertEqual(f.sql_events,[]);r.close();d.close_after_stop()
        f=ParentReadFixture();d=f.take();sql=f.sqlite(d)
        with self.assertRaises(ValueError):f.parent_read(d)
        self.assertEqual(f.parent_events,[]);sql.close();d.close_after_stop()

    def test_foreign_component_copy_pickle_and_abi_overflow_never_consume_original(self):
        f=ParentReadFixture();d=f.take();other=ParentReadFixture()
        with self.assertRaises(ValueError):
            _OriginalParentReadCustody._prepare_original(d,other.parent_functions,
                bootstrap_retained=1,bootstrap_execution=2,workspace_execution=3,
                read_retained=4,read_execution=5)
        for value in (True,2**63,-2**63-1,None):
            with self.assertRaises(ValueError):f.parent_read(d,read_execution=value)
        self.assertIsNone(d._parent_read_original);self.assertEqual(f.parent_events,[])
        r=f.parent_read(d)
        for call in (copy.copy,copy.deepcopy,pickle.dumps):
            with self.assertRaises(TypeError):call(r)
        r.close();d.close_after_stop()

    def test_wrong_reply_identity_or_operation_never_becomes_current_or_cleanup_success(self):
        for field in ('parent_wrong_host','parent_wrong_operation'):
            f=ParentReadFixture();d=f.take();setattr(f,field,True)
            with self.assertRaises(_OriginalParentReadError) as e:f.parent_read(d)
            self.assertTrue(e.exception.unknown);r=e.exception.cleanup_read
            self.assertIs(d._parent_read_original,r)
            with self.assertRaises(ValueError):d.close_after_stop()


if __name__=='__main__':unittest.main()
