from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import ByteWrite, LocalByteStore, StoredBytes


class LocalPhysicalObservationTests(unittest.TestCase):
    def store(self, path: Path) -> LocalByteStore:
        return LocalByteStore(path, max_records=4, max_record_bytes=128,
                              max_payload_bytes=256)

    def test_exact_original_bytes_and_generation_survive_reopen(self) -> None:
        # Missing and NULL, decomposed Unicode, CRLF and byte order are fixed
        # independently. The physical adapter never parses these Core bytes.
        raw = b'{"e\xcc\x81/~":null,"absent":{},"text":"a\\r\\nb"}'
        write = ByteWrite('e\u0301/~', None, raw)
        with TemporaryDirectory(prefix='actql-local-cas-observation-') as directory:
            path = Path(directory) / 'core.sqlite'
            with self.store(path) as store:
                self.assertIsNone(store.read_exchange(write))
                self.assertEqual(store.compare_exchange(write.key, None, raw), 0)
            with self.store(path) as store:
                self.assertEqual(store.read_exchange(write), StoredBytes(0, raw))
                self.assertIsNone(store.read_exchange(ByteWrite('é/~', None, raw)))
                self.assertIsNone(store.read_exchange(ByteWrite(write.key, None, b'null')))

    def test_lost_acknowledgement_lookup_never_repeats_the_transaction(self) -> None:
        class LostCommit(sqlite3.Connection):
            writes = 0
            lose = False

            def execute(self, sql: str, *args: object, **kwargs: object) -> sqlite3.Cursor:
                if sql.startswith(('INSERT', 'UPDATE')):
                    self.writes += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.lose:
                    self.lose = False
                    raise OSError('physical acknowledgement lost')
                return result

        connect = sqlite3.connect
        with TemporaryDirectory(prefix='actql-local-cas-loss-') as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostCommit}))):
                with self.store(Path(directory) / 'core.sqlite') as store:
                    write = ByteWrite('original', None, b'original-core-bytes')
                    store._connection.lose = True
                    with self.assertRaisesRegex(OSError, 'physical acknowledgement lost'):
                        store.compare_exchange(write.key, None, write.payload)
                    self.assertEqual(store.read_exchange(write), StoredBytes(0, write.payload))
                    self.assertEqual(store.read_exchange(write), StoredBytes(0, write.payload))
                    self.assertEqual(store._connection.writes, 1)

    def test_equal_bytes_at_a_later_generation_do_not_confirm_the_old_write(self) -> None:
        with TemporaryDirectory(prefix='actql-local-cas-revision-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                old = ByteWrite('original', None, b'fixed')
                self.assertEqual(store.compare_exchange(old.key, None, old.payload), 0)
                newer = ByteWrite(old.key, 0, old.payload)
                self.assertEqual(store.compare_exchange(newer.key, 0, newer.payload), 1)
                self.assertIsNone(store.read_exchange(old))
                self.assertEqual(store.read_exchange(newer), StoredBytes(1, b'fixed'))
                self.assertIsNone(store.read_exchange(ByteWrite('foreign', 0, b'fixed')))
                self.assertIsNone(store.read_exchange(ByteWrite(old.key, 0, b'changed')))
                self.assertEqual(store.read(old.key), StoredBytes(1, b'fixed'))

    def test_invalid_observations_fail_before_physical_read(self) -> None:
        with TemporaryDirectory(prefix='actql-local-cas-invalid-') as directory:
            with self.store(Path(directory) / 'core.sqlite') as store:
                with patch.object(store, 'read', side_effect=AssertionError('unexpected I/O')):
                    for generation in (True, -1, 2**63 - 1):
                        with self.assertRaises(ValueError):
                            store.read_exchange(ByteWrite('original', generation, b'fixed'))
                    with self.assertRaises(ValueError):
                        store.read_exchange(ByteWrite('', None, b'fixed'))
                    with self.assertRaises(ValueError):
                        store.read_exchange(ByteWrite('original', None, b'x' * 129))


if __name__ == '__main__':
    unittest.main()
