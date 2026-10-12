"""Independent actual POSIX descriptor cases; no accepted Run/Store claim."""
import copy
import errno
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import (
    LocalFileAcquisitionError, LocalFileError, LocalFileRoot, PhysicalFileIdentity,
)


class LocalFileDescriptorTests(unittest.TestCase):
    def root(self, path):
        return LocalFileRoot(path, max_files=2, max_chunk_bytes=16)

    def test_exclusive_exact_bytes_and_identity_survive_descriptor_close(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('stage-original', 32)
            body = b'NULL/e\xcc\x81\r\n\x00'
            observed = root.observe(value)
            actual = (path / value.name).stat()
            self.assertEqual(observed.identity, PhysicalFileIdentity(actual.st_dev, actual.st_ino))
            self.assertEqual(root.append(value, 0, body), len(body))
            self.assertEqual(root.sync(value).size, len(body))
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertTrue(root.close())
            self.assertEqual((path / 'stage-original').read_bytes(), body)
            reopened = self.root(path)
            with self.assertRaises(FileExistsError):
                reopened.create_writer('stage-original', 32)
            self.assertTrue(reopened.close())
            self.assertEqual((path / 'stage-original').read_bytes(), body)

    def test_root_lock_close_and_descriptor_capacity_do_not_replace_originals(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            with self.assertRaises(BlockingIOError):
                self.root(path)
            first = root.create_writer('first', 4)
            second = root.create_writer('second', 4)
            with self.assertRaisesRegex(LocalFileError, 'capacity'):
                root.create_writer('third', 4)
            self.assertFalse((path / 'third').exists())
            self.assertFalse(root.close())
            with self.assertRaises(LocalFileError):
                root.create_writer('fourth', 4)
            self.assertTrue(root.close_writer(first))
            self.assertFalse(root.close())
            self.assertTrue(root.close_writer(second))
            self.assertTrue(root.close())

    def test_invalid_names_limits_and_copied_handles_refuse_before_io(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('original', 4)
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('invalid reached open')):
                for name in ('', '.', '..', '../outside', 'a/b', 'a\x00b', 'é', 'x' * 129):
                    with self.assertRaises(ValueError):
                        root.create_writer(name, 4)
                for limit in (True, -1, 2**63):
                    with self.assertRaises(ValueError):
                        root.create_writer('another', limit)
            with patch('actql_sdk._local_files.os.fstat', side_effect=AssertionError('copy reached observation')):
                with self.assertRaises(ValueError):
                    root.observe(copy.copy(value))
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            with self.assertRaises(ValueError):
                root.close_writer(value)

    def test_foreign_symlink_and_existing_file_are_never_truncated_or_removed(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            target = path / 'foreign'
            target.write_bytes(b'foreign\r\n\x00')
            os.chmod(target, 0o600)
            (path / 'alias').symlink_to(target)
            root = self.root(path)
            for name in ('foreign', 'alias'):
                with self.assertRaises(FileExistsError):
                    root.create_writer(name, 10)
            self.assertEqual(target.read_bytes(), b'foreign\r\n\x00')
            self.assertTrue((path / 'alias').is_symlink())
            self.assertTrue(root.close())
            with self.assertRaises(LocalFileError):
                self.root(path / 'alias')

    def test_failed_original_fstat_keeps_same_acquisition_until_observation(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            with patch('actql_sdk._local_files.os.fstat', side_effect=OSError('original observation failed')):
                with self.assertRaises(LocalFileAcquisitionError) as failure:
                    root.create_writer('original', 4)
            value = failure.exception.original_file
            self.assertIs(root._files[id(value)], value)
            self.assertTrue((path / 'original').exists())
            self.assertFalse(root.close())
            self.assertEqual(root.observe(value).size, 0)
            root.sync_creation(value)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertTrue((path / 'original').exists())

    def test_creation_sync_failure_retries_same_descriptor_without_second_create(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('directory sync failed')):
                with self.assertRaises(LocalFileAcquisitionError) as failure:
                    root.create_writer('original', 4)
            value = failure.exception.original_file
            identity = root.observe(value).identity
            self.assertFalse(value.creation_synced)
            with self.assertRaises(LocalFileError):
                root.append(value, 0, b'NULL')
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('retry recreated file')):
                root.sync_creation(value)
            self.assertEqual(root.observe(value).identity, identity)
            self.assertEqual(root.append(value, 0, b'NULL'), 4)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_foreign_name_after_acquisition_never_becomes_original_descriptor(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('directory sync failed')):
                with self.assertRaises(LocalFileAcquisitionError) as failure:
                    root.create_writer('original', 4)
            value = failure.exception.original_file
            identity = root.observe(value).identity
            (path / 'original').rename(path / 'moved-original')
            (path / 'original').write_bytes(b'foreign')
            with self.assertRaisesRegex(LocalFileError, 'name changed'):
                root.sync_creation(value)
            self.assertEqual(root.observe(value).identity, identity)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertEqual((path / 'original').read_bytes(), b'foreign')
            self.assertTrue((path / 'moved-original').exists())

    def test_bounded_short_write_returns_actual_count_without_retry(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('original', 4)
            physical_write = os.write
            with patch('actql_sdk._local_files.os.write',
                       side_effect=lambda fd, data: physical_write(fd, data[:2])) as writes:
                self.assertEqual(root.append(value, 0, b'NULL'), 2)
                self.assertEqual(writes.call_count, 1)
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('invalid reached write')):
                for offset, body in ((0, b'LL'), (2, b'LLL'), (2, b'x' * 17)):
                    with self.assertRaises((ValueError, LocalFileError)):
                        root.append(value, offset, body)
            self.assertEqual(root.append(value, 2, b'LL'), 2)
            self.assertEqual(root.sync(value).size, 4)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertEqual((path / 'original').read_bytes(), b'NULL')

    def test_write_ack_loss_keeps_original_unknown_without_repeat_or_seal(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('original', 8)
            physical_write = os.write

            def write_then_fail(fd, data):
                physical_write(fd, data)
                raise OSError('original write acknowledgement loss')

            with patch('actql_sdk._local_files.os.write', side_effect=write_then_fail) as writes:
                with self.assertRaises(OSError):
                    root.append(value, 0, b'NULL')
                with self.assertRaises(LocalFileError):
                    root.append(value, 4, b'NULL')
                self.assertEqual(writes.call_count, 1)
            self.assertEqual(root.observe(value).size, 4)
            with self.assertRaises(LocalFileError):
                root.sync(value)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertEqual((path / 'original').read_bytes(), b'NULL')

    def test_failed_close_retries_same_descriptor_and_never_unlinks_file(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('original', 4)
            original = value.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('descriptor stop failed')):
                self.assertFalse(root.close_writer(value))
                self.assertFalse(root.close())
            self.assertEqual(value.descriptor, original)
            # A live equal-inode descriptor cannot prove which acquisition now
            # owns its number. Retry observation, not an unsafe second close.
            self.assertFalse(root.close_writer(value))
            os.close(original)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertTrue((path / 'original').exists())

    def test_lost_close_reply_never_closes_a_recycled_foreign_descriptor(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('original', 4)
            foreign_path = path / 'foreign'
            foreign_path.write_bytes(b'foreign')
            close = os.close
            foreign = []

            def close_and_recycle(fd):
                close(fd)
                foreign.append(os.open(foreign_path, os.O_RDONLY))
                self.assertEqual(foreign[0], fd)
                raise OSError('original close reply lost after fd recycling')

            with patch('actql_sdk._local_files.os.close', side_effect=close_and_recycle):
                self.assertFalse(root.close_writer(value))
            self.assertTrue(root.close_writer(value))
            self.assertEqual(os.read(foreign[0], 7), b'foreign')
            close(foreign[0])
            self.assertTrue(root.close())
            self.assertTrue((path / 'original').exists())

    def test_unobserved_acquisition_after_close_failure_keeps_unknown_handle(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            with patch('actql_sdk._local_files.os.fstat', side_effect=OSError('identity observation failed')):
                with self.assertRaises(LocalFileAcquisitionError) as failure:
                    root.create_writer('original', 4)
            value = failure.exception.original_file
            descriptor = value.descriptor
            self.assertIsNone(value.identity)
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('unobserved stop failed')):
                self.assertFalse(root.close_writer(value))
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('unknown descriptor closed again')):
                self.assertFalse(root.close_writer(value))
            self.assertIs(root._files[id(value)], value)
            self.assertFalse(root.close())
            # Explicit test-resource stop; its EBADF observation proves only this
            # descriptor retired. It supplies no file ownership or Run outcome.
            os.close(descriptor)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertTrue((path / 'original').exists())

    def test_root_initialization_cleanup_failure_keeps_same_root_handle(self):
        from actql_sdk._local_files import LocalFileInitializationError
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            with patch('actql_sdk._local_files.fcntl.flock', side_effect=OSError('root lock unavailable')):
                with patch('actql_sdk._local_files.os.close', side_effect=OSError('root descriptor close failed')):
                    with self.assertRaises(LocalFileInitializationError) as failure:
                        self.root(path)
            root = failure.exception.original_root
            self.assertIsNotNone(root._descriptor)
            self.assertFalse(root.close())
            os.close(root._descriptor)
            self.assertTrue(root.close())
            self.assertTrue(root.close())

    def test_recycled_same_inode_stays_unknown_without_closing_foreign_handle(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('original', 4)
            close = os.close
            foreign = []

            def close_and_reopen(fd):
                close(fd)
                foreign.append(os.open(path / 'original', os.O_RDONLY))
                self.assertEqual(foreign[0], fd)
                raise OSError('original close reply lost; same inode reopened')

            with patch('actql_sdk._local_files.os.close', side_effect=close_and_reopen):
                self.assertFalse(root.close_writer(value))
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('foreign equal-inode descriptor closed')):
                self.assertFalse(root.close_writer(value))
                self.assertFalse(root.close())
            self.assertEqual(os.fstat(foreign[0]).st_ino, value.identity.inode)
            close(foreign[0])
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_recycled_root_descriptor_stays_unknown_until_actual_retirement(self):
        with TemporaryDirectory(prefix='actql-local-files-') as directory:
            path = Path(directory)
            root = self.root(path)
            close = os.close
            foreign = []

            def close_and_reopen(fd):
                close(fd)
                foreign.append(os.open(path, os.O_RDONLY | os.O_DIRECTORY))
                self.assertEqual(foreign[0], fd)
                raise OSError('root close reply lost; same directory reopened')

            with patch('actql_sdk._local_files.os.close', side_effect=close_and_reopen):
                self.assertFalse(root.close())
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('foreign root descriptor closed')):
                self.assertFalse(root.close())
            self.assertEqual(os.fstat(foreign[0]).st_ino, root._identity.inode)
            close(foreign[0])
            self.assertTrue(root.close())
