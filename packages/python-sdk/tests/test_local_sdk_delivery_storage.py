"""Actual same-TX SQLite CAS with scalar Core, not grant/use/delivery ACK."""
import copy
import json
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_sdk_delivery_storage import (
    OriginalSDKDeliveryStore, SDKDeliveryStorageCleanupPending, _physical_plan,
)
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError, StoredBytes
import test_local_reader_facts as file_fixture
import test_local_sdk_read_storage as evidence_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKDeliveryStorageTests(unittest.TestCase):
    def test_grouped_proposal_file_change_rolls_back_before_commit_and_keeps_original_loans(self):
        from actql_sdk._local_files import LocalFileError
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (path, root, _, final):
            holder, store, core, observation, request, _, _, _, rows = self.bridge(
                root, helper.transfer_ready(root, final))
            sql = []
            inserted = [0]
            def changed(statement):
                sql.append(statement)
                if statement.startswith('INSERT INTO core_bytes'):
                    inserted[0] += 1
                    if inserted[0] == 3:
                        original = path / 'payload-original'
                        body = original.read_bytes()
                        original.write_bytes(b'X' + body[1:])
            store._connection.set_trace_callback(changed)
            with self.assertRaises(LocalFileError):
                holder.persist(request, 37)
            self.assertNotIn('COMMIT', sql)
            for row in rows:
                self.assertIsNone(store.read(store.namespaced_key(row['table'], row['key'])))
            self.assertIs(core._loans[request.ticket], request)
            self.assertFalse(holder.close())
            self.assertTrue(observation._projection.retire_outputs())
            self.assertTrue(holder.close())

    def test_one_six_row_proposal_keeps_complete_facts_at_group_and_commit_boundaries(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, observation, request, _, _, _, rows = self.bridge(
                root, helper.transfer_ready(root, final))
            sql = []
            store._connection.set_trace_callback(sql.append)
            with patch.object(observation, '_validate_facts', wraps=observation._validate_facts) as facts:
                self.assertEqual(holder.persist(request, 37), (0,) * 6)
                # Original preparation; bounded proposal before/after; original
                # precommit lookup and its independent post-producer validation.
                self.assertEqual(facts.call_count, 5)
            self.assertEqual(sql.count('COMMIT'), 1)
            for row in rows:
                self.assertEqual(store.read(store.namespaced_key(row['table'], row['key'])),
                    StoredBytes(0, row['body'].encode()))
            first = holder.original_first_output(request)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[request.ticket], request)
            self.assertTrue(holder.close())

    def rows(self, revision=None):
        cids = ['sha256:' + c * 64 for c in '123']
        tables = ['publication_contract'] * 3 + ['delivery_attempt', 'result_read_grant_usage', 'delivery_record_head']
        keys = cids + ['4' * 64, cids[0], cids[1]]
        bodies = ['opaque-grant', 'opaque-attempt', 'opaque-streaming', cids[1], 'opaque-usage', 'opaque-streaming']
        return [{'table': table, 'key': key, 'body': body, 'revision': revision if ordinal == 4 else None}
                for ordinal, (table, key, body) in enumerate(zip(tables, keys, bodies))]

    def bridge(self, root, reader, *, revision=None):
        fixture = evidence_fixture.SDKReadEvidenceStoreTests()
        fixture.addCleanup = self.addCleanup
        values = fixture.bridge(root, reader)
        evidence, store, core, binding, observation, request, _, _, codes, _ = values
        self.assertTrue(evidence.close())
        previous = core._call
        outputs, calls = {}, []
        state = {'cleanup': True, 'current': True, 'retire': True, 'retired': set()}
        observation._projection._cleanup = lambda: state['cleanup']
        rows = self.rows(revision)
        raw = json.dumps(rows, ensure_ascii=False).encode()
        if revision is not None:
            key = store.namespaced_key(rows[4]['table'], rows[4]['key'])
            store.compare_exchange(key, None, b'old-usage')
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'retire_sdk_delivery_output':
                if not state['retire']:
                    return -9
                loan = next(value for value in core._loans.values() if value.handle == args[0])
                if core._cleanup(loan.ticket) != 0:
                    return -9
                state['retired'].add(args[0])
                return 0
            if family == 'publication_commit_export' and name == 'produce_sdk_read_delivery_storage':
                frame = core._journal_callbacks(binding._current.ticket).reader
                self.assertIs(frame.owner, store)
                calls.append(args)
                if not state['current']: return -35
                self.assertEqual(args[1:4], (request.handle, 37, 31))
                if args[0] in outputs:
                    # Original cached return revalidates custody/current. It
                    # selects no new candidate after these physical writes.
                    observed = []
                    frame.read(rows[3]['table'], rows[3]['key'], observed.append)
                    self.assertEqual(observed[0][1].payload, rows[3]['body'].encode())
                    return 0
                outputs[args[0]] = raw
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                if args[0] in state['retired']:
                    return -33
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        holder = OriginalSDKDeliveryStore(observation, cleanup=lambda: state['cleanup'])
        return holder, store, core, observation, request, codes, state, calls, rows

    def test_six_cas_writes_commit_once_and_keep_core_borrow_through_final_current(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, observation, request, _, _, calls, rows = self.bridge(root, helper.transfer_ready(root, final))
            sql = []
            store._connection.set_trace_callback(sql.append)
            self.assertEqual(holder.persist(request, 37), (0,) * 6)
            self.assertEqual(sql.count('COMMIT'), 1)
            for row in rows:
                self.assertEqual(store.read(store.namespaced_key(row['table'], row['key'])), StoredBytes(0, row['body'].encode()))
            self.assertEqual(len(calls), 2)
            self.assertEqual(calls[0], calls[1])
            self.assertFalse(observation._projection.pending_outputs)
            self.assertIs(core._loans[request.ticket], request)
            first = holder.original_first_output(request)
            self.assertIs(core._loans[first.ticket], first)
            with self.assertRaisesRegex(RuntimeError, 'cleanup has completed'):
                core.read_publication_commit_material(first)
            self.assertTrue(holder.close_original_first(request))
            self.assertTrue(holder.close_original_first(request))
            with self.assertRaises(ValueError):
                holder.original_first_output(request)
            self.assertTrue(holder.close())

    def test_usage_cas_revision_is_applied_but_conflict_rolls_back_all_six(self):
        helper = file_fixture.ReaderFactsTests()
        for revision in (0, 7):
            with self.subTest(revision=revision), helper.file() as (_, root, _, final):
                holder, store, _, observation, request, _, _, _, rows = self.bridge(root, helper.transfer_ready(root, final), revision=revision)
                if revision == 0:
                    self.assertEqual(holder.persist(request, 37), (0, 0, 0, 0, 1, 0))
                else:
                    with self.assertRaises(LocalStorageError): holder.persist(request, 37)
                    self.assertIsNone(store.read(store.namespaced_key(rows[0]['table'], rows[0]['key'])))
                    self.assertEqual(store.read(store.namespaced_key(rows[4]['table'], rows[4]['key'])), StoredBytes(0, b'old-usage'))
                    self.assertFalse(holder.close())
                    self.assertTrue(observation._projection.retire_outputs())
                self.assertTrue(holder.close())

    def test_actual_commit_lost_reply_keeps_same_attempt_without_replay(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, observation, request, _, _, _, rows = self.bridge(root, helper.transfer_ready(root, final))
            original = store.compare_exchange_projected_inspected
            def lose(*args, **kwargs):
                original(*args, **kwargs)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_projected_inspected', side_effect=lose) as write:
                with self.assertRaises(LocalStorageCommitUnknown): holder.persist(request, 37)
                with self.assertRaises(LocalStorageError): holder.persist(request, 37)
                replacement = OriginalSDKDeliveryStore(observation, cleanup=lambda: True)
                with self.assertRaises(LocalStorageError): replacement.persist(request, 37)
                self.assertEqual(write.call_count, 1)
                self.assertTrue(replacement.close())
            self.assertEqual(store.read(store.namespaced_key(rows[3]['table'], rows[3]['key'])), StoredBytes(0, rows[3]['body'].encode()))
            self.assertIs(core._loans[request.ticket], request)
            self.assertTrue(holder.close())

    def test_post_write_current_denial_rolls_back_and_cleanup_failure_keeps_workspace(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, observation, request, _, state, _, rows = self.bridge(root, helper.transfer_ready(root, final))
            workspace = holder._workspace
            original = core._call
            produced = [0]
            def call(family, name, *args):
                if name == 'produce_sdk_read_delivery_storage':
                    produced[0] += 1
                    if produced[0] == 2: state['current'] = False
                return original(family, name, *args)
            core._call = original_byte_fixture_port(call)
            with self.assertRaises(LocalCoreError) as error: holder.persist(request, 37)
            self.assertEqual(error.exception.code, -35)
            self.assertIsNone(store.read(store.namespaced_key(rows[0]['table'], rows[0]['key'])))
            self.assertFalse(holder.close())
            self.assertTrue(observation._projection.retire_outputs())
            state['cleanup'] = False
            self.assertFalse(holder.close())
            self.assertIs(core._loans[workspace.ticket], workspace)
            state['cleanup'] = True
            self.assertTrue(holder.close())
            self.assertTrue(holder.close())

    def test_copy_and_reservation_refusal_are_not_permission_or_transport_success(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, _, _, observation, request, codes, _, calls, _ = self.bridge(root, helper.transfer_ready(root, final))
            with self.assertRaises(ValueError): copy.copy(holder).persist(request, 37)
            with self.assertRaises(ValueError): holder.persist(copy.copy(request), 37)
            self.assertFalse(calls)
            self.assertTrue(holder.close())
            codes['workspace', 'reserve'] = -4
            with self.assertRaises(SDKDeliveryStorageCleanupPending) as pending:
                OriginalSDKDeliveryStore(observation, cleanup=lambda: True)
            self.assertTrue(pending.exception.cleanup_storage.close())
        rows = self.rows()
        for mutate in (lambda r: r[0].update(revision=True), lambda r: r[4].update(revision=True),
                       lambda r: r[5].update(table='public_index'), lambda r: r[3].update(key='X'*64),
                       lambda r: r[0].update(extra=None), lambda r: r[2].update(body='x'*65537)):
            current = self.rows();mutate(current)
            with self.assertRaises(ValueError): _physical_plan(json.dumps(current).encode())
        self.assertEqual(len(_physical_plan(json.dumps(rows).encode())), 6)

    def test_transport_retirement_failure_keeps_registered_first_without_commit_or_reprojection(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, observation, request, _, state, calls, rows = self.bridge(root, helper.transfer_ready(root, final))
            state['retire'] = False
            with self.assertRaises(LocalCoreError) as issue:
                holder.persist(request, 37)
            self.assertEqual(issue.exception.code, -9)
            first = holder.original_first_output(request)
            self.assertIs(core._loans[first.ticket], first)
            self.assertFalse(observation._projection.pending_outputs)
            self.assertIsNone(store.read(store.namespaced_key(rows[3]['table'], rows[3]['key'])))
            before = len(calls)
            with self.assertRaises(LocalStorageError):
                holder.persist(request, 37)
            self.assertEqual(len(calls), before)
            with self.assertRaises(ValueError):
                holder.original_first_output(copy.copy(request))
            state['cleanup'] = False
            self.assertFalse(holder.close_original_first(request))
            self.assertIs(core._loans[first.ticket], first)
            state['cleanup'] = True
            self.assertTrue(holder.close_original_first(request))
            self.assertTrue(holder.close())

    def test_retained_first_capacity_refusal_precedes_core_preparation(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, _, request, codes, _, calls, rows = self.bridge(root, helper.transfer_ready(root, final))
            original_workspace = holder._workspace
            codes['workspace', 'reserve'] = -4
            with self.assertRaises(LocalCoreError) as issue:
                holder.persist(request, 37)
            self.assertEqual(issue.exception.code, -4)
            self.assertEqual(calls, [])
            self.assertFalse(holder._first_outputs)
            self.assertFalse(holder._first_workspaces)
            self.assertFalse(holder._uncertain_first)
            self.assertIs(core._loans[original_workspace.ticket], original_workspace)
            self.assertIs(core._loans[request.ticket], request)
            self.assertIsNone(store.read(store.namespaced_key(rows[3]['table'], rows[3]['key'])))
            self.assertTrue(holder.close())

    def test_transport_cleanup_reentry_close_refuses_commit_and_keeps_first_custody(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, observation, request, _, _, _, rows = self.bridge(root, helper.transfer_ready(root, final))
            original = core._call
            def call(family, name, *args):
                if family == 'publication_commit_export' and name == 'retire_sdk_delivery_output':
                    self.assertFalse(holder.close())
                return original(family, name, *args)
            core._call = original_byte_fixture_port(call)
            with self.assertRaisesRegex(RuntimeError, 'storage is closing'):
                holder.persist(request, 37)
            self.assertIsNone(store.read(store.namespaced_key(rows[3]['table'], rows[3]['key'])))
            self.assertFalse(observation._projection.pending_outputs)
            first = holder._first_outputs[request.ticket]
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[request.ticket], request)
            with self.assertRaises(ValueError):
                holder.original_first_output(request)
            self.assertTrue(holder.close())
