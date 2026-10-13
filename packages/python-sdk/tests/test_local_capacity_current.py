"""Actual capacity/current SQL transactions; no Core state or publication ACK."""
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import ByteFence, ByteWrite, CapacityReservation, LocalStorageCommitUnknown, LocalStorageError
import test_local_host_binding as binding_fixture


class CapacityCurrentTests(unittest.TestCase):
    def fixture(self):
        values = binding_fixture.OriginalHostBindingTests.fixture(self)
        store, core, binding = values[1], values[2], values[-1]
        key = store.namespaced_key('payload_record', 'original')
        raw = b'original Core Intent e\xcc\x81/~\r\n'
        store.compare_exchange(key, None, raw)
        return store, core, binding, ByteFence(key, 0, raw)

    def reserve(self, store, binding, original, *, inspect=None, maximum=128):
        with binding.fenced() as metadata:
            return store.reserve_capacity_inspected('publication_payload', original.key,
                64, 1, maximum, 2, (*metadata, original),
                inspect=inspect or (lambda reader: binding.inspect_reader(reader, lambda _: None)),
                current=binding.current)

    def test_reservation_inspection_and_amounts_share_original_write_snapshot(self):
        store, core, binding, original = self.fixture()
        observed = []
        def inspect(reader):
            def verify(_):
                self.assertTrue(store._connection.in_transaction)
                self.assertIs(core._journal_callbacks(binding._current.ticket).reader, reader)
                observed.append(store._read_bytes_locked(original.key))
            binding.inspect_reader(reader, verify)
        self.assertTrue(self.reserve(store, binding, original, inspect=inspect))
        self.assertFalse(self.reserve(store, binding, original))
        capacity = store.read_capacity('publication_payload', original.key)
        self.assertEqual((capacity.reserved_bytes, capacity.reserved_objects), (64, 1))
        self.assertEqual(observed[0].payload, original.payload)
        self.assertEqual(store.read(original.key).generation, 0)

    def test_changed_record_or_current_cannot_reserve(self):
        store, core, binding, original = self.fixture()
        store.compare_exchange(original.key, 0, b'foreign record')
        with self.assertRaises(LocalStorageError): self.reserve(store, binding, original)
        self.assertIsNone(store.read_capacity('publication_payload', original.key))
        with patch.object(core, 'bind_host_current', side_effect=OSError('current unavailable')):
            current = ByteFence(original.key, 1, b'foreign record')
            with self.assertRaisesRegex(OSError, 'current unavailable'):
                self.reserve(store, binding, current)
        self.assertIsNone(store.read_capacity('publication_payload', original.key))

    def test_existing_capacity_formula_is_not_relaxed(self):
        store, _, binding, original = self.fixture()
        with self.assertRaises(LocalStorageError): self.reserve(store, binding, original, maximum=63)
        self.assertIsNone(store.read_capacity('publication_payload', original.key))
        store.reserve_capacity('publication_payload', 'other', 100, 1, 128, 2)
        with self.assertRaises(LocalStorageError): self.reserve(store, binding, original)
        self.assertIsNone(store.read_capacity('publication_payload', original.key))

    def test_bounded_actual_capacity_observation_distinguishes_missing_and_query_failure(self):
        store, _, binding, original = self.fixture()
        self.reserve(store, binding, original)
        found = []
        with binding.fenced() as metadata:
            store.inspect_capacity_inspected('publication_payload', original.key, (*metadata, original),
                inspect=lambda reader, take: binding.inspect_reader(reader, lambda _: take()),
                consume=lambda actual: found.append(actual), current=binding.current)
        self.assertEqual(found, [CapacityReservation('publication_payload', original.key, 64, 1)])
        with patch.object(store, '_read_capacity_locked', side_effect=sqlite3.OperationalError('capacity query failed')):
            with binding.fenced() as metadata:
                with self.assertRaisesRegex(sqlite3.OperationalError, 'query failed'):
                    store.inspect_capacity_inspected('publication_payload', original.key, (*metadata, original),
                        inspect=lambda reader, take: binding.inspect_reader(reader, lambda _: take()),
                        consume=lambda _: self.fail('Query failure became absence'), current=binding.current)

    def test_reserved_cas_keeps_exact_capacity_record_and_metadata_fences(self):
        store, core, binding, original = self.fixture()
        self.reserve(store, binding, original)
        capacity = store.read_capacity('publication_payload', original.key)
        write = ByteWrite(original.key, 0, b'original Core Reserved e\xcc\x81/~')
        with binding.fenced() as metadata:
            def inspect(reader):
                binding.inspect_reader(reader, lambda _: self.assertIsNotNone(
                    core._journal_callbacks(binding._current.ticket).reader))
            self.assertEqual(store.compare_exchange_reserved_inspected(write, capacity,
                (*metadata, original), inspect=inspect, current=binding.current), 1)
        self.assertEqual(store.read_capacity(capacity.namespace, capacity.key), capacity)
        self.assertEqual(store.read(original.key).payload, write.payload)

    def test_missing_capacity_or_changed_record_rejects_cas_without_inspection(self):
        store, _, binding, original = self.fixture()
        write = ByteWrite(original.key, 0, b'candidate')
        capacity = CapacityReservation('publication_payload', original.key, 64, 1)
        with binding.fenced() as metadata:
            self.assertIsNone(store.compare_exchange_reserved_inspected(write, capacity,
                (*metadata, original), inspect=lambda _: self.fail('Missing capacity reached Core'),
                current=binding.current))
        self.assertEqual(store.read(original.key).payload, original.payload)

    def test_attempted_commit_exception_retains_same_store_and_actual_reservation(self):
        store, _, binding, original = self.fixture()
        # A proxy preserves the actual SQLite COMMIT and then loses its reply.
        actual = store._connection
        class LostReply:
            @property
            def in_transaction(self): return actual.in_transaction
            def execute(self, sql, *args):
                result = actual.execute(sql, *args)
                if sql == 'COMMIT': raise OSError('independent capacity COMMIT reply lost')
                return result
        with patch.object(store, '_connection', LostReply()):
            with self.assertRaises(LocalStorageCommitUnknown) as failure:
                self.reserve(store, binding, original)
        self.assertIs(failure.exception.cleanup_store, store)
        self.assertEqual(store.read_capacity('publication_payload', original.key).reserved_bytes, 64)
        self.assertFalse(actual.in_transaction)


if __name__ == '__main__':
    unittest.main()
