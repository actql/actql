"""Original handle/FFI doubles and actual file integrity; no native Engine execution."""
from contextlib import nullcontext
from dataclasses import replace
from copy import copy, deepcopy
from ctypes import c_void_p, cast, POINTER
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
    _configure_selected_engine, _platform_runtime_library, _verify_loaded_runtime)
from actql_sdk._local_image_recipe import _recipe_from_original
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_native_holding import (_NativeHoldingLease,
    NativeHoldingRetirementError, NativeHoldingScopeError)
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


class NativeRetirement:
    """Pointer/status double; no library loading, native allocation or unmap."""

    def __init__(self, events, replies):
        self.events, self.replies = events, list(replies)

    def __call__(self, slot):
        pointer = cast(slot, POINTER(c_void_p))
        self.events.append(('retire', pointer.contents.value))
        reply = self.replies.pop(0)
        if isinstance(reply, BaseException):
            raise reply
        code, cleared = reply
        if cleared:
            pointer.contents.value = None
        return code


class NativeScope:
    """Native TLS scope double, independent of production Python custody."""

    def __init__(self, state, operation):
        self.state, self.operation = state, operation

    def __call__(self, pointer):
        state = self.state
        state.events.append((self.operation, pointer.value))
        replies = state.enter_replies if self.operation == 'enter' else state.leave_replies
        code = replies.pop(0) if replies else 0
        if type(code) is int and code == 0:
            state.depth += 1 if self.operation == 'enter' else -1
        return code


class NativeTransfer:
    """Original native acquire context double, not a Python acceptance supplier."""

    def __init__(self):
        self.calls = []
        self.reply = 0

    def __call__(self, pointer, generation, recipe):
        self.calls.append((pointer.value, generation, bytes(recipe)))
        if isinstance(self.reply, BaseException): raise self.reply
        return self.reply


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
        self.runtime = lambda name: self.wasmtime if name in (
            'wasmtime', 'actql_local_runtime._wasmtime') else self.ffi

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

    def test_checked_image_does_not_rehash_the_same_already_verified_immutable_bytes(self):
        case = distribution_fixture.LocalDistributionTests(); case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        library = case.directory / 'darwin-aarch64/_libwasmtime.dylib'
        library.parent.mkdir(); library.write_bytes(b'independent runtime library fixture')
        distribution = SimpleNamespace(version='38.0.0', locate_file=lambda _: case.directory)
        with patch('actql_sdk._local_engine.metadata.distribution', return_value=distribution), \
                patch('actql_sdk._local_engine.hashlib.sha256', wraps=hashlib.sha256) as hashes:
            original = _checked_installed_image(components)
        self.assertEqual(original.encoded, IMAGE)
        self.assertEqual(original.sha256, components.image_sha256)
        complete_image_rehashes = [call for call in hashes.call_args_list if call.args == (IMAGE,)]
        self.assertEqual(complete_image_rehashes, [])

    def test_changed_image_descriptor_cannot_self_rebind_before_capture(self):
        case = distribution_fixture.LocalDistributionTests(); case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        library = case.directory / 'darwin-aarch64/_libwasmtime.dylib'
        library.parent.mkdir(); library.write_bytes(b'independent runtime library fixture')
        changed = IMAGE[:-1] + b'X'
        components.image.write_bytes(changed)
        case.body['compiled_image']['sha256'] = hashlib.sha256(changed).hexdigest()
        case.write_manifest()
        distribution = SimpleNamespace(version='38.0.0', locate_file=lambda _: case.directory)
        with patch('actql_sdk._local_engine.metadata.distribution', return_value=distribution), \
                patch('actql_sdk._local_engine._load_selected_image',
                      side_effect=AssertionError('capture before original binding')) as capture:
            with self.assertRaises(LocalInstallationError): _checked_installed_image(components)
            capture.assert_not_called()

    def test_image_change_after_descriptor_binding_still_fails_actual_full_digest_read(self):
        case = distribution_fixture.LocalDistributionTests(); case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        library = case.directory / 'darwin-aarch64/_libwasmtime.dylib'
        library.parent.mkdir(); library.write_bytes(b'independent runtime library fixture')
        components.image.write_bytes(IMAGE[:-1] + b'X')
        distribution = SimpleNamespace(version='38.0.0', locate_file=lambda _: case.directory)
        with patch('actql_sdk._local_engine.metadata.distribution', return_value=distribution):
            with self.assertRaises(LocalInstallationError): _checked_installed_image(components)

    def test_original_installed_files_and_dependency_digest_rechecked(self):
        case = distribution_fixture.LocalDistributionTests(); case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        library = case.directory / 'darwin-aarch64/_libwasmtime.dylib'
        library.parent.mkdir(); library.write_bytes(b'independent runtime library fixture')
        distribution = SimpleNamespace(version='38.0.0', locate_file=lambda _: case.directory)
        with patch('actql_sdk._local_engine.metadata.distribution', return_value=distribution):
            original = _checked_installed_image(components)
            self.assertEqual(original.encoded, IMAGE)
            _verify_loaded_runtime(original, SimpleNamespace(filename=library, dll=SimpleNamespace(_name=str(library))))
            library.write_bytes(b'x' * components.image_recipe.runtime_library_bytes)
            with self.assertRaises(LocalInstallationError): _checked_installed_image(components)
            library.write_bytes(b'independent runtime library fixture')
            components.module.write_bytes(b'changed raw original')
            with self.assertRaises(LocalInstallationError): _checked_installed_image(components)

    def test_platform_library_integrity_precedes_importing_its_package(self):
        case = distribution_fixture.LocalDistributionTests(); case.setUp(); self.addCleanup(case.doCleanups)
        components = case.inspect()
        library = case.directory / 'darwin-aarch64/_libwasmtime.dylib'
        library.parent.mkdir(); library.write_bytes(b'independent runtime library fixture')
        distribution = SimpleNamespace(version='38.0.0', locate_file=Mock(return_value=case.directory))
        from importlib import import_module
        imports = []
        def guarded_import(name, *args, **options):
            if name == 'wasmtime' or name.startswith('wasmtime.'):
                imports.append(name)
                raise AssertionError('Runtime package imported before library integrity admission')
            return import_module(name, *args, **options)
        with patch('actql_sdk._local_engine.metadata.version', return_value='38.0.0'), \
                patch('actql_sdk._local_engine.metadata.distribution', return_value=distribution), \
                patch('importlib.import_module', side_effect=guarded_import):
            self.assertEqual(_platform_runtime_library(components.image_recipe), library)
            self.assertEqual(_checked_installed_image(components).runtime_library, library)
            library.write_bytes(b'x' * components.image_recipe.runtime_library_bytes)
            with self.assertRaises(LocalInstallationError):
                _platform_runtime_library(components.image_recipe)
            with self.assertRaises(LocalInstallationError):
                _checked_installed_image(components)
        self.assertEqual(imports, [])

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
        core._host_operation.return_value = nullcontext()
        with TemporaryDirectory() as directory, \
                patch('actql_sdk._local_product.installed_local_components', return_value=components), \
                patch.object(LocalCore, '_from_installed_image', return_value=core) as create, \
                patch('actql_sdk._local_product._default_directory', return_value=Path(directory)), \
                patch.object(InstalledLocalHost, '__init__', return_value=None):
            InstalledLocalHost.installed(resources=RESOURCES)
        create.assert_called_once_with(components, transfer_capacity=12582912, slots=128,
                                       resources=RESOURCES, _ordinary_host=True)

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

    def _construct_with_baseline(self, failures=0, holding=None):
        calls = []
        self.engine.failures = failures
        linker = Handle('linker', self.events)
        linker.define_func = lambda *args, **kwargs: None
        linker.instantiate = lambda store, module: SimpleNamespace(exports=lambda store: {
            'memory': self.memory if holding is not None else None,
            'actql_host_abi_version': lambda store: LOCAL_CORE_ABI,
            'actql_buffer_open': lambda store, *args: calls.append(('open', args)) or 0,
            'actql_buffer_close_pool': lambda store, *args: calls.append(('close', args)) or 0})
        self.wasmtime.Linker = lambda engine: linker
        self.wasmtime.ValType = SimpleNamespace(i32=lambda: 'i32', i64=lambda: 'i64')
        self.wasmtime.FuncType = lambda *args: args
        if holding is not None:
            self.ffi.dll = holding._library
            self.store._context = lambda: c_void_p(345)
            self.wasmtime.Caller = type('Caller', (), {})
            memory_type = SimpleNamespace(is_64=False, is_shared=False,
                limits=SimpleNamespace(min=1, max=256), close=lambda: None)
            class Memory:
                def type(self, store): return memory_type
                def data_ptr(self, store): return c_void_p(234)
            self.wasmtime.Memory = Memory
            self.memory = Memory()
        resources = replace(RESOURCES, execution_bytes=16777216 + 65536 + 4096)
        with patch('actql_sdk._local_core.import_module', side_effect=self.runtime), \
                patch('actql_sdk._local_engine._verify_loaded_runtime'), \
                patch('actql_sdk._local_core._validate_core_module'):
            core = LocalCore(None, digest='b' * 64, transfer_capacity=65536,
                resources=resources, _compiled_image=self.image, _host_capacity_bytes=4096,
                _physical_holding=holding)
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

    def _holding(self, replies):
        retire = NativeRetirement(self.events, replies)
        state = SimpleNamespace(depth=0, events=[], enter_replies=[], leave_replies=[])
        library = SimpleNamespace(actql_owned_try_close=retire,
            actql_owned_enter=NativeScope(state, 'enter'),
            actql_owned_leave=NativeScope(state, 'leave'), scope=state,
            actql_owned_transfer=NativeTransfer())
        library.span_calls = []
        def span(pointer, address, length):
            library.span_calls.append((pointer.value, address.value, length))
            return 0
        library.actql_owned_contains_live_span = span
        def capacity(pointer, out):
            # Independent mapping scalar matches this fixture's VM + baseline.
            from ctypes import cast, POINTER, c_uint64
            cast(out, POINTER(c_uint64))[0] = 16777216 + 4096
            return 0
        library.actql_owned_capacity_bytes = capacity
        original = c_void_p(123)  # Independent pointer scalar, not an allocation.
        holding = _NativeHoldingLease(original, library, generation=7, recipe=b'r' * 32)
        self.assertIsNone(original.value)
        return holding, library

    def test_holding_failure_after_store_success_retries_only_original_holding(self):
        holding, library = self._holding([(-2, False), (0, True)])
        core, calls = self._construct_with_baseline(holding=holding)
        identity = core._identity
        self.assertEqual(core._physical_vm_span, (234, 16777216))
        with self.assertRaises(NativeHoldingRetirementError) as failure:
            core.close()
        self.assertEqual(failure.exception.code, -2)
        self.assertIs(core._identity, identity)
        self.assertIs(core._physical_holding, holding)
        self.assertIs(holding._library, library)
        self.assertEqual(holding._pointer.value, 123)
        self.assertIsNone(core._store)
        self.assertIsNone(core._physical_vm_span)
        self.assertFalse(core._closed)
        self.assertTrue(core._retired)
        with self.assertRaisesRegex(RuntimeError, 'closed'):
            core._call('buffer', 'open')
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertIsNone(core._physical_holding)
        self.assertEqual([name for name, _ in calls], ['open', 'close'])
        self.assertEqual([event for event in self.events if event[0] in ('close', 'retire')],
            [('close', 'linker'), ('close', 'module'), ('close', 'engine'),
             ('close', 'store'), ('retire', 123), ('retire', 123)])

    def test_store_failure_does_not_retire_holding_until_store_success(self):
        holding, _ = self._holding([(0, True)])
        core, _ = self._construct_with_baseline(holding=holding)
        self.store.failures = 1
        with self.assertRaises(OSError): core.close()
        self.assertIs(core._store, self.store)
        self.assertEqual(core._physical_vm_span, (234, 16777216))
        self.assertIs(core._physical_holding, holding)
        self.assertFalse(any(event[0] == 'retire' for event in self.events))
        self.assertTrue(core.close())
        self.assertEqual(self.events[-2:], [('close', 'store'), ('retire', 123)])

    def test_child_failure_does_not_retire_store_or_holding(self):
        holding, _ = self._holding([(0, True)])
        core, _ = self._construct_with_baseline(failures=1, holding=holding)
        with self.assertRaises(OSError): core.close()
        self.assertIs(core._store, self.store)
        self.assertIs(core._physical_holding, holding)
        self.assertFalse(any(event[0] == 'retire' for event in self.events))
        self.assertTrue(core.close())

    def test_unconfirmed_or_exceptional_retirement_does_not_mark_core_closed(self):
        for reply in ((0, False), (True, True), OSError('Unknown physical retirement')):
            with self.subTest(reply=reply):
                self.setUp()
                holding, library = self._holding([reply, (0, True)])
                core, calls = self._construct_with_baseline(holding=holding)
                with self.assertRaises((NativeHoldingRetirementError, OSError)) as first:
                    core.close()
                self.assertFalse(core._closed)
                self.assertIsNone(core._store)
                self.assertEqual(holding._pointer.value, None if reply == (True, True) else 123)
                with self.assertRaises((NativeHoldingRetirementError, OSError)) as second:
                    core.close()
                self.assertIs(first.exception, second.exception)
                self.assertIs(core._physical_holding, holding)
                self.assertFalse(core._closed)
                self.assertEqual(len(library.actql_owned_try_close.replies), 1)
                self.assertEqual([name for name, _ in calls], ['open', 'close'])

    def test_optional_import_failure_retains_same_holding_when_retirement_fails(self):
        holding, _ = self._holding([(-2, False), (0, True)])
        with patch('actql_sdk._local_core.import_module', side_effect=ImportError('Missing runtime')):
            with self.assertRaises(LocalCoreInitializationError) as failure:
                self.create(_physical_holding=holding)
        core = failure.exception.cleanup_core
        self.assertIs(core._physical_holding, holding)
        self.assertIsNone(core._store)
        self.assertFalse(core._closed)
        self.assertTrue(core._retired)
        self.assertIsInstance(failure.exception.__cause__, RuntimeError)
        self.assertTrue(core.close()); self.assertTrue(core.close())
        self.assertEqual(self.events, [('retire', 123), ('retire', 123)])

    def test_optional_import_failure_retires_holding_without_run_or_store(self):
        holding, _ = self._holding([(0, True)])
        with patch('actql_sdk._local_core.import_module', side_effect=ImportError('Missing runtime')):
            with self.assertRaisesRegex(RuntimeError, 'optional Wasmtime'):
                self.create(_physical_holding=holding)
        self.assertEqual(self.events, [('retire', 123)])
        self.assertIsNone(holding._pointer.value)

    def test_holding_slot_single_consumption_and_copy_refusal(self):
        retire = NativeRetirement(self.events, [(0, True)])
        library = SimpleNamespace(actql_owned_try_close=retire)
        slot = c_void_p(123)
        holding = _NativeHoldingLease(slot, library, generation=7, recipe=b'r' * 32)
        with self.assertRaises(ValueError):
            _NativeHoldingLease(slot, library, generation=7, recipe=b'r' * 32)
        with self.assertRaises(TypeError): copy(holding)
        with self.assertRaises(TypeError): deepcopy(holding)
        holding.close(); holding.close()
        self.assertEqual(self.events, [('retire', 123)])

    def test_holding_cannot_transfer_to_second_core_before_or_after_retirement(self):
        holding, _ = self._holding([(0, True)])
        core, _ = self._construct_with_baseline(holding=holding)
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Second engine')):
            with self.assertRaisesRegex(ValueError, 'already transferred'):
                self.create(_physical_holding=holding)
        self.assertIs(holding._core_identity, core._identity)
        self.assertTrue(core.close())
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Second engine')):
            with self.assertRaisesRegex(ValueError, 'already transferred'):
                self.create(_physical_holding=holding)

    def test_native_scope_covers_initialization_calls_and_store_retirement(self):
        holding, library = self._holding([(0, True)])
        state = library.scope
        config = self.wasmtime.Config
        self.wasmtime.Config = lambda: self._observe_scope(state, config)
        close_store = self.store.close
        self.store.close = lambda: self._observe_scope(state, close_store)
        core, _ = self._construct_with_baseline(holding=holding)
        self.assertEqual(state.depth, 0)
        # Original span observation, nominal capture, and the first guest-call
        # precheck each observe membership inside the same provider scope.
        self.assertEqual(state.events,
            [('enter', 123), ('enter', 123), ('leave', 123),
             ('enter', 123), ('leave', 123), ('enter', 123),
             ('enter', 123), ('leave', 123), ('leave', 123), ('leave', 123)])
        self.assertTrue(core.close())
        self.assertEqual(state.depth, 0)
        self.assertEqual(state.events[-6:],
            [('enter', 123), ('enter', 123), ('leave', 123),
             ('leave', 123), ('enter', 123), ('leave', 123)])

    def _observe_scope(self, state, action):
        self.assertGreater(state.depth, 0)
        return action()

    def test_foreign_runtime_library_refuses_before_config_or_engine(self):
        holding, library = self._holding([(0, True)])
        self.ffi.dll = object()
        with patch('actql_sdk._local_core.import_module', side_effect=self.runtime), \
                patch('actql_sdk._local_engine._verify_loaded_runtime'):
            with self.assertRaisesRegex(ValueError, 'runtime library differ'):
                self.create(_physical_holding=holding)
        self.deserialize.assert_not_called()
        self.assertEqual(self.events, [('retire', 123)])
        self.assertEqual(library.scope.depth, 0)

    def test_scope_enter_refusal_does_not_invoke_original_export(self):
        holding, library = self._holding([(0, True)])
        core, calls = self._construct_with_baseline(holding=holding)
        library.scope.enter_replies = [-3]
        with self.assertRaises(NativeHoldingScopeError) as failure:
            core._call('buffer', 'close_pool')
        self.assertEqual((failure.exception.operation, failure.exception.code), ('enter', -3))
        self.assertEqual([name for name, _ in calls], ['open'])
        self.assertFalse(core._closed)
        self.assertIs(core._physical_holding, holding)
        self.assertTrue(core.close())

    def test_native_export_exception_leaves_scope_without_replaying_call(self):
        holding, library = self._holding([(0, True)])
        core, calls = self._construct_with_baseline(holding=holding)
        unknown = OSError('Original native call outcome unknown')
        core._exports['actql_buffer_unknown'] = Mock(side_effect=unknown)
        with self.assertRaises(OSError) as failure:
            core._call('buffer', 'unknown')
        self.assertIs(failure.exception, unknown)
        core._exports['actql_buffer_unknown'].assert_called_once()
        self.assertEqual(library.scope.depth, 0)
        self.assertTrue(core._closing)
        self.assertTrue(core.close())
        self.assertEqual([name for name, _ in calls], ['open', 'close'])

    def test_final_holding_retry_does_not_reenter_a_retired_store_scope(self):
        holding, library = self._holding([(-2, False), (0, True)])
        core, _ = self._construct_with_baseline(holding=holding)
        with self.assertRaises(NativeHoldingRetirementError): core.close()
        scopes = list(library.scope.events)
        self.assertIsNone(core._store)
        self.assertTrue(core.close())
        self.assertEqual(library.scope.events, scopes)

    def test_scope_leave_failure_never_returns_success_or_releases_original_holding(self):
        holding, library = self._holding([(-3, False)])
        core, calls = self._construct_with_baseline(holding=holding)
        # Membership-precheck leave succeeds; the original guest-call scope's
        # leave then fails after guest execution, as in the original counterexample.
        library.scope.leave_replies = [0, -1]
        with self.assertRaises(NativeHoldingScopeError) as failure:
            core._call('buffer', 'close_pool')
        self.assertEqual((failure.exception.operation, failure.exception.code), ('leave', -1))
        self.assertEqual([name for name, _ in calls], ['open', 'close'])
        self.assertFalse(core._closed)
        self.assertIs(core._physical_holding, holding)
        self.assertEqual(library.scope.depth, 1)
        self.assertEqual([event for event in self.events if event[0] == 'retire'], [])
        # This double deliberately leaves an unconfirmed native scope. It is not
        # repaired/reentered here and does not establish physical cleanup.
