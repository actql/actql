"""Physical projection custody only; real Core acceptance is a separate gate."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input
from local_abi_declaration_fixture import original_byte_fixture_port


class MaterialCustodyTests(unittest.TestCase):
    def bridge(self, payload=b'e\xcc\x81/~\xf0\x9f\x98\x80\r\nNULL'):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._next_ticket = 1
        core._closing = False
        calls = []
        pending = [True]

        def call(family, name, *args):
            calls.append((family, name, args))
            if (family, name) == ('material', 'reserve'):
                self.assertEqual(core._inputs[args[2]].payload, b'')
                self.assertGreaterEqual(args[3], 2 * 1_048_576)
                return 19
            if (family, name) == ('material', 'produce'):
                return 0
            if (family, name) == ('material', 'length'):
                return len(payload)
            if (family, name) == ('buffer', 'byte'):
                return payload[args[1]]
            if (family, name) == ('material', 'close'):
                return -9 if pending[0] else core._cleanup(1)
            raise AssertionError('Unexpected physical ABI invocation')

        core._call = original_byte_fixture_port(call)
        return core, calls, pending

    def test_reservation_precedes_destination_and_cleanup_retains_same_loan(self):
        core, calls, pending = self.bridge()
        cleanup = []
        loan = core.reserve_material(7, 4, cleanup=lambda: cleanup.append('close') or True)
        core.produce_material(loan)
        payload = core.read_material(loan)
        self.assertEqual(payload, b'e\xcc\x81/~\xf0\x9f\x98\x80\r\nNULL')
        self.assertEqual(len(payload), 15)
        count = len(calls)
        self.assertIs(core.read_material(loan), payload)
        self.assertEqual(len(calls), count)
        self.assertFalse(core.close_material(loan))
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertEqual(cleanup, [])
        pending[0] = False
        self.assertTrue(core.close_material(loan))
        self.assertEqual(cleanup, ['close'])
        with self.assertRaises(ValueError):
            core.read_material(loan)

    def test_copied_foreign_and_wrong_kind_loans_fail_before_io(self):
        core, calls, _ = self.bridge()
        loan = core.reserve_material(7, 1, cleanup=lambda: True)
        foreign, _, _ = self.bridge()
        baseline = len(calls)
        for action in (lambda: core.read_material(copy.copy(loan)),
                       lambda: foreign.read_material(loan),
                       lambda: core.fill_input(loan, 0, 1),
                       lambda: core.close_input(loan)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        input_loan = _Input(core._identity, 2, 20, 4)
        core._loans[2] = input_loan
        with self.assertRaises(ValueError):
            core.read_material(input_loan)
        self.assertEqual(len(calls), baseline)

    def test_invalid_length_or_byte_never_becomes_a_partial_record(self):
        for refusal in ('length', 'byte'):
            core, _, _ = self.bridge()
            loan = core.reserve_material(7, 2, cleanup=lambda: True)
            original = core._call
            def call(family, name, *args):
                if name == refusal:
                    return 1_048_577 if refusal == 'length' else -5
                return original(family, name, *args)
            core._call = original_byte_fixture_port(call)
            with self.assertRaises(LocalCoreError):
                core.read_material(loan)
            self.assertEqual(core._inputs[loan.ticket].payload, b'')
            self.assertIs(core._loans[loan.ticket], loan)

    def test_producer_trap_retains_original_handle_without_retry(self):
        core, _, _ = self.bridge()
        loan = core.reserve_material(7, 1, cleanup=lambda: True)
        def trapped(*_):
            raise RuntimeError('Independent interrupted Core call')
        core._call = original_byte_fixture_port(trapped)
        with self.assertRaises(RuntimeError):
            core.produce_material(loan)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertEqual(core._inputs[loan.ticket].payload, b'')

    def test_empty_record_preserves_zero_length(self):
        core, _, _ = self.bridge(b'')
        loan = core.reserve_material(7, 4, cleanup=lambda: True)
        self.assertEqual(core.read_material(loan), b'')

    def test_normalization_is_an_opaque_original_core_projection(self):
        core, calls, pending = self.bridge(b'original journal wire')
        loan = core.reserve_material(7, 5, cleanup=lambda: True)
        self.assertEqual(calls[0][2][:2], (7, 5))
        core.produce_material(loan)
        self.assertEqual(core.read_material(loan), b'original journal wire')
        self.assertTrue(all(family in ('material', 'buffer') for family, _, _ in calls))
        baseline = len(calls)
        for kind in (True, 0, 6):
            with self.assertRaises(ValueError):
                core.reserve_material(7, kind, cleanup=lambda: True)
        core._closing = True
        with self.assertRaises(ValueError):
            core.reserve_material(7, 5, cleanup=lambda: True)
        self.assertEqual(len(calls), baseline)
        self.assertFalse(core.close_material(loan))
        self.assertIs(core._loans[loan.ticket], loan)
        pending[0] = False
        self.assertTrue(core.close_material(loan))


if __name__ == '__main__':
    unittest.main()
