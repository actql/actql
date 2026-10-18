"""Original compiler transport fault counters, not Engine/image acceptance."""
import hashlib
from contextlib import ExitStack
from pathlib import Path
import unittest
from unittest.mock import patch

import python_compiler_process as transport
from test_local_compiler_parent import CompilerParentTests
from test_local_native_domain_custody import DomainFixture
from test_local_native_domain_material import _OriginalDomainMaterial
from test_local_native_process_custody import ProcessFixture
from test_local_native_control_custody import Function
from actql_sdk._local_distribution import LocalInstallationError


class CompilerProcessTests(unittest.TestCase):
    def setUp(self):
        self.parent_case = CompilerParentTests()
        self.parent_case.setUp()
        self.addCleanup(self.parent_case.doCleanups)
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.domain_fixture = DomainFixture()
        self.parent = self.parent_case.acquire(self.domain_fixture)
        self.native = ProcessFixture(original=self.domain_fixture, domain=self.parent.domain)
        self.root = self.parent_case.fixture.case.root.resolve()
        self.executable = self.root / 'original-compiler'
        self.executable.write_bytes(b'independent executable byte correspondence fixture')
        self.executable.chmod(0o700)
        self.material = _OriginalDomainMaterial(self.parent.original.holding.source_sha,
            self.parent.original.recipe, tuple(range(15)))

    def invoke(self, **changes):
        arguments = dict(executable=self.executable, executable_bytes=self.executable.stat().st_size,
            executable_sha256=hashlib.sha256(self.executable.read_bytes()).hexdigest(),
            module=self.root / 'module.wasm', destination=self.root / 'image.cwasm',
            slot=str(self.root / 'process.slot'), nonce=7, timeout=1)
        arguments.update(changes)
        return transport.invoke_original_compiler(self.parent, **arguments)

    def io(self, response=b'not an image receipt\n'):
        selected = self.stack.enter_context(patch.object(transport.select, 'select',
            side_effect=lambda readers, *args: (readers, [], [])))
        writer = self.stack.enter_context(patch.object(transport.os, 'write', side_effect=lambda fd, data:
            self.native.events.append(('write', fd, data)) or len(data)))
        self.stack.enter_context(patch.object(transport.os, 'read', side_effect=[response, b'']))
        self.stack.enter_context(patch.object(type(self.parent.domain), '_project_original_material',
            return_value=self.material))
        # The helper constructs the normal same-library bindings before calling
        # the projection. These two unused FFI doubles complete that ABI only.
        library = self.parent.library
        library.actql_domain_project_into = Function(lambda *args: 0)
        library.actql_domain_copy_material = Function(lambda *args: 0)
        return selected, writer

    def test_same_original_arguments_binding_and_separate_stop_retirement(self):
        _, writer = self.io()
        raw = self.invoke()
        self.assertEqual(raw, b'not an image receipt\n')
        args = next(e[1] for e in self.native.events if e[0] == 'child').split(b'\0')[:-1]
        self.assertEqual(args, [self.material.recipe.hex().encode(),
            *(str(n).encode() for n in self.material.scalars),
            str(self.root / 'module.wasm').encode(), str(self.root / 'image.cwasm').encode()])
        events = self.native.events
        self.assertLess(events.index(('operate', 11)), events.index(('write', 21, b'R')))
        self.assertLess(events.index(('operate', 2)), events.index(('write', 21, b'R')))
        self.assertLess(events.index(('operate', 5)), events.index(('operate', 6)))
        self.assertLess(events.index(('operate', 6)), events.index(('operate', 8)))
        self.assertEqual(writer.call_count, 1)
        self.assertTrue(self.parent._closed)
        self.assertFalse(self.parent.descriptor.close_attempted)
        self.assertTrue(self.parent.runtime._initialized)

    def test_lost_spawn_keeps_same_native_unknown_and_never_signals_child(self):
        _, writer = self.io()
        original = self.native.operate
        def lost(*args):
            result = original(*args)
            if args[-2] == 11:
                raise OSError('lost original spawn reply')
            return result
        self.parent.library.actql_process_operate_into = Function(lost)
        with self.assertRaises(transport.CompilerChildProcessError) as caught:
            self.invoke()
        process = caught.exception.cleanup_process
        self.assertIs(process, self.parent.domain._installed_process_original)
        self.assertIsNotNone(process._unknown)
        self.assertFalse(self.parent._closed)
        writer.assert_not_called()
        self.assertNotIn(('operate', 8), self.native.events)

    def test_response_timeout_keeps_parent_endpoints_and_does_not_resend(self):
        selected, writer = self.io()
        selected.return_value = ([], [], [])
        selected.side_effect = None
        with self.assertRaises(transport.CompilerChildProcessError) as caught:
            self.invoke()
        self.assertIsInstance(caught.exception.__cause__, TimeoutError)
        self.assertEqual(writer.call_count, 1)
        self.assertEqual(self.native.events.count(('operate', 11)), 1)
        self.assertNotIn(('operate', 4), self.native.events)
        self.assertFalse(self.parent._closed)
        self.assertIs(caught.exception.cleanup_process, self.parent.domain._installed_process_original)

    def failed_response(self):
        selected, writer = self.io()
        selected.return_value = ([], [], [])
        selected.side_effect = None
        with self.assertRaises(transport.CompilerChildProcessError) as caught:
            self.invoke()
        self.assertIsInstance(caught.exception.primary_error, TimeoutError)
        return caught.exception, writer

    def test_explicit_stop_cleanup_preserves_primary_and_never_relaunches_or_closes_caller_fd(self):
        failure, writer = self.failed_response()
        primary = failure.primary_error
        self.assertNotIn(('operate', 12), self.native.events)
        self.assertTrue(transport.finish_original_compiler_after_stop_request(failure, timeout=1))
        self.assertIs(failure.primary_error, primary)
        self.assertEqual(writer.call_count, 1)
        self.assertEqual(self.native.events.count(('operate', 11)), 1)
        for operation in (12, 4, 5, 6, 8):
            self.assertEqual(self.native.events.count(('operate', operation)), 1)
        self.assertTrue(self.parent._closed)
        self.assertFalse(self.parent.descriptor.close_attempted)
        self.assertTrue(self.parent.runtime._initialized)
        before = list(self.native.events)
        self.assertFalse(transport.finish_original_compiler_after_stop_request(failure, timeout=1))
        self.assertEqual(self.native.events, before)

    def test_false_stop_request_still_needs_original_typed_stop_and_region_cleanup(self):
        failure, _ = self.failed_response()
        self.native.stop_request_status = 0
        self.assertFalse(transport.finish_original_compiler_after_stop_request(failure, timeout=1))
        self.assertIn(('operate', 6), self.native.events)
        self.assertIn(('operate', 8), self.native.events)
        self.assertTrue(self.parent._closed)
        self.assertFalse(self.parent.descriptor.close_attempted)

    def test_lost_stop_request_keeps_same_failure_unknown_and_does_not_resend(self):
        failure, _ = self.failed_response()
        self.native.call_fault = OSError('Independent stop request reply loss')
        with self.assertRaises(transport.CompilerChildProcessError) as caught:
            transport.finish_original_compiler_after_stop_request(failure, timeout=1)
        self.assertIs(caught.exception, failure)
        self.assertIsNotNone(failure.cleanup_error)
        self.assertIsInstance(failure.primary_error, TimeoutError)
        before = list(self.native.events)
        with self.assertRaises(transport.CompilerChildProcessError):
            transport.finish_original_compiler_after_stop_request(failure, timeout=1)
        self.assertEqual(self.native.events, before)
        self.assertFalse(self.parent._closed)
        self.assertIs(self.parent.domain._installed_process_original, failure.cleanup_process)
        self.assertNotIn(('operate', 8), before)

    def test_request_success_without_typed_stop_keeps_original_region_and_primary(self):
        failure, _ = self.failed_response()
        failure.cleanup_process._functions.facts = Function(
            lambda r, h, d, p, values: values.__setitem__(slice(None), (21, 22, 23, 1)) or 0)
        with patch.object(transport.time, 'monotonic', side_effect=[0, 2]):
            with self.assertRaises(transport.CompilerChildProcessError) as caught:
                transport.finish_original_compiler_after_stop_request(failure, timeout=1)
        self.assertIs(caught.exception, failure)
        self.assertIsInstance(failure.cleanup_error, TimeoutError)
        self.assertFalse(self.parent._closed)
        self.assertNotIn(('operate', 8), self.native.events)
        self.assertFalse(self.parent.descriptor.close_attempted)

    def test_lost_retirement_with_empty_slots_cannot_be_retried_as_released(self):
        failure, _ = self.failed_response()
        self.native.finish_fault = OSError('Independent original retirement reply loss')
        with self.assertRaises(transport.CompilerChildProcessError):
            transport.finish_original_compiler_after_stop_request(failure, timeout=1)
        process = failure.cleanup_process
        self.assertTrue(all(slot.value is None for slot in process._slots()))
        self.assertFalse(process._closed)
        self.assertIsNotNone(process._unknown)
        before = list(self.native.events)
        with self.assertRaises(transport.CompilerChildProcessError):
            transport.finish_original_compiler_after_stop_request(failure, timeout=1)
        self.assertEqual(self.native.events, before)
        self.assertFalse(self.parent._closed)
        self.assertFalse(self.parent.descriptor.close_attempted)

    def test_parent_only_partial_cleanup_does_not_repeat_original_child_stop_or_retirement(self):
        failure, _ = self.failed_response()
        with patch.object(self.parent, 'close_unstarted', side_effect=ValueError('known caller refusal')):
            with self.assertRaises(transport.CompilerChildProcessError):
                transport.finish_original_compiler_after_stop_request(failure, timeout=1)
        self.assertTrue(failure.cleanup_process._closed)
        self.assertFalse(self.parent._closed)
        before = list(self.native.events)
        self.assertFalse(transport.finish_original_compiler_after_stop_request(failure, timeout=1))
        self.assertTrue(self.parent._closed)
        self.assertEqual(self.native.events, before)
        self.assertFalse(self.parent.descriptor.close_attempted)

    def test_foreign_failure_process_and_invalid_cleanup_budget_refuse_before_native(self):
        failure, _ = self.failed_response()
        before = list(self.native.events)
        for value in (True, 0, float('nan'), float('inf')):
            with self.subTest(value=value), self.assertRaises(ValueError):
                transport.finish_original_compiler_after_stop_request(failure, timeout=value)
        original = failure.cleanup_process
        failure.cleanup_process = object()
        with self.assertRaises(ValueError):
            transport.finish_original_compiler_after_stop_request(failure, timeout=1)
        failure.cleanup_process = original
        self.assertEqual(self.native.events, before)
        self.assertFalse(self.parent._closed)

    def test_eof_without_typed_stop_cannot_retire_region(self):
        self.io()
        self.parent.library.actql_process_copy_facts = Function(
            lambda r, h, d, p, values: values.__setitem__(slice(None), (21, 22, 23, 1)) or 0)
        # Remaining time crosses the deadline only after EOF and one real poll.
        with patch.object(transport.time, 'monotonic', side_effect=[0, 0, 0, 2]):
            with self.assertRaises(transport.CompilerChildProcessError) as caught:
                self.invoke()
        self.assertIsInstance(caught.exception.__cause__, TimeoutError)
        self.assertEqual(bytes(caught.exception.response), b'not an image receipt\n')
        self.assertIn(('operate', 6), self.native.events)
        self.assertNotIn(('operate', 8), self.native.events)
        self.assertFalse(self.parent._closed)

    def test_lost_physical_finish_with_empty_slots_does_not_release_parent(self):
        self.io(); self.native.finish_fault = OSError('lost final process cleanup reply')
        with self.assertRaises(transport.CompilerChildProcessError) as caught:
            self.invoke()
        process = caught.exception.cleanup_process
        self.assertTrue(all(s.value is None for s in process._slots()))
        self.assertIsNotNone(process._unknown)
        self.assertIs(self.parent.domain._installed_process_original, process)
        self.assertFalse(self.parent._closed)
        self.assertFalse(self.parent.descriptor.close_attempted)

    def test_oversized_response_is_not_an_image_or_cleanup_ack(self):
        self.io(response=b'x' * 4097)
        with self.assertRaises(transport.CompilerChildProcessError) as caught:
            self.invoke()
        self.assertEqual(len(caught.exception.response), 4097)
        self.assertNotIn(('operate', 8), self.native.events)
        self.assertFalse(self.parent._closed)

    def test_foreign_material_refuses_before_process_preparation(self):
        self.io(); self.material = _OriginalDomainMaterial('f' * 40, self.material.recipe, self.material.scalars)
        # Replace the original projection return rather than copying its custody.
        with patch.object(type(self.parent.domain), '_project_original_material', return_value=self.material):
            with self.assertRaisesRegex(ValueError, 'differs from its parent'):
                self.invoke()
        self.assertEqual(self.native.events, [])
        self.assertIsNone(self.parent.domain._installed_process_original)

    def test_invalid_budget_output_or_executable_refuses_before_native(self):
        for changes in ({'timeout': True}, {'timeout': float('inf')},
                        {'destination': Path('relative')}, {'executable_sha256': '0' * 64}):
            with self.subTest(changes=changes):
                with self.assertRaises((ValueError, LocalInstallationError)): self.invoke(**changes)
        self.assertEqual(self.native.events, [])
        self.assertIsNone(self.parent.domain._installed_process_original)


if __name__ == '__main__':
    unittest.main()
