"""Explicit compiler cleanup composition; scalar Native owners, no Engine/image."""
import unittest
from unittest.mock import patch
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import test_local_compiler_process as process_tests
import test_local_compiler_parent as parent_tests
import python_compiler_program as program
from actql_sdk._local_distribution import LocalInstallationError

compiler = parent_tests.compiler


class FailedCompilerCleanupTests(unittest.TestCase):
    def setUp(self):
        self.original = process_tests.CompilerProcessTests()
        self.original.setUp()
        self.addCleanup(self.original.doCleanups)
        self.transport, self.writer = self.original.failed_response()
        self.parent = self.original.parent
        held = self.parent.original.holding
        selected = program._CompilerProgram(held.source_sha, held.module_sha256,
            '0' * 64, held.engine_sha256, self.original.root,
            ('unused selected executable; never launched by cleanup', 1, '0' * 64), ())
        self.failure = compiler.CompilerProcessAssemblyError(object(), selected)
        self.failure.cleanup_parent = self.parent
        self.failure.cleanup_runtime = self.parent.runtime
        self.failure.cleanup_descriptor = self.parent.descriptor
        self.failure.primary = self.transport

    def test_descriptor_closes_only_after_same_native_parent_and_failure_stays_unaccepted(self):
        result = compiler.finish_failed_compilation(self.failure, seconds=1)
        self.assertTrue(self.parent._closed)
        self.assertTrue(self.parent.descriptor.closed)
        self.assertIs(self.failure.primary, self.transport)
        self.assertIsInstance(self.transport.primary_error, TimeoutError)
        self.assertIs(result['image_accepted'], False)
        self.assertIs(result['physical_acceptance'], False)
        self.assertIs(result['process_runtime_retirement_ACK'], False)
        self.assertIsNone(result['normal_profile'])
        self.assertEqual(result['source_sha'], self.parent.original.holding.source_sha)
        self.assertEqual(self.original.native.events.count(('operate', 11)), 1)
        self.assertEqual(self.writer.call_count, 1)

    def test_lost_descriptor_close_keeps_original_carrier_and_never_repeats_close(self):
        fd = self.parent.descriptor.value
        # Scalar-only Native fixture: the close fault below does not execute a
        # physical close. This test still cleans its own ordinary temporary FD.
        actual_close = os.close
        try:
            with patch.object(os, 'close', side_effect=OSError('independent close response loss')) as closed:
                with self.assertRaises(compiler.CompilerProcessAssemblyError) as caught:
                    compiler.finish_failed_compilation(self.failure, seconds=1)
                self.assertIs(caught.exception, self.failure)
                self.assertTrue(self.parent._closed)
                self.assertFalse(self.parent.descriptor.closed)
                self.assertTrue(self.parent.descriptor.close_attempted)
                with self.assertRaises(compiler.CompilerProcessAssemblyError):
                    compiler.finish_failed_compilation(self.failure, seconds=1)
                self.assertEqual(closed.call_count, 1)
                self.assertEqual(self.original.native.events.count(('operate', 12)), 1)
                self.assertEqual(self.original.native.events.count(('operate', 8)), 1)
        finally:
            actual_close(fd)
            self.parent.descriptor.closed = True  # Test-only fault did not consume that FD.

    def test_foreign_runtime_program_or_descriptor_and_invalid_budget_do_not_touch_native(self):
        before = list(self.original.native.events)
        for seconds in (True, 0, float('nan'), float('inf')):
            with self.subTest(seconds=seconds), self.assertRaises(ValueError):
                compiler.finish_failed_compilation(self.failure, seconds=seconds)
        runtime = self.failure.cleanup_runtime
        self.failure.cleanup_runtime = object()
        with self.assertRaises(ValueError): compiler.finish_failed_compilation(self.failure, seconds=1)
        self.failure.cleanup_runtime = runtime
        selected = self.failure.program
        self.failure.program = selected._replace(source='f' * 40)
        with self.assertRaises(ValueError): compiler.finish_failed_compilation(self.failure, seconds=1)
        self.failure.program = selected
        self.assertEqual(self.original.native.events, before)
        self.assertFalse(self.parent.descriptor.close_attempted)
        self.assertFalse(self.parent._closed)

    def test_partial_parent_acquisition_is_not_a_failed_child_cleanup_fallback(self):
        self.failure.primary = compiler.CompilerParentAcquisitionError(self.parent)
        before = list(self.original.native.events)
        with self.assertRaises(compiler.CompilerProcessAssemblyError):
            compiler.finish_failed_compilation(self.failure, seconds=1)
        self.assertEqual(self.original.native.events, before)
        self.assertFalse(self.parent.descriptor.close_attempted)

    def test_bad_report_after_same_native_cleanup_only_finishes_original_descriptor(self):
        import python_compiler_process as transport
        transport.finish_original_compiler_after_stop_request(self.transport, timeout=1)
        self.failure.primary = ValueError('Original child report was unavailable')
        self.failure.transport_returned = True
        before = list(self.original.native.events)
        result = compiler.finish_failed_compilation(self.failure, seconds=1)
        self.assertEqual(self.original.native.events, before)
        self.assertFalse(result['request_relayed'])
        self.assertFalse(result['image_accepted'])
        self.assertTrue(self.parent.descriptor.closed)

    def test_transport_return_flag_alone_cannot_substitute_for_native_retirement(self):
        self.failure.primary = ValueError('Unaccepted child report')
        self.failure.transport_returned = True
        before = list(self.original.native.events)
        with self.assertRaises(compiler.CompilerProcessAssemblyError):
            compiler.finish_failed_compilation(self.failure, seconds=1)
        self.assertEqual(self.original.native.events, before)
        self.assertFalse(self.parent.descriptor.close_attempted)
        self.assertFalse(self.parent._closed)

    def test_failed_response_is_retained_verbatim_without_admitting_a_report(self):
        self.failure.program = self.failure.program._replace(directory=self.original.root / 'program')
        self.failure.response = b'{"compilation_status":11,"untrusted":"original"}\n'
        original_response = self.failure.response
        primary = self.failure.primary
        result = compiler._finish_failed_compiler_with_diagnostics(self.failure, seconds=1)
        self.assertEqual((self.original.root / 'compiler-failure-response.bin').read_bytes(),
                         original_response)
        self.assertIs(self.failure.primary, primary)
        self.assertIsNone(self.failure.diagnostic_error)
        self.assertFalse(result['image_accepted'])
        self.assertFalse(result['process_runtime_retirement_ACK'])
        self.assertTrue(self.parent.descriptor.closed)
        with self.assertRaises((ValueError, LocalInstallationError)):
            compiler._compiler_process_report(original_response, 4096)

    def test_diagnostic_collision_keeps_original_bytes_and_still_cleans_original(self):
        self.failure.program = self.failure.program._replace(directory=self.original.root / 'program')
        target = self.original.root / 'compiler-failure-response.bin'
        target.write_bytes(b'previous diagnostic; never overwrite')
        self.failure.response = b'new refused report'
        primary = self.failure.primary
        result = compiler._finish_failed_compiler_with_diagnostics(self.failure, seconds=1)
        self.assertEqual(target.read_bytes(), b'previous diagnostic; never overwrite')
        self.assertIsInstance(self.failure.diagnostic_error, FileExistsError)
        self.assertIs(self.failure.primary, primary)
        self.assertTrue(self.parent.descriptor.closed)
        self.assertFalse(result['image_accepted'])

    def test_overbound_diagnostic_is_not_written_or_used_to_skip_original_cleanup(self):
        self.failure.program = self.failure.program._replace(directory=self.original.root / 'program')
        self.failure.response = b'x' * 4098
        result = compiler._finish_failed_compiler_with_diagnostics(self.failure, seconds=1)
        self.assertFalse((self.original.root / 'compiler-failure-response.bin').exists())
        self.assertIsInstance(self.failure.diagnostic_error, ValueError)
        self.assertTrue(self.parent.descriptor.closed)
        self.assertFalse(result['image_accepted'])


class CompilerCleanupCliTests(unittest.TestCase):
    def test_invalid_cleanup_window_refuses_before_module_output_or_native_preparation(self):
        script = Path(__file__).resolve().parents[3] / 'scripts/compile-python-local-image.py'
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / 'unused-output'
            for value in ('0', '-1', 'nan', 'inf'):
                with self.subTest(value=value):
                    result = subprocess.run([sys.executable, '-I', '-B', str(script),
                        '--source', 'a' * 40, '--core-receipt', str(output / 'absent.json'),
                        '--destination', str(output), '--compile', '--cleanup-seconds', value],
                        capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn('finite positive failed-child cleanup window', result.stderr)
                    self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
