"""Independent declaration mutations fail at the named source boundary."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


WASM = load('wasm_binding', ROOT / 'scripts/generate-local-wasm-abi.py')
NATIVE = load('native_binding', ROOT / 'scripts/generate-local-native-runtime-binding.py')


class BindingMutationTests(unittest.TestCase):
    def test_scalar_width_and_same_type_order_change_generated_binding(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [*sorted((ROOT / 'src/client_host_wasm').glob('*.mbt')),
                         ROOT / 'src/physical_resources/imported_child_ledger_wasm.mbt']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            path = root / 'src/client_host_wasm/buffers.mbt'
            old = path.read_text()
            baseline = WASM.render(root)
            self.assertEqual(baseline, WASM.render())
            for before, after in [('start : Int, count : Int', 'count : Int, start : Int'),
                                  ('start : Int, count : Int', 'start : Int64, count : Int')]:
                self.assertIn(before, old)
                path.write_text(old.replace(before, after, 1))
                self.assertNotEqual(WASM.render(root), baseline)
            path.write_text(old.replace('start : Int, count : Int', 'start : String, count : Int', 1))
            with self.assertRaisesRegex(ValueError, 'parameter declaration'):
                WASM.render(root)

    def test_native_shim_same_type_output_swap_is_not_fresh(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [NATIVE.DECLARATION, NATIVE.ENTRY / 'main_native.mbt',
                         NATIVE.ENTRY / 'packaged_runtime_shim.c']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            baseline = NATIVE.outputs(root)
            self.assertEqual(baseline, NATIVE.outputs())
            path = root / 'src/platform_native/installed_arena_entry/packaged_runtime_shim.c'
            old = path.read_text()
            # Both inputs are uint16 pointer/count pairs; width checks alone
            # cannot distinguish these independently meaningful roles.
            before = 'const uint16_t *source, int32_t source_units,\n    const uint16_t *platform, int32_t platform_units'
            self.assertIn(before, old)
            path.write_text(old.replace(before, 'const uint16_t *platform, int32_t platform_units,\n    const uint16_t *source, int32_t source_units', 1))
            with self.assertRaisesRegex(ValueError, 'parameter binding changed'):
                NATIVE.outputs(root)

    def test_original_moon_callback_mismatch_refuses(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in [NATIVE.DECLARATION, NATIVE.ENTRY / 'main_native.mbt',
                         NATIVE.ENTRY / 'packaged_runtime_shim.c']:
                target = root / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
            path = root / 'src/platform_native/installed_arena_entry/main_native.mbt'
            path.write_text(path.read_text().replace('register_original_packaged_runtime_roots(',
                                                     'foreign_runtime_roots(', 1))
            with self.assertRaisesRegex(ValueError, 'MoonBit Runtime callback'):
                NATIVE.outputs(root)


if __name__ == '__main__':
    unittest.main()
