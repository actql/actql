"""Independent SQLite transport fixtures; no Core admission is asserted."""
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from threading import Thread
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    ByteFence, ByteWrite, LocalByteStore, LocalStorageCommitUnknown,
    LocalStorageError, StoredBytes, _NamespaceReader,
)


class LocalInventoryTransactionTests(unittest.TestCase):
    def test_selected_query_work_budget_is_separate_from_persisted_row_capacity(self) -> None:
        with LocalByteStore(self.path.parent / 'selected.sqlite', max_records=2,
                            max_record_bytes=128, max_payload_bytes=512,
                            max_inspection_queries=5) as store:
            key = store.namespaced_key('original', 'row')
            self.assertEqual(store.compare_exchange('epoch', None, b'original'), 0)
            self.assertEqual(store.compare_exchange(key, None, b'value'), 0)
            fence = (ByteFence('epoch', 0, b'original'),)
            seen: list[object] = []

            def inspect(reader: _NamespaceReader) -> None:
                for _ in range(3):
                    reader.read('original', 'row', seen.append)
                for _ in range(2):
                    reader.scan_after('original', 'row', seen.append)

            store.inspect_namespaces(fence, inspect=inspect, current=lambda: None)
            self.assertEqual(seen, [('row', StoredBytes(0, b'value'))] * 3 + [None] * 2)
            # A larger work budget supplies no additional durable row capacity.
            with self.assertRaises(LocalStorageError):
                store.compare_exchange('third-row', None, b'not-admitted')
            self.assertIsNone(store.read('third-row'))

    def test_selected_query_budget_exhaustion_stays_failed_before_cas(self) -> None:
        with LocalByteStore(self.path.parent / 'bounded.sqlite', max_records=2,
                            max_record_bytes=128, max_payload_bytes=512,
                            max_inspection_queries=5) as store:
            self.assertEqual(store.compare_exchange('epoch', None, b'original'), 0)
            fence = (ByteFence('epoch', 0, b'original'),)
            seen: list[object] = []

            def inspect(reader: _NamespaceReader) -> None:
                for _ in range(5):
                    reader.read('empty', 'row', seen.append)
                with self.assertRaisesRegex(LocalStorageError, 'inspection capacity exceeded'):
                    reader.scan_after('empty', '', seen.append)
                # Catching the exhausted callback cannot turn it into success.

            with self.assertRaisesRegex(LocalStorageError, 'inspection capacity exceeded'):
                store.compare_exchange_many_inspected((ByteWrite('epoch', 0, b'changed'),),
                    fence, inspect=inspect, current=lambda: None)
            self.assertEqual(seen, [None] * 5)
            self.assertEqual(store.read('epoch'), StoredBytes(0, b'original'))

    def test_selected_query_budget_does_not_expand_cumulative_copy_limit(self) -> None:
        with LocalByteStore(self.path.parent / 'copy.sqlite', max_records=2,
                            max_record_bytes=128, max_payload_bytes=128,
                            max_inspection_queries=5) as store:
            self.assertEqual(store.compare_exchange('epoch', None, b'e'), 0)
            self.assertEqual(store.compare_exchange(
                store.namespaced_key('original', 'row'), None, b'x' * 64), 0)

            def inspect(reader: _NamespaceReader) -> None:
                for _ in range(3):
                    reader.read('original', 'row', lambda row: None)

            with self.assertRaises(LocalStorageError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'e'),),
                    inspect=inspect, current=lambda: None)

    def test_invalid_selected_query_budget_refuses_before_file_creation(self) -> None:
        for index, value in enumerate([True, 0, -1, 65537, 1.5]):
            path = self.path.parent / f'invalid-{index}.sqlite'
            with self.assertRaises(ValueError):
                LocalByteStore(path, max_records=2, max_record_bytes=128,
                               max_payload_bytes=512, max_inspection_queries=value)
            self.assertFalse(path.exists())

    def setUp(self) -> None:
        self.directory = TemporaryDirectory(prefix='actql-python-inventory-')
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'original.sqlite'
        self.store = self.make_store()
        self.addCleanup(self.store.close)
        for key, body in [('epoch', b'original-epoch'), ('config', b'original-config'),
                          ('count', b'1')]:
            self.assertEqual(self.store.compare_exchange(key, None, body), 0)
        self.old_key = self.store.namespaced_key('client_runs', 'run-old')
        self.new_key = self.store.namespaced_key('client_runs', 'run-new')
        self.raw = b'{"e\xcc\x81/~":null,"s":"a\\r\\nb","n":1.25}'
        self.assertEqual(self.store.compare_exchange(self.old_key, None, self.raw), 0)
        self.fences = (ByteFence('epoch', 0, b'original-epoch'),
                       ByteFence('config', 0, b'original-config'),
                       ByteFence('count', 0, b'1'))
        self.writes = (ByteWrite('count', 0, b'2'),
                       ByteWrite(self.new_key, None, b'original-new-row'))

    def make_store(self, *, records: int = 12, row: int = 128,
                   total: int = 512) -> LocalByteStore:
        return LocalByteStore(self.path, max_records=records,
                              max_record_bytes=row, max_payload_bytes=total)

    def original_inventory(self, read: _NamespaceReader) -> None:
        # This is a fixed transport oracle, not a product state machine.
        read.scan_after('client_runs', '',
             lambda row: self.assertEqual(row, ('run-old', StoredBytes(0, self.raw))))
        read.scan_after('client_runs', 'run-old', lambda row: self.assertIsNone(row))

    def assert_unwritten(self) -> None:
        self.assertEqual(self.store.read('count'), StoredBytes(0, b'1'))
        self.assertIsNone(self.store.read(self.new_key))

    def test_exact_original_rows_and_physical_end_precede_atomic_cas(self) -> None:
        self.assertEqual(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=self.original_inventory,
            current=lambda: None), (1, 0))
        self.assertEqual(self.store.read('count'), StoredBytes(1, b'2'))
        self.assertEqual(self.store.read(self.old_key), StoredBytes(0, self.raw))
        self.assertEqual(self.store.read(self.new_key), StoredBytes(0, b'original-new-row'))

    def test_exact_read_and_scan_share_original_snapshot_without_neighbor_substitution(self) -> None:
        observations: list[object] = []

        def inspect(reader: _NamespaceReader) -> None:
            reader.read('client_runs', 'run-old', observations.append)
            reader.read('client_runs', 'run-missing', observations.append)
            reader.read('client_runs', 'run-new', observations.append)
            reader.scan_after('client_runs', '', observations.append)
            reader.scan_after('client_runs', 'run-old', observations.append)

        self.assertEqual(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=inspect, current=lambda: None), (1, 0))
        self.assertEqual(observations, [
            ('run-old', StoredBytes(0, self.raw)), None, None,
            ('run-old', StoredBytes(0, self.raw)), None])
        # These observations preceded the actual write, not a candidate read.
        self.assertEqual(self.store.read(self.new_key), StoredBytes(0, b'original-new-row'))

    def test_exact_namespace_key_preserves_unicode_null_and_prefix_neighbors(self) -> None:
        namespace = 'e\u0301:/~'
        for selected, raw in [(namespace, b'original'), ('é:/~', b'composed'),
                               (namespace + ':', b'prefix')]:
            self.assertEqual(self.store.compare_exchange(
                self.store.namespaced_key(selected, 'key\x00/~'), None, raw), 0)

        def inspect(reader: _NamespaceReader) -> None:
            reader.read(namespace, 'key\x00/~', lambda row: self.assertEqual(
                row, ('key\x00/~', StoredBytes(0, b'original'))))
            reader.read(namespace, 'key', lambda row: self.assertIsNone(row))
            reader.read('absent', 'key\x00/~', lambda row: self.assertIsNone(row))

        self.assertEqual(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=inspect, current=lambda: None), (1, 0))

    def test_exact_reads_and_scans_share_query_and_cumulative_copy_limits(self) -> None:
        long_key = self.store.namespaced_key('long', 'row')
        self.assertEqual(self.store.compare_exchange(long_key, None, b'x' * 64), 0)

        def many(reader: _NamespaceReader) -> None:
            for _ in range(7):
                reader.read('empty', 'row', lambda row: self.assertIsNone(row))
                reader.scan_after('empty', '', lambda row: self.assertIsNone(row))

        def copies(reader: _NamespaceReader) -> None:
            for _ in range(5):
                reader.read('long', 'row', lambda row: self.assertIsNotNone(row))
                reader.scan_after('long', '', lambda row: self.assertIsNotNone(row))

        for inspect in [many, copies]:
            with self.assertRaises(LocalStorageError):
                self.store.compare_exchange_many_inspected(
                    self.writes, self.fences, inspect=inspect, current=lambda: None)
            self.assert_unwritten()

    def test_exact_reader_refuses_recursive_consumption_and_expired_transaction_loan(self) -> None:
        readers: list[_NamespaceReader] = []

        def inspect(reader: _NamespaceReader) -> None:
            readers.append(reader)
            reader.read('client_runs', 'run-old', lambda row: self.assertEqual(
                row, ('run-old', StoredBytes(0, self.raw))))

        self.assertEqual(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=inspect, current=lambda: None), (1, 0))
        with self.assertRaises(ValueError):
            readers[0].read('client_runs', 'run-old', lambda row: None)
        # Select the independently fixed successor as the next transaction fence.
        self.writes = (ByteWrite('count', 1, b'3'),)
        self.fences = (ByteFence('epoch', 0, b'original-epoch'),
                       ByteFence('config', 0, b'original-config'),
                       ByteFence('count', 1, b'2'))

        def recursive(reader: _NamespaceReader) -> None:
            try:
                reader.read('client_runs', 'run-old', lambda row:
                            reader.scan_after('client_runs', '', lambda nested: None))
            except ValueError:
                pass

        with self.assertRaises(ValueError):
            self.store.compare_exchange_many_inspected(
                self.writes, self.fences, inspect=recursive, current=lambda: None)
        self.assertEqual(self.store.read('count'), StoredBytes(1, b'2'))

    def test_unknown_extra_row_is_observed_despite_unchanged_count(self) -> None:
        extra = self.store.namespaced_key('client_runs', 'run-unknown')
        self.assertEqual(self.store.compare_exchange(extra, None, b'unknown-row'), 0)
        # The expected physical end is now false. Do not replace the independent
        # inventory oracle with the product's actual count or filtered rows.
        with self.assertRaises(AssertionError):
            self.store.compare_exchange_many_inspected(
                self.writes, self.fences, inspect=self.original_inventory,
                current=lambda: None)
        self.assert_unwritten()
        self.assertEqual(self.store.read(extra), StoredBytes(0, b'unknown-row'))

    def test_empty_namespace_unicode_and_prefix_neighbors_are_distinct(self) -> None:
        namespace = 'e\u0301:/~'
        for selected, key, raw in [(namespace, 'a\x00/~', b'original-null-key'),
                                   ('é:/~', 'a\x00/~', b'composed-neighbor'),
                                   (namespace + ':', 'a', b'prefix-neighbor')]:
            self.assertEqual(self.store.compare_exchange(
                self.store.namespaced_key(selected, key), None, raw), 0)

        def inspect(read: _NamespaceReader) -> None:
            read.scan_after('empty', '', lambda row: self.assertIsNone(row))
            read.scan_after(namespace, '', lambda row: self.assertEqual(
                row, ('a\x00/~', StoredBytes(0, b'original-null-key'))))
            read.scan_after(namespace, 'a\x00/~', lambda row: self.assertIsNone(row))

        self.assertEqual(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=inspect, current=lambda: None), (1, 0))

    def test_metadata_mismatch_does_not_call_inspector_or_write(self) -> None:
        self.assertEqual(self.store.compare_exchange('config', 0, b'changed-config'), 1)
        calls: list[object] = []
        self.assertIsNone(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=lambda read: calls.append(read),
            current=lambda: None))
        self.assert_unwritten()
        self.assertEqual(calls, [])

    def test_same_sqlite_write_transaction_excludes_interleaved_writer(self) -> None:
        with sqlite3.connect(self.path, isolation_level=None, timeout=0) as foreign:
            def inspect(read: _NamespaceReader) -> None:
                self.original_inventory(read)
                with self.assertRaises(sqlite3.OperationalError):
                    foreign.execute('INSERT INTO core_bytes VALUES (?, ?, ?)',
                                    ('interleaved', 0, b'foreign'))

            self.assertEqual(self.store.compare_exchange_many_inspected(
                self.writes, self.fences, inspect=inspect, current=lambda: None), (1, 0))
        self.assertIsNone(self.store.read('interleaved'))

    def test_query_failure_is_not_end_even_if_inspector_swallows_it(self) -> None:
        class QueryFailure(sqlite3.Connection):
            fail = False

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if self.fail and 'ORDER BY key COLLATE BINARY LIMIT 1' in sql:
                    raise sqlite3.OperationalError('original query failed')
                return super().execute(sql, *args, **kwargs)

        self.store.close()
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': QueryFailure}))):
            self.store = self.make_store()
        self.addCleanup(self.store.close)
        self.store._connection.fail = True
        consumed: list[object] = []

        for lookup in [False, True]:
            def inspect(read: _NamespaceReader) -> None:
                try:
                    if lookup:
                        read.read('client_runs', 'run-old', consumed.append)
                    else:
                        read.scan_after('client_runs', '', consumed.append)
                except sqlite3.OperationalError:
                    pass

            with self.assertRaisesRegex(sqlite3.OperationalError, 'original query failed'):
                self.store.compare_exchange_many_inspected(
                    self.writes, self.fences, inspect=inspect, current=lambda: None)
            self.assertEqual(consumed, [])
            self.assert_unwritten()

    def test_no_scan_and_permission_or_consumer_booleans_are_refused(self) -> None:
        for inspect, current in [
                (lambda read: None, lambda: None),
                (self.original_inventory, lambda: True),
                (lambda read: read.scan_after('client_runs', '', lambda row: True), lambda: None),
                (lambda read: True, lambda: None)]:
            with self.assertRaises(ValueError):
                self.store.compare_exchange_many_inspected(
                    self.writes, self.fences, inspect=inspect, current=current)
            self.assert_unwritten()

    def test_captured_reader_cannot_outlive_transaction(self) -> None:
        readers: list[_NamespaceReader] = []

        def inspect(read: _NamespaceReader) -> None:
            readers.append(read)
            self.original_inventory(read)

        self.assertEqual(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=inspect, current=lambda: None), (1, 0))
        with self.assertRaises(ValueError):
            readers[0].scan_after('client_runs', '', lambda row: None)

    def test_recursive_or_foreign_thread_reader_failure_cannot_be_swallowed(self) -> None:
        def recursive(read: _NamespaceReader) -> None:
            try:
                read.scan_after('client_runs', '',
                     lambda row: read.scan_after('client_runs', '', lambda nested: None))
            except ValueError:
                pass

        def foreign(read: _NamespaceReader) -> None:
            errors: list[BaseException] = []

            def worker() -> None:
                try:
                    read.scan_after('client_runs', '', lambda row: None)
                except BaseException as error:
                    errors.append(error)

            child = Thread(target=worker)
            child.start()
            child.join(2)
            self.assertFalse(child.is_alive())
            self.assertEqual(len(errors), 1)

        for inspect in [recursive, foreign]:
            with self.assertRaises(ValueError):
                self.store.compare_exchange_many_inspected(
                    self.writes, self.fences, inspect=inspect, current=lambda: None)
            self.assert_unwritten()

    def test_repeated_queries_and_cumulative_copies_remain_bounded(self) -> None:
        def many(read: _NamespaceReader) -> None:
            for _ in range(13):
                read.scan_after('empty', '', lambda row: self.assertIsNone(row))

        # Nine 64-byte copies exceed the fixed 512-byte physical copy bound.
        # Keep the original payload oracle above unchanged.
        long_key = self.store.namespaced_key('long', 'row')
        self.assertEqual(self.store.compare_exchange(long_key, None, b'x' * 64), 0)

        def long_copies(read: _NamespaceReader) -> None:
            for _ in range(9):
                read.scan_after('long', '', lambda row: self.assertIsNotNone(row))

        for inspect in [many, long_copies]:
            with self.assertRaises(LocalStorageError):
                self.store.compare_exchange_many_inspected(
                    self.writes, self.fences, inspect=inspect, current=lambda: None)
            self.assert_unwritten()

    def test_foreign_oversized_row_and_empty_key_are_refused_not_omitted(self) -> None:
        prefix = 'namespace:11:client_runs:'
        for key, raw in [(prefix + 'oversized', b'x' * 129), (prefix, b'empty-key')]:
            with sqlite3.connect(self.path) as foreign:
                foreign.execute('INSERT INTO core_bytes VALUES (?, ?, ?)', (key, 0, raw))
            with self.assertRaises((LocalStorageError, ValueError)):
                self.store.compare_exchange_many_inspected(
                    self.writes, self.fences,
                    inspect=lambda read: read.scan_after('client_runs', '', lambda row: None),
                    current=lambda: None)
            self.assert_unwritten()
            with sqlite3.connect(self.path) as foreign:
                foreign.execute('DELETE FROM core_bytes WHERE key = ?', (key,))

    def test_current_revocation_during_consumption_rolls_back_without_write(self) -> None:
        revoked = False

        def current() -> None:
            if revoked:
                raise PermissionError('original publisher revoked')

        def inspect(read: _NamespaceReader) -> None:
            def consume(row: object) -> None:
                nonlocal revoked
                self.assertEqual(row, ('run-old', StoredBytes(0, self.raw)))
                revoked = True

            read.scan_after('client_runs', '', consume)

        with self.assertRaises(PermissionError):
            self.store.compare_exchange_many_inspected(
                self.writes, self.fences, inspect=inspect, current=current)
        self.assert_unwritten()

    def test_lost_commit_ack_uses_same_store_successor_inspection_without_resend(self) -> None:
        class LostAck(sqlite3.Connection):
            lose = False
            inserts = 0

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if sql.startswith('INSERT'):
                    self.inserts += 1
                result = super().execute(sql, *args, **kwargs)
                if self.lose and sql == 'COMMIT':
                    self.lose = False
                    raise OSError('original ACK lost')
                return result

        self.store.close()
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostAck}))):
            self.store = self.make_store()
        self.addCleanup(self.store.close)
        self.store._connection.lose = True
        with self.assertRaises(LocalStorageCommitUnknown) as failed:
            self.store.compare_exchange_many_inspected(
                self.writes, self.fences, inspect=self.original_inventory,
                current=lambda: None)
        self.assertIs(failed.exception.cleanup_store, self.store)
        self.assertIsInstance(failed.exception.__cause__, OSError)
        self.assertEqual(self.store._connection.inserts, 1)

        def saved(read: _NamespaceReader) -> None:
            read.scan_after('client_runs', '', lambda row: self.assertEqual(
                row, ('run-new', StoredBytes(0, b'original-new-row'))))
            read.scan_after('client_runs', 'run-new', lambda row: self.assertEqual(
                row, ('run-old', StoredBytes(0, self.raw))))
            read.scan_after('client_runs', 'run-old', lambda row: self.assertIsNone(row))

        self.assertEqual(self.store.read_exchange_many_inspected(
            self.writes, self.fences, inspect=saved, current=lambda: None),
            (StoredBytes(1, b'2'), StoredBytes(0, b'original-new-row')))
        self.assertEqual(self.store._connection.inserts, 1)

    def test_unmatched_successor_does_not_inspect_or_imply_nonexecution(self) -> None:
        calls: list[object] = []
        self.assertIsNone(self.store.read_exchange_many_inspected(
            self.writes, self.fences, inspect=lambda read: calls.append(read),
            current=lambda: None))
        self.assertEqual(calls, [])
        self.assert_unwritten()

    def test_cleanup_failure_keeps_same_store_transaction_pending(self) -> None:
        class PendingCleanup(sqlite3.Connection):
            refuse = False
            attempts = 0

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if self.refuse and sql == 'ROLLBACK':
                    self.attempts += 1
                    raise OSError('original snapshot cleanup failed')
                return super().execute(sql, *args, **kwargs)

        self.assertEqual(self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=self.original_inventory,
            current=lambda: None), (1, 0))
        self.store.close()
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': PendingCleanup}))):
            self.store = self.make_store()
        self.addCleanup(self.store.close)
        self.store._connection.refuse = True
        with self.assertRaisesRegex(OSError, 'snapshot cleanup failed'):
            self.store.read_exchange_many_inspected(
                self.writes, self.fences,
                inspect=lambda read: read.scan_after('empty', '', lambda row: self.assertIsNone(row)),
                current=lambda: None)
        self.assertEqual(self.store._connection.attempts, 1)
        self.assertTrue(self.store._connection.in_transaction)
        with self.assertRaises(LocalStorageError):
            self.store.read('count')
        self.assertEqual(self.store._connection.attempts, 1)
        # The same physical connection owns retry/close; there is no replacement
        # handle or implicit transaction retry after failed cleanup.
        self.store._connection.refuse = False
        self.store._connection.execute('ROLLBACK')
        self.assertEqual(self.store.read('count'), StoredBytes(1, b'2'))
