"""Actual bounded saved-file I/O; no adopted Host or public Local claim."""
import copy
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import (
    LocalFileError, LocalFileRoot, LocalOriginalAcquisitionError, PhysicalFileIdentity,
)


class LocalOriginalFileTests(unittest.TestCase):
    def root(self, path):
        return LocalFileRoot(path, max_files=2, max_chunk_bytes=4)

    def saved(self, path, name='account', body=b'NULL/e\xcc\x81\r\n\x00'):
        file = path / name
        file.write_bytes(body)
        file.chmod(0o600)
        return file

    def test_repeated_eof_observation_reuses_only_immutable_snapshot_after_each_physical_check(self):
        with TemporaryDirectory(prefix='actql-eof-observation-') as directory:
            path = Path(directory)
            self.saved(path, body=b'one')
            root = self.root(path)
            self.addCleanup(root.close)
            reader = root.open_original('account', max_bytes=3)
            self.addCleanup(lambda: root.close_original(reader))
            chunk = root.read_original(reader); root.release_original_chunk(reader, chunk)
            original = root.observe_original(reader)
            with patch.object(root, '_validate_original', wraps=root._validate_original) as current:
                for _ in range(5): self.assertIs(root.observe_original(reader), original)
                self.assertEqual(current.call_count, 5)
            (path / 'account').write_bytes(b'two')
            with self.assertRaises(LocalFileError): root.observe_original(reader)
            self.assertTrue(reader.invalid)

    def test_group_directory_change_after_last_member_refuses_and_keeps_original_fds(self):
        with TemporaryDirectory(prefix='actql-original-group-directory-') as directory:
            path = Path(directory)
            root = LocalFileRoot(path, max_files=4, max_chunk_bytes=4)
            self.addCleanup(root.close)
            readers = []
            for i in range(3):
                self.saved(path, 'original-' + str(i), b'one')
                reader = root.open_original('original-' + str(i), max_bytes=3)
                self.addCleanup(lambda value=reader: root.close_original(value))
                chunk = root.read_original(reader); root.release_original_chunk(reader, chunk)
                readers.append(reader)
            real_stat = os.stat
            def change_after_last(name, *args, **kwargs):
                result = real_stat(name, *args, **kwargs)
                if name == 'original-2' and kwargs.get('dir_fd') == root._open():
                    path.chmod(0o755)
                return result
            try:
                with patch('actql_sdk._local_files.os.stat', side_effect=change_after_last):
                    with self.assertRaises(LocalFileError): root._observe_originals(tuple(readers))
                self.assertTrue(all(reader.invalid for reader in readers))
                self.assertTrue(all(os.fstat(reader.descriptor).st_size == 3 for reader in readers))
            finally:
                path.chmod(0o700)

    def test_group_member_mutation_refuses_before_any_success_is_exposed(self):
        with TemporaryDirectory(prefix='actql-original-group-change-') as directory:
            path = Path(directory)
            root = self.root(path); self.addCleanup(root.close)
            readers = []
            for i in range(2):
                self.saved(path, 'original-' + str(i), b'one')
                reader = root.open_original('original-' + str(i), max_bytes=3)
                self.addCleanup(lambda value=reader: root.close_original(value))
                chunk = root.read_original(reader); root.release_original_chunk(reader, chunk)
                readers.append(reader)
            real_stat = os.stat
            def change_next(name, *args, **kwargs):
                result = real_stat(name, *args, **kwargs)
                if name == 'original-0' and kwargs.get('dir_fd') == root._open():
                    (path / 'original-1').write_bytes(b'two')
                return result
            with patch('actql_sdk._local_files.os.stat', side_effect=change_next):
                with self.assertRaises(LocalFileError): root._observe_originals(tuple(readers))
            self.assertTrue(all(reader.invalid for reader in readers))
            self.assertTrue(all(os.fstat(reader.descriptor).st_size == 3 for reader in readers))

    def test_group_foreign_copied_duplicate_and_closing_members_refuse_before_stat(self):
        with TemporaryDirectory(prefix='actql-original-group-ownership-') as directory:
            path = Path(directory); self.saved(path)
            root = self.root(path); self.addCleanup(root.close)
            reader = root.open_original('account', max_bytes=11)
            self.addCleanup(lambda: root.close_original(reader))
            for members in ([reader], (copy.copy(reader),), (reader, reader)):
                with self.subTest(members=type(members).__name__), \
                        patch('actql_sdk._local_files.os.fstat', side_effect=AssertionError('foreign I/O')):
                    with self.assertRaises(ValueError): root._observe_originals(members)
            reader.closing = True
            with patch('actql_sdk._local_files.os.fstat', side_effect=AssertionError('closing I/O')):
                with self.assertRaises(LocalFileError): root._observe_originals((reader,))

    def test_exact_raw_chunks_and_snapshot_preserve_unicode_crlf_and_null(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            file = self.saved(path)
            root = self.root(path)
            reader = root.open_original('account', max_bytes=11)
            chunks = []
            for offset, expected, eof in [(0, b'NULL', False), (4, b'/e\xcc\x81', False),
                                           (8, b'\r\n\x00', True)]:
                chunk = root.read_original(reader)
                self.assertEqual((chunk.offset, chunk.data, chunk.eof), (offset, expected, eof))
                with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('loan reread')):
                    self.assertIs(root.read_original(reader), chunk)
                chunks.append(chunk.data)
                root.release_original_chunk(reader, chunk)
            self.assertEqual(b''.join(chunks), b'NULL/e\xcc\x81\r\n\x00')
            snapshot = root.observe_original(reader)
            actual = file.stat()
            self.assertEqual(snapshot.observation.identity, PhysicalFileIdentity(actual.st_dev, actual.st_ino))
            self.assertEqual(snapshot.observation.size, 11)
            self.assertEqual(snapshot.physical_digest,
                             'sha256:513d3f191a4592178cdc0bd55912ecf1b334141d4daee1b18f0a113164d676e8')
            with self.assertRaisesRegex(LocalFileError, 'EOF'):
                root.read_original(reader)
            self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())
            self.assertEqual(file.read_bytes(), b'NULL/e\xcc\x81\r\n\x00')

    def test_empty_original_requires_explicit_eof_release(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            self.saved(path, body=b'')
            root = self.root(path)
            reader = root.open_original('account', max_bytes=0)
            with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                root.observe_original(reader)
            chunk = root.read_original(reader)
            self.assertEqual((chunk.offset, chunk.data, chunk.eof), (0, b'', True))
            root.release_original_chunk(reader, chunk)
            self.assertEqual(root.observe_original(reader).physical_digest,
                             'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
            self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())

    def test_mutation_after_io_latches_failure_and_retains_chunk_until_cleanup(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            file = self.saved(path, body=b'null')
            root = self.root(path)
            reader = root.open_original('account', max_bytes=4)
            chunk = root.read_original(reader)
            file.write_bytes(b'NULL')
            with self.assertRaisesRegex(LocalFileError, 'generation'):
                root.release_original_chunk(reader, chunk)
            self.assertIs(reader.chunk, chunk)
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('reread')):
                with self.assertRaisesRegex(LocalFileError, 'invalid'):
                    root.read_original(reader)
            self.assertFalse(root.close())
            self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())
            self.assertEqual(file.read_bytes(), b'NULL')

    def test_replaced_name_never_supplies_original_bytes_or_reopens_descriptor(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            file = self.saved(path, body=b'null')
            root = self.root(path)
            reader = root.open_original('account', max_bytes=4)
            file.rename(path / 'original')
            self.saved(path, body=b'NULL')
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('reopened')):
                with self.assertRaisesRegex(LocalFileError, 'generation'):
                    root.read_original(reader)
                self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())
            self.assertEqual((path / 'original').read_bytes(), b'null')
            self.assertEqual(file.read_bytes(), b'NULL')

    def test_mutation_during_pread_is_rejected_before_any_chunk_is_returned(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            file = self.saved(path, body=b'null')
            root = self.root(path)
            reader = root.open_original('account', max_bytes=4)
            physical_read = os.pread

            def changed(descriptor, count, offset):
                data = physical_read(descriptor, count, offset)
                file.write_bytes(b'NULL')
                return data

            with patch('actql_sdk._local_files.os.pread', side_effect=changed):
                with self.assertRaisesRegex(LocalFileError, 'generation'):
                    root.read_original(reader)
            self.assertIsNone(reader.chunk)
            self.assertEqual(reader.offset, 0)
            self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())

    def test_post_open_observation_failure_keeps_acquired_descriptor_for_cleanup(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            self.saved(path, body=b'null')
            root = self.root(path)
            with patch('actql_sdk._local_files.os.fstat', side_effect=OSError('generation unavailable')):
                with self.assertRaises(LocalOriginalAcquisitionError) as failure:
                    root.open_original('account', max_bytes=4)
            reader = failure.exception.original_reader
            self.assertIsNotNone(reader.descriptor)
            self.assertIsNone(reader.identity)
            self.assertFalse(root.close())
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('reacquired')):
                self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())

    def test_missing_symlink_public_special_and_oversize_fail_with_same_handle_cleanup(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            self.saved(path, body=b'null')
            self.saved(path, 'public', b'null').chmod(0o644)
            (path / 'alias').symlink_to(path / 'account')
            os.mkfifo(path / 'fifo', 0o600)
            root = self.root(path)
            for name, bound in [('missing', 4), ('alias', 4), ('public', 4),
                                ('fifo', 4), ('account', 3)]:
                with self.assertRaises(LocalOriginalAcquisitionError) as failure:
                    root.open_original(name, max_bytes=bound)
                reader = failure.exception.original_reader
                self.assertIs(root._original_readers[id(reader)], reader)
                self.assertEqual(root._used_slots(), 1)
                with self.assertRaises(LocalFileError):
                    root.read_original(reader)
                self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())
            self.assertFalse((path / 'missing').exists())
            self.assertTrue((path / 'alias').is_symlink())
            self.assertEqual((path / 'account').read_bytes(), b'null')

    def test_short_or_failed_read_cannot_retry_or_supply_completed_snapshot(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            self.saved(path, body=b'null')
            root = self.root(path)
            for result in (b'n', OSError('physical query failed')):
                reader = root.open_original('account', max_bytes=4)
                options = {'side_effect': result} if isinstance(result, OSError) else {'return_value': result}
                with patch('actql_sdk._local_files.os.pread', **options) as read:
                    with self.assertRaises((OSError, LocalFileError)):
                        root.read_original(reader)
                    with self.assertRaisesRegex(LocalFileError, 'invalid'):
                        root.read_original(reader)
                    self.assertEqual(read.call_count, 1)
                with self.assertRaises(LocalFileError):
                    root.observe_original(reader)
                self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())

    def test_copied_handles_chunks_and_invalid_arguments_refuse_before_io(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            self.saved(path, body=b'null')
            root = self.root(path)
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('invalid reached open')):
                for name in ('', '..', '../outside', 'é', 'a/b'):
                    with self.assertRaises(ValueError):
                        root.open_original(name, max_bytes=4)
                for bound in (True, -1, 1048577):
                    with self.assertRaises(ValueError):
                        root.open_original('account', max_bytes=bound)
            reader = root.open_original('account', max_bytes=4)
            with patch('actql_sdk._local_files.os.fstat', side_effect=AssertionError('copy reached I/O')):
                with self.assertRaises(ValueError):
                    root.read_original(copy.copy(reader))
            chunk = root.read_original(reader)
            with self.assertRaises(ValueError):
                root.release_original_chunk(reader, copy.copy(chunk))
            self.assertEqual(reader.offset, 0)
            root.release_original_chunk(reader, chunk)
            self.assertTrue(root.close_original(reader))
            with self.assertRaises(ValueError):
                root.close_original(reader)
            self.assertTrue(root.close())

    def test_area_reader_consumes_original_root_capacity_and_pins_parent_close(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('settings')
            child = root.open_area(area)
            self.saved(path / 'settings', body=b'null')
            reader = child.open_original('account', max_bytes=4)
            self.assertEqual(root._used_slots(), 2)
            with self.assertRaisesRegex(LocalFileError, 'capacity'):
                root.create_writer('extra', 0)
            self.assertFalse(root.close_area(area))
            self.assertFalse(root.close())
            with self.assertRaises(LocalFileError):
                child.read_original(reader)
            self.assertTrue(child.close_original(reader))
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())

    def test_uncertain_stop_retains_same_descriptor_slot_and_chunk_until_observed_closed(self):
        with TemporaryDirectory(prefix='actql-originals-') as directory:
            path = Path(directory)
            self.saved(path, body=b'null')
            root = self.root(path)
            reader = root.open_original('account', max_bytes=4)
            chunk = root.read_original(reader)
            descriptor = reader.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('stop unknown')) as stop:
                self.assertFalse(root.close_original(reader))
                self.assertFalse(root.close_original(reader))
                self.assertEqual(stop.call_count, 1)
            self.assertEqual(reader.descriptor, descriptor)
            self.assertIs(reader.chunk, chunk)
            self.assertEqual(root._used_slots(), 1)
            self.assertFalse(root.close())
            os.close(descriptor)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('second close')):
                self.assertTrue(root.close_original(reader))
            self.assertTrue(root.close())


if __name__ == '__main__':
    unittest.main()
