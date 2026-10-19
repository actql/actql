"""Selected producer command closure checks; no compiler or library loading."""
import importlib.util
import json
from pathlib import Path
import tempfile
import os
import shlex
from types import SimpleNamespace
from unittest.mock import patch
import unittest


SPEC = importlib.util.spec_from_file_location('native_provider',
    Path(__file__).with_name('produce-python-native-provider.py'))
assert SPEC is not None and SPEC.loader is not None
PRODUCER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRODUCER)


class NativeProviderRecipeTests(unittest.TestCase):
    def setUp(self):
        self.lines = ['moonc build-package original.mbt -pkg ' + name
                      + " -target native -o original.core -std-path '$MOON_HOME/lib/core'"
                      + ' -all-pkgs absent-debug-registry.json'
                      for name in sorted(PRODUCER.PACKAGES)]
        self.lines.append('moonc link-core original.core -target native -o entry.c'
                          + ' -all-pkgs absent-debug-registry.json')

    def parse(self, lines=None):
        return PRODUCER.emission_commands('\n'.join(lines or self.lines), Path('/selected/moon'))

    def test_original_closure_and_one_placeholder_only(self):
        commands = self.parse()
        self.assertEqual(len(commands), 164)
        self.assertTrue(all(command[0] == '/selected/moon/bin/moonc' for command in commands))
        self.assertEqual(commands[0][commands[0].index('-std-path') + 1], '/selected/moon/lib/core')
        self.assertTrue(all(command[command.index('-all-pkgs') + 1]
                            == 'absent-debug-registry.json' for command in commands))

    def test_other_build_commands_are_not_executed(self):
        self.lines += ['/usr/bin/cc -c original.c', '/usr/bin/cc -o entry.exe original.c']
        self.assertEqual(len(self.parse()), 164)

    def test_missing_duplicate_and_foreign_package_are_refused(self):
        for lines in (self.lines[:-2] + self.lines[-1:],
                      [self.lines[0]] + self.lines,
                      [self.lines[0].replace('actql/actql/', 'foreign/')] + self.lines[1:]):
            with self.subTest(lines=lines):
                with self.assertRaisesRegex(ValueError, 'inventory|closure'):
                    self.parse(lines)

    def test_original_process_owner_is_a_required_selected_dependency(self):
        package = 'actql/actql/platform_native/executor_slot'
        self.assertIn(package, PRODUCER.PACKAGES)
        self.assertEqual(len(PRODUCER.PACKAGES), 163)
        without_process = [line for line in self.lines if '-pkg ' + package + ' ' not in line]
        with self.assertRaisesRegex(ValueError, 'inventory'):
            self.parse(without_process)
        foreign = [line.replace('-pkg ' + package + ' ',
                               '-pkg actql/actql/foreign_executor_slot ')
                   for line in self.lines]
        with self.assertRaisesRegex(ValueError, 'closure'):
            self.parse(foreign)

    def test_same_process_owner_foreign_c_input_is_selected_once(self):
        selected = ('platform_native/executor_slot/executor_slot_stub.c', 'executor-slot')
        self.assertEqual(PRODUCER.FOREIGN_SOURCES.count(selected), 1)

    def test_foreign_target_and_unresolved_placeholder_are_refused(self):
        for line in (self.lines[0].replace('-target native', '-target js'),
                     self.lines[0] + ' -i $FOREIGN/original.mi'):
            with self.subTest(line=line):
                with self.assertRaisesRegex(ValueError, 'target|placeholder'):
                    self.parse([line] + self.lines[1:])

    def test_unexpected_compiler_operation_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'operation'):
            self.parse(self.lines + ['moonc run original.core'])

    def test_registry_argument_is_mandatory_for_transitive_traits(self):
        with self.assertRaisesRegex(ValueError, 'registry'):
            self.parse([line.replace(' -all-pkgs absent-debug-registry.json', '')
                        for line in self.lines])

    def test_actual_link_core_without_package_registry_is_preserved(self):
        lines = self.lines[:-1] + [self.lines[-1].replace(
            ' -all-pkgs absent-debug-registry.json', '')]
        commands = self.parse(lines)
        self.assertEqual(len(commands), 164)
        self.assertEqual(commands[-1][1], 'link-core')
        self.assertNotIn('-all-pkgs', commands[-1])
        self.assertTrue(all('-all-pkgs' in c for c in commands[:-1]))

    def registry(self):
        entries = []
        for package in sorted(PRODUCER.PACKAGES):
            rel = package.removeprefix('actql/actql/')
            entries.append({'root': 'actql/actql', 'rel': rel,
                            'artifact': '/metadata/check/' + rel + '/' + Path(rel).name + '.mi'})
        entries.append({'root': 'moonbitlang/core', 'rel': 'builtin',
                        'artifact': '/selected/moon/lib/core/_build/native/release/bundle/builtin/builtin.mi'})
        return {'packages': entries}

    def relocate(self, body):
        return PRODUCER.relocated_registry(json.dumps(body).encode(),
            Path('/metadata/check'), Path('/emission/build'), Path('/selected/moon'))

    def test_registry_relocates_exact_artifact_and_preserves_original_core(self):
        result = json.loads(self.relocate(self.registry()))['packages']
        source = next(p for p in result if p['rel'] == 'source_value')
        self.assertEqual(source['artifact'], '/emission/build/source_value/source_value.mi')
        self.assertEqual(result[-1], self.registry()['packages'][-1])

    def test_registry_refuses_foreign_or_aliased_artifact_and_duplicate(self):
        for patch in ('foreign-root', 'foreign-artifact', 'alias', 'duplicate'):
            body = self.registry()
            if patch == 'foreign-root': body['packages'][0]['root'] = 'foreign/module'
            elif patch == 'foreign-artifact': body['packages'][0]['artifact'] = '/foreign/original.mi'
            elif patch == 'alias': body['packages'][0]['rel'] = 'source_value/../source_value'
            else: body['packages'].append(body['packages'][0].copy())
            with self.subTest(patch=patch), self.assertRaisesRegex(ValueError, 'registry'):
                self.relocate(body)

    def test_registry_refuses_incomplete_selected_closure(self):
        body = self.registry(); body['packages'].pop(0)
        with self.assertRaisesRegex(ValueError, 'closure'):
            self.relocate(body)

    def test_sdk_alias_retains_requested_and_canonical_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            sdk = root / 'selected-sdk'; sdk.mkdir()
            header = sdk / 'real.h'; header.write_bytes(b'original header\n')
            alias = sdk / 'alias.h'; alias.symlink_to('real.h')
            self.assertEqual(PRODUCER.original_dependency(alias, sdk),
                             {'requested_path': str(alias), **PRODUCER.original(header)})
            other = root / 'foreign.h'; other.write_bytes(b'foreign header\n')
            alias.unlink(); alias.symlink_to(other)
            with self.assertRaisesRegex(ValueError, 'escapes original SDK'):
                PRODUCER.original_dependency(alias, sdk)

    def test_non_sdk_source_alias_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            original = root / 'source.c'; original.write_bytes(b'original source\n')
            alias = root / 'alias.c'; alias.symlink_to(original)
            with self.assertRaisesRegex(ValueError, 'unavailable'):
                PRODUCER.original_dependency(alias, root / 'selected-sdk')


class NativeProviderRegistryCallerTests(unittest.TestCase):
    """Reach the actual build caller before input capture; no compiler runs."""

    def exercise(self, spelling, *, python_initial=False):
        class ReachedInputCapture(Exception):
            pass
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            moon, sdk, destination = root / 'moon', root / 'sdk', root / 'output'
            moon.mkdir(); sdk.mkdir()
            pin = {'moonc': 'selected-compiler', 'moon': 'selected-builder'}
            (root / 'toolchain.json').write_text(json.dumps(pin))
            (moon / 'installed.json').write_text(json.dumps({'pin': pin, 'platform': 'darwin-arm64'}))
            first = root / 'src' / sorted(PRODUCER.PACKAGES)[0].removeprefix('actql/actql/')
            first.mkdir(parents=True); (first / 'original.mbt').write_text('fixture source\n')
            source = '1' * 40
            observed_commands = []
            def command(args, **kwargs):
                observed_commands.append(args)
                output = ''
                if args[:3] == ['git', 'rev-parse', 'HEAD']: output = source + '\n'
                elif args[:2] == ['git', 'status']: pass
                elif args[0] == str(moon / 'bin/moonc'): output = pin['moonc'] + '\n'
                elif args[1] == 'version': output = 'moon ' + pin['moon'] + '\n'
                elif args[1] == 'check' and args[0] == str(moon / 'bin/moon'):
                    check = destination / 'metadata/native/debug/check'
                    check.mkdir(parents=True)
                    entries = []
                    for package in sorted(PRODUCER.PACKAGES):
                        rel = package.removeprefix('actql/actql/')
                        entries.append({'root': 'actql/actql', 'rel': rel,
                            'artifact': str(check / rel / (Path(rel).name + '.mi'))})
                    (check / 'all_pkgs.json').write_text(json.dumps({'packages': entries}))
                elif args[1] == 'build' and args[0] == str(moon / 'bin/moon'):
                    registry = destination / 'emission/native/debug/build/all_pkgs.json'
                    selected = str(registry) if spelling == 'absolute' else os.path.relpath(registry, root)
                    if spelling == 'foreign': selected = str(root / 'foreign/all_pkgs.json')
                    lines = ['moonc build-package original.mbt -pkg ' + package
                        + ' -target native -o original.core -all-pkgs ' + shlex.quote(selected)
                        for package in sorted(PRODUCER.PACKAGES)]
                    lines.append('moonc link-core original.core -target native -o entry.c')
                    output = '\n'.join(lines)
                return SimpleNamespace(stdout=output, stderr='', returncode=0)
            with patch.object(PRODUCER, 'ROOT', root), \
                 patch.object(PRODUCER.platform, 'system', return_value='Darwin'), \
                 patch.object(PRODUCER.platform, 'machine', return_value='arm64'), \
                 patch.object(PRODUCER.subprocess, 'run', side_effect=command), \
                 patch.object(PRODUCER, 'prepare_allocator_source', return_value=(None, {})), \
                 patch.object(PRODUCER, 'prepare_python_initial_component', return_value={
                     'include': '/selected/include', 'sha256': '2' * 64,
                     'runtime': '/selected/derived-runtime.o'}) as initial, \
                 patch.object(PRODUCER, 'original', side_effect=ReachedInputCapture), \
                 patch.object(PRODUCER, 'require_emission_registry', wraps=PRODUCER.require_emission_registry) as gate:
                expected = ValueError if spelling == 'foreign' else ReachedInputCapture
                with self.assertRaises(expected):
                    PRODUCER.build(source, moon, Path('/selected/clang'), sdk, destination, 30,
                                   python_initial_control=python_initial)
                gate.assert_called_once()
                selected_checks = [args for args in observed_commands
                                   if '--python-initial' in args]
                if python_initial:
                    self.assertEqual(len(selected_checks), 1)
                    self.assertEqual(selected_checks[0][-2:], ['--python-initial', '--check'])
                    initial.assert_called_once_with(source, moon, destination)
                else:
                    self.assertEqual(selected_checks, [])
                    initial.assert_not_called()

    def test_actual_builder_accepts_ordinary_relative_registry(self):
        self.exercise('relative')

    def test_actual_builder_preserves_absolute_registry(self):
        self.exercise('absolute')

    def test_actual_builder_refuses_foreign_registry_before_input_capture(self):
        self.exercise('foreign')

    def test_selected_builder_requires_initial_abi_without_changing_default_entrance(self):
        self.exercise('relative', python_initial=True)


if __name__ == '__main__':
    unittest.main()
