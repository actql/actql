"""Same SQLite lookup/current snapshot; scalar Core, no full-chain adoption proof."""
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import LocalStorageError, StoredBytes
import test_local_publication_write_current as write_fixture


class PublicationReadCurrentTests(unittest.TestCase):
    def fixture(self):
        store, core, binding, originals, writes = write_fixture.PublicationWriteCurrentTests.fixture(self)
        for write in writes:
            store.compare_exchange(write.key, None, write.payload)
        return store, core, binding, originals, writes

    def invoke(self, store, binding, originals, inspect, *, namespace=None, before=None):
        with binding.fenced() as fences:
            store.inspect_publication_projected_inspected(inspect, originals, fences,
                namespace=namespace or (lambda reader, consume: binding.inspect_reader(reader, lambda _: consume())),
                current=binding.current, before_lookup=before or (lambda: None))

    def test_original_rows_and_publisher_use_same_current_reader_without_commit(self):
        store, core, binding, originals, writes = self.fixture()
        readers, observed, sql = [], [], []
        store._connection.set_trace_callback(sql.append)
        def namespace(reader, consume):
            readers.append(reader)
            binding.inspect_reader(reader, lambda _: consume())
        def before():
            self.assertIs(core._journal_callbacks(binding._current.ticket).reader, readers[0])
            self.assertTrue(store._connection.in_transaction)
        def inspect(read):
            for write in writes: read(write.key, lambda row: observed.append(row))
        self.invoke(store, binding, originals, inspect, namespace=namespace, before=before)
        self.assertEqual(observed, [StoredBytes(0, write.payload) for write in writes])
        self.assertEqual(sql.count('BEGIN'), 1)
        self.assertEqual(sql.count('ROLLBACK'), 1)
        self.assertFalse(any(q.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT')) for q in sql))
        self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)
        with self.assertRaises(ValueError): readers[0].read('public_index', 'b' * 64, lambda _: None)
        self.assertEqual(store.read_capacity(originals[0][1].namespace, originals[0][1].key), originals[0][1])

    def test_exact_missing_key_is_none_but_reader_cannot_escape_snapshot(self):
        store, _, binding, originals, _ = self.fixture()
        observed, retained = [], []
        def inspect(read):
            retained.append(read)
            read(store.namespaced_key('public_index', 'c' * 64), lambda row: observed.append(row))
        self.invoke(store, binding, originals, inspect)
        self.assertEqual(observed, [None])
        with self.assertRaises(ValueError): retained[0]('foreign', lambda _: None)
        self.assertFalse(store._connection.in_transaction)

    def test_query_failure_stays_failure_when_consumer_swallows_it(self):
        store, _, binding, originals, writes = self.fixture()
        actual_read = store._read_bytes_locked
        def fail(key, **kwargs):
            if key == writes[0].key: raise sqlite3.OperationalError('Original index lookup failed')
            return actual_read(key, **kwargs)
        def inspect(read):
            try: read(writes[0].key, lambda _: self.fail('Query failure became a row'))
            except sqlite3.OperationalError: pass
        with patch.object(store, '_read_bytes_locked', side_effect=fail):
            with self.assertRaisesRegex(sqlite3.OperationalError, 'index lookup failed'):
                self.invoke(store, binding, originals, inspect)
        self.assertFalse(store._connection.in_transaction)

    def test_missing_epoch_fence_rejects_before_original_key_or_publisher(self):
        store, _, binding, originals, _ = self.fixture()
        with binding.fenced() as fences:
            with self.assertRaisesRegex(LocalStorageError, 'required physical fences'):
                store.inspect_publication_projected_inspected(
                    lambda _: self.fail('Unfenced original key lookup'), originals, fences[:-1],
                    namespace=lambda reader, consume: binding.inspect_reader(reader, lambda _: consume()),
                    current=binding.current, before_lookup=lambda: self.fail('Unfenced publisher'))
        self.assertFalse(store._connection.in_transaction)

    def test_skipped_or_repeated_lookup_cannot_promote_complete_inspection(self):
        store, _, binding, originals, writes = self.fixture()
        for repeated in (False, True):
            def namespace(reader, consume):
                def invoke(_):
                    if repeated:
                        consume()
                        try: consume()
                        except ValueError: pass
                binding.inspect_reader(reader, invoke)
            with self.subTest(repeated=repeated), self.assertRaises(ValueError):
                self.invoke(store, binding, originals,
                    lambda read: read(writes[0].key, lambda _: None), namespace=namespace)
            self.assertFalse(store._connection.in_transaction)

    def test_zero_key_reads_cannot_be_reported_as_not_found(self):
        store, _, binding, originals, _ = self.fixture()
        with self.assertRaisesRegex(ValueError, 'Incomplete Local publication inspection'):
            self.invoke(store, binding, originals, lambda _: None)
        self.assertFalse(store._connection.in_transaction)

    def test_current_loss_during_lookup_keeps_original_bytes_and_reservations(self):
        store, _, binding, originals, writes = self.fixture()
        original_current = binding.current
        revoked = False
        def current():
            if revoked: raise PermissionError('Original publisher current was revoked')
            return original_current()
        def inspect(read):
            def consume(_):
                nonlocal revoked
                revoked = True
            read(writes[0].key, consume)
        with patch.object(binding, 'current', side_effect=current):
            with self.assertRaises(PermissionError): self.invoke(store, binding, originals, inspect)
        for write in writes: self.assertEqual(store.read(write.key), StoredBytes(0, write.payload))
        self.assertEqual(store.read_capacity(originals[0][1].namespace, originals[0][1].key), originals[0][1])
        self.assertFalse(store._connection.in_transaction)


if __name__ == '__main__':
    unittest.main()
