"""Independent Native reservation vectors through the actual Python SQLite port."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
from tempfile import TemporaryDirectory
from threading import Barrier
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    ByteFence, ByteWrite, CapacityReservation, CapacityUsage, LocalByteStore,
    LocalRunDefinitionConflict, LocalStorageError, StoredBytes, LocalStorageCommitUnknown,
    _DurableStoreLimits,
)

from actql_sdk._local_storage_physical import (
    _APPLICATION_ID, _CAPACITY_SCHEMA, _RUN_DEFINITION_INDEX, _SCHEMA, _SQLiteByteDatabase,
    _PhysicalWriteNotApplied,
)


class PhysicalCapacityTests(unittest.TestCase):
    def store(self, path: Path, *, records: int = 4) -> LocalByteStore:
        return LocalByteStore(path, max_records=records, max_record_bytes=128,
                              max_payload_bytes=256)

    def test_durable_rows_and_reservations_outlive_their_operation_limits(self) -> None:
        with TemporaryDirectory(prefix='actql-python-durable-capacity-') as directory:
            path = Path(directory) / 'core.sqlite'
            limits = dict(max_records=2, max_record_bytes=32, max_payload_bytes=48,
                          durable_limits=_DurableStoreLimits(6, 104, 4))
            with LocalByteStore(path, **limits) as store:
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite('a', None, b'a' * 16), ByteWrite('b', None, b'b' * 16),
                )), (0, 0))
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite('c', None, b'c' * 16), ByteWrite('d', None, b'd' * 16),
                )), (0, 0))
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite('e', None, b'e' * 16), ByteWrite('f', None, b'f' * 16),
                )), (0, 0))
                with self.assertRaisesRegex(ValueError, 'write batch'):
                    store.compare_exchange_many(tuple(ByteWrite(key, 0, b'x') for key in 'abc'))
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange_many((
                        ByteWrite('a', 0, b'x' * 25), ByteWrite('b', 0, b'y' * 25),
                    ))
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange('a', 0, b'x' * 25)
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange('g', None, b'')
                self.assertIsNone(store.read('g'))
                for key in 'abcd':
                    self.assertTrue(store.reserve_capacity('publication', key, 16, 1, 64, 4))
                with self.assertRaises(LocalStorageError):
                    store.reserve_capacity('different', 'e', 1, 1, 64, 4)
                self.assertEqual(store.capacity_usage('publication'), CapacityUsage(64, 4))

            with LocalByteStore(path, **limits) as store:
                for key in 'abcdef':
                    self.assertEqual(store.read(key), StoredBytes(0, key.encode() * 16))
                self.assertEqual(store.capacity_usage('publication'), CapacityUsage(64, 4))
                self.assertEqual(store.compare_exchange('a', 0, b'a' * 24), 1)
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange('a', 1, b'a' * 25)
                self.assertEqual(store.read('a'), StoredBytes(1, b'a' * 24))

    def test_projected_operation_keeps_its_write_bound_and_rolls_back_prefix(self) -> None:
        with TemporaryDirectory(prefix='actql-python-durable-projection-') as directory:
            path = Path(directory) / 'core.sqlite'
            settings = dict(max_records=2, max_record_bytes=32, max_payload_bytes=48,
                            durable_limits=_DurableStoreLimits(6, 128, 4))
            with LocalByteStore(path, **settings) as store:
                self.assertEqual(store.compare_exchange('original', None, b'kept'), 0)
                self.assertTrue(store.reserve_capacity('publication', 'original', 4, 1, 32, 4))
                originals = ((ByteFence('original', 0, b'kept'),
                              CapacityReservation('publication', 'original', 4, 1)),)
                observed = []

                def project(ordinal, consume):
                    observed.append(ordinal)
                    consume(ByteWrite(f'project/{ordinal}', None, b'x' * 25))

                with self.assertRaises(LocalStorageError):
                    store.compare_exchange_projected_attached(2, project, originals,
                        before_commit=lambda: self.fail('Over-limit projection reached precommit'))
                self.assertEqual(observed, [0, 1])
                self.assertIsNone(store.read('project/0'))
                self.assertIsNone(store.read('project/1'))
                self.assertEqual(store.read('original'), StoredBytes(0, b'kept'))
                self.assertEqual(store.capacity_usage('publication'), CapacityUsage(4, 1))
                self.assertEqual(store.compare_exchange_projected_attached(2,
                    lambda ordinal, consume: consume(ByteWrite(f'project/{ordinal}', None, b'x' * 24)),
                    originals, before_commit=lambda: None), (0, 0))

    def test_projected_reuse_and_writes_share_the_operation_body_limit(self) -> None:
        with TemporaryDirectory(prefix='actql-python-durable-reuse-') as directory:
            path = Path(directory) / 'core.sqlite'
            settings = dict(max_records=2, max_record_bytes=32, max_payload_bytes=48,
                            durable_limits=_DurableStoreLimits(6, 128, 4))
            with LocalByteStore(path, **settings) as store:
                self.assertEqual(store.compare_exchange('original', None, b'kept'), 0)
                self.assertTrue(store.reserve_capacity('publication', 'original', 4, 1, 32, 4))
                existing = ByteWrite('existing', None, b'x' * 25)
                self.assertEqual(store.compare_exchange_many((existing,)), (0,))
                originals = ((ByteFence('original', 0, b'kept'),
                              CapacityReservation('publication', 'original', 4, 1)),)
                values = (ByteWrite('fresh', None, b'y' * 24), existing)
                with patch.object(store, '_read_bytes_locked', wraps=store._read_bytes_locked) as read:
                    with self.assertRaises(LocalStorageError):
                        store.store_publication_projected_attached(2,
                            lambda ordinal, consume: consume(values[ordinal]), originals,
                            before_commit=lambda: self.fail('Over-limit reuse reached precommit'))
                    self.assertFalse(any(call.args[0] == existing.key for call in read.call_args_list))
                self.assertIsNone(store.read('fresh'))
                self.assertEqual(store.read('existing'), StoredBytes(0, existing.payload))

    def test_ordinary_writes_do_not_scan_or_account_unrelated_history(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            options = dict(max_records=4, max_record_bytes=128, max_payload_bytes=256, ordinary=True)
            with LocalByteStore(path, **options) as store:
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite(store.namespaced_key('client_submitted_intent_custody', 'issued'), None, b'0'),
                    ByteWrite(store.namespaced_key('client_submitted_intent_usage', 'retained'), None, b'0:0'),
                )), (0, 0))
                for offset in range(0, 1100, 4):
                    batch = tuple(ByteWrite(f'history:{index}', None, b'x' * 32)
                                  for index in range(offset, offset + 4))
                    self.assertEqual(store.compare_exchange_many(batch), (0, 0, 0, 0))
            with LocalByteStore(path, **options) as store:
                queries = []
                store._connection.set_trace_callback(queries.append)
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite('fresh', None, b'original'), ByteWrite('issued', None, b'1'),
                )), (0, 0))
                self.assertEqual(store.compare_exchange('fresh', 0, b'next'), 1)
                self.assertTrue(store.reserve_capacity('publication', 'fresh', 4, 1, 16, 4))
                self.assertFalse(store.reserve_capacity('publication', 'fresh', 4, 1, 16, 4))
                originals = ((ByteFence('fresh', 1, b'next'),
                              CapacityReservation('publication', 'fresh', 4, 1)),)
                self.assertEqual(store.compare_exchange_projected_attached(
                    1, lambda ordinal, consume: consume(ByteWrite('projected', None, b'next')),
                    originals, before_commit=lambda: None), (0,))
                self.assertTrue(store.release_capacity('publication', 'fresh', 4, 1))
                self.assertFalse(store.release_capacity('publication', 'fresh', 4, 1))
                normalized = tuple(' '.join(statement.lower().split()) for statement in queries)
                self.assertFalse(any('count(' in sql or 'sum(' in sql for sql in normalized))
                self.assertFalse(any('set records' in sql for sql in normalized))
                self.assertFalse(any('history:' in sql for sql in normalized))
                self.assertEqual(store._connection.execute(
                    'SELECT reservations, records, payload_bytes FROM actql_store_usage').fetchone(),
                    (0, None, None))

    def test_ordinary_run_batch_uses_sqlite_conflicts_in_write_order(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with LocalByteStore(path, max_records=8, max_record_bytes=512,
                                max_payload_bytes=2048, ordinary=True) as store:
                namespaced = store.namespaced_key
                count = namespaced('client_run_custody', 'issued')
                first_run = namespaced('client_runs', 'original')
                next_run = namespaced('client_runs', 'candidate')
                submitted = namespaced('client_submitted_intents', 'candidate')
                locator = namespaced('client_run_reference_index', 'selected')
                definition = 'sha256:' + 'a' * 64

                def run_payload(definition_cid, run):
                    return json.dumps({'run_definition': json.dumps({
                        'run_definition_cid': definition_cid}), 'run': run}).encode()

                original_run = run_payload(definition, 'original')
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite(count, None, b'1'),
                    ByteWrite(first_run, None, original_run),
                    ByteWrite(submitted, None, b'preparing'),
                    ByteWrite(locator, None, b'original'),
                    ByteWrite('epoch', None, b'current'),
                )), (0, 0, 0, 0, 0))
                fences = (ByteFence('epoch', 0, b'current'),)
                fresh = run_payload('sha256:' + 'b' * 64, 'candidate')
                prefix = ByteWrite(count, 0, b'2')
                submit = ByteWrite(submitted, 0, b'submitted')
                existing_locator = ByteWrite(locator, None, b'candidate')

                def inspect(reader):
                    reader.read('client_submitted_intents', 'candidate',
                                lambda row: self.assertEqual(row, ('candidate', StoredBytes(0, b'preparing'))))

                def append(writes):
                    return store.compare_exchange_many_inspected(
                        writes, fences, inspect=inspect, current=lambda: None)

                def original_preserved():
                    self.assertEqual(store.read(count), StoredBytes(0, b'1'))
                    self.assertEqual(store.read(first_run), StoredBytes(0, original_run))
                    self.assertEqual(store.read(submitted), StoredBytes(0, b'preparing'))
                    self.assertEqual(store.read(locator), StoredBytes(0, b'original'))
                    self.assertIsNone(store.read(next_run))
                    self.assertFalse(store._physical.in_transaction)

                def observe(operation):
                    return patch.object(_SQLiteByteDatabase, operation, autospec=True,
                                        side_effect=getattr(_SQLiteByteDatabase, operation))

                with (observe('write_record') as write, observe('read_header') as header,
                      observe('commit') as commit, observe('rollback') as rollback):
                    with self.assertRaises(LocalRunDefinitionConflict) as caught:
                        append((prefix, ByteWrite(next_run, None, run_payload(definition, 'candidate')),
                                submit, existing_locator))
                    self.assertEqual(caught.exception.definition, definition)
                    sqlite_error = caught.exception.__cause__.__cause__
                    self.assertIsInstance(sqlite_error, sqlite3.IntegrityError)
                    self.assertEqual(sqlite_error.sqlite_errorcode, sqlite3.SQLITE_CONSTRAINT_UNIQUE)
                    self.assertEqual([call.args[1] for call in write.call_args_list], [count, next_run])
                    header.assert_called_once_with(store._physical, next_run)
                    commit.assert_not_called()
                    rollback.assert_called_once()
                original_preserved()

                fresh_run = ByteWrite(next_run, None, fresh)
                with observe('write_record') as write:
                    self.assertIsNone(append((prefix, fresh_run, submit, existing_locator)))
                    self.assertEqual([call.args[1] for call in write.call_args_list],
                                     [count, next_run, submitted, locator])
                original_preserved()

                with observe('read_header') as header:
                    self.assertIsNone(append((prefix, fresh_run, ByteWrite(submitted, 1, b'wrong'))))
                    header.assert_called_once_with(store._physical, submitted)
                original_preserved()

                store._connection.execute("""
                    CREATE TEMP TRIGGER suppress_submit BEFORE UPDATE ON main.core_bytes
                    WHEN OLD.key = 'namespace:24:client_submitted_intents:candidate'
                    BEGIN SELECT RAISE(IGNORE); END
                """)
                with self.assertRaises(_PhysicalWriteNotApplied):
                    append((prefix, fresh_run, submit))
                original_preserved()
                store._connection.execute('DROP TRIGGER suppress_submit')

                with observe('read_header') as header:
                    self.assertEqual(append((prefix, fresh_run, submit)), (1, 0, 1))
                    header.assert_not_called()
                self.assertEqual(store.read(next_run), StoredBytes(0, fresh))
                self.assertEqual(store.read(submitted), StoredBytes(1, b'submitted'))

    def test_governed_totals_rollback_and_lost_commit_recovers_only_the_target(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            options = dict(max_records=4, max_record_bytes=128, max_payload_bytes=256,
                           durable_limits=_DurableStoreLimits(24, 1024, 4))
            with LocalByteStore(path, **options) as store, LocalByteStore(path, **options) as peer:
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite('issued', None, b'0'), ByteWrite('usage', None, b'0:0'),
                    ByteWrite('original', None, b'x'),
                )), (0, 0, 0))
                self.assertTrue(store.reserve_capacity('publication', 'original', 1, 1, 32, 4))
                originals = ((ByteFence('original', 0, b'x'),
                              CapacityReservation('publication', 'original', 1, 1)),)
                def fail():
                    raise OSError('precommit refused')
                def project(ordinal, consume):
                    consume(ByteWrite('rolled-back', None, b'123'))
                with self.assertRaisesRegex(OSError, 'precommit refused'):
                    store.compare_exchange_projected_attached(1, project, originals, before_commit=fail)
                self.assertIsNone(peer.read('rolled-back'))
                self.assertEqual(peer._connection.execute(
                    'SELECT reservations,records,payload_bytes FROM actql_store_usage').fetchone(),
                    (1, 3, 5))
                writes = (ByteWrite('issued', 0, b'1'), ByteWrite('usage', 0, b'1:2'),
                          ByteWrite('unknown', None, b'45'))
                real_commit = _SQLiteByteDatabase.commit
                commits = []
                def lose(database):
                    real_commit(database)
                    commits.append(database)
                    raise OSError('physical acknowledgement lost')
                with patch.object(_SQLiteByteDatabase, 'commit', lose):
                    with self.assertRaises(LocalStorageCommitUnknown) as caught:
                        store.compare_exchange_many(writes)
                self.assertIs(caught.exception.cleanup_store, store)
                self.assertEqual(commits, [store._physical])
                self.assertFalse(store._physical.in_transaction)
                self.assertEqual(peer.compare_exchange_many((
                    ByteWrite('issued', 1, b'2'), ByteWrite('usage', 1, b'2:6'),
                    ByteWrite('later', None, b'6789'),
                )), (2, 2, 0))
                self.assertIsNone(store.read_exchange_many_fenced(writes, (originals[0][0],), current=lambda: None))
                self.assertEqual(store.read_exchange(writes[-1]), StoredBytes(0, b'45'))
                self.assertEqual(store._connection.execute(
                    'SELECT reservations,records,payload_bytes FROM actql_store_usage').fetchone(),
                    (1, 5, 11))
                self.assertTrue(store.release_capacity('publication', 'original', 1, 1))
                self.assertFalse(store.release_capacity('publication', 'original', 1, 1))
                self.assertEqual(store._connection.execute(
                    'SELECT reservations,records,payload_bytes FROM actql_store_usage').fetchone(),
                    (0, 5, 11))

    def test_model_call_and_reservation_usage_share_the_actual_rollback(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                self.assertEqual(store.compare_exchange('epoch', None, b'original'), 0)
                fences = (ByteFence('epoch', 0, b'original'),)

                def save():
                    return store._save_model_call_entry_inspected(
                        'scope', 'attempt', 0, 1, b'model Entry', 32, fences,
                        inspect=lambda reader: reader.read('client_model_call_originals', 'attempt', lambda row: None),
                        confirm=lambda reader, row: reader.read('client_model_call_originals', 'attempt',
                            lambda observed: self.assertEqual(observed, ('attempt', row))),
                        current=lambda: None)

                def deny_entry(operation, table, column, database, source):
                    return (sqlite3.SQLITE_DENY if operation == sqlite3.SQLITE_INSERT
                            and table == 'core_bytes' else sqlite3.SQLITE_OK)

                store._connection.set_authorizer(deny_entry)
                with self.assertRaises(sqlite3.DatabaseError):
                    save()
                store._connection.set_authorizer(None)
                namespace = 'client_model_call_originals'
                self.assertIsNone(store.read(store.namespaced_key(namespace, 'attempt')))
                self.assertEqual(store.capacity_usage(namespace), CapacityUsage(0, 0))
                self.assertEqual(store._connection.execute(
                    'SELECT reservations FROM actql_store_usage').fetchone(), (0,))
                self.assertEqual(save(), StoredBytes(0, b'model Entry'))
                self.assertEqual(store.capacity_usage(namespace), CapacityUsage(11, 1))
                self.assertEqual(store._connection.execute(
                    'SELECT reservations FROM actql_store_usage').fetchone(), (1,))

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
                if sql.startswith('INSERT INTO main.actql_capacity VALUES'):
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
                    with self.assertRaises(LocalStorageCommitUnknown) as caught:
                        store.reserve_capacity('publication', 'original', 8, 1, 64, 4)
                    self.assertIs(caught.exception.cleanup_store, store)
                    expected = CapacityReservation('publication', 'original', 8, 1)
                    self.assertEqual(store.read_capacity('publication', 'original'), expected)
                    self.assertEqual(store.read_capacity('publication', 'original'), expected)
                    self.assertEqual(store._connection.inserts, 1)

    def test_failed_release_keeps_same_reservation_for_exact_retry(self) -> None:
        class RefuseRelease(sqlite3.Connection):
            refuse = False

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if self.refuse and sql.startswith('DELETE FROM main.actql_capacity_usage'):
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
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=4, max_record_bytes=128,
                                max_payload_bytes=256, durable_limits=_DurableStoreLimits(12, 1024, 2)) as store:
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
                    with self.assertRaises(LocalStorageCommitUnknown) as caught:
                        store.reserve_capacity('publication', 'original', 8, 1, 64, 4)
                    self.assertIs(caught.exception.cleanup_store, store)
                    with self.assertRaises(LocalStorageError):
                        store.read_capacity('publication', 'original')
                    with self.assertRaises(LocalStorageError):
                        store.capacity_usage('publication')
                    with self.assertRaises(LocalStorageError):
                        store.release_capacity('publication', 'original', 8, 1)
                with self.store(Path(directory) / 'core.sqlite') as reopened:
                    self.assertIsNone(reopened.read_capacity('publication', 'original'))

    @staticmethod
    def files(path):
        observed = {}
        for suffix in ('', '-journal', '-wal', '-shm'):
            selected = path.with_name(path.name + suffix)
            if selected.exists():
                st = selected.stat()
                observed[suffix] = (st.st_dev, st.st_ino, selected.read_bytes())
        return observed

    def test_old_catalog_and_wrong_usage_mode_refuse_before_touching_original(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'old.sqlite'
            with sqlite3.connect(path, isolation_level=None) as old:
                for sql in (_SCHEMA, _CAPACITY_SCHEMA, _RUN_DEFINITION_INDEX):
                    old.execute(sql)
                old.execute(f'PRAGMA application_id = {_APPLICATION_ID}')
                old.execute('INSERT INTO core_bytes VALUES (?,0,?)', ('original', b'keep'))
                path.chmod(0o600)
                before = self.files(path)
                with self.assertRaisesRegex(LocalStorageError, 'Unknown Local physical storage format'):
                    self.store(path)
                self.assertEqual(self.files(path), before)
                self.assertEqual(old.execute('PRAGMA journal_mode = WAL').fetchone(), ('wal',))
                old.execute('INSERT INTO core_bytes VALUES (?,0,?)', ('second', b'also keep'))
                before = self.files(path)
                self.assertEqual(set(before), {'', '-wal', '-shm'})
                with self.assertRaisesRegex(LocalStorageError, 'Unknown Local physical storage format'):
                    self.store(path)
                self.assertEqual(self.files(path), before)
            old.close()
            new_path = Path(directory) / 'current.sqlite'
            with self.store(new_path) as store:
                self.assertEqual(store.compare_exchange('original', None, b'keep'), 0)
            before = self.files(new_path)
            with self.assertRaisesRegex(LocalStorageError, 'Unknown Local physical storage format'):
                LocalByteStore(new_path, max_records=4, max_record_bytes=128, max_payload_bytes=256,
                               durable_limits=_DurableStoreLimits(16, 1024, 4))
            self.assertEqual(self.files(new_path), before)
            with self.assertRaisesRegex(LocalStorageError, 'Unknown Local physical storage format'):
                LocalByteStore(new_path, max_records=4, max_record_bytes=128,
                               max_payload_bytes=256, ordinary=True)
            self.assertEqual(self.files(new_path), before)
            with self.store(new_path) as store:
                issued = store.namespaced_key('client_submitted_intent_custody', 'issued')
                usage = store.namespaced_key('client_submitted_intent_usage', 'retained')
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite(issued, None, b'0'), ByteWrite(usage, None, b'00:0'),
                )), (0, 0))
            before = self.files(new_path)
            with self.assertRaisesRegex(LocalStorageError, 'Unknown Local physical storage format'):
                LocalByteStore(new_path, max_records=4, max_record_bytes=128,
                               max_payload_bytes=256, ordinary=True)
            self.assertEqual(self.files(new_path), before)
            with self.store(new_path) as store:
                store._connection.execute('DELETE FROM actql_store_usage')
            before = self.files(new_path)
            with self.assertRaisesRegex(LocalStorageError, 'Unknown Local physical storage format'):
                self.store(new_path)
            self.assertEqual(self.files(new_path), before)

    def test_ordinary_cold_admission_requires_the_original_issued_usage_pair(self) -> None:
        options = dict(max_records=4, max_record_bytes=128, max_payload_bytes=256, ordinary=True)
        cases = (
            ('issued count', b'2:5', False),
            ('row generation', b'1:5', True),
            ('zero count with bytes', b'0:5', False),
        )
        for reason, usage_body, advance_usage in cases:
            with self.subTest(reason=reason), TemporaryDirectory() as directory:
                path = Path(directory) / 'core.sqlite'
                with LocalByteStore(path, **options) as store:
                    issued = store.namespaced_key('client_submitted_intent_custody', 'issued')
                    usage = store.namespaced_key('client_submitted_intent_usage', 'retained')
                    target = store.namespaced_key('client_submitted_intents', 'original')
                    self.assertEqual(store.compare_exchange_many((
                        ByteWrite(issued, None, b'0'), ByteWrite(usage, None, b'0:0'),
                    )), (0, 0))
                with LocalByteStore(path, **options) as store:
                    self.assertEqual(store.compare_exchange_many((
                        ByteWrite(issued, 0, b'1'), ByteWrite(usage, 0, b'1:5'),
                        ByteWrite(target, None, b'proof'),
                    )), (1, 1, 0))
                with LocalByteStore(path, **options) as store:
                    self.assertEqual(store.read(target), StoredBytes(0, b'proof'))
                    self.assertEqual(store.read(usage), StoredBytes(1, b'1:5'))
                    if advance_usage:
                        self.assertEqual(store.compare_exchange(usage, 1, usage_body), 2)
                    else:
                        issued_body = b'0' if usage_body.startswith(b'0:') else b'1'
                        self.assertEqual(store.compare_exchange_many((
                            ByteWrite(issued, 1, issued_body), ByteWrite(usage, 1, usage_body),
                        )), (2, 2))
                before = self.files(path)
                with patch.object(sqlite3, 'connect', wraps=sqlite3.connect) as connect:
                    with self.assertRaisesRegex(LocalStorageError, 'Unknown Local physical storage format'):
                        with LocalByteStore(path, **options):
                            pass
                self.assertEqual([call.args[0] for call in connect.call_args_list],
                                 [path.as_uri() + '?mode=ro'])
                self.assertEqual(self.files(path), before)

    def test_missing_capacity_catalog_refuses_without_rewriting_original_bytes(self) -> None:
        with TemporaryDirectory(prefix='actql-python-capacity-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                store.compare_exchange('original', None, b'original Core bytes')
            connection = sqlite3.connect(path)
            connection.execute('DROP TABLE actql_capacity')
            connection.commit()
            connection.close()
            original = path.read_bytes()
            with self.assertRaises(LocalStorageError):
                self.store(path)
            self.assertEqual(path.read_bytes(), original)
            connection = sqlite3.connect(path)
            self.assertEqual(connection.execute('SELECT payload FROM core_bytes').fetchone()[0], b'original Core bytes')
            connection.close()
