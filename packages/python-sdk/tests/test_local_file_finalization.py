"""Actual POSIX stop/final-name facts; no Core/Store/Run completion claims."""
import copy
from contextlib import contextmanager
import errno
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError, LocalFileRoot, PhysicalFileIdentity


class LocalFinalNameTests(unittest.TestCase):
    body = b'NULL/e\xcc\x81\r\n\x00'
    digest = 'sha256:513d3f191a4592178cdc0bd55912ecf1b334141d4daee1b18f0a113164d676e8'

    @contextmanager
    def file(self, body=None, complete=True):
        if body is None:
            body = self.body
        with TemporaryDirectory(prefix='actql-local-final-name-') as directory:
            path = Path(directory)
            root = LocalFileRoot(path, max_files=2, max_chunk_bytes=4)
            value = root.create_writer('stage-original', 32)
            for offset in range(0, len(body), 4):
                root.append(value, offset, body[offset:offset + 4])
            snapshot = root.begin_snapshot(value)
            if complete:
                for _ in range(100):
                    if root.advance_snapshot(snapshot) is not None:
                        break
                else:
                    raise AssertionError('Independent bounded snapshot did not finish')
            try:
                yield path, root, value, snapshot
            finally:
                if id(value) in root._files:
                    stopped = root.close_writer(value)
                    if value.finalization is not None:
                        self.assertTrue(root.close_finalization(value.finalization))
                    if not stopped:
                        self.assertTrue(root.close_writer(value))
                self.assertTrue(root.close())

    def test_exact_original_stop_precedes_final_link_and_preserves_bytes_digest_and_slot(self):
        with self.file() as (path, root, value, snapshot):
            descriptor = value.descriptor
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            self.assertFalse(root.close_finalization(cursor))
            link = os.link

            def after_actual_stop(*args, **kwargs):
                self.assertIsNone(value.descriptor)
                with self.assertRaises(OSError) as stopped:
                    os.fstat(descriptor)
                self.assertEqual(stopped.exception.errno, errno.EBADF)
                return link(*args, **kwargs)

            with patch('actql_sdk._local_files.os.link', side_effect=after_actual_stop):
                actual = root.advance_finalization(cursor)
            self.assertIs(actual, snapshot.result)
            self.assertEqual(actual.physical_digest, self.digest)
            self.assertEqual(actual.observation.size, 11)
            self.assertEqual(value.name, 'payload-original')
            self.assertTrue(cursor.stopped)
            self.assertTrue(cursor.source_removed)
            self.assertEqual(root._used_slots(), 1)
            self.assertFalse((path / 'stage-original').exists())
            final = (path / 'payload-original').stat()
            self.assertEqual(actual.observation.identity, PhysicalFileIdentity(final.st_dev, final.st_ino))
            self.assertEqual((path / 'payload-original').read_bytes(), self.body)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('final reacquisition')):
                self.assertIs(root.advance_finalization(cursor), actual)
            self.assertTrue(root.close_finalization(cursor))
            with self.assertRaises(ValueError):
                root.advance_finalization(cursor)
            with self.assertRaises(LocalFileError):
                root.append(value, 11, b'x')

    def test_empty_result_has_fixed_empty_digest_and_actual_stopped_final_name(self):
        with self.file(b'') as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-empty')
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('empty read')):
                result = root.advance_finalization(cursor)
            self.assertEqual(result.observation.size, 0)
            self.assertEqual(result.physical_digest, 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
            self.assertEqual((path / 'payload-empty').read_bytes(), b'')
            self.assertTrue(root.close_finalization(cursor))

    def test_incomplete_original_snapshot_refuses_finalization_before_close_or_link(self):
        with self.file(complete=False) as (_, root, value, snapshot):
            self.assertIsNone(root.advance_snapshot(snapshot))
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('incomplete stop')):
                with self.assertRaises(LocalFileError):
                    root.begin_finalization(value, snapshot, 'payload-original')
            self.assertIsNone(value.finalization)

    def test_copied_foreign_files_snapshots_cursors_or_invalid_names_refuse_before_io(self):
        with self.file() as (_, root, value, snapshot):
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('foreign link')):
                for action in (lambda: root.begin_finalization(copy.copy(value), snapshot, 'payload-original'),
                               lambda: root.begin_finalization(value, copy.copy(snapshot), 'payload-original'),
                               lambda: root.begin_finalization(value, snapshot, '../payload'),
                               lambda: root.begin_finalization(value, snapshot, 'e\u0301')):
                    with self.assertRaises(ValueError):
                        action()
                cursor = root.begin_finalization(value, snapshot, 'payload-original')
                with self.assertRaises(ValueError):
                    root.advance_finalization(copy.copy(cursor))
                with self.assertRaises(ValueError):
                    root.close_finalization(copy.copy(cursor))
                with self.assertRaises(LocalFileError):
                    root.begin_finalization(value, snapshot, 'another')

    def test_failed_file_flush_retains_same_live_writer_and_retries_without_writing(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            descriptor = value.descriptor
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError(errno.EIO, 'Flush failed')):
                with self.assertRaises(OSError):
                    root.advance_finalization(cursor)
            self.assertEqual(value.descriptor, descriptor)
            self.assertFalse(cursor.stopped)
            self.assertFalse(cursor.linked)
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('repeated original write')):
                self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)

    def test_unknown_close_keeps_original_cursor_and_never_closes_again_or_links(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            descriptor = value.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError(errno.EIO, 'Close unknown')):
                with self.assertRaisesRegex(LocalFileError, 'physical stop remains unknown'):
                    root.advance_finalization(cursor)
            self.assertTrue(value.close_pending)
            self.assertIs(value.finalization, cursor)
            self.assertFalse(root.close_finalization(cursor))
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('unknown close repeated')):
                with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('unconfirmed stop linked')):
                    with self.assertRaisesRegex(LocalFileError, 'physical stop remains unknown'):
                        root.advance_finalization(cursor)
            self.assertEqual(value.descriptor, descriptor)
            # Independent fixture supplies real stop, not an inferred success.
            os.close(descriptor)
            self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)

    def test_lost_close_ack_observes_ebadf_without_repeating_close(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            close = os.close

            def lost_ack(descriptor):
                close(descriptor)
                raise OSError(errno.EIO, 'Lost stop acknowledgement')

            with patch('actql_sdk._local_files.os.close', side_effect=lost_ack):
                with self.assertRaises(LocalFileError):
                    root.advance_finalization(cursor)
            self.assertTrue(value.close_pending)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('observed stop closed again')):
                self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)
            self.assertIsNone(value.descriptor)

    def test_different_recycled_descriptor_is_never_closed_as_original(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            descriptor = value.descriptor
            close = os.close
            foreign = None

            def recycle_after_stop(stopped):
                nonlocal foreign
                close(stopped)
                foreign = os.open(path / 'foreign', os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
                self.assertEqual(foreign, descriptor)
                raise OSError(errno.EIO, 'Descriptor recycled')

            try:
                with patch('actql_sdk._local_files.os.close', side_effect=recycle_after_stop):
                    with self.assertRaises(LocalFileError):
                        root.advance_finalization(cursor)
                with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('foreign descriptor closed')):
                    self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)
                self.assertEqual(os.fstat(foreign).st_ino, (path / 'foreign').stat().st_ino)
            finally:
                if foreign is not None:
                    close(foreign)

    def test_same_inode_recycled_descriptor_remains_unknown_without_another_close(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            descriptor = value.descriptor
            close = os.close
            recycled = None

            def recycle_same_inode(stopped):
                nonlocal recycled
                close(stopped)
                recycled = os.open(path / 'stage-original', os.O_RDONLY)
                self.assertEqual(recycled, descriptor)
                raise OSError(errno.EIO, 'Same inode recycled')

            with patch('actql_sdk._local_files.os.close', side_effect=recycle_same_inode):
                with self.assertRaises(LocalFileError):
                    root.advance_finalization(cursor)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('same inode closed again')):
                with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('unknown stop linked')):
                    with self.assertRaises(LocalFileError):
                        root.advance_finalization(cursor)
            self.assertFalse(root.close_finalization(cursor))
            close(recycled)
            self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)

    def test_existing_final_file_directory_or_symlink_is_not_replaced_or_adopted(self):
        for kind in ('file', 'directory', 'symlink'):
            with self.subTest(kind=kind), self.file() as (path, root, value, snapshot):
                target = path / 'payload-original'
                if kind == 'file':
                    target.write_bytes(b'foreign')
                elif kind == 'directory':
                    target.mkdir()
                else:
                    target.symlink_to(path / 'stage-original')
                cursor = root.begin_finalization(value, snapshot, target.name)
                with self.assertRaises(FileExistsError):
                    root.advance_finalization(cursor)
                self.assertTrue(cursor.stopped)
                self.assertFalse(cursor.linked)
                self.assertIsNone(value.descriptor)
                with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('refused final acquisition repeated')):
                    with self.assertRaises(LocalFileError):
                        root.advance_finalization(cursor)
                self.assertEqual((path / 'stage-original').read_bytes(), self.body)
                if kind == 'file':
                    self.assertEqual(target.read_bytes(), b'foreign')
                elif kind == 'directory':
                    self.assertTrue(target.is_dir())
                else:
                    self.assertTrue(target.is_symlink())

    def test_lost_final_link_ack_remains_unknown_despite_same_inode_pathname(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            link = os.link

            def lost_ack(*args, **kwargs):
                link(*args, **kwargs)
                raise OSError(errno.EIO, 'Lost final link acknowledgement')

            with patch('actql_sdk._local_files.os.link', side_effect=lost_ack):
                with self.assertRaises(OSError):
                    root.advance_finalization(cursor)
            self.assertTrue(cursor.link_unknown)
            self.assertFalse(cursor.linked)
            self.assertIsNone(cursor.result)
            self.assertIsNone(value.descriptor)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('unknown final acquisition repeated')):
                with self.assertRaises(LocalFileError):
                    root.advance_finalization(cursor)
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)
            self.assertEqual((path / 'payload-original').read_bytes(), self.body)
            self.assertEqual(root._used_slots(), 1)
            self.assertTrue(root.close_finalization(cursor))
            self.assertTrue(root.close_writer(value))
            self.assertEqual((path / 'payload-original').read_bytes(), self.body)

    def test_unknown_final_link_error_without_visible_target_never_retries_acquisition(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            with patch('actql_sdk._local_files.os.link', side_effect=OSError(errno.EIO, 'Unknown link result')):
                with self.assertRaises(OSError):
                    root.advance_finalization(cursor)
            self.assertTrue(cursor.link_unknown)
            self.assertFalse((path / 'payload-original').exists())
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('unknown final acquisition retried')):
                with self.assertRaises(LocalFileError):
                    root.advance_finalization(cursor)
            self.assertIsNone(cursor.result)
            self.assertIsNone(value.descriptor)

    def test_known_final_link_directory_sync_failure_retries_same_custody_only(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            sync = os.fsync

            def fail_directory(descriptor):
                if descriptor == root._descriptor:
                    raise OSError(errno.EIO, 'Final directory sync failed')
                sync(descriptor)

            with patch('actql_sdk._local_files.os.fsync', side_effect=fail_directory):
                with self.assertRaises(OSError):
                    root.advance_finalization(cursor)
            self.assertTrue(cursor.linked)
            self.assertFalse(cursor.source_removed)
            self.assertTrue((path / 'stage-original').exists())
            self.assertTrue((path / 'payload-original').exists())
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('known final link repeated')):
                self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)

    def test_replaced_original_stage_is_never_unlinked_as_owned_after_link(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            link = os.link

            def replace_original(*args, **kwargs):
                link(*args, **kwargs)
                (path / 'stage-original').unlink()
                (path / 'stage-original').write_bytes(b'foreign')

            with patch('actql_sdk._local_files.os.link', side_effect=replace_original):
                with self.assertRaises(LocalFileError):
                    root.advance_finalization(cursor)
            self.assertEqual((path / 'stage-original').read_bytes(), b'foreign')
            self.assertEqual((path / 'payload-original').read_bytes(), self.body)

    def test_replaced_final_target_never_returns_original_digest_or_unlinks_stage(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            link = os.link

            def replace_target(*args, **kwargs):
                link(*args, **kwargs)
                (path / 'payload-original').unlink()
                (path / 'payload-original').write_bytes(b'foreign')

            with patch('actql_sdk._local_files.os.link', side_effect=replace_target):
                with self.assertRaises(LocalFileError):
                    root.advance_finalization(cursor)
            self.assertIsNone(cursor.result)
            self.assertEqual((path / 'stage-original').read_bytes(), self.body)
            self.assertEqual((path / 'payload-original').read_bytes(), b'foreign')

    def test_failed_owned_stage_unlink_retries_only_original_guarded_cleanup(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            with patch('actql_sdk._local_files.os.unlink', side_effect=OSError(errno.EIO, 'Stage unlink failed')):
                with self.assertRaises(OSError):
                    root.advance_finalization(cursor)
            self.assertTrue(cursor.remove_unknown)
            with patch('actql_sdk._local_files.os.link', side_effect=AssertionError('known final acquisition repeated')):
                self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)

    def test_lost_stage_unlink_ack_confirms_original_absence_without_unlink_repetition(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            unlink = os.unlink

            def lost_ack(*args, **kwargs):
                unlink(*args, **kwargs)
                raise OSError(errno.EIO, 'Lost stage unlink acknowledgement')

            with patch('actql_sdk._local_files.os.unlink', side_effect=lost_ack):
                with self.assertRaises(OSError):
                    root.advance_finalization(cursor)
            with patch('actql_sdk._local_files.os.unlink', side_effect=AssertionError('uncertain stage unlink repeated')):
                self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)

    def test_final_sync_after_stage_removal_keeps_unsettled_cursor_and_slot(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            sync = os.fsync
            count = 0

            def fail_last_directory_sync(descriptor):
                nonlocal count
                if descriptor == root._descriptor:
                    count += 1
                    if count == 2:
                        raise OSError(errno.EIO, 'Final sync failed after unlink')
                sync(descriptor)

            with patch('actql_sdk._local_files.os.fsync', side_effect=fail_last_directory_sync):
                with self.assertRaises(OSError):
                    root.advance_finalization(cursor)
            self.assertTrue(cursor.source_removed)
            self.assertIsNone(cursor.result)
            self.assertEqual(root._used_slots(), 1)
            with patch('actql_sdk._local_files.os.unlink', side_effect=AssertionError('known stage unlink repeated')):
                self.assertEqual(root.advance_finalization(cursor).physical_digest, self.digest)

    def test_same_size_changed_final_bytes_refuse_cached_result_even_with_restored_mtime(self):
        with self.file() as (path, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            root.advance_finalization(cursor)
            target = path / 'payload-original'
            before = target.stat()
            target.write_bytes(b'x' * len(self.body))
            os.utime(target, ns=(before.st_atime_ns, before.st_mtime_ns))
            self.assertNotEqual(target.stat().st_ctime_ns, before.st_ctime_ns)
            with self.assertRaisesRegex(LocalFileError, 'final-name generation changed'):
                root.advance_finalization(cursor)

    def test_original_cached_snapshot_cannot_be_reused_during_final_name_work(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            with self.assertRaises(LocalFileError):
                root.advance_snapshot(snapshot)
            self.assertFalse(snapshot.invalid)
            root.advance_finalization(cursor)
            with self.assertRaises(LocalFileError):
                root.advance_snapshot(snapshot)
            self.assertFalse(snapshot.invalid)

    def test_close_stops_original_writer_but_pins_cursor_until_transport_retirement(self):
        with self.file() as (_, root, value, snapshot):
            cursor = root.begin_finalization(value, snapshot, 'payload-original')
            self.assertFalse(root.close())
            self.assertFalse(root.close_finalization(cursor))
            self.assertFalse(root.close_writer(value))
            self.assertIsNone(value.descriptor)
            with self.assertRaises(LocalFileError):
                root.advance_finalization(cursor)
            self.assertIn(id(cursor), root._finalizations)
            self.assertTrue(root.close_finalization(cursor))
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
