"""Actual POSIX project inputs with an explicit Core workspace port."""
import copy
import errno
import importlib
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCore


class LocalProjectFileTests(unittest.TestCase):
    def port(self):
        core = LocalCore.__new__(LocalCore)
        core._lock, core._identity = RLock(), object()
        core._inputs, core._loans, core._released = {}, {}, set()
        core._next_ticket, core._closing, core._closed = 1, False, False
        calls = []

        def call(family, name, *args):
            calls.append((family, name, args))
            if (family, name) == ('workspace', 'reserve'):
                self.assertGreater(args[1], 1024)
                return 19
            if (family, name) == ('workspace', 'close'):
                return 0 if core._cleanup(1) == 0 else -9
            raise AssertionError('Project files cannot issue authority or a Run')
        core._call = call
        module = importlib.import_module('actql_sdk._local_project_files')
        return module, core, calls

    def test_discovery_retains_exact_original_and_nearer_absence(self):
        module, core, calls = self.port()
        with TemporaryDirectory(prefix='actql-project-files-') as temporary:
            root = Path(temporary)
            child = root / 'ordinary-project'
            child.mkdir(mode=0o755)
            original = b'{"version":"actql-config/0.1"}\r\n'
            (root / 'actql.config.json').write_bytes(original)
            files = module.OriginalLocalProjectFiles(core, max_files=8, max_bytes=4096)
            selected = files.discover(child)
            self.assertEqual(files.original_bytes(selected), original)
            self.assertEqual(selected.path, root / 'actql.config.json')
            self.assertEqual(calls[0][:2], ('workspace', 'reserve'))
            self.assertEqual(len(core._loans), 1)
            (child / 'actql.config.json').write_bytes(b'changed-nearer')
            with self.assertRaisesRegex(ValueError, 'absence changed'):
                files.original_bytes(selected)
            self.assertTrue(files.close())
            self.assertEqual((root / 'actql.config.json').read_bytes(), original)
            self.assertEqual(core._loans, {})

    def test_changed_generation_and_failed_close_never_reopen_or_reclose(self):
        module, core, calls = self.port()
        with TemporaryDirectory(prefix='actql-project-files-') as temporary:
            root = Path(temporary)
            path = root / '日本語.json'
            path.write_bytes(b'old')
            files = module.OriginalLocalProjectFiles(core, max_files=4, max_bytes=128)
            selected = files.read_original(path, max_bytes=128)
            descriptor = selected._descriptor
            path.rename(root / 'retained-original')
            path.write_bytes(b'foreign')
            with self.assertRaisesRegex(ValueError, 'generation changed'):
                files.original_bytes(selected)
            actual_close = os.close

            def lose_close_ack(fd):
                actual_close(fd)
                raise OSError(errno.EINTR, 'lost close acknowledgment')

            with patch.object(module.os, 'close', side_effect=lose_close_ack) as closes:
                self.assertFalse(files.close())
                self.assertEqual(closes.call_count, 1)
            with patch.object(module.os, 'open', side_effect=AssertionError('cleanup reopened')):
                self.assertTrue(files.close())
            self.assertEqual(descriptor.fd, None)
            self.assertEqual((root / 'retained-original').read_bytes(), b'old')
            self.assertEqual(path.read_bytes(), b'foreign')
            self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)

    def test_bound_and_nonregular_inputs_refuse_without_fallback_or_second_read(self):
        module, core, calls = self.port()
        with TemporaryDirectory(prefix='actql-project-files-') as temporary:
            root = Path(temporary)
            (root / 'large').write_bytes(b'12345')
            files = module.OriginalLocalProjectFiles(core, max_files=4, max_bytes=128)
            with self.assertRaises(module.LocalProjectFilesCleanupPending) as caught:
                files.read_original(root / 'large', max_bytes=4)
            self.assertIs(caught.exception.cleanup_files, files)
            with patch.object(module.os, 'open', side_effect=AssertionError('failed input was reopened')):
                with self.assertRaises(ValueError):
                    files.read_original(root / 'large', max_bytes=8)
            self.assertTrue(files.close())
            self.assertEqual((root / 'large').read_bytes(), b'12345')
            os.mkfifo(root / 'actql.config.json')
            module, core, calls = self.port()
            files = module.OriginalLocalProjectFiles(core, max_files=4, max_bytes=128)
            with self.assertRaises(module.LocalProjectFilesCleanupPending) as caught:
                files.discover(root)
            self.assertIsInstance(caught.exception.__cause__, ValueError)
            self.assertEqual(len(files._attempts), 1)
            self.assertTrue(files.close())

    def test_precharged_workspace_and_failed_observation_keep_original_custody(self):
        module, core, calls = self.port()
        with TemporaryDirectory(prefix='actql-project-files-') as temporary:
            root = Path(temporary)
            path = root / 'original'
            path.write_bytes(b'\x00\xff\r\n')
            files = module.OriginalLocalProjectFiles(core, max_files=4, max_bytes=128)
            self.assertEqual(calls[0][:2], ('workspace', 'reserve'))
            original_fstat = module.os.fstat
            seen = []

            def observe(fd):
                seen.append(fd)
                if len(seen) == 2:
                    raise OSError('original file observation failed')
                return original_fstat(fd)

            with patch.object(module.os, 'fstat', side_effect=observe):
                with self.assertRaises(module.LocalProjectFilesCleanupPending) as caught:
                    files.read_original(path, max_bytes=128)
            self.assertIs(caught.exception.cleanup_files, files)
            self.assertEqual(len([d for d in files._descriptors if d.fd is not None]), 2)
            self.assertTrue(files.close())
            self.assertEqual(path.read_bytes(), b'\x00\xff\r\n')
            self.assertEqual(core._loans, {})

    def test_nominal_originals_and_recycled_descriptor_cleanup_are_not_authority(self):
        module, core, calls = self.port()
        with TemporaryDirectory(prefix='actql-project-files-') as temporary:
            root = Path(temporary)
            path = root / 'original'
            path.write_bytes(b'exact')
            files = module.OriginalLocalProjectFiles(core, max_files=4, max_bytes=128)
            selected = files.read_original(path, max_bytes=128)
            with self.assertRaises(TypeError): copy.copy(files)
            with self.assertRaises(ValueError): files.original_bytes(copy.copy(selected))
            with self.assertRaises(ValueError): files.read_original(path, max_bytes=0)
            fd = selected._descriptor.fd
            selected._descriptor.close_pending = True
            # A still-open fd, even for the same inode, is not proof of the
            # original open-file description after an uncertain close.
            with patch.object(module.os, 'close', side_effect=AssertionError('uncertain fd reclosed')):
                self.assertFalse(files.close())
            self.assertEqual(os.read(fd, 1), b'')
            os.close(fd)
            self.assertTrue(files.close())
            self.assertEqual(path.read_bytes(), b'exact')

    def test_trapped_workspace_retains_ticket_until_same_core_cleanup_ack(self):
        module, core, calls = self.port()
        with patch.object(core, '_call', side_effect=RuntimeError('reserve acknowledgment lost')):
            with patch.object(module.os, 'open', side_effect=AssertionError('unbacked open')):
                with self.assertRaises(module.LocalProjectFilesCleanupPending) as caught:
                    module.OriginalLocalProjectFiles(core, max_files=2, max_bytes=128)
        files = caught.exception.cleanup_files
        self.assertEqual(files._uncertain_ticket, 1)
        self.assertIn(1, core._inputs)
        self.assertFalse(files.close())
        # Explicit Core port: only original global cleanup can establish this
        # acknowledgement; the project child cannot set it or re-reserve.
        self.assertEqual(files._descriptors, [])
        core._closed = True
        with patch.object(core, '_call', side_effect=AssertionError('closed Core reinvoked')):
            self.assertTrue(files.close())


if __name__ == '__main__':
    unittest.main()
