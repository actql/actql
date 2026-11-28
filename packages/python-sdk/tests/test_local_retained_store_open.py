"""Real SQLite files and physical replacement at the retained-open cutoff."""
from contextlib import closing
from hashlib import sha256
from tempfile import TemporaryDirectory
from pathlib import Path
from selectors import DefaultSelector, EVENT_READ
import json
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import actql_sdk._local_storage as storage
import actql_sdk._local_storage_admission as admission
from actql_sdk._local_files import LocalFileRoot
from actql_sdk._local_storage import (
    ByteWrite, LocalByteStore, LocalStorageError, LocalStorageInitializationError, StoredBytes,
)
from actql_sdk._local_storage_physical import _APPLICATION_ID, _SQLiteByteDatabase, _TrackedSQLiteConnection

JOURNAL_MAGIC = bytes.fromhex('d9d505f920a163d7')
RECORD_BYTES = 4096
N = 64
WRITER = __file__
HOT_LIMITS = dict(max_records=256, max_record_bytes=8192, max_payload_bytes=2097152)

LIMITS = dict(max_records=16, max_record_bytes=4096, max_payload_bytes=65536)

def create(path):
    store = LocalByteStore(path, **LIMITS)
    try:
        assert store.compare_exchange('same', None, b'closed original') == 0
    finally:
        store.close()

def physical(path):
    return path.stat().st_ino, sha256(path.read_bytes()).hexdigest()


def setup_hot_control(path):
    with closing(LocalByteStore(path, **HOT_LIMITS)) as store:
        assert store.compare_exchange_many(tuple(
            ByteWrite(f'bench:{index:03d}', None, b'A' * RECORD_BYTES)
            for index in range(N))) == (0,) * N
    return path.with_name(path.name + '-journal')


def retained(path):
    return LocalByteStore(path, **HOT_LIMITS)


def physical_file(path):
    stat = path.stat()
    return (stat.st_dev, stat.st_ino, stat.st_size, sha256(path.read_bytes()).hexdigest())


def spill_writer(path, role, terminate):
    # Force SQLite to spill changed pages before COMMIT. The child confirms
    # physical database writeback and rollback journal evidence before dying.
    old = physical_file(path)
    journal = path.with_name(path.name + '-journal')
    # Closing another descriptor for this database in the writer process would
    # drop SQLite's POSIX locks. Keep the observation descriptor until rollback.
    with (path.open('rb') as observed_database,
          closing(sqlite3.connect(path, isolation_level=None)) as db):
        assert db.execute('PRAGMA journal_mode=DELETE').fetchone() == ('delete',)
        db.execute('PRAGMA synchronous=EXTRA')
        db.execute('PRAGMA cache_size=2')
        db.execute('PRAGMA cache_spill=1')
        db.execute('BEGIN IMMEDIATE')
        if role == 'current':
            db.execute("UPDATE core_bytes SET payload = ? WHERE key LIKE 'bench:%'",
                       (b'B' * RECORD_BYTES,))
            db.execute("INSERT INTO core_bytes(key, generation, payload) VALUES('uncommitted',0,X'55')")
        else:
            db.execute("UPDATE foreign_rows SET payload = ?", (b'B' * RECORD_BYTES,))
        assert journal.read_bytes()[:8] == JOURNAL_MAGIC
        assert sha256(observed_database.read()).hexdigest() != old[3]
        print(json.dumps({'spilled': True, 'journal': physical_file(journal)}), flush=True)
        if terminate:
            os.kill(os.getpid(), signal.SIGKILL)
        assert sys.stdin.readline() == 'rollback\n'
        db.execute('ROLLBACK')


def check(root, role):
    folder = root / role
    folder.mkdir(mode=0o700)
    path = folder / 'physical.sqlite3'
    journal = folder / 'physical.sqlite3-journal'
    if role == 'current':
        store = retained(path)
        try:
            assert store.compare_exchange_many(tuple(
                ByteWrite(f'bench:{index:03d}', None, b'A' * RECORD_BYTES)
                for index in range(N))) == (0,) * N
        finally:
            store.close()
    else:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)
        with closing(sqlite3.connect(path, isolation_level=None)) as db:
            assert db.execute('PRAGMA journal_mode=DELETE').fetchone() == ('delete',)
            db.execute('CREATE TABLE foreign_rows (id INTEGER PRIMARY KEY,payload BLOB)')
            if role == 'same-marker-foreign':
                db.execute(f'PRAGMA application_id={_APPLICATION_ID}')
            db.executemany('INSERT INTO foreign_rows VALUES (?, ?)',
                           [(index, b'A' * RECORD_BYTES) for index in range(N)])
    current_when_committed = physical_file(path)
    writer = subprocess.run([sys.executable, '-B', __file__, 'kill', str(path), role],
                            timeout=20, capture_output=True, text=True)
    assert writer.returncode == -signal.SIGKILL, (writer.returncode, writer.stderr)
    assert json.loads(writer.stdout)['spilled']
    before = physical_file(path), physical_file(journal)
    assert before[0] != current_when_committed
    if role == 'current':
        store = retained(path)
        try:
            assert all(store.read(f'bench:{index:03d}').payload == b'A' * RECORD_BYTES
                       for index in range(N))
            assert store.read('uncommitted') is None
            assert store._connection.execute('PRAGMA synchronous').fetchone() == (3,)
        finally:
            store.close()
        assert not journal.exists()
        return {'kind': role, 'successfulRecovery': True, 'sameDBGeneration': before[0][:2] == physical_file(path)[:2]}
    try:
        reopened = retained(path)
    except LocalStorageError as refused:
        return {'kind': role, 'refusal': str(refused), 'dbSame': physical_file(path) == before[0],
                'journalSame': journal.is_file() and physical_file(journal) == before[1]}
    reopened.close()
    raise AssertionError('Foreign format accepted')


class RetainedOpenTests(unittest.TestCase):
    def test_registered_primitive_adapter_refuses_before_opening_original_sqlite(self):
        with TemporaryDirectory() as location:
            path = Path(location) / 'original.sqlite3'
            fresh = Path(location) / 'fresh.sqlite3'
            create(path)
            original = physical_file(path)
            invoked = []

            def adapt(value):
                invoked.append(value)
                return value

            for primitive in (str, int, bytes):
                with self.subTest(primitive=primitive):
                    key = (primitive, sqlite3.PrepareProtocol)
                    previous = sqlite3.adapters.get(key)
                    sqlite3.register_adapter(primitive, adapt)
                    try:
                        with patch.object(sqlite3, 'connect', wraps=sqlite3.connect) as connect:
                            for selected in (path, fresh):
                                with self.assertRaisesRegex(LocalStorageError, primitive.__name__):
                                    LocalByteStore(selected, **LIMITS)
                        connect.assert_not_called()
                    finally:
                        if previous is None:
                            sqlite3.adapters.pop(key, None)
                        else:
                            sqlite3.adapters[key] = previous
                    self.assertEqual(physical_file(path), original)
                    self.assertFalse(fresh.exists())
            self.assertFalse(invoked)

    def test_lost_initial_commit_closes_original_then_reopens_current_catalog(self):
        real_commit = _SQLiteByteDatabase.commit
        real_close = _TrackedSQLiteConnection.close
        lost_reply = OSError('Original initialization COMMIT reply lost')
        committed = []
        closed = []

        def lose_commit(database):
            self.assertTrue(database.in_transaction)
            real_commit(database)
            self.assertFalse(database.in_transaction)
            committed.append(database._connection)
            raise lost_reply

        def observe_close(connection):
            in_transaction = connection.in_transaction
            real_close(connection)
            closed.append((connection, in_transaction))

        with (TemporaryDirectory() as location,
              patch.object(_TrackedSQLiteConnection, 'close', observe_close)):
            path = Path(location) / 'client.sqlite3'
            with patch.object(_SQLiteByteDatabase, 'commit', lose_commit):
                with self.assertRaises(OSError) as failure:
                    LocalByteStore(path, **LIMITS)
            self.assertIs(failure.exception, lost_reply)
            self.assertEqual(len(committed), 1)
            self.assertEqual(closed, [(committed[0], False)])
            original_file = physical_file(path)
            self.assertFalse(path.with_name(path.name + '-journal').exists())
            with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as connection:
                self.assertEqual(connection.execute('PRAGMA main.application_id').fetchone(), (_APPLICATION_ID,))
                self.assertEqual(connection.execute('SELECT reservations FROM main.actql_store_usage').fetchone(), (0,))

            with patch.object(_SQLiteByteDatabase, 'begin_read', autospec=True,
                              side_effect=_SQLiteByteDatabase.begin_read) as begin:
                reopened = LocalByteStore(path, **LIMITS)
            catalog, adopted = [call.args[0] for call in begin.call_args_list]
            self.assertIs(adopted._connection, reopened._connection)
            self.assertEqual(closed, [(committed[0], False), (catalog._connection, True)])
            self.assertEqual(physical_file(path), original_file)
            with reopened:
                self.assertEqual(reopened.compare_exchange('original', None, b'kept'), 0)
                self.assertEqual(reopened.read('original'), StoredBytes(0, b'kept'))
            reopened.close()
            self.assertEqual(closed, [(committed[0], False), (catalog._connection, True),
                                      (adopted._connection, False)])

    def test_foreign_hot_journals_leave_both_original_files_intact(self):
        with TemporaryDirectory(prefix='actql-sqlite-hot-foreign-') as location:
            for role in ('foreign', 'same-marker-foreign'):
                with self.subTest(role=role):
                    result = check(Path(location), role)
                    self.assertTrue(result['dbSame'])
                    self.assertTrue(result['journalSame'])

    def test_future_catalog_with_the_same_marker_is_untouched(self):
        with tempfile.TemporaryDirectory() as location:
            path = Path(location) / 'client.sqlite3'
            create(path)
            with closing(sqlite3.connect(path, isolation_level=None)) as connection:
                connection.execute('PRAGMA user_version = 999')
            before = physical(path)
            real_connect = sqlite3.connect
            opened = []

            def connect(target, *args, **kwargs):
                opened.append(str(target))
                return real_connect(target, *args, **kwargs)

            with (patch.object(sqlite3, 'connect', side_effect=connect),
                  patch.object(_SQLiteByteDatabase, 'begin_read', autospec=True,
                               side_effect=_SQLiteByteDatabase.begin_read) as begin):
                with self.assertRaisesRegex(LocalStorageError, 'physical storage format'):
                    LocalByteStore(path, **LIMITS)
            self.assertEqual(opened, [path.as_uri()+'?mode=ro'])
            begin.assert_called_once()
            inspection = begin.call_args.args[0]
            with self.assertRaises(sqlite3.ProgrammingError):
                inspection._connection.execute('SELECT 1')
            self.assertEqual(physical(path), before)
            self.assertFalse(path.with_name('client.sqlite3-journal').exists())

    def test_corrupted_catalog_refuses_before_original_write(self):
        with tempfile.TemporaryDirectory() as location:
            path = Path(location) / 'client.sqlite3'
            create(path)
            with closing(sqlite3.connect(path, isolation_level=None)) as connection:
                page = connection.execute('PRAGMA page_size').fetchone()[0]
            with path.open('r+b') as file:
                file.seek(100)
                file.write(bytes(page - 100))
            original = physical(path)
            real_connect = sqlite3.connect
            opened = []

            def connect(target, *args, **kwargs):
                opened.append(str(target))
                return real_connect(target, *args, **kwargs)

            with patch.object(sqlite3, 'connect', side_effect=connect):
                with self.assertRaisesRegex(LocalStorageError, 'physical storage format'):
                    LocalByteStore(path, **LIMITS)
            self.assertEqual(opened, [path.as_uri()+'?mode=ro'])
            self.assertEqual(physical(path), original)
            self.assertFalse(path.with_name('client.sqlite3-journal').exists())

    def test_inspection_close_keeps_original_refusal_and_same_connection(self):
        with tempfile.TemporaryDirectory() as location:
            path = Path(location) / 'client.sqlite3'
            create(path)
            with closing(sqlite3.connect(path, isolation_level=None)) as connection:
                connection.execute('PRAGMA user_version = 999')
            original = physical(path)
            secondary = OSError('test retained connection close before physical return')
            calls = []
            opened = []
            connect = sqlite3.connect

            class InspectionConnection(_TrackedSQLiteConnection):
                def close(self):
                    calls.append(self)
                    if len(calls) == 1:
                        raise secondary
                    super().close()

            def tracked(target, *args, **kwargs):
                opened.append(str(target))
                return connect(target, *args, **{**kwargs, 'factory': InspectionConnection})

            with patch.object(sqlite3, 'connect', side_effect=tracked):
                with self.assertRaises(LocalStorageInitializationError) as pending:
                    LocalByteStore(path, **LIMITS)
            self.assertEqual(opened, [path.as_uri()+'?mode=ro'])
            failure = pending.exception
            self.assertEqual(str(failure.__cause__), 'Unknown Local physical storage format')
            self.assertEqual(str(failure.__cause__.__cause__),
                             'Unsupported Local rollback Store generation')
            store = failure.cleanup_store
            self.assertIs(store._catalog_inspection.failure, secondary)
            self.assertEqual(len(calls), 1)
            store.close()
            self.assertIsNone(store._catalog_inspection)
            self.assertEqual(len(calls), 2)
            self.assertIs(calls[0], calls[1])
            self.assertEqual(physical(path), original)

    def test_replaced_file_is_caught_before_writable_catalog_or_recovery(self):
        with tempfile.TemporaryDirectory() as location:
            directory = Path(location)
            path = directory / 'client.sqlite3'
            old, replacement = directory/'initial.sqlite3', directory/'staged.sqlite3'
            create(path)
            create(replacement)
            original, foreign = physical(path), physical(replacement)
            real_connect = sqlite3.connect
            observed = []

            def connect(target, *args, **kwargs):
                if str(target).endswith('?mode=rw'):
                    subprocess.run([sys.executable, '-B', '-c',
                        'import os,sys; os.replace(*sys.argv[1:3]); os.replace(*sys.argv[3:5])',
                        str(path), str(old), str(replacement), str(path)], check=True, timeout=10)
                    observed.append('physically replaced')
                return real_connect(target, *args, **kwargs)

            with patch.object(sqlite3, 'connect', side_effect=connect):
                with self.assertRaisesRegex(LocalStorageError, 'generation changed'):
                    LocalByteStore(path, **LIMITS)
            self.assertEqual(observed, ['physically replaced'])
            self.assertEqual(physical(old), original)
            self.assertEqual(physical(path), foreign)

    def test_same_inode_change_after_inspector_refuses_before_writable_open(self):
        with tempfile.TemporaryDirectory() as location:
            path = Path(location) / 'client.sqlite3'
            create(path)
            inspect = storage.inspect_retained_catalog
            original = physical(path)
            mutated = []
            def inspect_then_change(*args, **kwargs):
                result = inspect(*args, **kwargs)
                with closing(sqlite3.connect(path, isolation_level=None)) as connection:
                    connection.execute('PRAGMA user_version = 12')
                mutated.append(physical(path))
                return result
            with patch.object(storage, 'inspect_retained_catalog', side_effect=inspect_then_change):
                with self.assertRaisesRegex(ValueError, 'changed during retained inspection'):
                    LocalByteStore(path, **LIMITS)
            self.assertEqual(physical(path), mutated[0])
            self.assertEqual(original[0], mutated[0][0])
            self.assertNotEqual(original[1], mutated[0][1])

    def test_spilled_live_writer_refuses_without_mutating_either_original(self):
        with tempfile.TemporaryDirectory() as location:
            path = Path(location) / 'client.sqlite3'
            journal = setup_hot_control(path)
            with subprocess.Popen([sys.executable, '-B', WRITER, 'wait', str(path), 'current'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True) as writer:
                try:
                    with DefaultSelector() as selector:
                        selector.register(writer.stdout, EVENT_READ)
                        self.assertTrue(selector.select(timeout=10))
                    self.assertTrue(json.loads(writer.stdout.readline())['spilled'])
                    original = (physical(path), physical(journal))
                    with self.assertRaisesRegex(LocalStorageError, 'physical storage format'):
                        LocalByteStore(path, **HOT_LIMITS)
                    self.assertEqual((physical(path), physical(journal)), original)
                    _, errors = writer.communicate('rollback\n', timeout=10)
                    self.assertEqual(writer.returncode, 0, errors)
                finally:
                    if writer.poll() is None:
                        writer.kill()
                        writer.wait(timeout=10)
            self.assertFalse(journal.exists())
            with closing(LocalByteStore(path, **HOT_LIMITS)) as store:
                self.assertEqual(store.read('bench:000').payload, b'A' * RECORD_BYTES)
                self.assertIsNone(store.read('uncommitted'))

    def test_replaced_hot_journal_with_equal_bytes_refuses_before_recovery(self):
        with tempfile.TemporaryDirectory() as location:
            path = Path(location) / 'client.sqlite3'
            journal = setup_hot_control(path)
            writer = subprocess.run([sys.executable, '-B', WRITER, 'kill', str(path), 'current'],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(writer.returncode, -signal.SIGKILL, writer.stderr)
            self.assertTrue(json.loads(writer.stdout)['spilled'])
            original = (physical(path), physical(journal))
            replacement = path.with_name('replacement')
            replacement.write_bytes(journal.read_bytes())
            replacement.chmod(0o600)
            successor = physical(replacement)
            self.assertNotEqual(successor[0], original[1][0])
            self.assertEqual(successor[1], original[1][1])
            copy_exact = admission._copy_exact
            copied = []

            def replace_journal_after_copy(descriptor, stamp, destination, inspection):
                copy_exact(descriptor, stamp, destination, inspection)
                copied.append(destination.name)
                if destination.name.endswith('-journal'):
                    os.replace(replacement, journal)

            with patch.object(admission, '_copy_exact', side_effect=replace_journal_after_copy):
                with self.assertRaisesRegex(LocalStorageError, 'physical storage format'):
                    LocalByteStore(path, **HOT_LIMITS)
            self.assertEqual(copied, ['original.sqlite3', 'original.sqlite3-journal'])
            self.assertEqual(physical(path), original[0])
            self.assertEqual(physical(journal), successor)

    def test_hot_current_recovers_under_the_existing_exclusive_file_root(self):
        with tempfile.TemporaryDirectory() as location:
            directory = Path(location)
            path = directory / 'client.sqlite3'
            journal = setup_hot_control(path)
            writer = subprocess.run([sys.executable, '-B', WRITER, 'kill', str(path), 'current'],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(writer.returncode, -signal.SIGKILL, writer.stderr)
            self.assertTrue(json.loads(writer.stdout)['spilled'])
            generation = physical(path)[0]
            root = LocalFileRoot(directory, max_files=16, max_chunk_bytes=16384)
            try:
                with closing(LocalByteStore.reopen_owned_file(path, root, **HOT_LIMITS)) as store:
                    self.assertEqual(store.observe_generation()[1], generation)
                    self.assertEqual(store._connection.execute('PRAGMA journal_mode').fetchone(), ('delete',))
                    self.assertEqual(store._connection.execute('PRAGMA synchronous').fetchone(), (3,))
                    self.assertIsNone(store.read('uncommitted'))
                    self.assertTrue(all(store.read(f'bench:{i:03}').payload == b'A' * RECORD_BYTES
                                        for i in range(N)))
            finally:
                self.assertTrue(root.close())
            self.assertFalse(journal.exists())

if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] in ('kill', 'wait'):
        spill_writer(Path(sys.argv[2]), sys.argv[3], sys.argv[1] == 'kill')
    else:
        unittest.main()
