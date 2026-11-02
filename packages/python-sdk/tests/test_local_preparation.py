"""Independent physical ABI doubles; these are not actual Wasm acceptance."""
import copy
from threading import RLock
import unittest

from actql_sdk._local_core import LocalCore, LocalCoreError, _Input
from actql_sdk._local_preparation import LocalPreparation, LocalPreparationFailure, PreparedShape


class PreparationCustodyTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._lock = RLock()
        core._identity = object()
        core._closing = False
        core._loans = {}
        calls = []
        codes = {}
        next_handle = [40]

        def call(family, name, *args):
            self.assertEqual(family, 'program')
            calls.append((name, args))
            if name in codes:
                value = codes[name]
                if isinstance(value, BaseException):
                    core._closing = True
                    raise value
                return value
            if name.startswith('install_') or name == 'reserve_preparation':
                next_handle[0] += 1
                return next_handle[0]
            return {'prepare': 0, 'prepared_outcome': 1, 'prepared_results': 1, 'prepared_tasks': 2,
                    'close_preparation': 0, 'close_environment': 0}[name]

        core._call = call
        config = _Input(core._identity, 1, 11, 4)
        document = _Input(core._identity, 2, 12, 37)
        core._loans[1] = config
        core._loans[2] = document
        return core, LocalPreparation(core), config, document, calls, codes

    def test_original_handles_and_input_kind_only_reach_core(self):
        core, adapter, config, document, calls, _ = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        for format, kind in [('text', 2), ('program', 1), ('submitted', 3)]:
            loan = adapter.reserve(environment, document, format=format)
            self.assertIs(loan.input, document)
            self.assertIs(loan.environment, environment)
            self.assertEqual(calls[-1], ('reserve_preparation', (41, 12, kind)))
            self.assertEqual(adapter.prepare(loan), PreparedShape(1, 2))
            self.assertIs(core._loans[2], document)
        self.assertEqual(calls[0], ('install_environment', (11,)))
        self.assertTrue(all(name in ('install_environment', 'reserve_preparation',
                                   'prepare', 'prepared_outcome', 'prepared_results', 'prepared_tasks')
                            for name, _ in calls))

    def test_published_environment_uses_original_owner_entry(self):
        _, adapter, config, _, calls, _ = self.bridge()
        environment = adapter.install_environment(config, profile='published')
        self.assertIs(environment.input, config)
        self.assertEqual(calls, [('install_source_environment', (11,))])

    def test_foreign_copied_and_released_loans_refuse_before_abi(self):
        _, adapter, config, document, calls, _ = self.bridge()
        _, foreign, _, _, foreign_calls, _ = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        loan = adapter.reserve(environment, document, format='text')
        baseline = len(calls)
        actions = [lambda: adapter.prepare(copy.copy(loan)),
                   lambda: copy.copy(adapter).prepare(loan),
                   lambda: copy.copy(adapter).close_preparation(loan),
                   lambda: copy.copy(adapter).close_environment(environment),
                   lambda: copy.copy(adapter).install_environment(config, profile='source-free'),
                   lambda: foreign.prepare(loan),
                   lambda: adapter.reserve(copy.copy(environment), document, format='text'),
                   lambda: adapter.install_environment(copy.copy(config), profile='source-free'),
                   lambda: adapter.reserve(environment, copy.copy(document), format='program')]
        for action in actions:
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), baseline)
        self.assertEqual(foreign_calls, [])
        self.assertTrue(adapter.close_preparation(loan))
        baseline = len(calls)
        with self.assertRaises(ValueError):
            adapter.prepare(loan)
        with self.assertRaises(ValueError):
            adapter.close_preparation(loan)
        self.assertEqual(len(calls), baseline)

    def test_rejected_preparation_is_not_a_successful_shape(self):
        for name, code in [('prepare', -21), ('prepared_results', -22),
                           ('prepared_tasks', -23)]:
            _, adapter, config, document, calls, codes = self.bridge()
            environment = adapter.install_environment(config, profile='source-free')
            loan = adapter.reserve(environment, document, format='text')
            codes[name] = code
            with self.assertRaises(LocalCoreError) as caught:
                adapter.prepare(loan)
            self.assertEqual((caught.exception.operation, caught.exception.code), (name, code))
            self.assertIs(adapter._preparations[loan.handle], loan)
            self.assertEqual(calls[-1][0], name)

    def test_preparation_trap_retains_borrow_and_blocks_repeated_work(self):
        core, adapter, config, document, calls, codes = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        loan = adapter.reserve(environment, document, format='text')
        codes['prepare'] = RuntimeError('Independent fuel interruption')
        with self.assertRaisesRegex(RuntimeError, 'Independent fuel interruption'):
            adapter.prepare(loan)
        self.assertIs(adapter._preparations[loan.handle], loan)
        self.assertIs(core._loans[document.ticket], document)
        baseline = len(calls)
        with self.assertRaisesRegex(RuntimeError, 'closing'):
            adapter.prepare(loan)
        self.assertEqual(len(calls), baseline)
        self.assertTrue(adapter.close_preparation(loan))
        self.assertTrue(adapter.close_environment(environment))

    def test_close_pending_or_failure_preserves_same_handles(self):
        core, adapter, config, document, _, codes = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        loan = adapter.reserve(environment, document, format='program')
        core._closing = True
        for name, value, close, registry in [
                ('close_preparation', loan, adapter.close_preparation, adapter._preparations),
                ('close_environment', environment, adapter.close_environment, adapter._environments)]:
            codes[name] = -9
            self.assertFalse(close(value))
            self.assertIs(registry[value.handle], value)
            codes[name] = -8
            with self.assertRaises(LocalCoreError):
                close(value)
            self.assertIs(registry[value.handle], value)
            codes[name] = 0
            self.assertTrue(close(value))
            self.assertNotIn(value.handle, registry)
        self.assertIs(core._loans[config.ticket], config)
        self.assertIs(core._loans[document.ticket], document)

    def test_parent_close_refusal_remains_core_decision(self):
        _, adapter, config, document, calls, codes = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        loan = adapter.reserve(environment, document, format='text')
        codes['close_environment'] = -9
        self.assertFalse(adapter.close_environment(environment))
        self.assertEqual(calls[-1], ('close_environment', (environment.handle,)))
        self.assertEqual(adapter.prepare(loan), PreparedShape(1, 2))

    def test_zero_counts_are_preserved_without_invented_execution(self):
        _, adapter, config, document, calls, codes = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        loan = adapter.reserve(environment, document, format='program')
        codes.update(prepared_results=0, prepared_tasks=0)
        self.assertEqual(adapter.prepare(loan), PreparedShape(0, 0))
        self.assertEqual(calls[-3:], [('prepare', (loan.handle,)),
                                     ('prepared_results', (loan.handle,)),
                                     ('prepared_tasks', (loan.handle,))])

    def test_invalid_profile_format_and_closing_refuse_before_abi(self):
        core, adapter, config, document, calls, _ = self.bridge()
        with self.assertRaises(ValueError):
            adapter.install_environment(config, profile='other')
        self.assertEqual(calls, [])
        environment = adapter.install_environment(config, profile='source-free')
        baseline = len(calls)
        for format in (None, True, 'sql'):
            with self.assertRaises(ValueError):
                adapter.reserve(environment, document, format=format)
        core._closing = True
        with self.assertRaisesRegex(RuntimeError, 'closing'):
            adapter.reserve(environment, document, format='text')
        with self.assertRaisesRegex(RuntimeError, 'closing'):
            adapter.install_environment(config, profile='source-free')
        self.assertEqual(len(calls), baseline)

    def test_failed_install_or_reservation_never_issues_a_handle(self):
        core, adapter, config, document, _, codes = self.bridge()
        codes['install_environment'] = -20
        with self.assertRaises(LocalCoreError):
            adapter.install_environment(config, profile='source-free')
        self.assertEqual(adapter._environments, {})
        del codes['install_environment']
        environment = adapter.install_environment(config, profile='source-free')
        codes['reserve_preparation'] = -9
        with self.assertRaises(LocalCoreError):
            adapter.reserve(environment, document, format='text')
        self.assertEqual(adapter._preparations, {})
        self.assertIs(core._loans[document.ticket], document)


    def test_typed_original_failure_does_not_read_plan_counts_or_reprepare(self):
        core, adapter, config, document, calls, codes = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        loan = adapter.reserve(environment, document, format='submitted')
        codes['prepared_outcome'] = 2
        with self.assertRaises(LocalPreparationFailure) as issue:
            adapter.prepare(loan)
        failure = issue.exception
        self.assertIs(adapter.failed_original(failure), loan)
        self.assertIs(core._loans[document.ticket], document)
        self.assertEqual([name for name, _ in calls][-2:], ['prepare', 'prepared_outcome'])
        self.assertFalse(any(name in ('prepared_results', 'prepared_tasks') for name, _ in calls))
        before = len(calls)
        self.assertIs(adapter.failed_original(failure), loan)
        self.assertEqual(len(calls), before)
        self.assertTrue(adapter.close_preparation(loan))
        with self.assertRaises(ValueError):
            adapter.failed_original(failure)
        self.assertTrue(adapter.close_environment(environment))

    def test_failure_data_rejects_copies_foreign_aliases_and_nonterminal_status(self):
        _, adapter, config, document, calls, codes = self.bridge()
        environment = adapter.install_environment(config, profile='source-free')
        loan = adapter.reserve(environment, document, format='submitted')
        codes['prepared_outcome'] = 2
        with self.assertRaises(LocalPreparationFailure) as issue:
            adapter.prepare(loan)
        failure = issue.exception
        _, foreign, _, _, _, _ = self.bridge()
        before = len(calls)
        # Exception copying already refuses its original-only constructor.
        with self.assertRaises(TypeError):
            copy.copy(failure)
        for original, owner in [(failure, foreign),
                                (LocalPreparationFailure(adapter._identity, loan), adapter)]:
            with self.assertRaises(ValueError):
                owner.failed_original(original)
        self.assertEqual(len(calls), before)
        for status in [0, -41, 3, False]:
            _, other, conf, source, observed, values = self.bridge()
            env = other.install_environment(conf, profile='source-free')
            pending = other.reserve(env, source, format='submitted')
            values['prepared_outcome'] = status
            with self.assertRaises((LocalCoreError, RuntimeError)):
                other.prepare(pending)
            self.assertFalse(other._failures)
            self.assertEqual(observed[-1][0], 'prepared_outcome')
            self.assertTrue(other.close_preparation(pending))
            self.assertTrue(other.close_environment(env))
        self.assertTrue(adapter.close_preparation(loan))
        self.assertTrue(adapter.close_environment(environment))
