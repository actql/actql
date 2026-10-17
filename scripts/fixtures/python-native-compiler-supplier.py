"""Four same-provider 64-page supplier cases; no Rust, Engine, VM or Run.

The finite metadata below is an independent C-port diagnostic, not a selected
image recipe, module admission, product supplier or normal numerical profile.
"""
from ctypes import CDLL, byref, c_void_p
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
spec = importlib.util.spec_from_file_location('physical_compiler_supplier',
                                            ROOT / 'scripts/compile-python-local-image.py')
assert spec is not None and spec.loader is not None
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)
from actql_sdk._local_native_holding import NativeHoldingRetirementError, NativeHoldingScopeError  # noqa: E402
from actql_sdk._local_native_memory_abi import bind  # noqa: E402


class CompilerSupplierTests(unittest.TestCase):
    provider: Path
    digest: str
    holdings = []

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='actql-compiler-holding-original-')
        self.addCleanup(temporary.cleanup)
        source = Path(temporary.name)
        body = b'independent 64-page C supplier diagnostic; not an Engine recipe'
        recipe = SimpleNamespace(engine_body=body,
            runtime_library_sha256=hashlib.sha256(b'No Rust library in this diagnostic').hexdigest(),
            provider_library_sha256=self.digest, provider_library_bytes=self.provider.stat().st_size)
        original = source / 'packages/python-local-runtime/selected-compiler-holding.json'
        original.parent.mkdir(parents=True)
        module_hash = hashlib.sha256(b'No Wasm module in this diagnostic').hexdigest()
        original.write_text(json.dumps({'scope': 'image_compiler_only',
            'module_sha256': module_hash, 'engine_sha256': hashlib.sha256(body).hexdigest(),
            'runtime_library_sha256': recipe.runtime_library_sha256,
            'provider_library_sha256': self.digest,
            'capacity_bytes': 64 * os.sysconf('SC_PAGE_SIZE'), 'generation': 7}))
        def git(*args):
            return subprocess.check_output(['git', '-c', 'user.name=Fixture', '-c',
                'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', *args],
                cwd=source, text=True).strip()
        git('init', '-q'); git('add', '.'); git('commit', '-qm', 'test: retain compiler extent original')
        self.original = {'source': git('rev-parse', 'HEAD'), 'module_sha256': module_hash,
                         'recipe': recipe, 'provider_library': self.provider}
        scoped = patch.object(compiler, 'ROOT', source)
        scoped.start(); self.addCleanup(scoped.stop)
        self.selected = compiler._compiler_holding_original(self.original)

    def acquire(self):
        holding = compiler._acquire_compiler_holding(self.original, self.selected)
        self.holdings.append(holding)
        return holding

    def test_supplier_moves_same_physical_extent_and_enters_original_provider(self):
        holding = self.acquire()
        self.assertEqual(holding._capacity_bytes(), self.selected.capacity_bytes)
        self.assertIsNone(holding._core_identity)
        self.assertFalse(holding._transfer_attempted)
        with holding._scope():
            self.assertEqual(bind(holding._library, 'actql_native_owned_current')(), holding._pointer.value)
        self.assertIsNone(bind(holding._library, 'actql_native_owned_current')())
        holding.close(); holding.close()

    def test_busy_original_retirement_keeps_holding_until_confirmed_scope_leave(self):
        holding = self.acquire()
        pointer = holding._pointer.value
        with holding._scope():
            with self.assertRaises(NativeHoldingRetirementError):
                holding.close()
            self.assertEqual(holding._pointer.value, pointer)
            self.assertEqual(holding._capacity_bytes(), self.selected.capacity_bytes)
        holding.close()

    def test_live_original_extent_prevents_return_until_that_same_extent_retires(self):
        holding = self.acquire()
        span = c_void_p()
        with holding._scope():
            self.assertEqual(bind(holding._library, 'actql_native_owned_allocate')(
                holding._pointer, 32, 16, byref(span)), 0)
        pointer = holding._pointer.value
        with self.assertRaises(NativeHoldingRetirementError):
            holding.close()
        self.assertEqual(holding._pointer.value, pointer)
        # Closing rejects fresh scopes. The original C cleanup port still
        # retires this same extent; do not reopen a scope or replace the lease.
        with self.assertRaises(NativeHoldingScopeError):
            with holding._scope():
                self.fail('Closing holding admitted a fresh scope')
        self.assertEqual(bind(holding._library, 'actql_native_owned_retire')(
            holding._pointer, span), 0)
        holding.close()

    def test_python_binding_failure_after_move_retains_the_same_actual_holding(self):
        initialize = compiler._NativeHoldingLease._initialize_original
        primary = OSError('Independent Python initialization fault after original move')
        def fail_after_move(holding, *args):
            initialize(holding, *args)
            raise primary
        with patch.object(compiler._NativeHoldingLease, '_initialize_original', fail_after_move):
            with self.assertRaises(compiler.CompilerHoldingAcquisitionError) as caught:
                self.acquire()
        carrier = caught.exception
        self.assertEqual(carrier.code, 0)  # Actual C acquire returned its ACK.
        self.assertFalse(carrier.refused)
        self.assertIs(carrier.__cause__, primary)
        self.assertIsNone(carrier.slot.value)
        holding = carrier.holding
        self.assertIsNotNone(holding)
        self.holdings.append(holding)
        self.assertEqual(holding._capacity_bytes(), self.selected.capacity_bytes)
        self.assertIs(holding._library, carrier.library)
        holding.close()  # Same confirmed acquisition, not an acquire/close replay.


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise ValueError('Select the exact original provider and digest')
    provider, digest = Path(sys.argv[1]), sys.argv[2]
    if not provider.is_absolute() or len(digest) != 64:
        raise ValueError('Invalid selected provider')
    compiler._read_file(provider, maximum=16 * 1024 * 1024, digest=digest)
    CompilerSupplierTests.provider, CompilerSupplierTests.digest = provider, digest
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CompilerSupplierTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    closed = len(CompilerSupplierTests.holdings) == 4 and all(
        holding._pointer.value is None and holding._close_failure is None
        for holding in CompilerSupplierTests.holdings)
    compiler._read_file(provider, maximum=16 * 1024 * 1024, digest=digest)
    print(json.dumps({'cases': result.testsRun, 'skipped': len(result.skipped),
        'success': result.wasSuccessful(), 'originals_closed': closed,
        'provider_sha256': digest, 'fixture_pages': 64, 'new_native_build': 0,
        'rust_loaded': any(name == 'wasmtime' or name.startswith('wasmtime.') for name in sys.modules),
        'engine': 0, 'instance': 0, 'Run': 0, 'normal_funding': None,
        'public_local_acceptance': False}), flush=True)
    sys.exit(0 if result.testsRun == 4 and not result.skipped and result.wasSuccessful() and closed else 1)
