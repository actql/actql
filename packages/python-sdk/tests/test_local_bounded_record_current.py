"""Real bounded SQLite observation/current; not Core admission or Store ACK."""
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import LocalStorageError, StoredBytes
import test_local_host_binding as binding_fixture


class BoundedRecordCurrentTests(unittest.TestCase):
    def fixture(self):
        values = binding_fixture.OriginalHostBindingTests.fixture(self)
        store, core, binding = values[1], values[2], values[-1]
        key = store.namespaced_key('payload_record', 'original')
        raw = b'{"e\xcc\x81/~":null,"text":"a\\r\\nb","absent":{}}'
        store.compare_exchange(key, None, raw)
        return store, core, binding, key, raw

    def invoke(self, store, binding, key, consume, *, maximum=64, inspect=None):
        with binding.fenced() as fences:
            store.inspect_bounded_record_inspected(key, maximum, fences,
                inspect=inspect or (lambda reader, take: binding.inspect_reader(reader, lambda _: take())),
                consume=consume, current=binding.current)

    def test_exact_row_is_consumed_under_original_current_snapshot_without_writes(self):
        store, core, binding, key, raw = self.fixture()
        changes = store._connection.total_changes
        values = []
        def consume(actual):
            self.assertIsNotNone(core._journal_callbacks(binding._current.ticket).reader)
            self.assertTrue(store._connection.in_transaction)
            values.append(actual)
        self.invoke(store, binding, key, consume)
        self.assertEqual(values, [StoredBytes(0, raw)])
        self.assertEqual(changes, store._connection.total_changes)
        self.assertFalse(store._connection.in_transaction)

    def test_missing_and_sql_failure_are_distinct_observations(self):
        store, _, binding, _, _ = self.fixture()
        missing = store.namespaced_key('payload_record', 'missing')
        values = []
        self.invoke(store, binding, missing, lambda actual: values.append(actual))
        self.assertEqual(values, [None])
        read = store._read_bytes_locked
        def broken(key, **kwargs):
            if key == missing:
                raise sqlite3.OperationalError('independent payload query failure')
            return read(key, **kwargs)
        with patch.object(store, '_read_bytes_locked', side_effect=broken):
            with self.assertRaisesRegex(sqlite3.OperationalError, 'query failure'):
                self.invoke(store, binding, missing, lambda _: self.fail('Query failure became absence'))
        self.assertFalse(store._connection.in_transaction)

    def test_sql_bounds_large_retained_row_before_python_copy(self):
        store, _, binding, key, raw = self.fixture()
        store.compare_exchange(key, 0, raw * 100)
        queries = []
        store._connection.set_trace_callback(queries.append)
        with self.assertRaises(LocalStorageError):
            self.invoke(store, binding, key, lambda _: self.fail('Oversized row reached consumer'), maximum=8)
        self.assertTrue(any('CASE WHEN length(payload) <= 8 THEN payload ELSE NULL END' in q for q in queries))
        self.assertFalse(store._connection.in_transaction)

    def test_skipped_repeated_or_swallowed_consumption_cannot_return_success(self):
        for shape in ('skip', 'repeat', 'swallow'):
            with self.subTest(shape=shape):
                store, _, binding, key, _ = self.fixture()
                def inspect(reader, take):
                    def action(_):
                        if shape == 'skip': return
                        if shape == 'swallow':
                            try: take()
                            except OSError: pass
                        else:
                            take()
                            try: take()
                            except ValueError: pass
                    binding.inspect_reader(reader, action)
                def consume(_):
                    if shape == 'swallow': raise OSError('independent original consumer failure')
                with self.assertRaises((OSError, ValueError)):
                    self.invoke(store, binding, key, consume, inspect=inspect)
                self.assertFalse(store._connection.in_transaction)

    def test_changed_current_and_invalid_limit_reject_without_consumer(self):
        store, core, binding, key, _ = self.fixture()
        with patch.object(core, 'bind_host_current', side_effect=OSError('original current unavailable')):
            with self.assertRaisesRegex(OSError, 'current unavailable'):
                self.invoke(store, binding, key, lambda _: self.fail('Changed current reached consumer'))
        for limit in (True, 0, store._max_record_bytes + 1):
            with self.assertRaises(ValueError):
                self.invoke(store, binding, key, lambda _: self.fail('Invalid limit reached consumer'), maximum=limit)


if __name__ == '__main__':
    unittest.main()
