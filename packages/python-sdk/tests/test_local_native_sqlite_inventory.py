"""Independent bounded scan transport counters; real DLL is separate."""
import unittest
from test_local_native_sqlite_database_custody import DatabaseFixture
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseError


class OriginalDatabaseInventoryTests(unittest.TestCase):
    def test_empty_and_exact_unicode_cursor_copy_only_to_original_caller_buffers(self):
        f = DatabaseFixture(); db = f.database()
        for cursor in ('', 'e\u0301/😀', '\0'):
            key, body = bytearray(512), bytearray(16)
            fact, key_size, body_size = db.scan_after_into('sdk/原', cursor, key, body)
            self.assertEqual((fact.operation, fact.revision), (12, 3))
            self.assertEqual(key[:key_size], b'e\xcc\x81/\xf0\x9f\x98\x80')
            self.assertEqual(body[:body_size], b'\0\xff\r\n')
            self.assertEqual([x for x in f.database_events if x[:2] == ('call',12)][-1][4], ('sdk/原',cursor,16))
        db.close()

    def test_zero_body_and_notfound_are_distinct_and_do_not_advance_any_cursor(self):
        f = DatabaseFixture(); db = f.database(); f.row_body = b''
        key = bytearray(512)
        fact, key_size, body_size = db.scan_after_into('scope','',key,bytearray())
        self.assertTrue(fact.has_row); self.assertGreater(key_size,0); self.assertEqual(body_size,0)
        f.operation_issue[12] = 15
        before = sum(x[0] == 'copy' for x in f.database_events)
        with self.assertRaises(_OriginalDatabaseError) as error:
            db.scan_after_into('scope','exact',key,bytearray())
        self.assertFalse(error.exception.unknown); self.assertEqual(error.exception.fact.issue_family,15)
        self.assertEqual(sum(x[0] == 'copy' for x in f.database_events),before)
        db.close()

    def test_postcheck_or_large_row_refusal_copies_neither_key_nor_body(self):
        for refusal in ('after','size'):
            with self.subTest(refusal=refusal):
                f=DatabaseFixture();db=f.database()
                if refusal=='after': f.operation_after[12]=4
                else: f.operation_issue[12]=18
                key,body=bytearray(512),bytearray(16)
                with self.assertRaises(_OriginalDatabaseError) as error:
                    db.scan_after_into('scope','unchanged',key,body)
                self.assertFalse(error.exception.unknown)
                self.assertFalse(any(x[0] in ('copy','key') for x in f.database_events))
                self.assertEqual((key,body),(bytearray(512),bytearray(16)));db.close()

    def test_input_or_busy_refusal_precedes_foreign_scan(self):
        f=DatabaseFixture();db=f.database();before=list(f.database_events)
        same=bytearray(8)
        for args in [('scope','a'*513,bytearray(512),bytearray(8)),
                     ('scope','',bytearray(),bytearray(8)),
                     ('scope','',bytearray(513),bytearray(8)),
                     ('scope','',same,same),('scope','',bytearray(512),bytearray(1025))]:
            with self.assertRaises(ValueError):db.scan_after_into(*args)
        f.host._busy=True
        with self.assertRaises(ValueError):db.scan_after_into('scope','',bytearray(512),bytearray(8))
        self.assertTrue(f.host._busy);f.host._busy=False
        self.assertEqual(f.database_events,before);self.assertIsNone(db._unknown);db.close()

    def test_key_copy_loss_keeps_original_reply_and_parent_custody(self):
        f=DatabaseFixture();db=f.database()
        def lost(*args):raise OSError('key output response lost')
        f.database_functions.calls['copy_key']=lost
        with self.assertRaises(_OriginalDatabaseError) as error:
            db.scan_after_into('scope','',bytearray(512),bytearray(8))
        self.assertTrue(error.exception.unknown);self.assertIsNotNone(db._reply.value)
        self.assertIs(db._library._database_original,db)
        before=list(f.database_events)
        with self.assertRaises(_OriginalDatabaseError):db.close()
        self.assertEqual(f.database_events,before)

    def test_original_sql_unknown_is_not_scan_or_inventory_permission(self):
        f=DatabaseFixture();db=f.database();f.loss_operation=8
        with self.assertRaises(_OriginalDatabaseError) as error:db.transaction(8)
        before=list(f.database_events)
        with self.assertRaises(_OriginalDatabaseError) as again:
            db.scan_after_into('scope','',bytearray(512),bytearray(8))
        self.assertIs(again.exception,error.exception);self.assertEqual(f.database_events,before)
        db.close()


if __name__=='__main__':unittest.main()
