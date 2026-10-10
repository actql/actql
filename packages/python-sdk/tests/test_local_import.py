"""Remote import independence and pre-I/O Local artifact admission."""
import subprocess
import sys
import unittest
from pathlib import Path

from actql_sdk._local_core import LocalCore


class LocalImportTests(unittest.TestCase):
    def test_remote_import_never_loads_local_engines(self):
        root = Path(__file__).resolve().parents[1] / 'src'
        code = '''
import importlib.abc
import sys
class BlockLocal(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] in ('wasmtime', 'duckdb'):
            raise AssertionError('Remote import attempted Local runtime dependency')
sys.meta_path.insert(0, BlockLocal())
import actql_sdk
import actql_sdk._local_core
assert 'wasmtime' not in sys.modules and 'duckdb' not in sys.modules
'''
        result = subprocess.run([sys.executable, '-I', '-c',
            f'import sys; sys.path.insert(0, {str(root)!r});\n' + code],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_artifact_rejected_before_optional_engine_import(self):
        with self.assertRaisesRegex(ValueError, 'artifact or capacity'):
            LocalCore(b'not a module', digest='0' * 64, transfer_capacity=65536)


if __name__ == '__main__':
    unittest.main()
