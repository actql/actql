"""Actual SQLite metadata batches bound to every original physical payload.

Opaque physical persistence does not assert a validated or public Run outcome.
"""
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Barrier
from concurrent.futures import ThreadPoolExecutor
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    ByteFence, ByteWrite, CapacityReservation, LocalByteStore,
    LocalStorageError, StoredBytes,
)


class PublicationByteBatchTests(unittest.TestCase):
    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=256,
                              max_payload_bytes=1024)

    def originals(self, store):
        result = []
        for key, payload in [('e\u0301/~😀', b'NULL\x00/e\xcc\x81\r\n'), ('é/~😀', b'null')]:
            self.assertEqual(store.compare_exchange(key, None, payload), 0)
            self.assertTrue(store.reserve_capacity('publication_payload', key, 64, 1, 128, 2))
            result.append((ByteFence(key, 0, payload),
                           CapacityReservation('publication_payload', key, 64, 1)))
        return tuple(result)

    def writes(self):
        return (ByteWrite('binding/1', None, b'original-binding-1'),
                ByteWrite('binding/2', None, b'original-binding-2'),
                ByteWrite('index', None, b'original-index\r\n'))

    def unchanged(self, store, originals):
        for fence, capacity in originals:
            self.assertEqual(store.read(fence.key), StoredBytes(fence.generation, fence.payload))
            self.assertEqual(store.read_capacity(capacity.namespace, capacity.key), capacity)

    def test_complete_metadata_batch_keeps_exact_originals_and_survives_new_process(self):
        with TemporaryDirectory(prefix='actql-publication-batch-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                originals = self.originals(store)
                self.assertEqual(store.compare_exchange_many_attached(self.writes(), originals), (0, 0, 0))
                self.unchanged(store, originals)
            source = str(Path(__file__).resolve().parents[1] / 'src')
            script = """import json,sys
from pathlib import Path
sys.path.insert(0,sys.argv[2])
from actql_sdk._local_storage import LocalByteStore
with LocalByteStore(Path(sys.argv[1]),max_records=8,max_record_bytes=256,max_payload_bytes=1024) as store:
 print(json.dumps([(key,store.read(key).generation,store.read(key).payload.hex()) for key in ['binding/1','binding/2','index','e\\u0301/~😀','é/~😀']]))
"""
            actual = subprocess.run([sys.executable, '-c', script, str(path), source],
                                    capture_output=True, text=True, timeout=5, check=True)
            self.assertEqual(json.loads(actual.stdout), [
                ['binding/1', 0, b'original-binding-1'.hex()],
                ['binding/2', 0, b'original-binding-2'.hex()],
                ['index', 0, b'original-index\r\n'.hex()],
                ['e\u0301/~😀', 0, b'NULL\x00/e\xcc\x81\r\n'.hex()],
                ['é/~😀', 0, b'null'.hex()],
            ])

    def test_any_original_generation_bytes_or_capacity_mismatch_refuses_all_metadata(self):
        for index in (0, 1):
            for field in ('generation', 'bytes', 'capacity'):
                with self.subTest(index=index, field=field), TemporaryDirectory() as directory:
                    with self.store(Path(directory) / 'core.sqlite') as store:
                        originals = self.originals(store)
                        bad = list(originals)
                        fence, capacity = bad[index]
                        if field == 'generation':
                            bad[index] = (ByteFence(fence.key, 1, fence.payload), capacity)
                        elif field == 'bytes':
                            bad[index] = (ByteFence(fence.key, 0, b'changed'), capacity)
                        else:
                            bad[index] = (fence, CapacityReservation(capacity.namespace, capacity.key, 63, 1))
                        queries = []
                        store._connection.set_trace_callback(queries.append)
                        self.assertIsNone(store.compare_exchange_many_attached(self.writes(), tuple(bad)))
                        self.assertFalse(any(q.startswith(('INSERT', 'UPDATE', 'DELETE')) for q in queries))
                        for write in self.writes():
                            self.assertIsNone(store.read(write.key))
                        self.unchanged(store, originals)

    def test_last_metadata_conflict_never_installs_a_partial_prefix(self):
        with TemporaryDirectory() as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store.compare_exchange('index', None, b'competing')
                self.assertIsNone(store.compare_exchange_many_attached(self.writes(), originals))
                self.assertIsNone(store.read('binding/1'))
                self.assertIsNone(store.read('binding/2'))
                self.assertEqual(store.read('index'), StoredBytes(0, b'competing'))
                self.unchanged(store, originals)

    def test_second_metadata_insert_failure_rolls_back_without_retry(self):
        class FailInsert(sqlite3.Connection):
            armed = False
            writes = 0
            def execute(self, sql, *args, **kwargs):
                if self.armed and sql.startswith('INSERT INTO core_bytes'):
                    self.writes += 1
                    if self.writes == 2:
                        raise OSError('Independent second metadata failure')
                return super().execute(sql, *args, **kwargs)
        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': FailInsert}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store._connection.armed = True
                with self.assertRaisesRegex(OSError, 'second metadata failure'):
                    store.compare_exchange_many_attached(self.writes(), originals)
                self.assertEqual(store._connection.writes, 2)
                for write in self.writes():
                    self.assertIsNone(store.read(write.key))
                self.unchanged(store, originals)

    def test_lost_commit_ack_is_observed_without_repeating_batch_or_advancing_payload(self):
        class LostAck(sqlite3.Connection):
            armed = False
            writes = 0
            def execute(self, sql, *args, **kwargs):
                if self.armed and sql.startswith('INSERT INTO core_bytes'):
                    self.writes += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.armed:
                    self.armed = False
                    raise OSError('Independent metadata commit ACK lost')
                return result
        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': LostAck}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store._connection.armed = True
                with self.assertRaisesRegex(OSError, 'ACK lost'):
                    store.compare_exchange_many_attached(self.writes(), originals)
                self.assertEqual(store._connection.writes, 3)
                for write in self.writes():
                    self.assertEqual(store.read_exchange(write), StoredBytes(0, write.payload))
                self.assertEqual(store._connection.writes, 3)
                self.unchanged(store, originals)

    def test_competing_metadata_batches_have_one_complete_winner(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as left, self.store(path) as right:
                originals = self.originals(left)
                barrier = Barrier(2)
                def install(store, marker):
                    barrier.wait(timeout=5)
                    writes = tuple(ByteWrite(write.key, None, marker + write.payload) for write in self.writes())
                    return store.compare_exchange_many_attached(writes, originals)
                with ThreadPoolExecutor(max_workers=2) as pool:
                    a = pool.submit(install, left, b'L')
                    b = pool.submit(install, right, b'R')
                    results = [a.result(timeout=5), b.result(timeout=5)]
                self.assertEqual(results.count((0, 0, 0)), 1)
                self.assertEqual(results.count(None), 1)
                marker = b'L' if results[0] is not None else b'R'
                for write in self.writes():
                    self.assertEqual(left.read(write.key), StoredBytes(0, marker + write.payload))
                self.unchanged(left, originals)

    def test_invalid_empty_duplicate_original_and_payload_replacement_refuse_before_transaction(self):
        with TemporaryDirectory() as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                fence, capacity = originals[0]
                queries = []
                store._connection.set_trace_callback(queries.append)
                bad = [(), (originals[0], originals[0]),
                       ((fence, CapacityReservation(capacity.namespace, 'other', 64, 1)),),
                       ((ByteFence(fence.key, True, fence.payload), capacity),),
                       ((fence, CapacityReservation(capacity.namespace, fence.key, True, 1)),)]
                for original in bad:
                    with self.assertRaises(ValueError):
                        store.compare_exchange_many_attached(self.writes(), original)
                with self.assertRaises(ValueError):
                    store.compare_exchange_many_attached((ByteWrite(fence.key, 0, b'replaced'),), originals)
                self.assertFalse(any(q.startswith('BEGIN') for q in queries))
                self.unchanged(store, originals)

    def test_metadata_capacity_refusal_preserves_all_originals_and_reservations(self):
        with TemporaryDirectory() as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store._max_payload_bytes = 20
                with self.assertRaisesRegex(LocalStorageError, 'capacity exceeded'):
                    store.compare_exchange_many_attached(self.writes(), originals)
                for write in self.writes():
                    self.assertIsNone(store.read(write.key))
                self.unchanged(store, originals)

    def test_original_capacity_is_rechecked_inside_the_write_transaction(self):
        class ChangeAfterBegin(sqlite3.Connection):
            armed = False
            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if sql == 'BEGIN IMMEDIATE' and self.armed:
                    self.armed = False
                    super().execute('UPDATE actql_capacity SET reserved_bytes=63 WHERE reservation_key=?', ('é/~😀',))
                return result
        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': ChangeAfterBegin}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store._connection.armed = True
                self.assertIsNone(store.compare_exchange_many_attached(self.writes(), originals))
                for write in self.writes():
                    self.assertIsNone(store.read(write.key))
                self.unchanged(store, originals)


if __name__ == '__main__':
    unittest.main()
