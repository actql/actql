"""Memory binding role and opaque-width correspondence mutations."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('memory_binding', ROOT / 'scripts/generate-local-native-memory-binding.py')
GENERATOR = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GENERATOR)


class MemoryBindingTests(unittest.TestCase):
    def test_generated_outputs_are_current(self):
        for path, output in GENERATOR.outputs().items():
            self.assertEqual(path.read_text(), output)

    def test_same_width_rust_image_size_swap_refuses(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for file in ('owned_capacity.h', 'owned_domain_borrow.h', 'owned_abi.rs'):
                path = root / GENERATOR.NATIVE / file
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT / GENERATOR.NATIVE / file).read_bytes())
            path = root / GENERATOR.NATIVE / 'owned_abi.rs'
            before = path.read_text()
            self.assertIn('expected: usize, maximum: usize', before)
            # Change both matching Rust declarations: a Rust-only equality
            # check would pass, but the existing named C roles must disagree.
            path.write_text(before.replace('expected: usize, maximum: usize',
                                           'maximum: usize, expected: usize'))
            with self.assertRaisesRegex(ValueError, 'memory role/type mismatch'):
                GENERATOR.outputs(root)

    def test_unknown_memory_symbol_refuses_without_library_access(self):
        from actql_sdk._local_native_memory_abi import bind
        class Library:
            def __getattr__(self, name):
                raise AssertionError('Unknown symbol reached a library')
        with self.assertRaises(KeyError):
            bind(Library(), 'actql_owned_unknown')


if __name__ == '__main__':
    unittest.main()
