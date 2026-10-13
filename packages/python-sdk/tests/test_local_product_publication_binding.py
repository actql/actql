"""Actual SQLite binding CAS with scalar Core; not actual Wasm publication."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import LocalProductCleanupPending
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError
import test_local_sdk_start as start_fixture
import test_local_finite_run as run_fixture


class ProductPublicationBindingTests(unittest.TestCase):
    def host(self, directory):
        fixture = start_fixture.SDKStartAssemblyTests()
        self.addCleanup(fixture.doCleanups)
        return fixture, fixture.host(Path(directory))

    def test_original_binding_is_confirmed_before_dispatch_then_kept_until_cleanup(self):
        with TemporaryDirectory(prefix='actql-sdk-binding-') as directory:
            fixture, (host, core, run, events, _) = self.host(directory)
            host._configure_original_compute(run)
            self.assertLess(events.index((9, 'confirm_sdk_publication')), events.index((7, 'produce')))
            self.assertEqual((fixture.row(host).payload, fixture.row(host).generation), (start_fixture.CLAIM, 3))
            original, output = host._publication_bindings[0]
            self.assertIs(original, run)
            self.assertIs(core._loans[output.ticket], output)
            self.assertNotIn(output.ticket, core._inputs)
            self.assertIsNone(host._pending_binding_write)
            self.assertTrue(host.close())
            self.assertFalse(host._publication_bindings)

    def test_commit_reply_loss_keeps_saved_binding_and_original_handle_without_dispatch_or_replay(self):
        with TemporaryDirectory(prefix='actql-sdk-binding-') as directory:
            fixture, (host, core, run, events, _) = self.host(directory)
            store = host._installation._store
            write = store.compare_exchange_many_inspected
            calls = []
            def lose(*args, **kwargs):
                calls.append(write(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown):
                    host._configure_original_compute(run)
                with self.assertRaisesRegex(LocalStorageError, 'lookup'):
                    host._configure_original_compute(run)
            self.assertEqual(len(calls), 1)
            self.assertEqual(fixture.row(host).payload, start_fixture.BINDING)
            output = host._publication_bindings[0][1]
            self.assertIs(core._loans[output.ticket], output)
            self.assertIs(host._pending_binding_write, output)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))
            self.assertFalse(any(name == 'confirm_sdk_publication' for _, name in events))

    def test_current_refusal_before_write_keeps_original_run_and_blocks_dispatch(self):
        with TemporaryDirectory(prefix='actql-sdk-binding-') as directory:
            fixture, (host, _, run, events, failures) = self.host(directory)
            failures[9, 'validate_sdk_publication'] = -32
            with self.assertRaises(LocalCoreError) as failure:
                host._configure_original_compute(run)
            self.assertEqual(failure.exception.code, -32)
            self.assertEqual(fixture.row(host).payload, run_fixture.RUN_BODY)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))

    def test_saved_successor_unknown_is_not_a_confirmed_original_or_execution_permission(self):
        with TemporaryDirectory(prefix='actql-sdk-binding-') as directory:
            fixture, (host, core, run, events, failures) = self.host(directory)
            failures[9, 'confirm_sdk_publication'] = -41
            with self.assertRaises(LocalCoreError) as failure:
                host._configure_original_compute(run)
            self.assertEqual(failure.exception.code, -41)
            self.assertEqual(fixture.row(host).payload, start_fixture.BINDING)
            output = host._publication_bindings[0][1]
            self.assertIs(host._pending_binding_write, output)
            self.assertIs(core._loans[output.ticket], output)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))

    def test_retirement_failure_retries_same_cleanup_without_another_binding_cas(self):
        with TemporaryDirectory(prefix='actql-sdk-binding-') as directory:
            fixture, (host, core, run, events, failures) = self.host(directory)
            failures[9, 'retire_output'] = -9
            with self.assertRaises(LocalProductCleanupPending):
                host._configure_original_compute(run)
            output = host._publication_bindings[0][1]
            self.assertIn(output.ticket, core._inputs)
            self.assertEqual(fixture.row(host).generation, 1)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))
            del failures[9, 'retire_output']
            self.assertIs(host._bind_original_publication(run), output)
            self.assertEqual(sum(event == (9, 'produce') for event in events), 1)
            self.assertEqual(fixture.row(host).generation, 1)
            self.assertNotIn(output.ticket, core._inputs)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
