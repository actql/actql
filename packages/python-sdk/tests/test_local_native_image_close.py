"""Owned real FDs with injected close errors; Native/Core/Engine status doubles."""
import errno
import os
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreInitializationError
from actql_sdk._local_native_image import NativeImageError
import test_local_native_image as image_fixture


class NativeImageCloseTests(unittest.TestCase):
    def setUp(self):
        self.image = image_fixture.NativeImageTests()
        self.image.setUp()
        self.addCleanup(self.image.doCleanups)
        self.real_close = os.close

    def construct_failure(self, close):
        failure = None
        with patch('actql_sdk._local_native_image.os.close', side_effect=close) as attempt:
            try:
                self.image.create()
            except Exception as observed:
                failure = observed
            self.assertIsInstance(failure, LocalCoreInitializationError,
                'Unconfirmed original FD close must retain the same cleanup Core')
            core = failure.cleanup_core
            child = core._physical_image
            self.assertIs(child._lease, self.image.holding)
            self.assertIs(core._physical_holding, self.image.holding)
            self.assertIs(core._store, self.image.case.store)
            self.assertEqual(child._pointer.value, 123456)
            self.assertFalse(core._closed)
            original = child._fd_close_failure
            self.assertIsInstance(original, NativeImageError)
            self.assertEqual(original.operation, 'close_fd')
            for _ in range(3):
                with self.assertRaises(NativeImageError) as retry:
                    core.close()
                self.assertIs(retry.exception, original)
                self.assertIs(core._physical_image, child)
                self.assertIs(core._physical_holding, self.image.holding)
            self.assertEqual(attempt.call_count, 1)
            self.assertEqual(self.image.retire_calls, [])
            self.assertEqual(self.image.deserialize_calls, [])
            self.assertFalse(any(event[0] in ('close', 'retire')
                for event in self.image.case.events))
            self.assertEqual(self.image.holding._pointer.value, 123)
            return failure, core, original

    def test_unknown_close_retains_original_fd_and_blocks_parent_release(self):
        original = OSError(errno.EIO, 'injected original FD close failure')
        def close(fd):
            self.assertEqual(fd, self.image.captured_fd)
            raise original
        try:
            failure, core, pending = self.construct_failure(close)
            self.assertIs(failure.__cause__, pending)
            self.assertIs(pending.__cause__, original)
            self.assertEqual(core._physical_image._fd, self.image.captured_fd)
            # The fixture deliberately left this owned FD open. This observation
            # is not an ACK and does not permit product close by descriptor again.
            os.fstat(self.image.captured_fd)
        finally:
            self.real_close(self.image.captured_fd)

    def test_consumed_close_error_never_recloses_reused_descriptor(self):
        replacement = self.image.path.with_name('owned-replacement.txt')
        replacement.write_bytes(b'')
        reused = []
        def close(fd):
            self.real_close(fd)
            reused.append(os.open(replacement, os.O_WRONLY))
            self.assertEqual(reused[0], fd)
            raise OSError(errno.EIO, 'injected error after original close consumed FD')
        try:
            _, core, pending = self.construct_failure(close)
            # Patch is gone. Sticky Unknown must still avoid a second close,
            # despite the descriptor number now naming a different owned file.
            with self.assertRaises(NativeImageError) as retry:
                core.close()
            self.assertIs(retry.exception, pending)
            os.write(reused[0], b'original replacement remains writable')
            self.assertEqual(replacement.read_bytes(), b'original replacement remains writable')
        finally:
            for fd in reused:
                self.real_close(fd)

    def test_capture_failure_remains_primary_when_fd_close_is_also_unknown(self):
        primary = OSError('original capture result unavailable')
        self.image.capture_error = primary
        close_failure = OSError(errno.EINTR, 'injected close outcome unknown')
        def close(fd):
            raise close_failure
        try:
            failure, _, pending = self.construct_failure(close)
            self.assertIs(failure.__cause__, primary)
            self.assertIs(pending.__cause__, close_failure)
            self.assertEqual(len(self.image.capture_calls), 1)
        finally:
            self.real_close(self.image.captured_fd)


if __name__ == '__main__':
    unittest.main()
