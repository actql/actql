"""Scalar loan doubles; no actual Wasm, Host adoption or public execution."""
from local_abi_declaration_fixture import assert_current_local_abi
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, LOCAL_CORE_ABI, _ORIGINAL_SIGNATURES,
    _Input, _PhysicalInput,
)
from local_abi_declaration_fixture import original_byte_fixture_port


class OriginalMetadataTests(unittest.TestCase):
    def bridge(self, *, kind=4, payload=None):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {1: _PhysicalInput(b'original-physical-facts', lambda: True, lambda _: True)}
        source = _Input(core._identity, 1, 10, 23)
        core._loans = {1: source}
        core._released = set()
        core._next_ticket = 2
        core._closing = False
        calls = []
        codes = {}
        if payload is None:
            payload = b'{"body":"e\xcc\x81\\r\\n","cid":"original"}'

        def call(family, name, *args):
            calls.append((family, name, args))
            if name in codes:
                return codes[name]
            if (family, name) == ('original', 'reserve'):
                self.assertEqual(args[:3], (10, kind, 2))
                self.assertGreaterEqual(args[3], 2 * 65536)
                self.assertEqual(core._inputs[2].payload, b'')
                return 19
            if (family, name) == ('original', 'produce'):
                return 0
            if (family, name) == ('original', 'length'):
                return len(payload)
            if (family, name) == ('buffer', 'byte'):
                return payload[args[1]]
            if (family, name) == ('original', 'close'):
                return 0 if core._cleanup(2) == 0 else -9
            raise AssertionError('Unexpected adoption, Run or authority ABI')
        core._call = original_byte_fixture_port(call)
        return core, source, calls, codes, payload

    def test_project_configuration_uses_same_bounded_original_metadata_loan(self):
        core, source, calls, _, payload = self.bridge(kind=5)
        value = core.reserve_original_metadata(source, 5, cleanup=lambda: True)
        core.produce_original_metadata(value)
        self.assertEqual(core.read_original_metadata(value), payload)
        self.assertIs(core._loans[source.ticket], source)
        self.assertTrue(core.close_original_metadata(value))
        self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)
        self.assertTrue(all(family in ('original', 'buffer') for family, _, _ in calls))

    def test_original_projection_preserves_bytes_and_source_without_adoption(self):
        core, source, calls, _, payload = self.bridge()
        value = core.reserve_original_metadata(source, 4, cleanup=lambda: True)
        core.produce_original_metadata(value)
        self.assertEqual(core.read_original_metadata(value), payload)
        self.assertEqual(core.read_original_metadata(value), payload)
        self.assertEqual(sum(name == 'length' for _, name, _ in calls), 1)
        self.assertTrue(core.close_original_metadata(value))
        self.assertIs(core._loans[1], source)
        self.assertTrue(all(family in ('original', 'buffer') for family, _, _ in calls))

    def test_copies_wrong_kind_closing_and_wrong_family_refuse_before_abi(self):
        core, source, calls, _, _ = self.bridge()
        for kind in (False, True, 0, 6, '4'):
            with self.assertRaises(ValueError):
                core.reserve_original_metadata(source, kind, cleanup=lambda: True)
        with self.assertRaises(ValueError):
            core.reserve_original_metadata(copy.copy(source), 4, cleanup=lambda: True)
        self.assertEqual(calls, [])
        value = core.reserve_original_metadata(source, 4, cleanup=lambda: True)
        baseline = len(calls)
        for action in (lambda: core.read_original_metadata(copy.copy(value)),
                       lambda: core.read_bootstrap(value)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        core._closing = True
        with self.assertRaises(ValueError):
            core.reserve_original_metadata(source, 4, cleanup=lambda: True)

    def test_cleanup_failure_retains_same_source_and_handle_without_reissue(self):
        core, source, calls, _, _ = self.bridge()
        ready = [False]
        value = core.reserve_original_metadata(source, 4, cleanup=lambda: ready[0])
        core.produce_original_metadata(value)
        self.assertFalse(core.close_original_metadata(value))
        self.assertIs(core._loans[value.ticket], value)
        self.assertIs(core._loans[1], source)
        ready[0] = True
        self.assertTrue(core.close_original_metadata(value))
        self.assertEqual(sum(name == 'produce' for _, name, _ in calls), 1)
        baseline = len(calls)
        with self.assertRaises(ValueError):
            core.read_original_metadata(value)
        self.assertEqual(len(calls), baseline)

    def test_capacity_and_invalid_lengths_preserve_failure_not_metadata(self):
        core, source, _, codes, _ = self.bridge()
        codes['reserve'] = -4
        with self.assertRaises(LocalCoreError) as raised:
            core.reserve_original_metadata(source, 4, cleanup=lambda: True)
        self.assertEqual(raised.exception.code, -4)
        self.assertEqual(set(core._loans), {1})
        del codes['reserve']
        # The failed reservation consumed its ticket; restart the independent
        # fixture rather than changing the product's identity counter.
        core, source, _, codes, _ = self.bridge()
        value = core.reserve_original_metadata(source, 4, cleanup=lambda: True)
        for length in (-33, 65537):
            codes['length'] = length
            with self.assertRaises(LocalCoreError):
                core.read_original_metadata(value)
            self.assertEqual(core._inputs[value.ticket].payload, b'')

    def test_closed_export_shape_matches_current_private_abi(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_ORIGINAL_SIGNATURES, {
            'reserve': ('i64 i32 i32 i32 i64', 'i32'),
            'produce': ('i64 i32', 'i32'),
            'length': ('i64 i32', 'i32'),
            'close': ('i64 i32', 'i32'),
        })


if __name__ == '__main__':
    unittest.main()
