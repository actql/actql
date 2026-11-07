"""Closed SQLite inventory comparisons, not adoption or authorization evidence."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import ByteFence, LocalByteStore, LocalStorageError


_FENCES = (ByteFence('control', 0, b'original'),)


class ClosedInventoryTests(unittest.TestCase):
    def fixture(self):
        temporary = TemporaryDirectory(prefix='actql-closed-inventory-')
        self.addCleanup(temporary.cleanup)
        store = LocalByteStore(Path(temporary.name) / 'store.sqlite3', max_records=16,
                               max_record_bytes=64, max_payload_bytes=256)
        self.addCleanup(store.close)
        expected = (('a', b'first'), ('b:colon', b'second'), ('c', b'third'))
        for key, body in expected:
            store.compare_exchange(store.namespaced_key('settings', key), None, body)
        store.compare_exchange('control', None, b'original')
        observations = []
        def current():
            observations.append(True)
        return store, expected, observations, current

    def test_complete_inventory_groups_current_but_keeps_every_row_and_eof(self):
        store, expected, observations, current = self.fixture()
        readers = []
        queries = []
        original = type(store._physical).scan_range
        def scan(database, *args, **kwargs):
            queries.append(args)
            return original(database, *args, **kwargs)
        def inspect(reader):
            readers.append(reader)
            before = len(observations)
            self.assertIsNone(reader.check_inventory(reader, 'settings', expected, current))
            self.assertEqual(len(observations) - before, 2)
        before = store._connection.total_changes
        with patch.object(type(store._physical), 'scan_range', scan):
            store.inspect_namespaces(_FENCES, inspect=inspect, current=current)
        self.assertEqual(len(queries), len(expected) + 1)
        self.assertEqual(store._connection.total_changes, before)
        self.assertFalse(store._connection.in_transaction)
        with self.assertRaises(ValueError):
            readers[0].check_inventory(readers[0], 'settings', expected, current)

    def test_independent_physical_supplier_retains_per_row_current_checks(self):
        store, expected, observations, current = self.fixture()
        original = store._physical
        class PhysicalPort:
            def __getattr__(self, name):
                return getattr(original, name)
        store._physical = PhysicalPort()
        def inspect(reader):
            before = len(observations)
            reader.check_inventory(reader, 'settings', expected, current)
            self.assertEqual(len(observations) - before, 2 + 2 * (len(expected) + 1))
        store.inspect_namespaces(_FENCES, inspect=inspect, current=current)

    def test_missing_extra_generation_and_body_changes_are_not_complete(self):
        for mode in ('missing', 'extra', 'generation', 'body'):
            with self.subTest(mode=mode):
                store, expected, _, current = self.fixture()
                key = store.namespaced_key('settings', 'b:colon')
                if mode == 'missing':
                    store._connection.execute('DELETE FROM core_bytes WHERE key=?', (key,))
                elif mode == 'extra':
                    store.compare_exchange(store.namespaced_key('settings', 'z'), None, b'extra')
                else:
                    store.compare_exchange(key, 0, b'second' if mode == 'generation' else b'changed')
                def inspect(reader):
                    reader.check_inventory(reader, 'settings', expected, current)
                    self.fail('Changed inventory escaped')
                with self.assertRaises(LocalStorageError):
                    store.inspect_namespaces(_FENCES, inspect=inspect, current=current)
                self.assertFalse(store._connection.in_transaction)

    def test_swallowed_reentry_foreign_thread_and_copied_reader_latch_failure(self):
        for mode in ('reentry', 'thread', 'copy'):
            with self.subTest(mode=mode):
                store, expected, _, current = self.fixture()
                original = type(store._physical).scan_range
                readers, errors = [], []
                def nested():
                    reader = readers[0]
                    try:
                        reader.check_inventory(copy.copy(reader) if mode == 'copy' else reader,
                                               'settings', expected, current)
                    except ValueError as error:
                        errors.append(error)
                def scan(database, *args, **kwargs):
                    if mode == 'thread':
                        thread = Thread(target=nested); thread.start(); thread.join()
                    else:
                        nested()
                    return original(database, *args, **kwargs)
                def inspect(reader):
                    readers.append(reader)
                    reader.check_inventory(reader, 'settings', expected, current)
                    self.fail('Swallowed failure escaped')
                with patch.object(type(store._physical), 'scan_range', scan):
                    with self.assertRaises(ValueError):
                        store.inspect_namespaces(_FENCES, inspect=inspect, current=current)
                self.assertTrue(errors)
                self.assertFalse(store._connection.in_transaction)

    def test_current_callbacks_cannot_reenter_or_swallow_final_failure(self):
        for at_final in (False, True):
            with self.subTest(at_final=at_final):
                store, expected, _, _ = self.fixture()
                readers, failures = [], []
                calls = 0
                def current():
                    nonlocal calls
                    if not readers:
                        return
                    calls += 1
                    if calls == (2 if at_final else 1):
                        reader = readers[0]
                        try:
                            reader.check_inventory(reader, 'settings', expected, current)
                        except ValueError as error:
                            failures.append(error)
                def inspect(reader):
                    readers.append(reader)
                    try:
                        reader.check_inventory(reader, 'settings', expected, current)
                    except ValueError as error:
                        self.assertIs(error, failures[0])
                        raise
                    self.fail('Failed final current callback escaped')
                with self.assertRaises(ValueError):
                    store.inspect_namespaces(_FENCES, current=current, inspect=inspect)
                self.assertEqual(len(failures), 1)
                self.assertFalse(store._connection.in_transaction)

    def test_sql_exception_is_preserved_without_fallback_or_retry(self):
        store, expected, _, current = self.fixture()
        original = OSError('original inventory IO failed')
        with patch.object(type(store._physical), 'scan_range', side_effect=original) as query:
            with self.assertRaises(OSError) as raised:
                store.inspect_namespaces(_FENCES, current=current, inspect=lambda reader:
                    reader.check_inventory(reader, 'settings', expected, current))
        self.assertIs(raised.exception, original)
        self.assertEqual(query.call_count, 1)
        self.assertFalse(store._connection.in_transaction)

    def test_row_and_byte_budgets_remain_cumulative_in_same_reader(self):
        for budget in ('rows', 'bytes'):
            with self.subTest(budget=budget):
                store, expected, _, current = self.fixture()
                if budget == 'rows':
                    store._max_inspection_queries = len(expected)
                else:
                    store._max_payload_bytes = sum(len(body) for _, body in expected) - 1
                with self.assertRaises(LocalStorageError):
                    store.inspect_namespaces(_FENCES, current=current, inspect=lambda reader:
                        reader.check_inventory(reader, 'settings', expected, current))
                self.assertFalse(store._connection.in_transaction)


if __name__ == '__main__':
    unittest.main()
