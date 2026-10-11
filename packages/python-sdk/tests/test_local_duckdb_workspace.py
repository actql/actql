"""Physical assembly cases; these do not authorize or admit a Run."""
import copy
from threading import Event, Thread
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_duckdb import DuckDBConnection
from actql_sdk._local_duckdb_workspace import DuckDBWorkspace


class DuckDBWorkspaceTests(unittest.TestCase):
    def core(self):
        core = SimpleNamespace()
        calls = []
        loan = object()
        def reserve(bytes, *, stopped, cleanup):
            calls.append(('reserve', bytes))
            core.stopped = stopped
            core.cleanup = cleanup
            self.assertFalse(stopped(), 'Initialization has not entered native code')
            return loan
        def close(value):
            self.assertIs(value, loan)
            calls.append(('close',))
            return core.stopped() is True and core.cleanup() is True
        core.reserve_workspace = reserve
        core.close_workspace = close
        return core, calls

    def connection(self):
        connection = DuckDBConnection.__new__(DuckDBConnection)
        connection.stop_new_io = Mock(return_value=True)
        connection.close = Mock(return_value=True)
        return connection

    def test_capacity_refusal_precedes_native_constructor(self):
        core, _ = self.core()
        core.reserve_workspace = Mock(side_effect=LocalCoreError('workspace', -4))
        with patch.object(DuckDBWorkspace, '_open_connection') as native:
            with self.assertRaises(LocalCoreError):
                DuckDBWorkspace(core, object(), '', workspace_bytes=128, memory_bytes=64,
                                readonly=False)
            native.assert_not_called()

    def test_stop_and_cleanup_pending_keep_exact_connection_and_loan(self):
        core, calls = self.core()
        connection = self.connection()
        with patch.object(DuckDBWorkspace, '_open_connection', return_value=connection):
            workspace = DuckDBWorkspace(core, object(), '', workspace_bytes=128,
                                        memory_bytes=64, readonly=False)
        self.assertIs(workspace.connection(), connection)
        connection.stop_new_io.return_value = False
        self.assertFalse(workspace.close())
        connection.close.assert_not_called()
        connection.stop_new_io.return_value = True
        connection.close.return_value = False
        self.assertFalse(workspace.close())
        self.assertIs(workspace._connection, connection)
        connection.close.return_value = True
        self.assertTrue(workspace.close())
        baseline = len(calls)
        self.assertTrue(workspace.close())
        self.assertEqual(len(calls), baseline)
        self.assertEqual(connection.close.call_count, 2)
        with self.assertRaises(RuntimeError):
            workspace.connection()

    def test_failed_native_initialization_retains_original_cleanup(self):
        core, _ = self.core()
        pending = self.connection()
        pending.close.return_value = False
        failure = OSError('independent native construction failure')
        failure.physical_cleanup = pending
        with patch.object(DuckDBWorkspace, '_open_connection', side_effect=failure):
            with self.assertRaises(OSError) as caught:
                DuckDBWorkspace(core, object(), '', workspace_bytes=128, memory_bytes=64,
                                readonly=False)
        workspace = caught.exception.physical_cleanup
        self.assertIs(workspace._connection, pending)
        self.assertFalse(workspace._closed)
        pending.close.return_value = True
        self.assertTrue(workspace.close())
        self.assertEqual(pending.close.call_count, 2)

    def test_unknown_initialization_cleanup_cannot_return_capacity(self):
        core, calls = self.core()
        pending = object()
        failure = OSError('unknown physical cleanup')
        failure.physical_cleanup = pending
        with patch.object(DuckDBWorkspace, '_open_connection', side_effect=failure):
            with self.assertRaises(OSError) as caught:
                DuckDBWorkspace(core, object(), '', workspace_bytes=128, memory_bytes=64,
                                readonly=False)
        workspace = caught.exception.physical_cleanup
        self.assertIs(workspace._cleanup_unknown, pending)
        self.assertFalse(workspace.close())
        self.assertFalse(workspace._closed)
        self.assertEqual(calls, [('reserve', 128), ('close',), ('close',)])

    def test_overlapping_close_observes_pending_without_waiting_under_callback_lock(self):
        core, _ = self.core()
        connection = self.connection()
        with patch.object(DuckDBWorkspace, '_open_connection', return_value=connection):
            workspace = DuckDBWorkspace(core, object(), '', workspace_bytes=128,
                                        memory_bytes=64, readonly=False)
        entered, release, second_done = Event(), Event(), Event()
        original = core.close_workspace
        first_results, second_results, failures = [], [], []
        def closing(loan):
            entered.set()
            if not release.wait(2):
                raise AssertionError('Independent callback wait timed out')
            return original(loan)
        core.close_workspace = closing
        def first():
            try:
                first_results.append(workspace.close())
            except BaseException as error:
                failures.append(error)
        def second():
            try:
                second_results.append(workspace.close())
            except BaseException as error:
                failures.append(error)
            finally:
                second_done.set()
        left = Thread(target=first)
        right = Thread(target=second)
        left.start()
        self.assertTrue(entered.wait(1))
        right.start()
        observed_pending = second_done.wait(1)
        release.set()
        left.join(2)
        right.join(2)
        self.assertFalse(left.is_alive() or right.is_alive())
        self.assertEqual(failures, [])
        self.assertTrue(observed_pending)
        self.assertEqual(first_results, [True])
        self.assertEqual(second_results, [False])
        self.assertTrue(workspace.close())

    def test_copied_workspace_cannot_close_or_obtain_original_connection(self):
        core, calls = self.core()
        connection = self.connection()
        with patch.object(DuckDBWorkspace, '_open_connection', return_value=connection):
            workspace = DuckDBWorkspace(core, object(), '', workspace_bytes=128,
                                        memory_bytes=64, readonly=False)
        baseline = len(calls)
        for action in (copy.copy(workspace).close, copy.copy(workspace).connection):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        self.assertTrue(workspace.close())


if __name__ == '__main__':
    unittest.main()
