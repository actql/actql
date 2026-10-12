"""Independent actual descriptor snapshots, without Core publication claims."""
import copy
import hashlib
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError, LocalFileRoot, PhysicalFileIdentity


class LocalFileSnapshotTests(unittest.TestCase):
    def root(self, path):
        return LocalFileRoot(path, max_files=3, max_chunk_bytes=5)

    def write(self, root, value, body):
        for offset in range(0, len(body), 5):
            self.assertEqual(root.append(value, offset, body[offset:offset + 5]),
                             len(body[offset:offset + 5]))

    def finish(self, root, cursor):
        # A bounded independent test limit, not product completion inference.
        for _ in range(10):
            result = root.advance_snapshot(cursor)
            if result is not None:
                return result
        self.fail('Physical snapshot did not finish within independent fixture limit')

    def test_exact_bytes_bounded_steps_and_original_position_are_preserved(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('payload', 32)
            body = b'NULL/e\xcc\x81\r\n\x00'
            self.write(root, value, body)
            original = root.observe(value).identity
            cursor = root.begin_snapshot(value)
            pread = os.pread
            with patch('actql_sdk._local_files.os.pread', wraps=pread) as reads:
                self.assertIsNone(root.advance_snapshot(cursor))
                self.assertEqual(cursor.offset, 5)
                self.assertEqual(reads.call_count, 1)
                self.assertIsNone(root.advance_snapshot(cursor))
                result = root.advance_snapshot(cursor)
                self.assertEqual([call.args[1:] for call in reads.call_args_list],
                                 [(5, 0), (5, 5), (1, 10)])
            self.assertEqual(result.observation.identity, original)
            self.assertEqual(result.observation.size, 11)
            self.assertEqual(result.physical_digest, 'sha256:' + hashlib.sha256(body).hexdigest())
            self.assertEqual(os.lseek(value.descriptor, 0, os.SEEK_CUR), 11)
            self.assertIs(root.begin_snapshot(value), cursor)
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('repeated read')):
                self.assertIs(root.advance_snapshot(cursor), result)
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('stopped write')):
                with self.assertRaises(LocalFileError):
                    root.append(value, 11, b'x')
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertEqual((path / 'payload').read_bytes(), body)

    def test_empty_original_has_fixed_digest_and_no_read(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            root = self.root(Path(directory))
            value = root.create_writer('empty', 0)
            cursor = root.begin_snapshot(value)
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('empty read')):
                result = root.advance_snapshot(cursor)
            self.assertEqual(result.observation.size, 0)
            self.assertEqual(result.physical_digest,
                             'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_flush_failure_keeps_append_stopped_and_retries_same_descriptor(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            root = self.root(Path(directory))
            value = root.create_writer('payload', 4)
            self.write(root, value, b'NULL')
            original = value.descriptor
            with patch('actql_sdk._local_files.os.fsync', side_effect=OSError('flush failed')):
                with self.assertRaises(OSError):
                    root.begin_snapshot(value)
            self.assertIsNone(value.snapshot)
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('write repeated')):
                with self.assertRaises(LocalFileError):
                    root.append(value, 4, b'x')
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('file reopened')):
                result = self.finish(root, root.begin_snapshot(value))
            self.assertEqual(value.descriptor, original)
            self.assertEqual(result.observation.size, 4)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_unknown_write_refuses_snapshot_without_flush_or_read(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            root = self.root(Path(directory))
            value = root.create_writer('payload', 8)
            write = os.write

            def lose_ack(fd, data):
                write(fd, data)
                raise OSError('write acknowledgement lost')

            with patch('actql_sdk._local_files.os.write', side_effect=lose_ack):
                with self.assertRaises(OSError):
                    root.append(value, 0, b'NULL')
            with patch('actql_sdk._local_files.os.fsync', side_effect=AssertionError('unknown flush')):
                with self.assertRaises(LocalFileError):
                    root.begin_snapshot(value)
            self.assertIsNone(value.snapshot)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_copied_foreign_cursors_and_files_refuse_before_observation(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            root = self.root(Path(directory))
            first = root.create_writer('first', 4)
            second = root.create_writer('second', 4)
            cursor = root.begin_snapshot(first)
            copied_cursor = copy.copy(cursor)
            foreign_cursor = root.begin_snapshot(second)
            foreign_cursor.file = first
            with patch('actql_sdk._local_files.os.fstat', side_effect=AssertionError('foreign observation')):
                for invalid in (copied_cursor, foreign_cursor):
                    with self.assertRaises(ValueError):
                        root.advance_snapshot(invalid)
                with self.assertRaises(ValueError):
                    root.begin_snapshot(copy.copy(first))
            self.assertTrue(root.close_writer(first))
            self.assertTrue(root.close_writer(second))
            self.assertTrue(root.close())

    def test_name_replacement_never_adopts_foreign_bytes(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('payload', 8)
            self.write(root, value, b'NULL')
            cursor = root.begin_snapshot(value)
            (path / 'payload').rename(path / 'moved-original')
            (path / 'payload').write_bytes(b'NULL')
            with self.assertRaises(LocalFileError):
                root.advance_snapshot(cursor)
            self.assertTrue(cursor.invalid)
            self.assertIsNone(cursor.result)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())
            self.assertEqual((path / 'moved-original').read_bytes(), b'NULL')
            self.assertEqual((path / 'payload').read_bytes(), b'NULL')

    def test_same_size_changed_bytes_refuse_cached_result(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('payload', 4)
            self.write(root, value, b'NULL')
            cursor = root.begin_snapshot(value)
            self.finish(root, cursor)
            with (path / 'payload').open('r+b') as external:
                external.write(b'null')
                external.flush()
                os.fsync(external.fileno())
            current = (path / 'payload').stat()
            os.utime(path / 'payload', ns=(current.st_atime_ns, cursor.stamp[3] + 1000000))
            with self.assertRaises(LocalFileError):
                root.advance_snapshot(cursor)
            self.assertTrue(cursor.invalid)
            with self.assertRaises(LocalFileError):
                root.begin_snapshot(value)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_actual_changed_size_refuses_before_read(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('payload', 8)
            self.write(root, value, b'NULL')
            cursor = root.begin_snapshot(value)
            with (path / 'payload').open('ab') as external:
                external.write(b'x')
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('changed read')):
                with self.assertRaises(LocalFileError):
                    root.advance_snapshot(cursor)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_read_failure_retries_same_offset_without_a_write(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            root = self.root(Path(directory))
            value = root.create_writer('payload', 4)
            self.write(root, value, b'NULL')
            cursor = root.begin_snapshot(value)
            with patch('actql_sdk._local_files.os.pread', side_effect=OSError('read failed')):
                with self.assertRaises(OSError):
                    root.advance_snapshot(cursor)
            self.assertEqual(cursor.offset, 0)
            self.assertIsNone(cursor.result)
            with patch('actql_sdk._local_files.os.write', side_effect=AssertionError('read retry wrote')):
                result = self.finish(root, cursor)
            self.assertEqual(result.physical_digest, 'sha256:' + hashlib.sha256(b'NULL').hexdigest())
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_short_read_is_incomplete_and_cannot_be_reused(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            root = self.root(Path(directory))
            value = root.create_writer('payload', 4)
            self.write(root, value, b'NULL')
            cursor = root.begin_snapshot(value)
            pread = os.pread
            with patch('actql_sdk._local_files.os.pread', side_effect=lambda fd, n, at: pread(fd, 2, at)):
                with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                    root.advance_snapshot(cursor)
            self.assertEqual(cursor.offset, 0)
            self.assertIsNone(cursor.result)
            with self.assertRaises(LocalFileError):
                root.advance_snapshot(cursor)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_actual_mutation_during_read_invalidates_before_hashing(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('payload', 4)
            self.write(root, value, b'NULL')
            cursor = root.begin_snapshot(value)
            pread = os.pread

            def read_then_mutate(fd, count, offset):
                data = pread(fd, count, offset)
                with (path / 'payload').open('r+b') as external:
                    external.write(b'null')
                current = (path / 'payload').stat()
                os.utime(path / 'payload', ns=(current.st_atime_ns, cursor.stamp[3] + 1000000))
                return data

            with patch('actql_sdk._local_files.os.pread', side_effect=read_then_mutate):
                with self.assertRaises(LocalFileError):
                    root.advance_snapshot(cursor)
            self.assertTrue(cursor.invalid)
            self.assertEqual(cursor.offset, 0)
            self.assertIsNone(cursor.result)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_close_between_chunks_retires_cursor_but_preserves_named_data(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            path = Path(directory)
            root = self.root(path)
            value = root.create_writer('payload', 8)
            self.write(root, value, b'NULLNULL')
            cursor = root.begin_snapshot(value)
            self.assertIsNone(root.advance_snapshot(cursor))
            self.assertFalse(root.close())
            self.assertTrue(root.close_writer(value))
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('retired read')):
                with self.assertRaises(ValueError):
                    root.advance_snapshot(cursor)
            self.assertTrue(root.close())
            self.assertEqual((path / 'payload').read_bytes(), b'NULLNULL')

    def test_pending_descriptor_stop_preserves_cursor_and_capacity(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            root = self.root(Path(directory))
            value = root.create_writer('payload', 8)
            self.write(root, value, b'NULLNULL')
            cursor = root.begin_snapshot(value)
            self.assertIsNone(root.advance_snapshot(cursor))
            descriptor = value.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('stop failed')):
                self.assertFalse(root.close_writer(value))
            self.assertIs(root._files[id(value)], value)
            self.assertEqual(root._used_slots(), 1)
            self.assertFalse(root.close())
            with self.assertRaises(LocalFileError):
                root.advance_snapshot(cursor)
            self.assertFalse(root.close_writer(value))
            os.close(descriptor)
            self.assertTrue(root.close_writer(value))
            self.assertTrue(root.close())

    def test_original_allocation_child_uses_same_bounded_root_budget(self):
        with TemporaryDirectory(prefix='actql-file-snapshot-') as directory:
            path = Path(directory)
            root = self.root(path)
            area = root.create_area('alloc-original-1')
            child = root.open_area(area)
            value = child.create_writer('payload', 4)
            self.write(child, value, b'NULL')
            result = self.finish(child, child.begin_snapshot(value))
            physical = (path / 'alloc-original-1' / 'payload').stat()
            self.assertEqual(result.observation.identity,
                             PhysicalFileIdentity(physical.st_dev, physical.st_ino))
            self.assertEqual(root._used_slots(), 2)
            self.assertFalse(root.close_area(area))
            self.assertTrue(child.close_writer(value))
            self.assertTrue(root.close_area(area))
            self.assertEqual(root._used_slots(), 0)
            self.assertTrue(root.close())
            self.assertEqual((path / 'alloc-original-1' / 'payload').read_bytes(), b'NULL')


if __name__ == '__main__':
    unittest.main()
