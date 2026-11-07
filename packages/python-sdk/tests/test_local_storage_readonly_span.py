"""Explicit unchanged-reader checks, not physical current or permission."""
import copy
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
from threading import Thread
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import ByteFence, LocalByteStore, LocalStorageError
from actql_sdk._local_storage_physical import _SQLiteByteDatabase, _TrackedSQLiteConnection


class ReadOnlySpanTests(unittest.TestCase):
    def fixture(self):
        temporary = TemporaryDirectory(prefix='actql-readonly-span-')
        self.addCleanup(temporary.cleanup)
        store = LocalByteStore(Path(temporary.name) / 'store.sqlite3', max_records=16,
                               max_record_bytes=64, max_payload_bytes=256)
        self.addCleanup(store.close)
        store.compare_exchange('control', None, b'original')
        store.compare_exchange(store.namespaced_key('settings', 'a'), None, b'first')
        return store, (ByteFence('control', 0, b'original'),)

    def inspect(self, store, fences, consume, current=lambda: None):
        def read(reader):
            # The existing reader still requires an actual bounded query.
            reader.query_current(reader, 0, 'settings', '', current)
            consume(reader)
        store.inspect_namespaces(fences, current=current, inspect=read)

    def test_repeated_checks_return_nothing_and_do_not_call_physical_current(self):
        store, fences = self.fixture()
        observations, retained = [], []
        def current():
            observations.append(True)
        def consume(reader):
            retained.append(reader)
            before = len(observations)
            for _ in range(3):
                self.assertIsNone(reader.check_unchanged(reader))
            self.assertEqual(len(observations), before)
        self.inspect(store, fences, consume, current)
        with self.assertRaises(ValueError):
            retained[0].check_unchanged(retained[0])

    def test_same_transaction_mutations_and_schema_changes_latch_original_failure(self):
        for sql in (
            "INSERT INTO core_bytes VALUES ('extra', 0, X'01')",
            "UPDATE core_bytes SET payload=X'01' WHERE key != 'control'",
            "CREATE TABLE extra (value INTEGER)",
            "CREATE TEMP TABLE core_bytes (key TEXT, generation INTEGER, payload BLOB)",
        ):
            with self.subTest(sql=sql):
                store, fences = self.fixture()
                failures = []
                def consume(reader):
                    reader.check_unchanged(reader)
                    store._connection.execute(sql)
                    for _ in range(2):
                        with self.assertRaises(LocalStorageError) as raised:
                            reader.check_unchanged(reader)
                        failures.append(raised.exception)
                    self.assertIs(failures[0], failures[1])
                with self.assertRaises(LocalStorageError) as outer:
                    self.inspect(store, fences, consume)
                self.assertIs(outer.exception, failures[0])
                self.assertFalse(store._connection.in_transaction)

    def test_transaction_replacement_and_supplier_replacement_are_rejected(self):
        for mutation in ('commit', 'restart', 'raw_commit', 'raw_rollback',
                         'adapter', 'connection', 'store_connection'):
            with self.subTest(mutation=mutation):
                store, fences = self.fixture()
                database, connection = store._physical, store._connection
                other = sqlite3.connect(':memory:', isolation_level=None)
                self.addCleanup(other.close)
                failures = []
                def consume(reader):
                    if mutation in ('commit', 'restart'):
                        database.commit()
                        if mutation == 'restart':
                            database.begin_read()
                    elif mutation in ('raw_commit', 'raw_rollback'):
                        statement = '/* original boundary */ ' + (
                            'COMMIT' if mutation == 'raw_commit' else 'ROLLBACK')
                        # Re-execute identical statements to exercise SQLite's
                        # prepared statement cache, not only first preparation.
                        for _ in range(2):
                            connection.execute(statement)
                            connection.execute('-- next original transaction\n BEGIN')
                    elif mutation == 'adapter':
                        store._physical = object()
                    elif mutation == 'connection':
                        database._connection = other
                        other.execute('BEGIN')
                    else:
                        store._connection = other
                    try:
                        with self.assertRaises((ValueError, LocalStorageError)) as raised:
                            reader.check_unchanged(reader)
                        failures.append(raised.exception)
                    finally:
                        store._physical = database
                        store._connection = connection
                        database._connection = connection
                    with self.assertRaises(type(failures[0])) as repeated:
                        reader.check_unchanged(reader)
                    self.assertIs(repeated.exception, failures[0])
                with self.assertRaises((ValueError, LocalStorageError)) as outer:
                    self.inspect(store, fences, consume)
                self.assertIs(outer.exception, failures[0])

    def test_closed_connection_is_refused_by_the_port_and_failure_is_latched(self):
        store, fences = self.fixture()
        database = store._physical
        database.begin_read()
        failures = []
        def consume(reader):
            database.close()
            for _ in range(2):
                with self.assertRaises(sqlite3.ProgrammingError) as raised:
                    reader.check_unchanged(reader)
                failures.append(raised.exception)
            self.assertIs(failures[0], failures[1])
        # Exercise the reader directly: enclosing transaction cleanup cannot
        # query a deliberately closed connection and has its own failure path.
        with self.assertRaises(sqlite3.ProgrammingError) as outer:
            store._inspect_namespace_locked(consume, fences, lambda: None)
        self.assertIs(outer.exception, failures[0])

    def test_copied_reader_foreign_thread_and_query_reentry_are_latched(self):
        for mode in ('copy', 'owner', 'thread', 'reentry'):
            with self.subTest(mode=mode):
                store, fences = self.fixture()
                failures = []
                def consume(reader):
                    def invalid():
                        try:
                            reader.check_unchanged(copy.copy(reader) if mode == 'copy' else reader)
                        except ValueError as error:
                            failures.append(error)
                    if mode == 'thread':
                        thread = Thread(target=invalid)
                        thread.start()
                        thread.join()
                    elif mode == 'reentry':
                        reader.scan_after('settings', '', lambda _: invalid())
                    elif mode == 'owner':
                        object.__setattr__(reader, 'owner', object())
                        try:
                            invalid()
                        finally:
                            object.__setattr__(reader, 'owner', store)
                    else:
                        invalid()
                    self.assertEqual(len(failures), 1)
                    with self.assertRaises(ValueError) as repeated:
                        reader.check_unchanged(reader)
                    self.assertIs(repeated.exception, failures[0])
                with self.assertRaises(ValueError) as outer:
                    self.inspect(store, fences, consume)
                self.assertIs(outer.exception, failures[0])

    def test_swallowed_reentry_during_snapshot_observation_is_not_success(self):
        store, fences = self.fixture()
        original = type(store._physical)._snapshot_identity
        failures = []
        def consume(reader):
            def observe(database):
                try:
                    reader.check_unchanged(reader)
                except ValueError as error:
                    failures.append(error)
                return original(database)
            with patch.object(type(store._physical), '_snapshot_identity', observe):
                with self.assertRaises(ValueError) as raised:
                    reader.check_unchanged(reader)
                self.assertIs(raised.exception, failures[0])
        with self.assertRaises(ValueError) as outer:
            self.inspect(store, fences, consume)
        self.assertIs(outer.exception, failures[0])

    def test_non_exact_adapter_has_no_port_and_unused_port_does_not_forbid_writes(self):
        store, fences = self.fixture()
        original = store._physical
        class PhysicalPort:
            def __getattr__(self, name):
                return getattr(original, name)
        store._physical = PhysicalPort()
        self.inspect(store, fences, lambda reader: self.assertIsNone(reader.check_unchanged))
        store._physical = original
        def write_without_check(reader):
            self.assertIsNotNone(reader.check_unchanged)
            store._connection.execute("INSERT INTO core_bytes VALUES ('extra', 0, X'01')")
        self.inspect(store, fences, write_without_check)

    def test_plain_sqlite_connection_does_not_supply_unchanged_port(self):
        store, fences = self.fixture()
        original, connection = store._physical, store._connection
        ordinary = sqlite3.connect(':memory:', isolation_level=None)
        self.addCleanup(ordinary.close)
        connection.backup(ordinary)
        store._physical, store._connection = _SQLiteByteDatabase(ordinary), ordinary
        try:
            self.inspect(store, fences, lambda reader: self.assertIsNone(reader.check_unchanged))
        finally:
            store._physical, store._connection = original, connection

    def test_savepoint_controls_preserve_outer_snapshot_but_not_write_free_span(self):
        store, fences = self.fixture()
        def consume(reader):
            connection = store._connection
            original = store._physical._snapshot_identity()
            control = connection._transaction_epoch
            connection.execute('SAVEPOINT held')
            connection.execute("UPDATE core_bytes SET payload=X'01' WHERE key != 'control'")
            connection.execute('/* before */ ROLLBACK /* middle */ TRANSACTION -- line\n TO held')
            connection.execute('RELEASE held')
            observed = store._physical._snapshot_identity()
            self.assertEqual(observed[1], original[1])
            self.assertGreater(observed[2], original[2])
            self.assertEqual(connection._transaction_epoch, control + 3)
            # General readers still re-fence the unchanged control row in the
            # same outer transaction after rolling back a temporary mutation.
            reader.current()
            with self.assertRaises(LocalStorageError):
                reader.check_unchanged(reader)
        with self.assertRaises(LocalStorageError):
            self.inspect(store, fences, consume)

    def test_outer_epoch_distinguishes_rollback_to_and_savepoint_restart(self):
        connection = sqlite3.connect(':memory:', isolation_level=None,
                                     factory=_TrackedSQLiteConnection)
        self.addCleanup(connection.close)
        connection.execute('SAVEPOINT "TO"')
        outer = connection._outer_transaction_epoch
        control = connection._transaction_epoch
        for statement in ('SAVEPOINT nested', 'ROLLBACK /* ignored */ TO nested',
                          'ROLLBACK TRANSACTION /* ignored */ TO nested', 'RELEASE nested'):
            connection.execute(statement)
            self.assertEqual(connection._outer_transaction_epoch, outer)
            control += 1
            self.assertEqual(connection._transaction_epoch, control)
        connection.execute('RELEASE "TO"')
        self.assertFalse(connection.in_transaction)
        connection.execute('/* new outer */ SAVEPOINT "BEGIN"')
        self.assertEqual(connection._outer_transaction_epoch, outer + 1)
        connection.execute('ROLLBACK /* TO inside a comment is not a keyword */ TRANSACTION')
        self.assertEqual(connection._outer_transaction_epoch, outer + 2)
        connection.execute('BEGIN')
        self.assertEqual(connection._outer_transaction_epoch, outer + 3)
        connection.execute('ROLLBACK')

    def test_savepoint_without_writes_also_invalidates_explicit_read_only_span(self):
        store, fences = self.fixture()
        def consume(reader):
            original = store._physical._snapshot_identity()
            for statement in ('SAVEPOINT held', 'ROLLBACK TO held', 'RELEASE held'):
                store._connection.execute(statement)
            self.assertEqual(store._physical._snapshot_identity(), original)
            reader.current()
            reader.check_unchanged(reader)
            self.fail('Savepoint control escaped the explicit write-free check')
        with self.assertRaises(LocalStorageError):
            self.inspect(store, fences, consume)

    def test_trace_registration_preserves_tracking_and_user_statements(self):
        connection = sqlite3.connect(':memory:', isolation_level=None,
                                     factory=_TrackedSQLiteConnection)
        self.addCleanup(connection.close)
        first, second = [], []
        for callback in (first.append, second.append, None):
            connection.set_trace_callback(callback)
            before = connection._transaction_epoch
            for statement in (' \n/* comment */ BEGIN', '-- comment\n SAVEPOINT held',
                              'ROLLBACK TO held', 'RELEASE held', 'END'):
                connection.execute(statement)
                self.assertGreater(connection._transaction_epoch, before)
                before = connection._transaction_epoch
            for statement in ('SELECT 1', "SELECT 'BEGIN COMMIT ROLLBACK'",
                              '-- BEGIN\n SELECT 2', '/* COMMIT */ SELECT 3'):
                connection.execute(statement)
                self.assertEqual(connection._transaction_epoch, before)
        self.assertEqual(first, second)
        self.assertIn('ROLLBACK TO held', first)
        with self.assertRaises(TypeError):
            connection.set_trace_callback(object())
        before = connection._transaction_epoch
        connection.execute('BEGIN')
        self.assertGreater(connection._transaction_epoch, before)
        connection.execute('ROLLBACK')

    def test_recursive_trace_transaction_sql_is_tracked_and_exceptions_stay_sqlite_owned(self):
        connection = sqlite3.connect(':memory:', isolation_level=None,
                                     factory=_TrackedSQLiteConnection)
        self.addCleanup(connection.close)
        connection.execute('BEGIN')
        invoked = False
        def trace(statement):
            nonlocal invoked
            if not invoked:
                invoked = True
                connection.execute('COMMIT')
                connection.execute('BEGIN')
                raise RuntimeError('SQLite owns diagnostic callback exceptions')
        connection.set_trace_callback(trace)
        before = connection._transaction_epoch
        self.assertEqual(connection.execute('SELECT 1').fetchone(), (1,))
        self.assertEqual(connection._transaction_epoch, before + 2)
        self.assertTrue(invoked)
        connection.set_trace_callback(None)
        connection.execute('ROLLBACK')


if __name__ == '__main__':
    unittest.main()
