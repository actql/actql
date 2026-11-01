"""Real File/SQLite read evidence plumbing; scalar Core/publisher only."""
import copy
from contextlib import nullcontext
import json
import os
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError, _Input
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_sdk_read_storage import (
    OriginalSDKReadEvidenceStore, SDKReadEvidenceCleanupPending,
    _DECISION_WORKSPACE, _physical_write,
)
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError, StoredBytes
import test_local_reader_facts as file_fixture
import test_local_store_current_caller as store_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKReadEvidenceStoreTests(unittest.TestCase):
    key = 'sha256:' + '6' * 64
    packet = b'{"opaque-original":"e\xcc\x81/~\xf0\x9f\x98\x80\\r\\n","NULL":null}\r\n'

    def bridge(self, root, reader):
        case = store_fixture.StoreCurrentCallerTests()
        case.addCleanup = self.addCleanup
        store, core, binding, codes, observation, frames, _, _, _, _ = case.fixture(root, reader)
        observation.prepare(binding=binding)
        request = core.reserve_input(b'opaque-original-request', cleanup=lambda: True, stopped=lambda _: True)
        previous = core._call
        outputs, queries, producers = {}, [], []
        state = {'cleanup': True, 'mutate': None}
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'close':
                # Cleanup needs the original physical stop/cleanup callback,
                # not a new permission or borrowed current query transaction.
                return 0 if core._cleanup(args[0] - 200) == 0 else -9
            if family == 'publication_commit_export' and name in (
                    'produce_sdk_read_evidence_decision', 'produce_sdk_read_grant'):
                frame = core._journal_callbacks(binding._current.ticket).reader
                self.assertIsNotNone(frame)
                self.assertIs(frame.owner, store)
                submitted = next(value for value in core._loans.values()
                                 if type(value) is _Input and value.handle == args[1])
                self.assertEqual(core._inputs[submitted.ticket].payload, b'opaque-original-request')
                self.assertEqual(args[2:4], (37, 31))
                rows = []
                frame.read('client_local_read_evidence', self.key, rows.append)
                self.assertEqual(len(rows), 1)
                row = rows[0]
                queries.append(row)
                producers.append(name)
                if row is not None and (row[1].generation != 0 or row[1].payload != self.packet):
                    return -32
                if name == 'produce_sdk_read_grant':
                    if row is None: return -37
                    outputs[args[0]] = (b'sha256:' + b'7' * 64 if args[4] == 1 else b'opaque-issued-grant')
                else:
                    outputs[args[0]] = json.dumps({'body': self.packet.decode(), 'key': self.key,
                        'kind': 'append' if row is None else 'retained', 'revision': 0,
                        'table': 'client_local_read_evidence'}, ensure_ascii=False).encode()
                if state['mutate'] is not None: state['mutate']()
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        holder = OriginalSDKReadEvidenceStore(observation, cleanup=lambda: state['cleanup'])
        return holder, store, core, binding, observation, request, queries, producers, codes, state

    def test_atomic_core_proposal_and_grant_lookup_share_original_store_without_execution(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            holder, store, core, _, observation, request, queries, producers, _, _ = self.bridge(root, reader)
            sql = []
            store._connection.set_trace_callback(sql.append)
            self.assertEqual(holder.persist(request, 37), (0,))
            address = store.namespaced_key('client_local_read_evidence', self.key)
            self.assertEqual(store.read(address), StoredBytes(0, self.packet))
            self.assertIsNone(queries[0])
            self.assertEqual(sql.count('COMMIT'), 1)
            grants = []
            def consume(write):
                self.assertTrue(store._connection.in_transaction)
                self.assertEqual(write.payload, b'opaque-issued-grant')
                self.assertEqual(len(observation._projection.pending_outputs), 2)
                grants.append(True)
            holder.project_grant(request, 37, consume)
            self.assertEqual(grants, [True])
            self.assertEqual([row[1].payload for row in queries[1:]], [self.packet, self.packet])
            with self.assertRaises(LocalStorageError): holder.persist(request, 37)
            self.assertEqual(producers.count('produce_sdk_read_evidence_decision'), 1)
            self.assertIs(core._loans[request.ticket], request)
            self.assertTrue(holder.close())
            self.assertIs(core._loans[request.ticket], request)

    def test_actual_commit_lost_reply_is_only_observed_not_repeated(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            holder, store, _, _, _, request, _, producers, _, _ = self.bridge(root, reader)
            original = store.store_publication_projected_inspected
            def lose(*args, **kwargs):
                original(*args, **kwargs)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'store_publication_projected_inspected', side_effect=lose) as write:
                with self.assertRaises(LocalStorageCommitUnknown): holder.persist(request, 37)
                with self.assertRaises(LocalStorageError): holder.persist(request, 37)
                holder.project_grant(request, 37, lambda _: None)
                self.assertEqual(write.call_count, 1)
            self.assertEqual(producers.count('produce_sdk_read_evidence_decision'), 1)
            self.assertEqual(store.read(store.namespaced_key('client_local_read_evidence', self.key)), StoredBytes(0, self.packet))
            self.assertTrue(holder.close())

    def test_missing_changed_and_query_failure_never_issue_a_grant_or_write(self):
        helper = file_fixture.ReaderFactsTests()
        for problem in ('missing', 'changed', 'query'):
            with self.subTest(problem=problem), helper.file() as (_, root, _, final):
                reader = helper.transfer_ready(root, final)
                holder, store, core, _, observation, request, _, _, _, _ = self.bridge(root, reader)
                if problem == 'changed':
                    store.compare_exchange(store.namespaced_key('client_local_read_evidence', self.key), None, b'changed')
                before = store._connection.total_changes
                context = (patch.object(store, '_inspect_namespace_locked', side_effect=sqlite3.OperationalError('Original query failed'))
                           if problem == 'query' else nullcontext())
                with context:
                    with self.assertRaises(sqlite3.Error if problem == 'query' else LocalCoreError) as error:
                        holder.project_grant(request, 37, lambda _: self.fail('Invalid grant escaped'))
                if problem != 'query': self.assertEqual(error.exception.code, -37 if problem == 'missing' else -32)
                self.assertEqual(store._connection.total_changes, before)
                self.assertIs(core._loans[request.ticket], request)
                if observation._projection.pending_outputs:
                    self.assertFalse(holder.close())
                    self.assertTrue(observation._projection.retire_outputs())
                self.assertTrue(holder.close())

    def test_replacement_transport_and_new_input_cannot_replay_original_attempted_key(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            holder, store, core, _, observation, request, _, producers, _, _ = self.bridge(root, reader)
            holder.persist(request, 37)
            replacement = OriginalSDKReadEvidenceStore(observation, cleanup=lambda: True)
            with self.assertRaises(LocalStorageError): replacement.persist(request, 37)
            self.assertEqual(producers.count('produce_sdk_read_evidence_decision'), 1)
            copied_bytes = core.reserve_input(b'opaque-original-request', cleanup=lambda: True, stopped=lambda _: True)
            before = store._connection.total_changes
            with self.assertRaises(LocalStorageError): replacement.persist(copied_bytes, 37)
            self.assertEqual(store._connection.total_changes, before)
            self.assertFalse(replacement.close())
            self.assertTrue(observation._projection.retire_outputs())
            with self.assertRaises(RuntimeError):
                replacement.project_grant(copied_bytes, 37, lambda _: None)
            holder.project_grant(copied_bytes, 37, lambda _: None)
            self.assertTrue(replacement.close())
            self.assertTrue(holder.close())

    def test_existing_core_checked_evidence_reuses_exact_bytes_without_update(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            holder, store, _, _, _, request, queries, _, _, _ = self.bridge(root, reader)
            address = store.namespaced_key('client_local_read_evidence', self.key)
            store.compare_exchange(address, None, self.packet)
            before = store._connection.total_changes
            sql = []
            store._connection.set_trace_callback(sql.append)
            self.assertEqual(holder.persist(request, 37), (0,))
            self.assertEqual(queries[0][1], StoredBytes(0, self.packet))
            self.assertEqual(store._connection.total_changes, before)
            self.assertFalse(any(query.startswith(('INSERT', 'UPDATE', 'DELETE')) for query in sql))
            self.assertTrue(holder.close())

    def test_file_change_during_proposal_prevents_insert_and_keeps_exact_cleanup(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (path, root, _, final):
            reader = helper.transfer_ready(root, final)
            holder, store, core, _, observation, request, _, _, _, state = self.bridge(root, reader)
            workspace = holder._workspace
            state['mutate'] = lambda: os.utime(path/'payload-original', ns=(1, 1))
            with self.assertRaises(LocalFileError): holder.persist(request, 37)
            self.assertIsNone(store.read(store.namespaced_key('client_local_read_evidence', self.key)))
            self.assertFalse(holder.close())
            self.assertIs(core._loans[workspace.ticket], workspace)
            self.assertTrue(observation._projection.retire_outputs())
            self.assertTrue(holder.close())

    def test_copy_current_denial_and_workspace_cleanup_keep_original_custody(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            holder, store, core, _, _, request, _, producers, codes, state = self.bridge(root, reader)
            workspace = holder._workspace
            self.assertEqual(core._inputs[workspace.ticket].payload, b'')
            for candidate in (copy.copy(holder),):
                with self.assertRaises(ValueError): candidate.persist(request, 37)
            with self.assertRaises(ValueError): holder.persist(copy.copy(request), 37)
            codes['current', 'bind'] = -35
            with self.assertRaises(LocalCoreError): holder.persist(request, 37)
            self.assertEqual(producers, [])
            self.assertFalse(store._connection.in_transaction)
            state['cleanup'] = False
            self.assertFalse(holder.close())
            self.assertIs(holder._workspace, workspace)
            self.assertIs(core._loans[workspace.ticket], workspace)
            state['cleanup'] = True
            self.assertTrue(holder.close())
            self.assertTrue(holder.close())
            self.assertIs(core._loans[request.ticket], request)

    def test_workspace_refusal_precedes_transfer_and_projection_shape_is_closed(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            holder, _, _, _, observation, _, _, producers, codes, _ = self.bridge(root, reader)
            self.assertTrue(holder.close())
            codes['workspace', 'reserve'] = -4
            with self.assertRaises(SDKReadEvidenceCleanupPending) as failure:
                OriginalSDKReadEvidenceStore(observation, cleanup=lambda: True)
            self.assertTrue(failure.exception.cleanup_evidence.close())
            self.assertEqual(producers, [])
        valid = {'body': self.packet.decode(), 'key': self.key, 'kind': 'append', 'revision': 0,
                 'table': 'client_local_read_evidence'}
        for mutation in (valid | {'revision': True}, valid | {'revision': 1}, valid | {'kind': 'allow'},
                         valid | {'extra': None}, valid | {'table': 'public_index'}, valid | {'key': 'sha256:'+'F'*64},
                         valid | {'body': 'x' * 65537}):
            with self.assertRaises(ValueError): _physical_write(json.dumps(mutation).encode())
        with self.assertRaises(ValueError): _physical_write(b'{"body":"a","body":"b"}')
        self.assertEqual(_DECISION_WORKSPACE, 16 * (6 * 65536 + 256) + 8192)
