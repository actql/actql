"""Real SQLite metadata/transaction boundaries; not Core Run acceptance."""
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (ByteFence, ByteWrite, LocalByteStore,
                                      LocalStorageError, LocalStorageCommitUnknown, StoredBytes)

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
