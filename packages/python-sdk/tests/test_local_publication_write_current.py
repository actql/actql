"""Actual same-TX SQLite/current port, scalar Core; no publication ACK evidence."""
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    ByteFence, ByteWrite, CapacityReservation, LocalStorageCommitUnknown,
    LocalStorageError, StoredBytes,
)
import test_local_host_binding as binding_fixture


class PublicationWriteCurrentTests(unittest.TestCase):
    def fixture(self):
        _, store, core, _, _, _, _, _, _, _, binding = binding_fixture.OriginalHostBindingTests.fixture(self)
        payload_key = store.namespaced_key('payload_record', 'original')
        payload = b'original sealed payload e\xcc\x81/~\r\n'
        store.compare_exchange(payload_key, None, payload)
        self.assertTrue(store.reserve_capacity('publication_payload', payload_key, 64, 1, 128, 2))
        originals = ((ByteFence(payload_key, 0, payload),
                      CapacityReservation('publication_payload', payload_key, 64, 1)),)
        writes = (ByteWrite(store.namespaced_key('publication_contract', 'sha256:' + 'a' * 64),
                            None, b'original-Core-contract-e\xcc\x81\r\n'),
                  ByteWrite(store.namespaced_key('public_index', 'b' * 64),
                            None, b'sha256:' + b'a' * 64))
        return store, core, binding, originals, writes

    def invoke(self, store, binding, originals, writes, *, inspect=None, project=None, before=None):
        with binding.fenced() as fences:
            return store.store_publication_projected_inspected(
                len(writes), project or (lambda ordinal, consume: consume(writes[ordinal])),
                originals, fences,
                inspect=inspect or (lambda reader, consume: binding.inspect_reader(reader, lambda _: consume())),
                current=binding.current, before_commit=before or (lambda: None))

    def assert_absent(self, store, writes):
        for write in writes: self.assertIsNone(store.read(write.key))
        self.assertFalse(store._connection.in_transaction)

    def test_projection_and_publisher_share_exact_original_reader_before_commit(self):
        store, core, binding, originals, writes = self.fixture()
        readers, phases = [], []
        def inspect(reader, consume):
            readers.append(reader)
            binding.inspect_reader(reader, lambda _: consume())
        def protected(phase):
            callbacks = core._journal_callbacks(binding._current.ticket)
            self.assertIs(callbacks.reader, readers[0])
            self.assertTrue(store._connection.in_transaction)
            phases.append(phase)
        def project(ordinal, consume):
            protected(ordinal)
            consume(writes[ordinal])
        self.assertEqual(self.invoke(store, binding, originals, writes, inspect=inspect,
            project=project, before=lambda: protected('publisher')), (0, 0))
        self.assertEqual(phases, [0, 1, 'publisher'])
        for write in writes: self.assertEqual(store.read(write.key), StoredBytes(0, write.payload))
        self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)
        with self.assertRaises(ValueError): readers[0].read('public_index', 'b' * 64, lambda _: None)
        self.assertEqual(store.read_capacity(originals[0][1].namespace, originals[0][1].key), originals[0][1])

    def test_missing_epoch_fence_rejects_before_projection_or_publisher(self):
        store, _, binding, originals, writes = self.fixture()
        with binding.fenced() as fences:
            with self.assertRaisesRegex(LocalStorageError, 'required physical fences'):
                store.store_publication_projected_inspected(len(writes),
                    lambda *_: self.fail('Missing epoch reached projection'), originals, fences[:-1],
                    inspect=lambda reader, consume: binding.inspect_reader(reader, lambda _: consume()),
                    current=binding.current, before_commit=lambda: self.fail('Missing epoch reached publisher'))
        self.assert_absent(store, writes)

    def test_swallowed_projection_failure_cannot_commit_a_prefix(self):
        store, _, binding, originals, writes = self.fixture()
        def project(ordinal, consume):
            consume(writes[ordinal])
            raise OSError('Original projected transport failed')
        def inspect(reader, consume):
            def swallowed(_):
                try: consume()
                except OSError: pass
            binding.inspect_reader(reader, swallowed)
        with self.assertRaisesRegex(OSError, 'transport failed'):
            self.invoke(store, binding, originals, writes, inspect=inspect, project=project,
                        before=lambda: self.fail('Failed projection reached publisher'))
        self.assert_absent(store, writes)

    def test_repeated_batch_consumption_is_latched_even_when_caught(self):
        store, _, binding, originals, writes = self.fixture()
        def inspect(reader, consume):
            def twice(_):
                consume()
                try: consume()
                except ValueError: pass
            binding.inspect_reader(reader, twice)
        with self.assertRaisesRegex(ValueError, 'already consumed'):
            self.invoke(store, binding, originals, writes, inspect=inspect)
        self.assert_absent(store, writes)

    def test_metadata_fence_cannot_be_used_as_a_projection_target(self):
        store, _, binding, originals, writes = self.fixture()
        with binding.fenced() as fences:
            changed = ByteWrite(fences[0].key, None, fences[0].payload)
            with self.assertRaisesRegex(ValueError, 'original Local physical projection key'):
                store.store_publication_projected_inspected(1, lambda _, consume: consume(changed),
                    originals, fences,
                    inspect=lambda reader, consume: binding.inspect_reader(reader, lambda _: consume()),
                    current=binding.current, before_commit=lambda: self.fail('Fence write reached publisher'))
        self.assert_absent(store, writes)

    def test_commit_reply_loss_retains_same_store_and_never_repeats_writes(self):
        class LostAck(sqlite3.Connection):
            armed = False
            inserts = 0
            def execute(self, sql, *args, **kwargs):
                if self.armed and sql.startswith('INSERT INTO core_bytes'): self.inserts += 1
                result = super().execute(sql, *args, **kwargs)
                if self.armed and sql == 'COMMIT':
                    self.armed = False
                    raise OSError('Original projected ACK lost')
                return result
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': LostAck}))):
            store, _, binding, originals, writes = self.fixture()
            store._connection.armed = True
            with self.assertRaises(LocalStorageCommitUnknown) as failure:
                self.invoke(store, binding, originals, writes)
            self.assertIs(failure.exception.cleanup_store, store)
            self.assertIsInstance(failure.exception.__cause__, OSError)
            self.assertEqual(store._connection.inserts, 2)
            for write in writes: self.assertEqual(store.read(write.key), StoredBytes(0, write.payload))
            self.assertEqual(store._connection.inserts, 2)
            self.assertFalse(store._connection.in_transaction)

    def test_postcommit_current_failure_is_unknown_and_keeps_saved_original_bytes(self):
        store, _, binding, originals, writes = self.fixture()
        current = binding.current
        def after_commit():
            if not store._connection.in_transaction:
                raise PermissionError('Original current changed after COMMIT')
            return current()
        with patch.object(binding, 'current', side_effect=after_commit):
            with self.assertRaises(LocalStorageCommitUnknown) as failure:
                self.invoke(store, binding, originals, writes)
        self.assertIs(failure.exception.cleanup_store, store)
        self.assertIsInstance(failure.exception.__cause__, PermissionError)
        for write in writes: self.assertEqual(store.read(write.key), StoredBytes(0, write.payload))
        self.assertFalse(store._connection.in_transaction)


if __name__ == '__main__':
    unittest.main()
