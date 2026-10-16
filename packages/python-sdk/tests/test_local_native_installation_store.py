"""Installed Store routing with scalar Core/FFI; not Wasm or public acceptance."""
import copy
import pickle
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import unittest
from unittest.mock import patch

import test_local_installation as installation_fixture
from test_local_native_sqlite_database_custody import DatabaseFixture
from actql_sdk._local_core import LocalCore
from actql_sdk._local_files import LocalFileRoot
from actql_sdk._local_installation import OriginalLocalInstallation, LocalInstallationCleanupPending
from actql_sdk._local_native_store import _OriginalNativeStoreSelection
from actql_sdk._local_native_sqlite_database import _OriginalDatabaseError
from actql_sdk._local_storage import LocalStorageInitializationError


class NativeInstallationStoreTests(unittest.TestCase):
    def core(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object(); core._lock = RLock()
        core._closing = core._closed = core._retired = False
        return core

    def selection(self, core, fixture, library=None):
        return _OriginalNativeStoreSelection(core, library or fixture.sqlite(),
            fixture.database_functions, fixture.read_functions)

    def test_copied_or_foreign_core_is_rejected_before_file_or_native_calls(self):
        core = self.core(); other = self.core(); other._identity = core._identity
        f = DatabaseFixture(); selection = self.selection(core, f)
        with self.assertRaises(ValueError):
            selection.open(other, Path('/does-not-exist/store'), None,
                max_records=4, max_record_bytes=1024, max_payload_bytes=2048)
        for clone in (lambda: copy.copy(selection), lambda: copy.deepcopy(selection),
                      lambda: pickle.dumps(selection)):
            with self.assertRaises(TypeError): clone()
        forged = _OriginalNativeStoreSelection.__new__(_OriginalNativeStoreSelection)
        for name in _OriginalNativeStoreSelection.__slots__:
            setattr(forged, name, getattr(selection, name))
        with self.assertRaises(ValueError): forged.require_core(core)
        self.assertEqual(f.database_events, [])

    def test_core_lifecycle_and_identity_changes_are_not_repaired(self):
        for field, value in [('_closing', True), ('_closed', True),
                             ('_retired', True), ('_identity', object())]:
            with self.subTest(field=field):
                core = self.core(); f = DatabaseFixture(); selection = self.selection(core, f)
                setattr(core, field, value)
                with self.assertRaises(ValueError): selection.require_core(core)
                self.assertEqual(f.database_events, [])

    def test_foreign_provider_functions_are_rejected_without_acquisition(self):
        core = self.core(); f = DatabaseFixture(); g = DatabaseFixture(); library = f.sqlite()
        with self.assertRaises(ValueError):
            _OriginalNativeStoreSelection(core, library, g.database_functions, f.read_functions)
        self.assertEqual(f.database_events, []); self.assertEqual(g.database_events, [])

    def test_successful_selection_keeps_same_original_database_and_one_shot_library(self):
        with TemporaryDirectory() as directory:
            core = self.core(); f = DatabaseFixture(); selection = self.selection(core, f)
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            path = Path(directory)/'store'; file = root.create_writer('store', 0)
            store = selection.open(core, path, root, new_file=file,
                max_records=4, max_record_bytes=1024, max_payload_bytes=2048)
            self.assertIs(store._physical._original, selection._library._database_original)
            store.close(); before = list(f.database_events)
            with self.assertRaises(LocalStorageInitializationError) as error:
                selection.open(core, path, root, max_records=4,
                    max_record_bytes=1024, max_payload_bytes=2048)
            self.assertIsInstance(error.exception.__cause__, ValueError)
            self.assertEqual(f.database_events, before)
            error.exception.cleanup_store.close(); selection._library.close()
            root.close_writer(file); self.assertTrue(root.close())

    def test_core_postcheck_refusal_retains_open_database_for_same_cleanup(self):
        with TemporaryDirectory() as directory:
            core = self.core(); f = DatabaseFixture(); selection = self.selection(core, f)
            root = LocalFileRoot(Path(directory), max_files=1, max_chunk_bytes=64)
            file = root.create_writer('store', 0); actual = f.open
            def close_core(*args):
                code = actual(*args); core._closing = True; return code
            with patch.object(f, 'open', side_effect=close_core):
                with self.assertRaises(LocalStorageInitializationError) as error:
                    selection.open(core, Path(directory)/'store', root, new_file=file,
                        max_records=4, max_record_bytes=1024, max_payload_bytes=2048)
            store = error.exception.cleanup_store
            self.assertIs(store._physical._original, selection._library._database_original)
            self.assertFalse(store._closed)
            store.close(); selection._library.close(); root.close_writer(file)
            self.assertTrue(root.close())

    def test_installation_persists_original_markers_before_native_open_and_keeps_partial_store(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)
            core, calls = installation_fixture.OriginalLocalInstallationTests().core()
            core._retired = False
            f = DatabaseFixture(); library = f.sqlite(); selection = self.selection(core, f, library)
            f.open_issue = 13; f.database_close_issue = 5; actual = f.open
            def observed(*args):
                self.assertTrue((path/'state/journal-custody.json').is_file())
                self.assertEqual((path/'state/journal-initializing.json').read_bytes(),
                                 (path/'state/journal-custody.json').read_bytes())
                return actual(*args)
            with patch.object(f, 'open', side_effect=observed), patch(
                    'sqlite3.connect', side_effect=AssertionError('Native selection must not fall back')):
                with self.assertRaises(LocalInstallationCleanupPending) as error:
                    OriginalLocalInstallation(core, path,
                        observed_at='2026-10-12T00:00:00.000Z', now=lambda: 0,
                        project_epoch=lambda *_: self.fail('No epoch after failed open'),
                        native_store=selection)
            installation = error.exception.cleanup_installation
            store = installation._store
            self.assertIsNotNone(store)
            self.assertIs(store._physical._original, library._database_original)
            with self.assertRaises(_OriginalDatabaseError) as refused:
                installation.close()
            self.assertFalse(refused.exception.unknown)
            self.assertFalse(store._closed)
            self.assertTrue(any(root._descriptor is not None for root in installation._roots))
            f.database_close_issue = 0
            self.assertTrue(installation.close())
            library.close()
            self.assertTrue((path/'state/journal-custody.json').is_file())
            self.assertFalse(any(family in ('run','task','effect','model')
                                 for family, _, _ in calls))

    def test_foreign_selection_does_not_create_any_installation_material(self):
        with TemporaryDirectory() as directory:
            core = self.core(); f = DatabaseFixture(); selection = self.selection(core, f)
            with self.assertRaises(ValueError):
                OriginalLocalInstallation(self.core(), Path(directory),
                    observed_at='2026-10-12T00:00:00.000Z', now=lambda: 0,
                    project_epoch=lambda *_: b'', native_store=selection)
            self.assertEqual(list(Path(directory).iterdir()), [])
            self.assertEqual(f.database_events, [])
