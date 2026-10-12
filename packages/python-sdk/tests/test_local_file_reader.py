"""Actual descriptor/chunk custody; physical EOF is not Core publication."""
import copy
from contextlib import contextmanager
import errno
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import (LocalFileError, LocalFileRoot,
                                   LocalReaderAcquisitionError)


class LocalFileReaderTests(unittest.TestCase):
    body = b'NULL/e\xcc\x81\r\n\x00'
    digest = 'sha256:513d3f191a4592178cdc0bd55912ecf1b334141d4daee1b18f0a113164d676e8'

    @contextmanager
    def file(self, body=None, slots=3):
        if body is None:
            body = self.body
        with TemporaryDirectory(prefix='actql-local-original-reader-') as directory:
            path = Path(directory)
            root = LocalFileRoot(path, max_files=slots, max_chunk_bytes=4)
            value = root.create_writer('stage-original', 32)
            for offset in range(0, len(body), 4):
                root.append(value, offset, body[offset:offset + 4])
            snapshot = root.begin_snapshot(value)
            while root.advance_snapshot(snapshot) is None:
                pass
            final = root.begin_finalization(value, snapshot, 'payload-original')
            root.advance_finalization(final)
            try:
                yield path, root, value, final
            finally:
                for reader in list(root._readers.values()):
                    self.assertTrue(root.close_reader(reader))
                if value.finalization is not None:
                    self.assertTrue(root.close_finalization(final))
                self.assertTrue(root.close_writer(value))
                self.assertTrue(root.close())

    def consume(self, root, reader):
        chunks = []
        for _ in range(20):
            chunk = root.read_reader(reader)
            chunks.append(chunk)
            root.release_reader_chunk(reader, chunk)
            if chunk.eof:
                return chunks
        raise AssertionError('Independent bounded reader did not reach EOF')

    def test_exact_original_bounded_chunks_no_second_read_before_release(self):
        with self.file() as (path, root, value, final):
            reader = root.open_reader(final)
            self.assertIsNone(value.descriptor)
            self.assertEqual(root._used_slots(), 2)
            self.assertFalse(root.close_finalization(final))
            pread = os.pread
            sizes = []

            def bounded(descriptor, size, offset):
                sizes.append((size, offset))
                return pread(descriptor, size, offset)

            with patch('actql_sdk._local_files.os.pread', side_effect=bounded):
                chunk = root.read_reader(reader)
                self.assertEqual((chunk.offset, chunk.data, chunk.eof), (0, b'NULL', False))
                self.assertIs(root.read_reader(reader), chunk)
                self.assertEqual(reader.offset, 0)
                root.release_reader_chunk(reader, chunk)
                chunks = self.consume(root, reader)
            self.assertEqual(sizes, [(4, 0), (4, 4), (3, 8)])
            self.assertEqual([(c.offset, c.eof) for c in chunks], [(4, False), (8, True)])
            self.assertEqual(chunk.data + b''.join(c.data for c in chunks), self.body)
            self.assertEqual('sha256:' + reader.hash.hexdigest(), self.digest)
            self.assertTrue(root.finish_reader(reader))
            self.assertEqual(root._used_slots(), 1)
            self.assertEqual((path / 'payload-original').read_bytes(), self.body)
            self.assertIs(final.result, final.snapshot.result)

    def test_empty_original_requires_empty_eof_chunk_release_before_finish(self):
        with self.file(b'') as (_, root, _, final):
            reader = root.open_reader(final)
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('empty read')):
                chunk = root.read_reader(reader)
            self.assertEqual((chunk.offset, chunk.data, chunk.eof), (0, b'', True))
            with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                root.finish_reader(reader)
            root.release_reader_chunk(reader, chunk)
            self.assertTrue(root.finish_reader(reader))

    def test_copied_foreign_cursors_and_chunks_cannot_release_original_custody(self):
        with self.file() as (_, root, _, final):
            with self.assertRaises(ValueError):
                root.open_reader(copy.copy(final))
            reader = root.open_reader(final)
            chunk = root.read_reader(reader)
            for operation in (lambda: root.read_reader(copy.copy(reader)),
                              lambda: root.close_reader(copy.copy(reader)),
                              lambda: root.release_reader_chunk(reader, copy.copy(chunk))):
                with self.assertRaises(ValueError):
                    operation()
            self.assertIs(reader.chunk, chunk)
            self.assertEqual(reader.offset, 0)
            root.release_reader_chunk(reader, chunk)
            with self.assertRaises(ValueError):
                root.release_reader_chunk(reader, chunk)

    def test_finalization_completion_and_capacity_precede_readonly_open(self):
        with self.file(slots=1) as (_, root, _, final):
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('unreserved open')):
                with self.assertRaisesRegex(LocalFileError, 'capacity'):
                    root.open_reader(final)
            self.assertFalse(root._readers)
        with self.file() as (_, root, _, final):
            original = final.result
            final.result = None
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('incomplete open')):
                with self.assertRaises(LocalFileError):
                    root.open_reader(final)
            final.result = original

    def test_parallel_readers_and_allocation_area_share_original_descriptor_limit(self):
        with self.file() as (_, root, _, final):
            first = root.open_reader(final)
            area = root.create_area('allocation-original')
            self.assertEqual(root._used_slots(), 3)
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('Parallel capacity bypass')):
                with self.assertRaisesRegex(LocalFileError, 'capacity'):
                    root.open_reader(final)
            self.assertTrue(root.close_area(area))
            second = root.open_reader(final)
            self.assertEqual(root._used_slots(), 3)
            first_chunk = root.read_reader(first)
            second_chunk = root.read_reader(second)
            self.assertIsNot(first_chunk, second_chunk)
            self.assertEqual(first_chunk.data, second_chunk.data)
            with self.assertRaises(ValueError):
                root.release_reader_chunk(second, first_chunk)
            root.release_reader_chunk(first, first_chunk)
            self.assertEqual((first.offset, second.offset), (4, 0))
            self.assertTrue(root.close_reader(first))
            self.assertFalse(root.close_finalization(final))
            self.assertTrue(root.close_reader(second))

    def test_failed_open_retains_original_cursor_and_slot_until_explicit_cleanup(self):
        with self.file() as (_, root, _, final):
            with patch('actql_sdk._local_files.os.open', side_effect=OSError(errno.EMFILE, 'No descriptor')):
                with self.assertRaises(LocalReaderAcquisitionError) as failure:
                    root.open_reader(final)
            reader = failure.exception.original_reader
            self.assertIs(reader.finalization, final)
            self.assertIsNone(reader.descriptor)
            self.assertEqual(root._used_slots(), 2)
            self.assertFalse(root.close_finalization(final))
            self.assertTrue(root.close_reader(reader))
            self.assertEqual(root._used_slots(), 1)

    def test_post_open_validation_failure_retains_acquired_fd_until_same_handle_close(self):
        with self.file() as (_, root, _, final):
            fstat = os.fstat
            opened = []
            original_open = os.open

            def capture(*args, **kwargs):
                descriptor = original_open(*args, **kwargs)
                opened.append(descriptor)
                return descriptor

            def fail_new(descriptor):
                if descriptor in opened:
                    raise OSError(errno.EIO, 'Original post-open observation failed')
                return fstat(descriptor)

            with patch('actql_sdk._local_files.os.open', side_effect=capture):
                with patch('actql_sdk._local_files.os.fstat', side_effect=fail_new):
                    with self.assertRaises(LocalReaderAcquisitionError) as failure:
                        root.open_reader(final)
            reader = failure.exception.original_reader
            self.assertEqual(reader.descriptor, opened[0])
            self.assertTrue(reader.invalid)
            self.assertFalse(root.close_finalization(final))
            self.assertTrue(root.close_reader(reader))
            with self.assertRaises(OSError) as stopped:
                os.fstat(opened[0])
            self.assertEqual(stopped.exception.errno, errno.EBADF)

    def test_read_io_failure_keeps_same_offset_and_descriptor_for_retry(self):
        with self.file() as (_, root, _, final):
            reader = root.open_reader(final)
            descriptor = reader.descriptor
            with patch('actql_sdk._local_files.os.pread', side_effect=OSError(errno.EIO, 'Read failed')):
                with self.assertRaises(OSError):
                    root.read_reader(reader)
            self.assertEqual(reader.offset, 0)
            self.assertIsNone(reader.chunk)
            self.assertFalse(reader.invalid)
            self.assertEqual(reader.descriptor, descriptor)
            self.assertEqual(root.read_reader(reader).data, b'NULL')

    def test_short_read_invalidates_without_returning_partial_success_or_advancing(self):
        with self.file() as (_, root, _, final):
            reader = root.open_reader(final)
            with patch('actql_sdk._local_files.os.pread', return_value=b'N'):
                with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                    root.read_reader(reader)
            self.assertTrue(reader.invalid)
            self.assertEqual(reader.offset, 0)
            self.assertIsNone(reader.chunk)
            with self.assertRaises(LocalFileError):
                root.read_reader(reader)

    def test_cached_chunk_rechecks_same_size_generation_before_return_or_release(self):
        with self.file() as (path, root, _, final):
            reader = root.open_reader(final)
            chunk = root.read_reader(reader)
            target = path / 'payload-original'
            stamp = target.stat()
            with target.open('r+b') as output:
                output.write(b'FAIL')
            os.utime(target, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            with self.assertRaisesRegex(LocalFileError, 'generation changed'):
                root.read_reader(reader)
            self.assertIs(reader.chunk, chunk)
            self.assertEqual(reader.offset, 0)
            with self.assertRaises(LocalFileError):
                root.release_reader_chunk(reader, chunk)

    def test_mutation_during_pread_is_rejected_before_chunk_is_returned(self):
        with self.file() as (path, root, _, final):
            reader = root.open_reader(final)
            pread = os.pread

            def change_after_read(*args):
                data = pread(*args)
                with (path / 'payload-original').open('r+b') as output:
                    output.write(b'FAIL')
                return data

            with patch('actql_sdk._local_files.os.pread', side_effect=change_after_read):
                with self.assertRaises(LocalFileError):
                    root.read_reader(reader)
            self.assertIsNone(reader.chunk)
            self.assertEqual(reader.offset, 0)

    def test_replaced_final_name_refuses_original_descriptor_data(self):
        with self.file() as (path, root, _, final):
            reader = root.open_reader(final)
            target = path / 'payload-original'
            target.rename(path / 'retained-original')
            target.write_bytes(self.body)
            target.chmod(0o600)
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('replaced name read')):
                with self.assertRaises(LocalFileError):
                    root.read_reader(reader)
            self.assertEqual((path / 'retained-original').read_bytes(), self.body)

    def test_eof_is_not_finish_and_digest_failure_retains_original_pin(self):
        with self.file() as (_, root, _, final):
            reader = root.open_reader(final)
            with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                root.finish_reader(reader)
            self.consume(root, reader)
            with self.assertRaisesRegex(LocalFileError, 'already released'):
                root.read_reader(reader)
            # Independent fault exposes corrupt transfer without weakening the
            # original final snapshot or asking Core to accept an altered hash.
            reader.hash.update(b'wrong')
            with self.assertRaisesRegex(LocalFileError, 'digest changed'):
                root.finish_reader(reader)
            self.assertFalse(root.close_finalization(final))
            self.assertEqual(root._used_slots(), 2)

    def test_close_unknown_retains_chunk_and_pin_without_second_close(self):
        with self.file() as (_, root, _, final):
            reader = root.open_reader(final)
            chunk = root.read_reader(reader)
            descriptor = reader.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError(errno.EIO, 'Stop unknown')):
                self.assertFalse(root.close_reader(reader))
            self.assertIs(reader.chunk, chunk)
            self.assertEqual(root._used_slots(), 2)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('Unknown close repeated')):
                self.assertFalse(root.close_reader(reader))
            with self.assertRaisesRegex(LocalFileError, 'before physical completion'):
                root.finish_reader(reader)
            with self.assertRaises(LocalFileError):
                root.read_reader(reader)
            os.close(descriptor)
            self.assertTrue(root.close_reader(reader))
            self.assertEqual(root._used_slots(), 1)

    def test_finish_lost_close_ack_retries_observation_and_never_closes_twice(self):
        with self.file() as (_, root, _, final):
            reader = root.open_reader(final)
            self.consume(root, reader)
            close = os.close

            def lost(descriptor):
                close(descriptor)
                raise OSError(errno.EIO, 'Lost stop acknowledgement')

            with patch('actql_sdk._local_files.os.close', side_effect=lost):
                self.assertFalse(root.finish_reader(reader))
            self.assertTrue(reader.finish_ready)
            self.assertEqual(root._used_slots(), 2)
            with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('Finished close repeated')):
                self.assertTrue(root.finish_reader(reader))

    def test_recycled_descriptor_never_closes_foreign_file_and_same_inode_stays_unknown(self):
        with self.file() as (path, root, _, final):
            reader = root.open_reader(final)
            descriptor = reader.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError(errno.EIO, 'Unknown close')):
                self.assertFalse(root.close_reader(reader))
            os.close(descriptor)
            reused = os.open(path / 'payload-original', os.O_RDONLY)
            self.assertEqual(reused, descriptor)
            self.assertFalse(root.close_reader(reader))
            os.close(reused)
            foreign = path / 'foreign'
            foreign.write_bytes(b'foreign')
            reused = os.open(foreign, os.O_RDONLY)
            self.assertEqual(reused, descriptor)
            try:
                with patch('actql_sdk._local_files.os.close', side_effect=AssertionError('Foreign descriptor closed')):
                    self.assertTrue(root.close_reader(reader))
                self.assertEqual(os.pread(reused, 7, 0), b'foreign')
            finally:
                os.close(reused)

    def test_root_and_writer_close_keep_original_cursor_until_reader_physically_stops(self):
        with self.file() as (path, root, value, final):
            reader = root.open_reader(final)
            chunk = root.read_reader(reader)
            self.assertFalse(root.close_writer(value))
            self.assertFalse(root.close())
            with self.assertRaises(LocalFileError):
                root.read_reader(reader)
            self.assertFalse(root.close_finalization(final))
            self.assertIs(reader.chunk, chunk)
            self.assertTrue(root.close_reader(reader))
            self.assertTrue(root.close_finalization(final))
            self.assertEqual((path / 'payload-original').read_bytes(), self.body)
