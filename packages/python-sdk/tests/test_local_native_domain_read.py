"""Independent Python slot counters; matching emitted Native/C is separate."""
import unittest
from test_local_native_domain_custody import DomainFixture
from test_local_native_control_custody import Function
from actql_sdk._local_native_domain_custody import _OriginalDomainReadFunctions, _OriginalDomainError


class ReadFixture(DomainFixture):
    def __init__(self):
        super().__init__()
        self.read_issue = 0
        self.read_fault = None
        for name, operation in zip(('prepare', 'current', 'enter', 'leave', 'cleanup', 'close'), range(8, 14)):
            setattr(self.host._functions.library, 'actql_domain_read_' + name + '_into',
                    Function(lambda h, d, r, op=operation: self.read_call(op, h, d, r)))
        self.read_functions = _OriginalDomainReadFunctions(self.host._functions.library)

    def read_call(self, operation, host, domain, reply):
        self.events.append(('read', operation, host.value, domain.value))
        self.result(reply, operation, self.read_issue)
        if self.read_fault:
            raise self.read_fault
        return 0


class OriginalDomainReadTests(unittest.TestCase):
    def test_read_scope_and_close_keep_original_domain_and_independent_fd(self):
        f = ReadFixture()
        d = f.take()
        d._prepare_read_context(f.read_functions)
        d._require_read_current(f.read_functions)
        with d._read_scope(f.read_functions):
            self.assertEqual(d._domain.value, 301)
        d._close_read_context(f.read_functions)
        self.assertEqual([x[1] for x in f.events if x[0] == 'read'], [8, 9, 10, 11, 13])
        self.assertFalse(d._closed)
        self.assertEqual(d._host.value, 101)
        self.assertEqual(d._domain.value, 301)
        self.assertFalse(any(x[0] == 'finish' for x in f.events))
        self.assertFalse(f.descriptor.close_attempted)
        d.close_after_stop()
        self.assertTrue(d._closed)

    def test_known_retirement_refusal_keeps_original_and_allows_original_cleanup_only(self):
        f = ReadFixture()
        d = f.take()
        f.read_issue = 5
        with self.assertRaises(_OriginalDomainError) as error:
            d._close_read_context(f.read_functions)
        self.assertFalse(error.exception.unknown)
        self.assertIs(error.exception.cleanup_domain, d)
        self.assertEqual(error.exception.fact.operation, 13)
        self.assertEqual(d._domain.value, 301)
        f.read_issue = 0  # Simulate later original Owner ACK; not Python inference.
        d._close_read_context(f.read_functions)
        self.assertFalse(d._closed)
        self.assertFalse(any(x[0] == 'finish' for x in f.events))

    def test_lost_read_response_stays_unknown_without_second_prepare_or_cleanup(self):
        f = ReadFixture()
        d = f.take()
        f.read_fault = OSError('reply lost after native operation')
        with self.assertRaises(_OriginalDomainError) as error:
            d._prepare_read_context(f.read_functions)
        self.assertTrue(error.exception.unknown)
        self.assertIsNotNone(d._reply.value)
        before = list(f.events)
        for action in (lambda: d._prepare_read_context(f.read_functions),
                       lambda: d._require_read_current(f.read_functions),
                       lambda: d._close_read_context(f.read_functions), d.close_after_stop):
            with self.assertRaises(_OriginalDomainError) as again:
                action()
            self.assertIs(again.exception, error.exception)
        self.assertEqual(f.events, before)
        self.assertFalse(f.descriptor.close_attempted)

    def test_wrong_read_operation_is_unknown_not_a_current_success(self):
        f = ReadFixture()
        d = f.take()
        f.wrong_operation = 2
        with self.assertRaises(_OriginalDomainError) as error:
            d._require_read_current(f.read_functions)
        self.assertTrue(error.exception.unknown)
        self.assertEqual(d._domain.value, 301)
        self.assertIsNotNone(d._reply.value)

    def test_foreign_component_is_refused_before_any_original_call(self):
        f = ReadFixture()
        d = f.take()
        foreign = ReadFixture()
        before = list(f.events)
        with self.assertRaises(ValueError):
            d._prepare_read_context(foreign.read_functions)
        self.assertEqual(f.events, before)
        self.assertIsNone(d._unknown)

    def test_original_cleanup_scope_leaves_after_a_managed_failure(self):
        f = ReadFixture()
        d = f.take()
        primary = ValueError('original managed failure')
        with self.assertRaises(ValueError) as error:
            with d._read_scope(f.read_functions, cleanup=True):
                raise primary
        self.assertIs(error.exception, primary)
        self.assertEqual([x[1] for x in f.events if x[0] == 'read'], [12, 11])
        self.assertFalse(d._closed)
        self.assertEqual(d._domain.value, 301)


if __name__ == '__main__':
    unittest.main()
