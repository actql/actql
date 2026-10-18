"""Original preparation DATA/refusals only; no actual parent, Engine or VM."""
import copy
import json
import pickle
import unittest
from unittest.mock import patch

import test_local_image_compiler as image

from actql_sdk._local_distribution import LocalInstallationError

compiler = image.compiler


class PhysicalCorePreparationTests(unittest.TestCase):
    def setUp(self):
        self.fixture = image.ImageCompilerTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.case = self.fixture.case
        self.staging = self.enterContext(patch.object(compiler, 'prepare_compiler_runtime',
            side_effect=lambda original, *_: self.fixture.preparation(original)))
        self.enterContext(patch.object(compiler, 'CDLL', side_effect=AssertionError('Native load')))
        self.enterContext(patch.object(compiler, 'import_module', side_effect=AssertionError('Native import')))

    def prepare(self):
        return compiler._PhysicalCoreInputs.prepare(self.case.module_file, self.case.image_file,
            self.case.head, scope='physical_core_conformance_only', bindings_source=self.case.root / 'unused-source',
            native_libraries=self.case.root / 'unused-libraries',
            destination=self.case.root / 'unused-destination')

    def test_compile_only_module_and_image_prepare_data_without_final_components_or_funding(self):
        prepared = self.prepare()
        current = prepared.require_current()
        self.assertEqual(current['module_sha256'], self.case.module_original['module_sha256'])
        self.assertEqual(prepared._image_sha256, self.case.image['image_sha256'])
        self.assertIs(prepared._runtime, current['private_runtime'])
        self.staging.assert_called_once()
        with self.assertRaisesRegex(ValueError, 'physical-boundary Core receipt'):
            compiler.assembly.verify_original_core(self.case.source, self.case.module_original, self.case.head)
        with self.assertRaisesRegex(ValueError, 'physical-boundary Core receipt'):
            compiler.assembly.verify_original_core(self.case.source, prepared.__dict__, self.case.head)
        self.assertFalse(self.fixture.destination.exists())

    def test_scope_is_closed_and_does_not_select_a_production_or_compile_verifier(self):
        for scope in (None, False, 'image_compiler_only', 'physical_buffer_bridge_workspace_only',
                      'physical_core_conformance_only\n'):
            with self.subTest(scope=scope):
                with self.assertRaisesRegex(ValueError, 'private physical Core verifier scope'):
                    compiler._PhysicalCoreInputs.prepare(self.case.module_file, self.case.image_file,
                        self.case.head, scope=scope, bindings_source=self.case.root / 'unused',
                        native_libraries=self.case.root / 'unused', destination=self.case.root / 'unused')
        self.staging.assert_not_called()

    def test_relative_original_receipt_refuses_before_preparation(self):
        with self.assertRaisesRegex(ValueError, 'absolute original'):
            compiler._PhysicalCoreInputs.prepare(self.case.module_file.relative_to(self.case.root),
                self.case.image_file, self.case.head, scope='physical_core_conformance_only',
                bindings_source=self.case.root / 'unused', native_libraries=self.case.root / 'unused',
                destination=self.case.root / 'unused')
        self.staging.assert_not_called()

    def test_image_correspondence_is_shared_with_final_producer(self):
        shared = compiler.assembly.verify_original_image
        with patch.object(compiler.assembly, 'verify_original_image', wraps=shared) as observed:
            self.prepare()
        self.assertEqual(observed.call_count, 2)
        self.assertEqual(observed.call_args.args[0], self.case.image)

    def test_scope_label_or_compiler_success_does_not_supply_missing_physical_observations(self):
        value = dict(self.case.module_original, scope='physical_core_conformance_only', compiled=True)
        with self.assertRaisesRegex(ValueError, 'physical-boundary Core receipt'):
            compiler.assembly.verify_original_core(self.case.source, value, self.case.head)
        for part in ('result', 'physical', 'workspace'):
            with self.subTest(part=part):
                bad = dict(self.case.core)
                bad[part] = dict(bad[part], cases=[])
                with self.assertRaisesRegex(ValueError, 'same module'):
                    compiler.assembly.verify_original_core(self.case.source, bad, self.case.head)

    def test_wrong_recipe_source_module_or_library_refuses_before_staging(self):
        original = dict(self.case.image)
        for field, value in (('source_sha', 'f' * 40), ('module_sha256', 'f' * 64),
                             ('runtime_library_sha256', 'f' * 64),
                             ('provider_library_sha256', 'f' * 64),
                             ('engine_sha256', 'f' * 64), ('core_abi', True),
                             ('runtime_executed', True), ('public_local_acceptance', True)):
            with self.subTest(field=field):
                self.case.image_file.write_text(json.dumps(dict(original, **{field:value})))
                with self.assertRaisesRegex(ValueError, 'original recipe'):
                    self.prepare()
        self.staging.assert_not_called()

    def test_unknown_image_fields_and_invalid_binary_target_refuse_before_staging(self):
        self.case.image_file.write_text(json.dumps(dict(self.case.image, physical=True)))
        with self.assertRaisesRegex(ValueError, 'compiled-image production receipt'):
            self.prepare()
        self.case.image_file.write_text(json.dumps(self.case.image))
        # Updating the digest cannot reclassify a foreign binary target.
        import hashlib
        raw = b'not-an-original-image'
        self.case.image_path.write_bytes(raw)
        self.case.image_file.write_text(json.dumps(dict(self.case.image,
            image_sha256=hashlib.sha256(raw).hexdigest())))
        with self.assertRaisesRegex(ValueError, 'image binary target'):
            self.prepare()
        self.staging.assert_not_called()

    def test_changed_image_or_module_receipt_refuses_same_preparation(self):
        prepared = self.prepare()
        original = self.case.image_file.read_bytes()
        self.case.image_file.write_bytes(original + b'\n')
        with self.assertRaisesRegex(ValueError, 'inputs changed'):
            prepared.require_current()
        self.case.image_file.write_bytes(original)
        self.case.module_file.write_bytes(self.case.module_file.read_bytes() + b'\n')
        with self.assertRaisesRegex(ValueError, 'inputs changed'):
            prepared.require_current()
        self.assertEqual(self.staging.call_count, 1)

    def test_added_private_member_or_modified_selected_provider_refuses_current(self):
        prepared = self.prepare()
        extra = self.fixture.preparation_root / 'unexpected.py'
        extra.write_text('# Independent extra member\n')
        with self.assertRaisesRegex(ValueError, 'original preparation'):
            prepared.require_current()
        extra.unlink()
        self.fixture.provider.write_bytes(b'x' * self.fixture.provider.stat().st_size)
        with self.assertRaisesRegex(LocalInstallationError, 'digest mismatched'):
            prepared.require_current()

    def test_source_change_and_symlink_image_refuse_without_replacement_preparation(self):
        prepared = self.prepare()
        changed = self.case.source / 'src/new_physical_input.mbt'
        changed.write_text('// Independent changed source\n')
        with self.assertRaisesRegex(ValueError, 'committed clean source'):
            prepared.require_current()
        changed.unlink()
        old = self.case.image_path.with_suffix('.kept')
        self.case.image_path.rename(old)
        self.case.image_path.symlink_to(old)
        with self.assertRaisesRegex(ValueError, 'regular file'):
            prepared.require_current()
        self.assertEqual(self.staging.call_count, 1)

    def test_original_preparation_cannot_be_constructed_copied_or_serialized(self):
        prepared = self.prepare()
        for operation in (lambda:compiler._PhysicalCoreInputs(), lambda:copy.copy(prepared),
                          lambda:copy.deepcopy(prepared), lambda:pickle.dumps(prepared)):
            with self.assertRaises(TypeError):
                operation()
        foreign = compiler._PhysicalCoreInputs.__new__(compiler._PhysicalCoreInputs)
        foreign.__dict__.update(prepared.__dict__)
        with self.assertRaisesRegex(ValueError, 'Foreign physical'):
            foreign.require_current()


if __name__ == '__main__':
    unittest.main()
