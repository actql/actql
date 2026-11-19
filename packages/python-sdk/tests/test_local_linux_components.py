"""Linux component identity and loader correspondence; no native execution."""
from copy import deepcopy
from hashlib import sha256
from pathlib import Path
import json
import importlib.util
import os
import re
import struct
import subprocess
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from image_fixture import ENGINE, linux_version_library
from actql_sdk._local_distribution import (
    LocalInstallationError, _inspect_local_components_for_packaging, inspect_local_components,
    _execution_component_platform, installed_local_components,
)
from actql_sdk._local_engine import _platform_runtime_library
from actql_sdk._local_image_recipe import _image_descriptor, _recipe_from_original


class LinuxComponentTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.engine = deepcopy(ENGINE)
        self.engine.update(target='x86_64-unknown-linux-gnu', cpu_features=['x86_64-baseline'])
        self.library = b'Independent Linux runtime fixture; never loaded'
        self.original = {
            'wasmtime_version': '38.0.0', 'runtime_library_sha256': sha256(self.library).hexdigest(),
            'runtime_library_bytes': len(self.library), 'provider_library_sha256': None,
            'provider_library_bytes': None, 'engine_body': self.engine,
            'image_bytes_limit': 1024, 'runtime_allocation': 'platform',
        }
        # Header-only x86-64 ELF fixture, never compiled or deserialized.
        self.image = b'\x7fELF\x02\x01\x01' + b'\0' * 11 + b'\x3e\x00' + b'\0' * 44
        self.body = {
            'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0', 'platform': 'linux-x64',
            'core_abi': 89, 'wasmtime_version': '38.0.0', 'duckdb_version': 'v1.4.3', 'notices': {},
        }
        for name, key, value in (
                ('client_host_wasm.wasm', 'module', b'Independent non-executable Wasm fixture'),
                ('libduckdb.so', 'duckdb', b'Independent non-executable DuckDB fixture')):
            (self.root / name).write_bytes(value)
            self.body[key] = {'file': name, 'bytes': len(value), 'sha256': sha256(value).hexdigest()}
        self.body['compiled_image'] = {
            'source_sha': 'a' * 40, 'package_version': '0.0.0.dev0',
            'module_sha256': self.body['module']['sha256'], 'core_abi': 89,
            'wasmtime_version': '38.0.0', 'runtime_library_sha256': sha256(self.library).hexdigest(),
            'provider_library_sha256': None, 'platform': 'linux-x64', 'engine_body': self.engine,
            'engine_sha256': sha256(json.dumps(self.engine, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
            'file': 'client_host_wasm.cwasm', 'bytes': len(self.image), 'sha256': sha256(self.image).hexdigest(),
            'runtime_allocation': 'platform',
        }
        for name in ('LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE'):
            value = b'Independent notice fixture ' + name.encode()
            (self.root / name).write_bytes(value)
            self.body['notices'][name] = sha256(value).hexdigest()
        self.write()

    def write(self):
        original = json.dumps(self.original).encode()
        (self.root / 'engine-recipe.json').write_bytes(original)
        self.body['engine_recipe'] = {'file': 'engine-recipe.json', 'bytes': len(original),
                                      'sha256': sha256(original).hexdigest()}
        (self.root / 'client_host_wasm.cwasm').write_bytes(self.image)
        (self.root / 'artifact.json').write_text(json.dumps(self.body))

    def recipe(self):
        return _recipe_from_original(json.dumps(self.original).encode(), source_sha='a' * 40,
            package_version='0.0.0.dev0', module_sha256=self.body['module']['sha256'])

    def test_linux_component_correspondence_uses_original_recipe_and_binary_target_without_load(self):
        with patch('actql_sdk._local_distribution.sys.platform', 'linux'), \
             patch('actql_sdk._local_distribution.platform.machine', return_value='x86_64'), \
             patch('actql_sdk._local_distribution.os.confstr', return_value='glibc 2.39'), \
             patch('ctypes.CDLL', side_effect=AssertionError('No native load from metadata')):
            selected = inspect_local_components(self.root, package_version='0.0.0.dev0')
        self.assertEqual(selected.duckdb, self.root / 'libduckdb.so')
        self.assertEqual(selected.image_recipe, self.recipe())
        self.assertEqual(selected.source_sha, 'a' * 40)

    def test_release_and_image_each_refuse_independent_stale_abi_without_native_load(self):
        # Independent fixed expectations: declared ABI89 is the current cohort;
        # prior ABI88 remains incompatible in either release or image metadata.
        for release_abi, image_abi in ((88, 89), (89, 88), (88, 88)):
            with self.subTest(release_abi=release_abi, image_abi=image_abi):
                self.body['core_abi'] = release_abi
                self.body['compiled_image']['core_abi'] = image_abi
                self.write()
                expected = ('release cohort is incompatible' if release_abi == 88
                            else 'image does not match the selected recipe')
                with patch('actql_sdk._local_distribution.sys.platform', 'linux'), \
                     patch('actql_sdk._local_distribution.platform.machine', return_value='x86_64'), \
                     patch('actql_sdk._local_distribution.os.confstr', return_value='glibc 2.39'), \
                     patch('ctypes.CDLL', side_effect=AssertionError('No native load from metadata')):
                    with self.assertRaisesRegex(LocalInstallationError, expected):
                        inspect_local_components(self.root, package_version='0.0.0.dev0')

    def test_linux_manifest_cannot_relabel_arm_image(self):
        self.image = self.image[:18] + b'\xb7\x00' + self.image[20:]
        self.body['compiled_image']['sha256'] = sha256(self.image).hexdigest()
        self.write()
        with self.assertRaises(LocalInstallationError):
            _inspect_local_components_for_packaging(self.root, target_platform='linux-x64',
                package_version='0.0.0.dev0')

    def test_linux_platform_profile_refuses_mac_engine_and_owned_provider(self):
        mac = self.original | {'engine_body': deepcopy(ENGINE)}
        recipe = _recipe_from_original(json.dumps(mac).encode(), source_sha='a' * 40,
            package_version='0.0.0.dev0', module_sha256=self.body['module']['sha256'])
        descriptor = self.body['compiled_image'] | {'engine_body': deepcopy(ENGINE),
            'engine_sha256': sha256(json.dumps(ENGINE, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}
        with self.assertRaises(LocalInstallationError):
            _image_descriptor(descriptor, recipe)
        original = self.original | {'runtime_allocation': 'native-owned',
            'provider_library_sha256': 'c' * 64, 'provider_library_bytes': 23}
        # Native-owned has a distinct physical supplier. Adding the ordinary
        # Linux profile must not turn that absent supplier into a fallback.
        original.pop('runtime_allocation')
        with self.assertRaises(LocalInstallationError):
            _recipe_from_original(json.dumps(original).encode(), source_sha='a' * 40,
                package_version='0.0.0.dev0', module_sha256=self.body['module']['sha256'])

    def test_platform_runtime_selects_exact_linux_dependency_member_before_load(self):
        root = self.root / 'wasmtime'
        library = root / 'linux-x86_64/_libwasmtime.so'
        library.parent.mkdir(parents=True)
        library.write_bytes(self.library)
        class Distribution:
            version = '38.0.0'
            def locate_file(self, name):
                if name != 'wasmtime':
                    raise AssertionError('Foreign dependency lookup')
                return root
        with patch('actql_sdk._local_engine.metadata.distribution', return_value=Distribution()), \
             patch('ctypes.CDLL', side_effect=AssertionError('No native load from metadata')):
            self.assertEqual(_platform_runtime_library(self.recipe()), library)
            library.write_bytes(b'Changed original dependency')
            with self.assertRaises(LocalInstallationError):
                _platform_runtime_library(self.recipe())

    def test_linux_host_floor_and_musl_refuse_before_dependency_discovery(self):
        with patch('actql_sdk._local_distribution.sys.platform', 'linux'), \
             patch('actql_sdk._local_distribution.platform.machine', return_value='x86_64'), \
             patch('actql_sdk._local_distribution.metadata.version', side_effect=AssertionError('No dependency lookup')), \
             patch('actql_sdk._local_distribution.resources.files', side_effect=AssertionError('No resource lookup')):
            for value in ('glibc 2.27', 'musl 1.2', None, 'glibc 2.28.0'):
                with self.subTest(libc=value), patch('actql_sdk._local_distribution.os.confstr', return_value=value):
                    with self.assertRaises(LocalInstallationError):
                        installed_local_components()
            with patch('actql_sdk._local_distribution.os.confstr', return_value='glibc 2.28'):
                self.assertEqual(_execution_component_platform(), 'linux-x64')

    def test_missing_linux_cpp_dependency_keeps_original_loader_cause_without_retry(self):
        from actql_sdk._local_duckdb import DuckDBLibrary
        path = self.root / 'libduckdb.so'
        original = path.read_bytes()
        cause = OSError('libstdc++.so.6: version GLIBCXX_3.4.22 not found')
        with patch('actql_sdk._local_duckdb.C.CDLL', side_effect=cause) as load, \
             patch('actql_sdk._local_duckdb.bind_duckdb', side_effect=AssertionError('No ABI binding after failed load')):
            with self.assertRaises(OSError) as observed:
                DuckDBLibrary(path, digest=sha256(original).hexdigest(), version='v1.4.3')
        self.assertIs(observed.exception, cause)
        load.assert_called_once_with(str(path))


class LinuxLibraryMetadataTests(unittest.TestCase):
    def setUp(self):
        temporary = TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name) / 'libduckdb.so'
        self.header = linux_version_library()
        self.path.write_bytes(self.header)
        script = Path(__file__).resolve().parents[3] / 'scripts/prepare-python-local-runtime.py'
        spec = importlib.util.spec_from_file_location('linux_component_recipe_under_test', script)
        self.recipe = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.recipe)
        self.dynamic = '\n'.join(f'(NEEDED) Shared library: [{name}]'
            for name in ('libc.so.6', 'libgcc_s.so.1', 'libstdc++.so.6'))
        self.versions = 'Name: GLIBC_2.25\nName: GLIBCXX_3.4.22\nName: CXXABI_1.3.8\n'
        self.symbol_bytes = 0

    def inspect(self):
        self.path.write_bytes(linux_version_library(
            tuple(re.findall(r'Name: (\S+)', self.versions)), symbol_bytes=self.symbol_bytes))
        def execute(args, *, stdout, **options):
            self.assertEqual(args[0], 'readelf')
            descriptor, = options['pass_fds']
            self.assertEqual(args[2:], ['--', '/dev/fd/' + str(descriptor)])
            self.assertEqual(os.fstat(descriptor).st_ino, self.path.stat().st_ino)
            self.assertEqual(options['env']['LC_ALL'], 'C')
            stdout.write((self.dynamic if args[1] == '--dynamic' else self.versions).encode())
            return subprocess.CompletedProcess(args, 0)
        with patch.object(self.recipe.subprocess, 'run', side_effect=execute), \
             patch('ctypes.CDLL', side_effect=AssertionError('No native load')):
            return self.recipe.linux_library_target(self.path,
                original_sha256=sha256(self.path.read_bytes()).hexdigest(), original_bytes=self.path.stat().st_size)

    def test_linux_binary_profile_keeps_glibc_and_cpp_requirements_separate(self):
        actual = self.inspect()
        self.assertEqual(actual['required_versions'], {
            'GLIBC': [2, 25, 0], 'GLIBCXX': [3, 4, 22], 'CXXABI': [1, 3, 8]})
        self.assertEqual(actual['dependencies'], ['libc.so.6', 'libgcc_s.so.1', 'libstdc++.so.6'])
        self.assertIs(actual['native_loaded'], False)

    def test_large_symbol_index_does_not_expand_version_requirement_capture(self):
        self.symbol_bytes = 2 * 1024 * 1024
        self.versions = 'Version symbols: ' + '2 (GLIBC_2.25) ' * 100000 + '\n' + self.versions
        actual = self.inspect()
        self.assertEqual(actual['required_versions'], {
            'GLIBC': [2, 25, 0], 'GLIBCXX': [3, 4, 22], 'CXXABI': [1, 3, 8]})
        self.assertIs(actual['native_loaded'], False)

    def test_malformed_requirement_offsets_counts_and_names_refuse(self):
        original = linux_version_library()
        needs_header = 64 + 2 * 64
        needs_offset = struct.unpack_from('<Q', original, needs_header + 24)[0]
        for offset, encoding, value in (
                (40, '<Q', len(original) + 1),
                (needs_header + 40, '<I', 4),
                (needs_header + 32, '<Q', 1048577),
                (needs_offset + 2, '<H', 4097),
                (needs_offset + 8, '<I', 0),
                (needs_offset + 12, '<I', 16),
                (needs_offset + 24, '<I', len(original)),
                (needs_offset + 16 + 32 + 12, '<I', 16)):
            with self.subTest(offset=offset, value=value):
                changed = bytearray(original)
                struct.pack_into(encoding, changed, offset, value)
                self.path.write_bytes(changed)
                with patch.object(self.recipe.subprocess, 'run') as execute:
                    execute.side_effect = lambda args, **options: options['stdout'].write(self.dynamic.encode())
                    with self.assertRaises(ValueError):
                        self.recipe.linux_library_target(self.path,
                            original_sha256=sha256(changed).hexdigest(), original_bytes=len(changed))
        # A last name without its terminator cannot borrow unrelated table bytes.
        changed = bytearray(original)
        strings_end = struct.unpack_from('<Q', original, 64 + 64 + 24)[0] + struct.unpack_from('<Q', original, 64 + 64 + 32)[0]
        changed[strings_end - 1] = ord('X')
        self.path.write_bytes(changed)
        with self.path.open('rb') as retained, self.assertRaises(ValueError):
            self.recipe._linux_version_requirements(retained.fileno(), bytes(changed[:64]), len(changed))

    def test_private_unknown_and_newer_cpp_requirements_remain_refused(self):
        for name in ('GLIBC_PRIVATE', 'GLIBC_ABI_DT_RELR', 'GLIBC_2.29',
                     'GLIBCXX_3.4.23', 'CXXABI_1.3.9'):
            with self.subTest(name=name):
                self.versions = 'Name: GLIBC_2.25\nName: ' + name + '\n'
                with self.assertRaises(ValueError):
                    self.inspect()

    def test_linux_binary_profile_refuses_foreign_target_or_unavailable_linkage(self):
        self.path.write_bytes(self.header[:18] + b'\xb7\x00' + self.header[20:])
        with patch.object(self.recipe.subprocess, 'run', side_effect=AssertionError('No foreign tool invocation')):
            with self.assertRaises(ValueError):
                self.recipe.linux_library_target(self.path,
                    original_sha256=sha256(self.path.read_bytes()).hexdigest(), original_bytes=self.path.stat().st_size)
        self.path.write_bytes(self.header)
        original_dynamic, original_versions = self.dynamic, self.versions
        for dynamic, versions in (
                (original_dynamic + '\n(NEEDED) Shared library: [../foreign.so]', original_versions),
                (original_dynamic + '\n(RUNPATH) Library runpath: [/foreign]', original_versions),
                (original_dynamic, original_versions + 'Name: GLIBC_2.29\n'),
                (original_dynamic, original_versions + 'Name: GLIBCXX_3.4.23\n'),
                (original_dynamic, 'x' * 1048577)):
            with self.subTest(dynamic=dynamic, version_length=len(versions)):
                self.dynamic, self.versions = dynamic, versions
                with self.assertRaises(ValueError):
                    self.inspect()

    def test_linux_metadata_keeps_original_fd_and_refuses_path_replacement(self):
        original = self.path.read_bytes()
        retained = self.path.with_name('retained-original.so')
        observed = []
        def replace(args, *, stdout, **options):
            descriptor, = options['pass_fds']
            observed.append(descriptor)
            self.assertEqual(os.pread(descriptor, len(original), 0), original)
            self.path.rename(retained)
            self.path.write_bytes(original)
            # Equal bytes under a new inode are not the captured original.
            stdout.write(self.dynamic.encode())
            return subprocess.CompletedProcess(args, 0)
        with patch.object(self.recipe.subprocess, 'run', side_effect=replace):
            with self.assertRaises(LocalInstallationError):
                self.recipe.linux_library_target(self.path,
                    original_sha256=sha256(original).hexdigest(), original_bytes=len(original))
        self.assertEqual(len(observed), 1)
        self.assertEqual(retained.read_bytes(), original)
        with self.assertRaises(OSError):
            os.fstat(observed[0])


if __name__ == '__main__':
    unittest.main()
