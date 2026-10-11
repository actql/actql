"""Actual bounded POSIX allocation areas; no durable Core/Store acceptance claim."""
import copy
import errno
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import (
    LocalAreaAcquisitionError, LocalFileError, LocalFileRoot, PhysicalFileIdentity,
)


class LocalAllocationAreaTests(unittest.TestCase):
    def root(self, path, slots=4):
        return LocalFileRoot(path, max_files=slots, max_chunk_bytes=16)

    def test_original_area_identity_and_exact_file_bytes_survive_formal_physical_close(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            actual = (path / area.name).stat()
            self.assertEqual(root.observe_area(area), PhysicalFileIdentity(actual.st_dev, actual.st_ino))
            child = root.open_area(area)
            self.assertIs(root.open_area(area), child)
            value = child.create_writer('payload', 16)
            data = b'NULL/e\xcc\x81\r\n\x00'
            self.assertEqual(child.append(value, 0, data), len(data))
            self.assertEqual(child.sync(value).size, len(data))
            self.assertFalse(root.close())
            self.assertFalse(root.close_area(area))
            self.assertTrue(child.close_writer(value))
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())
            self.assertEqual((path / area.name / 'payload').read_bytes(), data)
            reopened = self.root(path)
            with self.assertRaises(FileExistsError):
                reopened.create_area(area.name)
            self.assertTrue(reopened.close())

    def test_parent_files_areas_and_child_files_share_one_unchanged_capacity(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path, 3)
            value = root.create_writer('parent', 4)
            area = root.create_area('alloc-original-1')
            child = root.open_area(area)
            payload = child.create_writer('payload', 4)
            self.assertEqual(root._used_slots(), 3)
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('capacity reached open')):
                with self.assertRaisesRegex(LocalFileError, 'capacity'):
                    root.create_writer('overflow', 4)
                with self.assertRaisesRegex(LocalFileError, 'capacity'):
                    child.create_writer('overflow', 4)
            with patch('actql_sdk._local_files.os.mkdir', side_effect=AssertionError('capacity reached mkdir')):
                with self.assertRaisesRegex(LocalFileError, 'capacity'):
                    root.create_area('alloc-other-2')
            self.assertTrue(child.close_writer(payload))
            self.assertEqual(root._used_slots(), 2)
            self.assertTrue(root.close_area(area))
            self.assertEqual(root._used_slots(), 1)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertFalse((path / 'overflow').exists())
            self.assertFalse((path / 'alloc-other-2').exists())

    def test_copy_foreign_handles_invalid_names_and_nested_areas_fail_before_io(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            child = root.open_area(area)
            with patch('actql_sdk._local_files.os.mkdir', side_effect=AssertionError('invalid reached mkdir')):
                for name in ('', '.', '..', '../outside', 'a/b', 'a\x00b', 'é', 'x' * 129):
                    with self.assertRaises(ValueError):
                        root.create_area(name)
                with self.assertRaisesRegex(LocalFileError, 'Nested'):
                    child.create_area('nested')
            with patch('actql_sdk._local_files.os.stat', side_effect=AssertionError('copy reached stat')):
                for operation in (root.observe_area, root.open_area, root.sync_area_creation, root.close_area):
                    with self.assertRaises(ValueError):
                        operation(copy.copy(area))
                with self.assertRaises(ValueError):
                    child.observe_area(area)
            self.assertTrue(root.close_area(area))
            with self.assertRaises(ValueError):
                root.close_area(area)
            self.assertTrue(root.close())

    def test_foreign_directory_file_and_symlink_are_never_adopted_or_removed(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            (path / 'foreign').mkdir(mode=0o700)
            (path / 'foreign' / 'data').write_bytes(b'foreign')
            (path / 'file').write_bytes(b'file')
            (path / 'alias').symlink_to(path / 'foreign')
            root = self.root(path)
            for name in ('foreign', 'file', 'alias'):
                with self.assertRaises(FileExistsError):
                    root.create_area(name)
                self.assertEqual(root._used_slots(), 0)
            self.assertEqual((path / 'foreign' / 'data').read_bytes(), b'foreign')
            self.assertEqual((path / 'file').read_bytes(), b'file')
            self.assertTrue((path / 'alias').is_symlink())
            self.assertTrue(root.close())

    def test_sync_failure_retries_original_area_without_mkdir_or_new_identity(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('parent sync failed')):
                with self.assertRaises(LocalAreaAcquisitionError) as failure:
                    root.create_area('alloc-original-1')
            area = failure.exception.original_area
            identity = root.observe_area(area)
            self.assertFalse(area.creation_synced)
            with self.assertRaises(LocalFileError):
                root.open_area(area)
            with patch('actql_sdk._local_files.os.mkdir', side_effect=AssertionError('area recreated')):
                root.sync_area_creation(area)
            self.assertEqual(root.observe_area(area), identity)
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())
            self.assertTrue((path / area.name).exists())

    def test_unknown_creation_never_acquires_identity_from_a_later_pathname(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            with patch('actql_sdk._local_files.os.stat', side_effect=OSError('original area inspection failed')):
                with self.assertRaises(LocalAreaAcquisitionError) as failure:
                    root.create_area('alloc-original-1')
            area = failure.exception.original_area
            self.assertIsNone(area.identity)
            with patch('actql_sdk._local_files.os.stat', side_effect=AssertionError('unknown promoted from name')):
                with self.assertRaisesRegex(LocalFileError, 'unknown'):
                    root.observe_area(area)
            self.assertFalse(root.close_area(area))
            self.assertFalse(root.close())
            self.assertIs(root._areas[id(area)], area)
            self.assertTrue((path / area.name).exists())
            # Test-resource stop only: pending unknown custody is not reported
            # as product cleanup success or durable allocation ownership.
            os.close(root._descriptor)
            root._descriptor = None

    def test_lost_mkdir_acknowledgement_retains_original_unknown_without_a_retry(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            mkdir = os.mkdir
            def mkdir_then_fail(*args, **kwargs):
                mkdir(*args, **kwargs)
                raise OSError('original mkdir acknowledgement lost')
            with patch('actql_sdk._local_files.os.mkdir', side_effect=mkdir_then_fail) as calls:
                with self.assertRaises(LocalAreaAcquisitionError) as failure:
                    root.create_area('alloc-original-1')
                self.assertEqual(calls.call_count, 1)
            area = failure.exception.original_area
            self.assertIsNone(area.identity)
            self.assertFalse(root.close_area(area))
            self.assertFalse(root.close())
            self.assertTrue((path / area.name).exists())
            os.close(root._descriptor)
            root._descriptor = None

    def test_name_replacement_before_open_or_sync_never_becomes_original_custody(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            identity = area.identity
            (path / area.name).rename(path / 'moved-original')
            (path / area.name).mkdir(mode=0o700)
            (path / area.name / 'foreign').write_bytes(b'foreign')
            with self.assertRaisesRegex(LocalFileError, 'identity changed'):
                root.open_area(area)
            with self.assertRaisesRegex(LocalFileError, 'identity changed'):
                root.sync_area_creation(area)
            self.assertEqual(area.identity, identity)
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())
            self.assertEqual((path / area.name / 'foreign').read_bytes(), b'foreign')
            self.assertTrue((path / 'moved-original').exists())

    def test_failed_child_descriptor_observation_keeps_same_open_until_stop(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            with patch('actql_sdk._local_files.os.fstat', side_effect=OSError('opened area observation failed')):
                with self.assertRaises(LocalAreaAcquisitionError) as failure:
                    root.open_area(area)
            self.assertIs(failure.exception.original_area, area)
            child = area.directory
            self.assertIsNone(child._identity)
            descriptor = child._descriptor
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('failed area reopened')):
                with self.assertRaises(LocalFileError):
                    root.open_area(area)
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('child stop failed')):
                self.assertFalse(root.close_area(area))
            self.assertFalse(root.close_area(area))
            self.assertFalse(root.close())
            self.assertEqual(child._descriptor, descriptor)
            os.close(descriptor)
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())

    def test_parent_close_refuses_new_io_on_its_original_live_child(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            child = root.open_area(area)
            value = child.create_writer('payload', 4)
            self.assertFalse(root.close())
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('closing parent reached open')):
                with self.assertRaises(LocalFileError):
                    child.create_writer('another', 4)
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('closing parent reached write')):
                with self.assertRaises(LocalFileError):
                    child.append(value, 0, b'NULL')
            self.assertEqual(child.observe(value).size, 0)
            self.assertTrue(child.close_writer(value))
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())

    def test_recycled_same_area_inode_is_not_closed_again_or_released_early(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            child = root.open_area(area)
            close = os.close
            foreign = []
            def close_then_reopen(fd):
                close(fd)
                foreign.append(os.open(path / area.name, os.O_RDONLY | os.O_DIRECTORY))
                self.assertEqual(foreign[0], fd)
                raise OSError('original area close acknowledgement lost')
            with patch('actql_sdk._local_files.os.close', side_effect=close_then_reopen):
                self.assertFalse(root.close_area(area))
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('recycled same-inode fd closed')):
                self.assertFalse(root.close_area(area))
                self.assertFalse(root.close())
            self.assertEqual(root._used_slots(), 1)
            self.assertEqual(os.fstat(foreign[0]).st_ino, area.identity.inode)
            close(foreign[0])
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())

    def test_copied_parent_or_child_root_never_closes_or_opens_original_descriptors(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            child = root.open_area(area)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('copy closed original fd')):
                for original in (root, child):
                    with self.assertRaises(ValueError):
                        copy.copy(original).close()
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('copied root opened file')):
                for original in (root, child):
                    with self.assertRaises(ValueError):
                        copy.copy(original).create_writer('copied', 4)
            self.assertFalse(root._closing)
            self.assertFalse(child._closing)
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())

    def test_raced_foreign_directory_fd_keeps_its_actual_identity_until_physical_stop(self):
        with TemporaryDirectory(prefix='actql-local-area-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            (path / 'foreign').mkdir(mode=0o700)
            foreign = (path / 'foreign').stat()
            physical_open = os.open
            def open_foreign(name, *args, **kwargs):
                return physical_open('foreign' if name == area.name else name, *args, **kwargs)
            with patch('actql_sdk._local_files.os.open', side_effect=open_foreign):
                with self.assertRaises(LocalAreaAcquisitionError):
                    root.open_area(area)
            child = area.directory
            self.assertEqual(child._identity, PhysicalFileIdentity(foreign.st_dev, foreign.st_ino))
            self.assertNotEqual(child._identity, area.identity)
            descriptor = child._descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('foreign fd stop failed')):
                self.assertFalse(root.close_area(area))
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('uncertain original fd closed twice')):
                self.assertFalse(root.close_area(area))
                self.assertFalse(root.close())
            self.assertEqual(child._descriptor, descriptor)
            self.assertEqual(root._used_slots(), 1)
            os.close(descriptor)
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())
            self.assertTrue((path / 'foreign').exists())
