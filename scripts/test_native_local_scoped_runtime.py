"""Closed CLI composition checks; no compiler, installed supplier or allocation."""
import importlib.util
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest

# Match direct script execution when unittest imports the producer by file.
sys.path.insert(0, str(Path(__file__).resolve().parent))
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

    def plan(self, commands=None, entry='src/cmd/native_client', **selection):
        return MODULE.commands_for(
            '\n'.join(shlex.join(c) for c in (self.commands if commands is None else commands)),
            self.home, self.emission, self.allocator, self.clang, self.sdk, entry=entry,
            source_sha=self.source, **selection)

    def test_linux_local_keeps_one_provider_original_link_and_ordinary_managed_values(self):
        header = Path('/owned/local-stock-file-control.h')
        planned = self.plan(target='linux-x64', stock_file_control_bytes=4096,
                            local_control_header=header)
        steps = [step for step in planned if step[0] == str(self.clang)]
        self.assertEqual(len(steps), 9)
        for step in steps:
            self.assertIn('-D_GNU_SOURCE', step)
            self.assertIn('-DACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY', step)
            self.assertIn('-DACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS=170', step)
            self.assertIn('-DACTQL_RUNTIME_MANAGED_VALUES=1', step)
            self.assertIn(str(header), step)
            self.assertNotIn('-isysroot', step)
            self.assertFalse(any(value.startswith(('-mmacosx-', '-DACTQL_BUNDLE_INITIAL_CONTROL_HEADER=',
                '-DACTQL_RESIDENT_INITIAL_CONTROL_HEADER=')) for value in step))
        self.assertEqual(sum(any(value.startswith('-DACTQL_SCOPED_READ_PROVIDER=') for value in step)
                             for step in steps), 1)
        exports = {'-Wl,--export-dynamic-symbol=' + symbol
                   for symbol in MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS}
        self.assertEqual({value for value in planned[-1] if value.startswith('-Wl,--export')}, exports)
        self.assertFalse(any(value in exports for step in planned[:-1] for value in step))

    def test_linux_local_needs_its_own_bounded_control_header(self):
        for header in (None, Path('/foreign/header.h'), Path('/owned/bad\nheader.h')):
            with self.subTest(header=header), self.assertRaisesRegex(ValueError, 'stock-File control header'):
                self.plan(target='linux-x64', stock_file_control_bytes=4096, local_control_header=header)
        for count in (None, 0, 4095, 4097):
            with self.subTest(count=count), self.assertRaisesRegex(ValueError, 'control page'):
                self.plan(target='linux-x64', stock_file_control_bytes=count,
                          local_control_header=Path('/owned/header.h'))
        with tempfile.TemporaryDirectory() as temporary:
            header = Path(temporary) / 'local.h'
            record = MODULE.local_stock_file_control_header(self.source, header)
            self.assertEqual(record['selected'], {'kind': 'private-native-client-stock-file-control',
                'target': 'linux-x64', 'stockFileControlBytes': 4096})
            self.assertEqual(header.read_text(), '/* Local command fixed File records; not arena capacity. */\n'
                             '#define ACTQL_BUNDLE_STOCK_FILE_CONTROL_BYTES 4096\n')
            self.assertFalse(record['permission'])
            self.assertFalse(record['physicalAcquired'])

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

    def test_in_checkout_toolchain_runtime_keeps_the_same_derived_provider(self):
        self.home = MODULE.ROOT / '.toolchains/moonbit-pinned'
        commands = [c.copy() for c in self.commands]
        for command in commands:
            for index, part in enumerate(command):
                if part.startswith('$MOON_HOME/lib/runtime/'):
                    command[index] = './.toolchains/moonbit-pinned/lib/runtime/' + Path(part).name
        planned = self.plan(commands)
        runtime = {p for c in planned for p in c
                   if p.endswith('.c') and p.startswith(str(self.allocator))}
        self.assertEqual(runtime, {str(self.allocator / (name + '.c'))
                                  for name in MODULE.RUNTIME_NAMES})
        for name in MODULE.RUNTIME_NAMES:
            relative = './.toolchains/moonbit-pinned/lib/runtime/' + name + '.c'
            self.assertEqual(MODULE.canonical_c_arguments(['-c', relative, '-O2']),
                             ['-c', str(self.home / 'lib/runtime' / (name + '.c')), '-O2'])
        foreign = [c.copy() for c in commands]
        foreign[6][-1] = './.toolchains/foreign/lib/runtime/env.c'
        with self.assertRaisesRegex(ValueError, 'FFI'):
            self.plan(foreign)

    def test_in_checkout_toolchain_original_link_and_utf_members_stay_exact(self):
        self.home = MODULE.ROOT / '.toolchains/moonbit-pinned'
        commands = [c.copy() for c in self.commands]
        final = commands[-1]
        final[final.index('$MOON_HOME/lib/libmoonbitrun.o')] = (
            './.toolchains/moonbit-pinned/lib/libmoonbitrun.o')
        archive = ['/owned/bin/ar', '-r', '-c', '-s',
                   str(self.emission / 'native/release/build/libruntime-original.a'),
                   './.toolchains/moonbit-pinned/lib/moonbit_simdutf.o',
                   './.toolchains/moonbit-pinned/lib/simdutf.o']
        output = '\n'.join(shlex.join(c) for c in commands + [archive])
        selected = MODULE.commands_for(output, self.home, self.emission, self.allocator,
                                      self.clang, self.sdk, entry=MODULE.LOCAL_ENTRY,
                                      source_sha=self.source, ar_driver=Path('/owned/bin/ar'))
        self.assertEqual(selected[-1], archive)
        self.assertIn('./.toolchains/moonbit-pinned/lib/libmoonbitrun.o', selected[-2])
        for member in ('libmoonbitrun.o', 'libbacktrace.a'):
            relative = './.toolchains/moonbit-pinned/lib/' + member
            self.assertEqual(MODULE.canonical_c_arguments([relative]),
                             [str(self.home / 'lib' / member)])

    def test_actual_moon_in_checkout_include_keeps_the_exact_original_directory(self):
        relative = ['-I./.toolchains/moonbit-pinned/include', '-c', '-O2',
                    './src/cmd/native_client/command_control_stub.c']
        actual = ['-I' + str(MODULE.ROOT / '.toolchains/moonbit-pinned/include'), '-c', '-O2',
                  str(MODULE.ROOT / 'src/cmd/native_client/command_control_stub.c')]
        self.assertEqual(MODULE.canonical_c_arguments(relative), actual)
        for changed in [
                ['-I' + str(MODULE.ROOT / '.toolchains/foreign/include'), *actual[1:]],
                [actual[0], '-c', '-O0', actual[-1]],
                ['-isystem', actual[0][2:], *actual[1:]]]:
            self.assertNotEqual(MODULE.canonical_c_arguments(relative), changed)

    def test_package_registry_and_all_original_c_flags_survive_selection(self):
        planned = self.plan()
        self.assertEqual(planned[0][1:], self.commands[0][1:])
        self.assertEqual(planned[2][1:], self.commands[2][1:])
        for before, after in zip(self.commands[3:], planned[3:]):
            original = [p.replace('$MOON_HOME', str(self.home)) for p in before[1:]]
            selected = after[7:]  # Common prefix plus the ordinary managed-value mode.
            if before == self.commands[-1]:
                exports = ['-Wl,-exported_symbol,_' + symbol
                           for symbol in MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS]
                self.assertEqual(selected[-len(exports):], exports)
                selected = selected[:-len(exports)]
            if before[-1].endswith('/stdout_stub.c'):
                self.assertEqual(selected[-1], '-DACTQL_NATIVE_CLIENT_SOURCE_SHA="' + self.source + '"')
                selected = selected[:-1]
            elif before[-1].endswith('/bootstrap_stub.c'):
                selected = selected[:-1]
            elif before[-1].startswith('$MOON_HOME/lib/runtime/'):
                original[-1] = str(self.allocator / Path(before[-1]).name)
            self.assertEqual(selected, original)

    def test_local_entry_keeps_original_link_order_without_startup_anchor(self):
        final = self.plan()[-1]
        archive = str(self.emission / 'native/release/build/cmd/native_client/libnative_client-0123456789abcdef.a')
        self.assertGreater(final.index(archive), final.index(str(self.home / 'lib/libmoonbitrun.o')))
        self.assertFalse(any('_actql_native_client_capture_command_entry' in value for value in final))
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
            '-Wl,-exported_symbol,_actql_native_private_scoped_allocate',
            '-Wl,-exported_symbol,_actql_native_private_scoped_free',
            '-Wl,-exported_symbol,_actql_native_private_scoped_contains_allocation',
        }
        final = self.plan()[-1]
        self.assertEqual({p for p in final if p.startswith('-Wl,-export')}, expected)
        self.assertFalse(any('dynamic_lookup' in p or 'export_dynamic' in p for p in final))
        for command in self.plan()[:-1]:
            self.assertFalse(any(p.startswith('-Wl,-export') for p in command))

    def test_local_exports_match_components_and_private_http_provider_ports(self):
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
        self.assertEqual(len(imported), 8)
        http = (root / 'src/platform_native/http_client/http_client_stub.c').read_text()
        private = set(re.findall(r'^extern [^;\n]*?\b(actql_native_private_scoped_[A-Za-z0-9_]+)\(', http, re.M))
        self.assertEqual(private, {'actql_native_private_scoped_allocate',
                                  'actql_native_private_scoped_free',
                                  'actql_native_private_scoped_contains_allocation'})
        self.assertEqual(set(MODULE.LOCAL_COMPONENT_PROVIDER_EXPORTS), imported | private)

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
        operational = [c for c in planned if '-DACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY=1' in c]
        self.assertEqual(operational, [])
        recipe = [c for c in planned if '-DACTQL_NATIVE_COMMAND_INITIAL_OS_RECIPE=1' in c]
        self.assertEqual(recipe, [])
        c_steps = [c for c in planned if c[0] == str(self.clang)]
        self.assertTrue(c_steps)
        for command in c_steps:
            self.assertEqual(command.count('-DACTQL_RUNTIME_MANAGED_VALUES=1'), 1)

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

    def test_explicit_package_version_reaches_only_its_original_stub_without_changing_other_flags(self):
        commands = [c.copy() for c in self.commands]
        commands.insert(-1, ['/usr/bin/cc', '-o', str(self.emission / 'version.o'),
            '-I$MOON_HOME/include', '-c', '-O2', './src/cmd/native_client/version_stub.c'])
        text = '\n'.join(shlex.join(c) for c in commands)
        original = MODULE.commands_for(text, self.home, self.emission, self.allocator, self.clang, self.sdk,
            entry=MODULE.LOCAL_ENTRY, source_sha=self.source)
        versioned = MODULE.commands_for(text, self.home, self.emission, self.allocator, self.clang, self.sdk,
            entry=MODULE.LOCAL_ENTRY, source_sha=self.source, package_version='0.0.7-rc.1')
        differences = [(old, new) for old, new in zip(original, versioned) if old != new]
        self.assertEqual(len(differences), 1)
        self.assertEqual(differences[0][1], differences[0][0] + ['-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION="0.0.7-rc.1"'])
        self.assertIn('./src/cmd/native_client/version_stub.c', differences[0][0])

    def test_package_version_cannot_select_a_resident_helper_missing_stub_or_duplicate_literal(self):
        text = '\n'.join(shlex.join(c) for c in self.commands)
        with self.assertRaisesRegex(ValueError, 'version stub'):
            MODULE.commands_for(text, self.home, self.emission, self.allocator, self.clang, self.sdk,
                entry=MODULE.LOCAL_ENTRY, source_sha=self.source, package_version='0.0.7')
        with self.assertRaisesRegex(ValueError, 'resident helper'):
            MODULE.commands_for(text, self.home, self.emission, self.allocator, self.clang, self.sdk,
                entry=MODULE.ENTRY, package_version='0.0.7')
        for version in ('patch', '0.0.7rc1', '0.0.7\n'):
            with self.assertRaises(subprocess.CalledProcessError):
                MODULE.commands_for(text, self.home, self.emission, self.allocator, self.clang, self.sdk,
                    entry=MODULE.LOCAL_ENTRY, source_sha=self.source, package_version=version)
        duplicate = self.commands + [['/usr/bin/cc', '-c', './src/cmd/native_client/version_stub.c',
            '-o', str(self.emission / 'version.o'), '-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION="0.0.7"']]
        with self.assertRaisesRegex(ValueError, 'Duplicate Native package version'):
            MODULE.commands_for('\n'.join(shlex.join(c) for c in duplicate), self.home, self.emission,
                self.allocator, self.clang, self.sdk, entry=MODULE.LOCAL_ENTRY,
                source_sha=self.source, package_version='0.0.7')


if __name__ == '__main__':
    unittest.main()
