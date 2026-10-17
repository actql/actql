"""Direct-provider holding conformance; no Rust, Engine, VM, Run or funding.

The isolated diagnostic caller owns each new 64-host-page fixture. Its raw
acquire is not a product supplier or a Common resource/authority decision.
"""
from ctypes import CDLL, byref, c_ubyte, c_void_p, memmove
import hashlib
import json
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_distribution import _read_file  # noqa: E402
from actql_sdk._local_native_holding import _NativeHoldingLease, NativeHoldingRetirementError  # noqa: E402
from actql_sdk._local_native_memory_abi import bind  # noqa: E402


class DirectProviderHoldingTests(unittest.TestCase):
    library: CDLL
    slots = []
    holdings = []

    def acquire(self):
        pointer = c_void_p()
        capacity = 64 * os.sysconf('SC_PAGE_SIZE')
        recipe = (c_ubyte * 32).from_buffer_copy(hashlib.sha256(b'original compiler holding fixture').digest())
        self.assertEqual(bind(self.library, 'actql_native_owned_acquire')(
            capacity, 7, recipe, byref(pointer)), 0)
        self.assertIsNotNone(pointer.value)
        self.slots.append(pointer)
        return pointer, capacity, bytes(recipe)

    def holding(self):
        pointer, capacity, recipe = self.acquire()
        original = pointer.value
        holding = _NativeHoldingLease._from_native_provider(pointer, self.library,
                                                            generation=7, recipe=recipe)
        self.holdings.append(holding)
        self.assertIsNone(pointer.value)
        self.assertEqual(holding._pointer.value, original)
        return holding, capacity

    def test_direct_scope_is_same_original_provider_and_capacity(self):
        holding, capacity = self.holding()
        with holding._scope():
            self.assertEqual(bind(self.library, 'actql_native_owned_current')(), holding._pointer.value)
            self.assertEqual(holding._capacity_bytes(), capacity)
        self.assertIsNone(bind(self.library, 'actql_native_owned_current')())
        holding.close(); holding.close()
        self.assertIsNone(holding._pointer.value)
        self.assertIsNone(holding._core_identity)
        self.assertFalse(holding._transfer_attempted)

    def test_original_span_remains_live_through_direct_scope_and_explicit_retirement(self):
        holding, _ = self.holding()
        span = c_void_p()
        with holding._scope():
            self.assertEqual(bind(self.library, 'actql_native_owned_allocate')(
                holding._pointer, 32, 16, byref(span)), 0)
            holding._require_live_span(span, 32)
            memmove(span, b'original scoped compiler bytes', 30)
            self.assertEqual(bind(self.library, 'actql_native_owned_retire')(holding._pointer, span), 0)
        holding.close()
        self.assertIsNone(holding._pointer.value)

    def test_busy_scope_refusal_does_not_release_or_replace_the_holding(self):
        holding, _ = self.holding()
        original = holding._pointer.value
        with holding._scope():
            with self.assertRaises(NativeHoldingRetirementError):
                holding.close()
            self.assertEqual(holding._pointer.value, original)
            self.assertEqual(bind(self.library, 'actql_native_owned_current')(), original)
        holding.close()
        self.assertIsNone(holding._pointer.value)

    def test_missing_rust_forwarder_never_consumes_the_direct_provider_slot(self):
        pointer, _, recipe = self.acquire()
        original = pointer.value
        self.assertFalse(hasattr(self.library, 'actql_owned_try_close'))
        with self.assertRaises(AttributeError):
            _NativeHoldingLease(pointer, self.library, generation=7, recipe=recipe)
        self.assertEqual(pointer.value, original)
        holding = _NativeHoldingLease._from_native_provider(pointer, self.library,
                                                            generation=7, recipe=recipe)
        self.holdings.append(holding)
        holding.close()
        self.assertIsNone(pointer.value)
        self.assertIsNone(holding._pointer.value)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise ValueError('Select the exact original candidate provider and SHA256')
    path, digest = Path(sys.argv[1]), sys.argv[2]
    if not path.is_absolute() or len(digest) != 64:
        raise ValueError('Invalid original candidate provider')
    _read_file(path, maximum=16 * 1024 * 1024, digest=digest)
    DirectProviderHoldingTests.library = CDLL(str(path))
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(DirectProviderHoldingTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    _read_file(path, maximum=16 * 1024 * 1024, digest=digest)
    closed = (all(slot.value is None for slot in DirectProviderHoldingTests.slots)
              and all(holding._pointer.value is None and holding._close_failure is None
                      for holding in DirectProviderHoldingTests.holdings))
    print(json.dumps({'cases': result.testsRun, 'skipped': len(result.skipped),
        'success': result.wasSuccessful(), 'originals_closed': closed,
        'provider_sha256': digest, 'fixture_pages': 64,
        'rust_loaded': any(name == 'wasmtime' or name.startswith('wasmtime.') for name in sys.modules),
        'engine': 0, 'instance': 0, 'Run': 0, 'normal_funding': None,
        'public_local_acceptance': False}), flush=True)
    sys.exit(0 if result.testsRun == 4 and not result.skipped and result.wasSuccessful() and closed else 1)
