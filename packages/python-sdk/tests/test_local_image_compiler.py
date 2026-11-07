"""Image compiler preflight/refusal and native doubles; no real compiler or image."""
from contextlib import ExitStack
from dataclasses import replace
import hashlib
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import test_local_artifact_producer as originals
import test_local_installed_image as native
from image_fixture import PROVIDER, ORIGINAL, table_module
from actql_sdk._local_distribution import LocalInstallationError
from actql_sdk._local_image_recipe import _recipe_from_original
from actql_sdk._local_native_holding import NativeHoldingScopeError

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('prepared_image_compiler', ROOT / 'scripts/compile-python-local-image.py')
compiler = importlib.util.module_from_spec(spec); spec.loader.exec_module(compiler)


class ImageCompilerTests(unittest.TestCase):
    def setUp(self):
        self.case = originals.LocalArtifactProducerTests(); self.case.setUp(); self.addCleanup(self.case.doCleanups)
        self.stack = ExitStack(); self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(compiler, 'ROOT', self.case.source))
        self.stack.enter_context(patch.object(compiler.sys, 'platform', 'darwin'))
        self.stack.enter_context(patch.object(compiler.platform, 'machine', return_value='arm64'))
        self.library = self.case.root / 'darwin-aarch64/_libwasmtime.dylib'
        self.library.parent.mkdir(); self.library.write_bytes(b'independent runtime library fixture')
        self.provider = self.library.parent / 'libactql_native_control.dylib'
        self.provider.write_bytes(PROVIDER)
        self.destination = self.case.root / 'compiled'
        self.preparation_root = (self.case.root / 'prepared').resolve()
        (self.preparation_root / 'actql_local_runtime/_wasmtime/darwin-aarch64').mkdir(parents=True)
        for name in ('__init__.py', '_wasmtime/__init__.py'):
            (self.preparation_root / 'actql_local_runtime' / name).write_text('# Independent scalar namespace fixture\n')
        for path in (self.library, self.provider):
            (self.preparation_root / 'actql_local_runtime/_wasmtime/darwin-aarch64' / path.name).write_bytes(path.read_bytes())
        self.library = self.preparation_root / 'actql_local_runtime/_wasmtime/darwin-aarch64/_libwasmtime.dylib'
        self.provider = self.library.parent / 'libactql_native_control.dylib'

    def preparation(self, original=None):
        original = compiler.verify(self.case.module_file, self.case.head) if original is None else original
        return compiler._CompilerRuntime(original['source'], original['recipe'], self.preparation_root,
            compiler._runtime_files(self.preparation_root, original['recipe']))

    def test_original_module_table_geometry_enters_the_same_compiler_configuration(self):
        self.case.module.write_bytes(table_module(1952, 1956))
        original = compiler.assembly.record_original_module(self.case.source, self.case.head,
            self.case.head, self.case.module, self.case.link_response, self.case.moon_home)
        self.case.module_file.write_text(json.dumps(original))
        checked = compiler.verify(self.case.module_file, self.case.head)
        engine = json.loads(checked['recipe'].engine_body)
        self.assertEqual(engine['pooling']['table_elements'], 1956)
        self.assertEqual(engine['memory_reservation'], 16777216)
        header = compiler._compiler_configuration_header(checked['recipe'])
        self.assertIn(b'wasmtime_pooling_allocation_config_table_elements_set(pool, 1956ULL);', header)
        self.assertIn(b'16777216ULL', header)

    def test_c_configuration_preparation_uses_original_verifier_without_native_import(self):
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native import')):
            result = compiler.prepare_compiler_configuration(self.case.module_file, self.case.head,
                                                            self.destination.resolve())
        header = (self.destination / 'compiler_configuration.generated.h').read_bytes()
        self.assertEqual(result['header_sha256'], hashlib.sha256(header).hexdigest())
        self.assertEqual(result['source_sha'], self.case.head)
        self.assertEqual(result['scope'], 'original_compiler_configuration_only')
        self.assertIs(result['compiled'], False)
        self.assertIs(result['native_engine_started'], False)
        self.assertIs(result['physical_acceptance'], False)
        self.assertIn(self.case.head.encode(), header)
        with self.assertRaisesRegex(ValueError, 'original physical-boundary Core receipt'):
            compiler.assembly.verify_original_core(self.case.source, result, self.case.head)
        with self.assertRaisesRegex(ValueError, 'fresh canonical'):
            compiler.prepare_compiler_configuration(self.case.module_file, self.case.head,
                                                   self.destination.resolve())

    def test_c_projection_keeps_original_target_policy_and_pool_width(self):
        recipe = _recipe_from_original(ORIGINAL, source_sha='a' * 40,
                                      package_version='0.0.0.dev0', module_sha256='b' * 64)
        engine = json.loads(recipe.engine_body)
        engine['pooling']['table_elements'] = 2**64 - 1
        header = compiler._compiler_configuration_header(replace(recipe,
            engine_body=json.dumps(engine, sort_keys=True, separators=(',', ':')).encode()))
        self.assertIn(b'wasmtime_config_strategy_set(config, WASMTIME_STRATEGY_CRANELIFT);', header)
        self.assertIn(b'wasmtime_config_target_set(config, "aarch64-apple-darwin")', header)
        self.assertIn(b'wasmtime_pooling_allocation_config_table_elements_set(pool, 18446744073709551615ULL);', header)
        self.assertIn(b'if (error != NULL) return error;', header)
        self.assertNotIn(b'wasm_engine_new', header)

    def test_c_projection_rejects_invalid_original_before_output(self):
        recipe = _recipe_from_original(ORIGINAL, source_sha='a' * 40,
                                      package_version='0.0.0.dev0', module_sha256='b' * 64)
        for field, invalid in (('consume_fuel', 1), ('parallel_compilation', True),
                               ('target', 'aarch64-apple-darwin";foreign();'),
                               ('memory_reservation', True), ('strategy', 'auto')):
            with self.subTest(field=field):
                body = json.loads(recipe.engine_body)
                body[field] = invalid
                with self.assertRaises(LocalInstallationError):
                    compiler._compiler_configuration_header(replace(recipe, engine_body=json.dumps(body).encode()))

    def test_c_projection_refuses_unrepresentable_artifact_bound_without_changing_python_recipe(self):
        recipe = _recipe_from_original(ORIGINAL, source_sha='a' * 40,
                                      package_version='0.0.0.dev0', module_sha256='b' * 64)
        wide = replace(recipe, image_bytes_limit=2**63)
        wide.validate()
        with self.assertRaisesRegex(ValueError, 'not representable'):
            compiler._compiler_configuration_header(wide)

    def test_c_configuration_preparation_does_not_admit_changed_module(self):
        self.case.module_file.write_bytes(b'changed original module receipt')
        with self.assertRaises((ValueError, LocalInstallationError)):
            compiler.prepare_compiler_configuration(self.case.module_file, self.case.head,
                                                   self.destination.resolve())
        self.assertFalse(self.destination.exists())

    def test_verify_only_does_not_import_native_runtime_or_issue_compiled_fact(self):
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            checked = compiler.verify(self.case.core_file, self.case.head)
        self.assertEqual(checked['source'], self.case.head)
        self.assertEqual(checked['module_sha256'], self.case.core['module_sha256'])
        self.assertEqual(checked['recipe'].source_sha, self.case.head)
        self.assertFalse(self.destination.exists())

    def test_source_preflight_does_not_execute_an_ordinary_package_initializer(self):
        package = self.case.root / 'wasmtime'
        package.mkdir()
        marker = self.case.root / 'unfunded-package-imported'
        (package / '__init__.py').write_text(
            'from pathlib import Path\n'
            f'Path({str(marker)!r}).write_text("package initializer executed")\n'
            'raise AssertionError("Unfunded package initializer")\n')
        self.stack.enter_context(patch.object(sys, 'path', [str(self.case.root), *sys.path]))
        checked = compiler.verify(self.case.module_file, self.case.head)
        self.assertNotIn('runtime_library', checked)
        self.assertFalse(marker.exists())
        self.assertNotIn('wasmtime', sys.modules)
        self.assertFalse(self.destination.exists())

    def test_foreign_or_changed_preparation_refuses_before_import(self):
        original = compiler.verify(self.case.module_file, self.case.head)
        prepared = self.preparation(original)
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            with self.assertRaisesRegex(ValueError, 'original preparation'):
                compiler._runtime_original(original, prepared._replace(source_sha='f' * 40))
            (self.preparation_root / 'actql_local_runtime/__init__.py').write_text('# Changed fixture')
            with self.assertRaisesRegex(ValueError, 'original preparation'):
                compiler._runtime_original(original, prepared)

    def test_compile_only_original_verifies_without_claiming_physical_success(self):
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            checked = compiler.verify(self.case.module_file, self.case.head)
        self.assertEqual(checked['module_sha256'], self.case.core['module_sha256'])
        self.assertEqual(checked['source'], self.case.head)
        self.assertFalse(self.destination.exists())

    def test_compile_scope_does_not_relax_the_original_holding_requirement(self):
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            with self.assertRaisesRegex(ValueError, 'original native compiler holding'):
                compiler.compile_image(self.case.module_file, self.case.head, self.destination)
        self.assertFalse(self.destination.exists())

    def test_missing_or_modified_provider_is_refused_before_engine_import(self):
        original = compiler.verify(self.case.module_file, self.case.head)
        prepared = self.preparation(original)
        self.provider.unlink()
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            with self.assertRaisesRegex(ValueError, 'original preparation'):
                compiler._runtime_original(original, prepared)
            self.provider.write_bytes(b'x' * len(PROVIDER))
            with self.assertRaisesRegex(LocalInstallationError, 'digest mismatched'):
                compiler._runtime_original(original, prepared)
        self.assertFalse(self.destination.exists())

    def test_foreign_source_and_changed_original_receipt_refuse_before_runtime(self):
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            with self.assertRaisesRegex(ValueError, 'source changed'):
                compiler.compile_image(self.case.core_file, '0' * 40, self.destination)
            self.case.core['scope'] = 'not-original'; self.case.write_receipts()
            with self.assertRaisesRegex(ValueError, 'not public Local acceptance'):
                compiler.compile_image(self.case.core_file, self.case.head, self.destination)
        self.assertFalse(self.destination.exists())

    def test_unadopted_recipe_cannot_be_compiled_from_fallback_defaults(self):
        self.case.git('rm', 'packages/python-local-runtime/selected-image-recipe.json')
        self.case.commit(); self.case.core['source_sha'] = self.case.head; self.case.write_receipts()
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            with self.assertRaisesRegex(ValueError, 'source-original image recipe is unavailable'):
                compiler.compile_image(self.case.core_file, self.case.head, self.destination)
        self.assertFalse(self.destination.exists())

    def test_missing_original_holding_refuses_before_native_runtime_import(self):
        calls = []
        case = native.InstalledImageTests(); case.setUp()
        case.ffi.filename = self.library; case.ffi.dll = SimpleNamespace(_name=str(self.library))
        case.wasmtime.Module = lambda engine, raw: case.module
        def runtime(name):
            calls.append(name)
            return case.runtime(name)
        with patch.object(compiler, 'import_module', side_effect=runtime):
            with self.assertRaisesRegex(ValueError, 'original native compiler holding'):
                compiler.compile_image(self.case.core_file, self.case.head, self.destination)
        self.assertEqual(calls, [])
        self.assertEqual(case.events, [])
        self.assertFalse(self.destination.exists())

    def prepared_native(self, replies=None):
        case = native.InstalledImageTests(); case.setUp()
        case.ffi.filename = self.library; case.ffi.dll = SimpleNamespace(_name=str(self.library))
        case.wasmtime.Module = lambda engine, raw: case.module
        holding, provider = case._holding([(0, True)] if replies is None else replies)
        # Independent scalar transport doubles replace only loaded-CDLL checks.
        # No DLL, allocation, native compilation or nominal Core is created.
        self.stack.enter_context(patch.object(compiler, '_verify_compiler_holding'))
        self.stack.enter_context(patch.object(compiler, '_verify_selected_provider_link'))
        self.stack.enter_context(patch.object(compiler, '_import_compiler_runtime',
            side_effect=lambda custody, original: (case.wasmtime, case.ffi)))
        return case, holding, provider

    def compile_prepared(self, holding):
        return compiler.compile_image(self.case.core_file, self.case.head,
                                      self.destination, _holding=holding,
                                      _runtime=self.preparation())

    def test_signature_refusal_closes_native_handles_without_instance_or_receipt(self):
        case, holding, provider = self.prepared_native()
        with self.assertRaisesRegex(ValueError, 'physical imports'):
            self.compile_prepared(holding)
        self.assertEqual([event[1] for event in case.events if event[0] == 'close'], ['module', 'engine'])
        self.assertEqual(provider.scope.depth, 0)
        self.assertIsNone(holding._pointer.value)
        self.assertFalse(any(event[0] == 'fuel' for event in case.events))
        self.assertFalse(self.destination.exists())

    def test_scalar_compile_and_all_handle_cleanup_use_same_original_scope(self):
        case, holding, provider = self.prepared_native()
        state = provider.scope
        def scoped(action):
            def run(*args):
                self.assertEqual(state.depth, 1)
                return action(*args)
            return run
        case.wasmtime.Config = scoped(case.wasmtime.Config)
        case.wasmtime.Engine = scoped(case.wasmtime.Engine)
        case.wasmtime.Module = scoped(case.wasmtime.Module)
        case.ffi.wasmtime_pooling_allocation_config_new = scoped(case.ffi.wasmtime_pooling_allocation_config_new)
        case.ffi.wasmtime_pooling_allocation_config_delete = scoped(case.ffi.wasmtime_pooling_allocation_config_delete)
        case.module.serialize = scoped(lambda: b'independent scalar image bytes')
        for handle in (case.module, case.engine):
            handle.close = scoped(handle.close)
        with patch.object(compiler, '_validate_core_module'):
            result = self.compile_prepared(holding)
        self.assertTrue(result['compiled'])  # Scalar test result, not actual compilation evidence.
        self.assertFalse(result['runtime_executed'])
        self.assertFalse(result['public_local_acceptance'])
        self.assertEqual(state.events, [('enter', 123), ('leave', 123)] * 2)
        self.assertIsNone(holding._core_identity)
        self.assertFalse(holding._transfer_attempted)
        self.assertIsNone(holding._pointer.value)
        self.assertEqual([event[1] for event in case.events if event[0] == 'close'], ['module', 'engine'])

    def test_config_refusal_keeps_pending_pool_until_original_cleanup(self):
        case, holding, _ = self.prepared_native()
        case.ffi.fail_setting = 'wasmtime_config_target_set'
        with self.assertRaisesRegex(RuntimeError, 'config setter failure'):
            self.compile_prepared(holding)
        self.assertEqual([event[1] for event in case.events if event[0] == 'close'], ['config'])
        self.assertEqual(sum(event[0] == 'delete_pool' for event in case.events), 1)
        self.assertIsNone(holding._pointer.value)
        self.assertFalse(self.destination.exists())

    def test_lost_module_close_retains_same_module_engine_and_holding_without_retry(self):
        case, holding, provider = self.prepared_native()
        case.module.failures = 1
        with self.assertRaises(compiler.ImageCompilerCleanupError) as failure:
            self.compile_prepared(holding)
        cleanup = failure.exception.cleanup_compilation
        self.assertIs(cleanup.module, case.module)
        self.assertIs(cleanup.engine, case.engine)
        self.assertIs(cleanup.holding, holding)
        self.assertRegex(str(failure.exception.primary), 'physical imports')
        self.assertEqual(provider.scope.depth, 0)
        self.assertEqual(holding._pointer.value, 123)
        before = list(case.events), list(provider.scope.events)
        with self.assertRaises(OSError):
            cleanup.close()
        self.assertEqual((case.events, provider.scope.events), before)
        self.assertFalse(self.destination.exists())

    def test_pool_close_response_loss_is_sticky_and_does_not_release_its_config(self):
        case, holding, provider = self.prepared_native()
        case.ffi.delete_failures = 1
        with self.assertRaises(compiler.ImageCompilerCleanupError) as failure:
            self.compile_prepared(holding)
        cleanup = failure.exception.cleanup_compilation
        self.assertIs(cleanup.pool, case.ffi.pool)
        self.assertIs(cleanup.config, case.config)
        before = list(case.events), list(provider.scope.events)
        with self.assertRaises(OSError):
            cleanup.close()
        self.assertEqual((case.events, provider.scope.events), before)
        self.assertEqual(holding._pointer.value, 123)
        self.assertFalse(any(event[0] == 'retire' for event in case.events))

    def test_scope_leave_loss_keeps_all_handles_without_reentry_or_cleanup_guess(self):
        case, holding, provider = self.prepared_native()
        provider.scope.leave_replies = [-2]
        with self.assertRaises(compiler.ImageCompilerCleanupError) as failure:
            self.compile_prepared(holding)
        cleanup = failure.exception.cleanup_compilation
        self.assertIsInstance(failure.exception.__cause__, NativeHoldingScopeError)
        self.assertIs(cleanup.module, case.module)
        self.assertIs(cleanup.engine, case.engine)
        before = list(case.events), list(provider.scope.events)
        with self.assertRaises(NativeHoldingScopeError):
            cleanup.close()
        self.assertEqual((case.events, provider.scope.events), before)
        self.assertEqual(holding._pointer.value, 123)

    def test_scope_entry_refusal_never_imports_or_retires_the_original(self):
        case, holding, provider = self.prepared_native()
        provider.scope.enter_replies = [-3]
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native import')):
            with self.assertRaises(compiler.ImageCompilerCleanupError) as failure:
                self.compile_prepared(holding)
        self.assertIs(failure.exception.cleanup_compilation.holding, holding)
        self.assertEqual(provider.scope.events, [('enter', 123)])
        self.assertEqual(case.events, [])

    def test_known_holding_retirement_refusal_retries_only_same_slot_after_handles_close(self):
        case, holding, provider = self.prepared_native([(-2, False), (0, True)])
        with self.assertRaises(compiler.ImageCompilerCleanupError) as failure:
            self.compile_prepared(holding)
        cleanup = failure.exception.cleanup_compilation
        self.assertIsNone(cleanup.module)
        self.assertIsNone(cleanup.engine)
        scope_before = list(provider.scope.events)
        cleanup.close(); cleanup.close()
        self.assertEqual(provider.scope.events, scope_before)
        self.assertEqual([event for event in case.events if event[0] == 'retire'], [('retire', 123)] * 2)
        self.assertIsNone(holding._pointer.value)
        self.assertFalse(self.destination.exists())

    def test_original_holding_refuses_fake_bound_retired_and_foreign_provider_inputs(self):
        case = native.InstalledImageTests(); case.setUp()
        holding, _ = case._holding([(0, True)])
        original = {'provider_library': self.provider}
        with self.assertRaisesRegex(ValueError, 'original native compiler holding'):
            compiler._verify_compiler_holding(original, object())
        holding._core_identity = object()
        with self.assertRaisesRegex(ValueError, 'original native compiler holding'):
            compiler._verify_compiler_holding(original, holding)
        holding._core_identity = None
        with self.assertRaisesRegex(ValueError, 'different selected provider'):
            compiler._verify_compiler_holding(original, holding)
        holding.close()
        with self.assertRaisesRegex(ValueError, 'original native compiler holding'):
            compiler._verify_compiler_holding(original, holding)

    def test_provider_linkage_refusal_precedes_config_and_releases_only_after_scope_stop(self):
        case, holding, provider = self.prepared_native()
        def mismatch(*args):
            self.assertEqual(provider.scope.depth, 1)
            raise LocalInstallationError('Independent foreign provider link')
        with patch.object(compiler, '_verify_selected_provider_link', side_effect=mismatch):
            with self.assertRaisesRegex(LocalInstallationError, 'foreign provider link'):
                self.compile_prepared(holding)
        self.assertEqual(case.events, [('retire', 123)])
        self.assertEqual(provider.scope.events, [('enter', 123), ('leave', 123)])
        self.assertIsNone(holding._pointer.value)

    def test_image_overflow_closes_original_handles_without_writing(self):
        case, holding, _ = self.prepared_native()
        case.module.serialize = lambda: b'x' * 1025
        with patch.object(compiler, '_validate_core_module'):
            with self.assertRaisesRegex(ValueError, 'file envelope'):
                self.compile_prepared(holding)
        self.assertEqual([event[1] for event in case.events if event[0] == 'close'], ['module', 'engine'])
        self.assertIsNone(holding._pointer.value)
        self.assertFalse(self.destination.exists())
