"""Core-key transport with mocked scalars and actual SQLite/File fences."""
import copy
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_storage import LocalByteStore, StoredBytes
import test_local_commit_store_caller as caller_fixture
import test_local_reader_facts as facts_fixture


class IndexLookupProjectionTests(unittest.TestCase):
    bridge = caller_fixture.OriginalCommitStoreCallerTests.bridge

    def test_key_only_reads_actual_saved_index_without_exporting_candidate_cid(self):
        core, parent, _, projection, calls, _, _, _, key = self.bridge()
        with TemporaryDirectory() as directory, LocalByteStore(
                Path(directory) / 'core.sqlite', max_records=8, max_record_bytes=256,
                max_payload_bytes=1024) as store:
            helper = facts_fixture.ReaderFactsTests()
            original = helper.original(store)
            physical_key = 'namespace:12:public_index:' + key.decode('ascii')
            store.compare_exchange(physical_key, None, b'physically-saved-older-index')
            observed = []
            def inspect(read):
                projection.project_index_lookup_key(
                    lambda selected: read(selected, lambda row: observed.append(row)))
                self.assertEqual(projection.pending_outputs, ())
            with projection.serialized():
                store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
            self.assertEqual(observed, [StoredBytes(0, b'physically-saved-older-index')])
            self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)
            self.assertEqual(sum(name == 'produce_index_key' for _, name, _ in calls), 1)
            self.assertFalse(any(name in ('produce_material', 'produce_schema') for _, name, _ in calls))
            self.assertIs(core._loans[7], parent)

    def test_failed_lookup_or_cleanup_retains_same_key_loan_without_substitution(self):
        for outcome in ('query_failed', 'cleanup_failed', 'bool_consumer'):
            with self.subTest(outcome=outcome):
                core, parent, _, projection, calls, state, _, _, _ = self.bridge()
                if outcome == 'cleanup_failed':
                    state['cleanup'] = False
                def consume(key):
                    self.assertEqual(key, 'namespace:12:public_index:' + 'd' * 64)
                    self.assertEqual(len(projection.pending_outputs), 1)
                    if outcome == 'query_failed':
                        raise OSError('Original Store query failed')
                    return True if outcome == 'bool_consumer' else None
                with self.assertRaises(OSError if outcome == 'query_failed' else
                                       ValueError if outcome == 'bool_consumer' else LocalCoreError):
                    projection.project_index_lookup_key(consume)
                retained = projection.pending_outputs
                self.assertEqual(len(retained), 1)
                self.assertIs(core._loans[retained[0].ticket], retained[0])
                with self.assertRaises(RuntimeError):
                    projection.project_index_lookup_key(lambda _: self.fail('No new key loan'))
                state['cleanup'] = False
                self.assertFalse(projection.close())
                self.assertIs(projection.pending_outputs[0], retained[0])
                state['cleanup'] = True
                self.assertTrue(projection.close())
                self.assertIs(core._loans[7], parent)
                self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)

    def test_owner_refusal_bad_key_and_copied_parent_do_not_start_physical_lookup(self):
        core, parent, _, projection, calls, state, _, _, _ = self.bridge()
        # Original Core refusal retains its reserved output, not a new authority.
        state['produce'] = -32
        with self.assertRaises(LocalCoreError):
            projection.project_index_lookup_key(lambda _: self.fail('Current Owner refused'))
        self.assertEqual(len(projection.pending_outputs), 1)
        self.assertTrue(projection.close())
        core, parent, _, projection, calls, _, _, _, _ = self.bridge()
        original_call = core._call
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'produce_index_key':
                return 0  # No output was supplied: read must not invent a key.
            return original_call(family, name, *args)
        core._call = call
        with self.assertRaises((LocalCoreError, KeyError)):
            projection.project_index_lookup_key(lambda _: self.fail('No original output'))
        self.assertEqual(len(projection.pending_outputs), 1)
        self.assertTrue(projection.close())
        core, parent, _, projection, calls, _, _, _, _ = self.bridge()
        projection._publication = copy.copy(parent)
        with self.assertRaises(ValueError):
            projection.project_index_lookup_key(lambda _: self.fail('Copied parent has no custody'))
        self.assertEqual(calls, [])

    def test_actual_original_reader_publisher_store_lookup_uses_one_loan_and_rechecks_mutation(self):
        helper = facts_fixture.ReaderFactsTests()
        for outcome in ('success', 'mutate', 'denied', 'unknown'):
            with self.subTest(outcome=outcome), helper.file() as (path, root, _, final), TemporaryDirectory() as directory:
                reader = helper.transfer_ready(root, final)
                core, record, publisher, projection, facts, calls, state, _ = helper.bridge(root, reader)
                original_call = core._call
                def call(family, name, *args):
                    if family == 'publisher' and name == 'authorize':
                        calls.append((family, name, args))
                        self.assertEqual(args, (17, 31, 0, 0))
                        if outcome == 'mutate':
                            os.utime(path / 'payload-original', ns=(1, 1))
                        return -35 if outcome == 'denied' else -36 if outcome == 'unknown' else 0
                    return original_call(family, name, *args)
                core._call = call
                facts.validate()
                loan = facts.pending_input
                with helper.store(Path(directory) / 'core.sqlite') as store:
                    original = helper.original(store)
                    store.compare_exchange('namespace:12:public_index:' + 'd' * 64,
                                           None, b'stored-previous-index')
                    received = []
                    def transaction():
                        with facts.serialized():
                            def inspect(read):
                                projection.project_index_lookup_key(
                                    lambda key: read(key, lambda row: received.append(row)))
                            store.inspect_publication_projected_attached(
                                inspect, original, current=lambda: facts.before_lookup(publisher))
                    if outcome == 'success':
                        transaction()
                        self.assertEqual(received, [StoredBytes(0, b'stored-previous-index')])
                        self.assertEqual(projection.pending_outputs, ())
                    else:
                        with self.assertRaises(LocalFileError if outcome == 'mutate' else LocalCoreError):
                            transaction()
                        self.assertEqual(received, [])
                        self.assertFalse(any(name == 'produce_index_key' for _, name, _ in calls))
                    self.assertIs(facts.pending_input, loan)
                    self.assertIs(core._loans[10], record)
                    self.assertIs(root._readers[id(reader)], reader)
                    state['meta_cleanup'] = False
                    self.assertFalse(facts.close())
                    self.assertIs(facts.pending_input, loan)
                    state['meta_cleanup'] = True
                    self.assertTrue(facts.close())


if __name__ == '__main__':
    unittest.main()
