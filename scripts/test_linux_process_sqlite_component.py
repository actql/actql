"""ELF selection counters only; synthetic tool output is not binding/admission."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('linux_process_sqlite',
    Path(__file__).with_name('produce-python-sqlite-component.py'))
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class LinuxProcessSQLiteTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.library = self.root / P.LINUX_LIBRARY
        header = bytearray(64)
        header[:7] = b'\x7fELF\x02\x01\x01'
        header[16:18] = (3).to_bytes(2, 'little')
        header[18:20] = (183).to_bytes(2, 'little')
        header[20:24] = (1).to_bytes(4, 'little')
        header[52:54] = (64).to_bytes(2, 'little')
        self.library.write_bytes(header)
        self.observations = {
            ('nm', '-D', '--defined-only'): ''.join('00000000 T ' + name[1:] + '\n' for name in sorted(P.EXPORTS)),
            ('nm', '-D', '--undefined-only'): ''.join('U ' + name + '\n' for name in sorted(P.PROCESS_IMPORTS)) + 'U memcpy@GLIBC_2.17\n',
            ('readelf', '--dynamic', '--wide'): '(NEEDED) Shared library: [libc.so.6]\n(SONAME) Library soname: [' + P.LINUX_LIBRARY + ']\n',
            ('readelf', '--program-headers', '--wide'): 'Type Offset VirtAddr\nLOAD 0 0\n',
        }

    def inspect(self, observations=None, **selection):
        selected = self.observations if observations is None else observations
        def execute(command, **kwargs):
            self.assertEqual(command[-1], str(self.library))
            return selected[(Path(command[0]).name, *command[1:-1])]
        return P.inspect_linux_process_component(self.library, execute=execute, **selection)

    def test_selected_x64_elf_has_its_own_machine_and_target(self):
        header = bytearray(self.library.read_bytes())
        header[18:20] = (62).to_bytes(2, 'little')
        self.library.write_bytes(header)
        result = self.inspect(process_target='linux-x64-gnu')
        self.assertEqual(result['target'], 'x86_64-unknown-linux-gnu')
        self.assertEqual(result['elf_machine'], 62)
        self.assertEqual(result['provider_imports'], sorted(P.PROCESS_IMPORTS))
        self.assertEqual(result['system_dependencies'], ['libc.so.6'])
        self.assertFalse(result['automatic_initializers'])
        self.assertFalse(result['component_tls'])

    def test_selected_elf_and_closed_original_imports_are_inspected_without_load(self):
        result = self.inspect()
        self.assertEqual(result['target'], 'aarch64-unknown-linux-gnu')
        self.assertEqual(result['provider_imports'], sorted(P.PROCESS_IMPORTS))
        self.assertEqual(result['system_dependencies'], ['libc.so.6'])
        self.assertFalse(result['automatic_initializers'])
        self.assertFalse(result['component_tls'])

    def test_wrong_class_endianness_machine_or_shared_kind_refuses_before_tools(self):
        original = self.library.read_bytes()
        for offset, value in ((0, 0), (4, 1), (5, 2), (7, 6), (16, 2), (18, 62), (20, 2), (52, 0)):
            with self.subTest(offset=offset):
                changed = bytearray(original); changed[offset] = value
                self.library.write_bytes(changed)
                with self.assertRaisesRegex(ValueError, 'ELF64'):
                    self.inspect()
        self.library.write_bytes(original)

    def test_x64_rejects_arm_or_other_elf_metadata_before_tools(self):
        original = bytearray(self.library.read_bytes())
        original[18:20] = (62).to_bytes(2, 'little')
        for offset, value in ((0, 0), (4, 1), (5, 2), (7, 6), (16, 2), (18, 183), (20, 2), (52, 0)):
            with self.subTest(offset=offset):
                changed = bytearray(original); changed[offset] = value
                self.library.write_bytes(changed)
                def forbidden(*args, **kwargs): self.fail('Wrong ELF metadata reached a tool')
                with self.assertRaisesRegex(ValueError, 'ELF64'):
                    P.inspect_linux_process_component(self.library, process_target='linux-x64-gnu', execute=forbidden)

    def test_foreign_process_target_refuses_before_input_or_tools(self):
        for target in ('linux-x64-musl', 'linux-riscv64-gnu', 'darwin-arm64', True):
            with self.subTest(target=target), self.assertRaisesRegex(ValueError, 'target selection'):
                P.inspect_linux_process_component(self.root / 'missing', process_target=target)

    def test_missing_or_foreign_original_provider_import_refuses(self):
        for name in P.PROCESS_IMPORTS:
            changed = copy.deepcopy(self.observations)
            changed[('nm', '-D', '--undefined-only')] = changed[('nm', '-D', '--undefined-only')].replace('U ' + name + '\n', '')
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'provider imports differ'):
                self.inspect(changed)
        changed = copy.deepcopy(self.observations)
        changed[('nm', '-D', '--undefined-only')] += 'U actql_foreign_provider\n'
        with self.assertRaisesRegex(ValueError, 'provider imports differ'):
            self.inspect(changed)

    def test_sqlite_export_or_another_allocator_definition_refuses(self):
        for name in ('sqlite3_open_v2', 'actql_native_owned_current'):
            changed = copy.deepcopy(self.observations)
            changed[('nm', '-D', '--defined-only')] += '00000000 T ' + name + '\n'
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'exports'):
                self.inspect(changed)

    def test_unversioned_external_allocator_and_stock_sqlite_imports_refuse(self):
        for name in ('external_allocator', 'sqlite3_open_v2@GLIBC_2.17', 'free@GCC_3.0'):
            changed = copy.deepcopy(self.observations)
            changed[('nm', '-D', '--undefined-only')] += 'U ' + name + '\n'
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'system import'):
                self.inspect(changed)

    def test_foreign_dependency_soname_and_loader_paths_refuse(self):
        key = ('readelf', '--dynamic', '--wide')
        for suffix in ('(NEEDED) Shared library: [libsqlite3.so]\n', '(NEEDED) Shared library: [libactql_control.so]\n',
                       '(RPATH) Library rpath: [/tmp]\n', '(RUNPATH) Library runpath: [.]\n'):
            changed = copy.deepcopy(self.observations); changed[key] += suffix
            with self.subTest(suffix=suffix), self.assertRaises(ValueError): self.inspect(changed)
        changed = copy.deepcopy(self.observations)
        changed[key] = changed[key].replace(P.LINUX_LIBRARY, 'foreign.so')
        with self.assertRaisesRegex(ValueError, 'SONAME'): self.inspect(changed)

    def test_automatic_initializers_and_tls_refuse(self):
        key = ('readelf', '--dynamic', '--wide')
        for name in ('INIT', 'FINI', 'INIT_ARRAY', 'FINI_ARRAY', 'PREINIT_ARRAY'):
            changed = copy.deepcopy(self.observations); changed[key] += '(' + name + ') 0x1000\n'
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'initializer'): self.inspect(changed)
        changed = copy.deepcopy(self.observations)
        changed[('readelf', '--program-headers', '--wide')] += '  TLS 0 0\n'
        with self.assertRaisesRegex(ValueError, 'TLS'): self.inspect(changed)

    def test_symlink_refuses_before_inspection(self):
        alias = self.root / 'alias.so'; alias.symlink_to(self.library)
        def forbidden(*args, **kwargs): self.fail('Untrusted input reached a tool')
        with self.assertRaises(OSError): P.inspect_linux_process_component(alias, execute=forbidden)

    def test_actual_build_entry_refuses_unselected_host_before_output(self):
        with patch.object(P.sys, 'platform', 'darwin'), patch.object(P.platform, 'machine', return_value='arm64'):
            with self.assertRaisesRegex(ValueError, 'linux-arm64-gnu'):
                P.build_linux_process_import('a' * 40, self.root / 'source.zip', Path('/missing/clang'), self.root / 'output', 60)
        self.assertFalse((self.root / 'output').exists())

    def test_x64_build_refuses_darwin_and_arm_host_before_output(self):
        for system, machine in (('darwin', 'x86_64'), ('linux', 'aarch64'), ('linux', 'i686')):
            with self.subTest(system=system, machine=machine), patch.object(P.sys, 'platform', system), \
                    patch.object(P.platform, 'machine', return_value=machine):
                with self.assertRaisesRegex(ValueError, 'linux-x64-gnu'):
                    P.build_linux_process_import('a' * 40, self.root / 'source.zip', Path('/missing/clang'),
                        self.root / 'output', 60, process_target='linux-x64-gnu')
                self.assertFalse((self.root / 'output').exists())

    def controlled_build(self, process_target='linux-x64-gnu', compiler_target='x86_64-pc-linux-gnu',
                         change_compiler=False):
        # Actual source/tool file hashing and ELF inspection, with authored
        # compiler outputs only. No compiler, Linux image or provider executes.
        from types import SimpleNamespace
        source = 'a' * 40
        compiler, archive = self.root / 'clang', self.root / 'source.zip'
        compiler.write_bytes(b'controlled compiler input')
        archive.write_bytes(b'controlled source archive input')
        resource = self.root / 'resource'; resource.mkdir()
        header = resource / 'stdint.h'; header.write_bytes(b'controlled compiler header')
        tools = {name: self.root / name for name in ('nm', 'readelf')}
        for path in tools.values(): path.write_bytes(b'controlled inspection tool')
        destination = self.root / 'output'
        commands = []
        real_inspect = P.inspect_linux_process_component
        def selected_path(value):
            return tools[Path(value).name] if str(value) in ('/usr/bin/nm', '/usr/bin/readelf') else Path(value)
        def git(command, **kwargs):
            self.assertEqual(command[0], 'git')
            return source if command[1] == 'rev-parse' else ''
        def stage(original, directory, *, process_target):
            self.assertEqual(original, archive)
            directory.mkdir()
            (directory / 'component.c').write_bytes(b'controlled original source')
            (directory / 'NOTICE').write_bytes(b'controlled original notice')
            return {'optimization': '-O2', 'recipe_sha256': 'b' * 64,
                    'target': 'aarch64-unknown-linux-gnu' if process_target == 'linux-arm64-gnu' else 'x86_64-unknown-linux-gnu'}
        def run(command, **kwargs):
            commands.append(command)
            self.assertEqual(kwargs['env'], {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C'})
            self.assertGreater(kwargs['timeout'], 0)
            if command[-1] == '-dumpmachine': output = compiler_target
            elif command[-1] == '-print-resource-dir': output = str(resource)
            elif '-c' in command:
                Path(command[command.index('-o') + 1]).write_bytes(b'controlled compiled object')
                Path(command[command.index('-MF') + 1]).write_text('component.o: ' +
                    str(destination / 'source/component.c') + ' ' + str(header) + '\n')
                if change_compiler: compiler.write_bytes(b'changed compiler input')
                output = ''
            else:
                self.assertIn('-shared', command)
                image = bytearray(self.library.read_bytes())
                image[18:20] = (183 if process_target == 'linux-arm64-gnu' else 62).to_bytes(2, 'little')
                Path(command[command.index('-o') + 1]).write_bytes(image)
                output = ''
            return SimpleNamespace(returncode=0, stdout=output, stderr='')
        def inspect(library, **selection):
            def execute(command, **kwargs):
                self.assertEqual(command[-1], str(library))
                return self.observations[(Path(command[0]).name, *command[1:-1])]
            return real_inspect(library, **selection, execute=execute)
        host = 'aarch64' if process_target == 'linux-arm64-gnu' else 'x86_64'
        with patch.object(P.sys, 'platform', 'linux'), patch.object(P.platform, 'machine', return_value=host), \
                patch.object(P, 'Path', side_effect=selected_path), patch.object(P.subprocess, 'check_output', side_effect=git), \
                patch.object(P.subprocess, 'run', side_effect=run), patch.object(P.STAGE, 'prepare', side_effect=stage), \
                patch.object(P, 'inspect_linux_process_component', side_effect=inspect):
            result = P.build_linux_process_import(source, archive, compiler, destination, 60,
                process_target=process_target)
        return result, commands, compiler, header

    def test_x64_build_records_actual_tools_and_target_without_arm_flags(self):
        result, commands, compiler, header = self.controlled_build()
        self.assertEqual(result['target'], 'x86_64-unknown-linux-gnu')
        self.assertEqual(result['compiler_target'], 'x86_64-pc-linux-gnu')
        self.assertEqual(result['elf_machine'], 62)
        compile_command = next(command for command in commands if '-c' in command)
        self.assertIn('-fPIC', compile_command)
        self.assertNotIn('-mno-outline-atomics', compile_command)
        self.assertFalse(any('aarch64' in value or '-mmacosx' in value for value in compile_command))
        self.assertEqual(result['inputs'][str(compiler)], P.identity(compiler, 512 * 1024 * 1024))
        self.assertEqual(result['compiled_inputs'][str(header)]['sha256'], P.identity(header, 65536)['sha256'])
        self.assertEqual((result['compile'], result['link']), (1, 1))
        self.assertFalse(result['loaded'])
        self.assertFalse(result['initialized'])
        self.assertIsNone(result['normal_profile'])
        self.assertFalse(result['installed_supplier'])

    def test_arm_build_retains_its_selected_target_and_outline_flag(self):
        result, commands, _, _ = self.controlled_build('linux-arm64-gnu', 'aarch64-unknown-linux-gnu')
        self.assertEqual(result['target'], 'aarch64-unknown-linux-gnu')
        self.assertEqual(result['elf_machine'], 183)
        self.assertIn('-mno-outline-atomics', next(command for command in commands if '-c' in command))

    def test_x64_rejects_foreign_compiler_abi_before_staging(self):
        for target in ('aarch64-unknown-linux-gnu', 'i686-linux-gnu', 'x86_64-linux-musl',
                       'x86_64-apple-darwin', 'x86_64-linux-gnux32'):
            with self.subTest(target=target):
                with tempfile.TemporaryDirectory(dir=self.root) as temporary:
                    old = self.root; self.root = Path(temporary)
                    try:
                        with self.assertRaisesRegex(ValueError, 'compiler target'):
                            self.controlled_build(compiler_target=target)
                        self.assertFalse((self.root / 'output/source').exists())
                        self.assertFalse((self.root / 'output/process-producer.json').exists())
                    finally: self.root = old

    def test_changed_selected_compiler_cannot_publish_a_receipt(self):
        with self.assertRaisesRegex(ValueError, 'build input changed'):
            self.controlled_build(change_compiler=True)
        self.assertFalse((self.root / 'output/process-producer.json').exists())
