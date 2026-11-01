"""Installed metadata and component bytes; no runtime generation or execution."""
from contextlib import ExitStack
import hashlib
from importlib import metadata
import importlib.util
import json
import os
from pathlib import Path
import struct
import tempfile
import tomllib
import unittest
from unittest.mock import patch

from image_fixture import IMAGE, ORIGINAL, descriptor

from actql_sdk._local_distribution import (
    inspect_local_components, installed_local_components, load_local_module, LocalInstallationError,
    LocalComponentReadCleanupPending, _read_file,
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
                     'platform': 'darwin-arm64', 'core_abi': 83, 'wasmtime_version': '38.0.0',
                     'duckdb_version': 'v1.4.3', 'notices': {}}
        for name, key in [('client_host_wasm.wasm', 'module'), ('libduckdb.dylib', 'duckdb')]:
            value = b'fixture component ' + name.encode()
            (self.directory / name).write_bytes(value)
            self.body[key] = {'file': name, 'bytes': len(value), 'sha256': hashlib.sha256(value).hexdigest()}
        for name in ('LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE'):
            value = b'fixture license ' + name.encode()
            (self.directory / name).write_bytes(value)
            self.body['notices'][name] = hashlib.sha256(value).hexdigest()
        (self.directory / 'client_host_wasm.cwasm').write_bytes(IMAGE)
        (self.directory / 'engine-recipe.json').write_bytes(ORIGINAL)
        self.body['compiled_image'] = descriptor('a' * 40, '0.0.0.dev0', self.body['module']['sha256'])
        self.body['engine_recipe'] = {'file': 'engine-recipe.json', 'bytes': len(ORIGINAL),
                                      'sha256': hashlib.sha256(ORIGINAL).hexdigest()}
        self.write_manifest()

    def write_manifest(self):
        (self.directory / 'artifact.json').write_text(json.dumps(self.body))

    def inspect(self):
        return inspect_local_components(self.directory, package_version='0.0.0.dev0')

    def test_installed_reader_keeps_fd_custody_without_buffered_handoff(self):
        path = self.directory / 'reader-original'
        path.write_bytes(b'original input')
        opened = []
        real_open = os.open
        def capture(*args, **kwargs):
            descriptor = real_open(*args, **kwargs)
            opened.append(descriptor)
            return descriptor
        try:
            with patch('actql_sdk._local_distribution.os.open', side_effect=capture), \
                 patch('actql_sdk._local_distribution.os.fdopen',
                       side_effect=MemoryError('Buffered handoff failed')) as buffered:
                self.assertEqual(_read_file(path, maximum=64), b'original input')
            buffered.assert_not_called()
            self.assertEqual(len(opened), 1)
            with self.assertRaises(OSError): os.fstat(opened[0])
        finally:
            # The red probe also owns its actual descriptor; a failed assertion
            # must not leave the fresh fixture's original open.
            for descriptor in opened:
                try: os.close(descriptor)
                except OSError: pass

    def test_input_construction_failure_closes_the_same_actual_fd(self):
        path = self.directory / 'reader-original'
        path.write_bytes(b'original input')
        opened = []
        real_open = os.open
        def capture(*args, **kwargs):
            descriptor = real_open(*args, **kwargs)
            opened.append(descriptor)
            return descriptor
        failure = MemoryError('Checksum construction failed')
        with patch('actql_sdk._local_distribution.os.open', side_effect=capture), \
             patch('actql_sdk._local_distribution.hashlib.sha256', side_effect=failure):
            with self.assertRaises(MemoryError) as caught: _read_file(path, maximum=64)
        self.assertIs(caught.exception, failure)
        self.assertEqual(len(opened), 1)
        with self.assertRaises(OSError): os.fstat(opened[0])

    def test_input_close_loss_keeps_original_and_never_closes_reused_number(self):
        path = self.directory / 'reader-original'
        path.write_bytes(b'original input')
        real_close = os.close
        closed = []
        failure = OSError('Close acknowledgement lost')
        def lose_reply(descriptor):
            real_close(descriptor)
            closed.append(descriptor)
            raise failure
        with patch('actql_sdk._local_distribution.os.close', side_effect=lose_reply) as close:
            with self.assertRaises(LocalComponentReadCleanupPending) as caught:
                _read_file(path, maximum=64)
            original = caught.exception.cleanup_descriptor
            self.assertIs(caught.exception.cleanup_error, failure)
            self.assertIsNone(caught.exception.original_error)
            self.assertTrue(original.close_attempted)
            self.assertFalse(original.closed)
            self.assertEqual(closed, [original.value])
            replacement = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
            try:
                self.assertEqual(replacement, original.value)
                # Observation/cleanup must not issue another close, even if the
                # OS has already reused the old original's descriptor number.
                with self.assertRaises(RuntimeError): original.close()
                self.assertEqual(close.call_count, 1)
                self.assertEqual(os.fstat(replacement).st_ino, path.stat().st_ino)
            finally:
                real_close(replacement)

    def test_input_primary_and_unconfirmed_close_retain_both_original_causes(self):
        path = self.directory / 'reader-original'
        path.write_bytes(b'original input')
        primary = OSError('Original read failed')
        cleanup = OSError('Original close failed')
        with patch('actql_sdk._local_distribution.os.read', side_effect=primary), \
             patch('actql_sdk._local_distribution.os.close', side_effect=cleanup) as close:
            with self.assertRaises(LocalComponentReadCleanupPending) as caught:
                _read_file(path, maximum=64)
            original = caught.exception.cleanup_descriptor
            self.assertIs(caught.exception.original_error, primary)
            self.assertIs(caught.exception.cleanup_error, cleanup)
            self.assertEqual(close.call_count, 1)
            self.assertEqual(os.fstat(original.value).st_ino, path.stat().st_ino)
        # This fixture's original close is known not to have executed. Dispose
        # only the fixture outside the failed production carrier.
        os.close(original.value)

    def test_exact_installed_component_paths_without_engine_import(self):
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine imported')):
            result = self.inspect()
        self.assertEqual(result.module, self.directory / 'client_host_wasm.wasm')
        self.assertEqual(result.duckdb, self.directory / 'libduckdb.dylib')
        self.assertEqual(result.source_sha, 'a' * 40)
        self.assertEqual(result.duckdb_version, 'v1.4.3')

    def test_loaded_module_is_the_same_bounded_digest_checked_bytes(self):
        components = self.inspect()
        expected = b'fixture component client_host_wasm.wasm'
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine imported')):
            self.assertEqual(load_local_module(components), expected)
        components.module.write_bytes(b'x' * len(expected))
        with self.assertRaisesRegex(LocalInstallationError, 'digest mismatched'):
            load_local_module(components)

    def test_module_replacement_symlink_and_growth_reject_before_engine_import(self):
        components = self.inspect()
        original = components.module.read_bytes()
        outside = self.directory / 'outside.wasm'
        outside.write_bytes(original)
        components.module.unlink()
        components.module.symlink_to(outside)
        with patch('actql_sdk._local_core.import_module', side_effect=AssertionError('Engine imported')):
            with self.assertRaisesRegex(LocalInstallationError, 'unavailable'):
                load_local_module(components)
            components.module.unlink()
            with components.module.open('wb') as source:
                source.truncate(32 * 1024 * 1024 + 1)
            with self.assertRaisesRegex(LocalInstallationError, 'size'):
                load_local_module(components)

    def test_manifest_cohort_abi_and_closed_fields_reject(self):
        original = dict(self.body)
        for field, value in [('source_sha', 'a' * 39), ('package_version', 'other'),
                             ('core_abi', 43), ('core_abi', 44), ('core_abi', 45), ('core_abi', 46), ('core_abi', 47), ('core_abi', 48), ('core_abi', 49), ('core_abi', 50), ('core_abi', 51), ('core_abi', 52), ('core_abi', 53), ('core_abi', 54), ('core_abi', 55), ('core_abi', 56), ('core_abi', 57), ('core_abi', 58), ('core_abi', 64), ('core_abi', 65), ('core_abi', 66), ('core_abi', 67), ('core_abi', 68), ('core_abi', 69), ('core_abi', 70), ('core_abi', 71), ('core_abi', 72), ('core_abi', 73), ('core_abi', 74), ('core_abi', 75), ('core_abi', 76), ('core_abi', 77), ('core_abi', True), ('platform', 'linux-x64'),
                             ('wasmtime_version', '37.0.0'), ('duckdb_version', 'unknown'),
                             ('extra', 'ignored')]:
            with self.subTest(field=field, value=value):
                self.body = original | {field: value}
                self.write_manifest()
                with self.assertRaises(LocalInstallationError):
                    self.inspect()
        self.body = original
        self.write_manifest()

    def test_old_raw_only_artifact_and_foreign_image_are_refused_without_engine(self):
        original = dict(self.body)
        del self.body['compiled_image']; del self.body['engine_recipe']
        self.write_manifest()
        with self.assertRaises(LocalInstallationError): self.inspect()
        self.body = original
        for key, value in [('module_sha256', '0' * 64), ('source_sha', '0' * 40),
                           ('wasmtime_version', '37.0.0'), ('runtime_library_sha256', '0' * 64)]:
            with self.subTest(key=key):
                self.body['compiled_image'] = original['compiled_image'] | {key: value}
                self.write_manifest()
                with self.assertRaises(LocalInstallationError): self.inspect()
        self.body = original; self.write_manifest()

    def test_foreign_binary_target_refused_even_when_image_digest_matches(self):
        wrong = IMAGE[:18] + b'\x3e\0' + IMAGE[20:]
        (self.directory / 'client_host_wasm.cwasm').write_bytes(wrong)
        self.body['compiled_image']['sha256'] = hashlib.sha256(wrong).hexdigest()
        self.write_manifest()
        with self.assertRaisesRegex(LocalInstallationError, 'binary target'): self.inspect()

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
        path.write_text(json.dumps(self.body)[:-1] + ', "core_abi": 74}')
        with self.assertRaisesRegex(LocalInstallationError, 'Duplicate'):
            self.inspect()
        path.write_bytes(b' ' * 65537)
        with self.assertRaisesRegex(LocalInstallationError, 'size'):
            self.inspect()

    def test_component_corruption_truncation_and_symlink_reject(self):
        for filename in ('client_host_wasm.wasm', 'client_host_wasm.cwasm', 'engine-recipe.json',
                         'libduckdb.dylib', 'MOONBIT-CORE-NOTICE'):
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
        binding = {'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0', 'core_abi': 83,
                   'artifact_sha256': hashlib.sha256((self.directory / 'artifact.json').read_bytes()).hexdigest(),
                   'host_capacity_sha256': 'c' * 64}
        (self.directory / '_local_release_binding.json').write_text(json.dumps(binding))
        versions = {'actql': '0.0.0.dev0', 'actql-sdk': '0.0.0.dev0', 'actql-local-runtime': '0.0.0.dev0', 'wasmtime': '38.0.0'}
        with patch('actql_sdk._local_distribution.metadata.version', side_effect=lambda name: versions[name]), \
                patch('actql_sdk._local_distribution.resources.files', return_value=self.directory) as resource:
            self.assertEqual(installed_local_components().module, self.directory / 'client_host_wasm.wasm')
            self.assertEqual([call.args for call in resource.call_args_list],
                             [('actql_local_runtime',), ('actql_sdk',)])
            for name in ('actql', 'actql-local-runtime', 'wasmtime'):
                original = versions[name]
                versions[name] = 'wrong'
                with self.assertRaisesRegex(LocalInstallationError, 'incompatible'):
                    installed_local_components()
                versions[name] = original
        with patch('actql_sdk._local_distribution.metadata.version', side_effect=metadata.PackageNotFoundError('runtime')):
            with self.assertRaisesRegex(LocalInstallationError, 'standard actql'):
                installed_local_components()

    def test_runtime_manifest_cannot_rebind_same_version_sdk_and_missing_binding_has_no_fallback(self):
        versions = {'actql': '0.0.0.dev0', 'actql-sdk': '0.0.0.dev0',
                    'actql-local-runtime': '0.0.0.dev0', 'wasmtime': '38.0.0'}
        binding = {'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0', 'core_abi': 83,
                   'artifact_sha256': hashlib.sha256((self.directory / 'artifact.json').read_bytes()).hexdigest(),
                   'host_capacity_sha256': 'c' * 64}
        path = self.directory / '_local_release_binding.json'
        with patch('actql_sdk._local_distribution.metadata.version', side_effect=versions.__getitem__), \
                patch('actql_sdk._local_distribution.resources.files', return_value=self.directory):
            with self.assertRaisesRegex(LocalInstallationError, 'binding is unavailable'):
                installed_local_components()
            path.write_text(json.dumps(binding))
            self.assertEqual(installed_local_components().source_sha, 'a' * 40)
            self.body['source_sha'] = 'b' * 40
            self.body['compiled_image']['source_sha'] = 'b' * 40
            self.write_manifest()
            with self.assertRaisesRegex(LocalInstallationError, 'digest mismatched'):
                installed_local_components()
            binding['artifact_sha256'] = hashlib.sha256((self.directory / 'artifact.json').read_bytes()).hexdigest()
            path.write_text(json.dumps(binding))
            with self.assertRaisesRegex(LocalInstallationError, 'source do not match'):
                installed_local_components()

    def test_platform_binding_requires_same_recipe_without_a_fabricated_capacity(self):
        original = json.loads(ORIGINAL)
        original.update(runtime_allocation='platform', provider_library_sha256=None,
                        provider_library_bytes=None)
        encoded = json.dumps(original).encode()
        (self.directory / 'engine-recipe.json').write_bytes(encoded)
        self.body['engine_recipe'].update(bytes=len(encoded), sha256=hashlib.sha256(encoded).hexdigest())
        self.body['compiled_image'].update(runtime_allocation='platform', provider_library_sha256=None)
        self.write_manifest()
        binding = {'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0', 'core_abi': 83,
                   'artifact_sha256': hashlib.sha256((self.directory / 'artifact.json').read_bytes()).hexdigest(),
                   'runtime_allocation': 'platform'}
        path = self.directory / '_local_release_binding.json'
        path.write_text(json.dumps(binding))
        versions = {'actql': '0.0.0.dev0', 'actql-sdk': '0.0.0.dev0',
                    'actql-local-runtime': '0.0.0.dev0', 'wasmtime': '38.0.0'}
        with patch('actql_sdk._local_distribution.metadata.version', side_effect=versions.__getitem__), \
                patch('actql_sdk._local_distribution.resources.files', return_value=self.directory):
            selected = installed_local_components()
            self.assertEqual(selected.image_recipe.runtime_allocation, 'platform')
            self.assertFalse((self.directory / '_local_host_capacity.json').exists())
            for change in ({'runtime_allocation': 'native-owned'}, {'host_capacity_sha256': 'c' * 64}):
                path.write_text(json.dumps(binding | change))
                with self.assertRaises(LocalInstallationError): installed_local_components()
            path.write_text(json.dumps({k: v for k, v in binding.items() if k != 'runtime_allocation'}
                                      | {'host_capacity_sha256': 'c' * 64}))
            with self.assertRaisesRegex(LocalInstallationError, 'allocation differ'):
                installed_local_components()

    def test_recipe_and_sdk_versions_dependencies_are_one_cohort(self):
        sdk = tomllib.loads((ROOT / 'packages/python-sdk/pyproject.toml').read_text())['project']
        runtime = tomllib.loads((ROOT / 'packages/python-local-runtime/pyproject.toml').read_text())['project']
        product = tomllib.loads((ROOT / 'packages/python-product/pyproject.toml').read_text())['project']
        self.assertEqual(runtime['version'], sdk['version'])
        self.assertEqual(product['version'], sdk['version'])
        self.assertEqual(product['dependencies'],
                         ['actql-sdk==' + sdk['version'], 'actql-local-runtime==' + sdk['version']])
        self.assertNotIn('local', sdk['optional-dependencies'])
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
