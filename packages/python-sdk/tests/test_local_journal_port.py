"""Independent physical transport oracles, not public Run/COMMIT acceptance."""
import copy
from contextlib import closing
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, LOCAL_CORE_ABI, _IMPORT_SIGNATURES,
    _JOURNAL_SIGNATURES, _Output, _PhysicalInput,
)
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_storage import (
    LocalByteStore, LocalStorageError, ByteWrite, ByteFence, StoredBytes, _NamespaceReader,
)
from actql_sdk._local_storage_physical import _SQLiteByteDatabase
from actql_sdk import _wire as wire
from actql_sdk._values import decode_json
from local_abi_declaration_fixture import assert_current_local_abi, original_byte_fixture_port


def scalar_reader_check(view, required, current):
    """Required checker for neutral scalar readers, never a production factory.

    Synthetic wrappers retain their original delegated physical fence and
    separately owned callback failure; actual Store readers use their own port.
    """
    view.check_fences(view, required)
    if current() is not None:
        raise ValueError('Scalar reader current cannot return permission')


def query(callbacks, mode, namespace, key):
    left, right = namespace.encode(), key.encode()
    status = callbacks.begin(mode, len(left), len(right))
    if status != 0:
        return status
    for ordinal, byte in enumerate(left + right):
        if callbacks.byte(ordinal, byte) != 0:
            return -41
    return callbacks.query()


class LocalJournalPhysicalPortTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory(prefix='actql-python-journal-port-')
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'original.sqlite'
        self.store = LocalByteStore(self.path, max_records=12,
                                   max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(self.store.close)
        self.namespace = 'e\u0301:/~'
        self.key = 'k\x00/~😀'
        self.raw = b'{"e\xcc\x81":"line\\r\\n","nullable":null,"n":1.25}'
        self.record_key = self.store.namespaced_key(self.namespace, self.key)
        self.assertEqual(self.store.compare_exchange('epoch', None, b'original'), 0)
        self.assertEqual(self.store.compare_exchange(self.record_key, None, self.raw), 0)
        self.fences = (ByteFence('epoch', 0, b'original'),)
        self.writes = (ByteWrite('outcome', None, b'original-Core-write'),)
        self.callbacks = _JournalCallbacks(lambda: None, self.store)

    def inside(self, fn):
        def inspect(reader):
            self.callbacks.reader = reader
            try:
                fn()
            finally:
                self.callbacks.reader = None
        return self.store.compare_exchange_many_inspected(
            self.writes, self.fences, inspect=inspect, current=lambda: None)

    def raw_row(self):
        callbacks = self.callbacks
        self.assertEqual(callbacks.length(0), len(self.key.encode()))
        self.assertEqual(callbacks.length(1), len(self.raw))
        return (bytes(callbacks.row_byte(0, i) for i in range(callbacks.length(0))),
                bytes(callbacks.row_byte(1, i) for i in range(callbacks.length(1))),
                callbacks.revision())

    def test_task_material_take_uses_original_row_transfer_and_confirmed_misses(self):
        run_key = 'sha256:' + 'a' * 64
        key = self.store.namespaced_key('client_task_run_materials', run_key + ':0')
        self.assertEqual(self.store.compare_exchange(key, None, b'original material'), 0)
        callbacks = self.callbacks
        statements = []
        self.store._connection.set_trace_callback(statements.append)

        def inspect(reader):
            callbacks.reader = reader
            try:
                with callbacks.task_material_rows(run_key, 17) as take:
                    self.assertEqual(take(0), 0)
                    self.assertEqual(callbacks.revision(), 0)
                    self.assertEqual(callbacks.row_copy(0, 0, 73), (run_key + ':0').encode())
                    self.assertEqual(callbacks.row_copy(1, 0, 17), b'original material')
                    self.assertEqual(callbacks.release(), 0)
                    for ordinal in (1, 2, 3):
                        self.assertEqual(take(ordinal), 1)
                        self.assertIsNone(callbacks.row)
                        self.assertEqual(callbacks.release(), 0)
                self.assertIsNone(callbacks.task_material_scope)
                self.assertEqual(take(0), -41)
                self.assertRegex(str(callbacks.failure), 'loan expired or changed')
            finally:
                callbacks.reader = None

        self.store.inspect_namespaces(self.fences, inspect=inspect, current=callbacks.current)
        self.assertEqual(sum('WITH requested(ordinal, key)' in sql for sql in statements), 1)
        self.assertFalse(self.store._connection.in_transaction)

    def test_task_material_abort_does_not_take_or_copy_a_later_slot(self):
        self.check_task_material_budget_after_first_slot(abort=True)

    def test_task_material_take_reports_original_later_capacity_refusal(self):
        self.check_task_material_budget_after_first_slot(abort=False)

    def check_task_material_budget_after_first_slot(self, *, abort):
        run_key = 'sha256:' + 'b' * 64
        keys = [self.store.namespaced_key('client_task_run_materials', f'{run_key}:{i}')
                for i in (0, 1)]
        first_payload = b'\xff' if abort else b'a'
        for key, payload in zip(keys, [first_payload, b'later physical row'], strict=True):
            self.assertEqual(self.store.compare_exchange(key, None, payload), 0)
        callbacks = self.callbacks
        copied = []
        read_row = _SQLiteByteDatabase.read_row

        def observe(database, key, max_bytes):
            if key in keys:
                copied.append(key)
            return read_row(database, key, max_bytes)

        def inspect(reader):
            callbacks.reader = reader
            try:
                with callbacks.task_material_rows(run_key, 1) as take:
                    self.assertEqual(take(0), 0)
                    self.assertEqual(callbacks.row_copy(1, 0, 1), first_payload)
                    self.assertEqual(callbacks.release(), 0)
                    if abort:
                        raise ValueError('first slot rejected by Common')
                    self.assertEqual(take(1), -41)
                    first = callbacks.failure
                    self.assertIsInstance(first, LocalStorageError)
                    self.assertEqual(take(2), -41)
                    self.assertIs(callbacks.failure, first)
            finally:
                callbacks.reader = None

        with patch.object(_SQLiteByteDatabase, 'read_row', observe):
            if abort:
                with self.assertRaisesRegex(ValueError, 'first slot rejected'):
                    self.store.inspect_namespaces(self.fences, inspect=inspect, current=callbacks.current)
                self.assertIsNone(callbacks.failure)
            else:
                with self.assertRaisesRegex(LocalStorageError, 'Over-budget') as failure:
                    self.store.inspect_namespaces(self.fences, inspect=inspect, current=callbacks.current)
                self.assertIs(failure.exception, callbacks.failure)
        self.assertEqual(copied, [keys[0]])
        self.assertIsNone(callbacks.task_material_scope)
        self.assertFalse(self.store._connection.in_transaction)

    def test_task_material_batch_preserves_indivisible_statement_failure(self):
        run_key = 'sha256:' + 'c' * 64
        callbacks = self.callbacks
        denying = False
        denied = []

        def authorize(action, table, column, *_):
            if denying and action == sqlite3.SQLITE_READ and table == 'core_bytes' and column == 'generation':
                denied.append(column)
                return sqlite3.SQLITE_DENY
            return sqlite3.SQLITE_OK

        def inspect(reader):
            nonlocal denying
            callbacks.reader = reader
            denying = True
            try:
                with callbacks.task_material_rows(run_key, 17):
                    self.fail('Failed physical statement admitted a task-material borrower')
            finally:
                denying = False
                callbacks.reader = None

        self.store._connection.set_authorizer(authorize)
        with self.assertRaises(sqlite3.DatabaseError) as refused:
            self.store.inspect_namespaces(self.fences, inspect=inspect, current=callbacks.current)
        self.assertEqual(refused.exception.sqlite_errorcode, sqlite3.SQLITE_AUTH)
        self.assertIs(callbacks.failure, refused.exception)
        self.assertIsNone(callbacks.row)
        self.assertIsNone(callbacks.task_material_scope)
        self.assertEqual(denied, ['generation'])
        self.assertFalse(self.store._connection.in_transaction)

    def test_saved_identity_pair_checks_reached_extent_before_physical_body(self):
        submission, run = ('sha256:' + value * 64 for value in ('a', 'b'))
        keys = (self.store.namespaced_key('client_submitted_intents', submission),
                self.store.namespaced_key('client_runs', run))
        bodies = (b'{"fixture":"original submission"}', b'{"fixture":"original saved run"}')
        for key, body in zip(keys, bodies, strict=True):
            self.assertEqual(self.store.compare_exchange(key, None, body), 0)
        copied = []
        targets = []
        physical_row = _SQLiteByteDatabase.read_row
        physical_headers = _SQLiteByteDatabase.read_target_headers

        def read_row(database, key, maximum):
            if key in keys:
                copied.append(key)
            return physical_row(database, key, maximum)

        def read_headers(database, requested):
            targets.append(requested)
            return physical_headers(database, requested)

        for second_size in (len(bodies[1]), len(bodies[1]) + 1, len(bodies[1]) - 1):
            callbacks = _JournalCallbacks(lambda: None, self.store)
            sizes = (len(bodies[0]), second_size)
            exact = second_size == len(bodies[1])
            copied.clear()
            targets.clear()

            def inspect(reader):
                callbacks.reader = reader
                try:
                    with callbacks.saved_identity_rows(submission, run, sizes, 512) as take:
                        self.assertEqual(copied, [])
                        self.assertEqual(take(0), 0)
                        self.assertEqual(callbacks.row_copy(1, 0, sizes[0]), bodies[0])
                        self.assertEqual(callbacks.release(), 0)
                        self.assertEqual(take(1), 0 if exact else 2)
                        if exact:
                            self.assertEqual(callbacks.row_copy(1, 0, sizes[1]), bodies[1])
                        else:
                            self.assertIsNone(callbacks.row)
                            self.assertIsNone(callbacks.failure)
                        self.assertEqual(callbacks.release(), 0)
                finally:
                    callbacks.reader = None

            with (patch.object(_SQLiteByteDatabase, 'read_target_headers', read_headers),
                  patch.object(_SQLiteByteDatabase, 'read_row', read_row)):
                self.store.inspect_namespaces(self.fences, inspect=inspect, current=callbacks.current)
            self.assertEqual(targets, [keys])
            self.assertEqual(copied, list(keys if exact else keys[:1]))
            self.assertIsNone(callbacks.task_material_scope)
            self.assertFalse(self.store._connection.in_transaction)

    def test_target_read_orders_exact_rows_and_refreshes_same_revision_bytes(self):
        revision = 9007199254740993
        empty = self.store.namespaced_key(self.namespace, 'empty')
        neighbor = self.store.namespaced_key(self.namespace, 'neighbor')
        with closing(sqlite3.connect(self.path)) as physical, physical:
            physical.execute('UPDATE core_bytes SET generation=? WHERE key=?',
                             (revision, self.record_key))
            physical.executemany('INSERT INTO core_bytes VALUES(?, 0, ?)',
                                 ((empty, b''), (neighbor, bytes(1024))))
        wanted = ((self.namespace, 'missing'), (self.namespace, self.key),
                  (self.namespace, 'empty'), ('é:/~', self.key))
        statements = []
        observed = []
        readers = []
        self.store._connection.set_trace_callback(statements.append)

        def inspect(reader):
            readers.append(reader)
            take = reader.get_many(reader, wanted, len(self.raw), current)
            observed.append(tuple(take(reader, ordinal) for ordinal in range(len(wanted))))
        current = lambda: None
        self.store.inspect_namespaces(self.fences, inspect=inspect, current=current)
        self.assertEqual(observed, [(None, StoredBytes(revision, self.raw), StoredBytes(0, b''), None)])
        queries = [statement for statement in statements if 'WITH requested(ordinal, key)' in statement]
        self.assertEqual(len(queries), 1)
        self.assertNotIn(neighbor.encode().hex(), queries[0])
        self.assertNotIn(neighbor, queries[0])
        self.assertFalse(self.store._connection.in_transaction)
        with self.assertRaisesRegex(ValueError, 'inventory reader is not active'):
            readers[0].get_many(readers[0], wanted, len(self.raw), current)

        # A different writer changes complete bytes while retaining the physical
        # generation. The next fresh observation must expose the changed bytes.
        changed = self.raw.replace(b'1.25', b'2.25')
        with closing(sqlite3.connect(self.path)) as physical, physical:
            physical.execute('UPDATE core_bytes SET payload=? WHERE key=?', (changed, self.record_key))
        self.store.inspect_namespaces(self.fences, inspect=inspect, current=current)
        self.assertEqual(observed, [
            (None, StoredBytes(revision, self.raw), StoredBytes(0, b''), None),
            (None, StoredBytes(revision, changed), StoredBytes(0, b''), None),
        ])
        self.assertIsNot(readers[0], readers[1])
        connection = self.store._connection
        self.store.close()
        with self.assertRaises(sqlite3.ProgrammingError):
            connection.execute('SELECT 1')

    def test_target_read_one_short_refuses_only_the_reached_body(self):
        second = b'\x00other original'
        other_key = self.store.namespaced_key(self.namespace, 'extra')
        self.assertEqual(self.store.compare_exchange(other_key, None, second), 0)
        wanted = ((self.namespace, self.key), (self.namespace, 'extra'))
        total = len(self.raw) + len(second)
        read_row = _SQLiteByteDatabase.read_row
        copied = []
        current = lambda: None

        def observe(database, key, max_bytes):
            row = read_row(database, key, max_bytes)
            if key != 'epoch':
                copied.append((key, max_bytes))
            return row

        def inspect(reader):
            take = reader.get_many(reader, wanted, total - 1, current)
            self.assertEqual(copied, [])
            self.assertEqual(take(reader, 0), StoredBytes(0, self.raw))
            take(reader, 1)

        with patch.object(_SQLiteByteDatabase, 'read_row', observe):
            with self.assertRaisesRegex(LocalStorageError, 'Over-budget'):
                self.store.inspect_namespaces(self.fences, inspect=inspect, current=current)
        self.assertEqual(copied, [(self.record_key, len(self.raw))])
        self.assertFalse(self.store._connection.in_transaction)

        def inspect_exact(reader):
            take = reader.get_many(reader, wanted, total, current)
            self.assertEqual(take(reader, 0), StoredBytes(0, self.raw))
            self.assertEqual(take(reader, 1), StoredBytes(0, second))

        self.store.inspect_namespaces(self.fences, inspect=inspect_exact, current=current)

    def test_target_read_uses_same_cumulative_query_budget_and_refuses_duplicates(self):
        self.store.close()
        self.store = LocalByteStore(self.path, max_records=12, max_record_bytes=512,
                                    max_payload_bytes=4096, max_inspection_queries=1)
        self.addCleanup(self.store.close)
        wanted = ((self.namespace, self.key), (self.namespace, 'missing'))
        statements = []
        self.store._connection.set_trace_callback(statements.append)
        current = lambda: None

        def inspect(reader):
            take = reader.get_many(reader, wanted, len(self.raw), current)
            self.assertEqual(take(reader, 0), StoredBytes(0, self.raw))
            take(reader, 1)

        with self.assertRaisesRegex(LocalStorageError, 'inspection capacity'):
            self.store.inspect_namespaces(self.fences, inspect=inspect, current=current)
        headers = [sql for sql in statements if 'WITH requested(ordinal, key)' in sql]
        self.assertEqual(len(headers), 1)
        self.assertNotIn('missing', headers[0])

        def duplicate(reader):
            reader.get_many(reader, (wanted[0], wanted[0]), len(self.raw), current)
        with self.assertRaisesRegex(ValueError, 'target key set'):
            self.store.inspect_namespaces(self.fences, inspect=duplicate, current=current)
        self.assertEqual(sum('WITH requested(ordinal, key)' in sql for sql in statements), 1)

    def test_target_read_refuses_foreign_reader_and_keeps_post_read_current_failure(self):
        wanted = ((self.namespace, self.key),)
        current = lambda: None
        returned = []

        def copied(reader):
            reader.get_many(copy.copy(reader), wanted, len(self.raw), current)
        with patch.object(_SQLiteByteDatabase, 'read_target_headers') as query:
            with self.assertRaisesRegex(ValueError, 'inventory reader is not active'):
                self.store.inspect_namespaces(self.fences, inspect=copied, current=current)
            query.assert_not_called()

        refusal = OSError('original target current observation lost')
        observations = []

        def after_body():
            observations.append('current')
            if len(observations) == 4:
                raise refusal

        def inspect(reader):
            take = reader.get_many(reader, wanted, len(self.raw), after_body)
            returned.append(take(reader, 0))
        with self.assertRaises(OSError) as raised:
            self.store.inspect_namespaces(self.fences, inspect=inspect, current=current)
        self.assertIs(raised.exception, refusal)
        self.assertEqual(len(observations), 4)
        self.assertEqual(returned, [])
        self.assertFalse(self.store._connection.in_transaction)
        self.assertEqual(self.store.read(self.record_key), StoredBytes(0, self.raw))

    def test_target_read_batch_sql_failure_and_swallowed_reentry_stay_failures(self):
        wanted = ((self.namespace, self.key),)
        current = lambda: None
        rows = []
        original = _SQLiteByteDatabase.read_row

        def observe(database, key, max_bytes):
            if key == self.record_key:
                rows.append(key)
            return original(database, key, max_bytes)

        denying = False
        def authorize(action, table, column, *_):
            return (sqlite3.SQLITE_DENY if denying and action == sqlite3.SQLITE_READ
                    and table == 'core_bytes' and column == 'generation'
                    else sqlite3.SQLITE_OK)

        self.store._connection.set_authorizer(authorize)
        def denied(reader):
            nonlocal denying
            denying = True
            try:
                reader.get_many(reader, wanted, len(self.raw), current)
            finally:
                denying = False

        with patch.object(_SQLiteByteDatabase, 'read_row', observe):
            with self.assertRaises(sqlite3.DatabaseError) as refused:
                self.store.inspect_namespaces(self.fences, inspect=denied, current=current)
        self.assertEqual(refused.exception.sqlite_errorcode, sqlite3.SQLITE_AUTH)
        self.assertEqual(rows, [])
        self.assertFalse(self.store._connection.in_transaction)
        self.store._connection.set_authorizer(None)

        errors = []
        def reenter(reader):
            def attempt():
                try:
                    reader.get_many(reader, wanted, len(self.raw), current)
                except ValueError as error:
                    errors.append(error)
            reader.get_many(reader, wanted, len(self.raw), attempt)

        with patch.object(_SQLiteByteDatabase, 'read_target_headers') as query:
            with self.assertRaises(ValueError) as raised:
                self.store.inspect_namespaces(self.fences, inspect=reenter, current=current)
            query.assert_not_called()
        self.assertEqual(len(errors), 1)
        self.assertIs(raised.exception, errors[0])
        self.assertFalse(self.store._connection.in_transaction)

    def test_target_read_retry_preserves_original_header_or_body_sql_failure(self):
        wanted = ((self.namespace, self.key),)
        physical_header = _SQLiteByteDatabase.read_target_headers
        physical_body = _SQLiteByteDatabase.read_row
        connection = self.store._connection

        for cut in ('header', 'body'):
            with self.subTest(cut=cut):
                denied = False
                calls = []
                caught = []

                def authorizer(action, table, column, *_):
                    return (sqlite3.SQLITE_DENY if denied and action == sqlite3.SQLITE_READ
                            and table == 'core_bytes' and column == 'generation'
                            else sqlite3.SQLITE_OK)

                def header(database, keys):
                    nonlocal denied
                    calls.append('header')
                    denied = cut == 'header'
                    try:
                        return physical_header(database, keys)
                    finally:
                        denied = False

                def body(database, key, max_bytes):
                    nonlocal denied
                    if key != self.record_key:
                        return physical_body(database, key, max_bytes)
                    calls.append('body')
                    denied = cut == 'body'
                    try:
                        return physical_body(database, key, max_bytes)
                    finally:
                        denied = False

                def current():
                    return None

                def inspect(reader):
                    def get():
                        return reader.get_many(reader, wanted, len(self.raw), current)

                    take = None if cut == 'header' else get()

                    def request():
                        return get() if take is None else take(reader, 0)

                    for retry in (request, request, reader.current):
                        with self.assertRaises(sqlite3.DatabaseError) as refused:
                            retry()
                        caught.append(refused.exception)

                connection.set_authorizer(authorizer)
                try:
                    with (patch.object(_SQLiteByteDatabase, 'read_target_headers', header),
                          patch.object(_SQLiteByteDatabase, 'read_row', body)):
                        with self.assertRaises(sqlite3.DatabaseError) as failed:
                            self.store.inspect_namespaces(self.fences, inspect=inspect, current=current)
                finally:
                    connection.set_authorizer(None)

                self.assertEqual(failed.exception.sqlite_errorcode, sqlite3.SQLITE_AUTH)
                self.assertEqual(len(caught), 3)
                self.assertTrue(all(error is failed.exception for error in caught))
                self.assertEqual(calls, ['header'] if cut == 'header' else ['header', 'body'])
                self.assertFalse(connection.in_transaction)
                self.assertEqual(self.store.read(self.record_key), StoredBytes(0, self.raw))

    def test_target_read_refuses_same_revision_mutation_inside_original_snapshot(self):
        wanted = ((self.namespace, self.key),)
        changed = self.raw.replace(b'1.25', b'2.25')
        current = lambda: None
        body_reads = []
        read_row = _SQLiteByteDatabase.read_row

        def observe(database, key, max_bytes):
            if key == self.record_key:
                body_reads.append(key)
            return read_row(database, key, max_bytes)

        def inspect(reader):
            take = reader.get_many(reader, wanted, len(self.raw), current)
            # Same connection, same revision and extent. The sticky original
            # snapshot observation must refuse before reading any body.
            self.store._connection.execute('UPDATE core_bytes SET payload=? WHERE key=?',
                                           (changed, self.record_key))
            take(reader, 0)

        with patch.object(_SQLiteByteDatabase, 'read_row', observe):
            with self.assertRaisesRegex(LocalStorageError, 'target snapshot changed'):
                self.store.inspect_namespaces(self.fences, inspect=inspect, current=current)
        self.assertEqual(body_reads, [])
        self.assertFalse(self.store._connection.in_transaction)
        self.assertEqual(self.store.read(self.record_key), StoredBytes(0, self.raw))

    def test_same_store_scan_and_exact_read_preserve_raw_key_body_and_int64(self):
        with sqlite3.connect(self.path) as physical:
            physical.execute('UPDATE core_bytes SET generation=? WHERE key=?',
                             (9007199254740993, self.record_key))
        def consume():
            self.assertEqual(query(self.callbacks, 0, self.namespace, ''), 0)
            self.assertEqual(self.raw_row(), (self.key.encode(), self.raw, 9007199254740993))
            self.assertEqual(self.callbacks.release(), 0)
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), 0)
            self.assertEqual(self.raw_row(), (self.key.encode(), self.raw, 9007199254740993))
            self.assertEqual(self.callbacks.release(), 0)
        self.assertEqual(self.inside(consume), (0,))
        self.assertEqual(self.store.read(self.record_key), StoredBytes(9007199254740993, self.raw))

    def test_physical_miss_and_scan_end_do_not_substitute_neighbor_or_composed_namespace(self):
        def consume():
            for mode, namespace, key in [(1, self.namespace, 'missing'),
                                          (0, self.namespace, self.key),
                                          (1, 'é:/~', self.key)]:
                self.assertEqual(query(self.callbacks, mode, namespace, key), 1)
                self.assertEqual(self.callbacks.revision(), -1)
                self.assertEqual(self.callbacks.length(1), -41)
                self.assertEqual(self.callbacks.release(), 0)
        self.assertEqual(self.inside(consume), (0,))

    def test_query_failure_retains_original_exception_never_a_notfound_observation(self):
        class QueryFailure(sqlite3.Connection):
            fail = False
            def execute(self, sql, *args, **kwargs):
                if self.fail and 'ORDER BY key COLLATE BINARY LIMIT 1' in sql:
                    raise sqlite3.OperationalError('original query failure')
                return super().execute(sql, *args, **kwargs)
        self.store.close()
        connect = sqlite3.connect
        with patch('actql_sdk._local_storage.sqlite3.connect',
                   side_effect=lambda *a, **k: connect(*a, **(k | {'factory': QueryFailure}))):
            self.store = LocalByteStore(self.path, max_records=12, max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(self.store.close)
        self.store._connection.fail = True
        self.callbacks.store = self.store
        def consume():
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
            self.assertIsInstance(self.callbacks.failure, sqlite3.OperationalError)
            self.assertEqual(self.callbacks.release(), -41)
        with self.assertRaisesRegex(sqlite3.OperationalError, 'original query failure'):
            self.inside(consume)
        self.assertIsNone(self.store.read('outcome'))

    def test_old_reader_and_permission_boolean_are_unavailable_not_current(self):
        saved = []
        def consume():
            saved.append(self.callbacks.reader)
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), 0)
            self.assertEqual(self.callbacks.release(), 0)
        self.assertEqual(self.inside(consume), (0,))
        self.callbacks.reader = saved[0]
        self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
        self.assertIsInstance(self.callbacks.failure, ValueError)
        wrong = _JournalCallbacks(lambda: True, self.store, reader=saved[0])
        self.assertEqual(wrong.check_current(), -41)
        self.assertIsInstance(wrong.failure, ValueError)

    def test_current_failure_keeps_original_cause_before_query_and_after_bad_retry(self):
        original = PermissionError('original epoch or authority unavailable')
        def refuse():
            raise original
        reader = _NamespaceReader(lambda *args: self.fail('Unexpected query'),
                                  lambda *args: self.fail('Unexpected query'), self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        callbacks = _JournalCallbacks(refuse, self.store, reader=reader)
        self.assertEqual(query(callbacks, 1, self.namespace, self.key), -41)
        self.assertIs(callbacks.failure, original)
        self.assertEqual(callbacks.byte(0, 97), -41)
        self.assertIs(callbacks.failure, original)
        self.assertEqual(callbacks.query(), -41)
        self.assertIs(callbacks.failure, original)

    def test_query_transfer_limits_and_order_refuse_without_io(self):
        reader = _NamespaceReader(lambda *args: self.fail('Unexpected query'),
                                  lambda *args: self.fail('Unexpected query'), self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        for mode, left, right in [(4, 1, 1), (1, 1, 0), (3, 1, 0), (0, 4097, 1), (0, 1, 4097), (True, 1, 1)]:
            callbacks = _JournalCallbacks(lambda: None, self.store, reader=reader)
            self.assertEqual(callbacks.begin(mode, left, right), -41)
        callbacks = _JournalCallbacks(lambda: None, self.store, reader=reader)
        self.assertEqual(callbacks.begin(1, 1, 1), 0)
        self.assertEqual(callbacks.byte(1, 97), -41)
        self.assertEqual(callbacks.query(), -41)
        incomplete = _JournalCallbacks(lambda: None, self.store, reader=reader)
        self.assertEqual(incomplete.begin(1, 1, 1), 0)
        self.assertEqual(incomplete.query(), -41)

    def test_name_hmac_mode_is_closed_to_the_selected_epoch_and_namespace(self):
        reader = _NamespaceReader(lambda *args: self.fail('Unexpected query'),
                                  lambda *args: self.fail('Unexpected query'),
                                  self.store, lambda: None, check_fences=lambda *_: None,
                                  check_fences_and_current=scalar_reader_check)
        namespace = 'client_submission_names'
        preimage = '["scoped-submission-name","local","actor","name"]'
        calls = []
        result = b'a' * 32

        def authenticate(body):
            calls.append(body)
            return result

        enabled = _JournalCallbacks(lambda: None, self.store, reader=reader,
                                    name_authenticate=authenticate)
        self.assertEqual(query(enabled, 3, namespace, preimage), 0)
        self.assertEqual(enabled.row, (b'authenticator', StoredBytes(0, result)))
        self.assertEqual(enabled.release(), 0)
        for rejected_namespace, authenticator in [('client_runs', authenticate), (namespace, None)]:
            rejected = _JournalCallbacks(lambda: None, self.store, reader=reader,
                                         name_authenticate=authenticator)
            self.assertEqual(query(rejected, 3, rejected_namespace, preimage), -41)
            self.assertIsNone(rejected.row)
        self.assertEqual(calls, [preimage.encode('utf-8')])

    def test_unreleased_query_copy_cannot_be_overwritten_by_another_query(self):
        def consume():
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), 0)
            original = self.callbacks.row
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
            self.assertIs(self.callbacks.row, original)
            self.assertEqual(self.callbacks.release(), -41)
        self.assertEqual(self.inside(consume), (0,))
        self.assertIsNone(self.callbacks.row)

    def test_current_revocation_after_read_keeps_same_row_loan_until_cleanup(self):
        active = [True]
        self.callbacks.current = lambda: None if active[0] else (_ for _ in ()).throw(
            PermissionError('original authority revoked'))
        def consume():
            reader = self.callbacks.reader
            def read(namespace, key, callback):
                reader.read(namespace, key, callback)
                active[0] = False
            self.callbacks.reader = _NamespaceReader(reader.scan_after, read, self.store, reader.current, check_fences=lambda _, required: reader.check_fences(reader, required),
                check_fences_and_current=scalar_reader_check)
            self.assertEqual(query(self.callbacks, 1, self.namespace, self.key), -41)
            self.assertIsInstance(self.callbacks.failure, PermissionError)
            self.assertEqual(self.callbacks.row[1].payload, self.raw)
            self.assertEqual(self.callbacks.length(1), -41)
        self.assertEqual(self.inside(consume), (0,))
        self.assertIsNotNone(self.callbacks.row)
        self.callbacks.release()
        self.assertIsNone(self.callbacks.row)


class LocalJournalBridgeCustodyTests(unittest.TestCase):
    def bridge(self):
        directory = TemporaryDirectory(prefix='actql-python-journal-scalar-')
        self.addCleanup(directory.cleanup)
        self.store = LocalByteStore(Path(directory.name) / 'original.sqlite', max_records=8,
                                    max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(self.store.close)
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {1: _PhysicalInput(b'', lambda: True, lambda _: True)}
        core._loans = {}
        core._released = set()
        core._next_ticket = 2
        core._closing = False
        material = _Output(core._identity, 1, 7, 1048576, 'material')
        core._loans[1] = material
        calls = []
        code = [0]
        def invoke(family, name, *args):
            calls.append((family, name, args))
            self.assertEqual(family, 'journal')
            if name == 'reserve':
                self.assertEqual(args[:2], (7, 8))
                self.assertGreaterEqual(args[3], 2 * 1048576)
                return 20
            if name == 'inspect':
                callbacks = core._journal_callbacks(2)
                self.assertIsNotNone(callbacks.reader)
                return code[0]
            if name == 'revision':
                return (0, 9, 2)[args[1]]
            if name == 'close':
                return 0 if core._cleanup(2) == 0 else -9
            raise AssertionError('Unexpected call')
        core._call = original_byte_fixture_port(invoke)
        return core, material, calls, code

    def test_same_ticket_retains_callback_input_and_cleanup_failure_for_retry(self):
        core, material, calls, code = self.bridge()
        ready = [False]
        cleaned = []
        loan = core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None,
                                               cleanup=lambda: cleaned.append('close') or ready[0])
        self.assertEqual(loan.limit, 4096)
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        core.inspect_journal_observation(loan, reader)
        self.assertIsNone(core._journal_callbacks(2).reader)
        self.assertEqual(core.journal_observation_revisions(loan, reader), (0, 9, 2))
        self.assertFalse(core.close_journal_observation(loan))
        self.assertIs(core._loans[2], loan)
        self.assertIs(core._loans[1], material)
        ready[0] = True
        self.assertTrue(core.close_journal_observation(loan))
        self.assertEqual(cleaned, ['close', 'close'])
        self.assertEqual(core._journal_current(2), -41)
        with self.assertRaises(ValueError):
            core.close_journal_observation(loan)
        self.assertTrue(all(family == 'journal' for family, _, _ in calls))

    def test_foreign_copied_parent_boolean_and_closing_refuse_before_io(self):
        core, material, calls, _ = self.bridge()
        original_store = self.store
        foreign, other, _, _ = self.bridge()
        self.store = original_store
        for action in [lambda: core.reserve_journal_observation(copy.copy(material), 8, store=self.store, current=lambda: None, cleanup=lambda: True),
                       lambda: core.reserve_journal_observation(other, 8, store=self.store, current=lambda: None, cleanup=lambda: True),
                       lambda: core.reserve_journal_observation(material, True, store=self.store, current=lambda: None, cleanup=lambda: True)]:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(calls, [])
        core._closing = True
        with self.assertRaises(ValueError):
            core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None, cleanup=lambda: True)
        self.assertEqual(calls, [])

    def test_core_refusal_releases_reader_only_not_original_parent_or_ticket(self):
        core, material, calls, code = self.bridge()
        loan = core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None, cleanup=lambda: True)
        code[0] = -42
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        with self.assertRaises(LocalCoreError) as failed:
            core.inspect_journal_observation(loan, reader)
        self.assertEqual(failed.exception.code, -42)
        self.assertIsNone(core._journal_callbacks(2).reader)
        self.assertIs(core._loans[2], loan)
        self.assertIs(core._loans[1], material)

    def test_original_query_exception_is_returned_without_notfound_or_resend(self):
        core, material, calls, code = self.bridge()
        loan = core.reserve_journal_observation(material, 8, store=self.store, current=lambda: None, cleanup=lambda: True)
        original = OSError('original physical query')
        def invoke(family, name, *args):
            core._journal_callbacks(2).failure = original
            return -41
        core._call = original_byte_fixture_port(invoke)
        with self.assertRaises(OSError) as failed:
            core.inspect_journal_observation(loan, _NamespaceReader(lambda *a: None, lambda *a: None, self.store, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check))
        self.assertIs(failed.exception, original)
        self.assertIs(core._loans[2], loan)
        self.assertIsNone(core._journal_callbacks(2).reader)

    def test_foreign_store_reader_and_expired_snapshot_refuse_without_core_adoption(self):
        core, material, calls, code = self.bridge()
        original_store = self.store
        loan = core.reserve_journal_observation(material, 8, store=original_store,
                                                current=lambda: None, cleanup=lambda: True)
        temporary = TemporaryDirectory(prefix='actql-python-foreign-journal-')
        self.addCleanup(temporary.cleanup)
        foreign = LocalByteStore(Path(temporary.name) / 'foreign.sqlite', max_records=8,
                                 max_record_bytes=512, max_payload_bytes=4096)
        self.addCleanup(foreign.close)
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, foreign, lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        baseline = len(calls)
        with self.assertRaises(ValueError):
            core.inspect_journal_observation(loan, reader)
        self.assertEqual(len(calls), baseline)
        self.assertIs(core._loans[2], loan)
        captured = []
        def inspect(original):
            captured.append(original)
            original.scan_after('empty', '', lambda row: self.assertIsNone(row))
        self.assertEqual(original_store.compare_exchange_many_inspected(
            (ByteWrite('fixed', None, b'original'),),
            (ByteFence('missing-original', 0, b'none'),),
            inspect=inspect, current=lambda: None), None)
        # Establish an independent actual metadata fence for the empty snapshot.
        self.assertEqual(original_store.compare_exchange('meta', None, b'original'), 0)
        self.assertEqual(original_store.compare_exchange_many_inspected(
            (ByteWrite('fixed', None, b'original'),),
            (ByteFence('meta', 0, b'original'),),
            inspect=inspect, current=lambda: None), (0,))
        callbacks = core._journal_callbacks(2)
        callbacks.reader = captured[0]
        self.assertEqual(callbacks.check_current(), -41)
        self.assertIsInstance(callbacks.failure, ValueError)
        callbacks.reader = None

    def test_private_loader_matches_changed_abi_imports_and_revision_width(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_JOURNAL_SIGNATURES, {
            'reserve': ('i64 i32 i32 i32 i64', 'i32'), 'inspect': ('i64 i32', 'i32'),
            'revision': ('i64 i32 i32', 'i64'), 'admission_length': ('i64 i32', 'i32'), 'close': ('i64 i32', 'i32')})
        self.assertEqual(_IMPORT_SIGNATURES['journal_query_header'],
                         ('i32 i32 i32 i32 i32 i32 i32', 'i32'))
        self.assertEqual(_IMPORT_SIGNATURES['journal_copy_row'], ('i32 i32 i32 i32 i32', 'i32'))
        self.assertNotIn('journal_revision', _IMPORT_SIGNATURES)
        self.assertNotIn('journal_begin', _IMPORT_SIGNATURES)

    def admission_bridge(self):
        core, material, calls, code = self.bridge()
        loan = core.reserve_journal_observation(material, 8, store=self.store,
            current=lambda: None, cleanup=lambda: True)
        # Independent closed public admission, not an actual Core decision.
        raw = (b'{"ref":{"namespaceId":"scope","authorityScopeCid":"sha256:' + b'b' * 64
               + b'","runDefinitionCid":"sha256:' + b'a' * 64
               + b'"},"durability":"durable","revision":0}')
        copied = []
        def invoke(family, name, *args):
            calls.append((family, name, args))
            if family == 'journal' and name == 'admission_length':
                self.assertIsNotNone(core._journal_callbacks(loan.ticket).reader)
                status = core._journal_current(loan.ticket)
                return status if status != 0 else len(raw) if code[0] == 0 else code[0]
            if family == 'buffer' and name == 'byte':
                copied.append(args[1])
                return raw[args[1]]
            raise AssertionError('Unexpected physical/semantic primitive')
        core._call = original_byte_fixture_port(invoke)
        reader = _NamespaceReader(lambda *a: None, lambda *a: None, self.store,
                                  lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        return core, loan, reader, raw, copied, calls, code

    def test_admission_transfer_and_cached_read_both_check_current_snapshot(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        self.assertTrue(wire.valid(decode_json(raw), 'admission'))
        self.assertEqual(core.read_journal_admission(loan, reader), raw)
        self.assertEqual(copied, list(range(len(raw))))
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        baseline = len(calls)
        self.assertEqual(core.read_journal_admission(loan, reader), raw)
        self.assertEqual([name for _, name, _ in calls[baseline:]],
                         ['admission_length', 'admission_length'])
        self.assertIs(core._loans[loan.ticket], loan)

    def test_cached_admission_cannot_bypass_core_current_refusal(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        self.assertEqual(core.read_journal_admission(loan, reader), raw)
        code[0] = -32
        baseline = len(calls)
        with self.assertRaises(LocalCoreError) as refused:
            core.read_journal_admission(loan, reader)
        self.assertEqual(refused.exception.code, -32)
        self.assertEqual([name for _, name, _ in calls[baseline:]], ['admission_length'])
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        self.assertEqual(core._inputs[loan.ticket].payload, raw)
        self.assertIs(core._loans[loan.ticket], loan)

    def test_admission_physical_failure_preserves_original_exception_and_loans(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        original = OSError('Original current snapshot unavailable')
        core._journal_callbacks(loan.ticket).current = lambda: (_ for _ in ()).throw(original)
        with self.assertRaises(OSError) as refused:
            core.read_journal_admission(loan, reader)
        self.assertIs(refused.exception, original)
        self.assertEqual(copied, [])
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIn(1, core._loans)

    def test_admission_foreign_loan_reader_and_closing_reject_before_io(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        baseline = len(calls)
        other = _NamespaceReader(lambda *a: None, lambda *a: None, object(),
                                 lambda: None, check_fences=lambda *_: None, check_fences_and_current=scalar_reader_check)
        for action in [lambda: core.read_journal_admission(copy.copy(loan), reader),
                       lambda: core.read_journal_admission(loan, other)]:
            with self.assertRaises(ValueError):
                action()
        core._closing = True
        with self.assertRaises(ValueError):
            core.read_journal_admission(loan, reader)
        self.assertEqual(len(calls), baseline)
        self.assertEqual(copied, [])

    def test_current_failure_after_copy_never_returns_admission_or_releases_loan(self):
        core, loan, reader, raw, copied, calls, code = self.admission_bridge()
        original = PermissionError('Original authority changed during transfer')
        invoke = core._call
        lengths = [0]
        def change(family, name, *args):
            if family == 'journal' and name == 'admission_length':
                lengths[0] += 1
                if lengths[0] == 3:
                    core._journal_callbacks(loan.ticket).failure = original
                    return -41
            return invoke(family, name, *args)
        core._call = original_byte_fixture_port(change)
        with self.assertRaises(PermissionError) as refused:
            core.read_journal_admission(loan, reader)
        self.assertIs(refused.exception, original)
        self.assertEqual(copied, list(range(len(raw))))
        self.assertEqual(core._inputs[loan.ticket].payload, raw)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIn(1, core._loans)
        self.assertIsNone(core._journal_callbacks(loan.ticket).reader)
