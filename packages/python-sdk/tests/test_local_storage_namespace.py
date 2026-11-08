"""Actual SQLite addresses for original Owner namespace/key and exact bytes."""
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import ByteFence, ByteWrite, LocalByteStore, LocalStorageError, StoredBytes


class LocalStorageNamespaceTests(unittest.TestCase):
    def test_fixed_utf8_length_and_non_normalization(self):
        self.assertEqual(LocalByteStore.namespaced_key('é', 'e\u0301/~\r\n'),
                         'namespace:2:é:e\u0301/~\r\n')
        self.assertNotEqual(LocalByteStore.namespaced_key('é', 'x'),
                            LocalByteStore.namespaced_key('e\u0301', 'x'))
        self.assertNotEqual(LocalByteStore.namespaced_key('a:b', 'c'),
                            LocalByteStore.namespaced_key('a', 'b:c'))

    def test_original_material_record_and_allocation_have_separate_cas(self):
        material = 'sha256:' + '3' * 64
        allocation = LocalByteStore.namespaced_key('publication_payload_allocation', material)
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=2,
                                max_record_bytes=128, max_payload_bytes=256) as store:
                self.assertEqual(store.compare_exchange(material, None, b'original-writing'), 0)
                self.assertEqual(store.compare_exchange(allocation, None, b'original-intent'), 0)
                self.assertEqual(store.compare_exchange(allocation, 0, b'original-owned'), 1)
                self.assertEqual(store.read(material), StoredBytes(0, b'original-writing'))
                self.assertEqual(store.read(allocation), StoredBytes(1, b'original-owned'))
                self.assertIsNone(store.compare_exchange(allocation, 0, b'foreign-retry'))
                self.assertEqual(store.read(allocation), StoredBytes(1, b'original-owned'))

    def test_different_namespaces_and_case_have_independent_presence(self):
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=4,
                                max_record_bytes=128, max_payload_bytes=512) as store:
                first = store.namespaced_key('allocation', 'A')
                for namespace, key in [('other', 'A'), ('allocation', 'a'), ('Allocation', 'A')]:
                    self.assertIsNone(store.read(store.namespaced_key(namespace, key)))
                self.assertEqual(store.compare_exchange(first, None, b'\x00\xff\r\n'), 0)
                for namespace, key in [('other', 'A'), ('allocation', 'a'), ('Allocation', 'A')]:
                    self.assertIsNone(store.read(store.namespaced_key(namespace, key)))
                self.assertEqual(store.read(first), StoredBytes(0, b'\x00\xff\r\n'))

    def test_same_store_total_record_limit_still_counts_namespaced_metadata(self):
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=1,
                                max_record_bytes=128, max_payload_bytes=128) as store:
                self.assertEqual(store.compare_exchange('original', None, b'writing'), 0)
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange(store.namespaced_key('allocation', 'original'), None, b'intent')
                self.assertEqual(store.read('original'), StoredBytes(0, b'writing'))

    def test_lost_ack_looks_up_same_namespaced_write_without_retry(self):
        class LostAck(sqlite3.Connection):
            writes = 0
            lose = False

            def execute(self, sql, *args, **kwargs):
                if sql.startswith('INSERT INTO core_bytes'):
                    self.writes += 1
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.lose:
                    self.lose = False
                    raise OSError('Independent namespaced commit acknowledgement lost')
                return result

        connect = sqlite3.connect
        with TemporaryDirectory() as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostAck}))):
                with LocalByteStore(Path(directory) / 'core.sqlite', max_records=2,
                                    max_record_bytes=128, max_payload_bytes=256) as store:
                    key = store.namespaced_key('publication_payload_allocation', 'original')
                    write = ByteWrite(key, None, b'original-intent')
                    store._connection.lose = True
                    with self.assertRaisesRegex(OSError, 'acknowledgement lost'):
                        store.compare_exchange(write.key, write.expected_generation, write.payload)
                    self.assertEqual(store._connection.writes, 1)
                    self.assertEqual(store.read_exchange(write), StoredBytes(0, b'original-intent'))
                    self.assertEqual(store.read_exchange(write), StoredBytes(0, b'original-intent'))
                    self.assertEqual(store._connection.writes, 1)

    def test_invalid_names_or_combined_key_bound_refuse(self):
        for namespace, key in [('', 'x'), ('x', ''), (True, 'x'), ('x', None),
                               ('x' * 513, 'x'), ('é' * 257, 'x'), ('x', 'y' * 4096)]:
            with self.assertRaises(ValueError):
                LocalByteStore.namespaced_key(namespace, key)

    def test_attached_metadata_fences_original_bytes_and_capacity_without_advancing_it(self):
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=2,
                                max_record_bytes=128, max_payload_bytes=256) as store:
                self.assertEqual(store.compare_exchange('original', None, b'writing'), 0)
                self.assertTrue(store.reserve_capacity('publication_payload', 'original', 12, 1, 12, 1))
                capacity = store.read_capacity('publication_payload', 'original')
                write = ByteWrite(store.namespaced_key('allocation', 'original'), None, b'intent')
                original = ByteFence('original', 0, b'writing')
                self.assertEqual(store.compare_exchange_attached(write, original, capacity), 0)
                self.assertEqual(store.read('original'), StoredBytes(0, b'writing'))
                self.assertEqual(store.read(write.key), StoredBytes(0, b'intent'))
                self.assertEqual(store.read_capacity('publication_payload', 'original'), capacity)

    def test_changed_missing_or_different_original_refuses_attached_write(self):
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=2,
                                max_record_bytes=128, max_payload_bytes=256) as store:
                self.assertEqual(store.compare_exchange('original', None, b'writing'), 0)
                self.assertTrue(store.reserve_capacity('publication_payload', 'original', 12, 1, 12, 1))
                capacity = store.read_capacity('publication_payload', 'original')
                write = ByteWrite(store.namespaced_key('allocation', 'original'), None, b'intent')
                for original in (ByteFence('original', 1, b'writing'),
                                 ByteFence('original', 0, b'changed')):
                    self.assertIsNone(store.compare_exchange_attached(write, original, capacity))
                    self.assertIsNone(store.read(write.key))
                    self.assertFalse(store._connection.in_transaction)
                with self.assertRaises(ValueError):
                    store.compare_exchange_attached(write, ByteFence('other', 0, b'writing'), capacity)
                self.assertTrue(store.reserve_capacity('publication_payload', 'missing', 12, 1, 24, 2))
                absent_capacity = store.read_capacity('publication_payload', 'missing')
                self.assertIsNone(store.compare_exchange_attached(write, ByteFence('missing', 0, b'writing'), absent_capacity))
                self.assertIsNone(store.read(write.key))

    def test_capacity_revocation_refuses_attachment_and_original_self_write_is_invalid(self):
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=2,
                                max_record_bytes=128, max_payload_bytes=256) as store:
                self.assertEqual(store.compare_exchange('original', None, b'writing'), 0)
                self.assertTrue(store.reserve_capacity('publication_payload', 'original', 12, 1, 12, 1))
                capacity = store.read_capacity('publication_payload', 'original')
                original = ByteFence('original', 0, b'writing')
                with self.assertRaises(ValueError):
                    store.compare_exchange_attached(ByteWrite('original', 0, b'writing'), original, capacity)
                self.assertTrue(store.release_capacity('publication_payload', 'original', 12, 1))
                write = ByteWrite(store.namespaced_key('allocation', 'original'), None, b'intent')
                self.assertIsNone(store.compare_exchange_attached(write, original, capacity))
                self.assertEqual(store.read('original'), StoredBytes(0, b'writing'))
                self.assertIsNone(store.read(write.key))

    def test_original_is_rechecked_after_transaction_begins(self):
        class ChangeAtBegin(sqlite3.Connection):
            change = False

            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if sql == 'BEGIN IMMEDIATE' and self.change:
                    self.change = False
                    super().execute("UPDATE core_bytes SET payload = x'6368616e676564' WHERE key = 'original'")
                return result

        connect = sqlite3.connect
        with TemporaryDirectory() as directory:
            with patch('actql_sdk._local_storage.sqlite3.connect',
                       side_effect=lambda *a, **k: connect(*a, **(k | {'factory': ChangeAtBegin}))):
                with LocalByteStore(Path(directory) / 'core.sqlite', max_records=2,
                                    max_record_bytes=128, max_payload_bytes=256) as store:
                    self.assertEqual(store.compare_exchange('original', None, b'writing'), 0)
                    self.assertTrue(store.reserve_capacity('publication_payload', 'original', 12, 1, 12, 1))
                    capacity = store.read_capacity('publication_payload', 'original')
                    write = ByteWrite(store.namespaced_key('allocation', 'original'), None, b'intent')
                    store._connection.change = True
                    self.assertIsNone(store.compare_exchange_attached(write, ByteFence('original', 0, b'writing'), capacity))
                    self.assertIsNone(store.read(write.key))
                    self.assertFalse(store._connection.in_transaction)
