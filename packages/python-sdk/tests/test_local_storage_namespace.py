"""Actual SQLite addresses for original Owner namespace/key and exact bytes."""
import json
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import (
    ByteFence, ByteWrite, LocalByteStore, LocalStorageError, StoredBytes,
    LocalRunDefinitionConflict, LocalStorageCommitUnknown, _DurableStoreLimits, _RUN_DEFINITION_OWNER, _TASK_MATERIAL_COUNT,
)
from actql_sdk._local_storage_physical import _SQLiteByteDatabase


class LocalStorageNamespaceTests(unittest.TestCase):
    def test_ordinary_reader_reuses_the_opened_catalog_across_fresh_reads(self):
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with LocalByteStore(path, ordinary=True, max_records=4,
                                max_record_bytes=128, max_payload_bytes=512) as store:
                key = store.namespaced_key('probe', 'original')
                self.assertEqual(store.compare_exchange(key, None, b'body'), 0)
                sql = []
                epochs = []

                def current():
                    return None

                def inspect(reader):
                    reader.journal_schema(reader, current)
                    self.assertEqual(reader.query_current(reader, 1, 'probe', 'original', current),
                                     ('original', StoredBytes(0, b'body')))
                    epochs.append(store._physical._snapshot_identity()[1])

                store._connection.set_trace_callback(sql.append)
                try:
                    for _ in range(2):
                        store.inspect_namespaces((ByteFence(key, 0, b'body'),),
                                                 inspect=inspect, current=current)
                finally:
                    store._connection.set_trace_callback(None)
                self.assertLess(*epochs)
                self.assertEqual(sum(statement == 'BEGIN' for statement in sql), 2)
                self.assertEqual(sum(statement == 'ROLLBACK' for statement in sql), 2)
                self.assertFalse(any(word in stmt.lower() for stmt in sql
                                     for word in ('schema_version', 'sqlite_schema', 'application_id')))

    def test_bound_key_queries_reuse_the_same_prepared_statements(self):
        prefix = 'namespace:5:probe:'
        logical = ("quote' nul\x00 café 東京 ?", 'x' * (4096 - len(prefix)))
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with LocalByteStore(path, ordinary=True, max_records=8,
                                max_record_bytes=128, max_payload_bytes=1024) as store:
                keys = tuple(store.namespaced_key('probe', key) for key in
                             (*logical, *(str(ordinal) for ordinal in range(6))))
                self.assertEqual(store.compare_exchange_many(tuple(
                    ByteWrite(key, None, bytes(ordinal + 1))
                    for ordinal, key in enumerate(keys))), (0,) * 8)

                physical = store._physical
                prepared = []

                def authorize(action, first, second, schema, trigger):
                    if action == sqlite3.SQLITE_SELECT:
                        prepared.append(action)
                    return sqlite3.SQLITE_OK

                store._connection.set_authorizer(authorize)
                try:
                    self.assertEqual(physical.read_header(keys[0]), (0, 1))
                    self.assertTrue(prepared)
                    count = len(prepared)
                    self.assertEqual(physical.read_header(keys[1]), (0, 2))
                    self.assertEqual(len(prepared), count)
                    for arity in range(1, 9):
                        request = keys[:arity]
                        rows = physical.read_target_headers(request)
                        self.assertEqual(sorted(rows), [
                            (ordinal, 1, 0, 'blob', ordinal + 1) for ordinal in range(arity)
                        ])
                        count = len(prepared)
                        reversed_rows = physical.read_target_headers(request[::-1])
                        self.assertEqual(sorted(reversed_rows), [
                            (ordinal, 1, 0, 'blob', arity - ordinal) for ordinal in range(arity)
                        ])
                        self.assertEqual(len(prepared), count)
                finally:
                    store._connection.set_authorizer(None)
                self.assertEqual(store.read(keys[0]), StoredBytes(0, b'\x00'))
                self.assertEqual(store.read(keys[1]), StoredBytes(0, b'\x00\x00'))

    def test_saved_run_header_reads_only_the_exact_current_run_extent(self):
        selected = 'sha256:' + 'a' * 64
        missing = 'sha256:' + 'b' * 64
        oversized = 'sha256:' + 'c' * 64
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with LocalByteStore(path, ordinary=True, max_records=4,
                                max_record_bytes=384, max_payload_bytes=768) as store:
                # Use the virtual namespace literally to keep the host wire fixed.
                namespace = 'client_sqlite_saved_run_current'
                key = store.namespaced_key('client_runs', selected)
                body = json.dumps({'value': 'sample original'}).encode()
                fences = (ByteFence('epoch', 0, b'original'),)
                self.assertEqual(store.compare_exchange_many((
                    ByteWrite('epoch', None, b'original'), ByteWrite(key, None, body),
                    ByteWrite(store.namespaced_key('client_runs_foreign', missing), None, body),
                )), (0, 0, 0))
                store._connection.execute(
                    'INSERT INTO main.core_bytes VALUES (?, 0, ?)',
                    (store.namespaced_key('client_runs', oversized), b'[' + b' ' * 383 + b']'))

                retained = []
                traces = []
                store._connection.set_trace_callback(traces.append)

                def current():
                    self.assertTrue(store._physical.in_transaction)

                def observe(logical, *, mode=1, observer=current):
                    observations = []

                    def inspect(reader):
                        retained.append(reader)
                        observations.append(reader.query_current(reader, mode, namespace, logical, observer))

                    store.inspect_namespaces(fences, inspect=inspect, current=current)
                    self.assertFalse(store._physical.in_transaction)
                    return observations[0]

                with patch.object(_SQLiteByteDatabase, 'scan_range',
                                  side_effect=AssertionError('Saved Run query fetched a body')):
                    self.assertEqual(observe(selected), (selected, StoredBytes(0, len(body).to_bytes(4, 'little'))))
                    self.assertIsNone(observe(missing))
                header_sql = [sql for sql in traces if sql.startswith('SELECT generation, length(payload)')]
                self.assertEqual(len(header_sql), 2)
                for sql, logical in zip(header_sql, (selected, missing)):
                    physical_key = store.namespaced_key('client_runs', logical)
                    self.assertTrue(sql.endswith(f"WHERE key = '{physical_key}'"), sql)
                with self.assertRaisesRegex(ValueError, 'not active'):
                    retained[0].query_current(retained[0], 1, namespace, selected, current)
                with self.assertRaisesRegex(ValueError, 'Saved Run header query'):
                    observe(selected, mode=0)
                with self.assertRaisesRegex(ValueError, 'Saved Run header query'):
                    observe('sha256:' + 'A' * 64)
                with self.assertRaisesRegex(LocalStorageError, 'Saved Run header is invalid'):
                    observe(oversized)
                with self.assertRaisesRegex(ValueError, 'Saved Run header query'):
                    store.compare_exchange_many_inspected((ByteWrite('fresh', None, b'x'),), fences,
                        inspect=lambda reader: reader.query_current(reader, 1, namespace, selected, current),
                        current=current)
                self.assertIsNone(store.read('fresh'))

                successor = body + b' '
                self.assertEqual(store.compare_exchange(key, 0, successor), 1)
                self.assertEqual(observe(selected),
                                 (selected, StoredBytes(1, len(successor).to_bytes(4, 'little'))))
                failure = RuntimeError('Original Saved read revoked during observation')
                calls = 0

                def revoked():
                    nonlocal calls
                    calls += 1
                    if calls == 2:
                        raise failure

                with self.assertRaises(RuntimeError) as caught:
                    observe(selected, observer=revoked)
                self.assertIs(caught.exception, failure)
                self.assertEqual(calls, 2)
                self.assertFalse(store._physical.in_transaction)
                self.assertEqual(store.read(key), StoredBytes(1, successor))

    def test_definition_index_is_only_observed_after_a_physical_unique_conflict(self):
        existing = 'sha256:' + 'a' * 64
        absent = 'sha256:' + 'b' * 64
        row = json.dumps({'run_definition': json.dumps({'run_definition_cid': existing})}).encode()
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            with LocalByteStore(path, max_records=4, max_record_bytes=256,
                                max_payload_bytes=512, ordinary=True) as store:
                key = store.namespaced_key('client_runs', 'original')
                competing = store.namespaced_key('client_runs', 'competing')
                queries = []
                store._connection.set_trace_callback(queries.append)
                self.assertEqual(store.compare_exchange(key, None, row), 0)
                self.assertFalse(any('INDEXED BY' in sql for sql in queries))
                self.assertIsNone(store.compare_exchange(key, None, row))
                self.assertIsNone(store.compare_exchange(key, 1, row))
                with self.assertRaises(LocalRunDefinitionConflict) as caught:
                    store.compare_exchange_many((ByteWrite('first', None, b'prefix'),
                                                 ByteWrite(competing, None, row)))
                self.assertEqual(caught.exception.__cause__.__cause__.sqlite_errorcode,
                                 sqlite3.SQLITE_CONSTRAINT_UNIQUE)
                self.assertFalse(store._physical.in_transaction)
                self.assertIsNone(store.read('first'))
                self.assertIsNone(store.read(competing))
                self.assertEqual(caught.exception.definition, existing)

                def current():
                    return None

                def read_owner(definition):
                    observations = []
                    store.inspect_namespaces((ByteFence(key, 0, row),), current=current,
                        inspect=lambda reader: observations.append(reader.query_current(
                            reader, 1, _RUN_DEFINITION_OWNER, definition, current)))
                    return observations[0]

                self.assertEqual(read_owner(existing), ('original', StoredBytes(0, row)))
                self.assertIsNone(read_owner(absent))
                with self.assertRaises(ValueError):
                    read_owner('sha256:' + 'X' * 64)
                store._connection.execute('DROP INDEX main.actql_client_run_definition_unique')
                with self.assertRaisesRegex(sqlite3.OperationalError, 'no such index'):
                    read_owner(existing)

    def test_current_reader_counts_only_unique_task_keys_without_copying_bodies(self):
        def current():
            return None

        def observe(store, fence, expected):
            seen = []
            def inspect(reader):
                seen.append(reader.query_current(reader, 1, _TASK_MATERIAL_COUNT, expected, current))
            store.inspect_namespaces((fence,), inspect=inspect, current=current)
            return seen[0]

        with TemporaryDirectory() as directory:
            path = Path(directory) / 'core.sqlite'
            options = dict(max_records=4, max_record_bytes=128, max_payload_bytes=256)
            with LocalByteStore(path, **options, ordinary=True) as store:
                key = store.namespaced_key('client_task_run_materials', 'original:0')
                foreign = store.namespaced_key('client_task_run_materials_other', 'original:0')
                self.assertEqual(store.compare_exchange(key, None, b'a' * 128), 0)
                self.assertEqual(store.compare_exchange(foreign, None, b'b' * 128), 0)
                fence = ByteFence(foreign, 0, b'b' * 128)

                with patch.object(type(store._physical), 'scan_range',
                                  side_effect=AssertionError('Task payload read')):
                    for expected, observed in [('0', b'0'), ('1', b'1'), ('2', b'0')]:
                        self.assertEqual(observe(store, fence, expected),
                                         (expected, StoredBytes(0, observed)))

                extra = store.namespaced_key('client_task_run_materials', 'unexpected:4')
                self.assertEqual(store.compare_exchange(extra, None, b'c' * 128), 0)
                self.assertEqual(observe(store, fence, '1'), ('1', StoredBytes(0, b'0')))
                self.assertEqual(observe(store, fence, '2'), ('2', StoredBytes(0, b'1')))
                for invalid in ('', '01', '-1', '１', '3073'):
                    with self.assertRaises(ValueError):
                        observe(store, fence, invalid)
                self.assertEqual(store.read(key), StoredBytes(0, b'a' * 128))

            # The exact same retained rows remain readable on the unselected port.
            with LocalByteStore(path, **options) as legacy:
                self.assertIsNone(observe(legacy, fence, '2'))

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

    def test_selected_retained_record_limit_counts_namespaced_metadata(self):
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=1,
                                max_record_bytes=128, max_payload_bytes=128,
                                durable_limits=_DurableStoreLimits(1, 128, 4)) as store:
                self.assertEqual(store.compare_exchange('original', None, b'writing'), 0)
                with self.assertRaises(LocalStorageError):
                    store.compare_exchange(store.namespaced_key('allocation', 'original'), None, b'intent')
                self.assertEqual(store.read('original'), StoredBytes(0, b'writing'))

    def test_lost_ack_looks_up_same_namespaced_write_without_retry(self):
        class LostAck(sqlite3.Connection):
            writes = 0
            lose = False

            def execute(self, sql, *args, **kwargs):
                if sql.startswith('INSERT INTO main.core_bytes'):
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
                    with self.assertRaises(LocalStorageCommitUnknown) as caught:
                        store.compare_exchange(write.key, write.expected_generation, write.payload)
                    self.assertIs(caught.exception.cleanup_store, store)
                    self.assertRegex(str(caught.exception.__cause__), 'acknowledgement lost')
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
