"""Independent Native reservation vectors through the actual Python SQLite port."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sqlite3
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Barrier
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    CapacityReservation, CapacityUsage, LocalByteStore, LocalStorageError, StoredBytes,
)


class PhysicalCapacityTests(unittest.TestCase):
    def store(self, path: Path, *, records: int = 4) -> LocalByteStore:
        return LocalByteStore(path, max_records=records, max_record_bytes=128,
                              max_payload_bytes=256)

    def test_native_vector_exact_identity_survives_close_and_fresh_process(self) -> None:
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                self.assertTrue(store.reserve_capacity('publication', 'one', 600, 1, 1024, 2))
                self.assertFalse(store.reserve_capacity('publication', 'one', 600, 1, 1024, 2))
                with self.assertRaises(LocalStorageError):
                    store.reserve_capacity('publication', 'one', 601, 1, 1024, 2)
                with self.assertRaises(LocalStorageError):
                    store.reserve_capacity('publication', 'two', 600, 1, 1024, 2)
                self.assertEqual(store.capacity_usage('publication'), CapacityUsage(600, 1))
                self.assertIsNone(store.read_capacity('other', 'one'))
                self.assertIsNone(store.read_capacity('publication', 'other'))
            result = subprocess.run([sys.executable, '-c', '''
from pathlib import Path
import sys
sys.path.insert(0, sys.argv[2])
from actql_sdk._local_storage import LocalByteStore, CapacityReservation, CapacityUsage
with LocalByteStore(Path(sys.argv[1]), max_records=4, max_record_bytes=128, max_payload_bytes=256) as store:
    assert store.read_capacity('publication', 'one') == CapacityReservation('publication', 'one', 600, 1)
    assert store.capacity_usage('publication') == CapacityUsage(600, 1)
    assert not store.claim_creation()
print('original reservation retained')
''', str(path), str(Path(__file__).resolve().parents[1] / 'src')],
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'original reservation retained')

    def test_competing_handles_cannot_overbook(self) -> None:
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as first, self.store(path) as second:
                barrier = Barrier(2)

                def reserve(store: LocalByteStore, key: str) -> bool:
                    barrier.wait(timeout=5)
                    try:
                        return store.reserve_capacity('publication', key, 600, 1, 1024, 2)
                    except LocalStorageError:
                        return False

                with ThreadPoolExecutor(max_workers=2) as pool:
                    a = pool.submit(reserve, first, 'one')
                    b = pool.submit(reserve, second, 'two')
                    self.assertEqual([a.result(timeout=5), b.result(timeout=5)].count(True), 1)
                self.assertEqual(first.capacity_usage('publication'), CapacityUsage(600, 1))

    def test_unicode_names_and_exact_release_do_not_normalize_or_infer_cleanup(self) -> None:
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.assertTrue(store.reserve_capacity('publication', 'e\u0301', 8, 1, 64, 4))
                self.assertTrue(store.reserve_capacity('publication', '\u00e9', 9, 1, 64, 4))
                self.assertEqual(store.read_capacity('publication', 'e\u0301'),
                                 CapacityReservation('publication', 'e\u0301', 8, 1))
                with self.assertRaises(LocalStorageError):
                    store.release_capacity('publication', 'e\u0301', 9, 1)
                self.assertEqual(store.capacity_usage('publication'), CapacityUsage(17, 2))
                self.assertFalse(store.release_capacity('foreign', 'e\u0301', 8, 1))
                self.assertTrue(store.release_capacity('publication', 'e\u0301', 8, 1))
                self.assertFalse(store.release_capacity('publication', 'e\u0301', 8, 1))
                self.assertEqual(store.capacity_usage('publication'), CapacityUsage(9, 1))

    def test_lost_commit_ack_uses_read_only_observation_without_second_insert(self) -> None:
        class LostCommit(sqlite3.Connection):
            lose = False
            inserts = 0

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if sql.startswith('INSERT INTO actql_capacity'):
                    self.inserts += 1
                cursor = super().execute(sql, *args, **kwargs)
                if self.lose and sql == 'COMMIT':
                    self.lose = False
                    raise OSError('independent lost reservation acknowledgement')
                return cursor

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostCommit}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    store._connection.lose = True
                    with self.assertRaises(OSError):
                        store.reserve_capacity('publication', 'original', 8, 1, 64, 4)
                    expected = CapacityReservation('publication', 'original', 8, 1)
                    self.assertEqual(store.read_capacity('publication', 'original'), expected)
                    self.assertEqual(store.read_capacity('publication', 'original'), expected)
                    self.assertEqual(store._connection.inserts, 1)

    def test_failed_release_keeps_same_reservation_for_exact_retry(self) -> None:
        class RefuseRelease(sqlite3.Connection):
            refuse = False

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if self.refuse and sql.startswith('DELETE FROM actql_capacity'):
                    raise OSError('independent reservation release failure')
                return super().execute(sql, *args, **kwargs)

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': RefuseRelease}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    store.reserve_capacity('publication', 'original', 8, 1, 64, 4)
                    store._connection.refuse = True
                    with self.assertRaises(OSError):
                        store.release_capacity('publication', 'original', 8, 1)
                    self.assertEqual(store.capacity_usage('publication'), CapacityUsage(8, 1))
                    store._connection.refuse = False
                    self.assertTrue(store.release_capacity('publication', 'original', 8, 1))
                    self.assertEqual(store.capacity_usage('publication'), CapacityUsage(0, 0))

    def test_invalid_requests_perform_no_sql_and_zero_amount_rows_remain_bounded(self) -> None:
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            with self.store(Path(directory) / 'core.sqlite', records=2) as store:
                queries: list[str] = []
                store._connection.set_trace_callback(queries.append)
                for args in (('', 'one', 1, 1, 64, 2), ('p', None, 1, 1, 64, 2),
                             ('p', 'one', True, 1, 64, 2), ('p', 'one', -1, 1, 64, 2),
                             ('p', 'one', 2**63, 1, 2**63, 2), ('p' * 513, 'one', 1, 1, 64, 2)):
                    with self.assertRaises(ValueError):
                        store.reserve_capacity(*args)
                self.assertEqual(queries, [])
                self.assertTrue(store.reserve_capacity('p', 'one', 0, 0, 0, 0))
                self.assertTrue(store.reserve_capacity('q', 'two', 0, 0, 0, 0))
                with self.assertRaises(LocalStorageError):
                    store.reserve_capacity('r', 'three', 0, 0, 0, 0)
                self.assertIsNone(store.read_capacity('r', 'three'))
                self.assertFalse(store.claim_creation())

    def test_rollback_failure_retains_unreadable_pending_connection(self) -> None:
        class RefuseCommitRollback(sqlite3.Connection):
            refuse = False

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if self.refuse and sql in ('COMMIT', 'ROLLBACK'):
                    raise OSError('independent transaction cleanup failure')
                return super().execute(sql, *args, **kwargs)

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': RefuseCommitRollback}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    store._connection.refuse = True
                    with self.assertRaises(OSError):
                        store.reserve_capacity('publication', 'original', 8, 1, 64, 4)
                    with self.assertRaises(LocalStorageError):
                        store.read_capacity('publication', 'original')
                    with self.assertRaises(LocalStorageError):
                        store.capacity_usage('publication')
                    with self.assertRaises(LocalStorageError):
                        store.release_capacity('publication', 'original', 8, 1)
                with self.store(Path(directory) / 'core.sqlite') as reopened:
                    self.assertIsNone(reopened.read_capacity('publication', 'original'))

    def test_prior_format_is_refused_without_rewriting_original_bytes(self) -> None:
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                store.compare_exchange('original', None, b'original Core bytes')
            connection = sqlite3.connect(path)
            connection.execute('DROP TABLE actql_capacity')
            connection.execute('PRAGMA user_version = 1')
            connection.commit()
            connection.close()
            original = path.read_bytes()
            with self.assertRaises(LocalStorageError):
                self.store(path)
            self.assertEqual(path.read_bytes(), original)
            connection = sqlite3.connect(path)
            self.assertEqual(connection.execute('PRAGMA user_version').fetchone()[0], 1)
            self.assertEqual(connection.execute('SELECT payload FROM core_bytes').fetchone()[0], b'original Core bytes')
            connection.close()
