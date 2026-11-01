"""Actual SQLite/File lookup using mocked original Core reference projection."""
import copy
import os
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_storage import LocalByteStore, StoredBytes
import test_local_commit_store_caller as caller_fixture
import test_local_reader_facts as facts_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class StoredContractLookupTests(unittest.TestCase):
    references = [b'sha256:' + b'e' * 64, b'sha256:' + b'f' * 64]
    bodies = [b'original-request-e\xcc\x81\r\nNULL', b'older-attempt-\xc3\xa9\nnull']

    def references_bridge(self, core, calls, state):
        original_call = core._call
        outputs = {}
        state['reference'] = 0
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'produce_lookup_reference':
                calls.append((family, name, args))
                self.assertEqual(args[1], 31)
                if state['reference']:
                    return state['reference']
                outputs[args[0]] = state.get('override', self.references[args[2]])
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return original_call(family, name, *args)
        core._call = original_byte_fixture_port(call)

    def bridge(self):
        core, parent, publisher, projection, calls, state, _, _, _ = caller_fixture.OriginalCommitStoreCallerTests.bridge(self)
        self.references_bridge(core, calls, state)
        return core, parent, publisher, projection, calls, state

    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=256, max_payload_bytes=1024)

    def populate(self, store):
        original = facts_fixture.ReaderFactsTests().original(store)
        for reference, raw in zip(self.references, self.bodies):
            store.compare_exchange('namespace:20:publication_contract:' + reference.decode('ascii'), None, raw)
        return original

    def test_actual_saved_request_and_older_attempt_bytes_use_core_refs_in_one_snapshot(self):
        core, parent, _, projection, calls, _ = self.bridge()
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = self.populate(store)
            received, sql = [], []
            store._connection.set_trace_callback(sql.append)
            def inspect(read):
                for field in ('request', 'attempt'):
                    projection.project_stored_contract_lookup_key(
                        field, lambda key: read(key, lambda row: received.append(row)))
                    self.assertEqual(projection.pending_outputs, ())
            with projection.serialized():
                store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
            self.assertEqual(received, [StoredBytes(0, raw) for raw in self.bodies])
            self.assertEqual([args[2] for _, name, args in calls if name == 'produce_lookup_reference'], [0, 1])
            self.assertFalse(any(name in ('produce_material', 'produce_schema', 'produce_index_key') for _, name, _ in calls))
            self.assertEqual(sql.count('BEGIN'), 1)
            self.assertEqual(sql.count('ROLLBACK'), 1)
            self.assertFalse(any(q.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT')) for q in sql))
            self.assertIs(core._loans[7], parent)

    def test_missing_dependent_row_and_query_failure_remain_distinct_without_commit_decision(self):
        for outcome in ('absent', 'query_failed'):
            with self.subTest(outcome=outcome), TemporaryDirectory() as directory:
                core, parent, _, projection, calls, _ = self.bridge()
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = facts_fixture.ReaderFactsTests().original(store)
                    received = []
                    def consume(row):
                        if outcome == 'query_failed':
                            raise sqlite3.OperationalError('Original dependent query failed')
                        received.append(row)
                    def inspect(read):
                        projection.project_stored_contract_lookup_key('attempt', lambda key: read(key, consume))
                    if outcome == 'absent':
                        store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
                        self.assertEqual(received, [None])
                        self.assertEqual(projection.pending_outputs, ())
                    else:
                        with self.assertRaises(sqlite3.OperationalError):
                            store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
                        self.assertEqual(len(projection.pending_outputs), 1)
                        self.assertEqual(received, [])
                        with self.assertRaises(RuntimeError):
                            projection.project_stored_contract_lookup_key('request', lambda _: None)
                        self.assertTrue(projection.close())
                    self.assertFalse(store._connection.in_transaction)
                    self.assertIs(core._loans[7], parent)
                    self.assertFalse(any(name in ('finish_commit', 'finish_observation', 'prepare_commit') for _, name, _ in calls))

    def test_invalid_field_parent_and_reference_bytes_cannot_select_physical_keys(self):
        core, parent, _, projection, calls, state = self.bridge()
        for field in (True, 'index', 'identity', '', None):
            with self.assertRaises(ValueError):
                projection.project_stored_contract_lookup_key(field, lambda _: self.fail('Invalid field reached Store'))
        self.assertEqual(calls, [])
        projection._publication = copy.copy(parent)
        with self.assertRaises(ValueError):
            projection.project_stored_contract_lookup_key('request', lambda _: self.fail('Copied parent reached Store'))
        self.assertEqual(calls, [])
        for raw in (b'e' * 64, b'sha256:' + b'g' * 64, b'sha256:' + b'E' * 64,
                    b'sha256:' + b'f' * 64 + b'\n', b'namespace:12:public_index:' + b'e' * 64):
            with self.subTest(raw=raw):
                core, parent, _, projection, _, state = self.bridge()
                state['override'] = raw
                with self.assertRaises(LocalCoreError):
                    projection.project_stored_contract_lookup_key('request', lambda _: self.fail('Bad Core address reached Store'))
                self.assertEqual(len(projection.pending_outputs), 1)
                self.assertTrue(projection.close())

    def test_denial_unknown_cleanup_failure_keep_same_original_output_and_no_next_reference(self):
        for outcome in ('denied', 'unknown', 'cleanup', 'consumer'):
            with self.subTest(outcome=outcome):
                core, parent, _, projection, calls, state = self.bridge()
                state['reference'] = -35 if outcome == 'denied' else -36 if outcome == 'unknown' else 0
                if outcome == 'cleanup':
                    state['cleanup'] = False
                with self.assertRaises(ValueError if outcome == 'consumer' else LocalCoreError):
                    projection.project_stored_contract_lookup_key('attempt', lambda _: True if outcome == 'consumer' else None)
                retained = projection.pending_outputs[0]
                self.assertIs(core._loans[retained.ticket], retained)
                with self.assertRaises(RuntimeError):
                    projection.project_stored_contract_lookup_key('request', lambda _: None)
                state['cleanup'] = False
                self.assertFalse(projection.close())
                self.assertIs(projection.pending_outputs[0], retained)
                state['cleanup'] = True
                self.assertTrue(projection.close())
                self.assertEqual(sum(name == 'reserve' for _, name, _ in calls), 1)
                self.assertIs(core._loans[7], parent)

    def test_actual_file_current_rechecks_run_while_reference_loan_is_live(self):
        helper = facts_fixture.ReaderFactsTests()
        for outcome in ('success', 'mutate', 'denied', 'unknown'):
            with self.subTest(outcome=outcome), helper.file() as (path, root, _, final), TemporaryDirectory() as directory:
                reader = helper.transfer_ready(root, final)
                core, record, publisher, projection, facts, calls, state, _ = helper.bridge(root, reader)
                self.references_bridge(core, calls, state)
                original_call = core._call
                current_calls = []
                def call(family, name, *args):
                    if family == 'publisher' and name == 'authorize':
                        self.assertEqual(args, (17, 31, 0, 0))
                        current_calls.append(bool(projection.pending_outputs))
                        if projection.pending_outputs:
                            if outcome == 'mutate':
                                os.utime(path / 'payload-original', ns=(1, 1))
                            if outcome in ('denied', 'unknown'):
                                return -35 if outcome == 'denied' else -36
                        return 0
                    return original_call(family, name, *args)
                core._call = original_byte_fixture_port(call)
                facts.validate()
                original_input = facts.pending_input
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = self.populate(store)
                    received = []
                    def transaction():
                        with facts.serialized():
                            def inspect(read):
                                projection.project_stored_contract_lookup_key(
                                    'attempt', lambda key: read(key, lambda row: received.append(row)))
                            store.inspect_publication_projected_attached(
                                inspect, original, current=lambda: facts.before_lookup(publisher))
                    if outcome == 'success':
                        transaction()
                        self.assertEqual(received, [StoredBytes(0, self.bodies[1])])
                        self.assertEqual(projection.pending_outputs, ())
                    else:
                        with self.assertRaises(LocalFileError if outcome == 'mutate' else LocalCoreError):
                            transaction()
                        self.assertEqual(received, [])
                        self.assertEqual(len(projection.pending_outputs), 1)
                        self.assertTrue(projection.close())
                    self.assertIn(True, current_calls)
                    self.assertFalse(store._connection.in_transaction)
                    self.assertIs(facts.pending_input, original_input)
                    self.assertIs(core._loans[10], record)
                    self.assertIs(root._readers[id(reader)], reader)
                    state['meta_cleanup'] = False
                    self.assertFalse(facts.close())
                    self.assertIs(facts.pending_input, original_input)
                    state['meta_cleanup'] = True
                    self.assertTrue(facts.close())


if __name__ == '__main__':
    unittest.main()
