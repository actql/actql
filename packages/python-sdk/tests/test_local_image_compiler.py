"""Image compiler preflight/refusal and native doubles; no real compiler or image."""
from contextlib import ExitStack
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import test_local_artifact_producer as originals
import test_local_installed_image as native

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
        self.stack.enter_context(patch.object(compiler.metadata, 'version', return_value='38.0.0'))
        self.stack.enter_context(patch.object(compiler.resources, 'files', return_value=self.case.root))
        self.library = self.case.root / 'darwin-aarch64/_libwasmtime.dylib'
        self.library.parent.mkdir(); self.library.write_bytes(b'independent runtime library fixture')
        self.destination = self.case.root / 'compiled'

    def test_verify_only_does_not_import_native_runtime_or_issue_compiled_fact(self):
        with patch.object(compiler, 'import_module', side_effect=AssertionError('Native engine')):
            checked = compiler.verify(self.case.core_file, self.case.head)
        self.assertEqual(checked['source'], self.case.head)
        self.assertEqual(checked['module_sha256'], self.case.core['module_sha256'])
        self.assertEqual(checked['recipe'].source_sha, self.case.head)
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

    def test_signature_refusal_closes_native_handles_without_instance_or_receipt(self):
        case = native.InstalledImageTests(); case.setUp()
        case.ffi.filename = self.library; case.ffi.dll = SimpleNamespace(_name=str(self.library))
        case.wasmtime.Module = lambda engine, raw: case.module
        with patch.object(compiler, 'import_module', side_effect=case.runtime):
            with self.assertRaisesRegex(ValueError, 'physical imports'):
                compiler.compile_image(self.case.core_file, self.case.head, self.destination)
        self.assertEqual([event[1] for event in case.events if event[0] == 'close'], ['module', 'engine'])
        self.assertFalse(any(event[0] == 'fuel' for event in case.events))
        self.assertFalse(self.destination.exists())
