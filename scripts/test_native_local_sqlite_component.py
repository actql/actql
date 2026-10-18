"""Closed same-process link selection; no component load or capacity claim."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('native_local_sqlite',
    Path(__file__).with_name('produce-native-local-sqlite-component.py'))
assert SPEC and SPEC.loader
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)
SOURCE = '1' * 40


class NativeLocalSQLite(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.exe = self.root / 'native_client.exe'
        self.exe.write_bytes(b'original executable bytes')
        raw = (P.ROOT / 'packages/python-local-runtime/native/pre-root/scoped-read-source.json').read_bytes()
        recipe = json.loads(raw)
        self.record = {'source': SOURCE, 'entry': 'src/cmd/native_client',
            'target': 'darwin-arm64', 'plan_only': False, 'moon_build_exit': 0,
            'providers': 1, 'commands_completed': 3,
            'executable': {'path': str(self.exe), **P.SQLITE.identity(self.exe, 1000)},
            'allocator': {'target': recipe['target'], 'recipe_sha256': hashlib.sha256(raw).hexdigest(),
                'patch_sha256': recipe['patch']['sha256'], 'required_defines': recipe['required_defines'],
                'outputs': recipe['outputs']}}

    def test_provider_is_exact_completed_local_executable(self):
        path, item = P.provider_original(self.record, SOURCE)
        self.assertEqual(path, self.exe)
        self.assertEqual(item, self.record['executable'])
        for key, value in [('source', '2' * 40), ('entry', 'src/cmd/native_remote_resident_site'),
                ('target', 'linux-x64-gnu'), ('plan_only', True), ('moon_build_exit', 1),
                ('moon_build_exit', False), ('providers', True), ('providers', 2),
                ('commands_completed', 0), ('commands_completed', True)]:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                P.provider_original({**self.record, key: value}, SOURCE)

    def test_changed_provider_or_foreign_allocator_refuses(self):
        self.exe.write_bytes(b'changed executable bytes!')
        with self.assertRaisesRegex(ValueError, 'changed'):
            P.provider_original(self.record, SOURCE)
        self.exe.write_bytes(b'original executable bytes')
        for key, value in [('target', 'foreign'), ('recipe_sha256', '0' * 64),
                ('patch_sha256', '0' * 64), ('required_defines', []), ('outputs', {})]:
            record = copy.deepcopy(self.record)
            record['allocator'][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'allocation source'):
                P.provider_original(record, SOURCE)

    def test_symbol_exceptions_match_actual_component_origin_check(self):
        text = (P.SQLITE.SOURCE / 'component.c').read_text()
        start = text.index('static int component_provider_origin(void) {')
        body = text[start:text.index('\n}', start) + 2]
        actual = set(re.findall(r'\(void\s*\*\)\s*(actql_[A-Za-z0-9_]+)', body))
        self.assertEqual(actual, P.PROVIDER_IMPORTS)
        self.assertEqual(len(actual), 7)
        command = P.link_arguments(['clang', '-O0'], self.root / 'component.o', self.root / 'component.dylib')
        self.assertIn('-Wl,-undefined,error', command)
        self.assertEqual({v for v in command if v.startswith('-Wl,-U,')},
                         {'-Wl,-U,_' + name for name in actual})
        self.assertFalse(any('dynamic_lookup' in v or 'native_control' in v or '-bundle_loader' in v
                             for v in command))
        self.assertIn('-O0', command)
        self.assertNotIn('-O2', command)

    def test_import_and_export_inventory_is_exact(self):
        imports = '\n'.join('_' + name for name in P.PROVIDER_IMPORTS)
        P.symbol_inventory(imports + '\n_malloc\n_free\n', undefined=True)
        for bad in [imports + '\n_actql_foreign_provider', imports + '\n_sqlite3_open',
                    imports.replace('_actql_native_owned_current', '_actql_wrong_current')]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                P.symbol_inventory(bad, undefined=True)
        exports = '\n'.join('000000 T ' + name for name in P.SQLITE.EXPORTS)
        P.symbol_inventory(exports, undefined=False)
        with self.assertRaisesRegex(ValueError, 'exports'):
            P.symbol_inventory(exports + '\n000000 T _sqlite3_open', undefined=False)
        with self.assertRaisesRegex(ValueError, 'exports'):
            P.symbol_inventory('\n'.join(sorted(P.SQLITE.EXPORTS)[:-1]), undefined=False)


if __name__ == '__main__':
    unittest.main()
