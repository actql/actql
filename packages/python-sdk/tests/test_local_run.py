"""Independent scalar ABI doubles, not physical Wasm or public admission."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input
from actql_sdk._local_preparation import LocalPreparation
from actql_sdk._local_run import LocalRunCustody


class RunCustodyTests(unittest.TestCase):
    def test_restored_run_keeps_same_snapshot_and_children_until_original_close(self):
        from dataclasses import replace
        from test_local_finite_run import FiniteRunFacadeTests
        core, custody, run, snapshot, calls, _ = FiniteRunFacadeTests().bridge()
        snapshot = replace(snapshot, family='submission_lookup')
        core._loans[snapshot.ticket] = snapshot
        before = len(calls)
        restored = custody.reserve_restoration(run.configuration, run.input, snapshot)
        custody.restore_materials(restored)
        custody.bind_restored_preparation(restored, run.preparation)
        custody.restore_run(run, restored)
        self.assertIs(custody._restorations[restored.handle], restored)
        self.assertIs(custody._run_restorations[run.handle], restored)
        self.assertIs(restored.input, run.input)
        self.assertIs(restored.snapshot, snapshot)
        self.assertFalse(any(family == 'program' and name == 'prepare'
                             or family == 'run' and name in ('prepare', 'prepare_sdk', 'reserve_physical_start')
                             for family, name, _ in calls[before:]))
        self.assertEqual([name for family, name, _ in calls[before:] if family == 'material'],
                         ['reserve_restoration', 'restore_sdk', 'restored'])
        self.assertFalse(custody.close_restoration(restored))
        self.assertTrue(custody.close_run(run))
        self.assertTrue(custody.close_restoration(restored))
        self.assertNotIn(restored.handle, custody._restorations)
        self.assertIs(core._loans[snapshot.ticket], snapshot)

    def test_restoration_refusal_preserves_same_parent_and_copies_cannot_reach_core(self):
        from dataclasses import replace
        from test_local_finite_run import FiniteRunFacadeTests
        core, custody, run, snapshot, calls, codes = FiniteRunFacadeTests().bridge()
        snapshot = replace(snapshot, family='submission_lookup')
        core._loans[snapshot.ticket] = snapshot
        restored = custody.reserve_restoration(run.configuration, run.input, snapshot)
        codes['material', 'restore_sdk'] = -35
        with self.assertRaises(LocalCoreError) as failed:
            custody.restore_materials(restored)
        self.assertEqual(failed.exception.code, -35)
        self.assertIs(custody._restorations[restored.handle], restored)
        self.assertIs(core._loans[snapshot.ticket], snapshot)
        before = len(calls)
        for action in (lambda: custody.restore_materials(copy.copy(restored)),
                       lambda: custody.bind_restored_preparation(restored, copy.copy(run.preparation)),
                       lambda: custody.restore_run(copy.copy(run), restored)):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)
        self.assertTrue(custody.close_run(run))
        self.assertTrue(custody.close_restoration(restored))

    def test_original_submitted_projection_uses_nominal_run_and_current_parents(self):
        core, _, custody, inputs, _, configuration, run, calls, _ = self.bridge()
        core._inputs = {}
        core._released = set()
        core._next_ticket = 6
        output = custody.reserve_submitted_rows(run, configuration, inputs[4], cleanup=lambda: True)
        self.assertEqual(calls[-1][:2], ('material', 'reserve_submitted_rows'))
        self.assertEqual(calls[-1][2][:3], (44, 43, 15))
        self.assertIs(core._loans[output.ticket], output)
        before = len(calls)
        for action in (
            lambda: custody.reserve_submitted_rows(copy.copy(run), configuration, inputs[4], cleanup=lambda: True),
            lambda: custody.reserve_submitted_rows(run, copy.copy(configuration), inputs[4], cleanup=lambda: True),
            lambda: custody.reserve_submitted_rows(run, configuration, copy.copy(inputs[4]), cleanup=lambda: True),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        core._loans = {}
        calls = []
        codes = {}
        sequence = [40]

        def call(family, name, *args):
            calls.append((family, name, args))
            if (family, name) in codes:
                result = codes[family, name]
                if isinstance(result, BaseException):
                    core._closing = True
                    raise result
                return result
            if name.startswith(('reserve', 'install')):
                sequence[0] += 1
                return sequence[0]
            if family == 'program' and name == 'prepared_outcome':
                return 1  # Independent declared successful-preparation outcome.
            return 0

        core._call = call
        inputs = [_Input(core._identity, index, 10 + index, 100)
                  for index in range(1, 6)]
        for input in inputs:
            core._loans[input.ticket] = input
        preparation = LocalPreparation(core)
        environment = preparation.install_environment(inputs[0], profile='source-free')
        prepared = preparation.reserve(environment, inputs[1], format='text')
        # The actual Core checks completed preparation again at run.reserve.
        preparation.prepare(prepared)
        custody = LocalRunCustody(core, preparation)
        configuration = custody.install_configuration(inputs[2])
        run = custody.reserve(configuration, prepared, inputs[3])
        return core, preparation, custody, inputs, prepared, configuration, run, calls, codes

    def test_original_parents_reach_run_owner_without_dispatch(self):
        _, _, custody, inputs, prepared, configuration, run, calls, _ = self.bridge()
        self.assertIs(run.preparation, prepared)
        self.assertIs(run.configuration, configuration)
        self.assertIs(run.input, inputs[3])
        self.assertEqual(calls[-2:], [('run', 'install_configuration', (13,)),
                                     ('run', 'reserve', (43, 42, 14))])
        self.assertIsNone(custody.prepare(run))
        self.assertEqual(calls[-2:], [('run', 'prepare', (44,)),
                                     ('run', 'prepared', (44,))])
        self.assertEqual([name for family, name, _ in calls if family == 'run'],
                         ['install_configuration', 'reserve', 'prepare', 'prepared'])

    def test_dispatch_action_is_only_original_reserve_or_reconcile_projection(self):
        _, _, custody, inputs, _, configuration, run, calls, codes = self.bridge()
        for action in (1, 2):
            codes['run', 'dispatch_action'] = action
            self.assertEqual(custody.dispatch_action(run, configuration, inputs[4]), action)
            self.assertEqual(calls[-1], ('run', 'dispatch_action', (44, 43, 15)))
        for code in (-32, -33, 0, 3):
            codes['run', 'dispatch_action'] = code
            with self.assertRaises(LocalCoreError) as caught:
                custody.dispatch_action(run, configuration, inputs[4])
            self.assertEqual(caught.exception.code, code)
            self.assertIs(custody._runs[run.handle], run)
        self.assertNotIn('reserve_physical_start', [name for _, name, _ in calls])

    def test_run_refusal_or_unknown_keeps_exact_loan(self):
        for operation, code in [('prepare', -31), ('prepared', -32), ('prepared', -33)]:
            core, _, custody, inputs, _, _, run, calls, codes = self.bridge()
            codes['run', operation] = code
            with self.assertRaises(LocalCoreError) as caught:
                custody.prepare(run)
            self.assertEqual((caught.exception.operation, caught.exception.code), (operation, code))
            self.assertIs(custody._runs[run.handle], run)
            self.assertIs(core._loans[inputs[3].ticket], inputs[3])
            self.assertEqual(calls[-1], ('run', operation, (44,)))

    def test_start_uses_original_current_configuration_and_physical_fact_loan(self):
        _, _, custody, inputs, _, configuration, run, calls, _ = self.bridge()
        current = custody.install_configuration(inputs[2])
        start = custody.reserve_physical_start(run, current, inputs[4])
        self.assertIs(start.run, run)
        self.assertIs(start.current, current)
        self.assertIs(start.input, inputs[4])
        self.assertIsNot(current, configuration)
        self.assertEqual(calls[-1], ('run', 'reserve_physical_start', (44, 45, 15)))
        self.assertIsNone(custody.confirm_physical_start(start))
        self.assertEqual(calls[-2:], [('run', 'confirm_physical_start', (46,)),
                                     ('run', 'physical_start_ready', (46,))])

    def test_start_unknown_is_not_repeated_or_reinterpreted_as_not_started(self):
        for operation, code in [('confirm_physical_start', -31),
                                ('physical_start_ready', -32),
                                ('physical_start_ready', -33)]:
            core, _, custody, inputs, _, configuration, run, calls, codes = self.bridge()
            start = custody.reserve_physical_start(run, configuration, inputs[4])
            baseline = len(calls)
            codes['run', operation] = code
            with self.assertRaises(LocalCoreError) as caught:
                custody.confirm_physical_start(start)
            self.assertEqual((caught.exception.operation, caught.exception.code), (operation, code))
            self.assertIs(custody._starts[start.handle], start)
            self.assertIs(core._loans[start.input.ticket], start.input)
            self.assertEqual(calls[-1], ('run', operation, (45,)))
            self.assertFalse(any(name.startswith('reserve') for _, name, _ in calls[baseline:]))

    def test_interrupted_owner_invocation_keeps_parents_and_allows_only_cleanup(self):
        core, _, custody, inputs, _, configuration, run, calls, codes = self.bridge()
        start = custody.reserve_physical_start(run, configuration, inputs[4])
        codes['run', 'confirm_physical_start'] = RuntimeError('Independent fuel interruption')
        with self.assertRaisesRegex(RuntimeError, 'Independent fuel interruption'):
            custody.confirm_physical_start(start)
        self.assertIs(custody._starts[start.handle], start)
        self.assertIs(custody._runs[run.handle], run)
        self.assertIs(custody._configurations[configuration.handle], configuration)
        self.assertIs(core._loans[inputs[4].ticket], inputs[4])
        baseline = len(calls)
        with self.assertRaisesRegex(RuntimeError, 'closing'):
            custody.confirm_physical_start(start)
        self.assertEqual(len(calls), baseline)
        self.assertTrue(custody.close_physical_start(start))
        self.assertTrue(custody.close_run(run))
        self.assertTrue(custody.close_configuration(configuration))
        self.assertEqual([name for _, name, _ in calls[baseline:]],
                         ['close_physical_start', 'close', 'close_configuration'])

    def test_cleanup_failure_and_pending_preserve_same_handle_for_retry(self):
        core, _, custody, inputs, _, configuration, run, calls, codes = self.bridge()
        start = custody.reserve_physical_start(run, configuration, inputs[4])
        core._closing = True
        for name, value, close, registry in [
                ('close_physical_start', start, custody.close_physical_start, custody._starts),
                ('close', run, custody.close_run, custody._runs),
                ('close_configuration', configuration, custody.close_configuration,
                 custody._configurations)]:
            for code in (-9, -8):
                codes['run', name] = code
                if code == -9:
                    self.assertFalse(close(value))
                else:
                    with self.assertRaises(LocalCoreError):
                        close(value)
                self.assertIs(registry[value.handle], value)
                self.assertEqual(calls[-1], ('run', name, (value.handle,)))
            codes['run', name] = 0
            self.assertTrue(close(value))
            self.assertNotIn(value.handle, registry)
        self.assertTrue(all(core._loans[value.ticket] is value for value in inputs))

    def test_parent_close_refusal_remains_original_core_decision(self):
        _, preparation, custody, inputs, prepared, configuration, run, calls, codes = self.bridge()
        start = custody.reserve_physical_start(run, configuration, inputs[4])
        codes['run', 'close'] = -9
        codes['run', 'close_configuration'] = -9
        codes['program', 'close_preparation'] = -9
        self.assertFalse(custody.close_run(run))
        self.assertFalse(custody.close_configuration(configuration))
        self.assertFalse(preparation.close_preparation(prepared))
        self.assertEqual(calls[-3:], [('run', 'close', (44,)),
                                     ('run', 'close_configuration', (43,)),
                                     ('program', 'close_preparation', (42,))])
        self.assertIs(custody._starts[start.handle], start)

    def test_copy_foreign_and_released_refs_refuse_before_abi(self):
        _, _, custody, inputs, prepared, configuration, run, calls, _ = self.bridge()
        _, _, foreign, _, _, _, _, foreign_calls, _ = self.bridge()
        start = custody.reserve_physical_start(run, configuration, inputs[4])
        baseline, foreign_baseline = len(calls), len(foreign_calls)
        for action in [lambda: custody.prepare(copy.copy(run)),
                       lambda: custody.close_run(copy.copy(run)),
                       lambda: copy.copy(custody).prepare(run),
                       lambda: copy.copy(custody).close_physical_start(start),
                       lambda: custody.confirm_physical_start(copy.copy(start)),
                       lambda: custody.dispatch_action(run, copy.copy(configuration), inputs[4]),
                       lambda: custody.reserve(configuration, copy.copy(prepared), inputs[3]),
                       lambda: custody.reserve(configuration, prepared, copy.copy(inputs[3])),
                       lambda: foreign.prepare(run)]:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        self.assertEqual(len(foreign_calls), foreign_baseline)
        self.assertTrue(custody.close_physical_start(start))
        baseline = len(calls)
        with self.assertRaises(ValueError):
            custody.confirm_physical_start(start)
        self.assertEqual(len(calls), baseline)

    def test_reservation_refusal_does_not_drop_parents_or_create_loan(self):
        _, _, custody, inputs, prepared, configuration, run, _, codes = self.bridge()
        for name, action, registry in [
                ('install_configuration', lambda: custody.install_configuration(inputs[2]),
                 custody._configurations),
                ('reserve', lambda: custody.reserve(configuration, prepared, inputs[3]), custody._runs),
                ('reserve_physical_start',
                 lambda: custody.reserve_physical_start(run, configuration, inputs[4]), custody._starts)]:
            before = dict(registry)
            codes['run', name] = -3
            with self.assertRaises(LocalCoreError) as caught:
                action()
            self.assertEqual(caught.exception.code, -3)
            self.assertEqual(registry, before)

    def test_foreign_preparation_core_or_copied_bridge_cannot_construct_run_bridge(self):
        core, preparation, _, _, _, _, _, calls, _ = self.bridge()
        foreign_core, _, _, _, _, _, _, _, _ = self.bridge()
        baseline = len(calls)
        for candidate in (copy.copy(preparation), LocalPreparation(foreign_core)):
            with self.assertRaises(ValueError):
                LocalRunCustody(core, candidate)
        self.assertEqual(len(calls), baseline)

    def test_closing_refuses_new_work_before_io(self):
        core, _, custody, inputs, prepared, configuration, run, calls, _ = self.bridge()
        start = custody.reserve_physical_start(run, configuration, inputs[4])
        core._closing = True
        baseline = len(calls)
        for action in [lambda: custody.install_configuration(inputs[2]),
                       lambda: custody.reserve(configuration, prepared, inputs[3]),
                       lambda: custody.prepare(run),
                       lambda: custody.dispatch_action(run, configuration, inputs[4]),
                       lambda: custody.reserve_physical_start(run, configuration, inputs[4]),
                       lambda: custody.confirm_physical_start(start)]:
            with self.assertRaisesRegex(RuntimeError, 'closing'):
                action()
        self.assertEqual(len(calls), baseline)


if __name__ == '__main__':
    unittest.main()
