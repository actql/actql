"""Independent Python slot/call faults; actual SQLite/DLL is separate."""
import copy
import ctypes as C
import pickle
from threading import Thread
import unittest
from unittest.mock import patch

from test_local_native_sqlite_custody import SqliteFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_sqlite_database import (
    _OriginalDatabaseCustody, _OriginalDatabaseError, _OriginalDatabaseFunctions)
from actql_sdk._local_native_domain_custody import _OriginalDomainError


class DatabaseFixture(SqliteFixture):
    def __init__(self):
        super().__init__()
        self.database_events, self.database_facts = [], {}
        self.bound = 1024
        self.open_issue = self.open_after = self.database_close_issue = 0
        self.original_present = True
        self.wrong_host = False
        self.database_capture_fault = self.drop_fault = self.database_finish_fault = None
        self.open_fault = self.copy_fault = None
        self.loss_operation = None
        self.operation_issue, self.operation_after = {}, {}
        self.row_body, self.row_revision = b'\x00\xff\r\n', 3
        self.override = {}
        self.on_operation = None
        calls = {
            'restore_utf16_into': lambda h, l, p, n, b, r: self.open(1, h, l, p, n, b, r),
            'initialize_utf16_into': lambda h, l, p, n, b, d, i, r: self.open(2, h, l, p, n, b, r, (d, i)),
            'originals_into': self.capture, 'drop_reply': self.drop_database,
            'finish_closed_data': self.finish_database, 'finish_refused_open': self.refused_database,
            'observe_into': lambda h, o, r: self.database_call(3, h, o, r),
            'read_utf16_into': lambda h, o, s, sn, k, kn, n, r: self.database_call(4, h, o, r, self.text(s, sn), self.text(k, kn), n),
            'insert_utf16_into': lambda h, o, s, sn, k, kn, b, n, r: self.database_call(5, h, o, r, self.text(s, sn), self.text(k, kn), bytes(b[:n])),
            'compare_utf16_into': lambda h, o, s, sn, k, kn, e, b, n, r: self.database_call(6, h, o, r, self.text(s, sn), self.text(k, kn), e, bytes(b[:n])),
            'transaction_into': lambda h, o, op, r: self.database_call(op, h, o, r),
            'close_into': lambda h, o, r: self.database_call(10, h, o, r),
            'fence_into': lambda h, o, r: self.database_call(11, h, o, r),

            'capacity_reserve_utf16_into': lambda h,o,s,sn,k,kn,b,ob,mb,mo,r: self.database_call(13,h,o,r,self.text(s,sn),self.text(k,kn),b,ob,mb,mo),
            'capacity_usage_utf16_into': lambda h,o,s,sn,r: self.database_call(14,h,o,r,self.text(s,sn)),
            'capacity_release_utf16_into': lambda h,o,s,sn,k,kn,b,ob,r: self.database_call(15,h,o,r,self.text(s,sn),self.text(k,kn),b,ob),
            'capacity_read_utf16_into': lambda h,o,s,sn,k,kn,r: self.database_call(16,h,o,r,self.text(s,sn),self.text(k,kn)),
            'database_usage_into': lambda h,o,r: self.database_call(17,h,o,r),
            'transaction_state_into': lambda h,o,r: self.database_call(18,h,o,r),
            'header_utf16_into': lambda h,o,s,sn,k,kn,r: self.database_call(19,h,o,r,self.text(s,sn),self.text(k,kn)),
            'begin_read_into': lambda h,o,r: self.database_call(20,h,o,r),
            'capacity_reserve_bounded_utf16_into': lambda h,o,s,sn,k,kn,b,ob,mb,mo,mr,r: self.database_call(21,h,o,r,self.text(s,sn),self.text(k,kn),b,ob,mb,mo,mr),
            'copy_row': self.copy_row,
            'copy_key': self.copy_key,
            'scan_utf16_into': lambda h, o, s, sn, k, kn, n, r: self.database_call(12, h, o, r, self.text(s, sn), self.text(k, kn), n),
        }
        for name in ('operation', 'stage', 'issue_family', 'after_issue_family', 'has_row', 'revision', 'body_bound', 'capacity_changed', 'reserved_bytes', 'reserved_objects',
                     'record_count', 'record_body_bytes', 'reservation_count', 'transaction_active', 'has_header', 'header_body_bytes'):
            calls[name] = lambda r, key=name: self.database_facts[r.value][key]
        for name, call in calls.items():
            setattr(self.host._functions.library, 'actql_sqlite_database_' + name, Function(call))
        self.database_functions = _OriginalDatabaseFunctions(self.host._functions.library)

    @staticmethod
    def text(text, units):
        return C.string_at(text, units * 2).decode('utf-16-le')

    def result_database(self, out, operation, stage, issue=0, after=0):
        key = 2600 + len(self.database_facts)
        present = operation in (4, 12, 24, 25) and self.row_body is not None and issue == 0
        self.database_facts[key] = dict(operation=operation, stage=stage,
            issue_family=issue, after_issue_family=after, has_row=int(present),
            revision=self.row_revision if present else 0 if operation in (5, 6, 19, 26) and not issue else -1,
            body_bound=self.bound if self.original_present else -1,
            capacity_changed=1 if operation in (13,15,21) and not issue else -1,
            reserved_bytes=8 if operation in (14,16,27,28) and not issue else -1,
            reserved_objects=1 if operation in (14,16,27,28) and not issue else -1,
            record_count=3 if operation in (17,29) and not issue else -1,
            record_body_bytes=8 if operation in (17,29) and not issue else -1,
            reservation_count=2 if operation in (17,29) and not issue else -1,
            transaction_active=0 if operation==18 and not issue else -1,
            has_header=int(operation in (19,26) and not issue),
            header_body_bytes=0 if operation in (19,26) and not issue else -1) | self.override
        out._obj.value = key

    def open(self, operation, host, library, path, units, bound, reply, ownership=None):
        self.database_events.append(('open', operation, host.value, library.value,
                                     self.text(path, units), bound, ownership))
        self.bound = bound
        self.result_database(reply, operation, 1 if self.original_present else 0, self.open_issue, self.open_after)
        if self.open_fault: raise self.open_fault
        return 0

    def capture(self, reply, host, library, original):
        self.database_events.append(('capture', reply.value))
        host._obj.value = 999 if self.wrong_host else 101
        library._obj.value = 401
        original._obj.value = 501 if self.original_present else None
        if self.database_capture_fault: raise self.database_capture_fault
        return 0

    def database_call(self, operation, host, original, reply, *inputs):
        self.database_events.append(('call', operation, host.value, original.value, inputs))
        if self.on_operation: self.on_operation(operation)
        issue = self.database_close_issue if operation == 10 else self.operation_issue.get(operation, 0)
        self.result_database(reply, operation, 3 if operation == 10 else 2, issue,
                             self.operation_after.get(operation, 0))
        if self.loss_operation == operation:
            self.loss_operation = None
            raise OSError('published original SQL response lost')
        return 0

    def copy_row(self, reply, host, library, original, buffer, capacity, length):
        self.database_events.append(('copy', reply.value, host.value, library.value, original.value, capacity))
        if self.row_body is None or len(self.row_body) > capacity: return -2
        for i, byte in enumerate(self.row_body): buffer[i] = byte
        length._obj.value = len(self.row_body)
        if self.copy_fault: raise self.copy_fault
        return 0

    def copy_key(self, reply, host, library, original, buffer, capacity, length):
        self.database_events.append(('key', reply.value, host.value, library.value, original.value, capacity))
        key = b'e\xcc\x81/\xf0\x9f\x98\x80'
        if len(key) > capacity: return -2
        for i, byte in enumerate(key): buffer[i] = byte
        length._obj.value = len(key)
        return 0

    def drop_database(self, reply, host, library, original):
        self.database_events.append(('drop', reply._obj.value, host.value, library.value, original.value))
        reply._obj.value = None
        if self.drop_fault: raise self.drop_fault
        return 0

    def finish_database(self, host, library, original, reply):
        self.database_events.append(('finish', host._obj.value, library._obj.value, original._obj.value))
        host._obj.value = library._obj.value = original._obj.value = reply._obj.value = None
        if self.database_finish_fault: raise self.database_finish_fault
        return 0

    def refused_database(self, host, library, reply):
        self.database_events.append(('refused', host._obj.value, library._obj.value))
        host._obj.value = library._obj.value = reply._obj.value = None
        return 0

    def database(self, library=None, **overrides):
        library = self.sqlite() if library is None else library
        return _OriginalDatabaseCustody._open_original(library, self.database_functions,
            self.read_functions, **({'path': '/private/原/😀.sqlite3', 'max_body_bytes': 1024} | overrides))


class OriginalDatabaseCustodyTests(unittest.TestCase):
    def test_original_read_write_binary_unicode_and_child_first_cleanup(self):
        f = DatabaseFixture(); library = f.sqlite(); db = f.database(library)
        self.assertIs(library._database_original, db)
        before = list(f.sql_events)
        with self.assertRaises(ValueError): library.close()
        self.assertEqual(f.sql_events, before)
        row = bytearray(16); fact, length = db.read_into('e\u0301/原', '😀', row)
        self.assertEqual((fact.operation, fact.stage, fact.revision, length), (4, 2, 3, 4))
        self.assertEqual(row[:length], b'\x00\xff\r\n')
        self.assertEqual(db.insert('原', 'e\u0301', b'\0\xff').revision, 0)
        db.compare_exchange('原', 'e\u0301', 0, b'')
        self.assertEqual(next(x for x in f.database_events if x[:2] == ('call', 5))[4], ('原', 'e\u0301', b'\0\xff'))
        db.close(); db.close(); library.close(); library._domain.close_after_stop()
        self.assertTrue(db._closed and library._closed)
        self.assertEqual(sum(x[0] == 'finish' for x in f.database_events), 1)

    def test_owned_initialize_and_existing_only_restore_are_distinct(self):
        f = DatabaseFixture(); db = f.database(ownership=(31, 47))
        self.assertEqual(f.database_events[0][1:], (2, 101, 401, '/private/原/😀.sqlite3', 1024, (31, 47)))
        db.close()
        g = DatabaseFixture(); restored = g.database()
        self.assertEqual(g.database_events[0][1], 1)
        restored.close()

    def test_empty_present_row_and_notfound_are_not_null_or_success(self):
        f = DatabaseFixture(); db = f.database(); f.row_body = b''
        fact, size = db.read_into('scope', 'empty', bytearray(8))
        self.assertTrue(fact.has_row); self.assertEqual(size, 0)
        f.operation_issue[4] = 15
        with self.assertRaises(_OriginalDatabaseError) as error: db.read_into('scope', 'absent', bytearray(8))
        self.assertFalse(error.exception.unknown); self.assertEqual(error.exception.fact.issue_family, 15)
        self.assertFalse(error.exception.fact.has_row)
        db.close()

    def test_known_preflight_and_postcall_refusals_keep_actual_stage_and_cleanup(self):
        f = DatabaseFixture(); db = f.database(); f.operation_after[4] = 4
        with self.assertRaises(_OriginalDatabaseError) as error: db.read_into('s', 'k', bytearray(8))
        self.assertFalse(error.exception.unknown)
        self.assertEqual((error.exception.fact.stage, error.exception.fact.after_issue_family), (2, 4))
        self.assertFalse(any(x[0] == 'copy' for x in f.database_events))
        self.assertIsNone(db._unknown)
        f.operation_after.clear(); db.close()

    def test_busy_and_foreign_thread_refuse_before_registration_or_sql(self):
        for operation in ('open', 'read', 'close'):
            for foreign in (False, True):
                with self.subTest(operation=operation, foreign=foreign):
                    f = DatabaseFixture(); library = f.sqlite()
                    db = None if operation == 'open' else f.database(library)
                    before = list(f.database_events); errors = []
                    action = lambda: f.database(library) if db is None else db.read_into('s', 'k', bytearray(8)) if operation == 'read' else db.close()
                    def invoke():
                        try: action()
                        except BaseException as error: errors.append(error)
                    if foreign:
                        worker = Thread(target=invoke); worker.start(); worker.join(2); self.assertFalse(worker.is_alive())
                    else:
                        f.host._busy = True; invoke(); self.assertTrue(f.host._busy); f.host._busy = False
                    self.assertEqual(len(errors), 1); self.assertIs(type(errors[0]), ValueError)
                    self.assertEqual(f.database_events, before)
                    self.assertIs(library._database_original, db)
                    if db is None: db = f.database(library)
                    self.assertIsNone(db._unknown); db.close(); library.close()

    def test_reentry_does_not_steal_parent_busy_or_poison_original(self):
        f = DatabaseFixture(); db = f.database(); refused = []
        def reenter(operation):
            if operation == 5:
                self.assertTrue(f.host._busy)
                with self.assertRaises(ValueError): db.transaction(8)
                self.assertTrue(f.host._busy); refused.append(operation)
        f.on_operation = reenter
        db.insert('s', 'k', b'original')
        self.assertEqual(refused, [5]); self.assertIsNone(db._unknown)
        self.assertEqual([x[1] for x in f.database_events if x[0] == 'call'], [5])
        db.close()

    def test_known_read_scope_refusal_and_parent_unknown_are_not_new_database_unknown(self):
        f = DatabaseFixture(); db = f.database(); f.read_issue = 5
        with self.assertRaises(_OriginalDomainError): db.read_into('s', 'k', bytearray(8))
        self.assertIsNone(db._unknown); f.read_issue = 0
        parent = db._library._mark_unknown()
        with self.assertRaises(type(parent)) as error: db.transaction(7)
        self.assertIs(error.exception, parent); self.assertIsNone(db._unknown)

    def test_partial_open_keeps_same_original_and_retries_only_known_cleanup(self):
        f = DatabaseFixture(); f.open_issue = 13
        with self.assertRaises(_OriginalDatabaseError) as error: f.database()
        db = error.exception.cleanup_database
        self.assertFalse(error.exception.unknown); self.assertEqual(db._original.value, 501)
        f.database_close_issue = 5
        with self.assertRaises(_OriginalDatabaseError) as pending: db.close()
        self.assertFalse(pending.exception.unknown); self.assertIs(db._library._database_original, db)
        f.database_close_issue = 0; db.close(); db._library.close()
        self.assertEqual(sum(x[0] == 'open' for x in f.database_events), 1)

    def test_refusal_without_database_finishes_data_but_never_reissues(self):
        f = DatabaseFixture(); library = f.sqlite(); f.original_present = False; f.open_issue = 4
        with self.assertRaises(_OriginalDatabaseError) as error: f.database(library)
        self.assertFalse(error.exception.unknown); self.assertTrue(error.exception.cleanup_database._closed)
        before = list(f.database_events)
        with self.assertRaises(ValueError): f.database(library)
        self.assertEqual(f.database_events, before); library.close()

    def test_lost_open_or_capture_and_foreign_original_keep_sticky_custody(self):
        for fault in ('open_fault', 'database_capture_fault', 'wrong_host'):
            with self.subTest(fault=fault):
                f = DatabaseFixture(); library = f.sqlite()
                setattr(f, fault, True if fault == 'wrong_host' else OSError('foreign loss'))
                with self.assertRaises(_OriginalDatabaseError) as error: f.database(library)
                db = error.exception.cleanup_database; before = list(f.database_events)
                self.assertTrue(error.exception.unknown); self.assertIs(library._database_original, db)
                with self.assertRaises(_OriginalDatabaseError) as again: db.close()
                self.assertIs(again.exception, error.exception); self.assertEqual(f.database_events, before)
                with self.assertRaises(ValueError): library.close()

    def test_published_lost_commit_reconciles_same_reply_fence_lookup_without_replay(self):
        f = DatabaseFixture(); db = f.database(); f.loss_operation = 8
        with self.assertRaises(_OriginalDatabaseError) as error: db.transaction(8)
        original = error.exception; self.assertTrue(original.unknown)
        self.assertIsNotNone(db._reply.value); self.assertIsNone(db._unknown)
        before = list(f.database_events)
        for action in (lambda: db.transaction(8), lambda: db.insert('s', 'k', b'new')):
            with self.assertRaises(_OriginalDatabaseError) as again: action()
            self.assertIs(again.exception, original)
        self.assertEqual(f.database_events, before)
        for _ in range(2):
            row = bytearray(8); fact, size = db.lookup_unconfirmed_into('s', 'k', row)
            self.assertEqual((fact.revision, size, row[:size]), (3, 4, b'\0\xff\r\n'))
        operations = [x[1] for x in f.database_events if x[0] == 'call']
        self.assertEqual(operations, [8, 11, 4, 4])
        self.assertIs(db._write_unknown, original)
        db.close(); self.assertTrue(db._closed); self.assertIs(db._write_unknown, original)

    def test_unconfirmed_active_transaction_lookup_stays_refused_and_invalid_query_does_not_fence(self):
        f = DatabaseFixture(); db = f.database(); f.loss_operation = 8
        with self.assertRaises(_OriginalDatabaseError): db.transaction(8)
        before = list(f.database_events)
        with self.assertRaises(ValueError): db.lookup_unconfirmed_into('s', 'k', bytearray())
        self.assertEqual(f.database_events, before)
        f.operation_issue[4] = 20
        with self.assertRaises(_OriginalDatabaseError) as error: db.lookup_unconfirmed_into('s', 'k', bytearray(8))
        self.assertFalse(error.exception.unknown); self.assertEqual(error.exception.fact.issue_family, 20)
        self.assertIsNotNone(db._write_unknown); db.close()

    def test_drop_or_final_data_loss_keeps_same_parent_without_another_close(self):
        for fault in ('drop_fault', 'database_finish_fault'):
            with self.subTest(fault=fault):
                f = DatabaseFixture(); db = f.database()
                setattr(f, fault, OSError('response after data release lost'))
                with self.assertRaises(_OriginalDatabaseError) as error:
                    if fault == 'drop_fault': db.transaction(7)
                    else: db.close()
                before = list(f.database_events)
                with self.assertRaises(_OriginalDatabaseError) as again: db.close()
                self.assertIs(again.exception, error.exception)
                self.assertEqual(f.database_events, before); self.assertFalse(db._closed)
                self.assertIs(db._library._database_original, db)

    def test_argument_allocation_failure_is_before_owner_entry_and_registration(self):
        f = DatabaseFixture(); library = f.sqlite()
        with patch('actql_sdk._local_native_sqlite_database.byref', side_effect=MemoryError('slot')):
            with self.assertRaises(MemoryError): f.database(library)
        self.assertIsNone(library._database_original); self.assertFalse(f.host._busy)
        self.assertEqual(f.database_events, [])

    def test_input_bounds_closed_transaction_selector_and_foreign_component_are_local(self):
        f = DatabaseFixture(); db = f.database(); before = list(f.database_events)
        for action in (lambda: db.transaction(True), lambda: db.transaction(12),
                       lambda: db.insert('s', 'k', b'x' * 1025),
                       lambda: db.insert('s', '\0', b''), lambda: db.read_into('s', 'k', bytearray()),
                       lambda: db.compare_exchange('s', 'k', True, b'')):
            with self.assertRaises(ValueError): action()
        self.assertEqual(f.database_events, before)
        other = DatabaseFixture(); library = f.sqlite(f.take())
        with self.assertRaises(ValueError): _OriginalDatabaseCustody._open_original(library,
            other.database_functions, f.read_functions, path='/p', max_body_bytes=8)
        self.assertIsNone(library._database_original); db.close(); library.close()

    def test_copy_pickle_and_wrong_fact_never_transfer_custody(self):
        f = DatabaseFixture(); db = f.database()
        for action in (lambda: copy.copy(db), lambda: copy.deepcopy(db), lambda: pickle.dumps(db)):
            with self.assertRaises(TypeError): action()
        f.override = {'operation': 8}
        with self.assertRaises(_OriginalDatabaseError) as error: db.read_into('s', 'k', bytearray(8))
        self.assertTrue(error.exception.unknown); self.assertIsNotNone(db._reply.value)
        before = list(f.database_events)
        with self.assertRaises(_OriginalDatabaseError): db.close()
        self.assertEqual(f.database_events, before)


if __name__ == '__main__':
    unittest.main()
