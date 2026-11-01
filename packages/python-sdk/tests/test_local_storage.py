import base64
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import sqlite3
import subprocess
import sys
from threading import Barrier
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (LocalByteStore, LocalStorageError,
                                      LocalStorageInitializationError, StoredBytes)


class LocalPhysicalStorageTests(unittest.TestCase):
    def test_original_fence_set_matches_exact_bytes_in_one_physical_read(self) -> None:
        with TemporaryDirectory(prefix='actql-exact-fence-set-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                rows = (("original'[]", 0, b'{"missing":null}'),
                        ('e\u0301', 0, b'original\r\nbytes'),
                        ('empty', 0, b''))
                for key, generation, payload in rows:
                    self.assertEqual(store.compare_exchange(key, None, payload), generation)
                statements = []
                store._connection.set_trace_callback(statements.append)
                database = store._physical
                database.begin_read()
                try:
                    self.assertTrue(database._match_rows(rows))
                finally:
                    database.finish_read()
                    store._connection.set_trace_callback(None)
                reads = [sql for sql in statements if 'FROM core_bytes' in sql]
                self.assertEqual(len(reads), 1, reads)
                self.assertFalse(any(sql.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT'))
                                     for sql in statements))

    def store(self, path: Path, *, records: int = 4, row: int = 128,
              total: int = 256) -> LocalByteStore:
        return LocalByteStore(path, max_records=records, max_record_bytes=row,
                              max_payload_bytes=total)

    def test_original_fence_set_requires_every_exact_row_and_indexed_lookup(self) -> None:
        with TemporaryDirectory(prefix='actql-exact-fence-values-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.assertEqual(store.compare_exchange('one', None, b'{"n":1}'), 0)
                self.assertEqual(store.compare_exchange('two', None, b''), 0)
                expected = (('one', 0, b'{"n":1}'), ('two', 0, b''))
                trace = []
                store._connection.set_trace_callback(trace.append)
                database = store._physical
                database.begin_read()
                try:
                    for wrong in ((('absent', 0, b''),),
                                  (('one', 1, b'{"n":1}'),),
                                  (('one', 0, b'{ "n":1}'),),
                                  (('one', 0, b'{"n":1}'), ('absent', 0, b''))):
                        self.assertFalse(database._match_rows(wrong))
                    self.assertTrue(database._match_rows(expected))
                    sql = next(s for s in reversed(trace) if s.startswith('WITH expected'))
                    plan = store._connection.execute('EXPLAIN QUERY PLAN ' + sql).fetchall()
                    self.assertTrue(any('SEARCH actual USING PRIMARY KEY (key=?)' in p[3]
                                        for p in plan), plan)
                    self.assertFalse(any('SCAN actual' in p[3] for p in plan), plan)
                finally:
                    database.finish_read()
                    store._connection.set_trace_callback(None)

    def test_original_fence_set_rejects_unbounded_or_forged_input_before_sql(self) -> None:
        with TemporaryDirectory(prefix='actql-exact-fence-bounds-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                trace = []
                store._connection.set_trace_callback(trace.append)
                rows = (('one', 0, b'a'),)
                bad = ((), list(rows), (('one', True, b'a'),),
                       (('one', -1, b'a'),), (('one', 2**63, b'a'),),
                       (('one', 0, bytearray(b'a')),), rows + rows,
                       tuple((str(i), 0, b'') for i in range(33)),
                       (('one', 0, b'a' * 8192),))
                for value in bad:
                    with self.subTest(value_type=type(value).__name__):
                        with self.assertRaises(ValueError):
                            store._physical._match_rows(value)
                self.assertEqual(trace, [])
                with self.assertRaisesRegex(ValueError, 'snapshot is not active'):
                    store._physical._match_rows(rows)
                self.assertEqual(trace, [])
                store._connection.set_trace_callback(None)

    def test_original_fence_set_keeps_transaction_change_refusal_and_original_error(self) -> None:
        class ChangedRead(sqlite3.Connection):
            change = False
            def execute(self, sql, *args, **kwargs):
                if sql.startswith('WITH expected') and self.change:
                    self.change = False
                    super().execute('CREATE TEMP TABLE changed(value)')
                return super().execute(sql, *args, **kwargs)
        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-exact-fence-current-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **k, factory=ChangedRead)):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    store.compare_exchange('one', None, b'original')
                    database = store._physical
                    database.begin_read()
                    store._connection.change = True
                    try:
                        with self.assertRaisesRegex(ValueError, 'snapshot changed'):
                            database._match_rows((('one', 0, b'original'),))
                        self.assertFalse(store._connection.change)
                        self.assertTrue(database.in_transaction)
                    finally:
                        database.finish_read()
        failure = sqlite3.OperationalError('original fixed-read failure')
        class FailedRead(sqlite3.Connection):
            attempts = 0
            def execute(self, sql, *args, **kwargs):
                if sql.startswith('WITH expected'):
                    self.attempts += 1
                    raise failure
                return super().execute(sql, *args, **kwargs)
        from actql_sdk._local_storage_physical import _SQLiteByteDatabase
        connection = sqlite3.connect(':memory:', factory=FailedRead, isolation_level=None)
        try:
            database = _SQLiteByteDatabase(connection)
            database.begin_read()
            with self.assertRaises(sqlite3.OperationalError) as error:
                database._match_rows((('one', 0, b'original'),))
            self.assertIs(error.exception, failure)
            self.assertEqual(connection.attempts, 1)
            self.assertTrue(database.in_transaction)
            database.finish_read()
        finally:
            connection.close()

    def test_exact_bytes_survive_process_exit_and_reopen(self) -> None:
        # Independently fixed bytes preserve missing, NULL, decomposed keys,
        # CRLF, numeric spelling and order. The store does not parse JSON.
        raw = b'{"e\xcc\x81/~":null,"missing":{},"s":"a\\r\\nb","n":1.25}'
        key = 'e\u0301/~'
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                self.assertEqual(store.compare_exchange(key, None, raw), 0)
                self.assertIsNone(store.read('é/~'))
            source = str(Path(__file__).resolve().parents[1] / 'src')
            child = '''import base64, sys
sys.path.insert(0, sys.argv[1])
from pathlib import Path
from actql_sdk._local_storage import LocalByteStore
with LocalByteStore(Path(sys.argv[2]), max_records=4, max_record_bytes=128, max_payload_bytes=256) as store:
    record = store.read('e\\u0301/~')
    assert record is not None and record.generation == 0
    assert record.payload == base64.b64decode(sys.argv[3])
    assert store.compare_exchange('e\\u0301/~', 0, b'original-next-bytes') == 1
'''
            result = subprocess.run([sys.executable, '-I', '-c', child, source,
                                     str(path), base64.b64encode(raw).decode('ascii')],
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            with self.store(path) as store:
                self.assertEqual(store.read(key), StoredBytes(1, b'original-next-bytes'))
                self.assertIsNone(store.compare_exchange(key, 0, b'stale'))
                self.assertEqual(store.read(key), StoredBytes(1, b'original-next-bytes'))

    def test_two_connections_cannot_replace_another_generation(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as first, self.store(path) as second:
                self.assertEqual(first.compare_exchange('original', None, b'a'), 0)
                self.assertEqual(second.read('original'), StoredBytes(0, b'a'))
                self.assertEqual(first.compare_exchange('original', 0, b'b'), 1)
                self.assertIsNone(second.compare_exchange('original', 0, b'c'))
                self.assertIsNone(second.compare_exchange('original', None, b'c'))
                self.assertEqual(second.read('original'), StoredBytes(1, b'b'))
                self.assertIsNone(first.read('absent'))

    def test_simultaneous_cas_has_one_winner_and_preserves_its_exact_bytes(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as first, self.store(path) as second:
                first.compare_exchange('original', None, b'first')
                barrier = Barrier(2)

                def claim(store: LocalByteStore, payload: bytes) -> int | None:
                    barrier.wait(timeout=5)
                    return store.compare_exchange('original', 0, payload)

                with ThreadPoolExecutor(max_workers=2) as pool:
                    a = pool.submit(claim, first, b'left')
                    b = pool.submit(claim, second, b'right')
                    left, right = a.result(timeout=5), b.result(timeout=5)
                self.assertEqual([left, right].count(1), 1)
                self.assertEqual([left, right].count(None), 1)
                self.assertEqual(first.read('original'),
                                 StoredBytes(1, b'left' if left == 1 else b'right'))

    def test_lost_commit_acknowledgement_is_not_automatically_repeated(self) -> None:
        class LostCommit(sqlite3.Connection):
            inserts = 0
            lose = False

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if sql.startswith('INSERT'):
                    self.inserts += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.lose:
                    self.lose = False
                    raise OSError('physical commit acknowledgement lost')
                return result

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **k, factory=LostCommit)):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    store._connection.lose = True
                    with self.assertRaises(OSError):
                        store.compare_exchange('original', None, b'original-wire')
                    self.assertEqual(store.read('original'), StoredBytes(0, b'original-wire'))
                    self.assertEqual(store._connection.inserts, 1)

    def test_failed_commit_and_rollback_cannot_expose_uncommitted_bytes(self) -> None:
        class PendingTransaction(sqlite3.Connection):
            refuse = False

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if self.refuse and sql in ('COMMIT', 'ROLLBACK'):
                    raise OSError('physical transaction cleanup refused')
                return super().execute(sql, *args, **kwargs)

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            path = Path(directory) / 'core.sqlite'
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **k, factory=PendingTransaction)):
                store = self.store(path)
            store._connection.refuse = True
            with self.assertRaises(OSError):
                store.compare_exchange('original', None, b'not-committed')
            with self.assertRaises(LocalStorageError):
                store.read('original')
            with self.assertRaises(LocalStorageError):
                store.compare_exchange('original', None, b'resend')
            store.close()
            with self.store(path) as reopened:
                self.assertIsNone(reopened.read('original'))

    def test_row_count_and_aggregate_bytes_reject_without_changing_original(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path, records=2, row=4, total=6) as store:
                self.assertEqual(store.compare_exchange('a', None, b'1234'), 0)
                self.assertEqual(store.compare_exchange('b', None, b'56'), 0)
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange('b', 0, b'789')
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange('c', None, b'')
                self.assertEqual(store.read('b'), StoredBytes(0, b'56'))
                self.assertIsNone(store.read('c'))
                with self.assertRaises(ValueError):
                    store.compare_exchange('a', 0, b'12345')
                self.assertEqual(store.compare_exchange('a', 0, b''), 1)
                self.assertEqual(store.read('a'), StoredBytes(1, b''))

    def test_oversized_retained_row_is_rejected_instead_of_returned(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path, row=4, total=6) as store:
                with sqlite3.connect(path) as physical:
                    physical.execute('INSERT INTO core_bytes VALUES (?, ?, ?)',
                                     ('corrupt', 0, b'0123456789'))
                with self.assertRaises(LocalStorageError):
                    store.read('corrupt')

    def test_foreign_format_is_refused_without_migration_or_deletion(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            path = Path(directory) / 'foreign.sqlite'
            with sqlite3.connect(path) as foreign:
                foreign.execute('CREATE TABLE original(payload BLOB)')
                foreign.execute('INSERT INTO original VALUES (?)', (b'original',))
            path.chmod(0o600)
            before = path.read_bytes()
            with self.assertRaises(LocalStorageError):
                self.store(path)
            self.assertEqual(path.read_bytes(), before)
            with sqlite3.connect(path) as foreign:
                self.assertEqual(foreign.execute('SELECT payload FROM original').fetchone(),
                                 (b'original',))

    def test_symlink_and_nonprivate_file_are_refused(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            target = Path(directory) / 'original'
            target.write_bytes(b'original')
            link = Path(directory) / 'link'
            link.symlink_to(target)
            with self.assertRaises(LocalStorageError):
                self.store(link)
            target.chmod(0o644)
            with self.assertRaises(LocalStorageError):
                self.store(target)
            self.assertEqual(target.read_bytes(), b'original')

    def test_close_failure_keeps_original_handle_for_retry(self) -> None:
        class FailingClose(sqlite3.Connection):
            calls = 0

            def close(self) -> None:
                self.calls += 1
                if self.calls == 1:
                    raise OSError('physical close refused')
                super().close()

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **k, factory=FailingClose)):
                store = self.store(Path(directory) / 'core.sqlite')
            with self.assertRaises(OSError):
                store.close()
            # Retained state is still readable; failed close did not claim release.
            self.assertIsNone(store.read('absent'))
            store.close()
            store.close()
            self.assertEqual(store._connection.calls, 2)
            with self.assertRaises(LocalStorageError):
                store.read('absent')

    def test_initialization_cleanup_failure_exposes_same_pending_handle(self) -> None:
        class FailedInitialization(sqlite3.Connection):
            calls = 0

            def execute(self, *args: object, **kwargs: object) -> sqlite3.Cursor:
                raise OSError('physical initialization refused')

            def close(self) -> None:
                self.calls += 1
                if self.calls == 1:
                    raise OSError('physical close refused')
                super().close()

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **k, factory=FailedInitialization)):
                with self.assertRaises(LocalStorageInitializationError) as pending:
                    self.store(Path(directory) / 'core.sqlite')
            store = pending.exception.cleanup_store
            with self.assertRaises(LocalStorageError):
                store.read('absent')
            store.close()
            store.close()
            self.assertEqual(store._connection.calls, 2)

    def test_opening_descriptor_failure_retains_exact_cleanup_handle(self) -> None:
        close = os.close
        descriptors: list[int] = []

        def fail_once(descriptor: int) -> None:
            descriptors.append(descriptor)
            if len(descriptors) == 1:
                raise OSError('physical descriptor close refused')
            close(descriptor)

        with TemporaryDirectory(prefix='actql-python-local-bytes-') as directory:
            with patch('actql_sdk._local_storage.os.close', side_effect=fail_once):
                with self.assertRaises(LocalStorageInitializationError) as pending:
                    self.store(Path(directory) / 'core.sqlite')
                store = pending.exception.cleanup_store
                store.close()
                store.close()
            self.assertEqual(len(descriptors), 2)
            self.assertEqual(descriptors[0], descriptors[1])
            with self.assertRaises(LocalStorageError):
                store.read('absent')
