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
            for file in ('owned_capacity.h', 'owned_domain_borrow.h', 'owned_thread.h', 'owned_abi.rs'):
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

    def test_thread_callback_is_cdecl_void_with_one_opaque_argument(self):
        from ctypes import CFUNCTYPE, c_void_p
        from actql_sdk._local_native_memory_abi import SIGNATURES
        callback = SIGNATURES['actql_native_owned_thread_start'][0][3]
        self.assertIs(callback, CFUNCTYPE(None, c_void_p))
        self.assertIsNone(callback._restype_)
        self.assertEqual(callback._argtypes_, (c_void_p,))
        configured = SIGNATURES['actql_native_owned_thread_start_configured'][0]
        self.assertIs(configured[3], c_void_p)
        self.assertIs(configured[4], callback)

    def test_callback_return_role_and_calling_convention_mutations_refuse(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for file in ('owned_capacity.h', 'owned_domain_borrow.h', 'owned_thread.h', 'owned_abi.rs'):
                path = root / GENERATOR.NATIVE / file
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT / GENERATOR.NATIVE / file).read_bytes())
            header = root / GENERATOR.NATIVE / 'owned_thread.h'
            original = header.read_text()
            for before, after in [('typedef void (*', 'typedef int (*'),
                                  ('void *argument);', 'size_t argument);'),
                                  ('(*actql_owned_thread_entry)', '(__stdcall *actql_owned_thread_entry)')]:
                with self.subTest(mutation=after):
                    self.assertIn(before, original)
                    header.write_text(original.replace(before, after))
                    with self.assertRaisesRegex(ValueError, 'thread callback'):
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
