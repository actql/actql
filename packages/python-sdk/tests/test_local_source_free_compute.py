"""Original scalar custody, not actual Wasm, public admission or publication."""
import copy
import unittest

from actql_sdk._local_core import LOCAL_CORE_ABI, LocalCoreError, _COMPUTE_SIGNATURES
from test_local_run import RunCustodyTests


class SourceFreeComputeTests(unittest.TestCase):
    def bridge(self):
        values = RunCustodyTests().bridge()
        core, _, custody, inputs, _, configuration, run, calls, codes = values
        core._compute_loans = {}
        custody.prepare(run)
        start = custody.reserve_physical_start(run, configuration, inputs[4])
        custody.confirm_physical_start(start)
        return core, custody, inputs, run, start, calls, codes

    def test_closed_abi_addition_is_exact_and_versioned(self):
        self.assertEqual(LOCAL_CORE_ABI, 44)
        self.assertEqual(_COMPUTE_SIGNATURES, {
            'reserve': ('i64 i32 i32', 'i32'),
            'reserve_source_free': ('i64 i32 i32 i32', 'i32'),
            'configure_source_free': ('i64 i32 i32', 'i32'),
            'configure': ('i64 i32', 'i32'),
            'configured': ('i64 i32', 'i32'),
            'close': ('i64 i32', 'i32'),
        })

    def test_original_run_start_and_input_reach_compute_without_source_or_task(self):
        core, custody, inputs, run, start, calls, _ = self.bridge()
        before = len(calls)
        value = custody.reserve_source_free_compute(start, inputs[3])
        self.assertIs(value.start, start)
        self.assertIs(value.start.run, run)
        self.assertIs(value.input, inputs[3])
        self.assertIs(core._compute_loans[value.core.handle], value.core)
        self.assertIsNone(custody.configure_source_free_compute(value, start.current))
        self.assertEqual(calls[before:], [
            ('compute', 'reserve_source_free', (run.handle, start.handle, inputs[3].handle)),
            ('compute', 'configure_source_free', (value.core.handle, start.current.handle)),
            ('compute', 'configured', (value.core.handle,)),
        ])

    def test_copy_foreign_and_released_loans_refuse_before_io(self):
        _, custody, inputs, _, start, calls, _ = self.bridge()
        _, other, _, _, foreign, other_calls, _ = self.bridge()
        baseline = len(calls)
        for action in [lambda: custody.reserve_source_free_compute(copy.copy(start), inputs[3]),
                       lambda: custody.reserve_source_free_compute(foreign, inputs[3]),
                       lambda: custody.reserve_source_free_compute(start, copy.copy(inputs[3]))]:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        value = custody.reserve_source_free_compute(start, inputs[3])
        baseline, other_baseline = len(calls), len(other_calls)
        for action in [lambda: custody.configure_source_free_compute(copy.copy(value), start.current),
                       lambda: other.close_source_free_compute(value),
                       lambda: copy.copy(custody).close_source_free_compute(value)]:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual((len(calls), len(other_calls)), (baseline, other_baseline))
        self.assertTrue(custody.close_source_free_compute(value))
        baseline = len(calls)
        with self.assertRaises(ValueError):
            custody.configure_source_free_compute(value, start.current)
        self.assertEqual(len(calls), baseline)

    def test_configuration_unknown_or_refusal_keeps_exact_handle_and_loans(self):
        for code in (-32, -33):
            core, custody, inputs, run, start, calls, codes = self.bridge()
            value = custody.reserve_source_free_compute(start, inputs[3])
            codes['compute', 'configured'] = code
            with self.assertRaises(LocalCoreError) as caught:
                custody.configure_source_free_compute(value, start.current)
            self.assertEqual(caught.exception.code, code)
            self.assertIs(custody._computes[value.core.handle], value)
            self.assertIs(custody._runs[run.handle], run)
            self.assertIs(custody._starts[start.handle], start)
            self.assertIs(core._loans[inputs[3].ticket], inputs[3])
            self.assertEqual(calls[-1], ('compute', 'configured', (value.core.handle,)))

    def test_pending_cleanup_and_failure_keep_same_compute_for_retry(self):
        core, custody, inputs, run, start, calls, codes = self.bridge()
        value = custody.reserve_source_free_compute(start, inputs[3])
        for code in (-9, -33):
            codes['compute', 'close'] = code
            if code == -9:
                self.assertFalse(custody.close_source_free_compute(value))
            else:
                with self.assertRaises(LocalCoreError):
                    custody.close_source_free_compute(value)
            self.assertIs(custody._computes[value.core.handle], value)
            self.assertIs(core._compute_loans[value.core.handle], value.core)
            self.assertIs(custody._runs[run.handle], run)
            self.assertIs(custody._starts[start.handle], start)
            self.assertIs(core._loans[inputs[3].ticket], inputs[3])
        core._closing = True
        baseline = len(calls)
        with self.assertRaises(RuntimeError):
            custody.configure_source_free_compute(value, start.current)
        self.assertEqual(len(calls), baseline)
        codes['compute', 'close'] = 0
        self.assertTrue(custody.close_source_free_compute(value))
        self.assertNotIn(value.core.handle, custody._computes)
        self.assertNotIn(value.core.handle, core._compute_loans)
        self.assertIs(custody._starts[start.handle], start)
        self.assertEqual([args for family, name, args in calls
                          if family == 'compute' and name == 'close'],
                         [(value.core.handle,)] * 3)

    def test_explicit_current_configuration_is_not_the_original_start_snapshot(self):
        _, custody, inputs, _, start, calls, codes = self.bridge()
        value = custody.reserve_source_free_compute(start, inputs[3])
        current = custody.install_configuration(inputs[2])
        self.assertIsNot(current, start.current)
        custody.configure_source_free_compute(value, current)
        self.assertEqual(calls[-2], ('compute', 'configure_source_free',
                                    (value.core.handle, current.handle)))
        self.assertIs(custody._compute_currents[value.core.handle], current)
        codes['compute', 'configure_source_free'] = -3
        with self.assertRaises(LocalCoreError):
            custody.configure_source_free_compute(value, start.current)
        self.assertIs(custody._compute_currents[value.core.handle], current)
        baseline = len(calls)
        with self.assertRaises(ValueError):
            custody.configure_source_free_compute(value, copy.copy(current))
        self.assertEqual(len(calls), baseline)

    def test_unknown_configuration_trap_leaves_cleanup_reachable(self):
        core, custody, inputs, _, start, _, codes = self.bridge()
        value = custody.reserve_source_free_compute(start, inputs[3])
        codes['compute', 'configure_source_free'] = RuntimeError('Interrupted original invocation')
        with self.assertRaises(RuntimeError):
            custody.configure_source_free_compute(value, start.current)
        self.assertTrue(core._closing)
        self.assertIs(custody._computes[value.core.handle], value)
        self.assertTrue(custody.close_source_free_compute(value))


if __name__ == '__main__':
    unittest.main()
