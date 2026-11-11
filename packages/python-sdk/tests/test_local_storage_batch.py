"""Independent physical atomicity fixtures, not Run recovery evidence."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sqlite3
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Barrier
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import ByteWrite, LocalByteStore, LocalStorageError, StoredBytes


class AtomicByteBatchTests(unittest.TestCase):
    def store(self, path: Path, *, records: int = 4, total: int = 256) -> LocalByteStore:
        return LocalByteStore(path, max_records=records, max_record_bytes=128,
                              max_payload_bytes=total)

    def test_late_conflict_changes_no_earlier_record(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-batch-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                store.compare_exchange('original', None, b'old')
                store.compare_exchange('index', None, b'index-old')
                self.assertIsNone(store.compare_exchange_many((
                    ByteWrite('original', 0, b'changed'),
                    ByteWrite('new', None, b'new'),
                    ByteWrite('index', None, b'stale-index'),
                )))
                self.assertEqual(store.read('original'), StoredBytes(0, b'old'))
                self.assertIsNone(store.read('new'))
                self.assertEqual(store.read('index'), StoredBytes(0, b'index-old'))

    def test_capacity_counts_all_writes_and_replacements_before_installation(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-batch-') as directory:
            with self.store(Path(directory) / 'core.sqlite', records=2, total=128) as store:
                store.compare_exchange('a', None, b'a' * 120)
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange_many((ByteWrite('a', 0, b'a' * 120),
                                                 ByteWrite('b', None, b'b' * 9)))
                self.assertEqual(store.read('a'), StoredBytes(0, b'a' * 120))
                self.assertIsNone(store.read('b'))
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite('a', 0, b'a'), ByteWrite('b', None, b'b' * 127))), (1, 0))
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange_many((ByteWrite('a', 1, b''),
                                                 ByteWrite('c', None, b'')))
                self.assertEqual(store.read('a'), StoredBytes(1, b'a'))
                self.assertIsNone(store.read('c'))

    def test_later_write_exception_rolls_back_all_prior_writes(self) -> None:
        class RefuseSecondInsert(sqlite3.Connection):
            refuse = False
            inserts = 0

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if self.refuse and sql.startswith('INSERT'):
                    self.inserts += 1
                    if self.inserts == 2:
                        raise OSError('independent second physical insert failure')
                return super().execute(sql, *args, **kwargs)

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-local-batch-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': RefuseSecondInsert}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    store.compare_exchange('original', None, b'old')
                    store._connection.refuse = True
                    with self.assertRaises(OSError):
                        store.compare_exchange_many((ByteWrite('original', 0, b'changed'),
                                                     ByteWrite('first', None, b'first'),
                                                     ByteWrite('second', None, b'second')))
                    self.assertEqual(store.read('original'), StoredBytes(0, b'old'))
                    self.assertIsNone(store.read('first'))
                    self.assertIsNone(store.read('second'))
                    self.assertEqual(store._connection.inserts, 2)

    def test_competing_batches_have_one_winner_without_mixed_materials(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-batch-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as first, self.store(path) as second:
                first.compare_exchange('index', None, b'initial')
                barrier = Barrier(2)

                def claim(store: LocalByteStore, marker: bytes) -> tuple[int, ...] | None:
                    barrier.wait(timeout=5)
                    return store.compare_exchange_many((
                        ByteWrite('material', None, marker + b'-material'),
                        ByteWrite('index', 0, marker + b'-index'),
                    ))

                with ThreadPoolExecutor(max_workers=2) as pool:
                    a = pool.submit(claim, first, b'left')
                    b = pool.submit(claim, second, b'right')
                    left, right = a.result(timeout=5), b.result(timeout=5)
                self.assertEqual([left, right].count((0, 1)), 1)
                self.assertEqual([left, right].count(None), 1)
                winner = b'left' if left is not None else b'right'
                self.assertEqual(first.read('material'), StoredBytes(0, winner + b'-material'))
                self.assertEqual(first.read('index'), StoredBytes(1, winner + b'-index'))

    def test_lost_commit_acknowledgement_does_not_repeat_any_write(self) -> None:
        class LostCommit(sqlite3.Connection):
            lose = False
            inserts = 0

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if sql.startswith('INSERT'):
                    self.inserts += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.lose:
                    self.lose = False
                    raise OSError('independent physical commit acknowledgement loss')
                return result

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-local-batch-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostCommit}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    store._connection.lose = True
                    with self.assertRaises(OSError):
                        store.compare_exchange_many((ByteWrite('material', None, b'raw-material'),
                                                     ByteWrite('index', None, b'raw-index')))
                    self.assertEqual(store.read('material'), StoredBytes(0, b'raw-material'))
                    self.assertEqual(store.read('index'), StoredBytes(0, b'raw-index'))
                    self.assertEqual(store._connection.inserts, 2)

    def test_invalid_batch_is_refused_before_opening_a_transaction(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-batch-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                with patch.object(store, '_open', side_effect=AssertionError('Unexpected storage I/O')):
                    for writes in ((), (ByteWrite('same', None, b'a'), ByteWrite('same', None, b'b')),
                                   (ByteWrite('x', True, b'a'),), (ByteWrite('x', None, b'a' * 129),),
                                   tuple(ByteWrite(str(i), None, b'') for i in range(5))):
                        with self.assertRaises(ValueError):
                            store.compare_exchange_many(writes)
                self.assertIsNone(store.read('same'))

    def test_exact_batch_survives_actual_process_exit(self) -> None:
        with TemporaryDirectory(prefix='actql-python-local-batch-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path):
                pass
            source = str(Path(__file__).resolve().parents[1] / 'src')
            child = '''import sys
sys.path.insert(0, sys.argv[1])
from pathlib import Path
from actql_sdk._local_storage import ByteWrite, LocalByteStore
with LocalByteStore(Path(sys.argv[2]), max_records=4, max_record_bytes=128, max_payload_bytes=256) as store:
    assert store.compare_exchange_many((ByteWrite('e\\u0301/~', None, b'{"n":1.250,"nullable":null}'),
                                       ByteWrite('é/~', None, b'line\\r\\nend'),
                                       ByteWrite('empty', None, b''))) == (0, 0, 0)
'''
            result = subprocess.run([sys.executable, '-I', '-c', child, source, str(path)],
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            with self.store(path) as store:
                self.assertEqual(store.read('e\u0301/~'), StoredBytes(0, b'{"n":1.250,"nullable":null}'))
                self.assertEqual(store.read('é/~'), StoredBytes(0, b'line\r\nend'))
                self.assertEqual(store.read('empty'), StoredBytes(0, b''))
                self.assertIsNone(store.read('absent'))
