"""Source/image metadata controls; these never execute a component or grant use."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import tarfile
import io
import subprocess
import re
import shutil
import struct
from unittest.mock import patch

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

    def test_export_refusal_observes_both_symbol_tables_and_dynamic_metadata_first(self):
        observed=[]
        def execute(arguments,text):
            self.assertTrue(text);observed.append(arguments)
            return ''
        with self.assertRaisesRegex(ValueError,'Unexpected Linux Crypto component exports'):
            P.inspect_linux_component(self.library,execute=execute)
        self.assertEqual(observed,[['/usr/bin/nm','-D','--defined-only',str(self.library)],
            ['/usr/bin/nm','-D','--undefined-only',str(self.library)],
            ['/usr/bin/readelf','--dynamic','--wide',str(self.library)]])

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
                                 ('imports', '\nU EVP_sha256@OPENSSL_3.0.0'),
                                 ('imports', '\nU _ITM_registerTMCloneTable'),
                                 ('imports', '\nw foreign_runtime')):
            with self.subTest(extra=extra):
                old = getattr(self, attribute)
                setattr(self, attribute, old + extra)
                with self.assertRaises(ValueError): self.inspect()
                setattr(self, attribute, old)

    def test_only_selected_optional_weak_c_runtime_references_are_accepted(self):
        self.imports += '\n' + '\n'.join('w ' + name for name in P.LINUX_WEAK_C_RUNTIME_IMPORTS)
        self.inspect()

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


class LinuxApiCompilerVisibility(unittest.TestCase):
    def test_real_api_declarations_keep_all_fourteen_definitions_default_visible(self):
        # Only real implementation signatures and the real public header are
        # compiled. Bodies trap and are never linked or executed as Crypto.
        compiler=shutil.which('clang')
        self.assertIsNotNone(compiler,'Selected LLVM compiler required')
        implementation=(P.SOURCE/'component.c').read_text()
        definitions=[]
        for name in P.EXPORTS:
            signatures=re.findall(r'^([^;{}\n]*?\b'+re.escape(name)+r'\s*\([^;{}]*\))\s*\{',implementation,re.M)
            self.assertEqual(len(signatures),1,name)
            definitions.append(signatures[0]+' { __builtin_trap(); }')
        with tempfile.TemporaryDirectory() as raw:
            root=Path(raw);source=root/'visibility.c';obj=root/'visibility.o'
            source.write_text('#include "component.h"\n'+'\n'.join(definitions)+'\n')
            command=[compiler,'--target=x86_64-unknown-linux-gnu','-ffreestanding',
                '-std=c11','-O2','-fvisibility=hidden','-Wall','-Wextra','-Werror',
                '-Wno-unused-parameter','-I',str(P.SOURCE),'-c',str(source),'-o',str(obj)]
            compiled=subprocess.run(command,capture_output=True,text=True,timeout=30)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            image=obj.read_bytes()
        self.assertEqual(image[:7],b'\x7fELF\x02\x01\x01')
        self.assertEqual(int.from_bytes(image[18:20],'little'),62)
        offset=struct.unpack_from('<Q',image,40)[0]
        width,count=struct.unpack_from('<HH',image,58)
        sections=[struct.unpack_from('<IIQQQQIIQQ',image,offset+index*width) for index in range(count)]
        symbols={}
        for section in sections:
            if section[1]!=2:continue
            table=sections[section[6]];strings=image[table[4]:table[4]+table[5]]
            for position in range(section[4],section[4]+section[5],section[9]):
                name,info,other,index,_,_=struct.unpack_from('<IBBHQQ',image,position)
                name=strings[name:strings.find(b'\0',name)].decode()
                if name in P.EXPORTS:symbols[name]=(info>>4,info&15,other&3,index!=0)
        self.assertEqual(set(symbols),set(P.EXPORTS))
        self.assertEqual(symbols,{name:(1,2,0,True) for name in P.EXPORTS})


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

    def test_another_startup_or_weak_runtime_profile_cannot_replace_the_selected_one(self):
        for key, value in (('link_startup', 'none'), ('weak_c_runtime_imports', ['foreign_runtime'])):
            with self.subTest(key=key):
                original = self.selected[key]; self.selected[key] = value
                with self.assertRaisesRegex(ValueError, 'Unselected Linux Crypto source profile'):
                    self.select()
                self.selected[key] = original

    def test_compiler_observation_cannot_replace_an_overlapping_original_header_pin(self):
        header = self.root / 'include/openssl/original.h'
        pinned = {str(header): P.original(header)}
        header.write_bytes(b'changed during the original compiler invocation')
        compiled = {str(header): P.original(header)}
        with self.assertRaisesRegex(ValueError, 'Original Crypto build input changed'):
            P.verify_original_inputs(pinned, compiled)


class CompatibleDarwinSource(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.archive = self.root / 'source.tar.gz'

    def write_archive(self, members):
        with tarfile.open(self.archive, 'w:gz') as output:
            for name, data, kind in members:
                item = tarfile.TarInfo(name); item.type = kind
                item.size = len(data) if kind == tarfile.REGTYPE else 0
                output.addfile(item, io.BytesIO(data) if item.size else None)
        return P.original(self.archive)

    def test_original_source_members_keep_their_bytes_without_a_build_or_install(self):
        expected = self.write_archive([('openssl-original/crypto/original.c', b'original C', tarfile.REGTYPE)])
        records = P.source_archive_members(self.archive, expected, 'openssl-original', self.root / 'stage')
        self.assertEqual(records, [{'path': 'openssl-original/crypto/original.c',
            'bytes': 10, 'sha256': hashlib.sha256(b'original C').hexdigest()}])
        self.assertEqual((self.root / 'stage/openssl-original/crypto/original.c').read_bytes(), b'original C')

    def test_archive_identity_and_links_or_escaping_members_refuse(self):
        expected = self.write_archive([('openssl-original/crypto/original.c', b'original C', tarfile.REGTYPE)])
        self.archive.write_bytes(self.archive.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'source archive mismatch'):
            P.source_archive_members(self.archive, expected, 'openssl-original', self.root / 'stage')
        for name, kind in (('openssl-original/link', tarfile.SYMTYPE),
                           ('openssl-original/../../foreign', tarfile.REGTYPE),
                           ('/foreign', tarfile.REGTYPE)):
            with self.subTest(name=name):
                expected = self.write_archive([(name, b'foreign', kind)])
                with self.assertRaisesRegex(ValueError, 'archive member'):
                    P.source_archive_members(self.archive, expected, 'openssl-original', self.root / 'stage')

    def test_original_member_and_total_bounds_are_checked_before_publication(self):
        expected = self.write_archive([('openssl-original/crypto/original.c', b'original C', tarfile.REGTYPE)])
        for extra in ({'maximum_member_bytes': 9}, {'unpacked_bytes': 9}):
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, 'Oversized'):
                P.source_archive_members(self.archive, {**expected, **extra},
                    'openssl-original', self.root / 'bounded')
        records = P.source_archive_members(self.archive,
            {**expected, 'maximum_member_bytes': 10, 'unpacked_bytes': 10, 'members': 1, 'files': 1},
            'openssl-original', self.root / 'exact')
        self.assertEqual(len(records), 1)

    def test_compatible_profile_does_not_relabel_the_existing_homebrew_archive(self):
        recipe = json.loads((P.SOURCE / 'source.json').read_bytes())
        self.assertEqual(recipe['minimum_macos'], '26.0')
        self.assertEqual(recipe['candidate_static_input']['sha256'],
            '074d179c9a8361e8f9143eb89a07954f4a251061dfb98a06c53f84153ed8d1b7')
        profile = recipe['source_builds']['darwin-arm64-macos11']
        self.assertEqual(profile['minimum_macos'], '11.0')
        self.assertEqual(profile['target'], 'aarch64-apple-darwin')
        self.assertEqual(profile['configure'], ['darwin64-arm64-cc', 'no-shared', 'no-tests', 'no-module'])
        self.assertEqual(recipe['upstream']['sha256'],
            'aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f')
        with patch.object(P.platform, 'system', return_value='Linux'):
            with self.assertRaisesRegex(ValueError, 'selected Darwin arm64'):
                P.produce_darwin_source(self.root / 'output', Path('/foreign/cc'), Path('/foreign/sdk'), 60)

    def test_original_multicall_tool_alias_keeps_its_invocation_name_and_canonical_bytes(self):
        binary = self.root / 'libtool'; binary.write_bytes(b'original selected tool')
        alias = self.root / 'ranlib'; alias.symlink_to(binary)
        tools = {'ranlib': alias}
        inputs, aliases = P.original_tool_inputs(tools)
        self.assertEqual(tools['ranlib'], alias)
        self.assertEqual(inputs, {str(binary): P.original(binary)})
        P.verify_tool_aliases(aliases)
        replacement = self.root / 'foreign'; replacement.write_bytes(b'foreign tool')
        alias.unlink(); alias.symlink_to(replacement)
        with self.assertRaisesRegex(ValueError, 'tool alias changed'):
            P.verify_tool_aliases(aliases)


class DarwinCompilerInputPins(unittest.TestCase):
    def test_actual_compiler_boundary_cannot_replace_a_pinned_public_header(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            original_source = P.SOURCE
            source = root / 'source'; source.mkdir()
            recipe = json.loads((original_source / 'source.json').read_bytes())
            for name in recipe['local']:
                path = source / name; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((original_source / name).read_bytes())
            openssl = root / 'openssl'
            files = {'.brew/openssl@3.rb': b'formula', 'INSTALL_RECEIPT.json': b'receipt',
                     'lib/libcrypto.a': b'original static archive', 'LICENSE.txt': b'license',
                     'include/openssl/original.h': b'original header'}
            for name, data in files.items():
                path = openssl / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            pinned = recipe['candidate_static_input']
            pinned.update(P.original(openssl / 'lib/libcrypto.a'))
            pinned['formula_sha256'] = P.original(openssl / '.brew/openssl@3.rb')['sha256']
            pinned['receipt_sha256'] = P.original(openssl / 'INSTALL_RECEIPT.json')['sha256']
            header = openssl / 'include/openssl/original.h'
            pinned['header_count'] = 1
            pinned['header_census_sha256'] = hashlib.sha256(json.dumps([
                {'path': 'openssl/original.h', **P.original(header)}],
                sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            recipe['license_sha256'] = P.original(openssl / 'LICENSE.txt')['sha256']
            (source / 'source.json').write_text(json.dumps(recipe))
            compiler = root / 'compiler'; compiler.write_bytes(b'compiler port')
            sdk = root / 'SDK'; sdk.mkdir()
            def execute(arguments, text, **options):
                if arguments[0] == 'git':
                    return '' if arguments[1] == 'status' else 'a' * 40 + '\n'
                if '-l' in arguments:
                    return 'cmd LC_BUILD_VERSION\ncmdsize 24\nplatform 1\nminos 26.0\n'
                if '-L' in arguments:
                    return 'component:\n@rpath/libactql_crypto_component.dylib (version)\n/usr/lib/libSystem.B.dylib (version)\n'
                if '-gU' in arguments:
                    return '\n'.join('0000 T _' + name for name in P.EXPORTS)
                return '\n'.join('_' + name for name in P.PROVIDER_IMPORTS)
            for changed in (False, True):
                with self.subTest(changed=changed):
                    header.write_bytes(b'original header')
                    output = root / ('changed' if changed else 'control')
                    def compile_port(arguments, **options):
                        library = Path(arguments[arguments.index('-o') + 1])
                        library.write_bytes(b'Source-only library port; never executable')
                        Path(arguments[arguments.index('-MF') + 1]).write_text(str(library) + ': ' + str(header) + '\n')
                        if changed: header.write_bytes(b'changed during compiler invocation')
                        return subprocess.CompletedProcess(arguments, 0)
                    with patch.object(P, 'SOURCE', source), patch.object(P.platform, 'system', return_value='Darwin'), \
                         patch.object(P.platform, 'machine', return_value='arm64'), \
                         patch.object(P.subprocess, 'check_output', side_effect=execute), \
                         patch.object(P.subprocess, 'run', side_effect=compile_port):
                        if changed:
                            with self.assertRaisesRegex(ValueError, 'Original Crypto build input changed'):
                                P.produce(output, openssl, compiler, sdk)
                            self.assertFalse((output / 'producer.json').exists())
                        else:
                            result = P.produce(output, openssl, compiler, sdk)
                            self.assertIn(str(header), result['inputs'])
                            self.assertIn(str(header), result['compiled_inputs'])


if __name__ == '__main__':
    unittest.main()
