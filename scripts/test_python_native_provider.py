"""Selected producer command closure checks; no compiler or library loading."""
import importlib.util
import json
from pathlib import Path
import tempfile
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
        self.assertEqual(len(commands), 162)
        self.assertTrue(all(command[0] == '/selected/moon/bin/moonc' for command in commands))
        self.assertEqual(commands[0][commands[0].index('-std-path') + 1], '/selected/moon/lib/core')
        self.assertTrue(all(command[command.index('-all-pkgs') + 1]
                            == 'absent-debug-registry.json' for command in commands))

    def test_other_build_commands_are_not_executed(self):
        self.lines += ['/usr/bin/cc -c original.c', '/usr/bin/cc -o entry.exe original.c']
        self.assertEqual(len(self.parse()), 162)

    def test_missing_duplicate_and_foreign_package_are_refused(self):
        for lines in (self.lines[:-2] + self.lines[-1:],
                      [self.lines[0]] + self.lines,
                      [self.lines[0].replace('actql/actql/', 'foreign/')] + self.lines[1:]):
            with self.subTest(lines=lines):
                with self.assertRaisesRegex(ValueError, 'inventory|closure'):
                    self.parse(lines)

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
        self.assertEqual(len(commands), 162)
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


if __name__ == '__main__':
    unittest.main()
