"""Selected-target bytes on a different preparation host; no runtime adoption.

The target is still Darwin. Host overrides are component controls, not actual
Linux execution/ABI acceptance. Existing inert fixtures and full readers stay
unchanged; no engine, native provider or business state is loaded.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import test_release_staging as staging
import test_local_artifact_producer as artifact_fixture
from actql_sdk import _local_distribution as distribution


class ReleasePackagingTargetTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='actql-packaging-target-')
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)

    def artifact(self):
        return staging.ReleaseStagingTests.artifact(self)

    def linux(self):
        self.enterContext(patch.object(distribution.sys, 'platform', 'linux'))
        self.enterContext(patch.object(distribution.platform, 'machine', return_value='x86_64'))
        self.enterContext(patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine import')))

    def inspect(self, root, **fields):
        return distribution._inspect_local_components_for_packaging(root,
            target_platform='darwin-arm64', package_version=staging.SOURCE_VERSION, **fields)

    def test_full_same_target_predicate_is_host_independent_without_loading_or_changing_bytes(self):
        root, _ = self.artifact()
        original = distribution.inspect_local_components(root, package_version=staging.SOURCE_VERSION)
        before = {path.name: path.read_bytes() for path in root.iterdir()}
        self.linux()
        actual = self.inspect(root)
        self.assertEqual(actual, original)
        self.assertEqual({path.name: path.read_bytes() for path in root.iterdir()}, before)
        self.assertEqual(actual.image_recipe.runtime_allocation, 'platform')

    def test_both_installed_entry_points_keep_early_host_refusal_before_input_or_metadata_io(self):
        root, _ = self.artifact()
        self.linux()
        with patch.object(distribution, '_read_file', side_effect=AssertionError('Unexpected component I/O')), \
                patch.object(distribution.metadata, 'version', side_effect=AssertionError('Unexpected installed metadata')):
            with self.assertRaisesRegex(distribution.LocalInstallationError, 'not available for this platform'):
                distribution.inspect_local_components(root, package_version=staging.SOURCE_VERSION)
            with self.assertRaisesRegex(distribution.LocalInstallationError, 'not available for this platform'):
                distribution.installed_local_components()

    def test_unqualified_target_choices_refuse_before_reading_any_artifact(self):
        self.linux()
        for target in ['linux-x64-gnu', 'linux-arm64', 'windows-x64', '', None, True]:
            with self.subTest(target=target), patch.object(distribution, '_read_file', side_effect=AssertionError('Unexpected input')):
                with self.assertRaisesRegex(distribution.LocalInstallationError, 'packaging target'):
                    distribution._inspect_local_components_for_packaging(self.directory / 'missing',
                        target_platform=target, package_version=staging.SOURCE_VERSION)

    def test_full_corrupt_components_and_self_consistent_foreign_platform_or_engine_still_refuse(self):
        root, body = self.artifact()
        self.linux()
        original = (root / 'artifact.json').read_bytes()
        module = root / body['module']['file']
        module_before = module.read_bytes()
        module.write_bytes(b'changed same target module')
        with self.assertRaises(distribution.LocalInstallationError):
            self.inspect(root)
        module.write_bytes(module_before)
        changed = json.loads(original)
        changed['platform'] = changed['compiled_image']['platform'] = 'linux-x64-gnu'
        (root / 'artifact.json').write_text(json.dumps(changed))
        with self.assertRaises(distribution.LocalInstallationError):
            self.inspect(root)
        (root / 'artifact.json').write_bytes(original)
        recipe_path = root / 'engine-recipe.json'
        recipe = json.loads(recipe_path.read_bytes())
        recipe['engine_body']['consume_fuel'] = False
        raw = json.dumps(recipe).encode()
        recipe_path.write_bytes(raw)
        changed = json.loads(original)
        changed['engine_recipe'].update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        changed['compiled_image']['engine_body']['consume_fuel'] = False
        (root / 'artifact.json').write_text(json.dumps(changed))
        with self.assertRaises(distribution.LocalInstallationError):
            self.inspect(root)

    def test_original_pending_descriptor_record_propagates_without_replacement(self):
        from actql_sdk._local_worker_slot import _OriginalDescriptor
        root, _ = self.artifact()
        self.linux()
        descriptor = _OriginalDescriptor(-1)  # Inert identity; not a live FD.
        pending = distribution.LocalComponentReadCleanupPending(descriptor)
        pending.original_error = OSError('original controlled failure')
        with patch.object(distribution, '_read_file', side_effect=pending):
            with self.assertRaises(distribution.LocalComponentReadCleanupPending) as observed:
                self.inspect(root)
        self.assertIs(observed.exception, pending)
        self.assertIs(observed.exception.cleanup_descriptor, descriptor)

    def producer_fixture(self):
        fixture = artifact_fixture.LocalArtifactProducerTests('runTest')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        # The reused assembly fixture predates the current ABI pin. Bind this
        # new metadata-only case to the actual producer pin; no image executes.
        fixture.image['core_abi'] = artifact_fixture.producer.LOCAL_CORE_ABI
        fixture.write_receipts()
        fixture.run_producer()
        return fixture

    def test_actual_preparation_calls_same_full_target_reader_on_a_nonexecuting_host(self):
        fixture = self.producer_fixture()
        self.linux()
        recipe = artifact_fixture.producer.recipe
        before = {path.name: path.read_bytes() for path in fixture.output.iterdir()}
        original = recipe.verify_artifact(fixture.output, target_platform='darwin-arm64')
        stage = fixture.root / 'cross-host-stage'
        def private_stage(components, archive, libraries, target):
            self.assertEqual(components, original)
            (target / 'WASMTIME-LICENSE').write_bytes(b'inert private notice fixture')
            return {'native_loaded': False}
        with patch.object(recipe, 'stage_private_runtime', side_effect=private_stage):
            result = recipe.prepare(fixture.output, stage, target_platform='darwin-arm64',
                bindings_source=fixture.root / 'inert-bindings', native_libraries=fixture.root / 'inert-libraries')
        self.assertFalse(result['runtime_executed'])
        self.assertFalse(result['public_local_accepted'])
        self.assertFalse(result['wheel_built'])
        self.assertEqual({path.name: path.read_bytes() for path in fixture.output.iterdir()}, before)
        self.assertEqual((stage / 'src/actql_local_runtime/artifact.json').read_bytes(), before['artifact.json'])

    def test_packaging_keeps_original_producer_library_target_and_abi_refusal(self):
        fixture = self.producer_fixture()
        self.linux()
        root = fixture.output
        body = json.loads((root / 'artifact.json').read_bytes())
        library = root / body['duckdb']['file']
        changed = bytearray(library.read_bytes())
        changed[4:8] = (0x01000007).to_bytes(4, 'little')  # Real predicate refuses wrong CPU.
        library.write_bytes(changed)
        body['duckdb']['sha256'] = hashlib.sha256(changed).hexdigest()
        (root / 'artifact.json').write_text(json.dumps(body))
        with self.assertRaisesRegex(ValueError, 'arm64'):
            artifact_fixture.producer.recipe.verify_artifact(root, target_platform='darwin-arm64')

    def test_both_real_cli_parsers_refuse_unqualified_linux_target_without_creating_output(self):
        for script in ['prepare-python-local-runtime.py', 'build-python-product-wheels.py']:
            output = self.directory / script
            args = [sys.executable, '-B', str(staging.ROOT / 'scripts' / script),
                '--artifact-directory', str(self.directory / 'missing'), '--destination', str(output),
                '--target-platform', 'linux-x64-gnu']
            if script.startswith('build-'):
                args += ['--version', '0.0.7']
            result = subprocess.run(args, capture_output=True, text=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('invalid choice', result.stderr)
            self.assertFalse(output.exists())
