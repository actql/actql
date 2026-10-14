"""Private binding selection and real file fences; no Engine/library execution."""
from unittest.mock import patch
import unittest

from actql_sdk._local_engine import _checked_installed_image_file
from actql_sdk._local_distribution import LocalInstallationError
import test_local_distribution as distribution
import test_local_installed_image as image


class PrivateRuntimeTests(unittest.TestCase):
    def test_original_holding_selects_only_private_binding_and_ffi(self):
        case = image.InstalledImageTests(); case.setUp()
        holding, _ = case._holding([(0, True)])
        original = case.runtime; imports = []
        def runtime(name):
            imports.append(name)
            return original(name)
        case.runtime = runtime
        core, _ = case._construct_with_baseline(holding=holding)
        self.assertEqual(imports, ['actql_local_runtime._wasmtime',
                                  'actql_local_runtime._wasmtime._ffi'])
        self.assertTrue(core.close())

    def test_missing_private_binding_never_imports_stock_or_constructs_engine(self):
        case = image.InstalledImageTests(); case.setUp()
        holding, _ = case._holding([(0, True)])
        imports = []
        def runtime(name):
            imports.append(name)
            raise ImportError('Independent missing private binding')
        case.runtime = runtime
        with self.assertRaisesRegex(RuntimeError, 'Wasmtime'):
            case._construct_with_baseline(holding=holding)
        self.assertEqual(imports, ['actql_local_runtime._wasmtime'])
        self.assertEqual(case.events, [('retire', 123)])
        self.assertIsNone(holding._pointer.value)

    def test_stock_library_cannot_replace_missing_private_component(self):
        case = distribution.LocalDistributionTests(); case.setUp()
        self.addCleanup(case.doCleanups)
        components = case.inspect()
        stock = case.directory / 'darwin-aarch64/_libwasmtime.dylib'
        stock.parent.mkdir(); stock.write_bytes(b'independent runtime library fixture')
        with patch('actql_sdk._local_engine.metadata.version', return_value=components.package_version), \
                patch('actql_sdk._local_engine.resources.files', side_effect=AssertionError('Stock fallback')):
            with self.assertRaises(FileNotFoundError): _checked_installed_image_file(components)

    def test_private_library_requires_exact_cohort_and_original_digest(self):
        case = distribution.LocalDistributionTests(); case.setUp()
        self.addCleanup(case.doCleanups)
        components = case.inspect()
        native = case.directory / '_wasmtime/darwin-aarch64/_libwasmtime.dylib'
        native.parent.mkdir(parents=True); native.write_bytes(b'independent runtime library fixture')
        with patch('actql_sdk._local_engine.metadata.version', return_value='foreign-cohort'):
            with self.assertRaisesRegex(LocalInstallationError, 'cohort mismatch'):
                _checked_installed_image_file(components)
        with patch('actql_sdk._local_engine.metadata.version', return_value=components.package_version), \
                patch('actql_sdk._local_engine.resources.files', side_effect=AssertionError('Import before holding')):
            selected = _checked_installed_image_file(components)
            self.assertEqual(selected.runtime_library, native)
            native.write_bytes(b'x' * len(b'independent runtime library fixture'))
            with self.assertRaises(LocalInstallationError): _checked_installed_image_file(components)
