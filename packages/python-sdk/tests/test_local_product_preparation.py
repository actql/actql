"""Actual File/SQLite preparation ordering with scalar Core, not public E2E."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_product import LocalProductCleanupPending
from actql_sdk._local_storage import LocalStorageCommitUnknown
import test_local_submission_append as fixture


class ProductPreparationTests(unittest.TestCase):
    def host(self, path):
        host, core, calls, counts = fixture.LocalSubmissionAppendTests().host(path)
        self.addCleanup(host.close)
        previous = core._call
        sources = {}
        statuses = {}
        documents = []

        def call(family, name, *args):
            if family != 'program':
                return previous(family, name, *args)
            calls.append((family, name, args))
            code = statuses.get(name)
            if isinstance(code, BaseException):
                raise code
            if code is not None:
                return code
            if name == 'install_environment':
                self.assertIsNotNone(core._journal_callbacks(
                    host._installation.binding._current.ticket).reader)
                return 600000
            if name == 'reserve_preparation':
                self.assertEqual(args[0], 600000)
                self.assertEqual(args[2], 3)
                handle = 700000 + args[1]
                sources[handle] = args[1]
                return handle
            if name == 'prepare':
                self.assertIsNotNone(core._journal_callbacks(
                    host._installation.binding._current.ticket).reader)
                documents.append(core._inputs[sources[args[0]] - 100].payload)
                return 0
            if name in ('prepared_results', 'prepared_tasks'):
                return 1
            if name in ('close_preparation', 'close_environment'):
                return 0
            raise AssertionError((family, name, args))

        core._call = call
        return host, core, calls, counts, statuses, documents

    def reference(self, host):
        return {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}

    def test_original_write_and_fresh_lookup_precede_exact_input_preparation(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, core, calls, counts, _, documents = self.host(Path(directory))
            prepared = host._prepare_original(self.reference(host), fixture.INTENT)
            self.assertIs(host._prepared_inputs[0], prepared)
            self.assertEqual(documents, [fixture.INTENT])
            self.assertEqual(counts['append_produce'], 2)
            fixture.LocalSubmissionAppendTests().assert_rows(host)
            self.assertEqual(sum(name == 'install_environment' for family, name, _ in calls
                                 if family == 'program'), 1)
            self.assertFalse(host._append_sources)
            self.assertFalse(host._projections)
            self.assertFalse(any(family in ('run', 'compute', 'source', 'publication')
                                 and name not in ('install_current_configuration',)
                                 for family, name, _ in calls))
            self.assertTrue(host.close())
            self.assertTrue(core._closed)

    def test_existing_original_is_rechecked_without_another_write_or_epoch(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, _, calls, _, _, documents = self.host(Path(directory))
            reference = self.reference(host)
            first = host._prepare_original(reference, fixture.INTENT)
            store = host._installation._store
            original_rows = {key: store.read(key) for key in (
                store.namespaced_key('client_submitted_intent_custody', 'issued'),
                store.namespaced_key('client_submitted_intents', fixture.REQUEST),
                'submission-epoch-authority')}
            with patch.object(store, 'compare_exchange_many_inspected',
                              side_effect=AssertionError('Unexpected submission write')):
                second = host._prepare_original(reference, fixture.INTENT)
            self.assertIsNot(first, second)
            self.assertEqual(documents, [fixture.INTENT, fixture.INTENT])
            self.assertEqual({key: store.read(key) for key in original_rows}, original_rows)
            self.assertEqual(sum(name == 'install_environment' for family, name, _ in calls
                                 if family == 'program'), 1)

    def test_lost_ack_keeps_original_loans_and_does_not_prepare_or_retry(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, core, calls, counts, _, documents = self.host(Path(directory))
            reference = self.reference(host)
            store = host._installation._store
            write = store.compare_exchange_many_inspected
            commits = []
            def lose(*args, **kwargs):
                commits.append(write(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown):
                    host._prepare_original(reference, fixture.INTENT)
            self.assertEqual(len(commits), 1)
            self.assertEqual(counts['append_produce'], 1)
            self.assertEqual(documents, [])
            self.assertFalse(any(family == 'program' for family, _, _ in calls))
            output = host._projections[-1]
            self.assertIs(core._loans[output.ticket], output)
            self.assertIn(output.ticket, host._append_sources)
            fixture.LocalSubmissionAppendTests().assert_rows(host)

    def test_changed_current_after_reservation_refuses_before_checker(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            path = Path(directory)
            host, _, calls, _, _, documents = self.host(path)
            reference = self.reference(host)
            reserve = host._preparation.reserve
            def change(*args, **kwargs):
                prepared = reserve(*args, **kwargs)
                (path / 'source/account.json').write_bytes(b'{"changed":true}')
                return prepared
            with patch.object(host._preparation, 'reserve', side_effect=change):
                with self.assertRaises(LocalFileError):
                    host._prepare_original(reference, fixture.INTENT)
            self.assertEqual(documents, [])
            self.assertEqual(len(host._prepared_inputs), 1)
            self.assertFalse(any(family == 'program' and name == 'prepare'
                                 for family, name, _ in calls))

    def test_checker_trap_keeps_same_issued_handle_and_does_not_repeat(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, _, calls, _, statuses, documents = self.host(Path(directory))
            statuses['prepare'] = RuntimeError('Original Wasm trap')
            with self.assertRaisesRegex(RuntimeError, 'Original Wasm trap'):
                host._prepare_original(self.reference(host), fixture.INTENT)
            self.assertEqual(documents, [])
            self.assertEqual(len(host._prepared_inputs), 1)
            self.assertEqual(sum(family == 'program' and name == 'prepare'
                                 for family, name, _ in calls), 1)

    def test_preparation_refusal_is_not_an_execution_outcome(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, _, calls, _, statuses, _ = self.host(Path(directory))
            statuses['prepared_results'] = -22
            with self.assertRaises(LocalCoreError) as raised:
                host._prepare_original(self.reference(host), fixture.INTENT)
            self.assertEqual(raised.exception.code, -22)
            self.assertEqual(len(host._prepared_inputs), 1)
            self.assertFalse(any(family in ('compute', 'source', 'publication')
                                 for family, _, _ in calls))

    def test_cleanup_failure_keeps_same_preparation_parent_and_input_for_retry(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, core, calls, _, statuses, _ = self.host(Path(directory))
            prepared = host._prepare_original(self.reference(host), fixture.INTENT)
            environment = host._environment
            statuses['close_preparation'] = -9
            self.assertFalse(host.close())
            self.assertIs(host._prepared_inputs[0], prepared)
            self.assertIs(host._environment, environment)
            self.assertIs(core._loans[prepared.input.ticket], prepared.input)
            self.assertFalse(any(family == 'program' and name == 'close_environment'
                                 for family, name, _ in calls))
            statuses['close_preparation'] = 0
            self.assertTrue(host.close())
            self.assertEqual([args for family, name, args in calls
                              if family == 'program' and name == 'close_preparation'],
                             [(prepared.handle,)] * 2)

    def test_input_cleanup_failure_after_transport_close_keeps_original_input(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, core, calls, _, _, documents = self.host(Path(directory))
            reference = self.reference(host)
            close = core.close_input
            held = []
            def pending(source):
                if source in host._append_sources.values():
                    held.append(source)
                    return False
                return close(source)
            with patch.object(core, 'close_input', side_effect=pending):
                with self.assertRaises(LocalProductCleanupPending) as raised:
                    host._prepare_original(reference, fixture.INTENT)
            self.assertIs(raised.exception.cleanup_host, host)
            self.assertEqual(len(held), 1)
            self.assertIs(core._loans[held[0].ticket], held[0])
            self.assertIn(held[0], host._inputs)
            self.assertFalse(host._projections)
            self.assertEqual(documents, [])
            self.assertFalse(any(family == 'program' for family, _, _ in calls))
            self.assertTrue(host.close())
            self.assertFalse(host._append_sources)

    def test_copied_host_and_invalid_transport_refuse_before_physical_operations(self):
        with TemporaryDirectory(prefix='actql-product-preparation-') as directory:
            host, _, calls, _, _, _ = self.host(Path(directory))
            reference = self.reference(host)
            before = len(calls)
            for owner, raw in ((copy.copy(host), fixture.INTENT), (host, b''),
                               (host, b'x' * 65537), (host, bytearray(fixture.INTENT))):
                with self.assertRaises(ValueError):
                    owner._prepare_original(reference, raw)
            self.assertEqual(len(calls), before)


if __name__ == '__main__':
    unittest.main()
