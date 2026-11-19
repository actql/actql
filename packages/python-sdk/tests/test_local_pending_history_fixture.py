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
