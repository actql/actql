"""Private wheel assembly with non-executable Mach-O fixtures; no native load."""
from dataclasses import replace
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

from actql_sdk._local_image_recipe import _recipe_from_original
from actql_sdk._local_distribution import LocalInstallationError
from image_fixture import ORIGINAL


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('private_runtime_stage',
    ROOT / 'scripts/prepare-python-local-runtime.py')
RECIPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECIPE)


def path_command(command, name):
    fixed = 12 if command == 0x8000001c else 24
    length = (fixed + len(name) + 1 + 7) & ~7
    return struct.pack('<3I', command, length, fixed) + b'\0' * (fixed - 12) + name + b'\0' * (length - fixed - len(name))


def library(identity, dependency=None, search=None, minimum=11 << 16):
    commands = [struct.pack('<6I', 0x32, 24, 1, minimum, minimum, 0), path_command(0xd, identity)]
    if dependency is not None:
        commands.append(path_command(0xc, dependency))
    if search is not None:
        commands.append(path_command(0x8000001c, search))
    body = b''.join(commands)
    return struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 6, len(commands), len(body), 0, 0) + body


class PrivateRuntimeStageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.native = self.root / 'native'
        self.native.mkdir()
        self.runtime = library(b'@rpath/_libwasmtime.dylib',
            b'@rpath/libactql_native_control.dylib', b'@loader_path')
        self.provider = library(b'@rpath/libactql_native_control.dylib')
        (self.native / '_libwasmtime.dylib').write_bytes(self.runtime)
        (self.native / 'libactql_native_control.dylib').write_bytes(self.provider)
        body = json.loads(ORIGINAL)
        for prefix, raw in [('runtime', self.runtime), ('provider', self.provider)]:
            body[prefix + '_library_sha256'] = hashlib.sha256(raw).hexdigest()
            body[prefix + '_library_bytes'] = len(raw)
        self.selected = _recipe_from_original(json.dumps(body).encode(),
            source_sha='a' * 40, package_version='0.0.0.dev0', module_sha256='b' * 64)
        self.target = self.root / 'stage'
        self.target.mkdir()
        self.license = (ROOT / 'packages/python-local-runtime/WASMTIME-LICENSE').read_bytes()

    def binding(self, source, target):
        # This fixture supplies only transformed Python bytes. Actual pinned
        # sdist/namespace checks are separately exercised by prepare_binding_source.
        private = target / 'actql_local_runtime/_wasmtime'
        private.mkdir(parents=True)
        (private / '__init__.py').write_bytes(b'# Independent non-executable binding fixture\n')
        (target / 'WASMTIME-PYTHON-LICENSE').write_bytes(self.license)
        return {'source_sha256': 'c' * 64, 'inputs': [{'file': '__init__.py'}]}

    def stage(self):
        with patch.object(RECIPE, 'prepare_private_bindings', side_effect=self.binding), \
                patch('ctypes.CDLL', side_effect=AssertionError('Native load')):
            return RECIPE.stage_private_runtime(SimpleNamespace(image_recipe=self.selected),
                self.root / 'fixed-archive', self.native, self.target)

    def test_exact_private_layout_and_notice_without_import(self):
        result = self.stage()
        for name, raw in [('_libwasmtime.dylib', self.runtime), ('libactql_native_control.dylib', self.provider)]:
            self.assertEqual((self.target / '_wasmtime/darwin-aarch64' / name).read_bytes(), raw)
        self.assertEqual((self.target / 'WASMTIME-LICENSE').read_bytes(), self.license)
        self.assertTrue((self.target / '_wasmtime/__init__.py').is_file())
        self.assertFalse(result['native_loaded'])

    def test_missing_corrupt_and_linked_original_are_refused(self):
        provider = self.native / 'libactql_native_control.dylib'
        for operation in ('missing', 'changed', 'symlink'):
            with self.subTest(operation=operation):
                provider.unlink()
                if operation == 'changed':
                    provider.write_bytes(b'x' * len(self.provider))
                if operation == 'symlink':
                    (self.root / 'outside').write_bytes(self.provider)
                    provider.symlink_to(self.root / 'outside')
                with self.assertRaises((OSError, ValueError, LocalInstallationError)):
                    self.stage()
                self.assertFalse((self.target / '_wasmtime').exists())
                if provider.is_symlink() or provider.exists():
                    provider.unlink()
                provider.write_bytes(self.provider)

    def test_wrong_identity_dependency_search_and_os_are_refused(self):
        for raw in (library(b'/private/build/libwasmtime.dylib', b'@rpath/libactql_native_control.dylib', b'@loader_path'),
                    library(b'@rpath/_libwasmtime.dylib', b'/opt/homebrew/lib/libactql_native_control.dylib', b'@loader_path'),
                    library(b'@rpath/_libwasmtime.dylib', b'@rpath/libactql_native_control.dylib', b'/private/build'),
                    library(b'@rpath/_libwasmtime.dylib', b'@rpath/libactql_native_control.dylib', b'@loader_path', 26 << 16)):
            with self.subTest(raw=raw):
                (self.native / '_libwasmtime.dylib').write_bytes(raw)
                self.selected = replace(self.selected, runtime_library_bytes=len(raw),
                    runtime_library_sha256=hashlib.sha256(raw).hexdigest())
                with self.assertRaises(ValueError):
                    self.stage()

    def test_input_metadata_swap_cannot_admit_invalid_staged_bytes(self):
        source = self.native / '_libwasmtime.dylib'
        invalid = library(b'@rpath/_libwasmtime.dylib',
            b'@rpath/libactql_native_control.dylib', b'@loader_path', 26 << 16)
        source.write_bytes(invalid)
        self.selected = replace(self.selected, runtime_library_bytes=len(invalid),
            runtime_library_sha256=hashlib.sha256(invalid).hexdigest())
        checked = RECIPE.library_target
        observations = []

        def swap_around_input_metadata(path, **options):
            observations.append(path)
            if path == source:
                # The first hash and later copy observe the selected invalid
                # bytes, but the separate input metadata read sees valid bytes.
                source.write_bytes(self.runtime)
                try:
                    checked(path, **options)
                finally:
                    source.write_bytes(invalid)
            else:
                checked(path, **options)

        with patch.object(RECIPE, 'library_target', side_effect=swap_around_input_metadata):
            with self.assertRaisesRegex(ValueError, 'macOS11'):
                self.stage()
        staged = self.target / '_wasmtime/darwin-aarch64/_libwasmtime.dylib'
        self.assertEqual(staged.read_bytes(), invalid)
        self.assertIn(staged, observations)

    def test_foreign_license_is_refused(self):
        self.license = b'Unrelated license bytes'
        with self.assertRaisesRegex(ValueError, 'license differs'):
            self.stage()

    def test_wheel_inspector_requires_every_staged_private_byte(self):
        self.stage()
        spec = importlib.util.spec_from_file_location('private_wheel', ROOT / 'scripts/build-python-product-wheels.py')
        wheel_recipe = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(wheel_recipe)
        # Artifact component checks stay independent of this private inventory.
        artifact_names = ('artifact.json', 'engine-recipe.json', 'client_host_wasm.cwasm',
            'client_host_wasm.wasm', 'libduckdb.dylib', 'LICENSE', 'DUCKDB-LICENSE',
            'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE')
        artifact = self.root / 'artifact'
        artifact.mkdir()
        for name in artifact_names:
            (artifact / name).write_bytes(b'Independent artifact fixture')
        stage = self.root / 'wheel-stage'
        package = stage / 'src/actql_local_runtime'
        package.parent.mkdir(parents=True)
        self.target.rename(package)
        members = {p.relative_to(package).as_posix(): p.read_bytes()
                   for p in package.rglob('*') if p.is_file()}
        for change in ('none', 'missing', 'corrupt', 'extra'):
            wheel = self.root / (change + '.whl')
            with zipfile.ZipFile(wheel, 'w') as archive:
                for name in artifact_names:
                    archive.writestr('actql_local_runtime/' + name, (artifact / name).read_bytes())
                for name, raw in members.items():
                    if change == 'missing' and name.endswith('_libwasmtime.dylib'):
                        continue
                    if change == 'corrupt' and name.endswith('_libwasmtime.dylib'):
                        raw = b'x' * len(raw)
                    archive.writestr('actql_local_runtime/' + name, raw)
                if change == 'extra':
                    archive.writestr('actql_local_runtime/_wasmtime/foreign.py', b'# unrelated')
            if change == 'none':
                wheel_recipe.runtime_wheel_components(wheel, artifact, stage)
            else:
                with self.assertRaises((ValueError, KeyError)):
                    wheel_recipe.runtime_wheel_components(wheel, artifact, stage)


if __name__ == '__main__':
    unittest.main()
