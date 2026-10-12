"""Installed metadata and component bytes; no runtime generation or execution."""
from contextlib import ExitStack
import hashlib
from importlib import metadata
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import tomllib
import unittest
from unittest.mock import patch

from actql_sdk._local_distribution import (
    inspect_local_components, installed_local_components, LocalInstallationError,
)

ROOT = Path(__file__).resolve().parents[3]


class LocalDistributionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.enterContext(patch('actql_sdk._local_distribution.sys.platform', 'darwin'))
        self.enterContext(patch('actql_sdk._local_distribution.platform.machine', return_value='arm64'))
        self.body = {'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0',
                     'platform': 'darwin-arm64', 'core_abi': 53, 'wasmtime_version': '38.0.0',
                     'duckdb_version': 'v1.4.3', 'notices': {}}
        for name, key in [('client_host_wasm.wasm', 'module'), ('libduckdb.dylib', 'duckdb')]:
            value = b'fixture component ' + name.encode()
            (self.directory / name).write_bytes(value)
            self.body[key] = {'file': name, 'bytes': len(value), 'sha256': hashlib.sha256(value).hexdigest()}
        for name in ('LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE'):
            value = b'fixture license ' + name.encode()
            (self.directory / name).write_bytes(value)
            self.body['notices'][name] = hashlib.sha256(value).hexdigest()
        self.write_manifest()

    def write_manifest(self):
        (self.directory / 'artifact.json').write_text(json.dumps(self.body))

    def inspect(self):
        return inspect_local_components(self.directory, package_version='0.0.0.dev0')

    def test_exact_installed_component_paths_without_engine_import(self):
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine imported')):
            result = self.inspect()
        self.assertEqual(result.module, self.directory / 'client_host_wasm.wasm')
        self.assertEqual(result.duckdb, self.directory / 'libduckdb.dylib')
        self.assertEqual(result.source_sha, 'a' * 40)
        self.assertEqual(result.duckdb_version, 'v1.4.3')

    def test_manifest_cohort_abi_and_closed_fields_reject(self):
        original = dict(self.body)
        for field, value in [('source_sha', 'a' * 39), ('package_version', 'other'),
                             ('core_abi', 43), ('core_abi', 44), ('core_abi', 45), ('core_abi', 46), ('core_abi', 47), ('core_abi', 48), ('core_abi', 49), ('core_abi', 50), ('core_abi', 51), ('core_abi', 52), ('core_abi', True), ('platform', 'linux-x64'),
                             ('wasmtime_version', '37.0.0'), ('duckdb_version', 'unknown'),
                             ('extra', 'ignored')]:
            with self.subTest(field=field, value=value):
                self.body = original | {field: value}
                self.write_manifest()
                with self.assertRaises(LocalInstallationError):
                    self.inspect()
        self.body = original
        self.write_manifest()

    def test_other_duckdb_versions_cannot_enter_selected_installed_profile(self):
        # The selected standalone version is independently fixed by the
        # vendor manifest and artifact producer, not a product response.
        original = dict(self.body)
        with patch('actql_sdk._local_core.import_module',
                   side_effect=AssertionError('Engine imported')):
            for version in ('v1.4.2', 'v1.5.5', 'v2.0.0'):
                with self.subTest(version=version):
                    self.body = original | {'duckdb_version': version}
                    self.write_manifest()
                    with self.assertRaisesRegex(LocalInstallationError, 'cohort is incompatible'):
                        self.inspect()

    def test_duplicate_manifest_and_oversized_manifest_reject(self):
        path = self.directory / 'artifact.json'
        path.write_text(json.dumps(self.body)[:-1] + ', "core_abi": 53}')
        with self.assertRaisesRegex(LocalInstallationError, 'Duplicate'):
            self.inspect()
        path.write_bytes(b' ' * 65537)
        with self.assertRaisesRegex(LocalInstallationError, 'size'):
            self.inspect()

    def test_component_corruption_truncation_and_symlink_reject(self):
        for filename in ('client_host_wasm.wasm', 'libduckdb.dylib', 'MOONBIT-CORE-NOTICE'):
            path = self.directory / filename
            original = path.read_bytes()
            for payload in (b'x' * len(original), original[:-1]):
                with self.subTest(filename=filename, corruption=payload[:5]):
                    path.write_bytes(payload)
                    with self.assertRaises(LocalInstallationError):
                        self.inspect()
            path.write_bytes(original)
            other = self.directory / 'outside'
            other.write_bytes(original)
            path.unlink()
            path.symlink_to(other)
            with self.assertRaises(LocalInstallationError):
                self.inspect()
            path.unlink()
            path.write_bytes(original)

    def test_paths_and_boolean_lengths_cannot_escape_manifest(self):
        original = self.body['module'].copy()
        for change in ({'file': '../client_host_wasm.wasm'}, {'bytes': True}, {'sha256': '0' * 64},
                       {'file': '/tmp/core.wasm'}, {'bytes': 33 * 1024 * 1024}):
            with self.subTest(change=change):
                self.body['module'] = original | change
                self.write_manifest()
                with self.assertRaises(LocalInstallationError):
                    self.inspect()

    def test_unsupported_platform_rejects_before_resources_or_dependency_discovery(self):
        with ExitStack() as stack:
            stack.enter_context(patch('actql_sdk._local_distribution.sys.platform', 'linux'))
            stack.enter_context(patch('actql_sdk._local_distribution.resources.files', side_effect=AssertionError('Discovery')))
            stack.enter_context(patch('actql_sdk._local_distribution.metadata.version', side_effect=AssertionError('Dependency')))
            with self.assertRaisesRegex(LocalInstallationError, 'platform'):
                installed_local_components()

    def test_installed_resolver_uses_matching_cohort_and_optional_dependency(self):
        versions = {'actql-sdk': '0.0.0.dev0', 'actql-local-runtime': '0.0.0.dev0', 'wasmtime': '38.0.0'}
        with patch('actql_sdk._local_distribution.metadata.version', side_effect=lambda name: versions[name]), \
                patch('actql_sdk._local_distribution.resources.files', return_value=self.directory) as resource:
            self.assertEqual(installed_local_components().module, self.directory / 'client_host_wasm.wasm')
            resource.assert_called_once_with('actql_local_runtime')
            for name in ('actql-local-runtime', 'wasmtime'):
                original = versions[name]
                versions[name] = 'wrong'
                with self.assertRaisesRegex(LocalInstallationError, 'incompatible'):
                    installed_local_components()
                versions[name] = original
        with patch('actql_sdk._local_distribution.metadata.version', side_effect=metadata.PackageNotFoundError('runtime')):
            with self.assertRaisesRegex(LocalInstallationError, r'actql-sdk\[local\]'):
                installed_local_components()

    def test_recipe_and_sdk_versions_dependencies_are_one_cohort(self):
        sdk = tomllib.loads((ROOT / 'packages/python-sdk/pyproject.toml').read_text())['project']
        runtime = tomllib.loads((ROOT / 'packages/python-local-runtime/pyproject.toml').read_text())['project']
        self.assertEqual(runtime['version'], sdk['version'])
        self.assertEqual(sdk['optional-dependencies']['local'],
                         ['actql-local-runtime==' + sdk['version'], 'wasmtime==38.0.0'])
        self.assertEqual(runtime['dependencies'], ['wasmtime==38.0.0'])
        self.assertEqual(sdk['dependencies'], ['httpx==0.28.1', 'rfc8785==0.1.4'])

    def test_recipe_reads_actual_binary_target_without_loading(self):
        spec = importlib.util.spec_from_file_location('local_recipe', ROOT / 'scripts/prepare-python-local-runtime.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        library = self.directory / 'fixture.dylib'
        def thin(cpu=0x0100000c, minimum=11 << 16):
            command = struct.pack('<6I', 0x32, 24, 1, minimum, minimum, 0)
            return struct.pack('<8I', 0xfeedfacf, cpu, 0, 6, 1, len(command), 0, 0) + command
        library.write_bytes(thin())
        module.library_target(library)
        # A universal library still advertises only the selected arm64 profile.
        binary = thin()
        library.write_bytes(struct.pack('>7I', 0xcafebabe, 1, 0x0100000c, 0, 28, len(binary), 0) + binary)
        module.library_target(library)
        for binary in (thin(cpu=0x01000007), thin(minimum=12 << 16), b'not a library'):
            library.write_bytes(binary)
            with self.assertRaises((ValueError, struct.error)):
                module.library_target(library)

    def test_recipe_refuses_node_homebrew_or_relative_dependency(self):
        spec = importlib.util.spec_from_file_location('local_recipe_dependencies', ROOT / 'scripts/prepare-python-local-runtime.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        minimum = struct.pack('<6I', 0x32, 24, 1, 11 << 16, 11 << 16, 0)
        for command in (0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023):
            for name, accepted in [(b'/usr/lib/libSystem.B.dylib', True),
                                   (b'/System/Library/Frameworks/Security.framework/Security', True),
                                   (b'@loader_path/node_modules/native.dylib', False),
                                   (b'/opt/homebrew/lib/libduckdb.dylib', False),
                                   (b'@rpath/libc++.dylib', False)]:
                padded = name + b'\0' * (4 - len(name) % 4)
                dependency = struct.pack('<6I', command, 24 + len(padded), 24, 0, 0, 0) + padded
                commands = minimum + dependency
                binary = struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 6, 2, len(commands), 0, 0) + commands
                library = self.directory / 'linked-fixture.dylib'
                library.write_bytes(binary)
                with self.subTest(command=command, name=name):
                    if accepted:
                        module.library_target(library)
                    else:
                        with self.assertRaisesRegex(ValueError, 'unbundled'):
                            module.library_target(library)

    def test_runtime_import_has_no_engine_or_sdk_dependency(self):
        spec = importlib.util.spec_from_file_location('runtime_package',
            ROOT / 'packages/python-local-runtime/src/actql_local_runtime/__init__.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertNotIn('wasmtime', vars(module))
        self.assertNotIn('duckdb', vars(module))
        self.assertNotIn('actql_sdk', vars(module))
