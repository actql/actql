"""Two actual original reader descriptors fenced through one Store lookup."""
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import _Output
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_storage import ByteFence, CapacityReservation
from actql_sdk._local_store_reconciliation import OriginalStoreReconciliation
import test_local_reader_facts as file_fixture
import test_local_store_reconciliation as observation_fixture


class StoreInventoryFactsTests(unittest.TestCase):
    @contextmanager
    def fixture(self):
        helper = file_fixture.ReaderFactsTests()
        case = observation_fixture.StoreReconciliationTests()
        with helper.file() as (path0, root0, _, final0), helper.file() as (path1, root1, _, final1), TemporaryDirectory() as directory, helper.store(Path(directory) / 'original.sqlite') as store:
            reader0 = helper.transfer_ready(root0, final0)
            reader1 = helper.transfer_ready(root1, final1)
            core, _, projection, first, transfers, old, calls, state, _ = case.bridge(root0, reader0, store)
            record = _Output(core._identity, core._next_ticket, 72, 65536, 'payload_record')
            core._next_ticket += 1
            core._loans[record.ticket] = record
            second = OriginalReaderFacts(projection, record, root1, reader1, 1, 1,
                'sha256:' + '1' * 64, 'sha256:' + '4' * 64,
                cleanup=lambda: state['meta_cleanup'], stopped=lambda _: True)
            original = core._call
            count = [2]
            def call(family, name, *args):
                if family == 'publication_commit_export' and name == 'result_count': return count[0]
                if family == 'publication_commit_export' and name == 'validate_payload_binding' and args[1] == record.handle:
                    self.assertEqual(args, (23, 72, 31, 1, 1))
                    calls.append((family, name, args))
                    return state['binding']
                if family == 'payload_record' and name == 'validate_snapshot' and args[0] == record.handle:
                    self.assertEqual(args[2], 31)
                    calls.append((family, name, args))
                    return state['snapshot']
                return original(family, name, *args)
            core._call = call
            store.compare_exchange('second-original', None, b'second-sealed')
            self.assertTrue(store.reserve_capacity('publication_payload', 'second-original', 64, 1, 128, 2))
            originals = (*old._originals, (ByteFence('second-original', 0, b'second-sealed'),
                         CapacityReservation('publication_payload', 'second-original', 64, 1)))
            caller = OriginalStoreReconciliation(projection, (first, second), store, originals,
                old._publisher, *transfers)
            try:
                yield caller, core, store, state, count, calls, first, second, path0, path1
            finally:
                state['borrow'] = False
                self.assertTrue(all(transfer.close() for transfer in reversed(transfers)))
                self.assertTrue(first.close())
                self.assertTrue(second.close())

    def test_complete_inventory_keeps_both_descriptors_active_through_same_lookup_and_finish(self):
        with self.fixture() as (caller, core, _, _, _, _, first, second, _, _):
            original = core._call
            def check(family, name, *args):
                if family == 'publication' and name in ('prepare_lookup', 'prepare_observation', 'finish_observation'):
                    self.assertTrue(first._active and second._active)
                    self.assertIsNotNone(first._reader.descriptor)
                    self.assertIsNotNone(second._reader.descriptor)
                return original(family, name, *args)
            core._call = check
            caller.prepare()
            self.assertEqual(caller.advance(7).work, 2)
            self.assertEqual(caller.finish(), 'adopt_committed_index')
            self.assertIsNotNone(first.pending_input)
            self.assertIsNotNone(second.pending_input)

    def test_missing_inventory_refuses_before_any_scoped_query(self):
        with self.fixture() as (caller, _, store, _, _, _, first, _, _, _):
            incomplete = OriginalStoreReconciliation(caller._projection, (first,), store,
                caller._originals, caller._publisher, caller._lookup, caller._response)
            sql = []
            store._connection.set_trace_callback(sql.append)
            with self.assertRaisesRegex(ValueError, 'Incomplete original'):
                incomplete.prepare()
            self.assertFalse(any('SELECT generation,payload FROM core_bytes' in statement for statement in sql))
            self.assertIsNone(caller._response.pending_input)

    def test_later_ordinal_mutation_refuses_before_query_and_keeps_original_descriptors(self):
        with self.fixture() as (caller, _, store, _, _, _, first, second, _, path1):
            (path1 / 'payload-original').write_bytes(b'changed later original')
            sql = []
            store._connection.set_trace_callback(sql.append)
            with self.assertRaises(LocalFileError): caller.prepare()
            self.assertIsNotNone(first._reader.descriptor)
            self.assertIsNotNone(second._reader.descriptor)
            self.assertIsNone(caller._response.pending_input)
            self.assertFalse(any('SELECT generation,payload FROM core_bytes' in statement for statement in sql))

    def test_later_ordinal_change_during_owner_finish_cannot_escape_as_adoption(self):
        with self.fixture() as (caller, core, _, _, _, _, first, second, _, path1):
            caller.prepare()
            original = core._call
            def change(family, name, *args):
                if family == 'publication' and name == 'finish_observation':
                    (path1 / 'payload-original').write_bytes(b'changed during finish')
                return original(family, name, *args)
            core._call = change
            with self.assertRaises(LocalFileError): caller.finish()
            self.assertIsNotNone(first.pending_input)
            self.assertIsNotNone(second.pending_input)
            self.assertIsNotNone(caller._response.pending_input)

    def test_duplicate_or_reordered_original_result_ordinals_are_rejected(self):
        with self.fixture() as (caller, _, store, _, _, _, first, second, _, _):
            for facts in ((), (first, first), (second, first)):
                with self.subTest(facts=facts), self.assertRaises(ValueError):
                    OriginalStoreReconciliation(caller._projection, facts, store,
                        caller._originals, caller._publisher, caller._lookup, caller._response)


if __name__ == '__main__':
    unittest.main()
