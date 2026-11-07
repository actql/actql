"""Consumed output ordering with scalar Core and real SQLite, not Wasm admission."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import _Input
from actql_sdk._local_product import LocalProductCleanupPending
import test_local_finite_run as run_fixture
import test_local_submission_append as append_fixture


class SubmissionOutputRetirementTests(unittest.TestCase):
    def assembly(self, directory):
        fixture = run_fixture.FiniteRunAssemblyTests()
        self.addCleanup(fixture.doCleanups)
        return fixture.assembly(Path(directory))

    def test_consumed_transport_retires_before_next_reservation_without_closing_originals(self):
        with TemporaryDirectory(prefix='actql-early-output-retirement-') as directory:
            host, core, _, admission = self.assembly(directory)
            reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
            events = []
            held = []
            inputs = []
            retire = core.retire_submission_append_output
            reserve = host._runs.reserve_submitted_rows
            invoke = core._call

            def retire_output(output):
                events.append('retire')
                held.append(output)
                inputs.extend(value for value in core._loans.values() if type(value) is _Input)
                # The complete new row-input copy already exists before retirement.
                self.assertIn(b'"preparing"', core._inputs[host._inputs[-1].ticket].payload)
                return retire(output)

            def reserve_rows(*args, **kwargs):
                self.assertEqual(events, ['retire'])
                events.append('reserve')
                self.assertIs(core._loans[held[0].ticket], held[0])
                self.assertTrue(any(value is held[0] for value in host._projections))
                for value in inputs:
                    self.assertIs(core._loans[value.ticket], value)
                return reserve(*args, **kwargs)

            def observe(family, name, *args):
                if family == 'material' and name == 'validate_submitted_rows':
                    events.append('validate')
                if held and family == 'submission' and name == 'close' and args[0] == held[0].handle:
                    self.fail('Output retirement closed the original submission record')
                return invoke(family, name, *args)

            with (patch.object(core, 'retire_submission_append_output', side_effect=retire_output),
                  patch.object(host._runs, 'reserve_submitted_rows', side_effect=reserve_rows),
                  patch.object(core, '_call', side_effect=observe)):
                _, saved = host._accept_original(reference, append_fixture.INTENT, run_id='original-run')
            self.assertEqual(saved, admission)
            self.assertEqual(events[:2], ['retire', 'reserve'])
            self.assertGreaterEqual(events.count('validate'), 2)
            self.assertEqual(events.count('retire'), 1)
            self.assertTrue(host.close())

    def test_retirement_refusal_retains_original_cleanup_and_blocks_new_reservation(self):
        for failure in (False, RuntimeError('Original output retirement failed')):
            with self.subTest(failure=failure), TemporaryDirectory(prefix='actql-retirement-refusal-') as directory:
                host, core, _, _ = self.assembly(directory)
                reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
                held = []
                before_rows = tuple(host._row_outputs)

                def refuse(output):
                    held.append(output)
                    if isinstance(failure, BaseException):
                        raise failure
                    return failure

                with (patch.object(core, 'retire_submission_append_output', side_effect=refuse),
                      patch.object(host._runs, 'reserve_submitted_rows',
                                   side_effect=AssertionError('Reserved after retirement refusal')) as reserve):
                    with self.assertRaises(RuntimeError if isinstance(failure, BaseException)
                                           else LocalProductCleanupPending) as caught:
                        host._accept_original(reference, append_fixture.INTENT, run_id='original-run')
                    if isinstance(failure, BaseException):
                        self.assertIs(caught.exception, failure)
                    reserve.assert_not_called()
                self.assertEqual(len(held), 1)
                self.assertIs(core._loans[held[0].ticket], held[0])
                self.assertIn(held[0].ticket, core._inputs)
                self.assertTrue(any(value is held[0] for value in host._projections))
                self.assertEqual(tuple(host._row_outputs), before_rows)
                self.assertEqual(len(host._run_loans), 1)
                self.assertIsNone(host._pending_run_write)
                self.assertTrue(host.close())
                self.assertTrue(core._closed)


if __name__ == '__main__':
    unittest.main()
