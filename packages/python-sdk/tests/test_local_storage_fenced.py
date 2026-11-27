"""Real SQLite metadata/transaction boundaries; not Core Run acceptance."""
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (ByteFence, ByteWrite, LocalByteStore,
                                      LocalStorageError, LocalStorageCommitUnknown,
                                      LocalStorageWriteCleanupPending, StoredBytes)

# Independent opaque byte fixtures. The physical adapter neither parses their
# labels nor issues phase, identity, permission or execution facts.
_EPOCH = b'{"epoch":"e\xcc\x81\\r\\n"}'
_CONFIG = b'{"original":null,"absent":{},"e\xcc\x81/~":"\\r\\n"}'
_RUN = b'original-Core-run-row'
_INTENT = b'original-Core-submitted-row'
_FENCES = (ByteFence('epoch', 0, _EPOCH), ByteFence('config', 0, _CONFIG),
           ByteFence('count', 0, b'0'))
_WRITES = (ByteWrite('count', 0, b'1'), ByteWrite('run', None, _RUN),
           ByteWrite('submitted', None, _INTENT))
_OBSERVED = (StoredBytes(1, b'1'), StoredBytes(0, _RUN), StoredBytes(0, _INTENT))


class LocalFencedBatchTests(unittest.TestCase):
    def store(self, path: Path) -> LocalByteStore:
        return LocalByteStore(path, max_records=8, max_record_bytes=256,
                              max_payload_bytes=1024)

    def initialize(self, store: LocalByteStore) -> None:
        for fence in _FENCES:
            self.assertEqual(store.compare_exchange(fence.key, None, fence.payload), 0)

    def current(self) -> None:
        # A trusted Host calls the typed Core/current port here. This test only
        # checks callback ordering; None cannot itself issue any authority.
        return None

    def test_named_census_transfers_keys_and_generations_without_nonselected_bodies(self) -> None:
        namespace = 'client_submission_names'
        first, second = 'a' * 64, 'b' * 64
        with TemporaryDirectory(prefix='actql-local-name-keys-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.initialize(store)
                self.assertEqual(store.compare_exchange(
                    store.namespaced_key(namespace, first), None, b'first-name'), 0)
                self.assertEqual(store.compare_exchange(
                    store.namespaced_key(namespace, second), None, b'selected-name'), 0)
                statements: list[str] = []
                store._connection.set_trace_callback(statements.append)

                def inspect(reader):
                    query = reader.query_current
                    self.assertIsNotNone(query)
                    self.assertEqual(query(reader, 2, namespace, '', self.current),
                                     (first, StoredBytes(0, b'')))
                    self.assertEqual(query(reader, 2, namespace, first, self.current),
                                     (second, StoredBytes(0, b'')))
                    self.assertIsNone(query(reader, 2, namespace, second, self.current))
                    self.assertEqual(query(reader, 1, namespace, second, self.current),
                                     (second, StoredBytes(0, b'selected-name')))

                store.inspect_namespaces(_FENCES, inspect=inspect, current=self.current)
                self.assertEqual(statements.count('BEGIN'), 1)
                self.assertEqual(statements.count('ROLLBACK'), 1)
                key_reads = [sql for sql in statements if 'ORDER BY key COLLATE BINARY LIMIT 1' in sql
                             and namespace in sql and 'length(payload)' in sql]
                self.assertEqual(len(key_reads), 4)
                self.assertEqual(sum('THEN payload' in sql for sql in key_reads), 1)
                with self.assertRaisesRegex(ValueError, 'original Local current query'):
                    store.inspect_namespaces(_FENCES, inspect=lambda reader:
                        reader.query_current(reader, 2, 'client_submitted_intents', '', self.current),
                        current=self.current)
                store.close()
                self.assertTrue(store._closed)

    def test_saved_payload_row_and_reservation_share_one_physical_read(self) -> None:
        with TemporaryDirectory(prefix='actql-local-payload-read-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                self.initialize(store)
                namespace = 'publication_payload'
                key = store.namespaced_key('payload_record', 'original')
                self.assertEqual(store.compare_exchange(key, None, b'original'), 0)
                self.assertEqual(store.compare_exchange(
                    store.namespaced_key('journal', 'control'), None, b'control'), 0)
                self.assertTrue(store.reserve_capacity(namespace, key, 37, 1, 1024, 8))
                statements, rows, reservations = [], [], []
                store._connection.set_trace_callback(statements.append)

                def inspect(reader, observe):
                    self.assertIs(reader.owner, store)
                    self.assertTrue(store._connection.in_transaction)
                    current = []
                    reader.read('journal', 'control', current.append)
                    self.assertEqual(current, [('control', StoredBytes(0, b'control'))])
                    observe()

                store.inspect_record_capacity_inspected(namespace, key, 64, _FENCES,
                    inspect=inspect, consume_record=rows.append,
                    consume_capacity=reservations.append, current=self.current)
                self.assertEqual(rows, [StoredBytes(0, b'original')])
                reservation, = reservations
                self.assertEqual((reservation.namespace, reservation.key, reservation.reserved_bytes,
                                  reservation.reserved_objects), (namespace, key, 37, 1))
                self.assertEqual((statements.count('BEGIN'), statements.count('ROLLBACK')), (1, 1))
                self.assertEqual(sum('FROM main.actql_capacity' in sql for sql in statements), 1)

                statements.clear()
                cause = ValueError('Original payload bytes changed')
                def refuse(row):
                    self.assertEqual(row, StoredBytes(0, b'original'))
                    raise cause
                with self.assertRaises(ValueError) as failure:
                    store.inspect_record_capacity_inspected(namespace, key, 64, _FENCES,
                        inspect=inspect, consume_record=refuse,
                        consume_capacity=reservations.append, current=self.current)
                self.assertIs(failure.exception, cause)
                self.assertEqual(reservations, [reservation])
                self.assertEqual((statements.count('BEGIN'), statements.count('ROLLBACK')), (1, 1))
                self.assertFalse(any('FROM main.actql_capacity' in sql for sql in statements))
            self.assertTrue(store._closed)

    def test_projected_journal_uses_same_fenced_sqlite_transaction(self) -> None:
        with TemporaryDirectory(prefix='actql-local-projected-journal-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                self.initialize(store)
                row = store.namespaced_key('journal', 'original')
                self.assertEqual(store.compare_exchange(row, None, b'original'), 0)
                events: list[str] = []

                def inspect(reader, stage):
                    self.assertIs(reader.owner, store)
                    self.assertTrue(store._connection.in_transaction)
                    observed = []
                    reader.read('journal', 'original', observed.append)
                    self.assertEqual(observed, [('original', StoredBytes(0, b'original'))])
                    events.append('inspect')
                    stage()

                def before_commit():
                    self.assertTrue(store._connection.in_transaction)
                    self.assertEqual(store._connection.execute(
                        'SELECT generation, payload FROM main.core_bytes WHERE key = ?', ('submitted',)
                    ).fetchone(), (0, _INTENT))
                    events.append('before_commit')

                def produce(ordinal, consume):
                    events.append('write-' + str(ordinal))
                    consume(_WRITES[ordinal])

                with self.assertRaisesRegex(ValueError, 'physical current and fences'):
                    store.compare_exchange_journal_projected_inspected(
                        len(_WRITES), produce, (), inspect=inspect, current=self.current,
                        before_commit=before_commit)
                self.assertEqual(events, [])

                self.assertEqual(store.compare_exchange_journal_projected_inspected(
                    len(_WRITES), produce, _FENCES[:2], inspect=inspect, current=self.current,
                    before_commit=before_commit), (1, 0, 0))
                self.assertEqual(events, ['inspect', 'write-0', 'write-1', 'write-2', 'before_commit'])
            with self.store(path) as reopened:
                self.assertEqual(tuple(reopened.read(write.key) for write in _WRITES), _OBSERVED)

    def test_projected_journal_distinguishes_rollback_from_postcommit_refusal(self) -> None:
        for committed in (False, True):
            with self.subTest(committed=committed), TemporaryDirectory(
                    prefix='actql-local-projected-journal-cutoff-') as directory:
                path = Path(directory) / 'core.sqlite'
                store = self.store(path)
                with store:
                    self.initialize(store)
                    key = store.namespaced_key('journal', 'original')
                    self.assertEqual(store.compare_exchange(key, None, b'original'), 0)
                    statements: list[str] = []
                    writes: list[int] = []
                    cause = PermissionError('original projected Journal current refused')
                    store._connection.set_trace_callback(statements.append)

                    def read(reader):
                        self.assertIs(reader.owner, store)
                        observed = []
                        reader.read('journal', 'original', observed.append)
                        self.assertEqual(observed, [('original', StoredBytes(0, b'original'))])

                    def inspect(reader, stage):
                        read(reader)
                        stage()

                    def before_commit():
                        self.assertTrue(store._connection.in_transaction)
                        if not committed:
                            raise cause

                    def current():
                        if committed and 'COMMIT' in statements:
                            self.assertFalse(store._connection.in_transaction)
                            raise cause

                    def produce(ordinal, consume):
                        writes.append(ordinal)
                        consume(_WRITES[ordinal])

                    failure = LocalStorageCommitUnknown if committed else PermissionError
                    with self.assertRaises(failure) as caught:
                        store.compare_exchange_journal_projected_inspected(
                            len(_WRITES), produce, _FENCES[:2], inspect=inspect,
                            current=current, before_commit=before_commit)
                    self.assertEqual(writes, [0, 1, 2])
                    self.assertEqual(statements.count('BEGIN IMMEDIATE'), 1)
                    self.assertEqual(statements.count('COMMIT'), int(committed))
                    self.assertEqual(statements.count('ROLLBACK'), int(not committed))
                    if committed:
                        self.assertIs(caught.exception.__cause__, cause)
                        self.assertIs(caught.exception.cleanup_store, store)
                        self.assertTrue(caught.exception.commit_confirmed)
                    else:
                        self.assertIs(caught.exception, cause)

                    store.inspect_namespaces(_FENCES[:2], inspect=read, current=self.current)
                    expected = _OBSERVED if committed else (StoredBytes(0, b'0'), None, None)
                    self.assertEqual(tuple(store.read(write.key) for write in _WRITES), expected)
                self.assertTrue(store._closed)
                with self.store(path) as reopened:
                    self.assertEqual(tuple(reopened.read(write.key) for write in _WRITES), expected)

    def test_file_task_point_bytes_are_borrowed_only_in_original_read(self) -> None:
        namespace = 'client_task_run_materials'
        slot = 'sha256:' + 'a' * 64 + ':0'
        physical_key = LocalByteStore.namespaced_key(namespace, slot)
        with TemporaryDirectory(prefix='actql-local-task-points-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.assertEqual(store.compare_exchange(physical_key, None, b'first'), 0)
                backend = type(store._physical)
                scan = backend.scan_range
                acquisitions = []

                def count(physical, lower, upper, limit, **options):
                    if physical is store._physical and lower == physical_key:
                        acquisitions.append(lower)
                    return scan(physical, lower, upper, limit, **options)

                def inspect(expected, *, change=False):
                    def consume(reader):
                        self.assertIsNotNone(reader.query_current)
                        query = reader.query_current
                        current = self.current
                        self.assertEqual(query(reader, 1, namespace, slot, current),
                                         (slot, expected))
                        if change:
                            def current():
                                store._connection.execute(
                                    'UPDATE main.core_bytes SET payload = ? WHERE key = ?',
                                    (b'intervening', physical_key))
                        self.assertEqual(query(reader, 1, namespace, slot, current),
                                         (slot, expected))

                    store._physical.begin_read()
                    try:
                        store._inspect_namespace_locked(consume, (), self.current,
                                                         _retain_task_points=True)
                    finally:
                        store._physical.finish_read()

                with patch.object(backend, 'scan_range', count):
                    inspect(StoredBytes(0, b'first'))
                    self.assertEqual(acquisitions, [physical_key])
                    self.assertEqual(store.compare_exchange(physical_key, 0, b'second'), 1)
                    inspect(StoredBytes(1, b'second'))
                    self.assertEqual(acquisitions, [physical_key] * 2)
                    with self.assertRaisesRegex(LocalStorageError, 'Task point snapshot changed'):
                        inspect(StoredBytes(1, b'second'), change=True)
                    self.assertEqual(acquisitions, [physical_key] * 3)
                self.assertEqual(store.read(physical_key), StoredBytes(1, b'second'))

    def test_exact_originals_and_successors_are_atomic_and_survive_reopen(self) -> None:
        with TemporaryDirectory(prefix='actql-local-fenced-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                self.initialize(store)
                self.assertIsNone(store.read_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current))
                self.assertEqual(store.compare_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current), (1, 0, 0))
                self.assertEqual(store.read('epoch'), StoredBytes(0, _EPOCH))
                self.assertEqual(store.read('config'), StoredBytes(0, _CONFIG))
            with self.store(path) as store:
                self.assertEqual(store.read_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current), _OBSERVED)
                self.assertIsNone(store.read_exchange_many_fenced(
                    _WRITES, (ByteFence('foreign-epoch', 0, _EPOCH),), current=self.current))
                self.assertIsNone(store.read_exchange_many_fenced(
                    _WRITES, (ByteFence('config', 0, _CONFIG.replace(b'\\r\\n', b'\\n')),),
                    current=self.current))

    def test_changed_epoch_configuration_or_count_refuses_all_writes(self) -> None:
        for key in ('epoch', 'config', 'count'):
            for advance in (False, True):
                with self.subTest(key=key, advance=advance):
                    with TemporaryDirectory(prefix='actql-local-fence-change-') as directory:
                        with self.store(Path(directory) / 'core.sqlite') as store:
                            self.initialize(store)
                            if advance:
                                store.compare_exchange(key, 0, b'changed')
                            else:
                                # Even a corrupt physical replacement at the same
                                # generation must fail its independently held bytes.
                                store._connection.execute(
                                    'UPDATE core_bytes SET payload = ? WHERE key = ?', (b'changed', key))
                            self.assertIsNone(store.compare_exchange_many_fenced(
                                _WRITES, _FENCES, current=self.current))
                            self.assertIsNone(store.read('run'))
                            self.assertIsNone(store.read('submitted'))

    def test_competing_target_rolls_back_every_other_target(self) -> None:
        with TemporaryDirectory(prefix='actql-local-fence-conflict-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.initialize(store)
                store.compare_exchange('submitted', None, b'foreign')
                self.assertIsNone(store.compare_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current))
                self.assertEqual(store.read('count'), StoredBytes(0, b'0'))
                self.assertIsNone(store.read('run'))
                self.assertEqual(store.read('submitted'), StoredBytes(0, b'foreign'))

    def test_lost_commit_reply_is_observed_without_a_second_write(self) -> None:
        class LostCommit(sqlite3.Connection):
            lose = False
            writes = 0

            def execute(self, sql, *args, **kwargs):
                if sql.startswith(('INSERT', 'UPDATE')):
                    self.writes += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.lose:
                    self.lose = False
                    raise OSError('original COMMIT reply lost')
                return result

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-local-fence-ack-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostCommit}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    self.initialize(store)
                    before = store._connection.writes
                    store._connection.lose = True
                    with self.assertRaises(LocalStorageCommitUnknown) as caught:
                        store.compare_exchange_many_fenced(_WRITES, _FENCES, current=self.current)
                    self.assertIs(caught.exception.cleanup_store, store)
                    self.assertFalse(caught.exception.commit_confirmed)
                    self.assertIsNone(caught.exception.cleanup_error)
                    self.assertIsInstance(caught.exception.__cause__, OSError)
                    self.assertEqual(str(caught.exception.__cause__), 'original COMMIT reply lost')
                    self.assertEqual(store._connection.writes, before + 3)
                    self.assertEqual(store.read_exchange_many_fenced(
                        _WRITES, _FENCES, current=self.current), _OBSERVED)
                    self.assertEqual(store.read_exchange_many_fenced(
                        _WRITES, _FENCES, current=self.current), _OBSERVED)
                    self.assertEqual(store._connection.writes, before + 3)
                    store.compare_exchange('run', 0, _RUN)
                    self.assertIsNone(store.read_exchange_many_fenced(
                        _WRITES, _FENCES, current=self.current))

    def test_lost_release_commit_reply_preserves_the_original_result_without_retry(self) -> None:
        class LostReply(sqlite3.Connection):
            lose = False
            commit_count = 0

            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT':
                    self.commit_count += 1
                    if self.lose:
                        self.lose = False
                        raise primary
                return result

        connect = sqlite3.connect
        primary = OSError('original COMMIT response lost')
        with TemporaryDirectory(prefix='actql-local-fence-release-') as directory:
            path = Path(directory) / 'core.sqlite'
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostReply}))):
                with self.store(path) as store:
                    self.assertTrue(store.reserve_capacity('space', 'item', 5, 1, 10, 2))
                    self.assertTrue(store.reserve_capacity('space', 'other', 3, 1, 10, 2))
                    before = store._connection.commit_count
                    store._connection.lose = True
                    with self.assertRaises(LocalStorageCommitUnknown) as caught:
                        store.release_capacity('space', 'item', 5, 1)
                    self.assertIs(caught.exception.cleanup_store, store)
                    self.assertIs(caught.exception.__cause__, primary)
                    self.assertFalse(caught.exception.commit_confirmed)
                    self.assertIsNone(caught.exception.cleanup_error)
                    self.assertFalse(store._connection.in_transaction)
                    self.assertEqual(store._connection.commit_count, before + 1)
            with self.store(path) as reopened:
                self.assertIsNone(reopened.read_capacity('space', 'item'))
                other = reopened.read_capacity('space', 'other')
                self.assertIsNotNone(other)
                self.assertEqual((other.reserved_bytes, other.reserved_objects), (3, 1))

    def test_failed_commit_preserves_primary_when_rollback_or_state_read_fails(self) -> None:
        class FailedCommit(sqlite3.Connection):
            armed = False
            refused = False
            rollback_count = 0
            begin_count = 0
            commit_attempt_count = 0

            @property
            def in_transaction(self):
                if self.refused and mode == 'state':
                    self.refused = False
                    raise cleanup
                return super().in_transaction

            def execute(self, sql, *args, **kwargs):
                if sql == 'BEGIN IMMEDIATE':
                    self.begin_count += 1
                if sql == 'COMMIT' and self.armed:
                    self.commit_attempt_count += 1
                    self.refused = True
                    raise primary
                if sql == 'ROLLBACK' and self.armed:
                    self.rollback_count += 1
                    raise cleanup
                return super().execute(sql, *args, **kwargs)

        connect = sqlite3.connect
        primary = sqlite3.IntegrityError('original COMMIT refused')
        cleanup = OSError('original transaction stop unconfirmed')
        for mode in ('rollback', 'state'):
            with self.subTest(mode=mode), TemporaryDirectory(
                    prefix='actql-local-fence-combined-') as directory:
                path = Path(directory) / 'core.sqlite'
                with patch('actql_sdk._local_storage.sqlite3.connect',
                           side_effect=lambda *a, **k: connect(*a, **(k | {'factory': FailedCommit}))):
                    with self.store(path) as store:
                        store._connection.armed = True
                        with self.assertRaises(LocalStorageCommitUnknown) as caught:
                            store.compare_exchange_many((ByteWrite('row', None, _RUN),))
                        self.assertIs(caught.exception.cleanup_store, store)
                        self.assertIs(caught.exception.__cause__, primary)
                        self.assertIs(caught.exception.cleanup_error, cleanup)
                        self.assertEqual(caught.exception._cleanup_phase,
                                         'rollback' if mode == 'rollback' else 'state_inspection')
                        self.assertFalse(caught.exception.commit_confirmed)
                        self.assertTrue(store._connection.in_transaction)
                        self.assertEqual(store._connection.rollback_count, int(mode == 'rollback'))
                        before = store._connection.begin_count
                        with self.assertRaisesRegex(LocalStorageError, 'cleanup is pending'):
                            store.read('row')
                        with self.assertRaisesRegex(LocalStorageError, 'cleanup is pending'):
                            store.reserve_capacity('space', 'item', 5, 1, 10, 2)
                        with self.assertRaisesRegex(LocalStorageError, 'cleanup is pending'):
                            store.compare_exchange_many((ByteWrite('row', None, _RUN),))
                        self.assertEqual(store._connection.begin_count, before)
                        self.assertEqual(store._connection.commit_attempt_count, 1)
                with self.store(path) as reopened:
                    self.assertIsNone(reopened.read('row'))
                    self.assertEqual(reopened.capacity_usage('space').reserved_objects, 0)

    def test_precommit_failure_with_lost_rollback_reply_fences_even_after_stop(self) -> None:
        class LostRollback(sqlite3.Connection):
            armed = False
            rollback_count = 0
            commit_count = 0

            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT':
                    self.commit_count += 1
                if sql == 'ROLLBACK' and self.armed:
                    self.rollback_count += 1
                    raise cleanup
                return result

        connect = sqlite3.connect
        primary = PermissionError('original pre-COMMIT refusal')
        cleanup = OSError('original ROLLBACK response lost')

        calls = 0

        def current():
            nonlocal calls
            calls += 1
            if calls == 2:
                raise primary

        with TemporaryDirectory(prefix='actql-local-fence-lost-rollback-') as directory:
            path = Path(directory) / 'core.sqlite'
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostRollback}))):
                with self.store(path) as store:
                    self.initialize(store)
                    store._connection.armed = True
                    before = store._connection.commit_count
                    with self.assertRaises(LocalStorageWriteCleanupPending) as caught:
                        store.compare_exchange_many_fenced(_WRITES, _FENCES, current=current)
                    self.assertIs(caught.exception.cleanup_store, store)
                    self.assertIs(caught.exception.__cause__, primary)
                    self.assertIs(caught.exception.cleanup_error, cleanup)
                    self.assertEqual(caught.exception._cleanup_phase, 'rollback')
                    self.assertFalse(store._connection.in_transaction)
                    self.assertEqual(store._connection.rollback_count, 1)
                    self.assertEqual(store._connection.commit_count, before)
                    with self.assertRaisesRegex(LocalStorageError, 'cleanup is pending'):
                        store.read('run')
            with self.store(path) as reopened:
                self.assertIsNone(reopened.read('run'))
                self.assertEqual(reopened.read('count'), StoredBytes(0, b'0'))

    def test_current_refusal_before_commit_rolls_back_and_after_commit_is_unknown(self) -> None:
        for refuse_at in (1, 2, 3):
            with self.subTest(refuse_at=refuse_at):
                with TemporaryDirectory(prefix='actql-local-fence-current-') as directory:
                    with self.store(Path(directory) / 'core.sqlite') as store:
                        self.initialize(store)
                        calls = 0

                        def current():
                            nonlocal calls
                            calls += 1
                            if calls == refuse_at:
                                raise PermissionError('typed current port refused')

                        failure = PermissionError if refuse_at < 3 else LocalStorageCommitUnknown
                        with self.assertRaises(failure) as caught:
                            store.compare_exchange_many_fenced(_WRITES, _FENCES, current=current)
                        if refuse_at == 3:
                            self.assertIs(caught.exception.cleanup_store, store)
                            self.assertTrue(caught.exception.commit_confirmed)
                            self.assertIsNone(caught.exception.cleanup_error)
                            self.assertIsNone(caught.exception._cleanup_phase)
                            self.assertIsInstance(caught.exception.__cause__, PermissionError)
                        self.assertEqual(calls, refuse_at)
                        expected = None if refuse_at < 3 else _OBSERVED
                        self.assertEqual(store.read_exchange_many_fenced(
                            _WRITES, _FENCES, current=self.current), expected)
                        with self.assertRaises(PermissionError):
                            store.read_exchange_many_fenced(_WRITES, _FENCES,
                                current=lambda: (_ for _ in ()).throw(PermissionError('revoked')))

    def test_current_callback_cannot_supply_boolean_or_modify_readonly_originals(self) -> None:
        with TemporaryDirectory(prefix='actql-local-fence-callback-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.initialize(store)
                for result in (True, False, 0, 1, (), 'allowed'):
                    with self.assertRaises(ValueError):
                        store.compare_exchange_many_fenced(
                            _WRITES, _FENCES, current=lambda: result)
                    with self.assertRaises(ValueError):
                        store.read_exchange_many_fenced(
                            _WRITES, _FENCES, current=lambda: result)
                calls = 0

                def change():
                    nonlocal calls
                    calls += 1
                    if calls == 2:
                        store._connection.execute(
                            'UPDATE core_bytes SET payload = ? WHERE key = ?', (b'changed', 'config'))

                self.assertIsNone(store.compare_exchange_many_fenced(_WRITES, _FENCES, current=change))
                self.assertEqual(store.read('config'), StoredBytes(0, _CONFIG))
                self.assertIsNone(store.read('run'))

    def test_read_current_recheck_cannot_return_changed_observations(self) -> None:
        with TemporaryDirectory(prefix='actql-local-fence-read-current-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.initialize(store)
                store.compare_exchange_many_fenced(_WRITES, _FENCES, current=self.current)
                calls = 0

                def change():
                    nonlocal calls
                    calls += 1
                    if calls == 2:
                        store._connection.execute(
                            'UPDATE core_bytes SET payload = ? WHERE key = ?', (b'changed', 'config'))

                self.assertIsNone(store.read_exchange_many_fenced(_WRITES, _FENCES, current=change))
                self.assertEqual(store.read('config'), StoredBytes(0, _CONFIG))
                self.assertEqual(store.read_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current), _OBSERVED)

    def test_query_failure_is_not_an_unmatched_or_absent_observation(self) -> None:
        with TemporaryDirectory(prefix='actql-local-fence-query-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                self.initialize(store)
                store.compare_exchange_many_fenced(_WRITES, _FENCES, current=self.current)
                original = store._read_bytes_locked

                def refuse(key):
                    if key == 'run':
                        raise OSError('original physical query failed')
                    return original(key)

                with patch.object(store, '_read_bytes_locked', side_effect=refuse):
                    with self.assertRaisesRegex(OSError, 'original physical query failed'):
                        store.read_exchange_many_fenced(_WRITES, _FENCES, current=self.current)
                self.assertEqual(store.read_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current), _OBSERVED)

    def test_failed_read_cleanup_keeps_the_same_store_pending(self) -> None:
        class Pending(sqlite3.Connection):
            refuse = False

            def execute(self, sql, *args, **kwargs):
                if sql == 'ROLLBACK' and self.refuse:
                    raise OSError('original read cleanup pending')
                return super().execute(sql, *args, **kwargs)

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-local-fence-cleanup-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': Pending}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    self.initialize(store)
                    store.compare_exchange_many_fenced(_WRITES, _FENCES, current=self.current)
                    store._connection.refuse = True
                    with self.assertRaisesRegex(OSError, 'original read cleanup pending'):
                        store.read_exchange_many_fenced(_WRITES, _FENCES, current=self.current)
                    self.assertTrue(store._connection.in_transaction)
                    self.assertFalse(store._closed)
                    with self.assertRaisesRegex(LocalStorageError, 'cleanup is pending'):
                        store.read_exchange_many_fenced(_WRITES, _FENCES, current=self.current)
                    self.assertTrue(store._connection.in_transaction)
                    store._connection.refuse = False
                    store._connection.execute('ROLLBACK')
                    self.assertEqual(store.read_exchange_many_fenced(
                        _WRITES, _FENCES, current=self.current), _OBSERVED)

    def test_malformed_or_unbounded_fences_refuse_before_database_io(self) -> None:
        with TemporaryDirectory(prefix='actql-local-fence-invalid-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                for fences in ((), (_FENCES[0], _FENCES[0]),
                               (ByteFence('epoch', True, _EPOCH),),
                               (ByteFence('epoch', -1, _EPOCH),),
                               (ByteFence('epoch', 0, b'x' * 257),),
                               (ByteFence('count', 1, b'0'),)):
                    with patch.object(store, '_open', side_effect=AssertionError('unexpected I/O')):
                        for method in (store.compare_exchange_many_fenced, store.read_exchange_many_fenced):
                            with self.assertRaises(ValueError):
                                method(_WRITES, fences, current=self.current)

    def test_metadata_fence_and_all_writes_share_the_sqlite_write_lock(self) -> None:
        with TemporaryDirectory(prefix='actql-local-fence-lock-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as writer, self.store(path) as other:
                self.initialize(writer)
                other._connection.execute('PRAGMA busy_timeout = 0')
                observed = []

                def compete(query):
                    if query.startswith('SELECT generation,') and not observed:
                        try:
                            other.compare_exchange('config', 0, b'foreign-current')
                        except sqlite3.OperationalError as failure:
                            observed.append(str(failure))
                        else:
                            observed.append('unexpected metadata replacement')

                writer._connection.set_trace_callback(compete)
                self.assertEqual(writer.compare_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current), (1, 0, 0))
                self.assertEqual(observed, ['database is locked'])
                self.assertEqual(writer.read('config'), StoredBytes(0, _CONFIG))
                self.assertEqual(writer.read_exchange_many_fenced(
                    _WRITES, _FENCES, current=self.current), _OBSERVED)
