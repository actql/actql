"""Independent pre-generation inverse and selected C role mutations."""
import ctypes as C
import importlib.util
import json
import re
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('duckdb_binding', ROOT / 'scripts/generate-local-duckdb-binding.py')
GENERATOR = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GENERATOR)


class DuckDBBindingTests(unittest.TestCase):
    def test_generated_binding_is_current(self):
        self.assertEqual((ROOT / GENERATOR.OUTPUT).read_text(), GENERATOR.render())

    def test_original_scalar_and_by_value_layouts_are_unchanged(self):
        from actql_sdk import _local_duckdb_abi as abi
        original = json.loads((ROOT / 'scripts/fixtures/python-duckdb-ctypes-original.json').read_text())
        def typename(value):return None if value is None else value.__name__
        actual = {name: [[typename(t) for t in arguments], typename(result)]
                  for name, (arguments, result) in abi.SIGNATURES.items()}
        self.assertEqual(len(actual), 39)
        self.assertEqual(actual, original['signatures'])
        def shape(value):
            if issubclass(value, (C.Structure, C.Union)):
                return [C.sizeof(value), C.alignment(value),
                        [[getattr(value, name).offset, shape(field)] for name, field in value._fields_]]
            return [C.sizeof(value), C.alignment(value)]
        self.assertEqual({name: shape(getattr(abi, name)) for name in original['layouts']}, original['layouts'])

    def test_same_width_parameter_roles_change_generated_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selected = json.loads((ROOT / GENERATOR.SELECTION).read_text())
            for relative in (GENERATOR.SELECTION, Path(selected['header'])):
                path = root / relative;path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT / relative).read_bytes())
            header = root / selected['header'];old = header.read_text()
            declaration = re.search(r'duckdb_bind_varchar_length\([^;]*\)', old)[0]
            self.assertIn('idx_t param_idx', declaration)
            self.assertIn('idx_t length', declaration)
            changed = declaration.replace('idx_t param_idx', 'idx_t length').replace('const char *val, idx_t length', 'const char *val, idx_t param_idx')
            header.write_text(old.replace(declaration, changed))
            self.assertNotEqual(GENERATOR.render(root), GENERATOR.render())


if __name__ == '__main__':
    unittest.main()
