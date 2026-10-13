"""Actual allocation-metadata CAS with current/record/capacity SQL fences."""
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import ByteWrite, LocalStorageCommitUnknown
import test_local_capacity_current as capacity_fixture


class AttachedCurrentTests(unittest.TestCase):
    def fixture(self):
        fixture = capacity_fixture.CapacityCurrentTests()
        self.addCleanup(fixture.doCleanups)
        store, core, binding, original = fixture.fixture()
        fixture.reserve(store, binding, original)
        capacity = store.read_capacity('publication_payload', original.key)
        write = ByteWrite(store.namespaced_key('publication_payload_allocation', 'original'), None, b'original Core allocation')
        return store, core, binding, original, capacity, write

    def invoke(self, store, binding, original, capacity, write, inspect=None):
        with binding.fenced() as metadata:
            return store.compare_exchange_attached_inspected(write, original, capacity, metadata,
                inspect=inspect or (lambda reader: binding.inspect_reader(reader, lambda _: None)),
                current=binding.current)

    def test_same_current_transaction_attaches_original_metadata_without_advancing_parent(self):
        store, core, binding, original, capacity, write = self.fixture()
        def inspect(reader):
            def check(_):
                self.assertTrue(store._connection.in_transaction)
                self.assertIs(core._journal_callbacks(binding._current.ticket).reader, reader)
            binding.inspect_reader(reader, check)
        self.assertEqual(self.invoke(store, binding, original, capacity, write, inspect), 0)
        self.assertEqual(store.read(write.key).payload, write.payload)
        self.assertEqual(store.read(original.key).generation, 0)
        self.assertEqual(store.read_capacity(capacity.namespace, capacity.key), capacity)

    def test_changed_parent_or_capacity_leaves_allocation_absent(self):
        store, _, binding, original, capacity, write = self.fixture()
        store.compare_exchange(original.key, 0, b'changed original')
        self.assertIsNone(self.invoke(store, binding, original, capacity, write,
            lambda _: self.fail('Changed original reached Core')))
        self.assertIsNone(store.read(write.key))

    def test_commit_reply_loss_preserves_same_store_and_actual_allocated_bytes(self):
        store, _, binding, original, capacity, write = self.fixture()
        actual = store._connection
        class LostReply:
            @property
            def in_transaction(self): return actual.in_transaction
            def execute(self, sql, *args):
                result = actual.execute(sql, *args)
                if sql == 'COMMIT': raise OSError('original allocation reply lost')
                return result
        with patch.object(store, '_connection', LostReply()):
            with self.assertRaises(LocalStorageCommitUnknown) as failure:
                self.invoke(store, binding, original, capacity, write)
        self.assertIs(failure.exception.cleanup_store, store)
        self.assertEqual(store.read(write.key).payload, write.payload)
        self.assertEqual(store.read_capacity(capacity.namespace, capacity.key), capacity)


if __name__ == '__main__':
    unittest.main()
