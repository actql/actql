"""Actual SQLite/path observations; no Host adoption or authority claim."""
import copy
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import LocalByteStore, LocalStorageError


class LocalStoreGenerationTests(unittest.TestCase):
    def store(self, path):
        return LocalByteStore(path, max_records=4, max_record_bytes=128, max_payload_bytes=512)

    def test_original_identity_survives_sqlite_writes_and_explicit_reopen(self):
        with TemporaryDirectory(prefix='actql-store-generation-') as directory:
            path = Path(directory) / 'core.sqlite'
            store = self.store(path)
            original = path.stat()
            expected = (original.st_dev, original.st_ino)
            self.assertEqual(store.observe_generation(), expected)
            self.assertEqual(store.compare_exchange('original', None, b'null/e\xcc\x81\r\n'), 0)
            self.assertEqual(store.observe_generation(), expected)
            self.assertEqual(store.read('original').payload, b'null/e\xcc\x81\r\n')
            store.close()
            with self.assertRaises(LocalStorageError):
                store.observe_generation()
            reopened = self.store(path)
            self.assertEqual(reopened.observe_generation(), expected)
            self.assertFalse(reopened.claim_creation())
            reopened.close()

    def test_replacement_database_is_not_original_or_automatically_adopted(self):
        with TemporaryDirectory(prefix='actql-store-generation-') as directory:
            root = Path(directory)
            path = root / 'core.sqlite'
            store = self.store(path)
            expected = store.observe_generation()
            store.compare_exchange('original', None, b'original')
            path.rename(root / 'retained.sqlite')
            replacement = self.store(path)
            self.assertNotEqual(replacement.observe_generation(), expected)
            replacement.compare_exchange('foreign', None, b'foreign')
            with self.assertRaisesRegex(LocalStorageError, 'generation changed'):
                store.observe_generation()
            # A physical failure retains the old connection; no lookup on the
            # replacement supplies a missing original row or resend permission.
            self.assertEqual(store.read('original').payload, b'original')
            self.assertIsNone(store.read('foreign'))
            store.close()
            self.assertEqual(replacement.read('foreign').payload, b'foreign')
            replacement.close()

    def test_replaced_parent_is_refused_even_when_original_file_inode_is_preserved(self):
        with TemporaryDirectory(prefix='actql-store-generation-') as directory:
            root = Path(directory)
            parent = root / 'private'
            parent.mkdir(mode=0o700)
            path = parent / 'core.sqlite'
            store = self.store(path)
            expected = store.observe_generation()
            parent.rename(root / 'old')
            parent.mkdir(mode=0o700)
            os.link(root / 'old/core.sqlite', path)
            self.assertEqual((path.stat().st_dev, path.stat().st_ino), expected)
            with self.assertRaisesRegex(LocalStorageError, 'directory generation'):
                store.observe_generation()
            store.close()

    def test_missing_symlink_and_permission_changes_supply_no_generation(self):
        with TemporaryDirectory(prefix='actql-store-generation-') as directory:
            root = Path(directory)
            path = root / 'core.sqlite'
            store = self.store(path)
            path.chmod(0o644)
            with self.assertRaises(LocalStorageError):
                store.observe_generation()
            path.chmod(0o600)
            path.rename(root / 'retained.sqlite')
            with self.assertRaises(FileNotFoundError):
                store.observe_generation()
            path.symlink_to(root / 'retained.sqlite')
            with self.assertRaises(LocalStorageError):
                store.observe_generation()
            store.close()
            self.assertTrue(path.is_symlink())
            self.assertTrue((root / 'retained.sqlite').is_file())

    def test_copied_store_refuses_before_path_or_sqlite_io(self):
        with TemporaryDirectory(prefix='actql-store-generation-') as directory:
            store = self.store(Path(directory) / 'core.sqlite')
            with patch('pathlib.Path.lstat', side_effect=AssertionError('copied path I/O')):
                with self.assertRaises(ValueError):
                    copy.copy(store).observe_generation()
            store.close()

    def test_generation_inside_transaction_is_only_physical_and_does_not_commit(self):
        with TemporaryDirectory(prefix='actql-store-generation-') as directory:
            store = self.store(Path(directory) / 'core.sqlite')
            expected = store.observe_generation()
            store._connection.execute('BEGIN IMMEDIATE')
            self.assertEqual(store.observe_generation(), expected)
            self.assertTrue(store._connection.in_transaction)
            with patch('pathlib.Path.lstat', side_effect=OSError('observation unavailable')):
                with self.assertRaises(OSError):
                    store.observe_generation()
            self.assertTrue(store._connection.in_transaction)
            store._connection.execute('ROLLBACK')
            self.assertIsNone(store.read('absent'))
            store.close()


if __name__ == '__main__':
    unittest.main()
