"""Independent scalar slot/call counters, not actual Core/DLL acceptance."""
import copy
import pickle
import unittest
from unittest.mock import patch

from test_local_native_control_custody import Fixture as ControlFixture, Function
from actql_sdk._local_native_control_custody import _OriginalControlError
from actql_sdk._local_native_initial_custody import _OriginalPythonNativeInitial
from actql_sdk._local_native_backing_custody import (
    _OriginalBackingCustody, _OriginalBackingError, _OriginalBackingFunctions,
)


class BackingFixture:
    def __init__(self):
        self.control = ControlFixture()
        self.host = self.control.take()
        self.events = []
        self.facts = {}
        self.borrow_fault = self.capture_fault = self.return_fault = self.finish_fault = None
        self.current_issue = self.return_issue = self.borrow_issue = 0
        self.live = False
        self.scopes = 0
        self.scope_enter_fault = self.scope_leave_fault = None
        self.scope_enter_issue = self.scope_leave_issue = 0
        self.reenter = None
        library = self.control.library
        calls = {'borrow_into':self.borrow, 'current_into':self.current,
                 'return_into':self.return_loan, 'originals_into':self.originals,
                 'enter_scope_into':self.enter_scope, 'leave_scope_into':self.leave_scope,
                 'drop_reply':self.drop, 'finish_returned_data':self.finish,
                 'finish_refused_borrow':self.refused,
                 'operation':lambda p: self.facts[p.value][0],
                 'issue_family':lambda p: self.facts[p.value][1]}
        for name, call in calls.items():
            setattr(library, 'actql_backing_' + name, Function(call))
        self.functions = _OriginalBackingFunctions(library)

    def result(self, slot, operation, issue):
        identity = 300 + len(self.facts)
        self.facts[identity] = (operation, issue)
        slot._obj.value = identity

    def borrow(self, host, reply):
        self.events.append(('borrow', host.value))
        self.live = self.borrow_issue == 0
        self.control.pending = self.live
        self.result(reply, 1, self.borrow_issue)
        if self.borrow_fault: raise self.borrow_fault
        return 0

    def originals(self, reply, host, loan):
        self.events.append(('capture', reply.value))
        host._obj.value = 101
        if self.live: loan._obj.value = 201
        if self.capture_fault: raise self.capture_fault
        return 0

    def drop(self, reply, host, loan):
        self.events.append(('drop', reply._obj.value, host.value, loan.value))
        reply._obj.value = None
        return 0

    def current(self, host, loan, reply):
        self.events.append(('current', host.value, loan.value))
        self.result(reply, 2, self.current_issue)
        return 0

    def return_loan(self, host, loan, reply):
        self.events.append(('return', host.value, loan.value))
        issue = 5 if self.scopes else self.return_issue
        self.result(reply, 3, issue)
        if issue == 0:
            self.live = False
            self.control.pending = False
        if self.return_fault: raise self.return_fault
        if self.reenter: self.reenter()
        return 0

    def enter_scope(self, host, loan, reply):
        self.events.append(('enter_scope', host.value, loan.value))
        self.result(reply, 4, self.scope_enter_issue)
        if self.scope_enter_issue == 0:
            self.scopes += 1
        if self.scope_enter_fault: raise self.scope_enter_fault
        return 0

    def leave_scope(self, host, loan, reply):
        self.events.append(('leave_scope', host.value, loan.value))
        self.result(reply, 5, self.scope_leave_issue)
        if self.scope_leave_issue == 0:
            assert self.scopes > 0
            self.scopes -= 1
        if self.scope_leave_fault: raise self.scope_leave_fault
        return 0

    def finish(self, host, loan, reply):
        self.events.append(('finish', host._obj.value, loan._obj.value, reply._obj.value))
        reply._obj.value = None
        loan._obj.value = None
        host._obj.value = None
        if self.finish_fault: raise self.finish_fault
        return 0

    def refused(self, host, reply):
        self.events.append(('refused_data', host._obj.value, reply._obj.value))
        host._obj.value = reply._obj.value = None
        return 0

    def take(self):
        return _OriginalBackingCustody._borrow_original(self.host, self.functions)


class BackingCustodyTests(unittest.TestCase):
    def test_python_initial_refusal_precedes_original_backing_borrow(self):
        # Controlled ABI ports, not a Native initial or physical supplier.
        f = BackingFixture()
        initial = _OriginalPythonNativeInitial.__new__(_OriginalPythonNativeInitial)
        f.host._python_initial_original = initial
        primary = ValueError('Original Python Runtime is unavailable')
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current',
                          side_effect=primary) as current:
            with self.assertRaises(ValueError) as observed: f.take()
            self.assertIs(observed.exception, primary)
            current.assert_called_once_with()
        self.assertEqual(f.events, [])
        self.assertEqual(f.host._original.value, 101)
        self.assertFalse(f.host._busy)
        self.assertIs(f.host._python_initial_original, initial)
        f.host.close()

    def test_python_initial_refusal_blocks_backing_use_but_not_original_return(self):
        f = BackingFixture()
        initial = _OriginalPythonNativeInitial.__new__(_OriginalPythonNativeInitial)
        f.host._python_initial_original = initial
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current'):
            loan = f.take()
        before = list(f.events)
        primary = ValueError('Original Python Runtime became unavailable')
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current',
                          side_effect=primary):
            for call in (loan.current, lambda: loan._change_physical_scope(4)):
                with self.assertRaises(ValueError) as observed: call()
                self.assertIs(observed.exception, primary)
                self.assertFalse(f.host._busy)
            self.assertEqual(f.events, before)
            loan.return_after_stop()
            f.host.close()
        self.assertTrue(loan._closed)
        self.assertEqual(f.events.count(('borrow', 101)), 1)
        self.assertEqual(f.events.count(('return', 101, 201)), 1)
        self.assertEqual(f.control.events.count(('physical_close', 101)), 1)

    def test_python_initial_refusal_keeps_entered_scope_leave_and_same_return(self):
        f = BackingFixture()
        initial = _OriginalPythonNativeInitial.__new__(_OriginalPythonNativeInitial)
        f.host._python_initial_original = initial
        refused = False
        def current():
            if refused: raise ValueError('Original Python Runtime became unavailable')
        with patch.object(_OriginalPythonNativeInitial, 'require_control_current',
                          side_effect=current):
            loan = f.take()
            with loan._physical_scope():
                refused = True
            self.assertEqual(f.scopes, 0)
            with self.assertRaises(ValueError): loan.current()
            loan.return_after_stop()
            f.host.close()
        self.assertTrue(loan._closed)
        self.assertEqual(f.events.count(('enter_scope', 101, 201)), 1)
        self.assertEqual(f.events.count(('leave_scope', 101, 201)), 1)
        self.assertEqual(f.events.count(('return', 101, 201)), 1)

    def test_lost_borrow_reply_keeps_same_loan_carrier_without_late_error_allocation(self):
        f = BackingFixture()
        primary = OSError('lost original borrow response')
        f.borrow_fault = primary
        original = f.functions.borrow.call
        unavailable = patch('actql_sdk._local_native_backing_custody._OriginalBackingError',
                            side_effect=MemoryError('late error metadata'))

        def borrow_then_lose(*args):
            unavailable.start()
            return original(*args)

        f.functions.borrow.call = borrow_then_lose
        try:
            with self.assertRaises(_OriginalBackingError) as observed: f.take()
        finally:
            unavailable.stop()
        failure = observed.exception
        loan = failure.cleanup_borrow
        self.assertTrue(failure.unknown)
        self.assertIs(failure.__cause__, primary)
        self.assertIs(loan._owner, f.host)
        self.assertIsNotNone(loan._reply.value)
        self.assertTrue(f.live)
        self.assertFalse(f.control.physically_closed)
        self.assert_sticky(loan, failure, f)

    def assert_sticky(self, borrow, failure, fixture):
        before = list(fixture.events)
        for call in (borrow.current, borrow.return_after_stop):
            with self.assertRaises(_OriginalBackingError) as observed: call()
            self.assertIs(observed.exception, failure)
        self.assertEqual(fixture.events, before)

    def test_same_loan_return_does_not_close_host_or_transfer_again(self):
        f = BackingFixture(); loan = f.take()
        self.assertEqual((loan.current().operation, loan.current().issue_family), (2, 0))
        loan.return_after_stop(); loan.return_after_stop()
        self.assertTrue(loan._closed)
        self.assertIsNone(loan._host.value); self.assertIsNone(loan._loan.value)
        self.assertEqual(f.events.count(('borrow', 101)), 1)
        self.assertEqual(f.events.count(('return', 101, 201)), 1)
        self.assertFalse(f.control.physically_closed)
        self.assertIs(loan._functions.library, f.control.library)
        f.host.close()
        self.assertEqual(f.control.events.count(('physical_close', 101)), 1)
        with self.assertRaises(ValueError): loan.current()

    def test_pending_host_close_keeps_same_loan_and_cleanup_return(self):
        f = BackingFixture(); loan = f.take()
        with self.assertRaises(_OriginalControlError) as observed: f.host.close()
        self.assertFalse(observed.exception.unknown)
        self.assertFalse(f.control.physically_closed)
        f.current_issue = 4
        with self.assertRaises(_OriginalBackingError) as refused: loan.current()
        self.assertFalse(refused.exception.unknown)
        self.assertEqual(refused.exception.fact.issue_family, 4)
        self.assertEqual(loan._loan.value, 201)
        loan.return_after_stop()
        self.assertFalse(f.control.physically_closed)
        f.host.close()
        self.assertEqual(f.control.events.count(('physical_close', 101)), 1)

    def test_pre_call_allocation_failure_leaves_original_and_no_native_call(self):
        f = BackingFixture(); primary = MemoryError('slot metadata')
        with patch('actql_sdk._local_native_backing_custody._new_backing_slots', side_effect=primary):
            with self.assertRaises(MemoryError) as observed: f.take()
        self.assertIs(observed.exception, primary)
        self.assertEqual(f.events, [])
        self.assertEqual(f.host._original.value, 101)
        self.assertFalse(f.host._busy)

    def test_borrow_response_loss_keeps_reply_and_same_carrier_without_reacquire(self):
        f = BackingFixture(); f.borrow_fault = OSError('lost borrow response')
        with self.assertRaises(_OriginalBackingError) as observed: f.take()
        loan = observed.exception.cleanup_borrow
        self.assertTrue(observed.exception.unknown)
        self.assertIsNotNone(loan._reply.value)
        self.assertIsNone(loan._host.value)
        self.assertIs(loan._owner, f.host)
        self.assert_sticky(loan, observed.exception, f)

    def test_capture_response_loss_keeps_published_host_and_loan(self):
        f = BackingFixture(); f.capture_fault = OSError('lost accessor response')
        with self.assertRaises(_OriginalBackingError) as observed: f.take()
        loan = observed.exception.cleanup_borrow
        self.assertEqual((loan._host.value, loan._loan.value), (101, 201))
        self.assertIsNotNone(loan._reply.value)
        self.assert_sticky(loan, observed.exception, f)

    def test_return_response_loss_never_repeats_original_return(self):
        f = BackingFixture(); loan = f.take(); f.return_fault = OSError('lost return response')
        with self.assertRaises(_OriginalBackingError) as observed: loan.return_after_stop()
        self.assertEqual(loan._loan.value, 201)
        self.assertFalse(loan._closed)
        self.assertIsNotNone(loan._reply.value)
        self.assert_sticky(loan, observed.exception, f)
        self.assertEqual(f.events.count(('return', 101, 201)), 1)

    def test_finish_response_loss_keeps_unknown_even_after_slots_cleared(self):
        f = BackingFixture(); loan = f.take(); f.finish_fault = OSError('lost data drop response')
        with self.assertRaises(_OriginalBackingError) as observed: loan.return_after_stop()
        self.assertTrue(observed.exception.unknown)
        self.assertFalse(loan._closed)
        self.assertIsNone(loan._host.value); self.assertIsNone(loan._loan.value)
        self.assertIsNone(loan._reply.value)
        self.assert_sticky(loan, observed.exception, f)
        self.assertFalse(f.control.physically_closed)

    def test_known_refused_borrow_has_no_loan_or_false_unknown(self):
        f = BackingFixture(); f.borrow_issue = 1
        with self.assertRaises(_OriginalBackingError) as observed: f.take()
        self.assertFalse(observed.exception.unknown)
        loan = observed.exception.cleanup_borrow
        self.assertTrue(loan._closed)
        self.assertIsNone(loan._host.value); self.assertIsNone(loan._loan.value)
        self.assertEqual(f.events.count(('borrow', 101)), 1)
        self.assertFalse(f.control.physically_closed)

    def test_known_return_refusal_retains_same_slots_for_explicit_retry_only(self):
        f = BackingFixture(); loan = f.take(); f.return_issue = 5
        with self.assertRaises(_OriginalBackingError) as observed: loan.return_after_stop()
        self.assertFalse(observed.exception.unknown)
        self.assertEqual(loan._loan.value, 201)
        self.assertIsNotNone(loan._reply.value)
        self.assertEqual(f.events.count(('return', 101, 201)), 1)
        f.return_issue = 0
        loan.return_after_stop()
        self.assertEqual(f.events.count(('return', 101, 201)), 2)

    def test_nested_physical_scope_keeps_return_pending_until_every_leave(self):
        f = BackingFixture(); loan = f.take()
        with loan._physical_scope():
            with loan._physical_scope():
                self.assertEqual(f.scopes, 2)
                with self.assertRaises(_OriginalBackingError) as observed:
                    loan.return_after_stop()
                self.assertEqual(observed.exception.fact.issue_family, 5)
                self.assertFalse(loan._closed)
            self.assertEqual(f.scopes, 1)
        self.assertEqual(f.scopes, 0)
        loan.return_after_stop()
        self.assertTrue(loan._closed)
        self.assertEqual(f.events.count(('enter_scope', 101, 201)), 2)
        self.assertEqual(f.events.count(('leave_scope', 101, 201)), 2)

    def test_scope_entry_refusal_does_not_enter_body_or_infer_cleanup(self):
        f = BackingFixture(); loan = f.take(); f.scope_enter_issue = 6
        with self.assertRaises(_OriginalBackingError) as observed:
            with loan._physical_scope():
                self.fail('Refused scope entered the physical caller')
        self.assertFalse(observed.exception.unknown)
        self.assertEqual(observed.exception.fact.operation, 4)
        self.assertEqual(f.scopes, 0)
        self.assertEqual(f.events.count(('leave_scope', 101, 201)), 0)
        self.assertEqual(loan._loan.value, 201)
        loan.return_after_stop()

    def test_lost_scope_entry_keeps_original_loan_without_automatic_leave(self):
        f = BackingFixture(); loan = f.take()
        f.scope_enter_fault = OSError('lost original scope entry')
        with self.assertRaises(_OriginalBackingError) as observed:
            with loan._physical_scope():
                self.fail('Unknown scope entered the physical caller')
        self.assertTrue(observed.exception.unknown)
        self.assertEqual(f.scopes, 1)
        self.assertEqual(f.events.count(('leave_scope', 101, 201)), 0)
        self.assertEqual(loan._loan.value, 201)
        self.assert_sticky(loan, observed.exception, f)

    def test_cleanup_refusal_preserves_primary_and_same_scope_for_explicit_retry(self):
        f = BackingFixture(); loan = f.take(); primary = OSError('physical caller failed')
        with self.assertRaises(_OriginalBackingError) as observed:
            with loan._physical_scope():
                f.scope_leave_issue = 6
                raise primary
        self.assertIs(observed.exception.__cause__, primary)
        self.assertFalse(observed.exception.unknown)
        self.assertEqual(observed.exception.fact.operation, 5)
        self.assertEqual(f.scopes, 1)
        self.assertEqual(f.events.count(('leave_scope', 101, 201)), 1)
        self.assertFalse(loan._closed)
        f.scope_leave_issue = 0
        loan._change_physical_scope(5)
        loan.return_after_stop()

    def test_lost_scope_leave_is_sticky_even_when_native_slot_consumed(self):
        f = BackingFixture(); loan = f.take()
        with self.assertRaises(_OriginalBackingError) as observed:
            with loan._physical_scope():
                f.scope_leave_fault = OSError('lost original scope leave')
        self.assertTrue(observed.exception.unknown)
        self.assertEqual(f.scopes, 0)
        self.assertEqual(f.events.count(('leave_scope', 101, 201)), 1)
        self.assertEqual(loan._loan.value, 201)
        self.assert_sticky(loan, observed.exception, f)

    def test_invalid_or_retired_scope_is_rejected_before_native_calls(self):
        f = BackingFixture(); loan = f.take(); before = list(f.events)
        for invalid in (True, 0, 3, 6):
            with self.assertRaises(ValueError): loan._change_physical_scope(invalid)
        self.assertEqual(f.events, before)
        loan.return_after_stop(); before = list(f.events)
        with self.assertRaises(ValueError):
            with loan._physical_scope(): self.fail('Retired scope entered')
        self.assertEqual(f.events, before)

    def test_copy_foreign_component_reentry_and_boolean_fact_are_rejected(self):
        f = BackingFixture(); other = BackingFixture()
        with self.assertRaises(ValueError):
            _OriginalBackingCustody._borrow_original(f.host, other.functions)
        self.assertEqual(f.events, [])
        loan = f.take()
        for call in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): call(loan)
        def reenter():
            with self.assertRaises(ValueError): loan.return_after_stop()
        f.reenter = reenter
        loan.return_after_stop()
        self.assertEqual(f.events.count(('return', 101, 201)), 1)
        f = BackingFixture(); loan = f.take()
        f.functions.issue.call = lambda p: False
        with self.assertRaises(_OriginalBackingError) as observed: loan.current()
        self.assertTrue(observed.exception.unknown)
        self.assert_sticky(loan, observed.exception, f)


if __name__ == '__main__': unittest.main()
