"""Source/image metadata controls; these never execute a component or grant use."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('crypto_original',
    Path(__file__).with_name('produce-native-crypto-component.py'))
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class LinuxCryptoImage(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.library = self.root / P.LINUX_LIBRARY
        self.header = bytearray(64)
        self.header[:7] = b'\x7fELF\x02\x01\x01'
        for offset, size, value in ((16, 2, 3), (18, 2, 62), (20, 4, 1), (52, 2, 64)):
            self.header[offset:offset+size] = value.to_bytes(size, 'little')
        self.library.write_bytes(self.header)
        self.definitions = '\n'.join('0000 T ' + name for name in P.EXPORTS)
        self.imports = '\n'.join('U ' + name for name in P.PROVIDER_IMPORTS) + '\nU malloc@GLIBC_2.2.5\n'
        self.dynamic = ('(NEEDED) Shared library: [libc.so.6]\n'
                        '(SONAME) Library soname: [libactql_crypto_component.so]\n')

    def inspect(self):
        def execute(arguments, text):
            self.assertTrue(text)
            if arguments[0] == '/usr/bin/nm':
                return self.definitions if '--defined-only' in arguments else self.imports
            self.assertEqual(arguments[:3], ['/usr/bin/readelf', '--dynamic', '--wide'])
            return self.dynamic
        return P.inspect_linux_component(self.library, execute=execute)

    def test_original_x64_profile_has_only_the_same_process_provider_and_closed_exports(self):
        observed = self.inspect()
        self.assertEqual(observed['target'], 'x86_64-unknown-linux-gnu')
        self.assertEqual(observed['provider_imports'], sorted(P.PROVIDER_IMPORTS))
        self.assertEqual(observed['dependencies'], ['libc.so.6'])

    def test_foreign_image_refuses_before_inspection_tools(self):
        for offset, value in ((4, 1), (5, 2), (18, 183), (16, 2)):
            with self.subTest(offset=offset):
                raw = self.header.copy(); raw[offset] = value
                self.library.write_bytes(raw)
                with self.assertRaisesRegex(ValueError, 'ELF64 little-endian x86-64'):
                    self.inspect()

    def test_provider_exports_and_unversioned_crypto_imports_cannot_expand(self):
        for attribute, extra in (('definitions', '\n0000 T EVP_sha256'),
                                 ('imports', '\nU actql_other_provider'),
                                 ('imports', '\nU EVP_sha256'),
                                 ('imports', '\nU EVP_sha256@OPENSSL_3.0.0')):
            with self.subTest(extra=extra):
                old = getattr(self, attribute)
                setattr(self, attribute, old + extra)
                with self.assertRaises(ValueError): self.inspect()
                setattr(self, attribute, old)

    def test_shared_crypto_and_ambient_search_paths_cannot_substitute_the_static_original(self):
        for extra in ('(NEEDED) Shared library: [libcrypto.so.3]',
                      '(NEEDED) Shared library: [libactql_native_control.so]',
                      '(RUNPATH) Library runpath: [/foreign]',
                      '(NEEDED) Shared library: [libc.so.6]'):
            with self.subTest(extra=extra):
                original = self.dynamic
                self.dynamic += extra
                with self.assertRaises(ValueError): self.inspect()
                self.dynamic = original


class LinuxCryptoSources(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        recipe = json.loads((P.SOURCE / 'source.json').read_bytes())
        self.selected = copy.deepcopy(recipe['source_targets'][P.LINUX_TARGET])
        for item, data in ((self.selected['archive'], b'original static archive'),
                           (self.selected['license'], b'original copyright')):
            path = self.root / item['path']; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data); item.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
        headers = []
        for directory, name in zip(self.selected['header_roots'], ('original.h', 'configuration.h')):
            path = self.root / directory / name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'original public header')
            headers.append({'path': str(path.relative_to(self.root / 'include')),
                            **P.original(path)})
        self.selected['header_count'] = 2
        self.selected['header_census_sha256'] = hashlib.sha256(json.dumps(
            sorted(headers, key=lambda item: item['path']), sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        self.packages = 'libssl-dev\t3.0.13-0ubuntu3.16\tamd64\nlibssl3t64\t3.0.13-0ubuntu3.16\tamd64\n'

    def select(self):
        return P.linux_source_inputs(self.root, self.selected,
            query=lambda arguments, text: self.packages)

    def test_static_archive_headers_and_official_package_version_target_are_all_required(self):
        self.assertEqual(len(self.select()), 4)
        for packages in (self.packages.replace('amd64', 'arm64'),
                         self.packages.replace('3.0.13-0ubuntu3.16', '3.0.13-0ubuntu3'),
                         self.packages + self.packages):
            old = self.packages; self.packages = packages
            with self.assertRaisesRegex(ValueError, 'package version/target'): self.select()
            self.packages = old

    def test_changed_archive_header_or_census_refuses_without_another_source(self):
        archive = self.root / self.selected['archive']['path']
        archive.write_bytes(b'changed static archive')
        with self.assertRaisesRegex(ValueError, 'member mismatch'): self.select()
        archive.write_bytes(b'original static archive')
        self.selected['header_census_sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'header membership'): self.select()


if __name__ == '__main__':
    unittest.main()
