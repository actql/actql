"""Remote import independence and pre-I/O Local artifact admission."""
import subprocess
import sys
import hashlib
from threading import RLock
import unittest
from unittest.mock import patch
from pathlib import Path

from actql_sdk._local_core import LocalCore, LocalCoreResources, _PhysicalInput


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
            LocalCore(b'not a module', digest='0' * 64, transfer_capacity=65536,
                      resources=LocalCoreResources(0, 8, 0, 0, 0, 16 * 1024 * 1024 + 65536))

    def test_scalar_budgets_rejected_before_optional_engine_import(self):
        module = b'installed module'
        digest = hashlib.sha256(module).hexdigest()
        cases = [
            {'transfer_capacity': 2**63},
            {'transfer_capacity': 2**64 + 65536},
            {'transfer_capacity': 65536, 'fuel': 2**64},
            {'transfer_capacity': 65536, 'fuel': 2**64 + 100000000},
        ]
        with patch('actql_sdk._local_core.import_module',
                   side_effect=AssertionError('Invalid scalar reached Wasmtime')):
            for settings in cases:
                with self.subTest(settings=settings):
                    with self.assertRaisesRegex(ValueError, 'artifact or capacity'):
                        LocalCore(module, digest=digest,
                                  resources=LocalCoreResources(0, 8, 0, 0, 0, 16 * 1024 * 1024 + 65536),
                                  **settings)

    def test_invalid_root_limits_rejected_before_optional_engine_import(self):
        module = b'installed module'
        digest = hashlib.sha256(module).hexdigest()
        cases = (
            LocalCoreResources(0, 1, 0, 0, 0, 16 * 1024 * 1024 + 65536),
            LocalCoreResources(False, 8, 0, 0, 0, 16 * 1024 * 1024 + 65536),
            LocalCoreResources(0, 8, 0, 0, 0, 16 * 1024 * 1024 + 65535),
            LocalCoreResources(0, 8, 0, -1, 0, 16 * 1024 * 1024 + 65536),
            LocalCoreResources(0, 8, 0, 0, 0, 2**63),
        )
        with patch('actql_sdk._local_core.import_module',
                   side_effect=AssertionError('Invalid root reached Wasmtime')):
            for resources in cases:
                with self.subTest(resources=resources):
                    with self.assertRaises(ValueError):
                        LocalCore(module, digest=digest, transfer_capacity=65536,
                                  resources=resources)

    def test_physical_cleanup_fact_survives_missing_core_acknowledgement(self):
        core = LocalCore.__new__(LocalCore)
        calls = []
        def cleanup():
            calls.append('physical close')
            return True
        core._inputs = {1: _PhysicalInput(b'null', cleanup, lambda _: True)}
        core._released = set()
        core._native_observers = {}
        core._native_loans = {}
        self.assertEqual(core._cleanup(1), 0)
        self.assertEqual(core._cleanup(1), 0)
        self.assertEqual(calls, ['physical close'])
        self.assertEqual(core._released, {1})
        self.assertEqual(core._inputs, {})

    def test_native_cleanup_failure_retries_retired_resources_without_wasm(self):
        calls = []
        class Resource:
            def __init__(self, name, failures=0):
                self.name = name
                self.failures = failures
            def close(self):
                calls.append(self.name)
                if self.failures:
                    self.failures -= 1
                    raise OSError('independent native close failure')
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._closed = False
        core._retired = True
        core._closing = True
        core._store = Resource('store')
        core._linker = Resource('linker', 1)
        core._module = Resource('module')
        core._engine = Resource('engine')
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._native_observers = {}
        core._native_loans = {}
        linker = core._linker
        with self.assertRaises(OSError):
            core.close()
        self.assertIs(core._linker, linker)
        self.assertIsNone(core._store)
        self.assertTrue(core.close())
        self.assertTrue(core.close())
        self.assertEqual(calls, ['store', 'linker', 'linker', 'module', 'engine'])


if __name__ == '__main__':
    unittest.main()
