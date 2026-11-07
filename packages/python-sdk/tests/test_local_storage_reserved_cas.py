"""Actual SQLite reservation fences; opaque bytes do not assert Run states."""
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    ByteWrite, CapacityReservation, CapacityUsage, LocalByteStore, StoredBytes,
)


class ReservedByteCASTests(unittest.TestCase):
    def store(self, path: Path) -> LocalByteStore:
        return LocalByteStore(path, max_records=4, max_record_bytes=128,
                              max_payload_bytes=256)

    def original(self, store: LocalByteStore) -> CapacityReservation:
        self.assertEqual(store.compare_exchange('material', None, b'original\x00NULL/e\xcc\x81\r\n'), 0)
        self.assertTrue(store.reserve_capacity('publication_payload', 'material', 64, 1, 128, 2))
        observation = store.read_capacity('publication_payload', 'material')
        self.assertEqual(observation, CapacityReservation('publication_payload', 'material', 64, 1))
        assert observation is not None
        return observation

    def mutations(self, queries: list[str]) -> list[str]:
        return [q for q in queries if q.startswith(('INSERT', 'UPDATE', 'DELETE'))]

    def test_exact_reservation_and_original_bytes_commit_once_and_survive_reopen(self) -> None:
        with TemporaryDirectory(prefix='actql-python-reserved-cas-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                observation = self.original(store)
                write = ByteWrite('material', 0, b'next\x00NULL/e\xcc\x81\r\n')
                self.assertEqual(store.compare_exchange_reserved(write, observation), 1)
                self.assertEqual(store.read_exchange(write), StoredBytes(1, write.payload))
                self.assertIsNone(store.compare_exchange_reserved(write, observation))
                self.assertEqual(store.capacity_usage('publication_payload'), CapacityUsage(64, 1))
            with self.store(path) as reopened:
                self.assertEqual(reopened.read('material'), StoredBytes(1, write.payload))
                self.assertEqual(reopened.read_capacity('publication_payload', 'material'), observation)

    def test_released_after_observation_performs_no_write_or_reacquisition(self) -> None:
        with TemporaryDirectory(prefix='actql-python-reserved-cas-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as writer, self.store(path) as other:
                observation = self.original(writer)
                self.assertTrue(other.release_capacity('publication_payload', 'material', 64, 1))
                queries: list[str] = []
                writer._connection.set_trace_callback(queries.append)
                self.assertIsNone(writer.compare_exchange_reserved(ByteWrite('material', 0, b'next'), observation))
                self.assertEqual(self.mutations(queries), [])
                self.assertEqual(writer.read('material').generation, 0)
                self.assertIsNone(writer.read_capacity('publication_payload', 'material'))

    def test_changed_amount_or_foreign_namespace_cannot_install_record(self) -> None:
        with TemporaryDirectory(prefix='actql-python-reserved-cas-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                observation = self.original(store)
                store.release_capacity('publication_payload', 'material', 64, 1)
                store.reserve_capacity('publication_payload', 'material', 65, 1, 128, 2)
                write = ByteWrite('material', 0, b'next')
                queries: list[str] = []
                store._connection.set_trace_callback(queries.append)
                self.assertIsNone(store.compare_exchange_reserved(write, observation))
                self.assertIsNone(store.compare_exchange_reserved(write, CapacityReservation('foreign', 'material', 65, 1)))
                self.assertEqual(self.mutations(queries), [])
                self.assertEqual(store.read('material').generation, 0)
                self.assertEqual(store.capacity_usage('publication_payload'), CapacityUsage(65, 1))

    def test_capacity_read_and_record_write_share_the_actual_sqlite_write_lock(self) -> None:
        with TemporaryDirectory(prefix='actql-python-reserved-cas-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as writer, self.store(path) as other:
                observation = self.original(writer)
                other._connection.execute('PRAGMA busy_timeout = 0')
                observations: list[object] = []

                def attempt_release(query: str) -> None:
                    if query.startswith('SELECT reserved_bytes, reserved_objects'):
                        observations.append(writer._connection.in_transaction)
                        try:
                            other.release_capacity('publication_payload', 'material', 64, 1)
                        except sqlite3.OperationalError as error:
                            observations.append(str(error))
                        else:
                            observations.append('released')

                writer._connection.set_trace_callback(attempt_release)
                self.assertEqual(writer.compare_exchange_reserved(
                    ByteWrite('material', 0, b'next'), observation), 1)
                writer._connection.set_trace_callback(None)
                self.assertEqual(observations, [True, 'database is locked'])
                self.assertEqual(writer.read_capacity('publication_payload', 'material'), observation)
                self.assertTrue(other.release_capacity('publication_payload', 'material', 64, 1))

    def test_later_batch_conflict_preserves_original_record_and_capacity(self) -> None:
        with TemporaryDirectory(prefix='actql-python-reserved-cas-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                observation = self.original(store)
                store.compare_exchange('index', None, b'original index')
                queries: list[str] = []
                store._connection.set_trace_callback(queries.append)
                self.assertIsNone(store.compare_exchange_many((
                    ByteWrite('material', 0, b'next'), ByteWrite('index', None, b'wrong'),
                ), capacity=observation))
                self.assertEqual(self.mutations(queries), [])
                self.assertEqual(store.read('material').generation, 0)
                self.assertEqual(store.read('index'), StoredBytes(0, b'original index'))
                self.assertEqual(store.read_capacity('publication_payload', 'material'), observation)

    def test_original_key_and_valid_amounts_are_required_before_sql(self) -> None:
        with TemporaryDirectory(prefix='actql-python-reserved-cas-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                observation = self.original(store)
                queries: list[str] = []
                store._connection.set_trace_callback(queries.append)
                for action in (
                    lambda: store.compare_exchange_reserved(ByteWrite('other', 0, b'next'), observation),
                    lambda: store.compare_exchange_reserved(ByteWrite('material', 0, b'next'), None),
                    lambda: store.compare_exchange_reserved(ByteWrite('material', 0, b'next'),
                        CapacityReservation('publication_payload', 'material', True, 1)),
                    lambda: store.compare_exchange_many((ByteWrite('material', 0, b'next'),),
                        capacity=CapacityReservation('publication_payload', 'material', 64, -1)),
                ):
                    with self.assertRaises(ValueError):
                        action()
                self.assertEqual(queries, [])

    def test_lost_commit_ack_keeps_original_observation_without_second_update(self) -> None:
        class LostCommit(sqlite3.Connection):
            lose = False
            updates = 0

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if sql.startswith('UPDATE core_bytes'):
                    self.updates += 1
                result = super().execute(sql, *args, **kwargs)
                if self.lose and sql == 'COMMIT':
                    self.lose = False
                    raise OSError('independent capacity-bound commit acknowledgement loss')
                return result

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-python-reserved-cas-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostCommit}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    observation = self.original(store)
                    write = ByteWrite('material', 0, b'next')
                    store._connection.lose = True
                    with self.assertRaises(OSError):
                        store.compare_exchange_reserved(write, observation)
                    self.assertEqual(store.read_exchange(write), StoredBytes(1, b'next'))
                    self.assertEqual(store.read_capacity('publication_payload', 'material'), observation)
                    self.assertEqual(store._connection.updates, 1)
