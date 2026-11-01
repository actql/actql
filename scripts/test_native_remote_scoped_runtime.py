"""Composition checks only; no compiler, runtime, allocation or capacity grant."""
import importlib.util
from pathlib import Path
import shlex
import json
import tempfile
import unittest
import subprocess
import sys
import os

SPEC = importlib.util.spec_from_file_location('remote_build', Path(__file__).with_name('produce-native-remote-scoped-runtime.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RemoteScopedComposition(unittest.TestCase):
    def setUp(self):
        self.home = Path('/selected/moon')
        self.emission = Path('/owned/emission')
        self.stage = Path('/owned/derived-read-source')
        self.clang = Path('/selected/clang')
        self.sdk = Path('/selected/sdk')
        self.core = self.emission / 'native/release/build/cmd/native_remote_resident_site/native_remote_resident_site.c'
        self.exe = self.core.with_suffix('.exe')
        self.commands = [
            ['moonc', 'build-package', '-target', 'native', '-pkg',
             'actql/actql/cmd/native_remote_resident_site', '-o', str(self.emission / 'entry.core')],
            ['moonc', 'link-core', '-target', 'native', '-o', str(self.core)],
            ['/usr/bin/cc', '-o', str(self.emission / 'bootstrap.o'), '-I$MOON_HOME/include',
             '-c', './src/platform_native/host_bootstrap/bootstrap_stub.c'],
            *[['/usr/bin/cc', '-o', str(self.emission / (name + '.o')), '-I$MOON_HOME/include',
               '-c', '$MOON_HOME/lib/runtime/' + name + '.c'] for name in sorted(MODULE.RUNTIME_NAMES)],
            ['/usr/bin/cc', '-o', str(self.exe), '-I$MOON_HOME/include', str(self.core),
             '$MOON_HOME/lib/libmoonbitrun.o', '-lm'],
        ]

    def plan(self, commands=None):
        return MODULE.commands_for('\n'.join(shlex.join(c) for c in (self.commands if commands is None else commands)),
                                   self.home, self.emission, self.stage, self.clang, self.sdk)

    def test_same_header_runtime_and_single_provider(self):
        planned = self.plan()
        c = [p for p in planned if p[0] == str(self.clang)]
        for command in c:
            self.assertLess(command.index('-I' + str(self.stage)), command.index('-I' + str(self.home / 'include')))
            self.assertIn('-DACTQL_SCOPED_READ_ALLOCATOR', command)
        provider = [p for p in c if any(x.startswith('-DACTQL_SCOPED_READ_PROVIDER=') for x in p)]
        self.assertEqual(len(provider), 1)
        self.assertIn('./src/platform_native/host_bootstrap/bootstrap_stub.c', provider[0])
        runtime = {Path(x).name for p in c for x in p if x.startswith(str(self.stage)) and x.endswith('.c')}
        self.assertEqual(runtime, {name + '.c' for name in MODULE.RUNTIME_NAMES})
        self.assertFalse(any(str(self.home / 'lib/runtime') in x for p in planned for x in p))
        self.assertEqual(planned[-1][-2:], [str(self.home / 'lib/libmoonbitrun.o'), '-lm'])

    def test_original_debug_registry_and_compiler_arguments_are_preserved(self):
        commands = [c.copy() for c in self.commands]
        commands[0] += ['-g', '-O0', '-all-pkgs', str(self.emission / 'all_pkgs.json')]
        planned = self.plan(commands)
        self.assertEqual(planned[0][1:], commands[0][1:])

    def test_private_driver_selects_only_the_planned_c_boundary(self):
        driver = Path('/owned/bin/cc')
        commands = [[str(driver), *c[1:]] if c[0] == '/usr/bin/cc' else c for c in self.commands]
        output = '\n'.join(shlex.join(c) for c in commands)
        plan = MODULE.commands_for(output, self.home, self.emission, self.stage,
                                   self.clang, self.sdk, cc_driver=driver)
        self.assertEqual(plan, self.plan())

    def test_actual_moon_archive_flags_are_preserved(self):
        archive = ['/owned/bin/ar', '-r', '-c', '-s',
                   str(self.emission / 'liboriginal.a'), str(self.emission / 'original.o')]
        output = '\n'.join(shlex.join(c) for c in self.commands + [archive])
        plan = MODULE.commands_for(output, self.home, self.emission, self.stage,
                                   self.clang, self.sdk, ar_driver=Path('/owned/bin/ar'))
        self.assertEqual(plan[-1], archive)

    def release_archive_plan(self, archive):
        output = '\n'.join(shlex.join(c) for c in self.commands + [archive])
        return MODULE.commands_for(output, self.home, self.emission, self.stage,
                                   self.clang, self.sdk, ar_driver=Path('/owned/bin/ar'))

    def release_archive(self):
        return ['/owned/bin/ar', '-r', '-c', '-s',
                str(self.emission / 'native/release/build/libruntime-original.a'),
                *[str(self.emission / ('runtime-' + name + '.o'))
                  for name in sorted(MODULE.RUNTIME_NAMES)],
                str(self.home / 'lib/moonbit_simdutf.o'), str(self.home / 'lib/simdutf.o')]

    def test_release_runtime_keeps_the_original_pinned_utf_objects(self):
        archive = self.release_archive()
        self.assertEqual(self.release_archive_plan(archive)[-1], archive)

    def test_release_runtime_refuses_a_foreign_utf_object(self):
        archive = self.release_archive()
        archive[-1] = '/foreign/simdutf.o'
        with self.assertRaisesRegex(ValueError, 'Foreign archive input'):
            self.release_archive_plan(archive)

    def test_pinned_utf_objects_cannot_be_added_to_an_ffi_archive(self):
        archive = self.release_archive()
        archive[4] = str(self.emission / 'native/release/build/platform_native/sqlite/libsqlite.a')
        with self.assertRaisesRegex(ValueError, 'Foreign archive input'):
            self.release_archive_plan(archive)

    def test_release_runtime_refuses_missing_or_duplicate_utf_objects(self):
        original = self.release_archive()
        for archive in (original[:-1], original + [original[-1]]):
            with self.subTest(archive=archive), self.assertRaisesRegex(ValueError, 'Foreign archive input'):
                self.release_archive_plan(archive)

    def test_only_observed_source_path_absolutization_is_equivalent(self):
        relative = ['./src/platform_native/filesystem/filesystem_stub.c', '-o', './src/result.o', '-O0']
        absolute = [str(MODULE.ROOT / relative[0]), *relative[1:]]
        self.assertEqual(MODULE.canonical_c_arguments(relative), absolute)
        self.assertEqual(MODULE.canonical_c_arguments(['/foreign/input.c', '-O2']), ['/foreign/input.c', '-O2'])
        self.assertNotEqual(MODULE.canonical_c_arguments(relative),
                            MODULE.canonical_c_arguments([relative[0], '-o', './src/result.o', '-O2']))

    def test_private_c_port_rejects_unplanned_invocation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'plan.json'
            path.write_text(json.dumps({'steps': []}))
            with self.assertRaisesRegex(ValueError, 'Unplanned'):
                MODULE.compile_selected_c(path, ['--arbitrary'])

    def test_actual_private_cc_driver_import_needs_no_release_parser_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan = root / 'plan.json'
            plan.write_text(json.dumps({'steps': []}))
            script = ('import importlib.util,sys\n'
                      'from pathlib import Path\n'
                      's=importlib.util.spec_from_file_location("selected_cc",sys.argv[1])\n'
                      'm=importlib.util.module_from_spec(s);s.loader.exec_module(m)\n'
                      'try:m.compile_selected_c(Path(sys.argv[2]),["--unplanned"])\n'
                      'except ValueError as e:print(str(e))\n')
            result = subprocess.run([sys.executable, '-I', '-c', script,
                                     str(Path(MODULE.__file__)), str(plan)],
                                    cwd=root, env={**os.environ, 'PYTHONPATH': ''},
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), 'Unplanned or ambiguous C compiler invocation')

    def test_private_c_port_rechecks_allocator_before_compiler(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            header = root / 'header.h'
            header.write_text('original')
            expected = MODULE.original(header)
            header.write_text('changed')
            path = root / 'plan.json'
            path.write_text(json.dumps({'steps': [{'original': ['expected']}],
                                        'allocator_inputs': [expected]}))
            with self.assertRaisesRegex(ValueError, 'changed'):
                MODULE.compile_selected_c(path, ['expected'])

    def test_second_core_cannot_split_owner_identity(self):
        with self.assertRaisesRegex(ValueError, 'composition'):
            self.plan(self.commands + [self.commands[1]])

    def test_missing_or_duplicate_provider_refuses(self):
        for commands in (self.commands[:2] + self.commands[3:], self.commands + [self.commands[2]]):
            with self.assertRaisesRegex(ValueError, 'composition'):
                self.plan(commands)

    def test_missing_or_duplicate_runtime_refuses(self):
        for commands in (self.commands[:3] + self.commands[4:], self.commands + [self.commands[3]]):
            with self.assertRaises(ValueError):
                self.plan(commands)

    def test_foreign_entry_refuses(self):
        commands = [c.copy() for c in self.commands]
        commands[1][-1] = str(self.emission / 'foreign.c')
        with self.assertRaisesRegex(ValueError, 'Core'):
            self.plan(commands)

    def test_output_escape_refuses(self):
        commands = [c.copy() for c in self.commands]
        commands[2][2] = '/foreign/output.o'
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.plan(commands)

    def test_unresolved_placeholder_and_foreign_ffi_refuse(self):
        commands = [c.copy() for c in self.commands]
        commands[2][-1] = '$UNSELECTED/source.c'
        with self.assertRaisesRegex(ValueError, 'placeholder'):
            self.plan(commands)
        commands[2][-1] = '/foreign/source.c'
        with self.assertRaisesRegex(ValueError, 'FFI'):
            self.plan(commands)

    def test_non_native_or_execution_command_refuses(self):
        commands = [c.copy() for c in self.commands]
        commands[0][3] = 'js'
        with self.assertRaisesRegex(ValueError, 'target'):
            self.plan(commands)
        commands = self.commands + [[str(self.exe), '-o', str(self.emission / 'not-a-build')]]
        with self.assertRaisesRegex(ValueError, 'tool'):
            self.plan(commands)


if __name__ == '__main__':
    unittest.main()
