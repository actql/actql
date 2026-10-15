"""Independent pointer-slot/call frames only; actual selected DLL is separate."""
import copy
import ctypes as C
import pickle
from threading import Thread
import unittest

from test_local_native_sqlite_database_custody import DatabaseFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseError
from actql_sdk._local_native_sqlite_lookup import _OriginalLookupError


class LookupFixture(DatabaseFixture):
    def __init__(self):
        super().__init__()
        self.lookup_events = []
        self.lookup_issue, self.lookup_after = {}, {}
        self.start_refused = False
        self.start_loss = self.before_start_loss = False
        self.lookup_loss_operation = None
        self.alias_drop_loss = False
        self.on_start = self.on_alias_drop = self.on_lookup = None
        self.start_child_slot = self.start_reply_slot = None
        calls = {
            'start_into': self.start_lookup,
            'observe_into': lambda h,o,r: self.lookup_call(23,h,o,r),
            'read_utf16_into': lambda h,o,s,sn,k,kn,n,r: self.lookup_call(24,h,o,r,self.text(s,sn),self.text(k,kn),n),
            'scan_utf16_into': lambda h,o,s,sn,k,kn,n,r: self.lookup_call(25,h,o,r,self.text(s,sn),self.text(k,kn),n),
            'header_utf16_into': lambda h,o,s,sn,k,kn,r: self.lookup_call(26,h,o,r,self.text(s,sn),self.text(k,kn)),
            'capacity_utf16_into': lambda h,o,s,sn,k,kn,r: self.lookup_call(27,h,o,r,self.text(s,sn),self.text(k,kn)),
            'capacity_usage_utf16_into': lambda h,o,s,sn,r: self.lookup_call(28,h,o,r,self.text(s,sn)),
            'database_usage_into': lambda h,o,r: self.lookup_call(29,h,o,r),
            'finish_into': lambda h,o,r: self.lookup_call(30,h,o,r),
            'close_into': lambda h,o,r: self.lookup_call(31,h,o,r),
            'drop': self.drop_lookup,
        }
        for name, call in calls.items():
            setattr(self.host._functions.library, 'actql_sqlite_lookup_' + name, Function(call))

    def start_lookup(self, host, database, child, reply):
        self.lookup_events.append(('start',host.value,database.value))
        self.start_child_slot, self.start_reply_slot = child._obj, reply._obj
        if self.on_start: self.on_start()
        if self.before_start_loss: raise OSError('unconfirmed before any output')
        child._obj.value = None if self.start_refused else 601
        self.result_database(reply,22,0 if self.start_refused else 1,
            1 if self.start_refused else self.lookup_issue.get(22,0))
        if self.start_loss: raise OSError('lost start response after both original slots')
        return 0

    def lookup_call(self, operation, host, original, reply, *inputs):
        self.lookup_events.append(('call',operation,host.value,original.value,inputs))
        if self.on_lookup: self.on_lookup(operation)
        self.result_database(reply,operation,3 if operation==31 else 2,
            self.lookup_issue.get(operation,0),self.lookup_after.get(operation,0))
        if self.lookup_loss_operation == operation:
            self.lookup_loss_operation = None
            raise OSError('lost original read response')
        return 0

    def drop_lookup(self, original):
        self.lookup_events.append(('drop',original._obj.value,id(original._obj)))
        if self.on_alias_drop: self.on_alias_drop()
        original._obj.value = None
        if self.alias_drop_loss: raise OSError('lost alias retirement')
        return 0

    def unconfirmed(self):
        database = self.database()
        self.loss_operation = 8
        with unittest.TestCase().assertRaises(_OriginalDatabaseError): database.transaction(8)
        return database

    def count(self, operation):
        return sum(event[:2]==('call',operation) for event in self.lookup_events)


class OriginalLookupCustodyTests(unittest.TestCase):
    def test_same_child_bounded_values_finish_and_old_write_unknown_is_unchanged(self):
        f=LookupFixture();db=f.unconfirmed();old=db._write_unknown
        read=db.lookup_unconfirmed_snapshot()
        self.assertIs(db._lookup_original,read)
        body=bytearray(16);fact,n=read.read_into('e\u0301/原','😀',body)
        self.assertEqual((fact.operation,fact.revision,n,body[:n]),(24,3,4,b'\x00\xff\r\n'))
        key=bytearray(16);fact,kn,bn=read.scan_after_into('原','',key,body)
        self.assertEqual((fact.operation,key[:kn],bn),(25,b'e\xcc\x81/\xf0\x9f\x98\x80',4))
        header=read.read_header('原','empty')
        self.assertTrue(header.has_header);self.assertEqual(header.header_body_bytes,0)
        self.assertFalse(header.has_row)
        self.assertEqual(read.read_capacity('原','held').reserved_bytes,8)
        self.assertEqual(read.capacity_usage('原').reserved_objects,1)
        self.assertEqual(read.database_usage().reservation_count,2)
        self.assertEqual(read.finish().operation,30)
        self.assertTrue(read._closed);self.assertIsNone(db._lookup_original)
        self.assertIs(db._write_unknown,old)
        with self.assertRaises(_OriginalDatabaseError) as error:db.insert('原','new',b'no')
        self.assertIs(error.exception,old)
        self.assertEqual((f.count(30),f.count(31)),(1,0))
        db.close()

    def test_empty_and_absent_are_distinct_and_notfound_does_not_complete_or_destroy_read(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        f.row_body=b''
        fact,n=read.read_into('原','empty',bytearray(4))
        self.assertTrue(fact.has_row);self.assertEqual(n,0)
        f.lookup_issue[24]=15
        with self.assertRaises(_OriginalLookupError) as error:read.read_into('原','absent',bytearray(4))
        self.assertFalse(error.exception.unknown)
        self.assertEqual(error.exception.fact.issue_family,15)
        self.assertFalse(read._closed)
        read.finish();db.close()

    def test_busy_and_foreign_thread_before_start_keep_registration_and_calls_unchanged(self):
        f=LookupFixture();db=f.unconfirmed();db._fence_unconfirmed_response()
        f.host._busy=True
        with self.assertRaises(ValueError):db.lookup_unconfirmed_snapshot()
        self.assertTrue(f.host._busy);self.assertIsNone(db._lookup_original)
        f.host._busy=False
        errors=[]
        def foreign():
            try:db.lookup_unconfirmed_snapshot()
            except BaseException as error:errors.append(error)
        worker=Thread(target=foreign);worker.start();worker.join()
        self.assertIsInstance(errors[0],ValueError)
        self.assertEqual(f.lookup_events,[]);self.assertIsNone(db._lookup_original)
        db.close()

    def test_start_response_loss_retains_both_exact_outslots_and_cleans_without_another_start(self):
        f=LookupFixture();db=f.unconfirmed();old=db._write_unknown;f.start_loss=True
        with self.assertRaises(_OriginalLookupError) as error:db.lookup_unconfirmed_snapshot()
        read=error.exception.cleanup_lookup
        self.assertIs(read._lookup,f.start_child_slot);self.assertIs(read._reply,f.start_reply_slot)
        self.assertIs(db._lookup_original,read)
        self.assertEqual((read._lookup.value,error.exception.operation),(601,22))
        with self.assertRaises(_OriginalLookupError):read.read_header('原','key')
        read.close();read.close()
        self.assertEqual(sum(event[0]=='start' for event in f.lookup_events),1)
        self.assertEqual(f.count(31),1);self.assertIs(db._write_unknown,old)
        self.assertIsNone(db._lookup_original);db.close()

    def test_unconfirmed_start_without_slots_retains_parent_without_retry_or_inferred_absence_ack(self):
        f=LookupFixture();db=f.unconfirmed();f.before_start_loss=True
        with self.assertRaises(_OriginalLookupError) as error:db.lookup_unconfirmed_snapshot()
        read=error.exception.cleanup_lookup
        with self.assertRaises(_OriginalLookupError):read.close()
        with self.assertRaises(_OriginalLookupError):db.close()
        self.assertIs(db._lookup_original,read)
        self.assertFalse(read._closed or db._closed)
        self.assertEqual(sum(event[0]=='start' for event in f.lookup_events),1)
        self.assertEqual(f.count(31),0)
        self.assertFalse(any(event[:2]==('call',10) for event in f.database_events))

    def test_pending_start_keeps_same_child_and_partial_cleanup_sends_no_original_sql(self):
        f=LookupFixture();db=f.unconfirmed();old=db._write_unknown;f.lookup_issue[22]=20
        with self.assertRaises(_OriginalLookupError) as error:db.lookup_unconfirmed_snapshot()
        self.assertFalse(error.exception.unknown)
        read=error.exception.cleanup_lookup
        self.assertIs(db._lookup_original,read)
        with self.assertRaises(ValueError):read.finish()
        read.close()
        self.assertEqual((f.count(30),f.count(31)),(0,1))
        self.assertIs(db._write_unknown,old)
        self.assertFalse(any(event[:2]==('call',9) for event in f.database_events))
        db.close()

    def test_known_start_refusal_has_no_child_and_does_not_become_unknown(self):
        f=LookupFixture();db=f.unconfirmed();f.start_refused=True
        with self.assertRaises(_OriginalLookupError) as error:db.lookup_unconfirmed_snapshot()
        self.assertFalse(error.exception.unknown)
        self.assertTrue(error.exception.cleanup_lookup._closed)
        self.assertIsNone(db._lookup_original)
        self.assertEqual(f.count(31),0)
        db.close()

    def test_lost_finish_drains_same_reply_and_uses_cleanup_never_a_second_finish(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        f.lookup_loss_operation=30
        with self.assertRaises(_OriginalLookupError) as error:read.finish()
        self.assertEqual(error.exception.operation,30)
        self.assertIs(db._lookup_original,read);self.assertFalse(read._closed)
        read.close()
        self.assertEqual((f.count(30),f.count(31)),(1,1))
        with self.assertRaises(ValueError):read.finish()
        db.close()

    def test_known_cleanup_failure_keeps_same_child_for_only_its_original_cleanup(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        pointer=read._lookup;f.lookup_issue[31]=20
        with self.assertRaises(_OriginalLookupError) as error:read.close()
        self.assertFalse(error.exception.unknown)
        self.assertIs(read._lookup,pointer);self.assertEqual(pointer.value,601)
        self.assertIs(db._lookup_original,read)
        f.lookup_issue[31]=0;read.close()
        self.assertEqual(f.count(31),2)
        self.assertEqual(sum(event[0]=='drop' for event in f.lookup_events),1)
        db.close()

    def test_lost_cleanup_response_drains_original_ack_without_another_cleanup_call(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        f.lookup_loss_operation=31
        with self.assertRaises(_OriginalLookupError):read.close()
        self.assertEqual(f.count(31),1)
        read.close()
        self.assertEqual(f.count(31),1)
        self.assertTrue(read._closed);db.close()

    def test_alias_drop_lost_after_null_retains_same_carrier_without_passing_old_pointer_again(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        f.alias_drop_loss=True
        with self.assertRaises(_OriginalLookupError) as error:read.finish()
        self.assertIs(read._lookup,f.start_child_slot);self.assertIsNone(read._lookup.value)
        self.assertFalse(read._closed);self.assertIs(db._lookup_original,read)
        with self.assertRaises(_OriginalLookupError) as again:read.close()
        self.assertIs(again.exception,error.exception)
        self.assertEqual(sum(event[0]=='drop' for event in f.lookup_events),1)
        self.assertFalse(db._closed)

    def test_reply_drop_loss_preserves_original_parent_and_no_stop_or_new_read_is_invented(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        f.drop_fault=OSError('lost reply retirement')
        with self.assertRaises(_OriginalLookupError):read.read_header('原','key')
        self.assertIsNone(read._reply.value)
        with self.assertRaises(_OriginalLookupError):read.close()
        self.assertEqual((f.count(26),f.count(31)),(1,0))
        self.assertIs(db._lookup_original,read);self.assertFalse(db._closed)

    def test_wrong_reply_and_invalid_metadata_hold_same_slots_without_zero_substitution(self):
        for override in ({'operation':17},{'record_count':True},{'reservation_count':-2}):
            with self.subTest(override=override):
                f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
                f.override=override
                with self.assertRaises(_OriginalLookupError) as error:read.database_usage()
                self.assertTrue(error.exception.unknown)
                self.assertIs(error.exception.cleanup_lookup,read)
                self.assertIsNotNone(read._reply.value)
                self.assertIs(db._lookup_original,read)
                self.assertEqual(f.count(29),1)

    def test_reentrant_parent_close_before_start_slots_and_during_alias_drop_is_local_only(self):
        f=LookupFixture();db=f.unconfirmed();errors=[]
        def reenter():
            try:db.close()
            except BaseException as error:errors.append(error)
        f.on_start=reenter;f.on_alias_drop=reenter
        read=db.lookup_unconfirmed_snapshot()
        self.assertIsNone(read._response_unknown)
        read.finish()
        self.assertEqual(len(errors),2)
        self.assertTrue(all(isinstance(error,ValueError) for error in errors))
        self.assertFalse(f.host._busy)
        self.assertEqual(f.count(31),0)
        self.assertIsNone(db._lookup_original);db.close()

    def test_current_postcheck_failure_copies_nothing_and_cannot_be_laundered_by_later_finish(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        f.lookup_after[24]=4;body=bytearray(b'????')
        before=sum(event[0]=='copy' for event in f.database_events)
        with self.assertRaises(_OriginalLookupError) as error:read.read_into('原','key',body)
        self.assertFalse(error.exception.unknown)
        self.assertEqual(body,b'????')
        self.assertEqual(sum(event[0]=='copy' for event in f.database_events),before)
        f.lookup_after[24]=0
        with self.assertRaises(ValueError):read.finish()
        self.assertEqual(f.count(30),0)
        read.close();db.close()

    def test_copy_pickle_old_alias_and_foreign_thread_never_acquire_another_child(self):
        f=LookupFixture();db=f.unconfirmed();read=db.lookup_unconfirmed_snapshot()
        before=list(f.lookup_events)
        for copy_call in (lambda:copy.copy(read),lambda:copy.deepcopy(read),lambda:pickle.dumps(read)):
            with self.assertRaises(TypeError):copy_call()
        errors=[]
        def foreign():
            try:read.database_usage()
            except BaseException as error:errors.append(error)
        worker=Thread(target=foreign);worker.start();worker.join()
        self.assertIsInstance(errors[0],ValueError);self.assertEqual(f.lookup_events,before)
        read.finish();fresh=db.lookup_unconfirmed_snapshot()
        read.close()
        self.assertIs(db._lookup_original,fresh)
        with self.assertRaises(ValueError):read.database_usage()
        fresh.close();db.close()
