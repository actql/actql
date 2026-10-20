"""Actual readonly FD handling, native pointer/status doubles; no Engine execution."""
from ctypes import c_void_p, cast, POINTER, Structure
from dataclasses import replace
import fcntl
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from actql_sdk._local_core import LocalCoreInitializationError
from actql_sdk._local_engine import _InstalledImageFileInput, _checked_installed_image_file
from actql_sdk._local_native_image import NativeImageError
import test_local_installed_image as image_fixture
import test_local_distribution as distribution_fixture


class ModulePointer(Structure):
    pass


class NativeImageTests(unittest.TestCase):
    def setUp(self):
        self.case = image_fixture.InstalledImageTests(); self.case.setUp()
        directory = TemporaryDirectory(); self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / 'client_host_wasm.cwasm'
        self.path.write_bytes(b'original image scalar fixture')
        self.case.image = _InstalledImageFileInput(self.path, 29, 'c' * 64,
            self.case.recipe, Path('/original/runtime.dylib'))
        self.holding, self.library = self.case._holding([(0, True)])
        self.capture_calls = []; self.retire_calls = []; self.deserialize_calls = []
        self.capture_code = 0; self.capture_error = None
        self.retire_codes = []; self.module_failures = 0; self.module_closes = []
        self.deserialize_error = None; self.deserialize_pointer = 777
        self.deserialize_exception = None
        self.captured_fd = None
        self.library.actql_owned_capture_image_fd = self.capture
        self.library.actql_owned_retire = self.retire
        self.case.ffi.wasmtime_module_t = ModulePointer
        self.case.ffi.wasmtime_module_deserialize = self.deserialize
        test = self

        class Module:
            # Preserve the relevant pinned Managed pointer-slot contract.
            def _set_ptr(self, pointer): self.pointer = pointer
            def _consume(self):
                pointer, self.pointer = self.pointer, None
                return pointer
            def close(self):
                pointer = getattr(self, 'pointer', None)
                if pointer is None: return
                test.module_closes.append(cast(pointer, c_void_p).value)
                if test.module_failures:
                    test.module_failures -= 1
                    raise OSError('Original module physical cleanup failure')
                self.pointer = None

        Module.deserialize = Mock(side_effect=AssertionError('Whole-image copy fallback'))
        self.case.wasmtime.Module = Module

    def capture(self, lease, fd, length, maximum, digest, output):
        self.capture_calls.append((lease.value, length, maximum, bytes(digest)))
        self.captured_fd = fd
        self.assertEqual(fcntl.fcntl(fd, fcntl.F_GETFL) & 3, 0)
        cast(output, POINTER(c_void_p))[0] = c_void_p(123456)
        if self.capture_error: raise self.capture_error
        return self.capture_code

    def retire(self, lease, image):
        self.retire_calls.append((lease.value, image.value))
        return self.retire_codes.pop(0) if self.retire_codes else 0

    def deserialize(self, engine, image, length, output):
        self.deserialize_calls.append((engine, cast(image, c_void_p).value, length))
        if self.deserialize_pointer:
            cast(output, POINTER(POINTER(ModulePointer)))[0] = cast(
                c_void_p(self.deserialize_pointer), POINTER(ModulePointer))
        if self.deserialize_exception: raise self.deserialize_exception
        return self.deserialize_error

    def create(self):
        # Native symbols in a fake DLL are plain functions with C signature
        # attributes. They do not load, allocate, hash or deserialize natively.
        self.library.actql_owned_capture_image_fd = lambda *args: self.capture(*args)
        self.library.actql_owned_retire = lambda *args: self.retire(*args)
        return self.case._construct_with_baseline(holding=self.holding)

    def assert_fd_closed(self):
        with self.assertRaises(OSError): fcntl.fcntl(self.captured_fd, fcntl.F_GETFL)

    def test_native_pointer_path_has_no_whole_image_copy_and_retires_same_extent(self):
        core, calls = self.create()
        self.assertEqual(self.capture_calls, [(123, 29, self.case.recipe.image_bytes_limit, b'\xcc' * 32)])
        self.assertEqual(self.deserialize_calls, [(self.case.engine, 123456, 29)])
        self.assertEqual(self.retire_calls, [(123, 123456)])
        self.assertIsNone(core._physical_image)
        self.case.wasmtime.Module.deserialize.assert_not_called()
        self.assert_fd_closed()
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual(self.module_closes, [777])
        self.assertEqual([name for name, _ in calls], ['open', 'close'])

    def test_capture_failure_retains_original_extent_until_same_core_cleanup_retry(self):
        self.capture_code = -5; self.retire_codes = [-2, 0]
        with self.assertRaises(LocalCoreInitializationError) as failure: self.create()
        core = failure.exception.cleanup_core
        self.assertIsInstance(failure.exception.__cause__, NativeImageError)
        self.assertEqual(core._physical_image._pointer.value, 123456)
        self.assertIs(core._physical_image._lease, self.holding)
        self.assertIs(core._store, self.case.store)
        self.assertFalse(core._closed)
        self.assertEqual(self.deserialize_calls, [])
        self.assert_fd_closed()
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual(len(self.capture_calls), 1)
        self.assertEqual(self.retire_calls, [(123, 123456), (123, 123456)])

    def test_capture_exception_keeps_published_cleanup_pointer_and_original_error(self):
        original = OSError('Original native capture outcome unknown')
        self.capture_error = original; self.retire_codes = [-2, 0]
        with self.assertRaises(LocalCoreInitializationError) as failure: self.create()
        core = failure.exception.cleanup_core
        self.assertIs(failure.exception.__cause__, original)
        self.assertEqual(core._physical_image._pointer.value, 123456)
        self.assertTrue(core.close())
        self.assertEqual(len(self.capture_calls), 1)
        self.assertEqual(self.deserialize_calls, [])

    def test_deserializer_exception_retains_module_output_before_scope_exit(self):
        original = OSError('Original native deserialization outcome unknown')
        self.deserialize_exception = original; self.module_failures = 1
        with self.assertRaises(LocalCoreInitializationError) as failure: self.create()
        core = failure.exception.cleanup_core
        self.assertIs(failure.exception.__cause__, original)
        self.assertEqual(cast(core._module.pointer, c_void_p).value, 777)
        self.assertIs(core._store, self.case.store)
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual(self.module_closes, [777, 777])
        self.assertEqual(len(self.deserialize_calls), 1)

    def test_null_module_on_error_is_not_deleted_or_replaced_with_jit(self):
        self.deserialize_pointer = None; self.deserialize_error = object()
        with self.assertRaisesRegex(RuntimeError, 'target rejected'): self.create()
        self.assertEqual(self.module_closes, [])
        self.assertEqual(len(self.deserialize_calls), 1)
        self.case.wasmtime.Module.deserialize.assert_not_called()
        self.assertEqual(self.retire_calls, [(123, 123456)])

    def test_missing_holding_refuses_native_file_input_before_engine_import(self):
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Native import')):
            with self.assertRaisesRegex(ValueError, 'artifact or capacity'):
                self.case.create()
        self.assertEqual(self.capture_calls, [])

    def test_symlink_capture_refuses_before_native_call_and_releases_same_holding(self):
        alias = self.path.with_name('alias.cwasm'); alias.symlink_to(self.path)
        self.case.image = replace(self.case.image, path=alias)
        with self.assertRaises(OSError): self.create()
        self.assertEqual(self.capture_calls, [])
        self.assertEqual(self.deserialize_calls, [])
        self.assertIsNone(self.holding._pointer.value)

    def test_installed_descriptor_reuses_manifest_without_capturing_image(self):
        case = distribution_fixture.LocalDistributionTests(); case.setUp()
        self.addCleanup(case.doCleanups)
        components = case.inspect()
        library = case.directory / '_wasmtime/darwin-aarch64/_libwasmtime.dylib'
        library.parent.mkdir(parents=True); library.write_bytes(b'independent runtime library fixture')
        from image_fixture import PROVIDER
        (library.parent / 'libactql_native_control.dylib').write_bytes(PROVIDER)
        with patch('actql_sdk._local_engine.metadata.version', return_value=components.package_version), \
                patch('actql_sdk._local_engine.metadata.distribution', side_effect=AssertionError('Stock dependency discovery')), \
                patch('actql_sdk._local_engine._load_selected_image', side_effect=AssertionError('Capture')):
            image = _checked_installed_image_file(components)
            self.assertEqual((image.path, image.length, image.sha256),
                             (components.image, components.image_bytes, components.image_sha256))
            self.assertFalse(hasattr(image, 'encoded'))
            with self.assertRaisesRegex(RuntimeError, 'descriptor mismatch'):
                _checked_installed_image_file(replace(components, image_bytes=1))
