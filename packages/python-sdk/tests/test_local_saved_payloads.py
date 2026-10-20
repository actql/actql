"""Real saved-generation File ports; not a Run/Store/grant acceptance."""
import copy
import hashlib
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_files import (
    LocalAreaAcquisitionError, LocalFileError, LocalFileRoot,
    LocalOriginalAcquisitionError, PhysicalFileIdentity,
    PhysicalFileObservation, PhysicalFileSnapshot,
)


class SavedPayloadDescriptorTests(unittest.TestCase):
    def fixture(self, path):
        area = path / 'saved-area'
        area.mkdir(mode=0o700)
        body = b'[{"n":1}]'
        file = area / 'saved-payload'
        file.write_bytes(body)
        file.chmod(0o600)
        directory, payload = area.stat(), file.stat()
        return (PhysicalFileIdentity(directory.st_dev, directory.st_ino),
                PhysicalFileSnapshot(PhysicalFileObservation(
                    PhysicalFileIdentity(payload.st_dev, payload.st_ino), len(body)),
                    'sha256:' + hashlib.sha256(body).hexdigest()), body)

    def consume(self, root, reader):
        chunks = []
        while not reader.eof:
            chunk = root.read_original(reader)
            self.assertIs(root.read_original(reader), chunk)
            chunks.append(chunk.data)
            root.release_original_chunk(reader, chunk)
        return b''.join(chunks)

    def test_new_root_restores_recorded_area_and_payload_without_creation_or_finalization(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)
            identity, expected, body = self.fixture(path)
            old = LocalFileRoot(path, max_files=3, max_chunk_bytes=4)
            self.assertTrue(old.close())
            root = LocalFileRoot(path, max_files=3, max_chunk_bytes=4)
            with patch('actql_sdk._local_files.os.mkdir', side_effect=AssertionError('creation')):
                area = root.restore_area('saved-area', identity)
            self.assertFalse(area.creation_synced)
            child = area.directory
            self.assertIsNotNone(child)
            reader = child.open_saved_payload('saved-payload', expected)
            with self.assertRaises(ValueError):
                child.read_original(copy.copy(reader))
            self.assertEqual(self.consume(child, reader), body)
            self.assertEqual(child.observe_original(reader), expected)
            self.assertFalse(root.close_area(area))
            self.assertTrue(child.close_original(reader))
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())
            self.assertEqual((path / 'saved-area' / 'saved-payload').read_bytes(), body)

    def test_foreign_area_symlink_and_duplicate_retain_only_original_cleanup(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)
            identity, _, body = self.fixture(path)
            root = LocalFileRoot(path, max_files=4, max_chunk_bytes=4)
            with self.assertRaises(LocalAreaAcquisitionError) as failure:
                root.restore_area('saved-area', PhysicalFileIdentity(identity.device, identity.inode + 1))
            self.assertTrue(root.close_area(failure.exception.original_area))
            (path / 'alias').symlink_to(path / 'saved-area', target_is_directory=True)
            with self.assertRaises(LocalAreaAcquisitionError) as failure:
                root.restore_area('alias', identity)
            self.assertTrue(root.close_area(failure.exception.original_area))
            area = root.restore_area('saved-area', identity)
            with self.assertRaises(LocalFileError):
                root.restore_area('saved-area', identity)
            with self.assertRaises(ValueError):
                root.close_area(copy.copy(area))
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())
            self.assertEqual((path / 'saved-area' / 'saved-payload').read_bytes(), body)

    def test_recorded_generation_refuses_before_bytes_and_wrong_digest_never_observes_complete(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)
            identity, expected, _ = self.fixture(path)
            root = LocalFileRoot(path, max_files=3, max_chunk_bytes=4)
            area = root.restore_area('saved-area', identity)
            child = area.directory
            wrong = PhysicalFileSnapshot(PhysicalFileObservation(
                PhysicalFileIdentity(expected.observation.identity.device,
                                     expected.observation.identity.inode + 1),
                expected.observation.size), expected.physical_digest)
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('foreign read')):
                with self.assertRaises(LocalOriginalAcquisitionError) as failure:
                    child.open_saved_payload('saved-payload', wrong)
            self.assertTrue(child.close_original(failure.exception.original_reader))
            wrong = PhysicalFileSnapshot(expected.observation, 'sha256:' + '0' * 64)
            reader = child.open_saved_payload('saved-payload', wrong)
            self.consume(child, reader)
            with self.assertRaises(LocalFileError):
                child.observe_original(reader)
            with self.assertRaises(LocalFileError):
                child.read_original(reader)
            self.assertTrue(child.close_original(reader))
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())

    def test_mutation_and_uncertain_close_keep_same_descriptor_and_parent_busy(self):
        with TemporaryDirectory() as directory:
            path = Path(directory)
            identity, expected, _ = self.fixture(path)
            root = LocalFileRoot(path, max_files=3, max_chunk_bytes=4)
            area = root.restore_area('saved-area', identity)
            child = area.directory
            reader = child.open_saved_payload('saved-payload', expected)
            chunk = child.read_original(reader)
            (path / 'saved-area' / 'saved-payload').write_bytes(b'[{"n":2}]')
            with self.assertRaises(LocalFileError):
                child.release_original_chunk(reader, chunk)
            descriptor = reader.descriptor
            with patch('actql_sdk._local_files.os.close', side_effect=OSError('unconfirmed')):
                self.assertFalse(child.close_original(reader))
            self.assertFalse(root.close_area(area))
            self.assertIs(child._original_readers[id(reader)], reader)
            self.assertFalse(child.close_original(reader))
            os.close(descriptor)
            self.assertTrue(child.close_original(reader))
            self.assertTrue(root.close_area(area))
            self.assertTrue(root.close())


if __name__ == '__main__':
    unittest.main()
