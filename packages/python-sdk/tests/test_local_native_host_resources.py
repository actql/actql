"""Independent original-slot faults; matching actual DLL results are separate."""
import copy
from threading import Thread
import unittest
from unittest.mock import patch

from test_local_native_original_read import ParentReadFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_host_resources import (
    _OriginalHostResourcesCustody, _OriginalHostResourcesFunctions,
    _OriginalHostResourcesError, _RETIRED_HOST_RESOURCES_DATA,
)


class PairFixture(ParentReadFixture):
    def __init__(self):
        super().__init__()
        self.pair_events, self.pair_facts = [], {}
        self.bind_issue, self.call_issue = (0, 0), (0, 0)
        self.pair_present = True
        self.bind_fault = self.capture_fault_pair = self.operate_fault = None
        self.claim_fault = self.claim_drop_fault = None
        self.pair_drop_fault = self.pair_finish_fault = None
        self.closed_override = self.operation_override = None
        self.wrong_original = False
        calls = {'bind_into':self.bind_pair, 'operate_into':self.operate_pair,
                 'claim_read_into':self.claim_read_pair,
                 'originals_into':self.pair_originals, 'drop_reply':self.pair_drop,
                 'finish_closed_data':self.pair_finish,
                 'finish_refused_bind_data':self.pair_refused,
                 'operation':lambda r:self.pair_facts[r.value][0],
                 'issue_origin':lambda r:self.pair_facts[r.value][1],
                 'issue_family':lambda r:self.pair_facts[r.value][2],
                 'close_confirmed':lambda r:self.pair_facts[r.value][3]}
        for name, call in calls.items():
            setattr(self.host._functions.library,'actql_host_resources_'+name,Function(call))
        self.pair_functions = _OriginalHostResourcesFunctions(self.host._functions.library)
        self.r = self.parent_read(self.take())
        self.s = self.sqlite(self.take())

    def result_pair(self, out, op, issue):
        key = 3400+len(self.pair_facts)
        closed = int(op == 8 and issue == (0, 0)) if self.closed_override is None else self.closed_override
        self.pair_facts[key] = (op if self.operation_override is None else self.operation_override, *issue, closed)
        out._obj.value = key

    def bind_pair(self, h, r, s, out):
        self.pair_events.append(('bind',h.value,r.value,s.value))
        self.result_pair(out,1,self.bind_issue)
        if self.bind_fault: raise self.bind_fault
        return 0

    def operate_pair(self,h,p,op,out):
        self.pair_events.append(('operate',op,h.value,p.value))
        self.result_pair(out,op,self.call_issue)
        if self.operate_fault: raise self.operate_fault
        return 0

    def claim_read_pair(self,h,p,retained,execution,out):
        self.pair_events.append(('claim',h.value,p.value,retained,execution))
        self.result_pair(out,9,self.call_issue)
        if self.claim_drop_fault:self.pair_drop_fault=self.claim_drop_fault
        if self.claim_fault: raise self.claim_fault
        return 0

    def pair_originals(self,r,h,sh,read,sql,original):
        self.pair_events.append(('originals',r.value))
        h._obj.value = 101;sh._obj.value = 999 if self.wrong_original else 101
        read._obj.value = 701;sql._obj.value = 401
        original._obj.value = 801 if self.pair_present else None
        if self.capture_fault_pair: raise self.capture_fault_pair
        return 0

    def pair_drop(self,r,*originals):
        self.pair_events.append(('drop',r._obj.value))
        r._obj.value = None
        if self.pair_drop_fault: raise self.pair_drop_fault
        return 0

    def pair_finish(self,*outputs):
        self.pair_events.append(('finish',))
        for output in outputs:output._obj.value = None
        if self.pair_finish_fault: raise self.pair_finish_fault
        return 0

    def pair_refused(self,*outputs):
        self.pair_events.append(('refused',))
        for output in outputs:output._obj.value = None
        if self.pair_finish_fault: raise self.pair_finish_fault
        return 0

    def pair(self):
        return _OriginalHostResourcesCustody._bind_original(self.r,self.s,self.pair_functions)


class OriginalHostResourcesTests(unittest.TestCase):
    def test_originals_one_binding_phase_and_parent_data_are_retained(self):
        f=PairFixture();p=f.pair()
        self.assertIs(f.host._host_resources_original,p)
        self.assertEqual(p.current().operation,2)
        with f.r.scope():
            self.assertTrue(f.r._scope_open)
            self.assertEqual(p._phase,'read')
            with self.assertRaises(ValueError):
                with f.s._domain._read_scope(f.read_functions):pass
        self.assertFalse(f.r._scope_open)
        with f.s._domain._read_scope(f.read_functions):self.assertEqual(p._phase,'sqlite')
        self.assertEqual([x[1] for x in f.pair_events if x[0]=='operate'],[2,3,5,4,5])
        self.assertFalse(f.r._closed or f.s._closed)
        p.close();before=list(f.pair_events);p.close()
        self.assertEqual(f.pair_events,before)
        self.assertTrue(p._closed and f.r._closed and f.s._closed)
        self.assertIs(f.host._host_resources_original,_RETIRED_HOST_RESOURCES_DATA)
        self.assertFalse(f.host._closed or f.descriptor.close_attempted)
        with self.assertRaises(ValueError):f.pair()
        with self.assertRaises(ValueError):p.current()

    def test_claim_keeps_same_original_pair_and_serial_read_sqlite_read_phases(self):
        f=PairFixture();p=f.pair();slots=[v.value for v in p._slots()[:-1]]
        self.assertEqual(p.claim_read(32768,65536).operation,9)
        self.assertIsNone(p._phase);self.assertFalse(f.r._scope_open)
        self.assertEqual([v.value for v in p._slots()[:-1]],slots)
        self.assertEqual([x for x in f.pair_events if x[0]=='claim'],[('claim',101,801,32768,65536)])
        for phase in ('read','sqlite','read'):
            with p.scope(phase):self.assertEqual(p._phase,phase)
        self.assertIsNone(p._phase);self.assertFalse(f.r._scope_open)
        self.assertEqual([x[1] for x in f.pair_events if x[0]=='operate'],[3,5,4,5,3,5])
        p.close();self.assertTrue(p._closed and f.r._closed and f.s._closed)

    def test_claim_transports_exact_signed_int64_and_native_refusal_is_not_unknown(self):
        f=PairFixture();p=f.pair();f.call_issue=(2,5)
        with self.assertRaises(_OriginalHostResourcesError) as error:
            p.claim_read(-(1<<63),(1<<63)-1)
        self.assertFalse(error.exception.unknown)
        self.assertEqual(error.exception.fact.operation,9)
        self.assertEqual(f.pair_events[-2],('claim',101,801,-(1<<63),(1<<63)-1))
        self.assertIsNone(p._unknown);self.assertFalse(p._closed or f.r._closed or f.s._closed)
        f.call_issue=(0,0);p.current();p.close()

    def test_claim_invalid_scalar_or_active_phase_refuses_before_foreign_call(self):
        f=PairFixture();p=f.pair()
        for quote in [(True,1),(1,False),(1.0,1),(1,None),(1<<63,1),(1,-(1<<63)-1)]:
            before=list(f.pair_events)
            with self.assertRaises(ValueError):p.claim_read(*quote)
            self.assertEqual(f.pair_events,before);self.assertIsNone(p._unknown)
        with p.scope('read'):
            before=list(f.pair_events)
            with self.assertRaises(ValueError):p.claim_read(32,64)
            self.assertEqual(f.pair_events,before);self.assertEqual(p._phase,'read')
        before=list(f.pair_events)
        with self.assertRaises(ValueError):p._call(9)
        self.assertEqual(f.pair_events,before)
        p.close()

    def test_claim_busy_thread_and_process_refusals_preserve_registration_and_busy(self):
        for mode in ('busy','thread','process'):
            with self.subTest(mode=mode):
                f=PairFixture();p=f.pair();before=list(f.pair_events);errors=[]
                def call():
                    try:p.claim_read(32,64)
                    except BaseException as error:errors.append(error)
                if mode=='busy':f.host._busy=True;call();self.assertTrue(f.host._busy);f.host._busy=False
                elif mode=='thread':
                    worker=Thread(target=call);worker.start();worker.join(2);self.assertFalse(worker.is_alive())
                else:
                    with patch('actql_sdk._local_native_control_custody.getpid',return_value=-1):call()
                self.assertEqual(len(errors),1);self.assertEqual(f.pair_events,before)
                self.assertIsNone(p._unknown);self.assertIs(f.host._host_resources_original,p)
                p.close()

    def test_claim_lost_outslot_or_drop_ack_retains_same_carrier_without_reclaim(self):
        for failure in ('claim_fault','claim_drop_fault'):
            with self.subTest(failure=failure):
                f=PairFixture();p=f.pair();setattr(f,failure,OSError('claim response lost'))
                with self.assertRaises(_OriginalHostResourcesError) as error:p.claim_read(32,64)
                self.assertTrue(error.exception.unknown);self.assertIs(error.exception.cleanup_resources,p)
                self.assertEqual([v.value for v in p._slots()[:-1]],[101,101,701,401,801])
                self.assertEqual(sum(event[0]=='claim' for event in f.pair_events),1)
                before=list(f.pair_events)
                for call in (lambda:p.claim_read(32,64),p.current,p.close):
                    with self.assertRaises(_OriginalHostResourcesError) as again:call()
                    self.assertIs(again.exception,error.exception)
                self.assertEqual(f.pair_events,before);self.assertFalse(p._closed or f.r._closed or f.s._closed)

    def test_native_unknown_claim_preserves_original_fact_and_never_reissues(self):
        f=PairFixture();p=f.pair();f.call_issue=(2,9)
        with self.assertRaises(_OriginalHostResourcesError) as error:p.claim_read(32,64)
        self.assertTrue(error.exception.unknown);self.assertEqual(error.exception.fact.operation,9)
        self.assertIsNotNone(p._reply.value);self.assertIsNone(p._phase)
        before=list(f.pair_events)
        with self.assertRaises(_OriginalHostResourcesError) as again:p.claim_read(32,64)
        self.assertIs(again.exception,error.exception);self.assertEqual(f.pair_events,before)

    def test_claim_wrong_operation_or_close_shape_does_not_start_phase_or_retire(self):
        for field,value in [('operation_override',3),('closed_override',1)]:
            with self.subTest(field=field):
                f=PairFixture();p=f.pair();setattr(f,field,value)
                with self.assertRaises(_OriginalHostResourcesError) as error:p.claim_read(32,64)
                self.assertTrue(error.exception.unknown);self.assertIsNone(p._phase)
                self.assertFalse(p._closed or f.r._closed or f.s._closed)

    def test_busy_thread_process_rejections_make_no_native_bind_or_registration(self):
        for mode in ('busy','thread','process'):
            with self.subTest(mode=mode):
                f=PairFixture();errors=[]
                if mode=='busy':f.host._busy=True
                def run():
                    try:f.pair()
                    except BaseException as error:errors.append(error)
                if mode=='thread':
                    worker=Thread(target=run);worker.start();worker.join(2);self.assertFalse(worker.is_alive())
                elif mode=='process':
                    with patch('actql_sdk._local_native_control_custody.getpid',return_value=-1):run()
                else:run()
                self.assertEqual(len(errors),1);self.assertIs(type(errors[0]),ValueError)
                self.assertEqual(f.pair_events,[]);self.assertIsNone(f.host._host_resources_original)
                f.host._busy=False;f.pair().close()

    def test_foreign_parent_or_component_refuses_before_ffi(self):
        f=PairFixture();other=PairFixture()
        for r,s,fn in [(f.r,other.s,f.pair_functions),(f.r,f.s,other.pair_functions)]:
            with self.assertRaises(ValueError):_OriginalHostResourcesCustody._bind_original(r,s,fn)
        self.assertEqual(f.pair_events,[]);self.assertIsNone(f.host._host_resources_original)

    def test_known_bind_refusal_retires_only_no_pair_data(self):
        f=PairFixture();f.bind_issue=(2,10);f.pair_present=False
        with self.assertRaises(_OriginalHostResourcesError) as e:f.pair()
        p=e.exception.cleanup_resources;self.assertFalse(e.exception.unknown)
        self.assertTrue(p._closed);self.assertFalse(p._bound)
        before=(list(f.parent_events),list(f.sql_events));p.close()
        self.assertEqual(before,(f.parent_events,f.sql_events))
        self.assertFalse(f.r._closed or f.s._closed)
        self.assertEqual(sum(x[0]=='refused' for x in f.pair_events),1)

    def test_refused_selected_pair_never_falls_back_to_legacy_new_work(self):
        f=PairFixture();f.bind_issue=(2,10);f.pair_present=False
        with self.assertRaises(_OriginalHostResourcesError) as failure:f.pair()
        p=failure.exception.cleanup_resources
        before=(list(f.parent_events),list(f.events))
        with self.assertRaises(ValueError):
            with f.r.scope():pass
        with self.assertRaises(ValueError):
            with f.s._domain._read_scope(f.read_functions):pass
        self.assertEqual(before,(f.parent_events,f.events))
        # Only the same original cleanup ports remain available. They do not
        # resurrect the failed binding or call its absent Native pair.
        with f.r.scope(cleanup=True):self.assertTrue(f.r._scope_open)
        with f.s._domain._read_scope(f.read_functions,cleanup=True):pass
        self.assertFalse(any(x[0]=='operate' for x in f.pair_events))
        f.s.close();self.assertIs(f.host._host_resources_original,p)
        f.parent_close_issue=5
        with self.assertRaises(Exception):f.r.close()
        self.assertIs(f.host._host_resources_original,p)
        self.assertFalse(f.r._closed)
        f.parent_close_issue=0;f.r.close()
        self.assertIs(f.host._host_resources_original,_RETIRED_HOST_RESOURCES_DATA)
        self.assertFalse(f.host._closed or f.descriptor.close_attempted)

    def test_bind_loss_after_outslot_keeps_same_carrier_and_forbids_resend(self):
        f=PairFixture();f.bind_fault=OSError('reply lost after native bind')
        with self.assertRaises(_OriginalHostResourcesError) as e:f.pair()
        p=e.exception.cleanup_resources;self.assertTrue(e.exception.unknown)
        self.assertIs(f.host._host_resources_original,p);self.assertIsNotNone(p._reply.value)
        before=list(f.pair_events)
        for call in (p.current,p.close):
            with self.assertRaises(_OriginalHostResourcesError) as again:call()
            self.assertIs(again.exception,e.exception)
        with self.assertRaises(ValueError):f.pair()
        self.assertEqual(f.pair_events,before)

    def test_partial_getter_or_drop_loss_retains_all_original_roles(self):
        for field in ('capture_fault_pair','pair_drop_fault'):
            with self.subTest(field=field):
                f=PairFixture();setattr(f,field,MemoryError('partial foreign response'))
                with self.assertRaises(_OriginalHostResourcesError) as e:f.pair()
                p=e.exception.cleanup_resources
                self.assertEqual([v.value for v in p._slots()[:-1]],[101,101,701,401,801])
                self.assertTrue(e.exception.unknown);self.assertFalse(p._closed)

    def test_wrong_original_or_success_shape_never_becomes_ack(self):
        for field,value in [('wrong_original',True),('closed_override',1),('operation_override',2)]:
            with self.subTest(field=field):
                f=PairFixture();setattr(f,field,value)
                with self.assertRaises(_OriginalHostResourcesError) as e:f.pair()
                self.assertTrue(e.exception.unknown);self.assertFalse(e.exception.cleanup_resources._closed)

    def test_explicit_read_unknown_is_sticky_but_sqlite_target_refusal_is_known(self):
        for issue,unknown in [((2,9),True),((3,9),False)]:
            with self.subTest(issue=issue):
                f=PairFixture();p=f.pair();f.call_issue=issue
                with self.assertRaises(_OriginalHostResourcesError) as e:p.current()
                self.assertEqual(e.exception.unknown,unknown)
                if unknown:
                    before=list(f.pair_events)
                    with self.assertRaises(_OriginalHostResourcesError):p.close()
                    self.assertEqual(f.pair_events,before)
                else:f.call_issue=(0,0);p.close()

    def test_known_failed_leave_keeps_phase_and_explicit_same_owner_retry(self):
        f=PairFixture();p=f.pair()
        with self.assertRaises(_OriginalHostResourcesError) as e:
            with f.r.scope():f.call_issue=(1,5)
        self.assertFalse(e.exception.unknown);self.assertEqual(p._phase,'read');self.assertTrue(f.r._scope_open)
        before=list(f.pair_events)
        with self.assertRaises(ValueError):
            with p.scope('sqlite'):pass
        self.assertEqual(f.pair_events,before)
        f.call_issue=(0,0);f.r.leave_scope();self.assertIsNone(p._phase);p.close()

    def test_lost_phase_response_never_reenters_or_auto_leaves(self):
        f=PairFixture();p=f.pair();f.operate_fault=OSError('phase response lost')
        with self.assertRaises(_OriginalHostResourcesError) as e:
            with f.r.scope():self.fail('unknown enter must not call user body')
        before=list(f.pair_events)
        with self.assertRaises(_OriginalHostResourcesError):p.close()
        self.assertEqual(f.pair_events,before);self.assertIsNotNone(p._reply.value)
        self.assertTrue(e.exception.unknown)

    def test_native_close_refusal_does_not_close_parent_transports(self):
        f=PairFixture();p=f.pair();f.call_issue=(3,5)
        with self.assertRaises(_OriginalHostResourcesError):p.close()
        self.assertFalse(p._closed or f.r._closed or f.s._closed)
        self.assertIs(f.host._host_resources_original,p)
        f.call_issue=(0,0);p.close()

    def test_success_shaped_close_with_active_phase_is_unknown_not_retirement(self):
        f=PairFixture();p=f.pair()
        with self.assertRaises(_OriginalHostResourcesError) as e:
            with p.scope('read'):p.close()
        self.assertTrue(e.exception.unknown)
        self.assertEqual(p._phase,'read');self.assertFalse(p._closed)
        self.assertFalse(any(event[0]=='finish' for event in f.pair_events))
        self.assertFalse(f.r._closed or f.s._closed)

    def test_lost_data_finish_ack_keeps_unknown_and_never_repeats_close(self):
        f=PairFixture();p=f.pair();f.pair_finish_fault=OSError('ACK lost after slots cleared')
        with self.assertRaises(_OriginalHostResourcesError) as e:p.close()
        self.assertTrue(e.exception.unknown);self.assertFalse(p._closed)
        before=list(f.pair_events)
        with self.assertRaises(_OriginalHostResourcesError):p.close()
        self.assertEqual(f.pair_events,before);self.assertIs(f.host._host_resources_original,p)
        self.assertFalse(f.r._closed or f.s._closed)

    def test_pending_or_unknown_child_blocks_parent_before_native_close(self):
        f=PairFixture();p=f.pair();child=type('Child',(),{'_unknown':None})();f.s._database_original=child
        before=list(f.pair_events)
        with self.assertRaises(ValueError):p.close()
        self.assertEqual(f.pair_events,before)
        original_error=OSError('original child Unknown');child._unknown=original_error
        with self.assertRaises(OSError) as e:p.close()
        self.assertIs(e.exception,original_error);self.assertEqual(f.pair_events,before)
        f.s._database_original=None;p.close()

    def test_data_reobservation_failure_keeps_registration_after_pair_ack(self):
        f=PairFixture();p=f.pair();f.sql_close_issue=5
        with self.assertRaises(Exception):p.close()
        self.assertTrue(p._closed);self.assertFalse(f.s._closed or f.r._closed)
        self.assertIs(f.host._host_resources_original,p)
        before=sum(x[0]=='operate' and x[1]==8 for x in f.pair_events)
        f.sql_close_issue=0;p.close()
        self.assertEqual(sum(x[0]=='operate' and x[1]==8 for x in f.pair_events),before)
        self.assertIs(f.host._host_resources_original,_RETIRED_HOST_RESOURCES_DATA)

    def test_copied_serialized_and_foreign_scope_functions_are_rejected(self):
        import pickle
        f=PairFixture();p=f.pair()
        for call in (lambda:copy.copy(p),lambda:copy.deepcopy(p),lambda:pickle.dumps(p)):
            with self.assertRaises(TypeError):call()
        other=PairFixture()
        with self.assertRaises(ValueError):
            with f.s._domain._read_scope(other.read_functions):pass
        for value in (None,True,'Read','sqlite\n'):
            with self.assertRaises(ValueError):
                with p.scope(value):pass
        p.close()


if __name__=='__main__':unittest.main()
