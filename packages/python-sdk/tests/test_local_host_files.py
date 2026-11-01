"""Actual POSIX/SQLite pins; no Host/Run/adoption/scope permission claim."""
import copy
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_host_files import LocalHostFiles, LocalHostFilesCleanupPending
from actql_sdk._local_files import LocalFileRoot, LocalFileError
from actql_sdk._local_storage import LocalByteStore, LocalStorageError


class LocalHostFilePinsTests(unittest.TestCase):
    def fixture(self):
        directory = TemporaryDirectory(prefix='actql-host-pins-')
        self.addCleanup(directory.cleanup)
        path = Path(directory.name)
        for name, body in [('account.json', b'null/e\xcc\x81\r\n'), ('policy.json', b'{"unknown":null}')]:
            (path / name).write_bytes(body)
            (path / name).chmod(0o600)
        root = LocalFileRoot(path, max_files=8, max_chunk_bytes=4)
        store = LocalByteStore(path / 'client.sqlite3', max_records=8,
                              max_record_bytes=256, max_payload_bytes=1024)
        self.addCleanup(store.close)
        pins = LocalHostFiles(root, store, max_files=2, max_bytes=32)
        self.addCleanup(lambda: root.close())
        self.addCleanup(lambda: pins.close())
        return path, root, store, pins

    def test_complete_file_group_checks_directory_twice_and_every_original_fd_and_name(self):
        with TemporaryDirectory(prefix='actql-group-directory-') as directory:
            path = Path(directory)
            for i in range(5):
                name = path / ('original-' + str(i))
                name.write_bytes(b'original'); name.chmod(0o600)
            root = LocalFileRoot(path, max_files=8, max_chunk_bytes=8)
            self.addCleanup(root.close)
            store = LocalByteStore(path / 'client.sqlite3', max_records=8,
                                  max_record_bytes=256, max_payload_bytes=1024)
            self.addCleanup(store.close)
            pins = LocalHostFiles(root, store, max_files=5, max_bytes=64)
            self.addCleanup(pins.close)
            originals = tuple(pins.read_original('original-' + str(i), max_bytes=8) for i in range(5))
            root_fd = root._open()
            real_fstat, real_stat = os.fstat, os.stat
            observed, named = [], []
            def fstat(fd):
                observed.append(fd)
                return real_fstat(fd)
            def stat(*args, **kwargs):
                if kwargs.get('dir_fd') == root_fd: named.append(args[0])
                return real_stat(*args, **kwargs)
            with patch('actql_sdk._local_files.os.fstat', side_effect=fstat), \
                    patch('actql_sdk._local_files.os.stat', side_effect=stat):
                pins.require_current_originals(originals)
            self.assertEqual(observed.count(root_fd), 2)
            self.assertEqual([observed.count(value.reader.descriptor) for value in originals], [1] * 5)
            self.assertEqual(named, ['original-' + str(i) for i in range(5)])

    def test_exact_original_bytes_and_current_preserve_files_store_and_no_scope(self):
        path, root, store, pins = self.fixture()
        changes = store._connection.total_changes
        account = pins.read_original('account.json', max_bytes=11)
        policy = pins.read_original('policy.json', max_bytes=16)
        self.assertEqual(pins.original_bytes(account), b'null/e\xcc\x81\r\n')
        self.assertEqual(pins.original_bytes(policy), b'{"unknown":null}')
        self.assertIsNone(pins.current())
        self.assertEqual(store._connection.total_changes, changes)
        self.assertFalse(root.close())
        self.assertTrue(pins.close())
        self.assertTrue(root.close())
        self.assertEqual((path / 'account.json').read_bytes(), b'null/e\xcc\x81\r\n')
        self.assertIsNone(store.read('absent'))

    def test_changed_or_replaced_saved_file_refuses_without_default_repair(self):
        path, _, _, pins = self.fixture()
        value = pins.read_original('account.json', max_bytes=11)
        (path / 'account.json').write_bytes(b'null/e\xcc\x81\n\r')
        with self.assertRaises(LocalFileError):
            pins.current()
        with self.assertRaises(LocalFileError):
            pins.original_bytes(value)
        self.assertTrue(pins.close())
        self.assertEqual((path / 'account.json').read_bytes(), b'null/e\xcc\x81\n\r')

    def test_replaced_store_or_closed_root_does_not_return_cached_originals(self):
        path, root, store, pins = self.fixture()
        value = pins.read_original('account.json', max_bytes=11)
        (path / 'client.sqlite3').rename(path / 'original.sqlite3')
        replacement = LocalByteStore(path / 'client.sqlite3', max_records=8,
                                    max_record_bytes=256, max_payload_bytes=1024)
        self.addCleanup(replacement.close)
        with self.assertRaises(LocalStorageError):
            pins.original_bytes(value)
        self.assertTrue(pins.close())
        self.assertTrue(root.close())
        with self.assertRaises(ValueError):
            pins.current()
        self.assertIsNone(store.read('absent'))

    def test_copied_pins_and_file_cannot_observe_original_custody(self):
        _, _, _, pins = self.fixture()
        value = pins.read_original('account.json', max_bytes=11)
        with patch('actql_sdk._local_host_files.LocalByteStore.observe_generation', side_effect=AssertionError('copy I/O')):
            with self.assertRaises(ValueError):
                copy.copy(pins).current()
            with self.assertRaises(ValueError):
                pins.original_bytes(copy.copy(value))

    def test_group_current_requires_exact_members_before_physical_observation(self):
        _, _, _, pins = self.fixture()
        original = pins.read_original('account.json', max_bytes=11)
        _, _, _, foreign = self.fixture()
        other = foreign.read_original('account.json', max_bytes=11)
        self.assertIsNone(pins.require_current_originals((original,)))
        with patch.object(pins._root, 'observe_original',
                          side_effect=AssertionError('Invalid member reached observation')):
            for candidate in (copy.copy(original), other):
                with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                    pins.require_current_originals((candidate,))
            with self.assertRaises(ValueError):
                copy.copy(pins).require_current_originals((original,))
            with self.assertRaises(ValueError):
                pins.require_current_originals((original,) * 3)
        self.assertTrue(pins.close())
        with self.assertRaises(ValueError):
            pins.require_current_originals((original,))

    def test_failed_acquisition_preserves_same_reader_for_explicit_cleanup(self):
        path, root, _, pins = self.fixture()
        with patch('actql_sdk._local_files.os.fstat', side_effect=OSError('original observation unknown')):
            with self.assertRaises(LocalHostFilesCleanupPending) as raised:
                pins.read_original('account.json', max_bytes=11)
        self.assertIs(raised.exception.cleanup_files, pins)
        self.assertEqual(len(pins._pending), 1)
        self.assertFalse(root.close())
        with self.assertRaises(ValueError):
            pins.current()
        with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('reopen/repair')):
            self.assertTrue(pins.close())
        self.assertTrue(root.close())
        self.assertEqual((path / 'account.json').read_bytes(), b'null/e\xcc\x81\r\n')

    def test_failed_close_keeps_exact_pin_and_reservation_until_observed_stop(self):
        _, root, _, pins = self.fixture()
        value = pins.read_original('account.json', max_bytes=11)
        descriptor = value.reader.descriptor
        with patch('actql_sdk._local_files.os.close', side_effect=OSError('stop unknown')) as closed:
            self.assertFalse(pins.close())
            self.assertFalse(pins.close())
            self.assertEqual(closed.call_count, 1)
        self.assertIs(pins._files[value.name], value)
        self.assertEqual(pins._bytes, len(value.body))
        self.assertFalse(root.close())
        os.close(descriptor)
        with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('double stop')):
            self.assertTrue(pins.close())
        self.assertEqual(pins._bytes, 0)
        self.assertTrue(root.close())

    def test_raw_holding_limits_reject_before_open_without_truncating(self):
        _, _, _, pins = self.fixture()
        pins.read_original('account.json', max_bytes=11)
        pins.read_original('policy.json', max_bytes=16)
        with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('limit reached I/O')):
            with self.assertRaises(ValueError):
                pins.read_original('another', max_bytes=1)
            with self.assertRaises(ValueError):
                pins.read_original('account.json', max_bytes=1048577)


if __name__ == '__main__':
    unittest.main()
