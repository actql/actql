"""Private binding freshness, original inverse and meaningful role mutations."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('shim_generator', ROOT / 'scripts/generate-local-native-shim-bindings.py')
GENERATOR = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GENERATOR)


class NativeShimBindingTests(unittest.TestCase):
    def test_outputs_are_fresh(self):
        self.assertEqual((ROOT / GENERATOR.OUTPUT).read_text(), GENERATOR.render())
        self.assertEqual((ROOT / GENERATOR.HEADER).read_text(), GENERATOR.render_header())

    def test_original_139_ctypes_declarations_are_unchanged(self):
        from actql_sdk._local_native_shim_abi import SIGNATURES
        expected = json.loads((ROOT / 'scripts/fixtures/python-native-shim-ctypes-original.json').read_text())
        self.assertEqual(len(expected), 139)
        actual = {name: [[t.__name__ for t in SIGNATURES[name][0]], SIGNATURES[name][1].__name__]
                  for name in expected}
        self.assertEqual(actual, expected)

    def test_same_width_role_swap_changes_generated_declaration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for shim in GENERATOR.SHIMS:
                relative = GENERATOR.source_path(shim)
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT / relative).read_bytes())
            before = GENERATOR.render(root)
            path = root / GENERATOR.ENTRY / 'sqlite_database_shim.c'
            original = path.read_text()
            roles = ('int actql_sqlite_database_read_utf16_into(actql_control_host *host, actql_sqlite_database *original,\n'
                     '    const uint16_t *scope, int32_t scope_units, const uint16_t *key, int32_t key_units,')
            # Inspect the named original role, not merely equal C widths.
            if roles not in original:
                raise AssertionError('Original SQLite namespace role changed')
            swapped = roles.replace('const uint16_t *scope, int32_t scope_units, const uint16_t *key, int32_t key_units,',
                                    'const uint16_t *key, int32_t key_units, const uint16_t *scope, int32_t scope_units,')
            path.write_text(original.replace(roles, swapped, 1))
            self.assertNotEqual(before, GENERATOR.render(root))

    def test_original_process_child_abi_roles_and_output_slot_are_closed(self):
        from actql_sdk._local_native_shim_abi import SIGNATURES, PARAMETERS
        arguments, result = SIGNATURES['actql_process_child_utf16_into']
        self.assertEqual([t.__name__ for t in arguments], [
            'c_void_p', 'c_void_p', 'c_void_p', 'LP_c_ushort', 'c_int',
            'LP_c_ubyte', 'c_int', 'LP_c_ubyte', 'c_int', 'LP_c_void_p'])
        self.assertEqual(result.__name__, 'c_int')
        self.assertEqual([name for name, _ in PARAMETERS['actql_process_child_utf16_into']],
            ['host', 'domain', 'process', 'executable', 'units', 'arguments',
             'arguments_bytes', 'environment', 'environment_bytes', 'slot'])
        self.assertEqual([name for name, _ in PARAMETERS['actql_process_originals_into']],
            ['reply', 'host', 'domain', 'process', 'channel', 'frame'])
        self.assertNotIn('actql_process_close_fd', SIGNATURES)

    def test_host_pair_keeps_both_host_roles_originals_and_int64_capacity(self):
        from actql_sdk._local_native_shim_abi import PARAMETERS, SIGNATURES
        self.assertEqual([name for name, _ in PARAMETERS['actql_host_resources_originals_into']],
            ['reply', 'host', 'sqlite_host', 'read', 'sqlite', 'original'])
        self.assertEqual([name for name, _ in PARAMETERS['actql_host_resources_finish_closed_data']],
            ['host', 'sqlite_host', 'read', 'sqlite', 'original', 'reply'])
        arguments, result = SIGNATURES['actql_host_resources_capacity_scalar']
        from ctypes import c_int32, c_int64, c_void_p
        self.assertEqual(arguments, [c_void_p, c_int32])
        self.assertIs(result, c_int64)
        self.assertEqual([name for name, _ in PARAMETERS['actql_host_resources_operate_into']],
            ['host', 'original', 'operation', 'reply'])

    def test_unknown_symbol_cannot_bind_or_call_owner(self):
        from actql_sdk._local_native_shim_abi import bind
        class Library:
            def __getattr__(self, name):
                raise AssertionError('Unknown operation reached a library')
        with self.assertRaises(KeyError):
            bind(Library(), 'actql_unregistered_operation')

    def test_journal_transport_keeps_original_roles_and_owned_slots(self):
        from ctypes import c_void_p, c_double, c_int32, c_int64, POINTER, c_int
        from actql_sdk._local_native_shim_abi import SIGNATURES, PARAMETERS, ORIGINS
        symbol = 'actql_local_journal_prepare_into'
        args, result = SIGNATURES[symbol]
        self.assertEqual(args, [c_void_p, c_void_p, c_void_p, c_double, c_int32,
                                c_int64, POINTER(c_void_p)])
        self.assertEqual(result, c_int)
        self.assertEqual([name for name, _ in PARAMETERS[symbol]], [
            'session', 'library', 'crypto', 'ttl_ms', 'max_records',
            'max_snapshot_bytes', 'capture'])
        self.assertEqual([name for name, _ in PARAMETERS['actql_local_journal_originals_into']],
                         ['capture', 'session', 'host', 'failure'])
        self.assertEqual([name for name, _ in PARAMETERS['actql_local_journal_finish_closed_data']],
                         ['capture', 'reply'])
        self.assertEqual(ORIGINS[symbol][0],
                         'src/platform_native/client_host/local_journal_shim_impl.h')
        self.assertEqual([name for name, _ in PARAMETERS['actql_local_journal_drop_originals']],
                         ['capture', 'session', 'host', 'failure'])
        self.assertNotIn('actql_local_journal_force_release', SIGNATURES)


if __name__ == '__main__':
    unittest.main()
