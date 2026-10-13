"""Host physical COMMIT assembly with actual File/SQLite and scalar Core only."""
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._local_run import _RunConfiguration
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError, StoredBytes
import test_local_store_current_caller as store_fixture
import test_local_reader_facts as file_fixture


class ProductCommitStoreTests(unittest.TestCase):
    def fixture(self, root, reader):
        case = store_fixture.StoreCurrentCallerTests()
        case.addCleanup = self.addCleanup
        store, core, binding, codes, caller, frames, packets, originals, transfers, scope = case.fixture(root, reader)
        projection, facts, publisher = caller._projection, caller._facts[0], caller._publisher
        previous = core._call
        refs = {0: b'sha256:' + b'f' * 64, 1: b'sha256:' + b'9' * 64,
                7: b'sha256:' + b'e' * 64}
        bodies = {0: b'{"request":"original e\xcc\x81"}', 1: b'{"attempt":"older"}',
                  7: b'{"actual":"stored-old-index"}'}
        def call(family, name, *args):
            if family == 'publication_commit_export':
                self.assertIsNotNone(core._journal_callbacks(binding._current.ticket).reader)
                if name == 'count': return 8
                if name == 'result_count': return 1
                if name in ('produce_material', 'produce_schema'):
                    ordinal, field = args[2:]
                    if name == 'produce_schema':
                        body = (b'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513'
                                if field == 0 else b'{"id":{"nullable":false,"type":"number"}}')
                    else:
                        body = ((refs.get(ordinal) or b'sha256:' + b'1' * 62 + f'{ordinal:02x}'.encode())
                                if field == 3 else bodies.get(ordinal, b'original-Core-material-' + str(ordinal).encode()))
                    core._inputs[args[0] - 200].payload = body
                    return 0
            return previous(family, name, *args)
        core._call = call
        host = InstalledLocalHost.__new__(InstalledLocalHost)
        host._sdk_read_evidence = {}
        host._original = host
        host._core, host._closing = core, False
        host._installation = SimpleNamespace(binding=binding, _store=store)
        host._configuration = _RunConfiguration(core._identity, 31, binding._input, binding._current, True)
        host._publications, host._publishers = [projection._publication], [publisher]
        host._commit_projections, host._reader_facts = [], []
        host._observation_transfers, host._store_observations = [], {}
        host._observation_attempts, host._commit_requests = set(), {}
        host._publication_write_attempts, host._pending_publication_write = set(), None
        host._pending_publication_publisher = None
        host._physical_work = []
        host._uncertain_ticket = None
        host._response_streams = set()
        return host, store, binding, projection, facts, publisher, originals, frames, scope

    def test_original_fields_and_publisher_enter_same_write_frame_but_do_not_ack_run(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            host, store, _, projection, facts, publisher, originals, frames, scope = self.fixture(root, reader)
            sql = []
            store._connection.set_trace_callback(sql.append)
            host._store_original_commit(projection, (facts,), originals, publisher)
            self.assertEqual(store.read(scope), StoredBytes(0, b'sha256:' + b'e' * 64))
            self.assertEqual(sql.count('COMMIT'), 1)
            self.assertIs(host._pending_publication_write, projection)
            self.assertIs(host._pending_publication_publisher, publisher)
            self.assertEqual(host._publication_write_attempts, {projection._publication.ticket})
            self.assertIs(host._reader_facts[0], facts)
            self.assertIs(host._commit_projections[0], projection)
            self.assertFalse(any(name in ('prepare_observation', 'finish_observation', 'finish_commit') for name, _ in frames))
            before = list(sql)
            with self.assertRaises(LocalStorageError): host._store_original_commit(projection, (facts,), originals, publisher)
            self.assertEqual(sql, before)

    def test_commit_unknown_keeps_exact_fact_and_projection_without_a_second_store_invocation(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            host, store, _, projection, facts, publisher, originals, _, _ = self.fixture(root, reader)
            failure = LocalStorageCommitUnknown(store)
            with patch.object(store, 'store_publication_projected_inspected', side_effect=failure) as write:
                with self.assertRaises(LocalStorageCommitUnknown) as raised:
                    host._store_original_commit(projection, (facts,), originals, publisher)
                self.assertIs(raised.exception, failure)
                with self.assertRaises(LocalStorageError): host._store_original_commit(projection, (facts,), originals, publisher)
            self.assertEqual(write.call_count, 1)
            self.assertIs(host._pending_publication_write, projection)
            self.assertIs(host._pending_publication_publisher, publisher)
            self.assertEqual(host._reader_facts, [facts])
            self.assertIsNotNone(facts.pending_input)
            self.assertIs(root._readers[id(reader)], reader)

    def test_failed_original_fact_fill_is_retained_before_any_store_write(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            host, store, _, projection, facts, publisher, originals, _, _ = self.fixture(root, reader)
            with patch.object(facts, 'validate', side_effect=LocalCoreError('original_fact_fill', -4)), \
                    patch.object(store, 'store_publication_projected_inspected') as write:
                with self.assertRaises(LocalCoreError): host._store_original_commit(projection, (facts,), originals, publisher)
            write.assert_not_called()
            self.assertIsNone(host._pending_publication_write)
            self.assertEqual(host._commit_projections, [projection])
            self.assertEqual(host._reader_facts, [facts])
            self.assertFalse(host._publication_write_attempts)

    def test_child_cleanup_failure_keeps_parent_and_same_children_for_retry(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            host, _, _, projection, facts, publisher, originals, _, _ = self.fixture(root, reader)
            host._store_original_commit(projection, (facts,), originals, publisher)
            with patch.object(projection, 'close', return_value=False) as close:
                self.assertFalse(host.close())
                self.assertFalse(host.close())
                self.assertEqual(close.call_count, 2)
            self.assertEqual(host._commit_projections, [projection])
            self.assertEqual(host._publications, [projection._publication])
            with patch.object(projection, 'close', return_value=True), patch.object(facts, 'close', return_value=False):
                self.assertFalse(host.close())
            self.assertEqual(host._reader_facts, [facts])
            self.assertEqual(host._publications, [projection._publication])
            self.assertIs(host._pending_publication_write, projection)
            self.assertIs(host._pending_publication_publisher, publisher)


if __name__ == '__main__':
    unittest.main()
