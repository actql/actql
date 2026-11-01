"""Independent scalar custody tests, not actual Wasm or durable admission."""
from local_abi_declaration_fixture import assert_current_local_abi
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import (
    LOCAL_CORE_ABI, LocalCore, LocalCoreError, _Input, _PhysicalInput,
    _MATERIAL_SIGNATURES,
)
from local_abi_declaration_fixture import original_byte_fixture_port


class SubmittedMaterialCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._next_ticket = 2
        core._closing = False
        source = _Input(core._identity, 1, 10, 12)
        core._inputs[1] = _PhysicalInput(b'original-ref', lambda: True, lambda _: True)
        core._loans[1] = source
        calls = []
        pending = [True]
        payload = b'{"run_key":"original","preparing":"e\xcc\x81\r\n"}'

        def call(family, name, *args):
            calls.append((family, name, args))
            if (family, name) == ('material', 'reserve_submitted_rows'):
                self.assertEqual(args[:3], (7, 8, 10))
                self.assertEqual(core._inputs[args[3]].payload, b'')
                self.assertGreaterEqual(args[4], 2 * 1_048_576)
                return 19
            if (family, name) == ('material', 'produce'):
                return 0
            if (family, name) == ('material', 'length'):
                return len(payload)
            if (family, name) == ('buffer', 'byte'):
                return payload[args[1]]
            if (family, name) == ('material', 'close'):
                return -9 if pending[0] else core._cleanup(2)
            raise AssertionError('Unexpected ABI invocation')
        core._call = original_byte_fixture_port(call)
        return core, source, calls, pending, payload

    def test_original_rows_use_same_material_loan_without_acceptance_or_dispatch(self):
        core, source, calls, pending, payload = self.bridge()
        cleanup = []
        loan = core.reserve_submitted_run_rows(7, 8, source,
                                              cleanup=lambda: cleanup.append('output') or True)
        core.produce_material(loan)
        self.assertEqual(core.read_material(loan), payload)
        self.assertEqual(core._inputs[source.ticket].payload, b'original-ref')
        self.assertTrue(all(family in ('material', 'buffer') for family, _, _ in calls))
        self.assertFalse(core.close_material(loan))
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertEqual(cleanup, [])
        pending[0] = False
        self.assertTrue(core.close_material(loan))
        self.assertEqual(cleanup, ['output'])
        self.assertIs(core._loans[source.ticket], source)

    def test_boolean_handles_foreign_copies_and_closing_refuse_before_io(self):
        core, source, calls, _, _ = self.bridge()
        foreign, _, _, _, _ = self.bridge()
        for action in (
            lambda: core.reserve_submitted_run_rows(True, 8, source, cleanup=lambda: True),
            lambda: core.reserve_submitted_run_rows(7, True, source, cleanup=lambda: True),
            lambda: core.reserve_submitted_run_rows(0, 8, source, cleanup=lambda: True),
            lambda: core.reserve_submitted_run_rows(7, 8, copy.copy(source), cleanup=lambda: True),
            lambda: foreign.reserve_submitted_run_rows(7, 8, source, cleanup=lambda: True),
        ):
            with self.assertRaises(ValueError):
                action()
        core._closing = True
        with self.assertRaises(ValueError):
            core.reserve_submitted_run_rows(7, 8, source, cleanup=lambda: True)
        self.assertEqual(calls, [])
        self.assertEqual(core._next_ticket, 2)

    def test_producer_trap_preserves_original_output_and_source(self):
        core, source, _, _, _ = self.bridge()
        loan = core.reserve_submitted_run_rows(7, 8, source, cleanup=lambda: True)
        def trapped(*_):
            raise RuntimeError('Independent interrupted producer')
        core._call = original_byte_fixture_port(trapped)
        with self.assertRaises(RuntimeError):
            core.produce_material(loan)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIs(core._loans[source.ticket], source)
        self.assertEqual(core._inputs[loan.ticket].payload, b'')

    def test_reservation_refusal_remains_refusal_without_success_payload(self):
        core, source, _, _, _ = self.bridge()
        core._call = original_byte_fixture_port(lambda *_: -31)
        with self.assertRaises(LocalCoreError) as failure:
            core.reserve_submitted_run_rows(7, 8, source, cleanup=lambda: True)
        self.assertEqual(failure.exception.code, -31)
        self.assertEqual(set(core._inputs), {1})
        self.assertEqual(set(core._loans), {1})

    def test_retired_output_waits_for_same_input_borrow_and_cannot_be_read(self):
        core, source, calls, _, _ = self.bridge()
        cleanup = []
        loan = core.reserve_submitted_run_rows(7, 8, source,
                                              cleanup=lambda: cleanup.append('output') or True)
        original = core._call
        stopped = [False]
        def call(family, name, *args):
            if (family, name) == ('material', 'close'):
                self.assertEqual(core._cleanup(loan.ticket), 0)
                return 0 if stopped[0] else -9
            return original(family, name, *args)
        core._call = original_byte_fixture_port(call)
        self.assertFalse(core.close_material(loan))
        self.assertEqual(cleanup, ['output'])
        self.assertIs(core._loans[loan.ticket], loan)
        with self.assertRaisesRegex(RuntimeError, 'cleanup has completed'):
            core.read_material(loan)
        self.assertIs(core._loans[source.ticket], source)
        stopped[0] = True
        self.assertTrue(core.close_material(loan))
        self.assertEqual(cleanup, ['output'])
        self.assertNotIn('cancel', [name for _, name, _ in calls])

    def test_strict_private_abi_requires_original_submitted_row_export(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_MATERIAL_SIGNATURES['reserve_submitted_rows'],
                         ('i64 i32 i32 i32 i32 i64', 'i32'))


if __name__ == '__main__':
    unittest.main()
