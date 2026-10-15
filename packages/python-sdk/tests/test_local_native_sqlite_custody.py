"""Independent slot/call faults. Actual matching Native/DLL is separate."""
import copy
import pickle
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
        return _OriginalSqliteCustody._prepare_original(domain, self.sql_functions, self.read_functions,
            **({'path': '/private/é-😀/sqlite.dylib', 'heap_bytes': 524288,
                'diagnostic_ceiling': 128} | overrides))


class OriginalSqliteCustodyTests(unittest.TestCase):
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
            _OriginalSqliteCustody._prepare_original(d, foreign.sql_functions, f.read_functions,
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

    def test_known_original_read_refusal_is_not_a_sqlite_unknown(self):
        f = SqliteFixture(); d = f.take(); f.read_issue = 4
        with self.assertRaises(_OriginalDomainError) as e: f.sqlite(d)
        self.assertFalse(e.exception.unknown)
        self.assertEqual(f.sql_events, [])
        f.read_issue = 0
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
