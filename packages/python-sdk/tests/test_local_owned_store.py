"""Actual pre-SQL file custody; not Host adoption or public Local acceptance."""
import copy
import json
import os
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileRoot, LocalFileError
from actql_sdk._local_storage import ByteWrite, LocalByteStore, LocalStorageError
from actql_sdk._local_submission import LocalSubmissionAuthority, LocalSubmissionIdentityError


class LocalOwnedStoreInitializationTests(unittest.TestCase):
    def fixture(self):
        directory = TemporaryDirectory(prefix='actql-owned-store-')
        self.addCleanup(directory.cleanup)
        path = Path(directory.name)
        root = LocalFileRoot(path, max_files=4, max_chunk_bytes=16)
        self.addCleanup(root.close)
        value = root.create_writer('client.sqlite3', 0)
        self.addCleanup(lambda: root.close_writer(value) if id(value) in root._files else None)
        return path, root, value

    def open(self, path, root, original):
        store = LocalByteStore.initialize_owned_file(path, root, original,
            max_records=8, max_record_bytes=4096, max_payload_bytes=32768)
        self.addCleanup(store.close)
        return store

    def test_owned_journal_format_keeps_unique_definition_in_original_transaction(self):
        path, root, original = self.fixture()
        store = self.open(path / original.name, root, original)
        self.assertEqual(store._connection.execute('PRAGMA user_version').fetchone(), (3,))
        expected = ("CREATE UNIQUE INDEX actql_client_run_definition_unique ON core_bytes("
                    "json_extract(json_extract(CAST(payload AS TEXT),'$.run_definition'),"
                    "'$.run_definition_cid')) WHERE key>='namespace:11:client_runs:' "
                    "AND key<'namespace:11:client_runs;'")
        self.assertEqual(store._connection.execute(
            "SELECT sql FROM sqlite_schema WHERE name='actql_client_run_definition_unique'").fetchone(),
            (expected,))
        # Physical index vectors only: these are not admitted Run originals.
        body = json.dumps({'run_definition': json.dumps({'run_definition_cid': 'sha256:' + 'a' * 64})}).encode()
        first = store.namespaced_key('client_runs', 'first')
        second = store.namespaced_key('client_runs', 'second')
        self.assertEqual(store.compare_exchange(first, None, body), 0)
        with self.assertRaises(sqlite3.IntegrityError):
            store.compare_exchange_many((ByteWrite('original-counter', None, b'1'),
                                         ByteWrite(second, None, body)))
        self.assertIsNone(store.read(second))
        self.assertIsNone(store.read('original-counter'))
        self.assertEqual(store.read(first).payload, body)

    def test_owned_journal_schema_observation_is_fresh_and_needs_same_transaction(self):
        path, root, original = self.fixture()
        store = self.open(path / original.name, root, original)
        database = store._physical
        with self.assertRaises(ValueError):
            database._journal_schema()
        database.begin_read()
        try:
            self.assertEqual(database._journal_schema(), 1)
            store._connection.execute('DROP INDEX actql_client_run_definition_unique')
            with self.assertRaises(ValueError):
                database._journal_schema()
        finally:
            database.finish_read()
        database.begin_read()
        try:
            self.assertEqual(database._journal_schema(), 1)
        finally:
            database.finish_read()

    def test_owned_journal_reopen_refuses_missing_or_colliding_index_without_repair(self):
        for colliding in (False, True):
            with self.subTest(colliding=colliding):
                path, root, original = self.fixture()
                filename = path / original.name
                store = self.open(filename, root, original)
                store.close()
                with sqlite3.connect(filename) as physical:
                    physical.execute('DROP INDEX actql_client_run_definition_unique')
                    if colliding:
                        physical.execute('CREATE UNIQUE INDEX actql_client_run_definition_unique ON core_bytes(key)')
                    before = physical.execute('SELECT name, sql FROM sqlite_schema ORDER BY name').fetchall()
                with self.assertRaisesRegex(LocalStorageError, 'physical storage format'):
                    LocalByteStore(filename, max_records=8, max_record_bytes=4096,
                                   max_payload_bytes=32768)
                with sqlite3.connect(filename) as physical:
                    self.assertEqual(physical.execute('PRAGMA user_version').fetchone(), (3,))
                    self.assertEqual(physical.execute('SELECT name, sql FROM sqlite_schema ORDER BY name').fetchall(), before)

    def test_raw_legacy_store_stays_format_two_and_is_never_migrated_on_observation(self):
        with TemporaryDirectory(prefix='actql-legacy-journal-format-') as directory:
            filename = Path(directory) / 'legacy.sqlite3'
            store = LocalByteStore(filename, max_records=8, max_record_bytes=4096,
                                   max_payload_bytes=32768)
            self.addCleanup(store.close)
            database = store._physical
            database.begin_read()
            try:
                self.assertEqual(database._journal_schema(), 0)
            finally:
                database.finish_read()
            self.assertEqual(store._connection.execute('PRAGMA user_version').fetchone(), (2,))
            self.assertIsNone(store._connection.execute(
                "SELECT sql FROM sqlite_schema WHERE name='actql_client_run_definition_unique'").fetchone())
            store.close()
            reopened = LocalByteStore(filename, max_records=8, max_record_bytes=4096,
                                      max_payload_bytes=32768)
            self.addCleanup(reopened.close)
            self.assertEqual(reopened._connection.execute('PRAGMA user_version').fetchone(), (2,))

    def test_original_file_generation_is_bound_before_sql_and_claimed_once(self):
        path, root, value = self.fixture()
        observed = root.observe(value)
        # Durable original intent precedes the physical schema/key operation.
        # This independent byte marker makes no claim to a Core contract.
        marker = root.create_writer('journal-initializing.json', 16)
        root.append(marker, 0, b'original-intent')
        root.sync(marker)
        self.assertTrue(root.close_writer(marker))
        store = self.open(path / value.name, root, value)
        self.assertEqual(store.observe_generation(),
                         (observed.identity.device, observed.identity.inode))
        self.assertTrue(store.claim_creation())
        self.assertFalse(store.claim_creation())
        self.assertTrue(value.store_claimed)
        self.assertFalse(root.close())
        self.assertEqual((path / 'journal-initializing.json').read_bytes(), b'original-intent')
        self.assertIsNone(store.read('absent'))
        self.assertTrue(root.close_writer(value))
        self.assertTrue(root.close())

    def test_reopened_empty_file_does_not_create_schema_or_authority(self):
        path, root, value = self.fixture()
        self.assertTrue(root.close_writer(value))
        self.assertTrue(root.close())
        with self.assertRaisesRegex(LocalStorageError, 'no initialization custody'):
            LocalByteStore(path / value.name, max_records=8,
                max_record_bytes=4096, max_payload_bytes=32768)
        self.assertEqual((path / value.name).read_bytes(), b'')
        connection = sqlite3.connect(path / value.name)
        self.addCleanup(connection.close)
        self.assertEqual(connection.execute("SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'").fetchall(), [])
        self.assertEqual(connection.execute('PRAGMA application_id').fetchone()[0], 0)

    def test_copied_foreign_closed_and_replaced_files_refuse_before_sql(self):
        for invalid in ('copy', 'foreign_path', 'closed', 'replaced'):
            with self.subTest(invalid=invalid):
                path, root, value = self.fixture()
                original = value
                candidate = path / value.name
                if invalid == 'copy':
                    original = copy.copy(value)
                elif invalid == 'foreign_path':
                    candidate = path / 'other.sqlite3'
                elif invalid == 'closed':
                    root.close_writer(value)
                else:
                    candidate.rename(path / 'original.sqlite3')
                    candidate.write_bytes(b'')
                    candidate.chmod(0o600)
                with patch('actql_sdk._local_storage.sqlite3.connect', side_effect=AssertionError('Invalid acquisition reached SQL')):
                    with self.assertRaises((LocalFileError, ValueError)):
                        self.open(candidate, root, original)
                self.assertFalse(value.store_claimed)

    def test_failure_after_claim_preserves_consumed_file_and_does_not_retry_or_repair(self):
        path, root, value = self.fixture()
        failure = OSError('Original SQL opening is unknown')
        with patch('actql_sdk._local_storage.sqlite3.connect', side_effect=failure) as opened:
            with self.assertRaises(OSError) as raised:
                self.open(path / value.name, root, value)
            self.assertIs(raised.exception, failure)
            self.assertEqual(opened.call_count, 1)
            with self.assertRaises(LocalFileError):
                self.open(path / value.name, root, value)
            self.assertEqual(opened.call_count, 1)
        self.assertTrue(value.store_claimed)
        self.assertFalse(root.close())
        self.assertEqual((path / value.name).read_bytes(), b'')
        self.assertTrue(root.close_writer(value))
        with self.assertRaises(LocalStorageError):
            LocalByteStore(path / value.name, max_records=8,
                max_record_bytes=4096, max_payload_bytes=32768)

    def test_new_owned_file_supplies_original_epoch_key_but_reopen_never_recreates_it(self):
        path, root, value = self.fixture()
        store = self.open(path / value.name, root, value)
        projected = []
        authority = LocalSubmissionAuthority(store, lambda *args: projected.append(args), now=lambda: 0)
        self.assertIsNone(authority.observe_custody())
        original = store.read('submission-epoch-authority')
        self.assertEqual(original.generation, 0)
        store.close()
        self.assertTrue(root.close_writer(value))
        reopened = LocalByteStore(path / value.name, max_records=8,
            max_record_bytes=4096, max_payload_bytes=32768)
        self.addCleanup(reopened.close)
        self.assertFalse(reopened.claim_creation())
        current = LocalSubmissionAuthority(reopened, lambda *args: projected.append(args), now=lambda: 0)
        self.assertEqual(current.custody_fence().payload, original.payload)
        reopened._connection.execute('DELETE FROM core_bytes WHERE key=?', ('submission-epoch-authority',))
        with self.assertRaises(LocalSubmissionIdentityError):
            LocalSubmissionAuthority(reopened, lambda *args: projected.append(args), now=lambda: 0)
        self.assertEqual(projected, [])
        self.assertIsNone(reopened.read('submission-epoch-authority'))

    def test_claimed_writer_cannot_resume_payload_work_and_failure_keeps_same_descriptor(self):
        path, root, value = self.fixture()
        self.open(path / value.name, root, value)
        descriptor = value.descriptor
        with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('Claimed writer IO')):
            with self.assertRaises(LocalFileError):
                root.append(value, 0, b'x')
        with self.assertRaises(LocalFileError):
            root.sync(value)
        with self.assertRaises(LocalFileError):
            root.begin_snapshot(value)
        with patch('actql_sdk._local_files.os.close', side_effect=OSError('Original stop unknown')) as stopped:
            self.assertFalse(root.close_writer(value))
            self.assertFalse(root.close_writer(value))
            self.assertEqual(stopped.call_count, 1)
        self.assertIs(root._files[id(value)], value)
        self.assertFalse(root.close())
        os.close(descriptor)
        with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('Double stop')):
            self.assertTrue(root.close_writer(value))


if __name__ == '__main__':
    unittest.main()
