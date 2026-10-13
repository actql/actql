"""Original handle/FFI doubles and actual file integrity; no native Engine execution."""
from dataclasses import replace
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from actql_sdk._local_core import LocalCore, LocalCoreResources, LocalCoreInitializationError, LOCAL_CORE_ABI
from actql_sdk._local_distribution import LocalInstallationError
from actql_sdk._local_engine import (_InstalledImageInput, _checked_installed_image,
    _configure_selected_engine, _verify_loaded_runtime)
from actql_sdk._local_image_recipe import _recipe_from_original
from actql_sdk._local_product import InstalledLocalHost
from image_fixture import ORIGINAL, IMAGE, ENGINE
import test_local_distribution as distribution_fixture

RESOURCES = LocalCoreResources(0, 8, 0, 0, 0, 16 * 1024 * 1024 + 65536)


class Handle:
    def __init__(self, name, events, failures=0):
        self.name, self.events, self.failures = name, events, failures
        self.imports = []
    def close(self):
        self.events.append(('close', self.name))
        if self.failures:
            self.failures -= 1
            raise OSError('independent original native cleanup failure')
    def ptr(self): return self
    def set_fuel(self, value): self.events.append(('fuel', value))
    def set_limits(self, **values): self.events.append(('limits', values))


class FFI:
    def __init__(self, events):
        self.events = events; self.pool = object(); self.delete_failures = 0
        self.fail_setting = None
    def wasmtime_pooling_allocation_config_new(self):
        self.events.append(('new_pool', self.pool)); return self.pool
    def wasmtime_pooling_allocation_config_delete(self, value):
        self.events.append(('delete_pool', value))
        if self.delete_failures:
            self.delete_failures -= 1
            raise OSError('independent pool cleanup failure')
    def __getattr__(self, name):
        def setter(*args):
            self.events.append((name, args))
            if name == self.fail_setting: raise RuntimeError('independent config setter failure')
            return None
        return setter


class InstalledImageTests(unittest.TestCase):
    def setUp(self):
        self.recipe = _recipe_from_original(ORIGINAL, source_sha='a' * 40,
            package_version='0.0.0.dev0', module_sha256='b' * 64)
        self.image = _InstalledImageInput(IMAGE, hashlib.sha256(IMAGE).hexdigest(),
                                        self.recipe, Path('/original/runtime.dylib'))
        self.events = []; self.ffi = FFI(self.events)
        self.config = Handle('config', self.events)
        self.engine = Handle('engine', self.events)
        self.store = Handle('store', self.events)
        self.module = Handle('module', self.events)
        self.deserialize = Mock(return_value=self.module)
        self.wasmtime = SimpleNamespace(Config=lambda: self.config,
            Engine=lambda config: self.engine, Store=lambda engine: self.store,
            Module=SimpleNamespace(deserialize=self.deserialize),
            WasmtimeError=SimpleNamespace(_from_ptr=lambda value: RuntimeError('target rejected')))
        self.runtime = lambda name: self.wasmtime if name == 'wasmtime' else self.ffi

    def create(self, **options):
        return LocalCore(None, digest='b' * 64, transfer_capacity=65536,
                         resources=RESOURCES, _compiled_image=self.image, **options)

    def test_exact_config_and_unused_pools_without_new_limits(self):
        _configure_selected_engine(self.config, self.ffi.pool, self.ffi, self.wasmtime, self.recipe)
        self.assertTrue(self.config.consume_fuel)
        self.assertEqual(self.config.strategy, 'cranelift')
        calls = dict(self.events)
        self.assertEqual(calls['wasmtime_config_target_set'][1].value, b'aarch64-apple-darwin')
        for name in ('wasm_gc', 'wasm_component_model', 'async_support'):
            self.assertIs(calls['wasmtime_config_' + name + '_set'][1], False)
        for name in ('total_gc_heaps', 'total_component_instances', 'total_stacks'):
            self.assertEqual(calls['wasmtime_pooling_allocation_config_' + name + '_set'][1], 0)
        self.assertEqual(calls['wasmtime_config_memory_reservation_set'][1], 16777216)
        self.assertEqual(calls['wasmtime_config_max_wasm_stack_set'][1], 524288)
        self.assertEqual(self.events[-1][0], 'wasmtime_pooling_allocation_strategy_set')
        self.assertFalse(any('flag_enable' in str(event[0]) for event in self.events))

    def test_invalid_recipe_refuses_before_setting_or_import(self):
        recipe = replace(self.recipe, engine_body=b'{}')
        with self.assertRaises(LocalInstallationError):
            _configure_selected_engine(self.config, self.ffi.pool, self.ffi, self.wasmtime, recipe)
        self.assertEqual(self.events, [])
        self.image = replace(self.image, recipe=recipe)
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Native import')):
            with self.assertRaises(LocalInstallationError): self.create()

    def test_resources_refuse_before_image_capture(self):
        with patch('actql_sdk._local_engine._checked_installed_image', side_effect=AssertionError('Capture')):
            with self.assertRaises(ValueError):
                LocalCore._from_installed_image(object(), resources=RESOURCES, transfer_capacity=65537)

    def test_changed_image_and_unmetered_fuel_refuse_before_engine_import(self):
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Native import')):
            with self.assertRaisesRegex(ValueError, 'instruction fuel'): self.create(fuel=100000001)
            self.image = replace(self.image, encoded=b'changed')
            with self.assertRaisesRegex(ValueError, 'artifact or capacity'): self.create()

    def test_original_installed_files_and_dependency_digest_rechecked(self):
        case = distribution_fixture.LocalDistributionTests(); case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        library = case.directory / 'darwin-aarch64/_libwasmtime.dylib'
        library.parent.mkdir(); library.write_bytes(b'independent runtime library fixture')
        with patch('actql_sdk._local_engine.metadata.version', return_value='38.0.0'), \
                patch('actql_sdk._local_engine.resources.files', return_value=case.directory):
            original = _checked_installed_image(components)
            self.assertEqual(original.encoded, IMAGE)
            _verify_loaded_runtime(original, SimpleNamespace(filename=library, dll=SimpleNamespace(_name=str(library))))
            library.write_bytes(b'x' * components.image_recipe.runtime_library_bytes)
            with self.assertRaises(LocalInstallationError): _checked_installed_image(components)
            library.write_bytes(b'independent runtime library fixture')
            components.module.write_bytes(b'changed raw original')
            with self.assertRaises(LocalInstallationError): _checked_installed_image(components)

    def test_foreign_loaded_library_rejects_before_configuration(self):
        with self.assertRaises(LocalInstallationError):
            _verify_loaded_runtime(self.image, SimpleNamespace(filename=Path('/foreign/lib.dylib'),
                dll=SimpleNamespace(_name='/foreign/lib.dylib')))
        self.assertEqual(self.events, [])

    def test_installed_branch_only_deserializes_then_uses_existing_signature_refusal(self):
        with patch('actql_sdk._local_core.import_module', side_effect=self.runtime), \
                patch('actql_sdk._local_engine._verify_loaded_runtime'):
            with self.assertRaisesRegex(ValueError, 'physical imports'): self.create()
        self.deserialize.assert_called_once_with(self.engine, IMAGE)
        self.assertEqual([event for event in self.events if event[0] == 'fuel'], [('fuel', 100000000)])
        self.assertEqual([event[1] for event in self.events if event[0] == 'close'],
                         ['module', 'engine', 'store'])
        self.assertEqual([value for name, value in self.events if name == 'delete_pool'], [self.ffi.pool])

    def test_config_failure_retains_original_pending_pool_for_same_core_cleanup(self):
        self.ffi.fail_setting = 'wasmtime_pooling_allocation_config_max_core_instance_size_set'
        self.ffi.delete_failures = 1
        with patch('actql_sdk._local_core.import_module', side_effect=self.runtime), \
                patch('actql_sdk._local_engine._verify_loaded_runtime'):
            with self.assertRaises(LocalCoreInitializationError) as failure: self.create()
        core = failure.exception.cleanup_core
        self.assertIs(core._pool_configuration, self.ffi.pool)
        self.deserialize.assert_not_called()
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual([value for name, value in self.events if name == 'delete_pool'],
                         [self.ffi.pool, self.ffi.pool])
        self.assertEqual([event for event in self.events if event == ('close', 'config')], [('close', 'config')])

    def test_deserialized_module_cleanup_failure_keeps_original_engine_and_module(self):
        self.module.failures = 1
        with patch('actql_sdk._local_core.import_module', side_effect=self.runtime), \
                patch('actql_sdk._local_engine._verify_loaded_runtime'):
            with self.assertRaises(LocalCoreInitializationError) as failure: self.create()
        core = failure.exception.cleanup_core
        self.assertIs(core._module, self.module); self.assertIs(core._engine, self.engine)
        self.assertIs(core._store, self.store)
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.deserialize.assert_called_once()
        self.assertEqual([event[1] for event in self.events if event[0] == 'close'],
                         ['module', 'module', 'engine', 'store'])

    def test_installed_host_routes_only_to_image_constructor(self):
        components = object(); core = Mock()
        with TemporaryDirectory() as directory, \
                patch('actql_sdk._local_product.installed_local_components', return_value=components), \
                patch.object(LocalCore, '_from_installed_image', return_value=core) as create, \
                patch('actql_sdk._local_product._default_directory', return_value=Path(directory)), \
                patch.object(InstalledLocalHost, '__init__', return_value=None):
            InstalledLocalHost.installed(resources=RESOURCES)
        create.assert_called_once_with(components, transfer_capacity=12582912, slots=64, resources=RESOURCES)

    def test_baseline_competes_with_vm_and_pool_before_capture(self):
        # Independent scalar fixture, not an adopted product baseline.
        resources = replace(RESOURCES, execution_bytes=16777216 + 65536 + 4095)
        with patch('actql_sdk._local_engine._checked_installed_image', side_effect=AssertionError('Capture')):
            with self.assertRaises(ValueError):
                LocalCore._from_installed_image(object(), resources=resources,
                    transfer_capacity=65536, _host_capacity_bytes=4096)
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Native import')):
            for invalid in (None, True, -1, 2**63):
                with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                    self.create(_host_capacity_bytes=invalid)
            with self.assertRaises(ValueError):
                self.create(_host_capacity_bytes=1)

    def _construct_with_baseline(self, failures=0):
        calls = []
        self.engine.failures = failures
        linker = Handle('linker', self.events)
        linker.define_func = lambda *args: None
        linker.instantiate = lambda store, module: SimpleNamespace(exports=lambda store: {
            'actql_host_abi_version': lambda store: LOCAL_CORE_ABI,
            'actql_buffer_open': lambda store, *args: calls.append(('open', args)) or 0,
            'actql_buffer_close_pool': lambda store, *args: calls.append(('close', args)) or 0})
        self.wasmtime.Linker = lambda engine: linker
        self.wasmtime.ValType = SimpleNamespace(i32=lambda: 'i32', i64=lambda: 'i64')
        self.wasmtime.FuncType = lambda *args: args
        resources = replace(RESOURCES, execution_bytes=16777216 + 65536 + 4096)
        with patch('actql_sdk._local_core.import_module', side_effect=self.runtime), \
                patch('actql_sdk._local_engine._verify_loaded_runtime'), \
                patch('actql_sdk._local_core._validate_core_module'):
            core = LocalCore(None, digest='b' * 64, transfer_capacity=65536,
                resources=resources, _compiled_image=self.image, _host_capacity_bytes=4096)
        return core, calls

    def test_exact_initial_root_projection_and_no_second_baseline_on_close(self):
        core, calls = self._construct_with_baseline()
        self.assertEqual(calls, [('open', (core._nonce, 65536, 32, 1048576,
            0, 8, 0, 0, 0, 16846848, 4096))])
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual([name for name, args in calls], ['open', 'close'])
        self.assertEqual([event[1] for event in self.events if event[0] == 'close'],
                         ['linker', 'module', 'engine', 'store'])

    def test_cleanup_failure_keeps_original_engine_without_reopening_root(self):
        core, calls = self._construct_with_baseline(failures=1)
        with self.assertRaises(OSError): core.close()
        self.assertIs(core._engine, self.engine)
        self.assertIs(core._store, self.store)
        self.assertFalse(core._closed)
        self.assertTrue(core._retired)
        self.assertTrue(core.close())
        self.assertEqual([name for name, args in calls], ['open', 'close'])
        self.assertEqual([event[1] for event in self.events if event[0] == 'close'],
                         ['linker', 'module', 'engine', 'engine', 'store'])

    def test_store_failure_preserves_root_and_does_not_repeat_retired_native_handles(self):
        core, calls = self._construct_with_baseline()
        self.store.failures = 1
        with self.assertRaises(OSError): core.close()
        self.assertIs(core._store, self.store)
        self.assertIsNone(core._module); self.assertIsNone(core._engine)
        self.assertFalse(core._closed)
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual([name for name, args in calls], ['open', 'close'])
        self.assertEqual([event[1] for event in self.events if event[0] == 'close'],
                         ['linker', 'module', 'engine', 'store', 'store'])
