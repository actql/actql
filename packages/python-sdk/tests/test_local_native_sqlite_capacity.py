"""Independent original capacity call/fact counters; no Python formula."""
import unittest
from test_local_native_sqlite_database_custody import DatabaseFixture
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseError


class OriginalDatabaseCapacityTests(unittest.TestCase):
    def test_exact_unicode_amounts_and_no_implicit_transaction(self):
        f=DatabaseFixture();db=f.database()
        fact=db.reserve_capacity_in_transaction('e\u0301/原','😀',8,1,64,2)
        self.assertIs(fact.capacity_changed,True)
        self.assertEqual([x[4] for x in f.database_events if x[:2]==('call',13)], [('e\u0301/原','😀',8,1,64,2)])
        self.assertIs(db.release_capacity_in_transaction('e\u0301/原','😀',8,1).capacity_changed,True)
        self.assertEqual([x[1] for x in f.database_events if x[0]=='call'],[13,15])
        db.close()

    def test_false_zero_and_absent_capacity_fields_are_distinct(self):
        f=DatabaseFixture();db=f.database();f.override={'capacity_changed':0}
        self.assertIs(db.reserve_capacity_in_transaction('s','k',0,0,0,0).capacity_changed,False)
        f.override={'reserved_bytes':0,'reserved_objects':0}
        usage=db.capacity_usage('s')
        self.assertEqual((usage.reserved_bytes,usage.reserved_objects),(0,0));self.assertIsNone(usage.capacity_changed)
        f.override={}
        self.assertIsNone(db.transaction(7).reserved_bytes)
        db.close()

    def test_known_refusal_keeps_stage_and_postcheck_actual_observation(self):
        f=DatabaseFixture();db=f.database();f.operation_issue[13]=19
        with self.assertRaises(_OriginalDatabaseError) as error:db.reserve_capacity_in_transaction('s','k',8,1,1,1)
        self.assertFalse(error.exception.unknown);self.assertEqual(error.exception.fact.issue_family,19)
        self.assertIsNone(error.exception.fact.capacity_changed)
        f.operation_after[14]=4
        with self.assertRaises(_OriginalDatabaseError) as error:db.capacity_usage('s')
        self.assertFalse(error.exception.unknown)
        self.assertEqual((error.exception.fact.stage,error.exception.fact.after_issue_family,error.exception.fact.reserved_bytes),(2,4,8))
        self.assertIsNone(db._unknown);db.close()

    def test_capacity_input_and_busy_refuse_without_foreign_call_or_registration_change(self):
        f=DatabaseFixture();db=f.database();before=list(f.database_events)
        for bad in (True,-1,2**63,1.0):
            with self.assertRaises(ValueError):db.reserve_capacity_in_transaction('s','k',bad,1,64,2)
            with self.assertRaises(ValueError):db.release_capacity_in_transaction('s','k',8,bad)
        f.host._busy=True
        with self.assertRaises(ValueError):db.capacity_usage('s')
        self.assertTrue(f.host._busy);f.host._busy=False
        self.assertEqual(f.database_events,before);self.assertIsNone(db._unknown);db.close()

    def test_capacity_reply_loss_preserves_original_and_never_replays_or_releases(self):
        for operation in (13,15):
            with self.subTest(operation=operation):
                f=DatabaseFixture();db=f.database();f.loss_operation=operation
                call=lambda:db.reserve_capacity_in_transaction('s','k',8,1,64,2) if operation==13 else db.release_capacity_in_transaction('s','k',8,1)
                with self.assertRaises(_OriginalDatabaseError) as error:call()
                self.assertTrue(error.exception.unknown);self.assertIsNone(db._unknown);self.assertIsNotNone(db._reply.value)
                before=list(f.database_events)
                for action in (call,lambda:db.capacity_usage('s')):
                    with self.assertRaises(_OriginalDatabaseError) as again:action()
                    self.assertIs(again.exception,error.exception)
                self.assertEqual(f.database_events,before);db.close()
                self.assertIs(db._write_unknown,error.exception)
                self.assertEqual(sum(x[:2]==('call',operation) for x in f.database_events),1)

    def test_malformed_capacity_observations_keep_same_reply_and_unknown_custody(self):
        for fields in ({'reserved_bytes':-1},{'reserved_objects':2**63},{'reserved_bytes':True},
                       {'capacity_changed':1}):
            with self.subTest(fields=fields):
                f=DatabaseFixture();db=f.database();f.override=fields
                with self.assertRaises(_OriginalDatabaseError) as error:db.capacity_usage('s')
                self.assertTrue(error.exception.unknown);self.assertIsNotNone(db._reply.value)
                self.assertIs(db._library._database_original,db)
                before=list(f.database_events)
                with self.assertRaises(_OriginalDatabaseError):db.close()
                self.assertEqual(f.database_events,before)

    def test_original_lost_commit_usage_lookup_is_readonly_and_keeps_unknown(self):
        f=DatabaseFixture();db=f.database();f.loss_operation=8
        with self.assertRaises(_OriginalDatabaseError) as error:db.transaction(8)
        for _ in range(2):
            usage=db.lookup_unconfirmed_capacity_usage('s')
            self.assertEqual((usage.reserved_bytes,usage.reserved_objects),(8,1))
        self.assertEqual([x[1] for x in f.database_events if x[0]=='call'],[8,11,14,14])
        self.assertIs(db._write_unknown,error.exception)
        with self.assertRaises(_OriginalDatabaseError) as again:db.capacity_usage('s')
        self.assertIs(again.exception,error.exception);db.close()

    def test_invalid_or_busy_unconfirmed_usage_does_not_consume_fence_or_reply(self):
        f=DatabaseFixture();db=f.database();f.loss_operation=8
        with self.assertRaises(_OriginalDatabaseError):db.transaction(8)
        before=list(f.database_events)
        with self.assertRaises(ValueError):db.lookup_unconfirmed_capacity_usage('\0')
        f.host._busy=True
        with self.assertRaises(ValueError):db.lookup_unconfirmed_capacity_usage('s')
        self.assertTrue(f.host._busy);f.host._busy=False
        self.assertEqual(f.database_events,before);self.assertIsNone(db._unknown);db.close()


if __name__=='__main__':unittest.main()
