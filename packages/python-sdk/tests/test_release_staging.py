"""Release metadata and inert packaging, never product/engine acceptance."""
from dataclasses import replace
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from unittest.mock import patch
import zipfile

from image_fixture import ENGINE, IMAGE, RUNTIME_HASH
from actql_sdk._local_distribution import inspect_local_components, LocalInstallationError
from actql_sdk._local_wasm_abi import LOCAL_CORE_ABI

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import (select_release_version, release_project_metadata,
                                   release_runtime_metadata, verify_built_cohort)

SPEC = importlib.util.spec_from_file_location('release_wheel_builder', ROOT / 'scripts/build-python-product-wheels.py')
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)
SOURCE = 'a' * 40  # Independent fixture; not a selected product release.
SOURCE_VERSION = '0.0.0.dev0'


def digest(body):
    return hashlib.sha256(body).hexdigest()


class ReleaseStagingTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='actql-release-staging-')
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)

    def test_shared_version_owner_and_no_implicit_number(self):
        for value, expected in [('0.0.7', '0.0.7'), ('0.0.7-alpha.0', '0.0.7a0'),
                                ('0.0.7-beta.2', '0.0.7b2'), ('0.0.7-rc.3', '0.0.7rc3')]:
            actual = select_release_version(value)
            self.assertEqual(actual['pythonVersion'], expected)
            self.assertEqual(actual['version'], value)
        for value in ['patch', '0.0.7-preview.1', '0.0.7rc3', '0.0.7\n']:
            with self.assertRaises(subprocess.CalledProcessError):
                select_release_version(value)
        with self.assertRaises(TypeError):
            BUILDER.build(self.directory / 'absent-artifact', self.directory / 'absent-output')
        self.assertFalse((self.directory / 'absent-output').exists())

    def test_three_project_projections_preserve_every_other_field_and_original_bytes(self):
        for package, name in [('python-product', 'actql'), ('python-sdk', 'actql-sdk'),
                              ('python-local-runtime', 'actql-local-runtime')]:
            path = ROOT / 'packages' / package / 'pyproject.toml'
            original = path.read_bytes()
            expected = tomllib.loads(original.decode())
            expected['project']['version'] = '0.0.7rc3'
            if name == 'actql':
                expected['project']['dependencies'] = ['actql-sdk==0.0.7rc3', 'actql-local-runtime==0.0.7rc3']
            after = release_project_metadata(original, name, SOURCE_VERSION, '0.0.7rc3')
            self.assertEqual(tomllib.loads(after.decode()), expected)
            self.assertEqual(path.read_bytes(), original)
            with self.assertRaises(ValueError):
                release_project_metadata(original, name, '0.0.6', '0.0.7rc3')
        broken = original.replace(b'version = "0.0.0.dev0"', b'version = "0.0.0.dev0" # changed layout')
        with self.assertRaises(ValueError):
            release_project_metadata(broken, name, SOURCE_VERSION, '0.0.7rc3')

    def artifact(self):
        root = self.directory / 'original-artifact'
        root.mkdir()
        body = {'source_sha': SOURCE, 'package_version': SOURCE_VERSION, 'platform': 'darwin-arm64',
                'core_abi': LOCAL_CORE_ABI, 'wasmtime_version': '38.0.0', 'duckdb_version': 'v1.4.3', 'notices': {}}
        for name, key in [('client_host_wasm.wasm', 'module'), ('libduckdb.dylib', 'duckdb')]:
            value = ('Independent inert fixture ' + name).encode()
            (root / name).write_bytes(value)
            body[key] = {'file': name, 'bytes': len(value), 'sha256': digest(value)}
        for name in ['LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE']:
            value = ('Independent fixture notice ' + name).encode()
            (root / name).write_bytes(value)
            body['notices'][name] = digest(value)
        recipe = {'wasmtime_version': '38.0.0', 'runtime_library_sha256': RUNTIME_HASH,
                  'runtime_library_bytes': len(b'independent runtime library fixture'),
                  'provider_library_sha256': None, 'provider_library_bytes': None,
                  'engine_body': ENGINE, 'image_bytes_limit': 1024, 'runtime_allocation': 'platform'}
        original = json.dumps(recipe).encode()
        (root / 'engine-recipe.json').write_bytes(original)
        body['engine_recipe'] = {'file': 'engine-recipe.json', 'bytes': len(original), 'sha256': digest(original)}
        (root / 'client_host_wasm.cwasm').write_bytes(IMAGE)
        engine = json.dumps(ENGINE, sort_keys=True, separators=(',', ':')).encode()
        body['compiled_image'] = {'source_sha': SOURCE, 'package_version': SOURCE_VERSION,
            'module_sha256': body['module']['sha256'], 'core_abi': LOCAL_CORE_ABI, 'wasmtime_version': '38.0.0',
            'runtime_library_sha256': RUNTIME_HASH, 'provider_library_sha256': None,
            'platform': 'darwin-arm64', 'engine_body': ENGINE, 'engine_sha256': digest(engine),
            'file': 'client_host_wasm.cwasm', 'bytes': len(IMAGE), 'sha256': digest(IMAGE),
            'runtime_allocation': 'platform'}
        (root / 'artifact.json').write_bytes(json.dumps(body).encode())
        self.enterContext(patch('actql_sdk._local_distribution.sys.platform', 'darwin'))
        self.enterContext(patch('actql_sdk._local_distribution.platform.machine', return_value='arm64'))
        return root, body

    def test_full_original_and_staged_component_readers_keep_exact_binary_and_recipe_identity(self):
        root, body = self.artifact()
        before = {p.name: p.read_bytes() for p in root.iterdir()}
        original = inspect_local_components(root, package_version=SOURCE_VERSION)
        selected = self.directory / 'selected'
        shutil.copytree(root, selected)
        projected = release_runtime_metadata(before['artifact.json'], SOURCE, SOURCE_VERSION, '0.0.7rc3')
        (selected / 'artifact.json').write_bytes(projected)
        actual = inspect_local_components(selected, package_version='0.0.7rc3', artifact_sha256=digest(projected))
        self.assertEqual(actual.image_recipe, replace(original.image_recipe, package_version='0.0.7rc3'))
        for field in ['module_sha256', 'duckdb_sha256', 'image_sha256', 'image_bytes', 'engine_recipe_sha256']:
            self.assertEqual(getattr(actual, field), getattr(original, field))
        expected = json.loads(before['artifact.json'])
        expected['package_version'] = expected['compiled_image']['package_version'] = '0.0.7rc3'
        self.assertEqual(json.loads(projected), expected)
        for name, value in before.items():
            self.assertEqual((root / name).read_bytes(), value)
            if name != 'artifact.json':
                self.assertEqual((selected / name).read_bytes(), value)
        with self.assertRaises(LocalInstallationError):
            inspect_local_components(selected, package_version=SOURCE_VERSION)
        changed = json.loads(projected)
        changed['compiled_image']['engine_body']['consume_fuel'] = False
        (selected / 'artifact.json').write_text(json.dumps(changed))
        with self.assertRaises(LocalInstallationError):
            inspect_local_components(selected, package_version='0.0.7rc3')

    def test_runtime_projection_refuses_foreign_originals_duplicates_and_expanded_wire(self):
        root, body = self.artifact()
        original = (root / 'artifact.json').read_bytes()
        for source, version in [('b' * 40, SOURCE_VERSION), (SOURCE, '0.0.6')]:
            with self.assertRaises(ValueError):
                release_runtime_metadata(original, source, version, '0.0.7rc3')
        duplicate = original.replace(b'"source_sha":', b'"source_sha":"a", "source_sha":', 1)
        with self.assertRaises(ValueError):
            release_runtime_metadata(duplicate, SOURCE, SOURCE_VERSION, '0.0.7rc3')
        with self.assertRaises(ValueError):
            release_runtime_metadata(original, SOURCE, SOURCE_VERSION, '7' * 65536)

    def test_real_rc_and_final_wheels_have_separate_metadata_names_and_exact_internal_pins(self):
        wheels = self.directory / 'wheels'
        wheels.mkdir()
        for version in ['0.0.7rc3', '0.0.7']:
            for package, distribution in [('python-product', 'actql'), ('python-sdk', 'actql-sdk'),
                                           ('python-local-runtime', 'actql-local-runtime')]:
                stage = self.directory / (package + '-' + version)
                stage.mkdir()
                original = ROOT / 'packages' / package
                (stage / 'pyproject.toml').write_bytes(release_project_metadata(
                    (original / 'pyproject.toml').read_bytes(), distribution, SOURCE_VERSION, version))
                (stage / 'README.md').write_text('Independent inert packaging fixture; not a product release.\n')
                shutil.copyfile(ROOT / 'LICENSE', stage / 'LICENSE')
                module = distribution.replace('-', '_')
                payload = stage / 'src' / module
                payload.mkdir(parents=True)
                for name in ['__init__.py', '__init__.pyi', 'py.typed']:
                    (payload / name).write_text('')
                if distribution == 'actql-local-runtime':
                    shutil.copyfile(original / 'setup.py', stage / 'setup.py')
                    (payload / 'artifact.json').write_text('{"platform":"darwin-arm64"}')
                    for name in ['DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE', 'WASMTIME-LICENSE']:
                        (stage / name).write_text('Inert notice fixture\n')
                subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation', '--outdir',
                                str(wheels), str(stage)], check=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=30)
                tag = 'py3-none-macosx_11_0_arm64' if distribution == 'actql-local-runtime' else 'py3-none-any'
                wheel = wheels / (module + '-' + version + '-' + tag + '.whl')
                BUILDER.wheel_metadata(wheel, distribution, version)
                other = '0.0.7' if version.endswith('rc3') else '0.0.7rc3'
                with self.assertRaises(ValueError):
                    BUILDER.wheel_metadata(wheel, distribution, other)
        self.assertEqual(len(list(wheels.glob('*.whl'))), 6)

    def test_fixed_release_manifest_and_original_binary_check_survive_wheel_staging(self):
        original, _ = self.artifact()
        components = inspect_local_components(original, package_version=SOURCE_VERSION)
        fixed = release_runtime_metadata((original / 'artifact.json').read_bytes(), SOURCE, SOURCE_VERSION, '0.0.7rc3')
        stage = self.directory / 'stage'
        payload = stage / 'src/actql_local_runtime'
        shutil.copytree(original, payload)
        (payload / 'artifact.json').write_bytes(fixed)
        (payload / 'WASMTIME-LICENSE').write_bytes(b'Independent inert runtime notice\n')
        wheel = self.directory / 'fixture.whl'
        def pack():
            with zipfile.ZipFile(wheel, 'w') as archive:
                for path in payload.iterdir():
                    archive.writestr('actql_local_runtime/' + path.name, path.read_bytes())
        pack()
        recipe = replace(components.image_recipe, package_version='0.0.7rc3')
        self.assertEqual(BUILDER.runtime_wheel_components(wheel, original, stage,
            selected_recipe=recipe, release_manifest=fixed), {})
        (payload / 'artifact.json').write_bytes(fixed + b' ')
        pack()
        with self.assertRaises(ValueError):
            BUILDER.runtime_wheel_components(wheel, original, stage, selected_recipe=recipe, release_manifest=fixed)
        (payload / 'artifact.json').write_bytes(fixed)
        (payload / 'client_host_wasm.wasm').write_bytes(b'Changed binary cannot follow metadata projection')
        pack()
        with self.assertRaises(ValueError):
            BUILDER.runtime_wheel_components(wheel, original, stage, selected_recipe=recipe, release_manifest=fixed)

    def test_cohort_verifier_binds_optional_release_projection_and_exact_transform_inventory(self):
        wheels = self.directory / 'wheels'
        wheels.mkdir()
        records = []
        version = '0.0.7rc3'
        for name in ['actql-sdk', 'actql-local-runtime', 'actql']:
            tag = 'py3-none-macosx_11_0_arm64' if name == 'actql-local-runtime' else 'py3-none-any'
            stem = name.replace('-', '_')
            path = wheels / (stem + '-' + version + '-' + tag + '.whl')
            info = stem + '-' + version + '.dist-info/'
            dependencies = {'actql': ['actql-sdk==' + version, 'actql-local-runtime==' + version],
                'actql-sdk': ['httpx==0.28.1', 'rfc8785==0.1.4'],
                'actql-local-runtime': ['wasmtime==38.0.0']}[name]
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr(info + 'METADATA', 'Metadata-Version: 2.4\nName: ' + name + '\nVersion: ' + version + '\n' +
                                 ''.join('Requires-Dist: ' + value + '\n' for value in dependencies))
                archive.writestr(info + 'WHEEL', 'Wheel-Version: 1.0\nTag: ' + tag + '\n')
                if name == 'actql':
                    for member in ['__init__.py', '__init__.pyi', 'py.typed']:
                        archive.writestr('actql/' + member, '')
            records.append({'distribution': name, 'file': path.name, 'bytes': path.stat().st_size,
                            'sha256': digest(path.read_bytes())})
        transforms = [{'file': name, 'before_sha256': 'a' * 64, 'after_sha256': 'b' * 64} for name in [
            'stages/python-product/pyproject.toml', 'stages/python-sdk/pyproject.toml',
            'stages/python-local-runtime/pyproject.toml',
            'stages/python-local-runtime/src/actql_local_runtime/artifact.json']]
        body = {'source_sha': SOURCE, 'package_version': version, 'artifact_sha256': 'b' * 64,
                'platform': 'darwin-arm64', 'core_abi': 78, 'module_sha256': 'c' * 64, 'duckdb_sha256': 'd' * 64,
                'image_sha256': 'e' * 64, 'engine_recipe_sha256': 'f' * 64, 'host_capacity_sha256': None,
                'wheels': records, 'runtime_executed': False, 'public_local_accepted': False,
                'recovery_accepted': False, 'published': False,
                'release_metadata': {'version': '0.0.7-rc.3', 'source_package_version': SOURCE_VERSION,
                                     'source_artifact_sha256': 'a' * 64, 'transforms': transforms}}
        manifest = self.directory / 'cohort.json'
        manifest.write_text(json.dumps(body))
        verify_built_cohort(self.directory, SOURCE, version)
        body['release_metadata']['version'] = '0.0.7'
        manifest.write_text(json.dumps(body))
        with self.assertRaises(ValueError):
            verify_built_cohort(self.directory, SOURCE, version)
        body['release_metadata']['version'] = '0.0.7-rc.3'
        body['release_metadata']['transforms'][-1]['after_sha256'] = 'c' * 64
        manifest.write_text(json.dumps(body))
        with self.assertRaises(ValueError):
            verify_built_cohort(self.directory, SOURCE, version)


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ReleaseStagingTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    executed = result.testsRun - len(result.skipped)
    print(f'Python release staging: executed={executed}, skipped={len(result.skipped)}', flush=True)
    sys.exit(0 if executed > 0 and result.wasSuccessful() else 1)
