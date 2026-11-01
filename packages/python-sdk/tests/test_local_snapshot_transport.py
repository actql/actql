"""Actual SQLite frame counters with explicit Core ports, not installed authority."""
from pathlib import Path
import json
from tempfile import TemporaryDirectory
from unittest.mock import patch
import unittest
from dataclasses import replace
from threading import Thread

from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_storage import ByteFence, LocalByteStore
import test_local_original_operation_current as operation_fixture
import test_local_submission_lookup as lookup_fixture


class SnapshotTransportTests(unittest.TestCase):
    def test_original_fence_packet_matches_actual_rows_with_two_currents_and_no_row_copy(self):
        with TemporaryDirectory(prefix='actql-original-fence-packet-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            namespace = b'publication_contract'
            expected = [['first', '0', '{"n":1}'], ['second', '0', 'original\r\nbytes']]
            for name, _, body in expected:
                store.compare_exchange(store.namespaced_key(namespace.decode(), name), None,
                                       body.encode())
            currents = []
            def current(): currents.append(None)
            callbacks = _JournalCallbacks(current, store)
            def inspect(reader):
                callbacks.reader = reader
                for change in (False, True):
                    packet = json.dumps(expected).encode() if not change else json.dumps(
                        [['first', '1', '{"n":1}'], expected[1]]).encode()
                    self.assertEqual(callbacks.begin(2, len(namespace), len(packet)), 0)
                    self.assertEqual(callbacks.query_copy(0, namespace + packet),
                                     len(namespace) + len(packet))
                    before = len(currents)
                    with patch.object(store._physical, '_match_rows', wraps=store._physical._match_rows) as match:
                        self.assertEqual(callbacks.query(), int(change))
                        self.assertEqual(match.call_count, 1)
                    self.assertEqual(len(currents) - before, 2)
                    self.assertIsNone(callbacks.row)
                    self.assertIsNone(callbacks.request)
                    self.assertEqual(callbacks.release(), 0)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=current)
            self.assertFalse(store._physical.in_transaction)

    def test_original_fence_packet_charges_each_row_and_poisoning_survives_swallow(self):
        from actql_sdk._local_storage import LocalStorageError
        with TemporaryDirectory(prefix='actql-original-fence-capacity-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384, max_inspection_queries=1)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            namespace = b'publication_contract'
            packet = b'[["first","0","a"],["second","0","b"]]'
            callbacks = _JournalCallbacks(lambda: None, store)
            failures = []
            def inspect(reader):
                callbacks.reader = reader
                self.assertEqual(callbacks.begin(2, len(namespace), len(packet)), 0)
                self.assertEqual(callbacks.query_copy(0, namespace + packet), len(namespace + packet))
                with patch.object(store._physical, '_match_rows', wraps=store._physical._match_rows) as match:
                    self.assertEqual(callbacks.query(), -41)
                    self.assertEqual(match.call_count, 0)
                failures.append(callbacks.failure)
                self.assertIsInstance(callbacks.failure, LocalStorageError)
                with self.assertRaises(LocalStorageError) as same:
                    reader.current()
                self.assertIs(same.exception, callbacks.failure)
            with self.assertRaises(LocalStorageError) as original:
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)
            self.assertIs(original.exception, failures[0])
            self.assertFalse(store._physical.in_transaction)

    def test_original_fence_packet_keeps_current_changes_at_entry_and_return(self):
        from actql_sdk._local_storage import LocalStorageError
        for stop in (1, 2):
            with self.subTest(stop=stop), TemporaryDirectory(prefix='actql-original-fence-current-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                store.compare_exchange(store.namespaced_key('publication_contract', 'first'), None, b'a')
                calls, armed = [], []
                def current():
                    if armed:
                        calls.append(None)
                        if len(calls) == stop:
                            store._connection.execute('UPDATE core_bytes SET generation=1 WHERE key=?', ('epoch',))
                callbacks = _JournalCallbacks(current, store)
                namespace = b'publication_contract';packet = b'[["first","0","a"]]'
                def inspect(reader):
                    callbacks.reader = reader
                    self.assertEqual(callbacks.begin(2, len(namespace), len(packet)), 0)
                    self.assertEqual(callbacks.query_copy(0, namespace + packet), len(namespace + packet))
                    armed.append(None)
                    self.assertEqual(callbacks.query(), -41)
                    armed.clear()
                    self.assertIsInstance(callbacks.failure, LocalStorageError)
                with self.assertRaises(LocalStorageError):
                    store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                        inspect=inspect, current=current)
                self.assertEqual(len(calls), stop)
                self.assertIsNone(callbacks.row)
                self.assertEqual(store.read('epoch').generation, 0)

    def test_original_fence_packet_unsupported_adapter_selects_old_scalar_before_row_io(self):
        with TemporaryDirectory(prefix='actql-original-fence-scalar-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('publication_contract', 'first'), None, b'a')
            database = store._physical
            class ScalarPhysical:
                # Explicit physical-adapter port, not an actual Native backend.
                def __getattr__(self, name): return getattr(database, name)
            store._physical = ScalarPhysical()
            callbacks = _JournalCallbacks(lambda: None, store)
            namespace = b'publication_contract';packet = b'[["first","0","a"]]'
            def inspect(reader):
                callbacks.reader = reader
                self.assertIsNone(reader.match_rows_current)
                self.assertEqual(callbacks.begin(2, len(namespace), len(packet)), 0)
                self.assertEqual(callbacks.query_copy(0, namespace + packet), len(namespace + packet))
                with patch.object(database, 'scan_range', wraps=database.scan_range) as query:
                    self.assertEqual(callbacks.query(), 2)
                    self.assertEqual(query.call_count, 0)
                self.assertIsNone(callbacks.failure)
                self.assertEqual(callbacks.release(), 0)
                self.assertEqual(callbacks.begin(1, len(namespace), 5), 0)
                self.assertEqual(callbacks.query_copy(0, namespace + b'first'), len(namespace) + 5)
                self.assertEqual(callbacks.query(), 0)
                self.assertEqual(callbacks.row[1].payload, b'a')
                self.assertEqual(callbacks.release(), 0)
            try:
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)
            finally:
                store._physical = database

    def test_original_journal_row_transfer_has_only_query_entry_and_return_currents(self):
        with TemporaryDirectory(prefix='actql-direct-journal-row-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            calls = []
            def current(): calls.append(None)
            callbacks = _JournalCallbacks(current, store)
            def inspect(reader):
                callbacks.reader = reader
                self.assertEqual(callbacks.begin(1, 8, 3), 0)
                self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                before = len(calls)
                self.assertEqual(callbacks.query(), 0)
                self.assertEqual(len(calls) - before, 2)
                self.assertEqual(callbacks.row[0], b'one')
                self.assertEqual(callbacks.row_copy(1, 0, 12), b'original-row')
                self.assertEqual(callbacks.release(), 0)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=current)
            self.assertFalse(store._physical.in_transaction)

    def test_semantic_current_reuses_only_unchanged_sql_snapshot_and_keeps_each_current(self):
        with TemporaryDirectory(prefix='actql-same-sql-snapshot-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            currents = []
            def current(): currents.append(True)
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                before = len(currents)
                with patch.object(store, '_read_bytes_locked', wraps=store._read_bytes_locked) as sql:
                    for _ in range(5):
                        reader.check_fences(reader, (ByteFence('epoch', 0, b'original-epoch'),))
                    self.assertEqual(len(currents) - before, 5)
                    self.assertEqual(sql.call_count, 0)
                with patch.object(store, '_read_bytes_locked', wraps=store._read_bytes_locked) as sql:
                    reader.read('original', 'one', lambda _: None)
                    # The three original query boundaries still each read both
                    # sides of mutable current; no query/commit fence is removed.
                    self.assertEqual(sql.call_count, 6)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=current)

    def test_current_query_keeps_entry_and_return_currents_and_actual_row_with_same_snapshot_metadata(self):
        with TemporaryDirectory(prefix='actql-query-immutable-metadata-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=16,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            fences = tuple(ByteFence('epoch:' + str(i), 0, b'original-metadata') for i in range(7))
            for fence in fences: store.compare_exchange(fence.key, None, fence.payload)
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            currents = []
            def current(): currents.append(True)
            def inspect(reader):
                sql = []
                observed = []
                before = len(currents)
                store._connection.set_trace_callback(sql.append)
                try:
                    observed.append(reader.query_current(reader, 1, 'original', 'one', current))
                finally:
                    store._connection.set_trace_callback(None)
                self.assertEqual(len(currents) - before, 2)
                self.assertEqual(len(observed), 1)
                self.assertEqual(observed[0][0], 'one')
                self.assertEqual(observed[0][1].payload, b'original-row')
                reads = [query for query in sql if query.lstrip().upper().startswith('SELECT')]
                self.assertEqual(len(reads), 1)  # SAME actual physical row is not cached
                probes = [query for query in sql if query.startswith('PRAGMA')]
                self.assertEqual(probes, ['PRAGMA schema_version', 'PRAGMA temp.schema_version'] * 4)
            store.inspect_namespaces(fences, inspect=inspect, current=current)


    def test_consumer_query_refuses_metadata_mutation_at_each_current_boundary(self):
        from actql_sdk._local_storage import LocalStorageError
        for stop in (1, 2, 3):
            with self.subTest(stop=stop), TemporaryDirectory(prefix='actql-query-metadata-current-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
                armed, calls, rows = [], [], []
                def current():
                    if armed:
                        calls.append(True)
                        if len(calls) == stop:
                            store._connection.execute('UPDATE core_bytes SET generation=1 WHERE key=?', ('epoch',))
                def inspect(reader):
                    armed.append(True)
                    with self.assertRaises(LocalStorageError):
                        reader.read('original', 'one', rows.append)
                    armed.clear()
                    with self.assertRaises(ValueError): reader.current()
                with self.assertRaises(ValueError):
                    store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                        inspect=inspect, current=current)
                self.assertEqual(len(calls), stop)
                self.assertEqual(len(rows), int(stop == 3))
                self.assertFalse(store._physical.in_transaction)
                self.assertEqual(store.read('epoch').payload, b'original-epoch')


    def test_current_query_refreshes_changed_metadata_and_never_reuses_actual_row(self):
        with TemporaryDirectory(prefix='actql-query-fresh-row-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            key = store.namespaced_key('original', 'one')
            store.compare_exchange(key, None, b'original-row')
            def inspect(reader):
                observed = []
                def consume(row):
                    observed.append(row[1].payload)
                    store._connection.execute('UPDATE core_bytes SET payload=? WHERE key=?', (b'changed-row', key))
                with patch.object(store, '_read_bytes_locked', wraps=store._read_bytes_locked) as reads:
                    consume(reader.query_current(reader, 1, 'original', 'one', current))
                    self.assertEqual(reads.call_count, 0)  # No arbitrary callback runs within the physical query
                    observed.append(reader.query_current(reader, 1, 'original', 'one', current)[1].payload)
                    self.assertEqual(reads.call_count, 1)
                self.assertEqual(observed, [b'original-row', b'changed-row'])
            def current(): pass
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=current)
            self.assertEqual(store.read(key).payload, b'original-row')  # same read transaction rolled back


    def test_raw_and_other_physical_queries_keep_complete_metadata_reads(self):
        for mode in ('raw-read', 'raw-scan', 'other-physical'):
            with self.subTest(mode=mode), TemporaryDirectory(prefix='actql-query-fallback-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
                if mode == 'other-physical':
                    original = store._physical
                    class ExistingPhysicalPort:
                        def __getattr__(self, name): return getattr(original, name)
                    store._physical = ExistingPhysicalPort()
                rows = []
                def inspect(reader):
                    sql = []
                    store._connection.set_trace_callback(sql.append)
                    try:
                        if mode == 'raw-read': reader.read('original', 'one', rows.append)
                        elif mode == 'raw-scan': reader.scan_after('original', '', rows.append)
                        else: rows.append(reader.query_current(reader, 1, 'original', 'one', current))
                    finally:
                        store._connection.set_trace_callback(None)
                    self.assertEqual(len([q for q in sql if q.lstrip().upper().startswith('SELECT')]), 5 if mode == 'other-physical' else 7)
                def current(): pass
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=current)
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0][1].payload, b'original-row')


    def test_snapshot_reuse_refuses_mutation_in_current_and_latches_original_failure(self):
        from actql_sdk._local_storage import LocalStorageError
        with TemporaryDirectory(prefix='actql-sql-current-mutation-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            mutate = []
            def current():
                if mutate:
                    store._connection.execute('UPDATE core_bytes SET generation=1 WHERE key=?', ('epoch',))
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                reader.check_fences(reader, (ByteFence('epoch', 0, b'original-epoch'),))
                mutate.append(True)
                with self.assertRaises(LocalStorageError) as caught: reader.current()
                mutate.clear()
                store._connection.execute('UPDATE core_bytes SET generation=0 WHERE key=?', ('epoch',))
                # Repairing fixture bytes does not unpoison an original reader.
                with self.assertRaises(ValueError): reader.current()
                self.assertIn('metadata changed', str(caught.exception))
            with self.assertRaises(ValueError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=current)

    def test_snapshot_reuse_rechecks_unrelated_writes_and_refuses_replaced_transaction(self):
        from actql_sdk._local_storage import LocalStorageError
        for replace_transaction in (False, True):
            with self.subTest(replace_transaction=replace_transaction), \
                    TemporaryDirectory(prefix='actql-sql-snapshot-version-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                def inspect(reader):
                    reader.read('original', 'one', lambda _: None)
                    if replace_transaction:
                        store._physical.rollback(); store._physical.begin_read()
                        with self.assertRaises(LocalStorageError): reader.current()
                        return
                    store._physical.write_record('unrelated', None, b'actual-other-write')
                    with patch.object(store, '_read_bytes_locked', wraps=store._read_bytes_locked) as sql:
                        reader.current()
                        self.assertEqual(sql.call_count, 1)
                        reader.current()
                        self.assertEqual(sql.call_count, 1)
                if replace_transaction:
                    with self.assertRaises(LocalStorageError):
                        store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                            inspect=inspect, current=lambda: None)
                else:
                    store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                        inspect=inspect, current=lambda: None)
                    self.assertIsNone(store.read('unrelated'))  # read snapshot was rolled back

    def test_physical_supplier_without_original_sqlite_marker_keeps_full_checks(self):
        with TemporaryDirectory(prefix='actql-no-snapshot-marker-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            original = store._physical
            class ExistingPhysicalPort:
                def __getattr__(self, name): return getattr(original, name)
            store._physical = ExistingPhysicalPort()
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                with patch.object(store, '_read_bytes_locked', wraps=store._read_bytes_locked) as sql:
                    for _ in range(5): reader.current()
                    self.assertEqual(sql.call_count, 10)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=lambda: None)

    def test_snapshot_schema_change_refuses_even_without_a_row_mutation(self):
        from actql_sdk._local_storage import LocalStorageError
        with TemporaryDirectory(prefix='actql-sql-schema-change-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                before = store._connection.total_changes
                store._connection.execute('CREATE TABLE foreign_schema_change (value BLOB)')
                self.assertEqual(store._connection.total_changes, before)
                with self.assertRaises(LocalStorageError): reader.current()
            with self.assertRaises(LocalStorageError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)

    def test_temp_schema_shadow_cannot_reuse_main_metadata_as_current(self):
        from actql_sdk._local_storage import LocalStorageError
        with TemporaryDirectory(prefix='actql-sql-temp-schema-shadow-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                reader.check_fences(reader, (ByteFence('epoch', 0, b'original-epoch'),))
                schema = store._connection.execute('PRAGMA schema_version').fetchone()[0]
                changes = store._connection.total_changes
                store._connection.execute('CREATE TEMP TABLE core_bytes(key TEXT, generation INTEGER, payload BLOB)')
                self.assertEqual(store._connection.total_changes, changes)
                self.assertEqual(store._connection.execute('PRAGMA schema_version').fetchone()[0], schema)
                with self.assertRaises(LocalStorageError): reader.current()
            with self.assertRaises(LocalStorageError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)
            self.assertFalse(store._physical.in_transaction)
            self.assertEqual(store.read('epoch').payload, b'original-epoch')

    def test_schema_probe_cannot_return_a_replaced_original_connection_or_transaction(self):
        import sqlite3
        for replace_connection in (False, True):
            with self.subTest(replace_connection=replace_connection), \
                    TemporaryDirectory(prefix='actql-schema-original-reentry-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                foreign = sqlite3.connect(':memory:', isolation_level=None)
                self.addCleanup(foreign.close)
                database = store._physical
                original = store._connection
                armed = []
                fired = []
                def reenter(sql):
                    if armed and sql == 'PRAGMA temp.schema_version':
                        armed.clear()
                        fired.append(True)
                        if replace_connection:
                            database._connection = foreign
                        else:
                            database.rollback()
                            database.begin_read()
                def inspect(reader):
                    reader.read('original', 'one', lambda _: None)
                    armed.append(True)
                    original.set_trace_callback(reenter)
                    try:
                        with self.assertRaises(ValueError): reader.current()
                    finally:
                        original.set_trace_callback(None)
                        database._connection = original
                    with self.assertRaises(ValueError): reader.current()
                with self.assertRaises(ValueError):
                    store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                        inspect=inspect, current=lambda: None)
                self.assertEqual(fired, [True])
                self.assertFalse(database.in_transaction)
                self.assertEqual(store.read('epoch').payload, b'original-epoch')

    def test_temp_shadow_from_query_consumer_refuses_the_original_after_consumer_fence(self):
        from actql_sdk._local_storage import LocalStorageError
        with TemporaryDirectory(prefix='actql-query-temp-after-consumer-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            rows = []
            def consume(row):
                rows.append(row)
                store._connection.execute('CREATE TEMP TABLE core_bytes(key TEXT, generation INTEGER, payload BLOB)')
            def inspect(reader):
                with self.assertRaises(LocalStorageError):
                    reader.read('original', 'one', consume)
                with self.assertRaises(ValueError): reader.current()
            # The second attempted use is the existing poisoned-reader refusal.
            with self.assertRaises(ValueError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0][1].payload, b'original-row')
            self.assertFalse(store._physical.in_transaction)


    def test_temp_schema_probe_refusal_is_not_a_cached_success(self):
        import sqlite3
        with TemporaryDirectory(prefix='actql-temp-schema-probe-denied-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                def deny(action, name, argument, database, *_):
                    return (sqlite3.SQLITE_DENY if action == sqlite3.SQLITE_PRAGMA
                            and name == 'schema_version' and database == 'temp' else sqlite3.SQLITE_OK)
                store._connection.set_authorizer(deny)
                try:
                    with self.assertRaises(sqlite3.DatabaseError): reader.current()
                finally:
                    store._connection.set_authorizer(None)
                with self.assertRaises(ValueError): reader.current()
            # The second attempted use is the existing poisoned-reader refusal.
            with self.assertRaises(ValueError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)
            self.assertFalse(store._physical.in_transaction)
            self.assertEqual(store.read('epoch').payload, b'original-epoch')

    def test_snapshot_savepoint_rollback_invalidates_without_reusing_a_mutated_row(self):
        with TemporaryDirectory(prefix='actql-sql-savepoint-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                before = store._connection.total_changes
                store._connection.execute('SAVEPOINT original_test')
                store._connection.execute('UPDATE core_bytes SET generation=1 WHERE key=?', ('epoch',))
                store._connection.execute('ROLLBACK TO original_test')
                store._connection.execute('RELEASE original_test')
                self.assertGreater(store._connection.total_changes, before)
                with patch.object(store, '_read_bytes_locked', wraps=store._read_bytes_locked) as sql:
                    reader.current()
                    self.assertEqual(sql.call_count, 1)
                    reader.current()
                    self.assertEqual(sql.call_count, 1)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=lambda: None)

    def test_snapshot_equal_markers_on_different_connection_do_not_supply_original_reader(self):
        from actql_sdk._local_storage import LocalStorageError
        import sqlite3
        with TemporaryDirectory(prefix='actql-sql-foreign-connection-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            foreign = sqlite3.connect(':memory:', isolation_level=None)
            self.addCleanup(foreign.close)
            foreign.execute('CREATE TABLE core_bytes(key TEXT, generation INTEGER, payload BLOB)')
            foreign.execute('INSERT INTO core_bytes VALUES(?,?,?)', ('epoch', 0, b'original-epoch'))
            foreign.execute('BEGIN')
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                original = store._physical._connection
                self.assertEqual(foreign.total_changes, original.total_changes)
                store._physical._connection = foreign
                try:
                    with self.assertRaises(LocalStorageError): reader.current()
                finally:
                    store._physical._connection = original
            with self.assertRaises(LocalStorageError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)

    def test_same_snapshot_counts_all_sql_schema_probes_separately_from_metadata_rows(self):
        with TemporaryDirectory(prefix='actql-sql-snapshot-census-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=16,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            fences = tuple(ByteFence('original-' + str(i), 0, b'original-metadata') for i in range(7))
            for fence in fences: store.compare_exchange(fence.key, None, fence.payload)
            currents = []
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                sql = []
                before = len(currents)
                store._connection.set_trace_callback(sql.append)
                try:
                    for _ in range(5): reader.check_fences(reader, fences)
                finally:
                    store._connection.set_trace_callback(None)
                self.assertEqual(len(currents) - before, 5)
                self.assertEqual(len(sql), 20)
                self.assertEqual(sql, ['PRAGMA schema_version', 'PRAGMA temp.schema_version'] * 10)
            store.inspect_namespaces(fences, inspect=inspect, current=lambda: currents.append(True))

    def test_schema_probe_failure_is_not_cached_success_or_permission(self):
        import sqlite3
        with TemporaryDirectory(prefix='actql-sql-schema-denied-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            def inspect(reader):
                reader.read('original', 'one', lambda _: None)
                def deny_schema(action, name, *_):
                    return sqlite3.SQLITE_DENY if action == sqlite3.SQLITE_PRAGMA else sqlite3.SQLITE_OK
                store._connection.set_authorizer(deny_schema)
                try:
                    reader.current()
                finally:
                    store._connection.set_authorizer(None)
            with self.assertRaises(sqlite3.DatabaseError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)
            self.assertFalse(store._physical.in_transaction)
            self.assertEqual(store.read('epoch').payload, b'original-epoch')

    def test_query_keeps_distinct_current_and_refuses_at_every_existing_boundary(self):
        for stop in (None, 1, 2):
            with self.subTest(stop=stop), TemporaryDirectory(prefix='actql-query-refusal-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
                original_calls, required_calls = [], []
                failure = PermissionError('same original current refused')
                def original_current():
                    original_calls.append('physical')
                def required_current():
                    required_calls.append('required')
                    if len(required_calls) == stop:
                        raise failure
                callbacks = _JournalCallbacks(required_current, store)
                def inspect(reader):
                    callbacks.reader = reader
                    self.assertEqual(callbacks.begin(1, 8, 3), 0)
                    self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                    before = len(original_calls)
                    if stop is None:
                        self.assertEqual(callbacks.query(), 0)
                        self.assertEqual(len(original_calls) - before, 2)
                        self.assertEqual(len(required_calls), 2)
                        self.assertEqual(callbacks.row_copy(1, 0, 12), b'original-row')
                        self.assertEqual(callbacks.release(), 0)
                    else:
                        self.assertEqual(callbacks.query(), -41)
                        self.assertIs(callbacks.failure, failure)
                        self.assertEqual(len(required_calls), stop)
                        self.assertEqual(callbacks.release(), -41)
                if stop is None:
                    store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                        inspect=inspect, current=original_current)
                else:
                    with self.assertRaises(PermissionError) as failed:
                        store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                            inspect=inspect, current=original_current)
                    self.assertIs(failed.exception, failure)


    def test_query_current_change_cannot_hide_a_metadata_fence_mutation(self):
        from actql_sdk._local_storage import LocalStorageError
        with TemporaryDirectory(prefix='actql-query-row-change-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            callbacks = _JournalCallbacks(lambda: None, store)
            def changed():
                store._connection.execute('UPDATE core_bytes SET generation=1 WHERE key=?', ('epoch',))
            def inspect(reader):
                callbacks.reader = reader
                self.assertEqual(callbacks.begin(1, 8, 3), 0)
                self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                callbacks.current = changed
                self.assertEqual(callbacks.query(), -41)
                self.assertIsInstance(callbacks.failure, LocalStorageError)
                self.assertIsNone(callbacks.row)
            with self.assertRaises(LocalStorageError):
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=lambda: None)

    def test_query_current_is_observed_at_each_physical_boundary_without_adjacent_duplicates(self):
        with TemporaryDirectory(prefix='actql-query-current-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            observations = []
            def current():
                observations.append('original-current')
            callbacks = _JournalCallbacks(current, store)
            def inspect(reader):
                callbacks.reader = reader
                self.assertEqual(callbacks.begin(1, 8, 3), 0)
                self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                before = len(observations)
                self.assertEqual(callbacks.query(), 0)
                # Before physical read and before returning immutable row DATA.
                # The outer current and full SQL-fence checks remain separate.
                self.assertEqual(len(observations) - before, 2)
                self.assertEqual(callbacks.row_copy(1, 0, 12), b'original-row')
                self.assertEqual(callbacks.release(), 0)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=current)


    def test_frame_copy_thread_and_read_reentry_poison_only_the_original_reader(self):
        for mode in ('copy', 'thread', 'reentry'):
            with self.subTest(mode=mode), TemporaryDirectory(prefix='actql-frame-original-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
                callbacks = _JournalCallbacks(lambda: None, store)
                def inspect(reader):
                    callbacks.reader = reader
                    self.assertEqual(callbacks.begin(1, 8, 3), 0)
                    self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                    self.assertEqual(callbacks.query(), 0)
                    if mode == 'copy':
                        callbacks.reader = replace(reader)
                        self.assertEqual(callbacks.check_frame(), -41)
                    elif mode == 'thread':
                        result = []
                        thread = Thread(target=lambda: result.append(callbacks.check_frame()))
                        thread.start()
                        thread.join()
                        self.assertEqual(result, [-41])
                    else:
                        def receive(_):
                            self.assertEqual(callbacks.check_frame(), -41)
                        reader.read('original', 'one', receive)
                    self.assertIsInstance(callbacks.failure, ValueError)
                with self.assertRaises(ValueError):
                    store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                        inspect=inspect, current=lambda: None)

    def test_joined_lookup_keeps_both_failure_boundaries_and_original_cleanup(self):
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        import json
        admission = {'ref': reference, 'durability': 'durable', 'revision': 7}
        for after_copy in (False, True):
            with self.subTest(after_copy=after_copy), TemporaryDirectory(prefix='actql-lookup-fence-') as directory:
                fixture = lookup_fixture.LocalSubmissionLookupTests()
                self.addCleanup(fixture.doCleanups)
                host, core, _, _, _ = fixture.fixture(directory,
                    {'kind': 'ready', 'intentCid': 'sha256:' + 'e' * 64,
                     'admission': json.dumps(admission)}, run_reference=reference)
                failure = LocalCoreError('validate_submission_lookup', -32)
                validations = [None, failure] if after_copy else [failure]
                with patch.object(core, 'validate_submission_lookup', side_effect=validations):
                    with self.assertRaises(LocalCoreError) as failed:
                        host._read_original_reference(reference, kind=5)
                self.assertIs(failed.exception, failure)
                output = host._projections[-1]
                self.assertIs(core._loans[output.ticket], output)
                self.assertEqual(bool(core._inputs[output.ticket].payload), after_copy)
                self.assertFalse(host._run_loans)
                self.assertFalse(host._physical_work)
                self.assertTrue(host.close())

    def test_original_transport_does_not_reobserve_semantics_between_query_fences(self):
        with TemporaryDirectory(prefix='actql-snapshot-transport-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            key = store.namespaced_key('original', 'one')
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(key, None, b'original-row')
            observations = []
            def current():
                observations.append('current')
            callbacks = _JournalCallbacks(current, store)
            def inspect(reader):
                callbacks.reader = reader
                before = len(observations)
                self.assertEqual(callbacks.begin(1, 8, 3), 0)
                self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                self.assertEqual(len(observations), before)
                self.assertEqual(callbacks.query(), 0)
                self.assertGreater(len(observations), before)
                before = len(observations)
                self.assertEqual(callbacks.row_copy(0, 0, 3), b'one')
                self.assertEqual(callbacks.row_copy(1, 0, 12), b'original-row')
                self.assertEqual(len(observations), before)
                self.assertEqual(callbacks.release(), 0)
                self.assertEqual(callbacks.check_current(), 0)
                self.assertGreater(len(observations), before)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=current)
            # A frame is not a currentness token and cannot survive its reader.
            self.assertEqual(callbacks.check_frame(), -41)
            self.assertIsInstance(callbacks.failure, ValueError)

    def test_transport_never_turns_revocation_or_failed_reader_into_permission(self):
        with TemporaryDirectory(prefix='actql-snapshot-refusal-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            active = [True]
            original = PermissionError('original physical current revoked')
            def current():
                if not active[0]:
                    raise original
            callbacks = _JournalCallbacks(current, store)
            def inspect(reader):
                callbacks.reader = reader
                self.assertEqual(callbacks.begin(1, 8, 3), 0)
                self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                self.assertEqual(callbacks.query(), 0)
                row = callbacks.row
                active[0] = False
                self.assertEqual(callbacks.check_current(), -41)
                self.assertIs(callbacks.failure, original)
                with self.assertRaises(ValueError):
                    callbacks.row_copy(1, 0, 12)
                self.assertIs(callbacks.row, row)
                self.assertEqual(callbacks.release(), -41)
                active[0] = True
            with self.assertRaises(PermissionError) as failed:
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=current)
            self.assertIs(failed.exception, original)

    def test_original_operation_observation_joins_its_two_adjacent_current_checks(self):
        fixture = operation_fixture.OriginalOperationCurrentTests()
        self.addCleanup(fixture.doCleanups)
        _, core, _, binding, _ = fixture.fixture()
        def consume(current):
            core._invoking = True
            try:
                with patch.object(binding, '_physical_current', wraps=binding._physical_current) as physical:
                    self.assertEqual(core._journal_current_operation(current.ticket), core._host_operation_id)
                    self.assertEqual(physical.call_count, 1)
            finally:
                core._invoking = False
        with core._host_operation():
            binding.inspect(consume)

    def test_reference_produce_and_copy_share_only_the_adjacent_validation(self):
        fixture = lookup_fixture.LocalSubmissionLookupTests()
        self.addCleanup(fixture.doCleanups)
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        import json
        admission = {'ref': reference, 'durability': 'durable', 'revision': 7}
        with TemporaryDirectory(prefix='actql-lookup-handoff-') as directory:
            host, core, _, counts, _ = fixture.fixture(directory,
                {'kind': 'ready', 'intentCid': 'sha256:' + 'e' * 64,
                 'admission': json.dumps(admission)}, run_reference=reference)
            self.assertEqual(json.loads(host._read_original_reference(reference, kind=5)), admission)
            self.assertEqual(counts, {'produce': 1, 'validate': 2})
            self.assertFalse(host._run_loans)
            self.assertFalse(host._physical_work)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
