"""Independent custody/out-slot counters; no Native Session or DB execution."""
import copy
import pickle
from threading import Thread
import unittest
from unittest.mock import patch

from test_local_native_control_custody import Function
from test_local_native_host_resources import PairFixture
from actql_sdk._local_native_adoption import (
    _OriginalAdoptionCustody, _OriginalAdoptionError,
    _OriginalAdoptionFunctions, _RETIRED_ADOPTION_DATA,
)


class AdoptionFixture(PairFixture):
    def __init__(self):
        super().__init__()
        self.p = self.pair()
        self.adoption_events, self.adoption_facts = [], {}
        self.adoption_faults, self.adoption_issues = {}, {}
        self.session = self.journal = None
        self.original_override = self.tag_override = self.issue_override = None
        calls = {'operate_into': self.adoption_operate,
                 'capture_journal_into': self.adoption_journal,
                 'originals_into': self.adoption_originals,
                 'drop_originals': self.adoption_drop_originals,
                 'operation': lambda r: self.tag_override if self.tag_override is not None
                    else self.adoption_facts[r.value][0],
                 'issue_family': lambda r: self.issue_override if self.issue_override is not None
                    else self.adoption_facts[r.value][1],
                 'drop_reply': self.adoption_drop, 'finish_closed_data': self.adoption_finish}
        for name, call in calls.items():
            setattr(self.host._functions.library, 'actql_local_adoption_' + name, Function(call))
        self.adoption_functions = _OriginalAdoptionFunctions(self.host._functions.library)

    def fault(self, name):
        if name in self.adoption_faults:
            raise self.adoption_faults[name]

    def prepare_adoption(self, out):
        self.adoption_events.append(('prepare',))
        self.assert_registered()
        out._obj.value = 901
        self.fault('prepare')
        return 0

    def assert_registered(self):
        assert isinstance(self.r._adoption_original, _OriginalAdoptionCustody)
        assert self.host._busy

    def adoption_operate(self, original, op, out):
        self.assert_registered()
        assert original.value == 901
        self.adoption_events.append(('operate', op))
        if op == 1:
            self.session = 1001
        self.adoption_result(op, out)
        self.fault('operate' + str(op))
        return 0

    def adoption_result(self, op, out):
        key = 4000 + len(self.adoption_facts)
        self.adoption_facts[key] = op, self.adoption_issues.get(op, 0)
        out._obj.value = key

    def adoption_journal(self, original, ttl, records, snapshot, out):
        self.assert_registered()
        assert original.value == 901
        self.adoption_events.append(('journal', ttl, records, snapshot))
        self.journal = 1101
        self.adoption_result(4, out)
        self.fault('journal')
        return 0

    def adoption_originals(self, original, *outputs):
        self.adoption_events.append(('originals',))
        values = [101, 801, 701, 951, self.session, self.journal]
        if self.original_override is not None:
            values[self.original_override] = 999
        for slot, value in zip(outputs, values):
            assert slot._obj.value is None
            slot._obj.value = value
        self.fault('originals')
        return 0

    def adoption_drop_originals(self, original, *outputs):
        self.adoption_events.append(('drop-originals',))
        for slot in outputs:
            slot._obj.value = None
        self.fault('drop-originals')
        return 0

    def adoption_drop(self, reply, original):
        self.adoption_events.append(('drop-reply',))
        reply._obj.value = None
        self.fault('drop-reply')
        return 0

    def adoption_finish(self, original, reply):
        self.adoption_events.append(('finish',))
        assert self.adoption_facts[reply._obj.value] == (3, 0)
        original._obj.value = reply._obj.value = None
        self.fault('finish')
        return 0

    def adoption(self):
        return _OriginalAdoptionCustody._open_original(self.p, self.adoption_functions,
            prepare=self.prepare_adoption)


class OriginalAdoptionTests(unittest.TestCase):
    def test_same_registered_parent_child_and_separate_cleanup(self):
        f = AdoptionFixture(); a = f.adoption()
        self.assertIs(f.r._adoption_original, a)
        self.assertEqual([s.value for s in a._original_slots()], [101, 801, 701, 951, 1001, None])
        self.assertEqual(a.open_journal(ttl_ms=100.0, max_records=8,
            max_snapshot_bytes=8388608).operation, 5)
        self.assertEqual(a._journal.value, 1101)
        self.assertEqual(a.current().operation, 2)
        self.assertEqual([x for x in f.adoption_events if x[0] in ('prepare', 'operate', 'journal')],
            [('prepare',), ('operate', 1), ('journal', 100.0, 8, 8388608), ('operate', 5), ('operate', 2)])
        a.close(); before = list(f.adoption_events); a.close()
        self.assertEqual(f.adoption_events, before)
        self.assertIs(f.r._adoption_original, _RETIRED_ADOPTION_DATA)
        self.assertIsNone(a._preparation)
        self.assertFalse(f.p._closed or f.r._closed or f.s._closed or f.host._closed)
        with self.assertRaises(ValueError): a.current()
        f.p.close()

    def test_live_child_refuses_parent_retirement_and_unrelated_scope(self):
        f = AdoptionFixture(); a = f.adoption()
        before = (list(f.pair_events), list(f.parent_events), list(f.sql_events))
        for call in (f.p.close, f.r.close, f.s.close,
                     lambda: f.p.claim_read(32, 64), lambda: f.p._call(3), lambda: f.p._call(7)):
            with self.assertRaises(ValueError): call()
        self.assertEqual(before, (f.pair_events, f.parent_events, f.sql_events))
        a.close(); f.p.close()

    def test_cannot_reacquire_after_acknowledged_retirement(self):
        f = AdoptionFixture(); a = f.adoption(); a.close(); before = list(f.adoption_events)
        with self.assertRaises(ValueError): f.adoption()
        self.assertEqual(f.adoption_events, before)
        f.p.close()

    def test_cannot_copy_or_serialize(self):
        f = AdoptionFixture(); a = f.adoption()
        for call in (lambda: copy.copy(a), lambda: copy.deepcopy(a), lambda: pickle.dumps(a)):
            with self.assertRaises(TypeError): call()
        a.close(); f.p.close()

    def test_busy_thread_process_preflight_does_not_register_or_poison(self):
        for mode in ('busy', 'thread', 'process'):
            with self.subTest(mode=mode):
                f = AdoptionFixture(); errors = []
                def call():
                    try: f.adoption()
                    except BaseException as error: errors.append(error)
                if mode == 'busy': f.host._busy = True; call(); self.assertTrue(f.host._busy); f.host._busy = False
                elif mode == 'thread':
                    thread = Thread(target=call); thread.start(); thread.join(2); self.assertFalse(thread.is_alive())
                else:
                    with patch('actql_sdk._local_native_control_custody.getpid', return_value=-1): call()
                self.assertEqual(len(errors), 1); self.assertIs(type(errors[0]), ValueError)
                self.assertIsNone(getattr(f.r, '_adoption_original', None))
                self.assertEqual(f.adoption_events, []); self.assertIsNone(f.p._unknown)
                f.adoption().close(); f.p.close()

    def test_foreign_library_or_active_scope_refuses_before_preparation(self):
        f = AdoptionFixture(); other = AdoptionFixture()
        with self.assertRaises(ValueError):
            _OriginalAdoptionCustody._open_original(f.p, other.adoption_functions,
                prepare=f.prepare_adoption)
        with f.p.scope('read'):
            with self.assertRaises(ValueError): f.adoption()
        self.assertEqual(f.adoption_events, [])
        f.p.close(); other.p.close()

    def test_lost_prepare_or_first_open_never_repeats_and_fences_parent(self):
        for fault in ('prepare', 'operate1', 'originals', 'drop-originals', 'drop-reply'):
            with self.subTest(fault=fault):
                f = AdoptionFixture(); f.adoption_faults[fault] = OSError('lost acknowledgement')
                with self.assertRaises(_OriginalAdoptionError) as raised: f.adoption()
                error = raised.exception; a = error.cleanup_adoption
                self.assertTrue(error.unknown); self.assertIs(f.r._adoption_original, a)
                before = list(f.adoption_events)
                for call in (a.current, a.close, f.p.close, f.r.close, f.s.close):
                    with self.assertRaises(_OriginalAdoptionError) as again: call()
                    self.assertIs(again.exception, error)
                self.assertEqual(f.adoption_events, before)
                with self.assertRaises(ValueError): f.adoption()
                self.assertEqual(sum(x[0] == 'prepare' for x in f.adoption_events), 1)

    def test_known_open_refusal_preserves_same_cleanup_carrier(self):
        f = AdoptionFixture(); f.adoption_issues[1] = 4
        with self.assertRaises(_OriginalAdoptionError) as raised: f.adoption()
        error = raised.exception; a = error.cleanup_adoption
        self.assertFalse(error.unknown); self.assertEqual(error.fact.operation, 1)
        a.close(); f.p.close()
        self.assertEqual(sum(x == ('operate', 1) for x in f.adoption_events), 1)

    def test_original_mismatch_retains_partial_slots_and_never_uses_foreign_parent(self):
        for field in range(3):
            with self.subTest(field=field):
                f = AdoptionFixture(); f.original_override = field
                with self.assertRaises(_OriginalAdoptionError) as raised: f.adoption()
                a = raised.exception.cleanup_adoption
                self.assertTrue(raised.exception.unknown); self.assertIsNotNone(a._crypto.value)
                self.assertFalse(any(x[0] == 'operate' for x in f.adoption_events))

    def test_changed_crypto_session_or_child_alias_is_not_original_correspondence(self):
        for field in (3, 4, 5):
            with self.subTest(field=field):
                f = AdoptionFixture(); a = f.adoption()
                a.open_journal(ttl_ms=100.0, max_records=8, max_snapshot_bytes=8388608)
                f.original_override = field
                with self.assertRaises(_OriginalAdoptionError) as raised: a.current()
                self.assertTrue(raised.exception.unknown)
                before = list(f.adoption_events)
                with self.assertRaises(_OriginalAdoptionError): a.close()
                self.assertEqual(f.adoption_events, before)

    def test_preallocation_parent_retirement_is_known_before_registration_or_prepare(self):
        f = AdoptionFixture()
        from actql_sdk import _local_native_adoption as module
        make = module.c_void_p
        def allocate(*args):
            f.r._closed = True
            return make(*args)
        with patch.object(module, 'c_void_p', side_effect=allocate):
            with self.assertRaises(ValueError): f.adoption()
        self.assertIsNone(getattr(f.r, '_adoption_original', None))
        self.assertEqual(f.adoption_events, [])
        f.r._closed = False; f.p.close()

    def test_lost_journal_attach_keeps_child_and_never_reprepares_or_opens(self):
        f = AdoptionFixture(); a = f.adoption(); f.adoption_faults['journal'] = OSError('lost child')
        with self.assertRaises(_OriginalAdoptionError) as raised:
            a.open_journal(ttl_ms=100.0, max_records=8, max_snapshot_bytes=8388608)
        before = list(f.adoption_events)
        with self.assertRaises(_OriginalAdoptionError):
            a.open_journal(ttl_ms=100.0, max_records=8, max_snapshot_bytes=8388608)
        with self.assertRaises(_OriginalAdoptionError) as again: f.p.close()
        self.assertIs(again.exception, raised.exception)
        self.assertEqual(f.adoption_events, before)
        self.assertEqual(sum(x[0] == 'journal' for x in before), 1)
        self.assertNotIn(('operate', 5), before)

    def test_journal_choice_is_once_even_after_known_refusal(self):
        f = AdoptionFixture(); a = f.adoption(); f.adoption_issues[4] = 4
        with self.assertRaises(_OriginalAdoptionError) as raised:
            a.open_journal(ttl_ms=100.0, max_records=8, max_snapshot_bytes=8388608)
        self.assertFalse(raised.exception.unknown)
        before = list(f.adoption_events)
        with self.assertRaises(ValueError):
            a.open_journal(ttl_ms=200.0, max_records=9, max_snapshot_bytes=999)
        self.assertEqual(f.adoption_events, before)
        a.close(); f.p.close()

    def test_busy_reentry_on_existing_child_preserves_busy_and_can_cleanup(self):
        f = AdoptionFixture(); a = f.adoption(); before = list(f.adoption_events)
        f.host._busy = True
        for call in (a.current, a.close):
            with self.assertRaises(ValueError): call()
            self.assertTrue(f.host._busy)
        self.assertIsNone(a._unknown); self.assertEqual(f.adoption_events, before)
        f.host._busy = False; a.close(); f.p.close()

    def test_closed_operation_shape_mismatch_keeps_parent_and_ack_unconfirmed(self):
        for mode, value in [('tag_override', True), ('tag_override', 1),
                            ('issue_override', True), ('issue_override', 8)]:
            with self.subTest(mode=mode, value=value):
                f = AdoptionFixture(); a = f.adoption(); setattr(f, mode, value)
                with self.assertRaises(_OriginalAdoptionError) as raised: a.close()
                self.assertTrue(raised.exception.unknown); self.assertFalse(a._closed)
                self.assertIs(f.r._adoption_original, a)
                self.assertFalse(any(x[0] == 'finish' for x in f.adoption_events))

    def test_known_close_refusal_retries_only_same_cleanup(self):
        f = AdoptionFixture(); a = f.adoption(); f.adoption_issues[3] = 4
        with self.assertRaises(_OriginalAdoptionError) as raised: a.close()
        self.assertFalse(raised.exception.unknown)
        with self.assertRaises(ValueError): f.p.close()
        f.adoption_issues[3] = 0; a.close(); f.p.close()
        self.assertEqual(sum(x[0] == 'prepare' for x in f.adoption_events), 1)
        self.assertEqual(sum(x == ('operate', 3) for x in f.adoption_events), 2)

    def test_lost_close_finish_or_alias_drop_keeps_parent_registration(self):
        for fault in ('operate3', 'finish', 'drop-originals'):
            with self.subTest(fault=fault):
                f = AdoptionFixture(); a = f.adoption(); f.adoption_faults[fault] = OSError('lost cleanup')
                with self.assertRaises(_OriginalAdoptionError) as raised: a.close()
                before = list(f.adoption_events)
                for call in (a.close, f.p.close, f.r.close, f.s.close):
                    with self.assertRaises(_OriginalAdoptionError) as again: call()
                    self.assertIs(again.exception, raised.exception)
                self.assertEqual(f.adoption_events, before); self.assertFalse(a._closed)

    def test_unknown_open_or_failed_leave_never_becomes_known_cleanup_success(self):
        for family in (3, 7):
            with self.subTest(family=family):
                f = AdoptionFixture(); f.adoption_issues[1] = family
                with self.assertRaises(_OriginalAdoptionError) as raised: f.adoption()
                error = raised.exception; self.assertTrue(error.unknown)
                self.assertEqual(error.fact.issue_family, family)
                before = list(f.adoption_events)
                with self.assertRaises(_OriginalAdoptionError): error.cleanup_adoption.close()
                self.assertEqual(f.adoption_events, before)

    def test_journal_invalid_options_and_operation_do_not_reach_native(self):
        f = AdoptionFixture(); a = f.adoption(); before = list(f.adoption_events)
        for opts in [(True, 8, 10), (float('inf'), 8, 10), (0.0, 8, 10),
                     (100.0, True, 10), (100.0, 1 << 31, 10), (100.0, 8, 1 << 63)]:
            with self.assertRaises(ValueError):
                a.open_journal(ttl_ms=opts[0], max_records=opts[1], max_snapshot_bytes=opts[2])
        with self.assertRaises(ValueError): a._call(1)
        self.assertEqual(f.adoption_events, before)
        a.close(); f.p.close()


if __name__ == '__main__':
    unittest.main()
