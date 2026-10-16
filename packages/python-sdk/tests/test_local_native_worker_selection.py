"""Independent scalar slot/fault counters, not C or installed worker evidence."""
import copy
import pickle
import unittest
from unittest.mock import patch

from actql_sdk._local_native_worker_selection import (
    _OriginalWorkerSelectionCustody, _OriginalWorkerSelectionError,
    _OriginalWorkerSelectionFunctions,
)
from test_local_native_control_custody import Fixture as ControlFixture, Function


class SelectionFixture:
    def __init__(self):
        self.control = ControlFixture()
        self.host = self.control.take()
        self.events, self.facts = [], {}
        self.select_fault = self.capture_fault = self.current_fault = self.finish_fault = None
        self.issue = 0
        library = self.control.library
        for name, call in {
            'actql_worker_select_into': self.select,
            'actql_worker_selection_current_into': self.current,
            'actql_worker_selection_originals_into': self.capture,
            'actql_worker_selection_operation': lambda p: self.facts[p.value][0],
            'actql_worker_selection_issue_family': lambda p: self.facts[p.value][1],
            'actql_worker_selection_drop_reply': self.drop,
            'actql_worker_selection_finish_data': self.finish,
        }.items():
            setattr(library, name, Function(call))
        self.functions = _OriginalWorkerSelectionFunctions(library)

    def result(self, reply, operation, issue):
        identity = 301 + len(self.facts)
        self.facts[identity] = (operation, issue)
        reply._obj.value = identity

    def select(self, host, reply):
        self.events.append(('select', host.value))
        self.result(reply, 1, self.issue)
        if self.select_fault: raise self.select_fault
        return 0

    def capture(self, reply, host, selection):
        self.events.append(('capture', reply.value))
        host._obj.value = 101
        if self.facts[reply.value][1] == 0: selection._obj.value = 201
        if self.capture_fault: raise self.capture_fault
        return 0

    def current(self, host, selection, reply):
        self.events.append(('current', host.value, selection.value))
        self.result(reply, 2, 4 if self.control.physically_closed else self.issue)
        if self.current_fault: raise self.current_fault
        return 0

    def drop(self, reply, host, selection):
        self.events.append(('drop', reply._obj.value, host.value, selection.value))
        reply._obj.value = None
        return 0

    def finish(self, host, selection, reply):
        self.events.append(('finish_data', host._obj.value, selection._obj.value, reply._obj.value))
        host._obj.value = selection._obj.value = reply._obj.value = None
        if self.finish_fault: raise self.finish_fault
        return 0

    def take(self):
        return _OriginalWorkerSelectionCustody._select_original(self.host, self.functions)


class WorkerSelectionCustodyTests(unittest.TestCase):
    def assert_sticky(self, fixture, selection, failure):
        before = list(fixture.events)
        for call in (selection.current, selection.close):
            with self.assertRaises(_OriginalWorkerSelectionError) as observed: call()
            self.assertIs(observed.exception, failure)
        self.assertEqual(fixture.events, before)
        self.assertFalse(selection._closed)

    def test_same_original_metadata_close_does_not_close_host(self):
        f = SelectionFixture(); selected = f.take()
        self.assertEqual((selected._host.value, selected._selection.value), (101, 201))
        self.assertEqual((selected.current().operation, selected.current().issue_family), (2, 0))
        selected.close(); selected.close()
        self.assertEqual(sum(e[0] == 'finish_data' for e in f.events), 1)
        self.assertEqual(sum(e[0] == 'select' for e in f.events), 1)
        self.assertFalse(f.control.physically_closed)
        self.assertFalse(f.host._closed)

    def test_known_closing_keeps_metadata_and_data_close_never_recloses_host(self):
        f = SelectionFixture(); selected = f.take(); f.host.close()
        before = list(f.control.events)
        with self.assertRaises(_OriginalWorkerSelectionError) as observed: selected.current()
        self.assertFalse(observed.exception.unknown)
        self.assertEqual(observed.exception.fact.issue_family, 4)
        self.assertIs(observed.exception.cleanup_selection, selected)
        selected.close()
        self.assertTrue(selected._closed)
        self.assertEqual(f.control.events, before)

    def test_foreign_component_copy_and_fork_scope_refuse_before_calls(self):
        f = SelectionFixture(); other = SelectionFixture(); before = list(f.events)
        with self.assertRaises(ValueError):
            _OriginalWorkerSelectionCustody._select_original(f.host, other.functions)
        with patch('actql_sdk._local_native_control_custody.getpid', return_value=-1):
            with self.assertRaises(ValueError): f.take()
        self.assertEqual(f.events, before)
        selected = f.take(); before = list(f.events)
        for call in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): call(selected)
        self.assertEqual(f.events, before)
        selected.close()

    def test_lost_select_retains_original_reply_and_does_not_repeat(self):
        f = SelectionFixture(); f.select_fault = OSError('lost select reply')
        with self.assertRaises(_OriginalWorkerSelectionError) as observed: f.take()
        failure = observed.exception; selected = failure.cleanup_selection
        self.assertTrue(failure.unknown)
        self.assertEqual(selected._reply.value, 301)
        self.assertIs(selected._owner, f.host)
        self.assertFalse(f.control.physically_closed)
        self.assert_sticky(f, selected, failure)

    def test_lost_capture_retains_partial_persistent_slots(self):
        f = SelectionFixture(); f.capture_fault = OSError('lost capture reply')
        with self.assertRaises(_OriginalWorkerSelectionError) as observed: f.take()
        failure = observed.exception; selected = failure.cleanup_selection
        self.assertEqual((selected._host.value, selected._selection.value, selected._reply.value), (101, 201, 301))
        self.assert_sticky(f, selected, failure)

    def test_lost_current_retains_same_selection_without_reselect(self):
        f = SelectionFixture(); selected = f.take(); f.current_fault = OSError('lost current reply')
        with self.assertRaises(_OriginalWorkerSelectionError) as observed: selected.current()
        self.assertEqual(selected._selection.value, 201)
        self.assertIsNotNone(selected._reply.value)
        self.assert_sticky(f, selected, observed.exception)
        self.assertEqual(sum(e[0] == 'select' for e in f.events), 1)

    def test_lost_data_retirement_reply_is_not_host_cleanup_or_success(self):
        f = SelectionFixture(); selected = f.take(); f.finish_fault = OSError('lost data retirement reply')
        with self.assertRaises(_OriginalWorkerSelectionError) as observed: selected.close()
        self.assertIsNone(selected._host.value)
        self.assertIsNone(selected._selection.value)
        self.assertFalse(f.control.physically_closed)
        self.assert_sticky(f, selected, observed.exception)

    def test_error_metadata_failure_precedes_first_native_call(self):
        f = SelectionFixture()
        with patch('actql_sdk._local_native_worker_selection._OriginalWorkerSelectionError', side_effect=MemoryError('initial carrier allocation')):
            with self.assertRaises(MemoryError): f.take()
        self.assertEqual(f.events, [])
        self.assertFalse(f.host._busy)
