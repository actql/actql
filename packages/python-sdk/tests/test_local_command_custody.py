"""Command loan custody; actual Native Source execution has a separate gate."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _NativeAttempt
from local_abi_declaration_fixture import original_byte_fixture_port


class NativeCommandCustodyTests(unittest.TestCase):
    def bridge(self, payload=b'{"sql":"SELECT ?","parameters":[]}'):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._inputs = {}
        core._loans = {}
        core._released = set()
        core._next_ticket = 2
        core._closing = False
        attempt = _NativeAttempt(core._identity, 17)
        core._native_loans = {17: attempt}
        account = _Input(core._identity, 1, 13, 7)
        core._loans[1] = account
        calls = []
        pending = [True]

        def call(family, name, *args):
            calls.append((family, name, args))
            if (family, name) == ('source', 'reserve_command'):
                self.assertEqual(args[:3], (17, 3, 13))
                self.assertEqual(core._inputs[args[3]].payload, b'')
                self.assertGreaterEqual(args[4], 200_000)
                return 19
            if (family, name) == ('source', 'produce_command'):
                return 0
            if (family, name) == ('source', 'command_length'):
                return len(payload)
            if (family, name) == ('buffer', 'byte'):
                return payload[args[1]]
            if (family, name) == ('source', 'close_command'):
                return -9 if pending[0] else core._cleanup(2)
            raise AssertionError('Unexpected physical ABI invocation')

        core._call = original_byte_fixture_port(call)
        return core, account, calls, pending

    def test_exact_bytes_are_cached_with_same_loan_through_pending_cleanup(self):
        core, account, calls, pending = self.bridge()
        cleanup = []
        loan = core.reserve_native_command(core._native_loans[17], 3, account,
            cleanup=lambda: cleanup.append('close') or True)
        self.assertEqual(loan.limit, 100_000)
        core.produce_native_command(loan)
        payload = core.read_native_command(loan)
        self.assertEqual(payload, b'{"sql":"SELECT ?","parameters":[]}')
        baseline = len(calls)
        self.assertIs(core.read_native_command(loan), payload)
        self.assertEqual(len(calls), baseline)
        self.assertFalse(core.close_native_command(loan))
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertEqual(cleanup, [])
        pending[0] = False
        self.assertTrue(core.close_native_command(loan))
        self.assertEqual(cleanup, ['close'])
        self.assertIs(core._loans[account.ticket], account)
        with self.assertRaises(ValueError):
            core.read_native_command(loan)

    def test_copied_authority_and_cross_family_loans_fail_before_io(self):
        core, account, calls, _ = self.bridge()
        with self.assertRaises(ValueError):
            core.reserve_native_command(core._native_loans[17], 3, copy.copy(account), cleanup=lambda: True)
        self.assertEqual(calls, [])
        loan = core.reserve_native_command(core._native_loans[17], 3, account, cleanup=lambda: True)
        baseline = len(calls)
        for action in (lambda: core.read_native_command(copy.copy(loan)),
                       lambda: core.read_material(loan),
                       lambda: core.produce_material(loan),
                       lambda: core.close_material(loan),
                       lambda: core.close_input(loan)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)

    def test_refused_output_keeps_issued_loan_for_retirement(self):
        core, account, _, pending = self.bridge()
        loan = core.reserve_native_command(core._native_loans[17], 3, account, cleanup=lambda: True)
        original = core._call
        def call(family, name, *args):
            if name == 'produce_command':
                return -7
            return original(family, name, *args)
        core._call = original_byte_fixture_port(call)
        with self.assertRaises(LocalCoreError):
            core.produce_native_command(loan)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertEqual(core._inputs[loan.ticket].payload, b'')
        self.assertFalse(core.close_native_command(loan))
        pending[0] = False
        self.assertTrue(core.close_native_command(loan))

    def test_invalid_lengths_and_partial_bytes_never_publish_partial_command(self):
        for refusal in ('command_length', 'byte'):
            core, account, _, _ = self.bridge()
            loan = core.reserve_native_command(core._native_loans[17], 3, account, cleanup=lambda: True)
            original = core._call
            def call(family, name, *args):
                if name == refusal:
                    return 100_001 if refusal == 'command_length' else -5
                return original(family, name, *args)
            core._call = original_byte_fixture_port(call)
            with self.assertRaises(LocalCoreError):
                core.read_native_command(loan)
            self.assertEqual(core._inputs[loan.ticket].payload, b'')
            self.assertIs(core._loans[loan.ticket], loan)

    def test_reservation_trap_keeps_physical_registration_without_retry(self):
        core, account, _, _ = self.bridge()
        attempted = []
        def trapped(*args):
            attempted.append(args)
            raise RuntimeError('Independent interrupted Core call')
        core._call = original_byte_fixture_port(trapped)
        with self.assertRaises(RuntimeError):
            core.reserve_native_command(core._native_loans[17], 3, account, cleanup=lambda: True)
        self.assertEqual(len(attempted), 1)
        self.assertIn(2, core._inputs)
        self.assertEqual(core._next_ticket, 3)


if __name__ == '__main__':
    unittest.main()
