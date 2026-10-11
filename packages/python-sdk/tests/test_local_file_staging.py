"""Actual POSIX staging-name custody, separate from Core/Store completion."""
import copy
from contextlib import contextmanager
import errno
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError, LocalFileRoot, PhysicalFileIdentity


class LocalStagingNameTests(unittest.TestCase):
    body = b'NULL/e\xcc\x81\r\n\x00'

    @contextmanager
    def area(self):
        with TemporaryDirectory(prefix='actql-local-staging-') as directory:
            path = Path(directory)
            root = LocalFileRoot(path, max_files=3, max_chunk_bytes=16)
            area = root.create_area('alloc-original-1')
            origin = root.open_area(area)
            value = origin.create_writer('payload', 32)
            origin.append(value, 0, self.body)
            try:
                yield path, root, origin, value
            finally:
                owner = value.root
                if id(value) in owner._files:
                    stopped = owner.close_writer(value)
                    if value.adoption is not None:
                        self.assertTrue(value.adoption.origin.close_adoption(value.adoption))
                    if not stopped:
                        self.assertTrue(owner.close_writer(value))
                self.assertTrue(root.close_area(area))
                self.assertTrue(root.close())

    def test_exact_original_inode_bytes_offset_and_capacity_move_to_staging(self):
        with self.area() as (path, root, origin, value):
            observed = origin.observe(value)
            slots = root._used_slots()
            cursor = origin.begin_adoption(value, root, 'stage-original')
            self.assertIs(value.adoption, cursor)
            self.assertIn(id(cursor), root._name_transfers)
            with self.assertRaises(LocalFileError):
                origin.append(value, len(self.body), b'x')
            with self.assertRaises(LocalFileError):
                origin.begin_snapshot(value)
            self.assertEqual(origin.advance_adoption(cursor), observed)
            self.assertIs(value.root, root)
            self.assertEqual(value.name, 'stage-original')
            self.assertEqual(root._used_slots(), slots)
            self.assertFalse((path / 'alloc-original-1' / 'payload').exists())
            actual = (path / 'stage-original').stat()
            self.assertEqual(observed.identity, PhysicalFileIdentity(actual.st_dev, actual.st_ino))
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('duplicate acquisition')):
                self.assertEqual(origin.advance_adoption(cursor), observed)
            self.assertTrue(origin.close_adoption(cursor))
            self.assertEqual(root.append(value, len(self.body), b'x'), 1)
            self.assertEqual(root.sync(value).size, len(self.body) + 1)
            with self.assertRaises(ValueError):
                origin.close_writer(value)

    def test_same_root_name_move_and_cursor_retirement_do_not_reacquire(self):
        with self.area() as (path, root, origin, value):
            first = origin.begin_adoption(value, origin, 'stage-local')
            before = origin.observe(value)
            self.assertEqual(origin.advance_adoption(first), before)
            self.assertTrue(origin.close_adoption(first))
            self.assertEqual((path / 'alloc-original-1' / 'stage-local').read_bytes(), self.body)
            with self.assertRaises(ValueError):
                origin.advance_adoption(first)

    def test_foreign_or_copied_handles_roots_cursors_refuse_before_io(self):
        with self.area() as (_, root, origin, value), TemporaryDirectory() as other:
            foreign = LocalFileRoot(Path(other), max_files=3, max_chunk_bytes=16)
            try:
                with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('foreign acquisition')):
                    for target, handle in ((root, copy.copy(value)), (copy.copy(root), value), (foreign, value)):
                        with self.assertRaises(ValueError):
                            origin.begin_adoption(handle, target, 'stage-original')
                    for name in ('../stage', '', 'e\u0301', value.name):
                        with self.assertRaises((ValueError, LocalFileError)):
                            origin.begin_adoption(value, origin, name)
                    cursor = origin.begin_adoption(value, root, 'stage-original')
                    with self.assertRaises(ValueError):
                        origin.advance_adoption(copy.copy(cursor))
                    self.assertTrue(origin.close_adoption(cursor))
            finally:
                self.assertTrue(foreign.close())

    def test_existing_file_directory_or_symlink_is_never_overwritten_or_adopted(self):
        for kind in ('file', 'directory', 'symlink'):
            with self.subTest(kind=kind), self.area() as (path, root, origin, value):
                target = path / 'stage-original'
                if kind == 'file':
                    target.write_bytes(b'foreign')
                elif kind == 'directory':
                    target.mkdir()
                else:
                    target.symlink_to(path / 'alloc-original-1' / 'payload')
                cursor = origin.begin_adoption(value, root, 'stage-original')
                with self.assertRaises(FileExistsError):
                    origin.advance_adoption(cursor)
                with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('refused acquisition repeated')):
                    with self.assertRaises(LocalFileError):
                        origin.advance_adoption(cursor)
                self.assertFalse(cursor.linked)
                self.assertTrue((path / 'alloc-original-1' / 'payload').exists())
                if kind == 'file':
                    self.assertEqual(target.read_bytes(), b'foreign')
                elif kind == 'directory':
                    self.assertTrue(target.is_dir())
                else:
                    self.assertTrue(target.is_symlink())
                self.assertTrue(origin.close_adoption(cursor))

    def test_lost_link_ack_keeps_unknown_without_pathname_adoption_or_resend(self):
        with self.area() as (path, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            link = os.link

            def lost_ack(*args, **kwargs):
                link(*args, **kwargs)
                raise OSError(errno.EIO, 'Lost exclusive link acknowledgement')

            with patch('actql_sdk._local_files.os.link', side_effect=lost_ack):
                with self.assertRaises(OSError):
                    origin.advance_adoption(cursor)
            self.assertTrue(cursor.link_unknown)
            self.assertFalse(cursor.linked)
            self.assertIs(value.root, origin)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('unknown acquisition repeated')):
                with self.assertRaises(LocalFileError):
                    origin.advance_adoption(cursor)
            self.assertFalse(origin.close_adoption(cursor))
            self.assertFalse(origin.close_writer(value))
            self.assertIsNone(value.descriptor)
            self.assertTrue(origin.close_adoption(cursor))
            self.assertTrue(origin.close_writer(value))
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)
            self.assertEqual((path / 'alloc-original-1' / 'payload').read_bytes(), self.body)

    def test_sync_failure_keeps_one_known_link_and_original_private_name(self):
        with self.area() as (path, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError(errno.EIO, 'Directory sync failed')):
                with self.assertRaises(OSError):
                    origin.advance_adoption(cursor)
            self.assertTrue(cursor.linked)
            self.assertFalse(cursor.source_removed)
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)
            self.assertTrue((path / 'alloc-original-1' / 'payload').exists())
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('known link repeated')):
                self.assertEqual(origin.advance_adoption(cursor).size, len(self.body))
            self.assertTrue(origin.close_adoption(cursor))

    def test_replaced_acquired_target_refuses_and_never_unlinks_original(self):
        with self.area() as (path, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            link = os.link

            def replace_target(*args, **kwargs):
                link(*args, **kwargs)
                (path / 'stage-original').unlink()
                (path / 'stage-original').write_bytes(b'foreign')

            with patch('actql_sdk._local_files.os.link', side_effect=replace_target):
                with self.assertRaises(LocalFileError):
                    origin.advance_adoption(cursor)
            with patch('actql_sdk._local_files.os.unlink', side_effect=AssertionError('foreign cleanup')):
                with self.assertRaises(LocalFileError):
                    origin.advance_adoption(cursor)
            self.assertEqual((path / 'stage-original').read_bytes(), b'foreign')
            self.assertEqual((path / 'alloc-original-1' / 'payload').read_bytes(), self.body)

    def test_replaced_original_name_is_not_deleted_after_known_target_sync(self):
        with self.area() as (path, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            sync = os.fsync
            first = True

            def replace_source(descriptor):
                nonlocal first
                sync(descriptor)
                if first:
                    first = False
                    private = path / 'alloc-original-1' / 'payload'
                    private.unlink()
                    private.write_bytes(b'foreign')

            with patch('actql_sdk._local_files.os.fsync', side_effect=replace_source):
                with self.assertRaises(LocalFileError):
                    origin.advance_adoption(cursor)
            self.assertEqual((path / 'alloc-original-1' / 'payload').read_bytes(), b'foreign')
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)

    def test_failed_original_unlink_retries_only_same_guarded_name(self):
        with self.area() as (_, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            with patch('actql_sdk._local_files.os.unlink', side_effect=OSError(errno.EIO, 'Unlink failed')):
                with self.assertRaises(OSError):
                    origin.advance_adoption(cursor)
            self.assertTrue(cursor.remove_unknown)
            self.assertFalse(cursor.source_removed)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('known acquisition repeated')):
                self.assertEqual(origin.advance_adoption(cursor).size, len(self.body))
            self.assertTrue(origin.close_adoption(cursor))

    def test_lost_original_unlink_ack_confirms_absence_without_unlinking_again(self):
        with self.area() as (path, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            unlink = os.unlink

            def lost_ack(*args, **kwargs):
                unlink(*args, **kwargs)
                raise OSError(errno.EIO, 'Lost original unlink acknowledgement')

            with patch('actql_sdk._local_files.os.unlink', side_effect=lost_ack):
                with self.assertRaises(OSError):
                    origin.advance_adoption(cursor)
            self.assertTrue(cursor.remove_unknown)
            with patch('actql_sdk._local_files.os.unlink', side_effect=AssertionError('unknown unlink repeated')):
                self.assertEqual(origin.advance_adoption(cursor).size, len(self.body))
            self.assertFalse((path / 'alloc-original-1' / 'payload').exists())
            self.assertTrue(origin.close_adoption(cursor))

    def test_final_directory_sync_failure_retains_same_descriptor_and_target(self):
        with self.area() as (path, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            sync = os.fsync
            count = 0

            def fail_after_unlink(descriptor):
                nonlocal count
                count += 1
                if count == 3:
                    raise OSError(errno.EIO, 'Final origin sync failed')
                sync(descriptor)

            descriptor = value.descriptor
            with patch('actql_sdk._local_files.os.fsync', side_effect=fail_after_unlink):
                with self.assertRaises(OSError):
                    origin.advance_adoption(cursor)
            self.assertTrue(cursor.source_removed)
            self.assertFalse(cursor.complete)
            self.assertEqual(value.descriptor, descriptor)
            with patch('actql_sdk._local_files.os.unlink', side_effect=AssertionError('known unlink repeated')):
                self.assertEqual(origin.advance_adoption(cursor).size, len(self.body))
            self.assertTrue(origin.close_adoption(cursor))
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)

    def test_changed_original_size_refuses_before_link(self):
        with self.area() as (path, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            with (path / 'alloc-original-1' / 'payload').open('ab') as physical:
                physical.write(b'x')
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('changed generation linked')):
                with self.assertRaises(LocalFileError):
                    origin.advance_adoption(cursor)

    def test_stopped_snapshot_unknown_write_and_closing_refuse_new_name_work(self):
        for state in ('snapshot', 'unknown_write', 'closing'):
            with self.subTest(state=state), self.area() as (_, root, origin, value):
                if state == 'snapshot':
                    origin.begin_snapshot(value)
                elif state == 'unknown_write':
                    value.write_unknown = True
                else:
                    value.closing = True
                with self.assertRaises(LocalFileError):
                    origin.begin_adoption(value, root, 'stage-original')

    def test_parent_close_pins_both_roots_until_original_descriptor_stop_and_cursor_retire(self):
        with self.area() as (_, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError(errno.EIO, 'Sync failed')):
                with self.assertRaises(OSError):
                    origin.advance_adoption(cursor)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('live root closed')):
                self.assertFalse(root.close())
                self.assertFalse(origin.close())
            self.assertFalse(origin.close_adoption(cursor))
            descriptor = value.descriptor
            self.assertFalse(origin.close_writer(value))
            with self.assertRaises(OSError) as stopped:
                os.fstat(descriptor)
            self.assertEqual(stopped.exception.errno, errno.EBADF)
            self.assertIn(id(cursor), root._name_transfers)
            self.assertTrue(origin.close_adoption(cursor))
            self.assertTrue(origin.close_writer(value))

    def test_definite_name_refusal_keeps_original_writer_usable_after_cursor_close(self):
        with self.area() as (path, root, origin, value):
            (path / 'stage-original').write_bytes(b'foreign')
            cursor = origin.begin_adoption(value, root, 'stage-original')
            with self.assertRaises(FileExistsError):
                origin.advance_adoption(cursor)
            self.assertTrue(origin.close_adoption(cursor))
            self.assertEqual(origin.append(value, len(self.body), b'x'), 1)
            self.assertEqual((path / 'stage-original').read_bytes(), b'foreign')

    def test_pending_descriptor_close_never_releases_cursor_or_repeats_close(self):
        with self.area() as (_, root, origin, value):
            cursor = origin.begin_adoption(value, root, 'stage-original')
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError(errno.EIO, 'Sync failed')):
                with self.assertRaises(OSError):
                    origin.advance_adoption(cursor)
            descriptor = value.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError(errno.EIO, 'Close unknown')):
                self.assertFalse(origin.close_writer(value))
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('unknown close repeated')):
                self.assertFalse(origin.close_writer(value))
            self.assertFalse(origin.close_adoption(cursor))
            self.assertIs(value.adoption, cursor)
            # Independent fixture observes real stop of its retained descriptor;
            # production cannot infer this from a matching inode or close error.
            os.close(descriptor)
            self.assertFalse(origin.close_writer(value))
            self.assertTrue(origin.close_adoption(cursor))
            self.assertTrue(origin.close_writer(value))
