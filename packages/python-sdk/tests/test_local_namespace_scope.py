"""Independent actual SQLite read-only namespace lifetime/fence cases."""
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import LocalByteStore, ByteFence, LocalStorageError


class LocalNamespaceScopeTests(unittest.TestCase):
    def store(self, *, factory=None):
        directory = TemporaryDirectory(prefix='actql-namespace-scope-')
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'original.sqlite'
        if factory is None:
            store = LocalByteStore(path, max_records=8, max_record_bytes=256, max_payload_bytes=1024)
        else:
            connect = sqlite3.connect
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': factory}))):
                store = LocalByteStore(path, max_records=8, max_record_bytes=256, max_payload_bytes=1024)
        self.addCleanup(store.close)
        store.compare_exchange('epoch', None, b'original')
        store.compare_exchange(store.namespaced_key('e\u0301:/~', 'key'), None, b'{"n":null,"s":"a\\r\\n"}')
        return store

    def fences(self):
        return (ByteFence('epoch', 0, b'original'),)

    def test_read_only_exact_snapshot_and_late_reader_rejection(self):
        store = self.store()
        before = store._connection.total_changes
        captured, seen, sql = [], [], []
        store._connection.set_trace_callback(sql.append)
        def inspect(reader):
            captured.append(reader)
            reader.read('e\u0301:/~', 'key', lambda row: seen.append(row))
            reader.scan_after('e\u0301:/~', 'key', lambda row: seen.append(row))
        store.inspect_namespaces(self.fences(), inspect=inspect, current=lambda: None)
        self.assertEqual(seen[0][0], 'key')
        self.assertEqual(seen[0][1].payload, b'{"n":null,"s":"a\\r\\n"}')
        self.assertIsNone(seen[1])
        self.assertEqual(store._connection.total_changes, before)
        self.assertFalse(any(s.startswith(('COMMIT', 'INSERT', 'UPDATE', 'DELETE')) for s in sql))
        self.assertEqual(sql[0], 'BEGIN')
        self.assertEqual(sql[-1], 'ROLLBACK')
        self.assertFalse(store._connection.in_transaction)
        with self.assertRaises(ValueError):
            captured[0].read('e\u0301:/~', 'key', lambda row: None)

    def test_invalid_or_changed_fences_and_boolean_current_refuse_before_consumption(self):
        store = self.store()
        called = []
        invalid = [(), (ByteFence('epoch', True, b'original'),),
                   (ByteFence('epoch', 0, b'original'),) * 2,
                   (ByteFence('epoch', 0, b'x' * 257),)]
        for fences in invalid:
            with self.assertRaises(ValueError):
                store.inspect_namespaces(fences, inspect=lambda r: called.append(r), current=lambda: None)
        with self.assertRaises(LocalStorageError):
            store.inspect_namespaces((ByteFence('epoch', 1, b'changed'),),
                                     inspect=lambda r: called.append(r), current=lambda: None)
        with self.assertRaises(ValueError):
            store.inspect_namespaces(self.fences(), inspect=lambda r: called.append(r), current=lambda: True)
        self.assertEqual(called, [])
        self.assertFalse(store._connection.in_transaction)
        self.assertEqual(store.read('epoch').payload, b'original')

    def test_zero_queries_cannot_claim_completed_inspection(self):
        store = self.store()
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            store.inspect_namespaces(self.fences(), inspect=lambda reader: None, current=lambda: None)
        self.assertFalse(store._connection.in_transaction)
        self.assertEqual(store.read('epoch').generation, 0)

    def test_current_failure_after_transfer_is_not_a_successful_snapshot(self):
        store = self.store()
        failure = OSError('current original unavailable')
        ready = [True]
        def current():
            if not ready[0]:
                raise failure
        def inspect(reader):
            def consume(row):
                self.assertIsNotNone(row)
                ready[0] = False
            reader.read('e\u0301:/~', 'key', consume)
        with self.assertRaises(OSError) as raised:
            store.inspect_namespaces(self.fences(), inspect=inspect, current=current)
        self.assertIs(raised.exception, failure)
        self.assertFalse(store._connection.in_transaction)

    def test_wrong_thread_or_recursive_reader_latches_failure(self):
        store = self.store()
        failures = []
        def inspect(reader):
            def foreign():
                try:
                    reader.read('e\u0301:/~', 'key', lambda row: None)
                except BaseException as error:
                    failures.append(error)
            thread = Thread(target=foreign)
            thread.start()
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive())
        with self.assertRaises(ValueError):
            store.inspect_namespaces(self.fences(), inspect=inspect, current=lambda: None)
        self.assertEqual(len(failures), 1)
        self.assertFalse(store._connection.in_transaction)
        def nested(reader):
            def consume(row):
                reader.read('e\u0301:/~', 'key', lambda other: None)
            reader.read('e\u0301:/~', 'key', consume)
        with self.assertRaises(ValueError):
            store.inspect_namespaces(self.fences(), inspect=nested, current=lambda: None)
        self.assertFalse(store._connection.in_transaction)

    def test_failed_rollback_keeps_same_store_and_no_observation_escapes(self):
        class FailedRollback(sqlite3.Connection):
            failed = False
            def execute(self, statement, *args, **kwargs):
                if statement == 'ROLLBACK' and not self.failed:
                    self.failed = True
                    raise OSError('physical snapshot stop unknown')
                return super().execute(statement, *args, **kwargs)
        store = self.store(factory=FailedRollback)
        captured = []
        def inspect(reader):
            captured.append(reader)
            reader.read('e\u0301:/~', 'key', lambda row: None)
        with self.assertRaises(OSError):
            store.inspect_namespaces(self.fences(), inspect=inspect, current=lambda: None)
        self.assertTrue(store._connection.in_transaction)
        with self.assertRaises(LocalStorageError):
            store.read('epoch')
        with self.assertRaises(ValueError):
            captured[0].current()
        # Explicit cleanup stays with the same connection; it does not commit.
        store.close()


if __name__ == '__main__':
    unittest.main()
