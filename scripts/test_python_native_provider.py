"""Selected producer command closure checks; no compiler or library loading."""
import importlib.util
from pathlib import Path
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
        self.lines.append('moonc link-core original.core -target native -o entry.c')

    def parse(self, lines=None):
        return PRODUCER.emission_commands('\n'.join(lines or self.lines), Path('/selected/moon'))

    def test_original_closure_and_one_placeholder_only(self):
        commands = self.parse()
        self.assertEqual(len(commands), 13)
        self.assertTrue(all(command[0] == '/selected/moon/bin/moonc' for command in commands))
        self.assertEqual(commands[0][commands[0].index('-std-path') + 1], '/selected/moon/lib/core')
        self.assertTrue(all('-all-pkgs' not in command for command in commands))

    def test_other_build_commands_are_not_executed(self):
        self.lines += ['/usr/bin/cc -c original.c', '/usr/bin/cc -o entry.exe original.c']
        self.assertEqual(len(self.parse()), 13)

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


if __name__ == '__main__':
    unittest.main()
