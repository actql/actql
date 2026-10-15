"""Physical metadata transport counters, not SQL/Store adoption proof."""
import unittest
from test_local_native_sqlite_database_custody import DatabaseFixture
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseError


class OriginalDatabaseMetadataTests(unittest.TestCase):
    def test_exact_original_key_totals_and_transaction_state_do_not_write(self):
        f = DatabaseFixture(); db = f.database()
        capacity = db.read_capacity('e\u0301/原', '😀')
        self.assertEqual((capacity.reserved_bytes, capacity.reserved_objects), (8, 1))
        usage = db.database_usage()
        self.assertEqual((usage.record_count, usage.record_body_bytes, usage.reservation_count), (3, 8, 2))
        self.assertIs(db.transaction_state().transaction_active, False)
        self.assertEqual([x[1] for x in f.database_events if x[0] == 'call'], [16, 17, 18])
        self.assertEqual([x[4] for x in f.database_events if x[:2] == ('call', 16)], [('e\u0301/原', '😀')])
        db.close()

    def test_zero_inactive_and_missing_are_separate(self):
        f = DatabaseFixture(); db = f.database()
        f.override = {'reserved_bytes': 0, 'reserved_objects': 0}
        self.assertEqual(db.read_capacity('s', 'k').reserved_bytes, 0)
        f.override = {'record_count': 0, 'record_body_bytes': 0, 'reservation_count': 0}
        self.assertEqual(db.database_usage().record_count, 0)
        f.override = {'transaction_active': 1}
        self.assertIs(db.transaction_state().transaction_active, True)
        f.override = {}; f.operation_issue[16] = 15
        with self.assertRaises(_OriginalDatabaseError) as error: db.read_capacity('s', 'missing')
        self.assertFalse(error.exception.unknown)
        self.assertEqual(error.exception.fact.issue_family, 15)
        self.assertIsNone(error.exception.fact.reserved_bytes)
        db.close()

    def test_query_failure_and_postcheck_refusal_keep_original_data_separate(self):
        f = DatabaseFixture(); db = f.database(); f.operation_issue[17] = 20
        with self.assertRaises(_OriginalDatabaseError) as error: db.database_usage()
        self.assertFalse(error.exception.unknown)
        self.assertIsNone(error.exception.fact.record_count)
        f.operation_after[18] = 4
        with self.assertRaises(_OriginalDatabaseError) as error: db.transaction_state()
        self.assertFalse(error.exception.unknown)
        self.assertIs(error.exception.fact.transaction_active, False)
        self.assertEqual(error.exception.fact.after_issue_family, 4)
        self.assertIsNone(db._unknown); db.close()

    def test_known_busy_or_invalid_input_changes_no_original_slot(self):
        f = DatabaseFixture(); db = f.database(); before = list(f.database_events)
        with self.assertRaises(ValueError): db.read_capacity('s', 'x' * 513)
        f.host._busy = True
        for call in (db.database_usage, db.transaction_state, lambda: db.read_capacity('s', 'k')):
            with self.assertRaises(ValueError): call()
        self.assertTrue(f.host._busy); f.host._busy = False
        self.assertEqual(f.database_events, before)
        self.assertIsNone(db._unknown); db.close()

    def test_malformed_scalar_keeps_same_original_and_pending_reply(self):
        for operation, override in ((16, {'reserved_bytes': True}), (17, {'record_count': -1}),
                                    (17, {'record_body_bytes': 2**63}), (17, {'reservation_count': False}),
                                    (18, {'transaction_active': -1}), (18, {'transaction_active': True})):
            with self.subTest(operation=operation, override=override):
                f = DatabaseFixture(); db = f.database(); f.override = override
                call = lambda: db.read_capacity('s', 'k') if operation == 16 else db.database_usage() if operation == 17 else db.transaction_state()
                with self.assertRaises(_OriginalDatabaseError) as error: call()
                self.assertTrue(error.exception.unknown)
                self.assertIs(db._library._database_original, db)
                self.assertIsNotNone(db._reply.value)
                before = list(f.database_events)
                with self.assertRaises(_OriginalDatabaseError): db.close()
                self.assertEqual(f.database_events, before)

    def test_lost_commit_original_lookup_preserves_unknown_and_sends_no_write(self):
        f = DatabaseFixture(); db = f.database(); f.loss_operation = 8
        with self.assertRaises(_OriginalDatabaseError) as error: db.transaction(8)
        self.assertIs(db.lookup_unconfirmed_transaction_state().transaction_active, False)
        self.assertEqual(db.lookup_unconfirmed_capacity('s', 'k').reserved_bytes, 8)
        self.assertEqual(db.lookup_unconfirmed_database_usage().record_count, 3)
        self.assertEqual([x[1] for x in f.database_events if x[0] == 'call'], [8, 11, 18, 16, 17])
        self.assertIs(db._write_unknown, error.exception)
        before = list(f.database_events)
        with self.assertRaises(_OriginalDatabaseError) as again: db.transaction(7)
        self.assertIs(again.exception, error.exception)
        self.assertEqual(f.database_events, before); db.close()

    def test_lookup_requires_original_unknown_and_busy_does_not_consume_fence(self):
        f = DatabaseFixture(); db = f.database()
        with self.assertRaises(ValueError): db.lookup_unconfirmed_database_usage()
        f.loss_operation = 8
        with self.assertRaises(_OriginalDatabaseError): db.transaction(8)
        before = list(f.database_events)
        with self.assertRaises(ValueError): db.lookup_unconfirmed_capacity('s', '\0')
        f.host._busy = True
        with self.assertRaises(ValueError): db.lookup_unconfirmed_transaction_state()
        self.assertTrue(f.host._busy); f.host._busy = False
        self.assertEqual(f.database_events, before); db.close()


if __name__ == '__main__': unittest.main()
