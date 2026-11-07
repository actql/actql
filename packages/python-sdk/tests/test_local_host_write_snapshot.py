"""Actual fenced SQLite/current loans with scalar Core, not product acceptance."""
import copy
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError
from actql_sdk._local_storage import (
    ByteWrite, LocalStorageCommitUnknown, LocalStorageError, StoredBytes,
)
from test_local_host_binding import OriginalHostBindingTests


class OriginalHostWriteSnapshotTests(unittest.TestCase):
    def fixture(self):
        return OriginalHostBindingTests.fixture(self)

    def test_same_write_snapshot_and_fresh_successor_lookup_do_not_resend(self):
        _, store, core, _, _, _, _, calls, _, _, binding = self.fixture()
        key = store.namespaced_key('client_runs', 'original')
        write = ByteWrite(key, None, b'opaque-Core-candidate')
        inspected = []
        def inspect(reader):
            def consume(current):
                inspected.append(reader)
                self.assertIs(core._journal_callbacks(current.ticket).reader, reader)
                reader.read('client_runs', 'original', lambda row: self.assertIsNone(row))
            binding.inspect_reader(reader, consume)
        before = store._connection.total_changes
        with binding.fenced() as fences:
            self.assertEqual(store.compare_exchange_many_inspected(
                (write,), fences, inspect=inspect, current=binding.current), (0,))
        self.assertEqual(store._connection.total_changes, before + 1)
        self.assertEqual(store.read(key), StoredBytes(0, write.payload))
        self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)
        changes = store._connection.total_changes
        def lookup(reader):
            def consume(current):
                reader.read('client_runs', 'original', lambda row: self.assertEqual(
                    row, ('original', StoredBytes(0, write.payload))))
            binding.inspect_reader(reader, consume)
        with binding.fenced() as fences:
            self.assertEqual(store.read_exchange_many_inspected(
                (write,), fences, inspect=lookup, current=binding.current),
                (StoredBytes(0, write.payload),))
        self.assertEqual(store._connection.total_changes, changes)
        self.assertEqual(len(inspected), 1)
        self.assertFalse(any(name in ('start', 'dispatch', 'produce', 'finish_commit')
                             for _, name, _ in calls))

    def test_omitted_adoption_or_epoch_fence_refuses_before_core_and_cas(self):
        for omitted in (0, -1):
            with self.subTest(omitted=omitted):
                _, store, _, _, _, _, _, calls, _, _, binding = self.fixture()
                write = ByteWrite('candidate', None, b'opaque-candidate')
                before = len(calls)
                with binding.fenced() as fences:
                    omitted_index = omitted % len(fences)
                    incomplete = tuple(value for index, value in enumerate(fences)
                                       if index != omitted_index)
                    with self.assertRaisesRegex(LocalStorageError, 'required physical fences'):
                        store.compare_exchange_many_inspected((write,), incomplete,
                            inspect=lambda reader: binding.inspect_reader(
                                reader, lambda _: self.fail('Missing fence reached Core work')),
                            current=binding.current)
                self.assertEqual(len(calls), before)
                self.assertIsNone(store.read(write.key))
                self.assertFalse(store._connection.in_transaction)

    def test_copied_reader_cannot_borrow_original_current_even_if_error_is_caught(self):
        _, store, _, _, _, _, _, calls, _, _, binding = self.fixture()
        before = len(calls)
        with binding.fenced() as fences:
            def inspect(reader):
                with self.assertRaisesRegex(ValueError, 'Copied or foreign'):
                    binding.inspect_reader(copy.copy(reader), lambda _: None)
            with self.assertRaisesRegex(ValueError, 'Copied or foreign'):
                store.compare_exchange_many_inspected((ByteWrite('candidate', None, b'candidate'),),
                    fences, inspect=inspect, current=binding.current)
        self.assertEqual(len(calls), before)
        self.assertIsNone(store.read('candidate'))

    def test_expired_reader_and_unfenced_current_refuse_without_new_work(self):
        _, store, core, _, _, _, _, calls, _, _, binding = self.fixture()
        captured = []
        with binding.fenced() as fences:
            store.inspect_namespaces(fences,
                inspect=lambda reader: binding.inspect_reader(reader,
                    lambda _: captured.append(reader)), current=binding.current)
        before = len(calls)
        with self.assertRaises(ValueError):
            binding.current()
        with binding.fenced():
            with self.assertRaisesRegex(ValueError, 'not active'):
                binding.inspect_reader(captured[0], lambda _: None)
        self.assertEqual(len(calls), before)
        self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)

    def test_precommit_current_change_rolls_back_and_retains_original_loans(self):
        path, store, core, _, _, _, _, _, _, _, binding = self.fixture()
        loan = binding._current
        write = ByteWrite('candidate', None, b'candidate')
        def current():
            if store._connection.execute('SELECT EXISTS(SELECT 1 FROM core_bytes WHERE key=?)',
                                         (write.key,)).fetchone()[0]:
                (path / 'source' / 'account.json').write_bytes(b'changed-original')
            binding.current()
        with binding.fenced() as fences:
            with self.assertRaises(LocalFileError):
                store.compare_exchange_many_inspected((write,), fences,
                    inspect=lambda reader: binding.inspect_reader(reader, lambda _: None),
                    current=current)
        self.assertIsNone(store.read(write.key))
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        self.assertFalse(store._connection.in_transaction)

    def test_actual_lost_commit_ack_keeps_same_store_then_only_looks_up_successor(self):
        class LostAck(sqlite3.Connection):
            lose = False
            inserts = 0
            def execute(self, sql, *args, **kwargs):
                if sql.startswith('INSERT'):
                    self.inserts += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.lose:
                    self.lose = False
                    raise OSError('Original physical commit ACK lost')
                return result
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostAck}))):
            _, store, core, _, _, _, _, _, _, _, binding = self.fixture()
        original_connection = store._connection
        before = original_connection.inserts
        write = ByteWrite('candidate', None, b'original-opaque-Core-candidate')
        original_connection.lose = True
        with binding.fenced() as fences:
            with self.assertRaises(LocalStorageCommitUnknown) as raised:
                store.compare_exchange_many_inspected((write,), fences,
                    inspect=lambda reader: binding.inspect_reader(reader, lambda _: None),
                    current=binding.current)
        self.assertIs(raised.exception.cleanup_store, store)
        self.assertIsInstance(raised.exception.__cause__, OSError)
        self.assertIs(store._connection, original_connection)
        self.assertEqual(original_connection.inserts, before + 1)
        self.assertIs(core._loans[binding._current.ticket], binding._current)
        with binding.fenced() as fences:
            observed = store.read_exchange_many_inspected((write,), fences,
                inspect=lambda reader: binding.inspect_reader(reader, lambda _: None),
                current=binding.current)
        self.assertEqual(observed, (StoredBytes(0, write.payload),))
        self.assertEqual(original_connection.inserts, before + 1)
        self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)

    def test_rollback_failure_retains_same_connection_and_binding_for_explicit_cleanup(self):
        class PendingCleanup(sqlite3.Connection):
            refuse = False
            attempts = 0
            def execute(self, sql, *args, **kwargs):
                if sql == 'ROLLBACK' and self.refuse:
                    self.attempts += 1
                    raise OSError('Original physical rollback failed')
                return super().execute(sql, *args, **kwargs)
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': PendingCleanup}))):
            _, store, core, _, _, _, _, _, _, _, binding = self.fixture()
        original_connection = store._connection
        original_connection.refuse = True
        failure = OSError('Original consumer failed')
        with binding.fenced() as fences:
            with self.assertRaisesRegex(OSError, 'rollback failed'):
                store.compare_exchange_many_inspected((ByteWrite('candidate', None, b'candidate'),),
                    fences, inspect=lambda reader: binding.inspect_reader(reader,
                        lambda _: (_ for _ in ()).throw(failure)), current=binding.current)
        self.assertTrue(original_connection.in_transaction)
        self.assertEqual(original_connection.attempts, 1)
        self.assertIs(store._connection, original_connection)
        self.assertIs(core._loans[binding._current.ticket], binding._current)
        with self.assertRaises(LocalStorageError):
            with binding.fenced():
                self.fail('Pending transaction became a new current frame')
        self.assertEqual(original_connection.attempts, 1)
        original_connection.refuse = False
        original_connection.execute('ROLLBACK')  # Explicit same physical handle cleanup.
        self.assertIsNone(store.read('candidate'))
        self.assertTrue(binding.close())


if __name__ == '__main__':
    unittest.main()
