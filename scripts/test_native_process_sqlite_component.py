"""Process-import assembly checks; synthetic inspection never admits a provider."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('process_sqlite',
    Path(__file__).with_name('produce-python-sqlite-component.py'))
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class ProcessSQLiteTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.library = self.root / P.LIBRARY
        self.library.write_bytes(b'fixed tool observation fixture; not a loadable image')
        self.observations = {
            ('nm', '-gU'): ''.join('00000000 T ' + name + '\n' for name in sorted(P.EXPORTS)),
            ('nm', '-u'): ''.join('_' + name + '\n' for name in sorted(P.PROCESS_IMPORTS)),
            ('otool', '-L'): str(self.library) + ':\n\t@rpath/' + P.LIBRARY +
                ' (compatibility version 0.0.0, current version 0.0.0)\n'
                '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n',
            ('otool', '-l'): 'cmd LC_BUILD_VERSION\ncmdsize 32\nplatform 1\nminos 11.0\n',
        }

    def inspect(self, observations=None):
        selected = self.observations if observations is None else observations
        def execute(command, **kwargs):
            self.assertEqual(command[-1], str(self.library))
            return selected[(Path(command[0]).name, command[1])]
        return P.inspect_process_component(self.library, execute=execute)

    def test_exact_exports_and_original_process_imports_are_inspected_without_loading(self):
        observed = self.inspect()
        self.assertEqual(observed['exports'], sorted(P.EXPORTS))
        self.assertEqual(observed['provider_imports'], sorted(P.PROCESS_IMPORTS))
        self.assertNotIn('provider', observed)
        self.assertNotIn('loaded', observed)

    def test_each_missing_and_unknown_process_import_refuses(self):
        for name in P.PROCESS_IMPORTS:
            with self.subTest(name=name):
                changed = copy.deepcopy(self.observations)
                changed[('nm', '-u')] = changed[('nm', '-u')].replace('_' + name + '\n', '')
                with self.assertRaisesRegex(ValueError, 'provider imports differ'):
                    self.inspect(changed)
        changed = copy.deepcopy(self.observations)
        changed[('nm', '-u')] += '_actql_foreign_provider\n'
        with self.assertRaisesRegex(ValueError, 'provider imports differ'):
            self.inspect(changed)

    def test_additional_provider_definition_or_sqlite_export_refuses(self):
        for name in ['_actql_native_owned_current', '_sqlite3_open_v2']:
            with self.subTest(name=name):
                changed = copy.deepcopy(self.observations)
                changed[('nm', '-gU')] += '00000000 T ' + name + '\n'
                with self.assertRaisesRegex(ValueError, 'exports'):
                    self.inspect(changed)

    def test_second_provider_or_stock_sqlite_dependency_refuses(self):
        for name in ['@loader_path/libactql_native_control.dylib', '/usr/lib/libsqlite3.dylib']:
            with self.subTest(name=name):
                changed = copy.deepcopy(self.observations)
                changed[('otool', '-L')] += '\t' + name + ' (compatibility version 1.0.0, current version 1.0.0)\n'
                with self.assertRaisesRegex(ValueError, 'another provider or library'):
                    self.inspect(changed)

    def test_wrong_deployment_or_ambient_loader_path_refuses(self):
        for before, after, message in [('minos 11.0', 'minos 26.0', 'deployment'),
                                       ('cmdsize 32', 'cmd LC_RPATH\ncmdsize 32', 'search path')]:
            changed = copy.deepcopy(self.observations)
            changed[('otool', '-l')] = changed[('otool', '-l')].replace(before, after)
            with self.assertRaisesRegex(ValueError, message):
                self.inspect(changed)

    def test_changed_image_during_inspection_refuses(self):
        def execute(command, **kwargs):
            result = self.observations[(Path(command[0]).name, command[1])]
            if command[1] == '-l':
                self.library.write_bytes(b'changed original')
            return result
        with self.assertRaisesRegex(ValueError, 'changed during inspection'):
            P.inspect_process_component(self.library, execute=execute)

    def test_symlink_refuses_before_tool_observation(self):
        target = self.root / 'aliased.dylib'
        target.symlink_to(self.library)
        def forbidden(*args, **kwargs):
            self.fail('Symlink reached a tool')
        with self.assertRaises(OSError):
            P.inspect_process_component(target, execute=forbidden)
