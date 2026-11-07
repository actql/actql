"""Actual SQLite projection/cleanup fences, not public Core/publisher acceptance."""
import asyncio
from concurrent.futures import ThreadPoolExecutor
import gc
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
import weakref

from actql_sdk._local_storage import (
    ByteFence, ByteWrite, CapacityReservation, LocalByteStore,
    LocalStorageError, StoredBytes,
)


class ProjectedAttachmentTests(unittest.TestCase):
    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=256,
                              max_payload_bytes=1024)

    def originals(self, store):
        values = []
        for key, raw in [('e\u0301/~😀', b'NULL\x00\r\n'), ('é/~😀', b'null')]:
            self.assertEqual(store.compare_exchange(key, None, raw), 0)
            self.assertTrue(store.reserve_capacity('publication_payload', key, 64, 1, 128, 2))
            values.append((ByteFence(key, 0, raw),
                           CapacityReservation('publication_payload', key, 64, 1)))
        return tuple(values)

    def write(self, ordinal):
        # These physical byte expectations are independent of Core output.
        values = [('contract/e\u0301', b'original-e\xcc\x81\r\n'),
                  ('contract/é', b'original-\xc3\xa9/null'), ('index', b'original-index')]
        key, raw = values[ordinal]
        return ByteWrite(key, None, raw)

    def unchanged(self, store, originals):
        for fence, reservation in originals:
            self.assertEqual(store.read(fence.key), StoredBytes(fence.generation, fence.payload))
            self.assertEqual(store.read_capacity(reservation.namespace, reservation.key), reservation)

    def absent(self, store):
        for i in range(3):
            self.assertIsNone(store.read(self.write(i).key))

    def test_one_live_projection_is_consumed_before_cleanup_and_final_current_check(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.originals(store)
            events, references = [], []

            def project(ordinal, consume):
                self.assertTrue(all(ref() is None for ref in references))
                events.append(('produce', ordinal))
                write = self.write(ordinal)
                references.append(weakref.ref(write))
                consume(write)
                events.append(('consumed', ordinal))
                del write
                gc.collect()
                self.assertIsNone(references[-1]())
                events.append(('cleanup', ordinal))

            def current():
                self.assertTrue(all(ref() is None for ref in references))
                events.append(('current',))

            self.assertEqual(store.compare_exchange_projected_attached(
                3, project, originals, before_commit=current), (0, 0, 0))
            self.assertEqual(events, [(event, i) for i in range(3)
                                     for event in ('produce', 'consumed', 'cleanup')] + [('current',)])
            for i in range(3):
                write = self.write(i)
                self.assertEqual(store.read(write.key), StoredBytes(0, write.payload))
            self.unchanged(store, originals)

    def test_original_generation_bytes_capacity_fences_refuse_before_any_projection(self):
        for kind in ('generation', 'bytes', 'capacity'):
            with self.subTest(kind=kind), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.originals(store)
                    fence, capacity = originals[-1]
                    bad = originals[:-1] + ((
                        ByteFence(fence.key, 1 if kind == 'generation' else 0,
                                  b'changed' if kind == 'bytes' else fence.payload),
                        CapacityReservation(capacity.namespace, capacity.key,
                                            63 if kind == 'capacity' else 64, 1)),)
                    calls = []
                    self.assertIsNone(store.compare_exchange_projected_attached(
                        3, lambda *args: calls.append(args), bad,
                        before_commit=lambda: calls.append('current')))
                    self.assertEqual(calls, [])
                    self.absent(store)
                    self.unchanged(store, originals)

    def test_last_conflict_rolls_back_consumed_prefix_without_retry_or_current_check(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.originals(store)
            store.compare_exchange('index', None, b'competing')
            calls = []

            def project(ordinal, consume):
                calls.append(ordinal)
                consume(self.write(ordinal))

            self.assertIsNone(store.compare_exchange_projected_attached(
                3, project, originals, before_commit=lambda: self.fail('Unexpected current check')))
            self.assertEqual(calls, [0, 1, 2])
            self.assertIsNone(store.read(self.write(0).key))
            self.assertIsNone(store.read(self.write(1).key))
            self.assertEqual(store.read('index'), StoredBytes(0, b'competing'))
            self.unchanged(store, originals)

    def test_projection_cleanup_failure_and_coroutine_cancel_roll_back_without_advancement(self):
        for error in (OSError('Original projection cleanup pending'), asyncio.CancelledError()):
            with self.subTest(error=type(error)), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.originals(store)
                    calls = []
                    def project(ordinal, consume):
                        calls.append(ordinal)
                        consume(self.write(ordinal))
                        raise error

                    with self.assertRaises(type(error)):
                        store.compare_exchange_projected_attached(
                            3, project, originals,
                            before_commit=lambda: self.fail('Cleanup was incomplete'))
                    self.assertEqual(calls, [0])
                    self.absent(store)
                    self.unchanged(store, originals)

    def test_current_port_refusal_unknown_and_bool_never_commit(self):
        for outcome in (PermissionError('Current authority denied'),
                        OSError('Current authority unknown'), False, True):
            with self.subTest(outcome=repr(outcome)), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.originals(store)
                    calls = []

                    def project(ordinal, consume):
                        calls.append(ordinal)
                        consume(self.write(ordinal))

                    def current():
                        calls.append('current')
                        if isinstance(outcome, BaseException):
                            raise outcome
                        return outcome

                    with self.assertRaises(type(outcome) if isinstance(outcome, BaseException) else ValueError):
                        store.compare_exchange_projected_attached(3, project, originals,
                                                                  before_commit=current)
                    self.assertEqual(calls, [0, 1, 2, 'current'])
                    self.absent(store)
                    self.unchanged(store, originals)

    def test_capacity_and_record_count_refusals_keep_original_reservations(self):
        for limit in ('bytes', 'records'):
            with self.subTest(limit=limit), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.originals(store)
                    if limit == 'bytes':
                        store._max_payload_bytes = 40
                    else:
                        store._max_records = 3
                    calls = []

                    def project(ordinal, consume):
                        calls.append(ordinal)
                        consume(self.write(ordinal))

                    with self.assertRaisesRegex(LocalStorageError, 'capacity exceeded'):
                        store.compare_exchange_projected_attached(
                            3, project, originals, before_commit=lambda: self.fail('Capacity refused'))
                    self.assertEqual(calls, [0, 1])
                    self.absent(store)
                    self.unchanged(store, originals)

    def test_missing_duplicate_and_swallowed_consumer_failure_cannot_promote_success(self):
        for mode in ('missing', 'double', 'swallowed_invalid', 'returned_bool'):
            with self.subTest(mode=mode), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.originals(store)

                    def project(ordinal, consume):
                        if mode == 'missing':
                            return
                        consume(self.write(ordinal))
                        if mode in ('double', 'swallowed_invalid'):
                            try:
                                consume(self.write(ordinal) if mode == 'double' else None)
                            except ValueError:
                                pass
                        if mode == 'returned_bool':
                            return True

                    with self.assertRaises(ValueError):
                        store.compare_exchange_projected_attached(
                            3, project, originals, before_commit=lambda: self.fail('Incomplete projection'))
                    self.absent(store)
                    self.unchanged(store, originals)

    def test_foreign_thread_delivery_is_rejected_even_if_producer_swallows_error(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.originals(store)

            def project(ordinal, consume):
                with ThreadPoolExecutor(max_workers=1) as pool:
                    with self.assertRaises(ValueError):
                        pool.submit(consume, self.write(ordinal)).result(timeout=5)

            with self.assertRaises(ValueError):
                store.compare_exchange_projected_attached(
                    3, project, originals, before_commit=lambda: self.fail('Foreign thread'))
            self.absent(store)
            self.unchanged(store, originals)

    def test_retained_consumer_cannot_reactivate_for_another_ordinal_or_after_commit(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.originals(store)
            consumers = []

            def project(ordinal, consume):
                if consumers:
                    with self.assertRaises(ValueError):
                        consumers[-1](ByteWrite('late', None, b'late'))
                consume(self.write(ordinal))
                consumers.append(consume)

            self.assertEqual(store.compare_exchange_projected_attached(
                3, project, originals, before_commit=lambda: None), (0, 0, 0))
            for consume in consumers:
                with self.assertRaises(ValueError):
                    consume(ByteWrite('late', None, b'late'))
            self.assertIsNone(store.read('late'))
            self.unchanged(store, originals)

    def test_precommit_change_of_original_capacity_is_rechecked_and_rolled_back(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.originals(store)

            def current():
                store._connection.execute('UPDATE actql_capacity SET reserved_bytes=63 WHERE reservation_key=?',
                                          ('é/~😀',))

            self.assertIsNone(store.compare_exchange_projected_attached(
                3, lambda i, consume: consume(self.write(i)), originals, before_commit=current))
            self.absent(store)
            self.unchanged(store, originals)

    def test_duplicate_or_original_key_and_invalid_count_refuse_without_overwriting_payload(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.originals(store)
            queries = []
            store._connection.set_trace_callback(queries.append)
            for count in (0, True, -1, 9):
                with self.assertRaises(ValueError):
                    store.compare_exchange_projected_attached(
                        count, lambda *args: self.fail('Invalid count'), originals,
                        before_commit=lambda: None)
            self.assertFalse(any(q.startswith('BEGIN') for q in queries))
            for key in ('same', originals[0][0].key):
                with self.assertRaises(ValueError):
                    store.compare_exchange_projected_attached(
                        2, lambda i, consume: consume(ByteWrite(key, None, b'changed')),
                        originals, before_commit=lambda: self.fail('Duplicate/original key'))
                self.assertIsNone(store.read('same'))
                self.unchanged(store, originals)

    def test_second_insert_failure_rolls_back_and_is_not_replayed(self):
        class FailWrite(sqlite3.Connection):
            armed = False
            writes = 0

            def execute(self, sql, *args, **kwargs):
                if self.armed and sql.startswith('INSERT INTO core_bytes'):
                    self.writes += 1
                    if self.writes == 2:
                        raise OSError('Independent projected write failure')
                return super().execute(sql, *args, **kwargs)

        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': FailWrite}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                store._connection.armed = True
                with self.assertRaisesRegex(OSError, 'projected write failure'):
                    store.compare_exchange_projected_attached(
                        3, lambda i, consume: consume(self.write(i)), originals,
                        before_commit=lambda: self.fail('Write failed'))
                self.assertEqual(store._connection.writes, 2)
                self.absent(store)
                self.unchanged(store, originals)

    def test_lost_commit_ack_is_observed_without_second_projection_or_commit(self):
        class LostAck(sqlite3.Connection):
            armed = False
            commits = 0

            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.armed:
                    self.commits += 1
                    self.armed = False
                    raise OSError('Independent projected commit ACK lost')
                return result

        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': LostAck}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                calls = []

                def project(i, consume):
                    calls.append(i)
                    consume(self.write(i))

                store._connection.armed = True
                with self.assertRaisesRegex(OSError, 'ACK lost'):
                    store.compare_exchange_projected_attached(3, project, originals,
                                                              before_commit=lambda: None)
                self.assertEqual(calls, [0, 1, 2])
                expected = tuple(self.write(i) for i in range(3))
                self.assertEqual(store.read_exchange_many_attached(expected, originals),
                                 tuple(StoredBytes(0, write.payload) for write in expected))
                self.assertEqual(store._connection.commits, 1)
                self.unchanged(store, originals)

    def test_rollback_failure_keeps_same_store_pending_until_explicit_cleanup(self):
        class FailedRollback(sqlite3.Connection):
            armed = False

            def execute(self, sql, *args, **kwargs):
                if sql == 'ROLLBACK' and self.armed:
                    raise OSError('Independent projection rollback pending')
                return super().execute(sql, *args, **kwargs)

        physical = sqlite3.connect
        with TemporaryDirectory() as directory, patch('actql_sdk._local_storage.sqlite3.connect',
                side_effect=lambda *a, **k: physical(*a, **(k | {'factory': FailedRollback}))):
            with self.store(Path(directory) / 'core.sqlite') as store:
                originals = self.originals(store)
                handle = store._connection
                handle.armed = True
                with self.assertRaisesRegex(OSError, 'rollback pending'):
                    store.compare_exchange_projected_attached(
                        3, lambda i, consume: consume(self.write(i)), originals,
                        before_commit=lambda: False)
                self.assertIs(store._connection, handle)
                self.assertTrue(handle.in_transaction)
                self.assertFalse(store._closed)
                with self.assertRaisesRegex(LocalStorageError, 'cleanup is pending'):
                    store.read('index')
                handle.armed = False
                handle.execute('ROLLBACK')
                self.assertIs(store._connection, handle)
                self.absent(store)
                self.unchanged(store, originals)

    def test_complete_projection_survives_separate_process_without_reexecution(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                originals = self.originals(store)
                self.assertEqual(store.compare_exchange_projected_attached(
                    3, lambda i, consume: consume(self.write(i)), originals,
                    before_commit=lambda: None), (0, 0, 0))
            source = str(Path(__file__).resolve().parents[1] / 'src')
            script = """import json,sys
from pathlib import Path
sys.path.insert(0,sys.argv[2])
from actql_sdk._local_storage import LocalByteStore
with LocalByteStore(Path(sys.argv[1]),max_records=8,max_record_bytes=256,max_payload_bytes=1024) as store:
 print(json.dumps([[key,store.read(key).generation,store.read(key).payload.hex()] for key in ['contract/e\\u0301','contract/é','index']]))
"""
            actual = subprocess.run([sys.executable, '-c', script, str(path), source],
                                    capture_output=True, text=True, timeout=5, check=True)
            self.assertEqual(json.loads(actual.stdout), [
                ['contract/e\u0301', 0, b'original-e\xcc\x81\r\n'.hex()],
                ['contract/é', 0, b'original-\xc3\xa9/null'.hex()],
                ['index', 0, b'original-index'.hex()],
            ])
