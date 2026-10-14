"""Independent scalar faults; actual Native/DLL conformance is separate."""
import copy
import pickle
import unittest
from unittest.mock import patch

from test_local_native_control_custody import Fixture
from actql_sdk._local_native_control_custody import _OriginalControlError
from actql_sdk._local_worker_slot import _OriginalDescriptor


class OriginalControlFDTests(unittest.TestCase):
    def test_original_fd_is_lent_once_and_is_not_closed_by_host_cleanup(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(44)
        with patch('actql_sdk._local_worker_slot.os.close') as physical_close:
            fact = host.acquire_fd(fd)
            self.assertEqual((fact.operation, fact.issue_family), (2, 0))
            self.assertIs(host._borrowed_fd, fd)
            self.assertIsNone(host._reply.value)
            host.close()
            physical_close.assert_not_called()
        self.assertTrue(host._closed)
        self.assertFalse(fd.closed)
        self.assertEqual([e for e in f.events if e[0] == 'acquire_fd'], [('acquire_fd', 101, 44)])

    def test_duplicate_acquire_is_rejected_before_a_second_call(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(45)
        host.acquire_fd(fd); before = list(f.events)
        with self.assertRaises(ValueError): host.acquire_fd(fd)
        self.assertEqual(f.events, before)
        host.close()

    def test_closed_descriptor_is_rejected_before_native_call(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(46)
        with patch('actql_sdk._local_worker_slot.os.close'): fd.close()
        before = list(f.events)
        with self.assertRaises(ValueError): host.acquire_fd(fd)
        self.assertEqual(f.events, before)
        self.assertFalse(host._acquire_started)
        host.close()

    def test_unknown_fd_close_is_not_retried_or_accepted_for_acquire(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(47)
        primary = OSError('original FD close response lost')
        with patch('actql_sdk._local_worker_slot.os.close', side_effect=primary) as physical_close:
            with self.assertRaises(OSError): fd.close()
            with self.assertRaises(RuntimeError): fd.close()
            physical_close.assert_called_once_with(47)
        before = list(f.events)
        with self.assertRaises(ValueError): host.acquire_fd(fd)
        self.assertEqual(f.events, before)
        self.assertIs(fd.close_failure, primary)
        host.close()

    def test_lost_acquire_reply_preserves_same_host_fd_and_reply_without_retry(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(48)
        primary = OSError('acquire response lost after typed reply')
        actual = f.functions.acquire_fd.call
        def lost(*args):
            actual(*args)
            raise primary
        f.functions.acquire_fd.call = lost
        with self.assertRaises(_OriginalControlError) as caught: host.acquire_fd(fd)
        failure = caught.exception
        self.assertTrue(failure.unknown)
        self.assertIs(failure.cleanup_host, host)
        self.assertIs(host._borrowed_fd, fd)
        self.assertIs(failure.__cause__, primary)
        self.assertEqual(host._reply.value, 14)
        self.assertFalse(fd.close_attempted)
        before = list(f.events)
        for action in (lambda: host.acquire_fd(fd), host.current, host.close):
            with self.assertRaises(_OriginalControlError) as repeated: action()
            self.assertIs(repeated.exception, failure)
        self.assertEqual(f.events, before)

    def test_typed_physical_failure_keeps_fd_and_same_cleanup_owner(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(49)
        actual = f.functions.acquire_fd.call
        def failed(*args):
            actual(*args); f.replies[14] = (2, 6)
            return 0
        f.functions.acquire_fd.call = failed
        with self.assertRaises(_OriginalControlError) as caught: host.acquire_fd(fd)
        failure = caught.exception
        self.assertFalse(failure.unknown)
        self.assertEqual((failure.fact.operation, failure.fact.issue_family), (2, 6))
        self.assertIs(failure.cleanup_host, host)
        self.assertIs(host._borrowed_fd, fd)
        self.assertIsNone(host._reply.value)
        self.assertFalse(host._closed)
        host.close()
        self.assertTrue(host._closed)
        self.assertFalse(fd.close_attempted)

    def test_wrong_operation_is_unknown_not_a_successful_acquisition(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(50)
        actual = f.functions.acquire_fd.call
        def wrong(*args):
            actual(*args); f.replies[14] = (3, 0)
            return 0
        f.functions.acquire_fd.call = wrong
        with self.assertRaises(_OriginalControlError) as caught: host.acquire_fd(fd)
        self.assertTrue(caught.exception.unknown)
        self.assertIs(host._borrowed_fd, fd)
        self.assertEqual(host._reply.value, 14)

    def test_descriptor_copy_and_foreign_shell_cannot_transfer_original_custody(self):
        f = Fixture(); host = f.take(); fd = _OriginalDescriptor(51)
        for action in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): action(fd)
        shell = object.__new__(_OriginalDescriptor); shell.__dict__.update(fd.__dict__)
        before = list(f.events)
        with self.assertRaises(ValueError): host.acquire_fd(shell)
        with patch('actql_sdk._local_worker_slot.os.close') as close:
            with self.assertRaises(ValueError): shell.close()
            close.assert_not_called()
        self.assertEqual(f.events, before)
        host.close()


if __name__ == '__main__':
    unittest.main()
