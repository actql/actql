"""Real file claims with independent Native slot faults; no selected DLL."""
from pathlib import Path
from tempfile import TemporaryDirectory
import os
import unittest
from unittest.mock import patch

from test_local_native_sqlite_database_custody import DatabaseFixture
from actql_sdk._local_files import LocalFileRoot, LocalFileError
from actql_sdk._local_native_store import _open_original_native_store
from actql_sdk._local_storage import (
    LocalByteStore, LocalStorageError, LocalStorageInitializationError, StoredBytes)
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseError


class OriginalNativeStoreTests(unittest.TestCase):
    def open_store(self, path, root, fixture, library, **options):
        return _open_original_native_store(path, root, library=library,
            functions=fixture.database_functions, read=fixture.read_functions,
            max_records=4, max_record_bytes=1024, max_payload_bytes=2048, **options)

    def test_fresh_claim_precedes_native_open_and_keeps_existing_store_type(self):
        with TemporaryDirectory() as directory:
            root = LocalFileRoot(Path(directory), max_files=2, max_chunk_bytes=64)
            file = root.create_writer('store.sqlite3', 0)
            f = DatabaseFixture(); library = f.sqlite()
            real_open = f.open
            def observed_open(*args):
                self.assertTrue(file.store_claimed)
                return real_open(*args)
            with patch.object(f, 'open', side_effect=observed_open), patch(
                    'sqlite3.connect', side_effect=AssertionError('No system fallback')):
                store = self.open_store(Path(directory)/'store.sqlite3', root, f, library, new_file=file)
            self.assertIs(type(store), LocalByteStore)
            self.assertIs(store._physical._original, library._database_original)
            self.assertEqual(store.read('key'), StoredBytes(3, b'\0\xff\r\n'))
            opened = next(e for e in f.database_events if e[0] == 'open')
            self.assertEqual(opened[1], 2)
            metadata = os.stat(Path(directory)/'store.sqlite3')
            self.assertEqual(opened[-1], (metadata.st_dev, metadata.st_ino))
            store.close(); store.close(); library.close()
            self.assertTrue(root.close_writer(file)); self.assertTrue(root.close())

    def test_restore_uses_existing_only_without_new_creation_claim(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)/'store.sqlite3'; path.write_bytes(b'original schema bytes'); path.chmod(0o600)
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            f = DatabaseFixture(); library = f.sqlite()
            store = self.open_store(path, root, f, library)
            self.assertFalse(store.claim_creation())
            self.assertEqual(next(e for e in f.database_events if e[0] == 'open')[1], 1)
            self.assertEqual(path.read_bytes(), b'original schema bytes')
            store.close(); library.close(); self.assertTrue(root.close())

    def test_missing_restore_and_foreign_root_refuse_before_native(self):
        with TemporaryDirectory() as directory, TemporaryDirectory() as foreign:
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            f = DatabaseFixture(); library = f.sqlite()
            with self.assertRaises(FileNotFoundError):
                self.open_store(Path(directory)/'missing', root, f, library)
            with self.assertRaises(LocalStorageError):
                self.open_store(Path(foreign)/'missing', root, f, library)
            self.assertEqual(f.database_events, [])
            library.close(); self.assertTrue(root.close())

    def test_consumed_fresh_claim_is_not_issued_again_after_local_refusal(self):
        with TemporaryDirectory() as directory:
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            file = root.create_writer('store.sqlite3', 0)
            f = DatabaseFixture(); library = f.sqlite(); f.host._busy = True
            with self.assertRaises(LocalStorageInitializationError) as error:
                self.open_store(Path(directory)/'store.sqlite3', root, f, library, new_file=file)
            self.assertIsInstance(error.exception.__cause__, ValueError)
            self.assertTrue(file.store_claimed); self.assertEqual(f.database_events, [])
            f.host._busy = False
            error.exception.cleanup_store.close()
            with self.assertRaises(LocalFileError):
                self.open_store(Path(directory)/'store.sqlite3', root, f, library, new_file=file)
            self.assertEqual(f.database_events, [])
            library.close(); root.close_writer(file); self.assertTrue(root.close())

    def test_unknown_open_retains_exact_pending_database_without_reopen(self):
        with TemporaryDirectory() as directory:
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            file = root.create_writer('store.sqlite3', 0)
            f = DatabaseFixture(); library = f.sqlite(); f.open_fault = OSError('lost original open')
            with self.assertRaises(LocalStorageInitializationError) as error:
                self.open_store(Path(directory)/'store.sqlite3', root, f, library, new_file=file)
            store = error.exception.cleanup_store
            original = error.exception.__cause__
            self.assertIsInstance(original, _OriginalDatabaseError)
            self.assertTrue(original.unknown)
            self.assertIs(store._physical._original, original.cleanup_database)
            self.assertIs(library._database_original, original.cleanup_database)
            before = list(f.database_events)
            with self.assertRaises(_OriginalDatabaseError): store.close()
            self.assertFalse(store._closed); self.assertEqual(f.database_events, before)
            # Unknown custody remains live in the fixture, not a cleanup PASS.
            root.close_writer(file); self.assertTrue(root.close())

    def test_generation_swap_after_open_returns_same_cleanup_database(self):
        with TemporaryDirectory() as directory:
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            file = root.create_writer('store.sqlite3', 0)
            f = DatabaseFixture(); library = f.sqlite(); actual = f.open
            def swapped(*args):
                status = actual(*args)
                path = Path(directory)/'store.sqlite3'
                path.rename(Path(directory)/'original.sqlite3')
                path.touch(mode=0o600)
                return status
            with patch.object(f, 'open', side_effect=swapped):
                with self.assertRaises(LocalStorageInitializationError) as error:
                    self.open_store(Path(directory)/'store.sqlite3', root, f, library, new_file=file)
            store = error.exception.cleanup_store
            self.assertIs(store._physical._original, library._database_original)
            self.assertFalse(store._ready)
            store.close(); library.close(); root.close_writer(file); self.assertTrue(root.close())

    def test_root_closing_rejects_use_without_closing_native_database(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)/'store.sqlite3'; path.touch(mode=0o600)
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            f = DatabaseFixture(); library = f.sqlite(); store = self.open_store(path, root, f, library)
            root._closing = True; before = list(f.database_events)
            with self.assertRaises(LocalFileError): store.read('key')
            self.assertEqual(f.database_events, before)
            self.assertFalse(store._physical._original._closed)
            store.close(); library.close(); self.assertTrue(root.close())
