"""Shared staging and real Python import boundaries; no DLL load or Engine."""
from contextlib import contextmanager
from dataclasses import replace
from importlib import import_module
from pathlib import Path
import subprocess
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import test_local_image_compiler as image
import test_local_private_runtime_stage as stage

compiler = image.compiler


class CompilerPrivateRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.fixture = stage.PrivateRuntimeStageTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=image.ROOT, text=True).strip()
        self.original = {'source': source, 'recipe': replace(self.fixture.selected, source_sha=source)}
        self.destination = (self.root / 'compiler-preparation').resolve()
        self.depth = 0
        self.imports = []
        @contextmanager
        def scope():
            self.assertEqual(self.depth, 0)
            self.depth += 1
            try:
                yield
            finally:
                self.depth -= 1
        self.holding = SimpleNamespace(_scope=scope, close=Mock())
        self.custody = compiler._CompilerCustody(self.holding)
        self.stack = self.enterContext(patch.object(compiler.assembly.recipe,
            'prepare_private_bindings', side_effect=self.binding))
        self.enterContext(patch('ctypes.CDLL', side_effect=AssertionError('No native loading')))
        self.before_modules = {name: module for name, module in sys.modules.copy().items()
            if name == 'actql_local_runtime' or name.startswith('actql_local_runtime.')}
        self.assertEqual(self.before_modules, {})
        # Only these test-authored, non-native modules may be removed here.
        # Product cleanup does not unload/retry a partially imported runtime.
        self.addCleanup(self.clear_test_modules)

    def clear_test_modules(self):
        for name in list(sys.modules):
            if name == 'actql_local_runtime' or name.startswith('actql_local_runtime.'):
                del sys.modules[name]
        sys.modules.update(self.before_modules)

    def binding(self, source, target):
        result = self.fixture.binding(source, target)
        private = target / 'actql_local_runtime/_wasmtime'
        (private / '_ffi.py').write_text('"""Independent Python transport fixture; no native load."""\n')
        (private / '__init__.py').write_text('from . import _ffi\n')
        return result

    def prepare(self):
        prepared = compiler.prepare_compiler_runtime(self.original,
            self.root / 'fixed-source-archive', self.fixture.native, self.destination)
        self.custody.preparation = prepared
        return prepared

    def load(self, prepared):
        original = compiler._runtime_original(self.original, prepared)
        def observed(name):
            self.assertEqual(self.depth, 1)
            self.assertTrue(name.startswith('actql_local_runtime.'))
            self.imports.append(name)
            return import_module(name)
        with patch.object(compiler, 'import_module', side_effect=observed):
            return self.custody.scoped(lambda: compiler._import_compiler_runtime(self.custody, original))

    def test_source_only_stage_reuses_selected_product_checks_without_components(self):
        selected_stage = compiler.assembly.recipe.stage_selected_private_runtime
        with patch.object(compiler.assembly.recipe, 'stage_selected_private_runtime', wraps=selected_stage) as shared:
            prepared = self.prepare()
        shared.assert_called_once_with(self.original['recipe'], self.root / 'fixed-source-archive',
                                      self.fixture.native, self.destination / 'actql_local_runtime')
        checked = compiler._runtime_original(self.original, prepared)
        self.assertEqual(checked['provider_library'].read_bytes(), self.fixture.provider)
        self.assertEqual(checked['runtime_library'].read_bytes(), self.fixture.runtime)
        self.assertEqual(self.imports, [])
        self.assertNotIn('actql_local_runtime', sys.modules)
        self.holding.close.assert_not_called()

    def test_actual_private_python_import_is_in_same_scope_and_retains_aliases(self):
        prepared = self.prepare()
        before_path, before_bytecode = sys.path[:], sys.dont_write_bytecode
        runtime, ffi = self.load(prepared)
        self.assertIs(runtime._ffi, ffi)
        self.assertEqual(self.imports, ['actql_local_runtime._wasmtime', 'actql_local_runtime._wasmtime._ffi'])
        self.assertIn(runtime, self.custody.runtime_modules)
        self.assertIn(ffi, self.custody.runtime_modules)
        self.assertEqual(sys.path, before_path)
        self.assertIs(sys.dont_write_bytecode, before_bytecode)
        self.assertEqual(list(self.destination.rglob('*.pyc')), [])
        self.assertEqual(compiler._runtime_files(self.destination, prepared.recipe), prepared.files)
        self.custody.close()
        self.holding.close.assert_called_once()
        self.assertIs(self.custody.preparation, prepared)

    def test_preloaded_private_namespace_refuses_without_import_or_replacement(self):
        prepared = self.prepare()
        foreign = ModuleType('actql_local_runtime')
        sys.modules[foreign.__name__] = foreign
        with self.assertRaisesRegex(ValueError, 'already loaded'):
            self.load(prepared)
        self.assertEqual(self.imports, [])
        self.assertIs(sys.modules[foreign.__name__], foreign)
        self.custody.close()
        self.holding.close.assert_called_once()

    def test_added_changed_and_symlinked_members_refuse_before_import(self):
        prepared = self.prepare()
        member = self.destination / 'actql_local_runtime/_wasmtime/_ffi.py'
        raw = member.read_bytes()
        extra = member.parent / 'unexpected.py'
        extra.write_text('# Extra source is not the original preparation\n')
        with self.assertRaisesRegex(ValueError, 'original preparation'):
            self.load(prepared)
        extra.unlink()
        member.write_text('# Modified source\n')
        with self.assertRaisesRegex(ValueError, 'original preparation'):
            self.load(prepared)
        member.unlink(); (self.root / 'outside.py').write_bytes(raw)
        member.symlink_to(self.root / 'outside.py')
        with self.assertRaisesRegex(ValueError, 'nonregular'):
            self.load(prepared)
        self.assertEqual(self.imports, [])

    def test_partial_import_keeps_same_holding_aliases_and_sticky_cleanup(self):
        prepared = self.prepare()
        primary = OSError('Independent response loss after importing the original private ffi')
        def partial(name):
            self.assertEqual(self.depth, 1)
            module = import_module(name)
            self.imports.append(name)
            if name.endswith('._ffi'):
                raise primary
            return module
        original = compiler._runtime_original(self.original, prepared)
        before_path = sys.path[:]
        with patch.object(compiler, 'import_module', side_effect=partial):
            with self.assertRaises(OSError) as caught:
                self.custody.scoped(lambda: compiler._import_compiler_runtime(self.custody, original))
        self.assertIs(caught.exception, primary)
        self.assertIn(sys.modules['actql_local_runtime._wasmtime._ffi'], self.custody.runtime_modules)
        self.assertEqual(sys.path, before_path)
        with self.assertRaises(OSError) as repeated:
            self.custody.close()
        self.assertIs(repeated.exception, primary)
        self.holding.close.assert_not_called()
        self.assertFalse(self.custody._closed)
        self.assertIs(self.custody.preparation, prepared)
        self.assertEqual(len(self.imports), 2)

    def test_wrong_loaded_origin_keeps_partial_custody_without_claiming_cleanup(self):
        prepared = self.prepare()
        original = compiler._runtime_original(self.original, prepared)
        def foreign(name):
            module = import_module(name)
            if name.endswith('._ffi'):
                module.__file__ = str(self.root / 'foreign.py')
            return module
        with patch.object(compiler, 'import_module', side_effect=foreign):
            with self.assertRaisesRegex(ValueError, 'foreign private runtime'):
                self.custody.scoped(lambda: compiler._import_compiler_runtime(self.custody, original))
        with self.assertRaisesRegex(ValueError, 'foreign private runtime'):
            self.custody.close()
        self.holding.close.assert_not_called()
        self.assertTrue(self.custody.runtime_modules)

    def test_preparation_refuses_existing_directory_and_does_not_overwrite(self):
        prepared = self.prepare()
        before = prepared.files
        with self.assertRaisesRegex(ValueError, 'fresh absolute'):
            self.prepare()
        self.assertEqual(compiler._runtime_files(self.destination, prepared.recipe), before)

    def test_cli_composition_acquires_only_the_owned_staged_provider(self):
        original = {**self.original, 'module_sha256': 'b' * 64}
        selected = SimpleNamespace(capacity_bytes=123)
        self.holding._capacity_bytes = lambda: 123
        def acquire(checked, declaration):
            self.assertIs(declaration, selected)
            self.assertEqual(checked['provider_library'], self.destination /
                'actql_local_runtime/_wasmtime/darwin-aarch64/libactql_native_control.dylib')
            self.assertNotEqual(checked['provider_library'].parent, self.fixture.native)
            self.assertEqual(checked['provider_library'].read_bytes(), self.fixture.provider)
            self.assertNotIn('actql_local_runtime', sys.modules)
            return self.holding
        def compile_original(receipt, source, destination, **options):
            self.assertIs(options['_holding'], self.holding)
            self.assertEqual(options['_runtime'].directory, self.destination)
            self.assertEqual(options['_runtime'].source_sha, source)
            return {'scalar_composition_only': True}
        with patch.object(compiler, 'verify', return_value=original), \
                patch.object(compiler, '_compiler_holding_original', return_value=selected), \
                patch.object(compiler, '_acquire_compiler_holding', side_effect=acquire) as acquired, \
                patch.object(compiler, 'compile_image', side_effect=compile_original) as compiled:
            result = compiler.compile_from_original(self.root / 'receipt', original['source'],
                self.root / 'image', bindings_source=self.root / 'fixed-source-archive',
                native_libraries=self.fixture.native, preparation=self.destination)
        self.assertEqual(result, {'scalar_composition_only': True})
        acquired.assert_called_once(); compiled.assert_called_once()
        self.holding.close.assert_not_called()  # Scalar compile double owns this test-only responsibility.

    def test_partial_source_preparation_is_retained_without_acquiring(self):
        primary = ValueError('Independent binding-source refusal')
        with patch.object(compiler, 'verify', return_value=self.original), \
                patch.object(compiler, '_compiler_holding_original', return_value=object()), \
                patch.object(compiler.assembly.recipe, 'prepare_private_bindings', side_effect=primary), \
                patch.object(compiler, '_acquire_compiler_holding', side_effect=AssertionError('Acquire')):
            with self.assertRaises(ValueError) as caught:
                compiler.compile_from_original(self.root / 'receipt', self.original['source'],
                    self.root / 'image', bindings_source=self.root / 'fixed-source-archive',
                    native_libraries=self.fixture.native, preparation=self.destination)
        self.assertIs(caught.exception, primary)
        self.assertTrue((self.destination / 'actql_local_runtime/__init__.py').is_file())
        self.assertNotIn('actql_local_runtime', sys.modules)
        self.holding.close.assert_not_called()
