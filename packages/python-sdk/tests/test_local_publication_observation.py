"""Actual original-batch observations; no Run state, absence or retry decision."""
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Event, Thread
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    ByteFence, ByteWrite, CapacityReservation, LocalByteStore, LocalStorageError, StoredBytes,
)
import test_local_storage_publication_batch as batch


class OriginalBatchObservationTests(unittest.TestCase):
    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=256, max_payload_bytes=1024)

    def originals(self, store):
        return batch.PublicationByteBatchTests().originals(store)

    def writes(self):
        return batch.PublicationByteBatchTests().writes()

    def expected(self):
        return tuple(StoredBytes(0, write.payload) for write in self.writes())

    def test_exact_batch_and_originals_are_read_after_actual_process_restart(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                originals = self.originals(store)
                self.assertEqual(store.compare_exchange_many_attached(self.writes(), originals), (0, 0, 0))
            source = str(Path(__file__).resolve().parents[1] / 'src')
            script = """import json,sys
from pathlib import Path
sys.path.insert(0,sys.argv[2])
from actql_sdk._local_storage import ByteFence,ByteWrite,CapacityReservation,LocalByteStore
writes=(ByteWrite('binding/1',None,b'original-binding-1'),ByteWrite('binding/2',None,b'original-binding-2'),ByteWrite('index',None,b'original-index\\r\\n'))
originals=tuple((ByteFence(k,0,p),CapacityReservation('publication_payload',k,64,1)) for k,p in [('e\\u0301/~😀',b'NULL\\x00/e\\xcc\\x81\\r\\n'),('é/~😀',b'null')])
with LocalByteStore(Path(sys.argv[1]),max_records=8,max_record_bytes=256,max_payload_bytes=1024) as store:
 observed=store.read_exchange_many_attached(writes,originals)
 assert observed is not None
 print(json.dumps([(row.generation,row.payload.hex()) for row in observed]))
"""
            result = subprocess.run([sys.executable, '-c', script, str(path), source],
                                    capture_output=True, text=True, timeout=5, check=True)
            self.assertEqual(json.loads(result.stdout), [[r.generation, r.payload.hex()] for r in self.expected()])

    def test_missing_changed_or_later_metadata_returns_no_partial_observation_or_write(self):
        for kind in ('missing', 'changed', 'later'):
            with self.subTest(kind=kind), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.originals(store)
                    writes = self.writes()
                    self.assertEqual(store.compare_exchange_many_attached(writes, originals), (0, 0, 0))
                    if kind == 'missing':
                        store._connection.execute('DELETE FROM core_bytes WHERE key=?', ('index',))
                    elif kind == 'changed':
                        store._connection.execute('UPDATE core_bytes SET payload=? WHERE key=?', (b'other', 'index'))
                    else:
                        self.assertEqual(store.compare_exchange('index', 0, writes[-1].payload), 1)
                    queries = []
                    store._connection.set_trace_callback(queries.append)
                    self.assertIsNone(store.read_exchange_many_attached(writes, originals))
                    self.assertFalse(any(q.startswith(('INSERT', 'UPDATE', 'DELETE')) for q in queries))
                    self.assertFalse(store._connection.in_transaction)

    def test_original_bytes_generation_or_reservation_change_invalidates_entire_observation(self):
        for position in (0, 1):
            for field in ('generation', 'bytes', 'capacity'):
                with self.subTest(position=position, field=field), TemporaryDirectory() as directory:
                    with self.store(Path(directory) / 'core.sqlite') as store:
                        originals = self.originals(store)
                        store.compare_exchange_many_attached(self.writes(), originals)
                        fence, capacity = originals[position]
                        if field == 'capacity':
                            store._connection.execute('UPDATE actql_capacity SET reserved_bytes=63 WHERE reservation_key=?', (fence.key,))
                        elif field == 'bytes':
                            store._connection.execute('UPDATE core_bytes SET payload=? WHERE key=?', (b'changed', fence.key))
                        else:
                            store._connection.execute('UPDATE core_bytes SET generation=1 WHERE key=?', (fence.key,))
                        self.assertIsNone(store.read_exchange_many_attached(self.writes(), originals))

    def test_atomic_writer_cannot_split_the_read_snapshot_between_metadata_records(self):
        started, updated = Event(), Event()
        class PauseAfterFirst(sqlite3.Connection):
            armed = False
            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if self.armed and 'typeof(payload)' in sql and args[0][-1] == 'binding/1':
                    self.armed = False
                    started.set()
                    assert updated.wait(timeout=3), 'Writer did not reach original pending COMMIT'
                return result
        class ObserveUpdate(sqlite3.Connection):
            armed = False
            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if self.armed and sql.startswith('UPDATE core_bytes') and args[0][-1] == 'index':
                    updated.set()
                return result
        physical = sqlite3.connect
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with patch('actql_sdk._local_storage.sqlite3.connect', side_effect=lambda *a, **k: physical(*a, **(k | {'factory': PauseAfterFirst}))):
                reader = self.store(path)
            with patch('actql_sdk._local_storage.sqlite3.connect', side_effect=lambda *a, **k: physical(*a, **(k | {'factory': ObserveUpdate}))):
                writer = self.store(path)
            with reader, writer:
                originals = self.originals(reader)
                reader.compare_exchange_many_attached(self.writes(), originals)
                errors = []
                results = []
                def change():
                    try:
                        assert started.wait(timeout=3)
                        writer._connection.armed = True
                        writes = tuple(ByteWrite(w.key, 0, b'next-' + w.payload) for w in self.writes())
                        results.append(writer.compare_exchange_many_attached(writes, originals))
                    except BaseException as error:
                        errors.append(error)
                thread = Thread(target=change)
                thread.start()
                try:
                    reader._connection.armed = True
                    self.assertEqual(reader.read_exchange_many_attached(self.writes(), originals), self.expected())
                finally:
                    thread.join(timeout=5)
                self.assertFalse(thread.is_alive())
                self.assertEqual(errors, [])
                self.assertEqual(results, [(1, 1, 1)])
                self.assertIsNone(reader.read_exchange_many_attached(self.writes(), originals))

    def test_lost_commit_ack_requires_only_read_observation_without_a_second_batch(self):
        class LostAck(sqlite3.Connection):
            armed = False
            writes = 0
            def execute(self, sql, *args, **kwargs):
                if self.armed and sql.startswith('INSERT INTO core_bytes'):
                    self.writes += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.armed:
                    self.armed = False
                    raise OSError('Original batch ACK lost')
                return result
        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': LostAck}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store._connection.armed = True
                with self.assertRaisesRegex(OSError, 'ACK lost'):
                    store.compare_exchange_many_attached(self.writes(), originals)
                self.assertEqual(store.read_exchange_many_attached(self.writes(), originals), self.expected())
                self.assertEqual(store.read_exchange_many_attached(self.writes(), originals), self.expected())
                self.assertEqual(store._connection.writes, 3)

    def test_transaction_end_failure_exposes_no_observation_and_retains_pending_handle(self):
        class FailEnd(sqlite3.Connection):
            armed = False
            def execute(self, sql, *args, **kwargs):
                if sql == 'ROLLBACK' and self.armed:
                    self.armed = False
                    raise OSError('Original read transaction stop failed')
                return super().execute(sql, *args, **kwargs)
        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': FailEnd}))):
            store = self.store(Path(directory) / 'core.sqlite')
            try:
                originals = self.originals(store)
                store.compare_exchange_many_attached(self.writes(), originals)
                original = store._connection
                original.armed = True
                with self.assertRaisesRegex(OSError, 'stop failed'):
                    store.read_exchange_many_attached(self.writes(), originals)
                self.assertIs(store._connection, original)
                self.assertTrue(original.in_transaction)
                with self.assertRaisesRegex(LocalStorageError, 'cleanup is pending'):
                    store.read_exchange_many_attached(self.writes(), originals)
            finally:
                store.close()

    def test_corrupt_oversized_metadata_is_a_bounded_error_not_missing_or_success(self):
        with TemporaryDirectory() as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store.compare_exchange_many_attached(self.writes(), originals)
                store._connection.execute('UPDATE core_bytes SET payload=? WHERE key=?', (b'x' * 257, 'index'))
                with self.assertRaisesRegex(LocalStorageError, 'Invalid retained'):
                    store.read_exchange_many_attached(self.writes(), originals)
                self.assertFalse(store._connection.in_transaction)

    def test_invalid_batch_fences_and_controls_refuse_before_physical_read(self):
        with TemporaryDirectory() as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                queries = []
                store._connection.set_trace_callback(queries.append)
                fence, capacity = originals[0]
                for writes, origin in [
                    ((), originals), (self.writes(), ()),
                    (self.writes(), (originals[0], originals[0])),
                    (self.writes(), ((ByteFence(fence.key, True, fence.payload), capacity),)),
                    ((ByteWrite(fence.key, 0, fence.payload),), originals),
                    ((ByteWrite('index', True, b'null'),), originals),
                ]:
                    with self.assertRaises(ValueError):
                        store.read_exchange_many_attached(writes, origin)
                self.assertEqual(queries, [])

    def test_read_failure_keeps_same_store_and_read_retry_never_repeats_a_write(self):
        class FailRead(sqlite3.Connection):
            armed = False
            def execute(self, sql, *args, **kwargs):
                if self.armed and 'typeof(payload)' in sql and args[0][-1] == 'index':
                    self.armed = False
                    raise OSError('Original metadata observation failed')
                return super().execute(sql, *args, **kwargs)
        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': FailRead}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store.compare_exchange_many_attached(self.writes(), originals)
                original = store._connection
                original.armed = True
                queries = []
                original.set_trace_callback(queries.append)
                with self.assertRaisesRegex(OSError, 'observation failed'):
                    store.read_exchange_many_attached(self.writes(), originals)
                self.assertIs(store._connection, original)
                self.assertFalse(original.in_transaction)
                self.assertEqual(store.read_exchange_many_attached(self.writes(), originals), self.expected())
                self.assertFalse(any(q.startswith(('INSERT', 'UPDATE', 'DELETE')) for q in queries))


if __name__ == '__main__':
    unittest.main()
