"""Imported fixture guard/ACK controls with explicit ports, no VM or history."""
from contextlib import contextmanager
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest


path = Path(__file__).resolve().parents[3] / 'scripts/fixtures/python-local-sdk-current-history.py'
spec = spec_from_file_location('actql_pending_history_fixture', path)
history = module_from_spec(spec)
sys.modules[spec.name] = history
spec.loader.exec_module(history)


class PendingHistoryFixtureTests(unittest.TestCase):
    def ports(self, retire):
        events = []
        held = {'lock': False, 'cleanup': False}

        @contextmanager
        def lock():
            self.assertFalse(held['lock'])
            held['lock'] = True
            try:
                yield
            finally:
                held['lock'] = False

        @contextmanager
        def cleanup():
            self.assertTrue(held['lock'])
            events.append('cleanup')
            held['cleanup'] = True
            try:
                yield
            finally:
                held['cleanup'] = False

        prepared = object()
        run = SimpleNamespace(handle=1, preparation=prepared)
        host = SimpleNamespace(
            _core=SimpleNamespace(_lock=lock(), _host_cleanup=cleanup,
                                  _host_fuel_phase=None, _host_retained_work=None),
            _run_loans=[run], _prepared_inputs=[prepared],
            _runs=SimpleNamespace(_run_restorations={}, _runs={1: run}),
            _physical_work=[], _physical_starts=[], _source_free_computes=[],
            _tasks=[], _public_run_references=[], _uncertain_ticket=None,
            _pending_run_write=None, _pending_start_write=None, _pending_binding_write=None)
        original = history._OriginalExecution(host, run, submission=object(), rows_input=object())

        def parents(value):
            self.assertIs(value, original)
            self.assertTrue(held['lock'] and held['cleanup'])
            events.append('parents')
            return retire(value)

        host._retire_original_execution_parents = parents
        return host, original, events

    def test_same_original_uses_existing_cleanup_and_parent_ack(self):
        host, original, events = self.ports(lambda value: True)
        rows = original.rows_input
        history.retire_pending_original_parents(host, original)
        self.assertEqual(events, ['cleanup', 'parents'])
        # Only the selected SDK callable may change the descriptor's fields.
        self.assertIs(original.rows_input, rows)
        self.assertIsNotNone(original.submission)
        self.assertIsNone(host._core._host_fuel_phase)

    def test_false_and_error_keep_original_partial_ack_and_primary(self):
        primary = RuntimeError('Original parent cleanup failed')
        for outcome in (False, 1, primary):
            with self.subTest(outcome=type(outcome).__name__):
                def retire(value):
                    value.submission = None  # An earlier real ACK may be final.
                    if outcome is primary:
                        raise primary
                    return outcome

                host, original, events = self.ports(retire)
                rows = original.rows_input
                with self.assertRaises(RuntimeError) as caught:
                    history.retire_pending_original_parents(host, original)
                if outcome is primary:
                    self.assertIs(caught.exception, primary)
                else:
                    self.assertIs(type(caught.exception), history.LocalProductCleanupPending)
                    self.assertIs(caught.exception.cleanup_host, host)
                self.assertIsNone(original.submission)
                self.assertIs(original.rows_input, rows)
                self.assertIs(host._run_loans[0], original.run)
                self.assertEqual(events, ['cleanup', 'parents'])

    def test_nonfresh_shared_restored_active_and_uncertain_refuse_before_cleanup(self):
        changes = [
            lambda h, o: setattr(o, 'host', object()),
            lambda h, o: setattr(o, 'reference', object()),
            lambda h, o: setattr(o, 'compute', object()),
            lambda h, o: setattr(o, 'physical_start', object()),
            lambda h, o: setattr(o, 'submission', None),
            lambda h, o: h._run_loans.clear(),
            lambda h, o: h._prepared_inputs.clear(),
            lambda h, o: h._runs._run_restorations.update({o.run.handle: object()}),
            lambda h, o: h._runs._runs.update({2: SimpleNamespace(preparation=o.run.preparation)}),
            lambda h, o: h._physical_work.append(object()),
            lambda h, o: h._physical_starts.append(object()),
            lambda h, o: h._source_free_computes.append(object()),
            lambda h, o: h._tasks.append(object()),
            lambda h, o: h._public_run_references.append(object()),
            lambda h, o: setattr(h, '_pending_run_write', object()),
            lambda h, o: setattr(h, '_uncertain_ticket', object()),
            lambda h, o: setattr(h._core, '_host_fuel_phase', 'operation'),
            lambda h, o: setattr(h._core, '_host_retained_work', object()),
        ]
        for change in changes:
            with self.subTest(change=change.__code__.co_firstlineno):
                host, original, events = self.ports(lambda value: self.fail('Retired refused input'))
                change(host, original)
                with self.assertRaises(ValueError):
                    history.retire_pending_original_parents(host, original)
                self.assertEqual(events, [])
        host, _, events = self.ports(lambda value: self.fail('Retired nonnominal input'))
        with self.assertRaises(ValueError):
            history.retire_pending_original_parents(host, SimpleNamespace())
        self.assertEqual(events, [])


class HistoryPhaseControlTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        from unittest.mock import patch
        self.enterContext(patch.object(history.LocalCore, '__init__',
                                       side_effect=AssertionError('No VM selected in these controls')))

    def test_phase_selection_and_ready_namespace_correlation(self):
        import copy
        from tempfile import TemporaryDirectory
        self.assertEqual(history.history_phase('prepare-pending:100'), 'prepare')
        self.assertEqual(history.history_phase('target-pending:100'), 'target')
        for mode in (None, 'pending', 'pending:10', 'fault:current'):
            self.assertIsNone(history.history_phase(mode))
        with self.assertRaises(ValueError):
            history.history_phase('prepare-pending:10')
        with TemporaryDirectory() as directory:
            scratch = Path(directory)
            state = scratch / 'successful-preparation'; state.mkdir()
            source, fixture = 'a' * 40, 'b' * 64
            cohort = {'sourceSha': source, 'moduleSha256': 'c' * 64,
                      'imageSha256': 'd' * 64, 'imageBytes': 123}
            prepared = {'history': 100, 'acceptedPendingHistory': 100,
                        'retiredPendingParentLoans': 100, 'closedPendingHistory': 0,
                        'completedHistory': 0, 'steps': [], 'firstCloseReturned': True,
                        'cleanupFailures': [], 'refusal': None, 'fault': None,
                        'coreMode': 'installed-image/ordinary-operation-owner',
                        'stateIdentity': history.history_state_identity(state)}
            document = {'phase': 'prepare', 'fixtureSha256': fixture,
                        'installedCohort': cohort, 'histories': [prepared]}
            routed, selected = history.ready_history_state(document, scratch, source, fixture)
            self.assertEqual(routed, state.resolve())
            self.assertIs(selected, cohort)  # Routing DATA, not a replacement configuration.
            changes = [
                lambda d: d.update(phase='target'),
                lambda d: d.update(fixtureSha256='e' * 64),
                lambda d: d['installedCohort'].update(sourceSha='e' * 40),
                lambda d: d['histories'][0].update(firstCloseReturned=False),
                lambda d: d['histories'][0].update(acceptedPendingHistory=99),
                lambda d: d['histories'][0].update(retiredPendingParentLoans=99),
                lambda d: d['histories'][0].update(closedPendingHistory=100),
                lambda d: d['histories'][0].update(history=100.0),
                lambda d: d['histories'][0].update(steps=[{'phase': 'drive'}]),
                lambda d: d['histories'][0].update(cleanupFailures=['RuntimeError']),
                lambda d: d['histories'][0]['stateIdentity'].update(inode=0),
            ]
            for change in changes:
                with self.subTest(change=change.__code__.co_firstlineno):
                    altered = copy.deepcopy(document); change(altered)
                    with self.assertRaises(ValueError):
                        history.ready_history_state(altered, scratch, source, fixture)
            link = scratch / 'alias'; link.symlink_to(state, target_is_directory=True)
            altered = copy.deepcopy(document)
            altered['histories'][0]['stateIdentity']['path'] = str(link)
            with self.assertRaises(ValueError):
                history.ready_history_state(altered, scratch, source, fixture)
            history.correlate_history_cohort(dict(cohort), cohort)
            for key, value in [('moduleSha256', 'f' * 64), ('imageBytes', 124), ('imageBytes', 123.0),
                               ('sourceSha', 'f' * 40)]:
                altered = dict(cohort); altered[key] = value
                with self.assertRaises(ValueError):
                    history.correlate_history_cohort(altered, cohort)

    def test_first_retain_counts_only_actual_scan_and_preserves_original_result(self):
        from unittest.mock import patch
        store, result = object(), object()
        callback = SimpleNamespace(store=store, row=None)
        core = SimpleNamespace(_journal_callbacks=lambda ticket: callback)
        host = SimpleNamespace(_installation=SimpleNamespace(_store=store))
        observation = history.PrefixObservation()
        received = []

        def retain(receiver, reference, intent):
            received.append((receiver, reference, intent))
            # Other Core/point/table observations cannot certify this prefix.
            observation.observe(object(), 1, 0, 'client_runs', 0)
            observation.observe(core, 1, 1, 'client_runs', 0)
            observation.observe(core, 1, 0, 'other_namespace', 0)
            for index in range(100):
                callback.row = (str(index).encode(), object())
                observation.observe(core, 1, 0, 'client_runs', 0)
                observation.observe(core, 1, 0, 'client_runs', 0)  # Repeated visit is not a new Run.
            callback.row = None
            observation.observe(core, 1, 0, 'client_runs', 1)
            return result

        reference, intent = object(), b'original-input'
        with patch.object(history.InstalledLocalHost, '_retain_intent', retain):
            with observation.bind(host, core):
                self.assertIs(history.InstalledLocalHost._retain_intent(host, reference, intent), result)
                self.assertIs(history.InstalledLocalHost._retain_intent(host, reference, intent), result)
        self.assertEqual(received, [(host, reference, intent)] * 2)
        self.assertEqual(observation.report(), {'complete': True, 'observedRunRows': 100, 'scanEnded': True})
        with self.assertRaises(ValueError):
            with observation.bind(host, core):
                self.fail('A completed observation was reused')

    def test_prefix_partial_eof_foreign_and_error_never_replace_a_primary(self):
        from unittest.mock import patch
        for count, eof, foreign, raises in [(99, True, False, False), (100, False, False, False),
                                           (101, True, False, False), (100, True, True, False),
                                           (0, False, False, True)]:
            with self.subTest(count=count, eof=eof, foreign=foreign, raises=raises):
                store = object(); callback = SimpleNamespace(store=object() if foreign else store, row=None)
                core = SimpleNamespace(_journal_callbacks=lambda ticket: callback)
                host = SimpleNamespace(_installation=SimpleNamespace(_store=store))
                observation = history.PrefixObservation(); primary = RuntimeError('Original retain failure')

                def retain(receiver, reference, intent):
                    for index in range(count):
                        callback.row = (str(index).encode(), object())
                        observation.observe(core, 1, 0, 'client_runs', 0)
                    if eof:
                        callback.row = None; observation.observe(core, 1, 0, 'client_runs', 1)
                    if raises:
                        raise primary
                    return object()

                with patch.object(history.InstalledLocalHost, '_retain_intent', retain):
                    with observation.bind(host, core):
                        with self.assertRaises(RuntimeError if raises else AssertionError) as caught:
                            history.InstalledLocalHost._retain_intent(host, object(), b'original-input')
                if raises:
                    self.assertIs(caught.exception, primary)
                self.assertFalse(observation.complete)
                self.assertFalse(observation.active)
                self.assertLessEqual(len(observation.keys), 100)

    async def test_original_child_first_close_false_and_primary_are_preserved(self):
        from contextlib import redirect_stderr
        from io import StringIO
        events = []

        class Owner:
            def __init__(self, name): self.name = name
            async def aclose(self): events.append(self.name)

        def closed(): events.append('core'); return True
        client, host = Owner('client'), Owner('host')
        self.assertEqual(await history.close_history_owners(client, host, SimpleNamespace(close=closed), None), [])
        self.assertEqual(events, ['client', 'host', 'core'])
        events.clear()

        def pending(): events.append('core'); return False
        with self.assertRaises(RuntimeError):
            await history.close_history_owners(client, host, SimpleNamespace(close=pending), None)
        self.assertEqual(events, ['client', 'host', 'core'])
        primary = ValueError('Original target failure')
        with redirect_stderr(StringIO()):
            with self.assertRaises(ValueError) as caught:
                try:
                    raise primary
                finally:
                    await history.close_history_owners(client, host, SimpleNamespace(close=pending), primary)
        self.assertIs(caught.exception, primary)
