"""Independent slot/call faults. Actual matching Native/DLL is separate."""
import copy
import pickle
from threading import Thread
import unittest
from unittest.mock import patch
from test_local_native_domain_read import ReadFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_sqlite import _OriginalSqliteCustody, _OriginalSqliteFunctions, _OriginalSqliteError
from actql_sdk._local_native_domain_custody import _OriginalDomainError


class SqliteFixture(ReadFixture):
    def __init__(self):
        super().__init__()
        self.sql_facts = {}
        self.sql_events = []
        self.sql_issue = 0
        self.sql_close_issue = 0
        self.sql_current_issue = 0
        self.sql_present = True
        self.sql_fault = None
        self.sql_capture_fault = None
        self.sql_finish_fault = None
        self.sql_drop_fault = None
        self.sql_wrong_operation = None
        self.sql_wrong_host = False
        functions = {'prepare_utf16_into': self.sql_prepare,
                     'current_into': lambda h, o, r: self.sql_call(2, h, o, r),
                     'close_into': lambda h, o, r: self.sql_call(3, h, o, r),
                     'originals_into': self.sql_originals, 'drop_reply': self.sql_drop,
                     'finish_closed_data': self.sql_finish, 'finish_refused_prepare': self.sql_refused,
                     'operation': lambda r: self.sql_facts[r.value][0],
                     'issue_family': lambda r: self.sql_facts[r.value][1]}
        for name, call in functions.items():
            setattr(self.host._functions.library, 'actql_sqlite_' + name, Function(call))
        self.sql_functions = _OriginalSqliteFunctions(self.host._functions.library)

    def sql_result(self, slot, operation, issue):
        key = 1600 + len(self.sql_facts)
        self.sql_facts[key] = (self.sql_wrong_operation or operation, issue)
        slot._obj.value = key

    def sql_prepare(self, host, domain, text, units, heap, diagnostic, reply):
        self.sql_events.append(('prepare', host.value, domain.value, tuple(text[:units]), heap, diagnostic))
        self.sql_result(reply, 1, self.sql_issue)
        if self.sql_fault: raise self.sql_fault
        return 0

    def sql_originals(self, reply, host, domain, original):
        self.sql_events.append(('capture', reply.value))
        host._obj.value = 999 if self.sql_wrong_host else 101
        domain._obj.value = 301
        original._obj.value = 401 if self.sql_present else None
        if self.sql_capture_fault: raise self.sql_capture_fault
        return 0

    def sql_drop(self, reply, host, domain, original):
        self.sql_events.append(('drop', reply._obj.value))
        reply._obj.value = None
        if self.sql_drop_fault: raise self.sql_drop_fault
        return 0

    def sql_call(self, operation, host, original, reply):
        self.sql_events.append(('call', operation, host.value, original.value))
        self.sql_result(reply, operation, self.sql_current_issue if operation == 2 else self.sql_close_issue)
        return 0

    def sql_finish(self, host, domain, original, reply):
        self.sql_events.append(('finish', host._obj.value, domain._obj.value, original._obj.value))
        host._obj.value = domain._obj.value = original._obj.value = reply._obj.value = None
        if self.sql_finish_fault: raise self.sql_finish_fault
        return 0

    def sql_refused(self, host, domain, reply):
        self.sql_events.append(('refused', host._obj.value, domain._obj.value))
        host._obj.value = domain._obj.value = reply._obj.value = None
        return 0

    def sqlite(self, domain=None, **overrides):
        domain = self.take() if domain is None else domain
        return _OriginalSqliteCustody._prepare_original(domain, self.sql_functions,
            **({'path': '/private/é-😀/sqlite.dylib', 'heap_bytes': 524288,
                'diagnostic_ceiling': 128} | overrides))


class OriginalSqliteCustodyTests(unittest.TestCase):
    def test_busy_prepare_refuses_locally_without_registration_and_later_cleanup_succeeds(self):
        f = SqliteFixture(); d = f.take(); before = list(f.events)
        f.host._busy = True
        try:
            with self.assertRaises(ValueError): f.sqlite(d)
            self.assertTrue(f.host._busy)
            self.assertIsNone(d._sqlite_library_original)
            self.assertIsNone(d._unknown)
            self.assertEqual(f.sql_events, [])
            self.assertEqual(f.events, before)
        finally:
            f.host._busy = False
        original = f.sqlite(d); original.close(); d.close_after_stop()
        self.assertTrue(original._closed and d._closed)
        self.assertEqual(sum(event[0] == 'prepare' for event in f.sql_events), 1)

    def test_busy_current_and_close_preserve_existing_slots_and_later_cleanup(self):
        for operation in ('current', 'close'):
            with self.subTest(operation=operation):
                f = SqliteFixture(); d = f.take(); original = f.sqlite(d)
                slots = tuple(slot.value for slot in (original._host, original._native_domain,
                                                     original._original, original._reply))
                before = list(f.sql_events); f.host._busy = True
                try:
                    with self.assertRaises(ValueError): getattr(original, operation)()
                    self.assertTrue(f.host._busy)
                    self.assertIsNone(original._unknown)
                    self.assertIs(d._sqlite_library_original, original)
                    self.assertEqual(tuple(slot.value for slot in (original._host, original._native_domain,
                                                                  original._original, original._reply)), slots)
                    self.assertEqual(f.sql_events, before)
                finally:
                    f.host._busy = False
                original.close(); d.close_after_stop()
                self.assertTrue(original._closed and d._closed)
                self.assertEqual(sum(event[0] == 'call' and event[1] == 3 for event in f.sql_events), 1)

    def test_foreign_thread_preflight_preserves_busy_registration_and_existing_cleanup(self):
        for operation in ('prepare', 'current', 'close'):
            for busy in (False, True):
                with self.subTest(operation=operation, busy=busy):
                    f = SqliteFixture(); d = f.take()
                    original = None if operation == 'prepare' else f.sqlite(d)
                    before = list(f.sql_events); errors = []
                    def foreign():
                        try:
                            if original is None: f.sqlite(d)
                            else: getattr(original, operation)()
                        except BaseException as error: errors.append(error)
                    f.host._busy = busy
                    worker = Thread(target=foreign); worker.start(); worker.join(2)
                    self.assertFalse(worker.is_alive())
                    self.assertEqual(len(errors), 1); self.assertIs(type(errors[0]), ValueError)
                    self.assertEqual(f.host._busy, busy)
                    self.assertIs(d._sqlite_library_original, original)
                    self.assertEqual(f.sql_events, before)
                    if original is not None: self.assertIsNone(original._unknown)
                    f.host._busy = False
                    if original is None: original = f.sqlite(d)
                    original.close(); d.close_after_stop()
                    self.assertTrue(original._closed and d._closed)

    def test_reentrant_prepare_does_not_poison_another_original_domain(self):
        f = SqliteFixture(); d = f.take(); nested = f.take()
        def prepare(*args):
            self.assertTrue(f.host._busy)
            with self.assertRaises(ValueError): f.sqlite(nested)
            self.assertTrue(f.host._busy)
            self.assertIsNone(nested._sqlite_library_original)
            self.assertEqual(f.sql_events, [])
            return f.sql_prepare(*args)
        f.sql_functions.prepare = Function(prepare)
        original = f.sqlite(d)
        self.assertIsNone(original._unknown)
        self.assertFalse(f.host._busy)
        original.close(); d.close_after_stop()
        self.assertTrue(original._closed and d._closed)
        self.assertEqual(sum(event[0] == 'prepare' for event in f.sql_events), 1)

    def test_reentrant_close_does_not_steal_outer_busy_or_poison_current_library(self):
        f = SqliteFixture(); d = f.take(); original = f.sqlite(d)
        def current(host, library, reply):
            self.assertTrue(f.host._busy)
            before = list(f.sql_events)
            with self.assertRaises(ValueError): original.close()
            self.assertTrue(f.host._busy)
            self.assertIsNone(original._unknown)
            self.assertEqual(f.sql_events, before)
            return f.sql_call(2, host, library, reply)
        f.sql_functions.current = Function(current)
        self.assertEqual(original.current().operation, 2)
        self.assertFalse(f.host._busy)
        original.close(); d.close_after_stop()
        self.assertTrue(original._closed and d._closed)
        self.assertEqual(sum(event[0] == 'call' and event[1] == 3 for event in f.sql_events), 1)

    def test_parent_unknown_stays_the_same_parent_refusal_without_new_sqlite_unknown(self):
        for prepared in (False, True):
            with self.subTest(prepared=prepared):
                f = SqliteFixture(); d = f.take()
                original = f.sqlite(d) if prepared else None
                before = list(f.sql_events); parent_error = f.host._mark_unknown()
                with self.assertRaises(type(parent_error)) as error:
                    if original is None: f.sqlite(d)
                    else: original.close()
                self.assertIs(error.exception, parent_error)
                self.assertFalse(f.host._busy)
                self.assertIs(d._sqlite_library_original, original)
                self.assertEqual(f.sql_events, before)
                if original is not None: self.assertIsNone(original._unknown)
                # An actual parent Unknown is deliberately not cleared to fake
                # a later cleanup ACK. Its original Host retains responsibility.

    def test_foreign_process_entry_is_local_and_preserves_original_cleanup(self):
        for prepared in (False, True):
            with self.subTest(prepared=prepared):
                f = SqliteFixture(); d = f.take()
                original = f.sqlite(d) if prepared else None
                before = list(f.sql_events)
                with patch('actql_sdk._local_native_control_custody.getpid', return_value=-1):
                    with self.assertRaises(ValueError):
                        if original is None: f.sqlite(d)
                        else: original.close()
                self.assertFalse(f.host._busy)
                self.assertIs(d._sqlite_library_original, original)
                self.assertEqual(f.sql_events, before)
                if original is None: original = f.sqlite(d)
                self.assertIsNone(original._unknown)
                original.close(); d.close_after_stop()
                self.assertTrue(original._closed and d._closed)

    def test_argument_slot_allocation_failure_is_before_entry_and_registration(self):
        f = SqliteFixture(); d = f.take()
        with patch('actql_sdk._local_native_sqlite.byref', side_effect=MemoryError('before SQLite call')):
            with self.assertRaises(MemoryError): f.sqlite(d)
        self.assertFalse(f.host._busy)
        self.assertIsNone(d._sqlite_library_original)
        self.assertEqual(f.sql_events, [])
        original = f.sqlite(d); original.close(); d.close_after_stop()
        self.assertTrue(original._closed and d._closed)

    def test_call_argument_allocation_failure_keeps_original_library_for_cleanup(self):
        for operation in ('current', 'close'):
            with self.subTest(operation=operation):
                f = SqliteFixture(); d = f.take(); original = f.sqlite(d)
                before = list(f.sql_events)
                with patch('actql_sdk._local_native_sqlite.byref', side_effect=MemoryError('before SQLite call')):
                    with self.assertRaises(MemoryError): getattr(original, operation)()
                self.assertFalse(f.host._busy)
                self.assertIsNone(original._unknown)
                self.assertIs(d._sqlite_library_original, original)
                self.assertEqual(f.sql_events, before)
                original.close(); d.close_after_stop()
                self.assertTrue(original._closed and d._closed)

    def test_domain_closed_during_preallocation_is_rechecked_before_registration(self):
        from ctypes import byref
        f = SqliteFixture(); d = f.take(); observed = []
        def close_before_entry(value):
            if not observed:
                observed.append(True); d.close_after_stop()
            return byref(value)
        with patch('actql_sdk._local_native_sqlite.byref', side_effect=close_before_entry):
            with self.assertRaises(ValueError): f.sqlite(d)
        self.assertTrue(d._closed)
        self.assertFalse(f.host._busy)
        self.assertIsNone(d._sqlite_library_original)
        self.assertEqual(f.sql_events, [])

    def test_prepare_current_close_share_original_domain_and_block_parent_until_data_ack(self):
        f = SqliteFixture(); d = f.take(); s = f.sqlite(d)
        self.assertIs(d._sqlite_library_original, s)
        with self.assertRaises(ValueError): d.close_after_stop()
        self.assertFalse(any(x[0] == 'finish' for x in f.events))
        self.assertEqual(s.current().operation, 2)
        s.close(); s.close()
        self.assertTrue(s._closed)
        self.assertIsNot(d._sqlite_library_original, s)
        self.assertFalse(d._closed)
        before = list(f.sql_events)
        with self.assertRaises(ValueError): f.sqlite(d)
        self.assertEqual(f.sql_events, before)
        d.close_after_stop(); self.assertTrue(d._closed)
        self.assertIsNone(d._sqlite_library_original)
        self.assertFalse(f.descriptor.close_attempted)
        with self.assertRaises(ValueError): s.current()

    def test_utf16_path_is_preserved_without_unicode_normalization(self):
        f = SqliteFixture(); s = f.sqlite(path='/é/😀/e\u0301.dylib')
        values = f.sql_events[0][3]
        self.assertIn(0xd83d, values); self.assertIn(0xde00, values)
        self.assertIn(0x301, values); self.assertIn(0xe9, values)
        s.close()

    def test_known_partial_refusal_keeps_same_library_cleanup(self):
        f = SqliteFixture(); d = f.take(); f.sql_issue = 12
        with self.assertRaises(_OriginalSqliteError) as e: f.sqlite(d)
        s = e.exception.cleanup_library
        self.assertFalse(e.exception.unknown)
        self.assertIs(d._sqlite_library_original, s)
        self.assertEqual(s._original.value, 401)
        self.assertEqual(e.exception.fact.issue_family, 12)
        f.sql_close_issue = 5
        with self.assertRaises(_OriginalSqliteError) as pending: s.close()
        self.assertFalse(pending.exception.unknown)
        self.assertFalse(s._closed)
        self.assertEqual(s._original.value, 401)
        with self.assertRaises(ValueError): d.close_after_stop()
        f.sql_close_issue = 0
        s.close()
        self.assertEqual(sum(x[0] == 'prepare' for x in f.sql_events), 1)
        self.assertEqual(sum(x[0] == 'finish' for x in f.sql_events), 1)

    def test_pre_acquisition_refusal_drops_only_data_not_domain_or_descriptor(self):
        f = SqliteFixture(); d = f.take(); f.sql_issue = 1; f.sql_present = False
        with self.assertRaises(_OriginalSqliteError) as e: f.sqlite(d)
        s = e.exception.cleanup_library
        self.assertFalse(e.exception.unknown)
        self.assertTrue(s._closed)
        self.assertFalse(d._closed)
        s.close()
        self.assertEqual(sum(x[0] == 'refused' for x in f.sql_events), 1)
        self.assertFalse(any(x[0] == 'finish' for x in f.sql_events))
        self.assertFalse(f.descriptor.close_attempted)

    def test_lost_prepare_response_keeps_same_slot_and_never_resends(self):
        f = SqliteFixture(); d = f.take(); f.sql_fault = OSError('reply lost after Native')
        with self.assertRaises(_OriginalSqliteError) as e: f.sqlite(d)
        s = e.exception.cleanup_library
        self.assertTrue(e.exception.unknown); self.assertIsNotNone(s._reply.value)
        self.assertIs(d._sqlite_library_original, s)
        before = list(f.sql_events)
        for action in (s.current, s.close):
            with self.assertRaises(_OriginalSqliteError) as again: action()
            self.assertIs(again.exception, e.exception)
        with self.assertRaises(ValueError): d.close_after_stop()
        self.assertEqual(f.sql_events, before)

    def test_lost_capture_or_drop_response_keeps_partial_custody_unknown(self):
        for field in ('sql_capture_fault', 'sql_drop_fault'):
            with self.subTest(field=field):
                f = SqliteFixture(); d = f.take(); setattr(f, field, OSError('lost data response'))
                with self.assertRaises(_OriginalSqliteError) as e: f.sqlite(d)
                s = e.exception.cleanup_library
                self.assertTrue(e.exception.unknown); self.assertEqual(s._original.value, 401)
                before = list(f.sql_events)
                with self.assertRaises(_OriginalSqliteError): s.close()
                with self.assertRaises(ValueError): d.close_after_stop()
                self.assertEqual(f.sql_events, before)

    def test_finish_response_loss_does_not_repeat_close_or_treat_cleared_slots_as_ack(self):
        f = SqliteFixture(); d = f.take(); s = f.sqlite(d)
        f.sql_finish_fault = OSError('lost finish response after clearing')
        with self.assertRaises(_OriginalSqliteError) as e: s.close()
        self.assertTrue(e.exception.unknown)
        self.assertFalse(s._closed)
        self.assertIsNone(s._original.value)
        self.assertIs(d._sqlite_library_original, s)
        before = list(f.sql_events)
        with self.assertRaises(_OriginalSqliteError): s.close()
        with self.assertRaises(ValueError): d.close_after_stop()
        self.assertEqual(f.sql_events, before)

    def test_foreign_component_and_bad_inputs_refuse_before_native_or_registration(self):
        f = SqliteFixture(); d = f.take(); foreign = SqliteFixture()
        with self.assertRaises(ValueError):
            _OriginalSqliteCustody._prepare_original(d, foreign.sql_functions,
                path='/candidate', heap_bytes=1, diagnostic_ceiling=128)
        for values in ({'path':'relative'}, {'path':'/nul\0name'}, {'path':'/'+'x'*4096},
                       {'heap_bytes':True}, {'diagnostic_ceiling':2**31}):
            with self.subTest(values=values):
                with self.assertRaises(ValueError): f.sqlite(d, **values)
        self.assertIsNone(d._sqlite_library_original); self.assertEqual(f.sql_events, [])

    def test_ctor_carrier_allocation_failure_leaves_domain_unconsumed(self):
        f = SqliteFixture(); d = f.take()
        with patch('actql_sdk._local_native_sqlite._OriginalSqliteError', side_effect=MemoryError('before Native')):
            with self.assertRaises(MemoryError): f.sqlite(d)
        self.assertIsNone(d._sqlite_library_original); self.assertEqual(f.sql_events, [])

    def test_native_current_refusal_stays_typed_without_a_read_scope_wrapper(self):
        f = SqliteFixture(); d = f.take(); f.sql_issue = 4; f.sql_present = False
        before = list(f.events)
        with self.assertRaises(_OriginalSqliteError) as e: f.sqlite(d)
        self.assertFalse(e.exception.unknown)
        self.assertEqual(e.exception.fact.issue_family, 4)
        self.assertFalse(any(x[0] == 'read' for x in f.events[len(before):]))
        d.close_after_stop(); self.assertTrue(d._closed)

    def test_wrong_identity_or_operation_is_unknown_not_a_success(self):
        for wrong in ('sql_wrong_host', 'sql_wrong_operation'):
            with self.subTest(wrong=wrong):
                f = SqliteFixture(); d = f.take(); setattr(f, wrong, True if wrong.endswith('host') else 2)
                with self.assertRaises(_OriginalSqliteError) as e: f.sqlite(d)
                self.assertTrue(e.exception.unknown)
                with self.assertRaises(ValueError): d.close_after_stop()

    def test_original_custody_cannot_be_copied_or_pickled(self):
        f = SqliteFixture(); s = f.sqlite()
        for call in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): call(s)
        s.close()


if __name__ == '__main__':
    unittest.main()
