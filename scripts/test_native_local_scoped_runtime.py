"""Closed CLI composition checks; no compiler, installed supplier or allocation."""
import importlib.util
from pathlib import Path
import re
import shlex
import unittest

SPEC = importlib.util.spec_from_file_location(
    'local_scoped_build', Path(__file__).with_name('produce-native-remote-scoped-runtime.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalScopedComposition(unittest.TestCase):
    def setUp(self):
        self.home = Path('/selected/moon')
        self.emission = Path('/owned/emission')
        self.allocator = Path('/owned/derived-read-source')
        self.clang = Path('/selected/clang')
        self.sdk = Path('/selected/sdk')
        self.source = '1234567890abcdef1234567890abcdef12345678'
        self.core = self.emission / 'native/release/build/cmd/native_client/native_client.c'
        self.exe = self.core.with_suffix('.exe')
        self.commands = [
            ['moonc', 'build-package', '-target', 'native', '-pkg',
             'actql/actql/cmd/native_client', '-o', str(self.emission / 'entry.core'),
             '-all-pkgs', str(self.emission / 'all_pkgs.json')],
            ['moonc', 'build-package', '-target', 'native', '-pkg',
             'actql/actql/platform_native/filesystem', '-o', str(self.emission / 'filesystem.core')],
            ['moonc', 'link-core', '-target', 'native', '-o', str(self.core), '-O', '-all-pkgs',
             str(self.emission / 'all_pkgs.json')],
            ['/usr/bin/cc', '-o', str(self.emission / 'bootstrap.o'), '-I$MOON_HOME/include',
             '-c', '-O2', '-fwrapv', '-fno-strict-aliasing',
             './src/platform_native/host_bootstrap/bootstrap_stub.c'],
            ['/usr/bin/cc', '-o', str(self.emission / 'filesystem.o'), '-I$MOON_HOME/include',
             '-c', '-O2', '-fwrapv', '-fno-strict-aliasing',
             './src/platform_native/filesystem/filesystem_stub.c'],
            ['/usr/bin/cc', '-o', str(self.emission / 'stdout.o'), '-I$MOON_HOME/include',
             '-c', '-O2', '-fwrapv', '-fno-strict-aliasing',
             './src/cmd/native_client/stdout_stub.c'],
            *[['/usr/bin/cc', '-o', str(self.emission / (name + '.o')), '-I$MOON_HOME/include',
               '-c', '-O2', '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC',
               '$MOON_HOME/lib/runtime/' + name + '.c']
              for name in ('backtrace', 'env', 'runtime', 'sync_io', 'utf')],
            ['/usr/bin/cc', '-o', str(self.exe), '-I$MOON_HOME/include', '-O0',
             '-fwrapv', '-fno-strict-aliasing', '$MOON_HOME/lib/libmoonbitrun.o', str(self.core),
             str(self.emission / 'native/release/build/cmd/native_client/libnative_client-0123456789abcdef.a'),
             str(self.emission / 'native/release/build/libruntime-original.a'), '-lm'],
        ]

    def plan(self, commands=None, entry='src/cmd/native_client'):
        return MODULE.commands_for(
            '\n'.join(shlex.join(c) for c in (self.commands if commands is None else commands)),
            self.home, self.emission, self.allocator, self.clang, self.sdk, entry=entry,
            source_sha=self.source)

    def test_remote_default_build_arguments_remain_unchanged(self):
        self.assertEqual(MODULE.moon_build_arguments(
            self.home, self.emission, 'src/cmd/native_remote_resident_site'), [
                '/selected/moon/bin/moon', 'build', '--target', 'native', '--release', '--strip',
                '--target-dir', '/owned/emission', '-j', '1', 'src/cmd/native_remote_resident_site'])

    def test_local_build_keeps_ordinary_no_strip_selection(self):
        self.assertEqual(MODULE.moon_build_arguments(
            self.home, self.emission, 'src/cmd/native_client'), [
                '/selected/moon/bin/moon', 'build', '--target', 'native', '--release',
                '--target-dir', '/owned/emission', '-j', '1', 'src/cmd/native_client'])
        planned = self.plan()
        self.assertIn('-O0', planned[-1])
        self.assertNotIn('-O2', planned[-1])
        self.assertNotIn('-g', planned[-1])

    def test_local_core_filesystem_runtime_share_one_provider(self):
        planned = self.plan()
        c_steps = [c for c in planned if c[0] == str(self.clang)]
        self.assertEqual(len(c_steps), 9)
        for command in c_steps:
            self.assertLess(command.index('-I/owned/derived-read-source'),
                            command.index('-I/selected/moon/include'))
            self.assertEqual(command.count('-DACTQL_SCOPED_READ_ALLOCATOR'), 1)
        providers = [c for c in c_steps
                     if any(p.startswith('-DACTQL_SCOPED_READ_PROVIDER=') for p in c)]
        self.assertEqual(len(providers), 1)
        self.assertIn('./src/platform_native/host_bootstrap/bootstrap_stub.c', providers[0])
        runtime = {p for c in c_steps for p in c if p.endswith('.c') and p.startswith(str(self.allocator))}
        self.assertEqual(runtime, {str(self.allocator / (name + '.c'))
                                  for name in ('backtrace', 'env', 'runtime', 'sync_io', 'utf')})

    def test_package_registry_and_all_original_c_flags_survive_selection(self):
        planned = self.plan()
        self.assertEqual(planned[0][1:], self.commands[0][1:])
        self.assertEqual(planned[2][1:], self.commands[2][1:])
        for before, after in zip(self.commands[3:], planned[3:]):
            original = [p.replace('$MOON_HOME', str(self.home)) for p in before[1:]]
            selected = after[6:]  # Only the common header/SDK/allocator prefix is inserted.
            if before == self.commands[-1]:
                exports = ['-Wl,-exported_symbol,_' + symbol
                           for symbol in MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS]
                self.assertEqual(selected[-len(exports):], exports)
                selected = selected[:-len(exports)]
                self.assertEqual(selected[-1], MODULE.LOCAL_INITIAL_ENTRY_ANCHOR)
                selected = selected[:-1]
                archive = str(self.emission / 'native/release/build/cmd/native_client/libnative_client-0123456789abcdef.a')
                original.remove(archive)
                original.insert(original.index(str(self.home / 'lib/libmoonbitrun.o')), archive)
            if before[-1].endswith('/stdout_stub.c'):
                self.assertEqual(selected[-1], '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="' + self.source + '"')
                selected = selected[:-1]
            elif before[-1].endswith('/bootstrap_stub.c'):
                selected = selected[:-1]
            elif before[-1].startswith('$MOON_HOME/lib/runtime/'):
                original[-1] = str(self.allocator / Path(before[-1]).name)
            self.assertEqual(selected, original)

    def test_local_entry_archive_precedes_allocator_without_whole_archive(self):
        final = self.plan()[-1]
        archive = str(self.emission / 'native/release/build/cmd/native_client/libnative_client-0123456789abcdef.a')
        self.assertLess(final.index(archive), final.index(str(self.home / 'lib/libmoonbitrun.o')))
        self.assertEqual(final.count(MODULE.LOCAL_INITIAL_ENTRY_ANCHOR), 1)
        self.assertFalse(any('force_load' in value or 'all_load' in value for value in final))

    def test_missing_original_initialization_members_refuse(self):
        for omitted in [str(self.home / 'lib/libmoonbitrun.o'),
                        str(self.emission / 'native/release/build/cmd/native_client/libnative_client-0123456789abcdef.a')]:
            commands = [list(command) for command in self.commands]
            final = commands[-1]
            final.remove(omitted.replace(str(self.home), '$MOON_HOME'))
            with self.assertRaisesRegex(ValueError, 'Exact original CLI archive'):
                self.plan(commands)

    def test_only_the_original_component_provider_ports_are_exported(self):
        expected = {
            '-Wl,-exported_symbol,_actql_native_owned_current',
            '-Wl,-exported_symbol,_actql_native_owned_allocate',
            '-Wl,-exported_symbol,_actql_native_owned_retire',
            '-Wl,-exported_symbol,_actql_read_context_retain',
            '-Wl,-exported_symbol,_actql_read_context_release_after_owner_ack',
            '-Wl,-exported_symbol,_actql_bootstrap_current_read_context',
            '-Wl,-exported_symbol,_actql_native_file_scoped_allocate',
            '-Wl,-exported_symbol,_actql_native_file_scoped_free',
        }
        final = self.plan()[-1]
        self.assertEqual({p for p in final if p.startswith('-Wl,-export')}, expected)
        self.assertFalse(any('dynamic_lookup' in p or 'export_dynamic' in p for p in final))
        for command in self.plan()[:-1]:
            self.assertFalse(any(p.startswith('-Wl,-export') for p in command))

    def test_local_exports_match_both_actual_components_provider_origin_checks(self):
        root = Path(__file__).resolve().parents[1]
        imported = set()
        for directory, function in (
                ('crypto-component', 'provider_origin'),
                ('sqlite-component', 'component_provider_origin')):
            text = (root / 'packages/python-local-runtime/native' /
                    directory / 'component.c').read_text()
            start = text.index('static int ' + function + '(void) {')
            body = text[start:text.index('\n}', start) + 2]
            ports = set(re.findall(r'\(void\s*\*\)\s*(actql_[A-Za-z0-9_]+)', body))
            self.assertEqual(len(ports), 6 if directory == 'crypto-component' else 7)
            imported.update(ports)
        self.assertEqual(set(MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS), imported)
        self.assertEqual(len(imported), 8)

    def test_remote_core_executable_or_missing_local_module_are_foreign(self):
        for index, old, new in (
                (2, str(self.core), str(self.core).replace('native_client', 'native_remote_resident_site')),
                (-1, str(self.exe), str(self.exe).replace('native_client', 'native_remote_resident_site')),
                (0, 'actql/actql/cmd/native_client', 'actql/actql/cmd/foreign')):
            commands = [c.copy() for c in self.commands]
            commands[index][commands[index].index(old)] = new
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.plan(commands)
        with self.assertRaisesRegex(ValueError, 'Core'):
            self.plan(entry='src/cmd/native_remote_resident_site')

    def test_other_entries_and_path_aliases_are_not_selected(self):
        for entry in ('src/cmd/foreign', './src/cmd/native_client',
                      'src/cmd/../cmd/native_client', 'src/cmd/native_client/', ''):
            with self.subTest(entry=entry):
                with self.assertRaisesRegex(ValueError, 'entry'):
                    self.plan(entry=entry)
                with self.assertRaisesRegex(ValueError, 'entry'):
                    MODULE.moon_build_arguments(self.home, self.emission, entry)

    def test_same_basename_under_another_output_prefix_is_foreign(self):
        commands = [c.copy() for c in self.commands]
        commands[2][commands[2].index(str(self.core))] = str(
            self.emission / 'other/cmd/native_client/native_client.c')
        with self.assertRaisesRegex(ValueError, 'Core'):
            self.plan(commands)

    def test_missing_or_duplicate_local_provider_runtime_refuses(self):
        for commands in (self.commands[:3] + self.commands[4:],
                         self.commands + [self.commands[3]],
                         self.commands[:5] + self.commands[6:],
                         self.commands[:6] + self.commands[7:],
                         self.commands + [self.commands[5]]):
            with self.subTest(commands=commands), self.assertRaises(ValueError):
                self.plan(commands)

    def test_local_source_pin_is_exact_and_reaches_only_the_original_c_entrance(self):
        planned = self.plan()
        pins = [(c, p) for c in planned for p in c
                if p.startswith('-DACTQL_NATIVE_CLIENT_SOURCE_SHA=')]
        self.assertEqual(len(pins), 1)
        self.assertIn('./src/cmd/native_client/stdout_stub.c', pins[0][0])
        self.assertEqual(pins[0][1], '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="' + self.source + '"')

    def test_missing_malformed_or_duplicate_local_source_pin_refuses(self):
        output = '\n'.join(shlex.join(c) for c in self.commands)
        for source in (None, '', 'f' * 39, 'F' * 40, 'g' * 40, 'f' * 40 + 'x'):
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, 'source pin'):
                MODULE.commands_for(output, self.home, self.emission, self.allocator,
                                    self.clang, self.sdk, entry=MODULE.LOCAL_ENTRY, source_sha=source)
        commands = [c.copy() for c in self.commands]
        commands[5].append('-DACTQL_NATIVE_CLIENT_SOURCE_SHA="' + self.source + '"')
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.plan(commands)
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            self.plan(self.commands + [self.commands[5]])


if __name__ == '__main__':
    unittest.main()
