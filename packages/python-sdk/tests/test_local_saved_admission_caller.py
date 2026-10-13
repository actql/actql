"""Fresh original saved admission with actual SQLite and scalar Core only."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_product import LocalProductCleanupPending
import test_local_finite_run as run_fixture
import test_local_submission_append as input_fixture


class SavedAdmissionCallerTests(unittest.TestCase):
    def host(self, path):
        fixture = run_fixture.FiniteRunAssemblyTests()
        self.addCleanup(fixture.doCleanups)
        host, core, events, admission = fixture.assembly(path)
        ref = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
        run, original = host._accept_original(ref, input_fixture.INTENT, run_id='original-run')
        self.assertEqual(original, admission)
        return host, core, run, events, admission

    def test_retired_transport_reobserves_same_saved_rows_without_accept_or_execution(self):
        with TemporaryDirectory(prefix='actql-saved-admission-') as directory:
            host, core, run, events, admission = self.host(Path(directory))
            before = len(events)
            store = host._installation._store
            sql = []
            store._connection.set_trace_callback(sql.append)
            with patch.object(host, '_prepare_original', side_effect=AssertionError('Repeated preparation')), \
                    patch.object(store, 'compare_exchange_many_inspected', side_effect=AssertionError('Repeated write')):
                self.assertEqual(host._read_original_saved_admission(run), admission)
            self.assertEqual(events[before:].count(('journal', 'inspect')), 1)
            self.assertFalse(any(family in ('program', 'run', 'task', 'compute', 'source', 'publication')
                                 for family, _ in events[before:]))
            self.assertFalse(any(statement.startswith(('INSERT', 'UPDATE', 'DELETE')) for statement in sql))
            self.assertIs(host._run_rows[0][0], run)
            self.assertIs(core._loans[host._run_rows[0][1].ticket], host._run_rows[0][1])
            self.assertFalse(host._admission_observations)
            self.assertTrue(host.close())

    def test_current_change_does_not_reuse_an_earlier_admission_reply(self):
        with TemporaryDirectory(prefix='actql-saved-admission-') as directory:
            path = Path(directory)
            host, _, run, events, _ = self.host(path)
            (path/'source/account.json').write_bytes(b'{"changed":true}')
            before = len(events)
            with self.assertRaises(LocalFileError):
                host._read_original_saved_admission(run)
            self.assertFalse(any(name == 'admission_length' for _, name in events[before:]))
            self.assertIs(host._admission_observations[run.handle], host._journal_outputs[0])
            self.assertTrue(host.close())

    def test_core_inspection_refusal_retains_same_observation_without_a_new_child(self):
        with TemporaryDirectory(prefix='actql-saved-admission-') as directory:
            host, core, run, events, _ = self.host(Path(directory))
            original = core._call
            def deny(family, name, *args):
                if family == 'journal' and name == 'inspect': return -31
                return original(family, name, *args)
            core._call = deny
            with self.assertRaises(LocalCoreError) as failed:
                host._read_original_saved_admission(run)
            self.assertEqual(failed.exception.code, -31)
            held = host._admission_observations[run.handle]
            before = len(events)
            with self.assertRaises(LocalProductCleanupPending):
                host._read_original_saved_admission(run)
            self.assertEqual(len(events), before)
            self.assertIs(host._admission_observations[run.handle], held)
            self.assertIs(core._loans[held.ticket], held)
            self.assertTrue(host.close())

    def test_failed_observation_close_keeps_original_handle_until_explicit_cleanup(self):
        with TemporaryDirectory(prefix='actql-saved-admission-') as directory:
            host, core, run, events, _ = self.host(Path(directory))
            with patch.object(core, 'close_journal_observation', return_value=False):
                with self.assertRaises(LocalProductCleanupPending):
                    host._read_original_saved_admission(run)
            held = host._admission_observations[run.handle]
            before = len(events)
            with self.assertRaises(LocalProductCleanupPending):
                host._read_original_saved_admission(run)
            self.assertEqual(events[before:], [])
            self.assertIs(core._loans[held.ticket], held)
            self.assertTrue(host.close())
            self.assertFalse(host._admission_observations)
            self.assertFalse(host._run_rows)

    def test_foreign_copied_or_closed_run_cannot_observe_original_admission(self):
        with TemporaryDirectory(prefix='actql-saved-admission-') as directory:
            host, _, run, events, _ = self.host(Path(directory))
            before = len(events)
            for action in (lambda: copy.copy(host)._read_original_saved_admission(run),
                           lambda: host._read_original_saved_admission(copy.copy(run))):
                with self.assertRaises(ValueError): action()
            self.assertEqual(len(events), before)
            self.assertTrue(host.close())
            with self.assertRaises(ValueError): host._read_original_saved_admission(run)


if __name__ == '__main__':
    unittest.main()
