"""Independent physical port counters; no selected SQLite/DLL or public Host."""
import copy
import unittest

from actql_sdk._local_native_storage import _NativeByteDatabase, _BYTES
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseError
from actql_sdk._local_native_sqlite_lookup import _OriginalLookupError
from actql_sdk._local_storage import LocalStorageError
from actql_sdk._local_storage_physical import _PhysicalCapacityCollision, _PhysicalCapacityExceeded
from test_local_native_sqlite_lookup_custody import LookupFixture


class NativePhysicalByteDatabaseTests(unittest.TestCase):
    def test_same_original_raw_key_bytes_header_and_write_projection(self):
        f=LookupFixture();db=f.database();port=_NativeByteDatabase(db)
        key='namespace:6:e\u0301/原:😀'
        self.assertEqual(port.read_row(key,8),(3,b'\0\xff\r\n','blob',4))
        self.assertEqual(port.read_header(key),(0,0))
        self.assertEqual(port.write_record(key,None,b'\0\xff\r\n'),0)
        self.assertEqual(port.write_record(key,0,b''),0)
        calls=[x for x in f.database_events if x[0]=='call']
        self.assertEqual(calls[0][4],(_BYTES,key,8))
        self.assertEqual(calls[2][4],(_BYTES,key,b'\0\xff\r\n'))
        self.assertIs(port._original,db)
        with self.assertRaises(TypeError):copy.copy(port)
        with self.assertRaises(TypeError):copy.deepcopy(port)
        port.close()

    def test_zero_bound_uses_same_typed_header_without_one_unreserved_byte(self):
        f=LookupFixture();db=f.database();port=_NativeByteDatabase(db)
        self.assertEqual(port.read_row('empty',0),(0,b'','blob',0))
        self.assertFalse(any(x[:2]==('call',4) for x in f.database_events))
        f.override={'header_body_bytes':1}
        with self.assertRaises(LocalStorageError):port.read_row('large',0)
        self.assertFalse(any(x[0]=='copy' for x in f.database_events))
        f.override={};f.operation_issue[19]=15
        self.assertIsNone(port.read_row('missing',0))
        port.close()

    def test_inclusive_prefix_is_not_skipped_and_exact_absence_is_not_scan_permission(self):
        f=LookupFixture();db=f.database();port=_NativeByteDatabase(db)
        self.assertEqual(port.scan_range('prefix:','prefix;',8,inclusive=True,exact=False),
                         ('prefix:',3,b'\0\xff\r\n','blob',4))
        self.assertFalse(any(x[:2]==('call',12) for x in f.database_events))
        f.operation_issue[4]=15
        self.assertIsNone(port.scan_range('prefix:','prefix;',8,inclusive=False,exact=True))
        self.assertFalse(any(x[:2]==('call',12) for x in f.database_events))
        self.assertEqual(port.scan_range('a','z',8,inclusive=True,exact=False),
                         ('e\u0301/😀',3,b'\0\xff\r\n','blob',4))
        self.assertIsNone(port.scan_range('a','b',8,inclusive=False,exact=False))
        port.close()

    def test_capacity_and_metadata_are_original_facts_and_closed_bounded_reserve(self):
        f=LookupFixture();db=f.database();port=_NativeByteDatabase(db)
        self.assertEqual(port.read_capacity('原','e\u0301'),(8,1))
        self.assertEqual(port.capacity_usage('原'),(8,1))
        self.assertEqual(port.record_usage(),(3,8));self.assertEqual(port.reservation_count(),2)
        self.assertTrue(port.has_records_or_capacity())
        self.assertTrue(port.reserve_capacity_in_transaction('原','e\u0301',8,1,64,2,2))
        event=next(x for x in f.database_events if x[:2]==('call',21))
        self.assertEqual(event[4],('原','e\u0301',8,1,64,2,2))
        f.operation_issue[21]=16
        with self.assertRaises(_PhysicalCapacityCollision):port.reserve_capacity_in_transaction('原','e\u0301',8,1,64,2,2)
        f.operation_issue[21]=19
        with self.assertRaises(_PhysicalCapacityExceeded):port.reserve_capacity_in_transaction('原','e\u0301',8,1,64,2,2)
        f.operation_issue[15]=16
        with self.assertRaises(_PhysicalCapacityCollision):port.release_capacity_in_transaction('原','e\u0301',8,1)
        port.close()

    def test_finish_unknown_write_snapshot_preserves_original_identity_and_sends_no_commit(self):
        f=LookupFixture();db=f.unconfirmed();old=db._write_unknown;port=_NativeByteDatabase(db)
        port.begin_read();read=db._lookup_original
        self.assertEqual(port.read_row('original',8),(3,b'\0\xff\r\n','blob',4))
        self.assertEqual(port.record_usage(),(3,8))
        self.assertIs(port._original._lookup_original,read)
        with self.assertRaises(LocalStorageError):_ = port.in_transaction
        port.finish_read()
        self.assertTrue(read._closed);self.assertIsNone(db._lookup_original)
        self.assertIs(db._write_unknown,old)
        for action in (port.begin_immediate,port.commit,port.rollback):
            with self.assertRaises(_OriginalDatabaseError) as error:action()
            self.assertIs(error.exception,old)
        self.assertEqual((f.count(30),f.count(31)),(1,0))
        self.assertEqual([x[1] for x in f.database_events if x[0]=='call' and x[1] in (7,8,9)],[8])
        port.close()

    def test_failed_inspection_cleanup_only_uses_same_child_never_finish_or_sql_rollback(self):
        f=LookupFixture();db=f.unconfirmed();port=_NativeByteDatabase(db);port.begin_read()
        read=db._lookup_original;port.cleanup_read()
        self.assertTrue(read._closed)
        self.assertEqual((f.count(30),f.count(31)),(0,1))
        self.assertFalse(any(x[:2]==('call',9) for x in f.database_events))
        self.assertIsNotNone(db._write_unknown);port.close()

    def test_lost_start_is_retained_by_same_database_before_adapter_returns(self):
        f=LookupFixture();db=f.unconfirmed();port=_NativeByteDatabase(db);f.start_loss=True
        with self.assertRaises(_OriginalLookupError) as error:port.begin_read()
        child=error.exception.cleanup_lookup
        self.assertIs(db._lookup_original,child)
        self.assertIs(port._original,db)
        port.cleanup_read()
        self.assertTrue(child._closed)
        self.assertEqual(sum(x[0]=='start' for x in f.lookup_events),1)
        self.assertEqual((f.count(30),f.count(31)),(0,1));port.close()

    def test_only_confirmed_notfound_is_absent_and_postcurrent_refusal_stays_failure(self):
        f=LookupFixture();db=f.database();port=_NativeByteDatabase(db)
        f.operation_issue[4]=15
        self.assertIsNone(port.read_row('missing',8))
        f.operation_after[4]=4
        with self.assertRaises(_OriginalDatabaseError):port.read_row('protected',8)
        f.operation_after.clear();f.operation_issue[4]=0;f.loss_operation=4
        with self.assertRaises(_OriginalDatabaseError) as error:port.read_row('uncertain',8)
        self.assertTrue(error.exception.unknown)
        self.assertIs(error.exception.cleanup_database,db)
        self.assertFalse(db._closed)

    def test_invalid_bounds_and_native_unrepresentable_key_do_not_call_or_normalize(self):
        f=LookupFixture();db=f.database();port=_NativeByteDatabase(db)
        before=list(f.database_events)
        for size in (-1,True,1025):
            with self.assertRaises(ValueError):port.read_row('key',size)
        for key in ('x'*513,'a\0b'):
            with self.assertRaises(ValueError):port.read_row(key,8)
        with self.assertRaises(ValueError):port.scan_range('a','z',8,inclusive=1,exact=False)
        with self.assertRaises(ValueError):port.reserve_capacity_in_transaction('原','key',8,1,64,2,True)
        self.assertEqual(f.database_events,before)
        port.close()
