"""Actual original descriptor observations, not Core/Store acceptance."""
import copy
import os
from unittest.mock import patch
import unittest

from actql_sdk._local_files import LocalFileError
import test_local_file_reader as reader_fixture


class CompletedReaderTests(unittest.TestCase):
    body = reader_fixture.LocalFileReaderTests.body
    digest = reader_fixture.LocalFileReaderTests.digest
    file = reader_fixture.LocalFileReaderTests.file
    consume = reader_fixture.LocalFileReaderTests.consume

    def test_completed_observation_keeps_original_descriptor_and_rechecks_without_io(self):
        with self.file() as (path, root, value, final):
            reader = root.open_reader(final)
            self.consume(root, reader)
            descriptor = reader.descriptor
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('read repeated')), patch('actql_sdk._local_files.os.close', side_effect=AssertionError('premature close')):
                observed = root.observe_completed_reader(reader)
                self.assertIs(root.observe_completed_reader(reader), observed)
            actual = os.fstat(descriptor)
            self.assertEqual((observed.observation.identity.device, observed.observation.identity.inode, observed.observation.size), (actual.st_dev, actual.st_ino, len(self.body)))
            self.assertEqual(observed.physical_digest, self.digest)
            self.assertIs(observed, final.result)
            self.assertIs(root._readers[id(reader)], reader)
            self.assertEqual(reader.descriptor, descriptor)
            self.assertEqual(root._used_slots(), 2)
            self.assertFalse(root.close_finalization(final))
            self.assertTrue(root.finish_reader(reader))
            with self.assertRaises(ValueError):
                root.observe_completed_reader(reader)

    def test_missing_eof_and_outstanding_exact_chunk_do_not_grant_completion(self):
        with self.file(b'') as (_, root, _, final):
            reader = root.open_reader(final)
            with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                root.observe_completed_reader(reader)
            chunk = root.read_reader(reader)
            with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                root.observe_completed_reader(reader)
            self.assertFalse(reader.finish_ready)
            self.assertIs(reader.chunk, chunk)
            root.release_reader_chunk(reader, chunk)
            self.assertEqual(root.observe_completed_reader(reader).observation.size, 0)
            self.assertTrue(root.finish_reader(reader))

    def test_copied_and_foreign_reader_refuse_before_current_observation(self):
        with self.file() as (_, root, _, final), self.file() as (_, foreign, _, other):
            reader = root.open_reader(final)
            other_reader = foreign.open_reader(other)
            self.consume(root, reader)
            with patch('actql_sdk._local_files.os.fstat', side_effect=AssertionError('foreign reached descriptor')):
                for value in (copy.copy(reader), other_reader, final, final.result):
                    with self.assertRaises(ValueError):
                        root.observe_completed_reader(value)
            self.assertIs(root._readers[id(reader)], reader)

    def test_observation_does_not_cache_a_changed_final_name_as_current(self):
        with self.file() as (path, root, _, final):
            reader = root.open_reader(final)
            self.consume(root, reader)
            original = root.observe_completed_reader(reader)
            (path / final.name).rename(path / 'old-original')
            (path / final.name).write_bytes(self.body)
            os.chmod(path / final.name, 0o600)
            with self.assertRaisesRegex(LocalFileError, 'generation changed'):
                root.observe_completed_reader(reader)
            self.assertTrue(reader.invalid)
            self.assertIs(root._readers[id(reader)], reader)
            self.assertIs(final.result, original)
            self.assertTrue(root.close_reader(reader))

    def test_digest_mismatch_retains_same_descriptor_for_explicit_cleanup(self):
        with self.file() as (_, root, _, final):
            reader = root.open_reader(final)
            self.consume(root, reader)
            class WrongDigest:
                def hexdigest(self):
                    return '0' * 64
            reader.hash = WrongDigest()
            with self.assertRaisesRegex(LocalFileError, 'physical digest changed'):
                root.observe_completed_reader(reader)
            self.assertTrue(reader.invalid)
            self.assertFalse(reader.finish_ready)
            self.assertIs(root._readers[id(reader)], reader)
            self.assertEqual(root._used_slots(), 2)
            self.assertTrue(root.close_reader(reader))

    def test_close_uncertainty_keeps_original_pin_and_refuses_fresh_facts(self):
        with self.file() as (_, root, _, final):
            reader = root.open_reader(final)
            self.consume(root, reader)
            root.observe_completed_reader(reader)
            descriptor = reader.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('stop unknown')):
                self.assertFalse(root.finish_reader(reader))
            self.assertIs(root._readers[id(reader)], reader)
            self.assertEqual(reader.descriptor, descriptor)
            with self.assertRaisesRegex(LocalFileError, 'invalid or closing'):
                root.observe_completed_reader(reader)
            self.assertFalse(root.finish_reader(reader))
            os.close(descriptor)
            self.assertTrue(root.finish_reader(reader))
