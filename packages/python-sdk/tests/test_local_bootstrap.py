"""Independent metadata/loan ABI doubles; not real Wasm or public Local PASS."""
from local_abi_declaration_fixture import assert_current_local_abi
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import (
    LocalCore, LocalCoreError, LOCAL_CORE_ABI, _BOOTSTRAP_SIGNATURES,
    _Input, _PhysicalInput,
)
from local_abi_declaration_fixture import original_byte_fixture_port


class BootstrapCustodyTests(unittest.TestCase):
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
        core._inputs[1] = _PhysicalInput(b'original-root-clock', lambda: True, lambda _: True)
        core._loans[1] = source
        calls = []
        codes = {}
        payload = b'{"account":"e\xcc\x81\\r\\n","store":"original-scope"}'

        def call(family, name, *args):
            calls.append((family, name, args))
            if name in codes:
                outcome = codes[name]
                if isinstance(outcome, BaseException):
                    raise outcome
                return outcome
            if (family, name) == ('bootstrap', 'reserve'):
                self.assertEqual(args[:2], (10, 2))
                self.assertEqual(core._inputs[2].payload, b'')
                self.assertGreaterEqual(args[2], 2 * 1_048_576)
                return 19
            if family == 'bootstrap' and name in ('produce', 'produce_sdk'):
                return 0
            if (family, name) == ('bootstrap', 'length'):
                return len(payload)
            if (family, name) == ('buffer', 'byte'):
                return payload[args[1]]
            if (family, name) == ('bootstrap', 'close'):
                return 0 if core._cleanup(2) == 0 else -9
            raise AssertionError('Unexpected execution, authority or storage ABI')
        core._call = original_byte_fixture_port(call)
        return core, source, calls, codes, payload

    def test_original_metadata_copy_uses_one_reserved_loan_and_no_execution(self):
        core, source, calls, _, payload = self.bridge()
        loan = core.reserve_bootstrap(source, cleanup=lambda: True)
        core.produce_bootstrap(loan)
        self.assertEqual(core.read_bootstrap(loan), payload)
        self.assertEqual(core.read_bootstrap(loan), payload)
        self.assertEqual(sum(name == 'length' for _, name, _ in calls), 1)
        self.assertTrue(all(family in ('bootstrap', 'buffer') for family, _, _ in calls))
        self.assertTrue(core.close_bootstrap(loan))
        self.assertIs(core._loans[source.ticket], source)

    def test_copied_foreign_inputs_and_closing_refuse_before_abi(self):
        core, source, calls, _, _ = self.bridge()
        foreign, _, _, _, _ = self.bridge()
        for action in (
            lambda: core.reserve_bootstrap(copy.copy(source), cleanup=lambda: True),
            lambda: foreign.reserve_bootstrap(source, cleanup=lambda: True),
            lambda: core.reserve_bootstrap(source, cleanup=None),
        ):
            with self.assertRaises(ValueError):
                action()
        core._closing = True
        with self.assertRaises(ValueError):
            core.reserve_bootstrap(source, cleanup=lambda: True)
        self.assertEqual(calls, [])
        self.assertEqual(core._next_ticket, 2)

    def test_producer_failure_retains_same_handle_source_and_original_error(self):
        core, source, _, codes, _ = self.bridge()
        loan = core.reserve_bootstrap(source, cleanup=lambda: True)
        failure = RuntimeError('Original interrupted metadata producer')
        codes['produce'] = failure
        with self.assertRaises(RuntimeError) as actual:
            core.produce_bootstrap(loan)
        self.assertIs(actual.exception, failure)
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIs(core._loans[source.ticket], source)
        self.assertEqual(core._inputs[loan.ticket].payload, b'')

    def test_cleanup_failure_retries_same_loan_without_producer_or_cancel(self):
        core, source, calls, _, _ = self.bridge()
        ready = [False]
        cleanup = []
        def close():
            cleanup.append(ready[0])
            return ready[0]
        loan = core.reserve_bootstrap(source, cleanup=close)
        core.produce_bootstrap(loan)
        self.assertFalse(core.close_bootstrap(loan))
        self.assertIs(core._loans[loan.ticket], loan)
        self.assertIs(core._loans[source.ticket], source)
        ready[0] = True
        self.assertTrue(core.close_bootstrap(loan))
        self.assertEqual(cleanup, [False, True])
        self.assertEqual(sum(name == 'produce' for _, name, _ in calls), 1)
        self.assertNotIn('cancel', [name for _, name, _ in calls])
        baseline = len(calls)
        with self.assertRaises(ValueError):
            core.close_bootstrap(loan)
        self.assertEqual(len(calls), baseline)

    def test_wrong_family_copied_and_released_outputs_cannot_get_metadata(self):
        core, source, calls, _, _ = self.bridge()
        loan = core.reserve_bootstrap(source, cleanup=lambda: True)
        for action in (lambda: core.produce_bootstrap(copy.copy(loan)),
                       lambda: core.read_material(loan),
                       lambda: core.close_material(loan)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), 1)
        self.assertTrue(core.close_bootstrap(loan))
        with self.assertRaises(ValueError):
            core.read_bootstrap(loan)

    def test_capacity_and_bad_lengths_are_failures_without_success_payload(self):
        core, source, _, codes, _ = self.bridge()
        codes['reserve'] = -4
        with self.assertRaises(LocalCoreError) as error:
            core.reserve_bootstrap(source, cleanup=lambda: True)
        self.assertEqual(error.exception.code, -4)
        self.assertEqual(set(core._inputs), {1})
        self.assertEqual(set(core._loans), {1})
        core, source, _, codes, _ = self.bridge()
        loan = core.reserve_bootstrap(source, cleanup=lambda: True)
        for value in (-33, 1_048_577):
            codes['length'] = value
            with self.assertRaises(LocalCoreError):
                core.read_bootstrap(loan)
            self.assertEqual(core._inputs[loan.ticket].payload, b'')

    def test_bootstrap_exports_use_the_closed_current_private_abi(self):
        assert_current_local_abi(self, LOCAL_CORE_ABI)
        self.assertEqual(_BOOTSTRAP_SIGNATURES, {
            'reserve': ('i64 i32 i32 i64', 'i32'),
            'produce': ('i64 i32', 'i32'),
            'produce_sdk': ('i64 i32', 'i32'),
            'length': ('i64 i32', 'i32'),
            'close': ('i64 i32', 'i32'),
        })

    def test_sdk_profile_requires_its_own_nominal_output_and_exact_producer(self):
        core, source, calls, _, payload = self.bridge()
        output = core.reserve_sdk_bootstrap(source, cleanup=lambda: True)
        self.assertEqual(output.family, 'bootstrap_sdk')
        before = len(calls)
        for operation in (lambda: core.produce_bootstrap(output),
                          lambda: core.read_bootstrap(output),
                          lambda: core.close_bootstrap(output)):
            with self.assertRaises(ValueError):
                operation()
        self.assertEqual(len(calls), before)
        core.produce_sdk_bootstrap(output)
        self.assertEqual(core.read_sdk_bootstrap(output), payload)
        self.assertEqual([name for family, name, _ in calls if family == 'bootstrap' and name.startswith('produce')], ['produce_sdk'])
        self.assertTrue(core.close_sdk_bootstrap(output))
        self.assertIs(core._loans[source.ticket], source)
