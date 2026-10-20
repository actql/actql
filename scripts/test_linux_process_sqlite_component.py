"""ELF selection counters only; synthetic tool output is not binding/admission."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('linux_process_sqlite',
    Path(__file__).with_name('produce-python-sqlite-component.py'))
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class LinuxProcessSQLiteTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
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

    def inspect(self, observations=None):
        selected = self.observations if observations is None else observations
        def execute(command, **kwargs):
            self.assertEqual(command[-1], str(self.library))
            return selected[(Path(command[0]).name, *command[1:-1])]
        return P.inspect_linux_process_component(self.library, execute=execute)

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
        from unittest.mock import patch
        with patch.object(P.sys, 'platform', 'darwin'), patch.object(P.platform, 'machine', return_value='arm64'):
            with self.assertRaisesRegex(ValueError, 'linux-arm64-gnu'):
                P.build_linux_process_import('a' * 40, self.root / 'source.zip', Path('/missing/clang'), self.root / 'output', 60)
        self.assertFalse((self.root / 'output').exists())
