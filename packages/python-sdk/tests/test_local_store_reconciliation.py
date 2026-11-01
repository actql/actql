"""Actual File/SQLite same-snapshot composition; all Core decisions are mocked."""
import copy
import json
import os
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_observation_transfer import OriginalObservationTransfer
from actql_sdk._local_storage import LocalStorageError
from actql_sdk._local_store_reconciliation import OriginalStoreReconciliation
import test_local_reader_facts as original_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class StoreReconciliationTests(unittest.TestCase):
    ref = b'sha256:' + b'e' * 64
    request_ref = b'sha256:' + b'f' * 64
    attempt_ref = b'sha256:' + b'9' * 64
    index = b'{"stored":"older-index","unicode":"e\xcc\x81/~\xf0\x9f\x98\x80","NULL":null}\r\n'
    request = b'{"original-request":{},"n":9007199254740993}\n'
    attempt = b'{"attempt":"original-earlier","at":"2026-09-17T00:00:00Z"}\r'
    scope_key = 'namespace:12:public_index:' + 'd' * 64
    index_key = 'namespace:20:publication_contract:' + ref.decode()
    request_key = 'namespace:20:publication_contract:' + request_ref.decode()
    attempt_key = 'namespace:20:publication_contract:' + attempt_ref.decode()

    def bridge(self, root, reader, store, *, populate=True):
        helper = original_fixture.ReaderFactsTests()
        core, record, publisher, projection, facts, calls, state, metadata = helper.bridge(root, reader, result=0, binding_index=0)
        facts.validate()
        state.update(publisher=0, lookup=0, observation=0, advance=0, ready=1, work=2,
                     finish=4, borrow=True, transfer_cleanup=True, workspace_cleanup=True)
        workspaces, projected = {}, {}
        packets = []
        original_call = core._call
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'result_count': return 1
            if family == 'workspace':
                calls.append((family, name, args))
                if name == 'reserve':
                    handle = 1000 + args[0]
                    workspaces[handle] = args[0]
                    return handle
                if core._cleanup(workspaces[args[0]]) != 0:
                    return -9
                del workspaces[args[0]]
                return 0
            if family == 'publisher':
                calls.append((family, name, args))
                self.assertEqual((name, args), ('authorize', (17, 31, 0, 0)))
                return state['publisher']
            if family == 'publication':
                calls.append((family, name, args))
                if name in ('prepare_lookup', 'prepare_observation'):
                    self.assertEqual((args[0], args[2], args[3]), (23, 17, 31))
                    packets.append((name, core._inputs[args[1] - 500].payload))
                    return state['lookup' if name == 'prepare_lookup' else 'observation']
                if name == 'advance_observation':
                    return state['advance']
                if name == 'observation_progress':
                    return state['ready' if args[1] == 0 else 'work']
                if name == 'finish_observation':
                    return state['finish']
                self.fail(f'Unexpected Core operation {name}')
            if family == 'publication_commit_export' and name == 'produce_lookup_reference':
                calls.append((family, name, args))
                self.assertTrue(any(name == 'prepare_lookup' for name, _ in packets))
                projected[args[0]] = self.request_ref if args[2] == 0 else self.attempt_ref
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in projected:
                return len(projected[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in projected:
                return projected[args[0]][args[1]]
            if family == 'buffer' and name == 'close' and args[0] != 511 and state['borrow']:
                calls.append((family, name, args))
                return -9
            return original_call(family, name, *args)
        core._call = original_byte_fixture_port(call)
        transfers = [OriginalObservationTransfer(
            projection, publisher, max_source_bytes=512, max_packet_bytes=512,
            cleanup=lambda: state['transfer_cleanup'], stopped=lambda _: not state['borrow'],
            workspace_cleanup=lambda: state['workspace_cleanup'], workspace_stopped=lambda: True)
            for _ in range(2)]
        for transfer in transfers:
            transfer.reserve()
        originals = helper.original(store)
        if populate:
            for key, raw in ((self.scope_key, self.ref), (self.index_key, self.index),
                             (self.request_key, self.request), (self.attempt_key, self.attempt)):
                store.compare_exchange(key, None, raw)
        caller = OriginalStoreReconciliation(projection, (facts,), store, originals, publisher, *transfers)
        return core, record, projection, facts, transfers, caller, calls, state, packets

    def test_same_original_snapshot_forwards_actual_index_and_old_contracts_before_owner_fullchain_finish(self):
        helper = original_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            core, record, projection, facts, transfers, caller, calls, state, packets = self.bridge(root, reader, store)
            metadata = facts.pending_input
            sql = []
            store._connection.set_trace_callback(sql.append)
            caller.prepare()
            self.assertEqual(json.loads(packets[0][1]), {'identity': self.ref.decode(), 'index': self.index.decode()})
            self.assertEqual(json.loads(packets[1][1]), {'kind': 'stored', 'request': self.request.decode(),
                                                      'attempt': self.attempt.decode(), 'index': self.index.decode()})
            self.assertEqual(len(transfers[0].pending_sources), 2)
            self.assertEqual(len(transfers[1].pending_sources), 3)
            self.assertEqual(sql.count('BEGIN'), 1)
            self.assertEqual(sql.count('ROLLBACK'), 1)
            self.assertFalse(any(q.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT')) for q in sql))
            self.assertFalse(any(name == 'finish_commit' for _, name, _ in calls))
            self.assertEqual(caller.advance(7).work, 2)
            self.assertEqual(caller.finish(), 'adopt_committed_index')
            self.assertEqual([args[2] for _, name, args in calls if name == 'produce_lookup_reference'], [0, 1])
            self.assertIs(facts.pending_input, metadata)
            self.assertIs(core._loans[10], record)
            self.assertIs(root._readers[id(reader)], reader)
            before = len(sql)
            with self.assertRaises(RuntimeError):
                caller.prepare()
            self.assertEqual(len(sql), before)
            self.assertFalse(transfers[1].close())
            state['borrow'] = False
            self.assertTrue(all(t.close() for t in reversed(transfers)))
            self.assertIs(core._loans[10], record)
            self.assertTrue(facts.close())
            self.assertEqual(projection.pending_outputs, ())

    def test_only_confirmed_original_scoped_key_absence_transports_not_found(self):
        helper = original_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            _, _, _, _, transfers, caller, calls, state, packets = self.bridge(root, reader, store, populate=False)
            # A foreign scope entry is not adopted and is not an execution grant.
            store.compare_exchange('namespace:12:public_index:'+'a'*64, None, self.ref)
            caller.prepare()
            self.assertEqual(packets, [('prepare_observation', b'{"kind":"not_found"}')])
            self.assertIsNone(transfers[0].pending_input)
            self.assertEqual(transfers[0].pending_sources, ())
            state['finish'] = 3
            self.assertEqual(caller.finish(), 'confirm_uncommitted_failure')
            self.assertFalse(any(name in ('prepare_lookup', 'produce_lookup_reference', 'finish_commit') for _, name, _ in calls))
            state['borrow'] = False
            self.assertTrue(all(t.close() for t in reversed(transfers)))

    def test_actual_sql_query_failure_transports_unknown_keeps_same_inputs_and_requires_explicit_output_cleanup(self):
        helper = original_fixture.ReaderFactsTests()
        for failed_key in (self.scope_key, self.index_key, self.request_key, self.attempt_key):
            with self.subTest(key=failed_key), helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
                reader = helper.transfer_ready(root, final)
                core, record, projection, facts, transfers, caller, calls, state, packets = self.bridge(root, reader, store)
                original_read = store._read_bytes_locked
                def read(key, *, max_bytes=None):
                    if key == failed_key:
                        store._connection.execute('SELECT * FROM nonexistent_original_query_table')
                    return original_read(key, max_bytes=max_bytes)
                store._read_bytes_locked = read
                with self.assertRaises(sqlite3.OperationalError):
                    caller.prepare()
                self.assertEqual(packets[-1], ('prepare_observation', b'{"kind":"query_failed"}'))
                self.assertFalse(store._connection.in_transaction)
                response = transfers[1].pending_input
                original_outputs = projection.pending_outputs
                if original_outputs:
                    with self.assertRaises(RuntimeError):
                        caller.finish()
                    state['cleanup'] = False
                    self.assertFalse(projection.retire_outputs())
                    self.assertIs(projection.pending_outputs[0], original_outputs[0])
                    state['cleanup'] = True
                    self.assertTrue(projection.retire_outputs())
                self.assertIs(transfers[1].pending_input, response)
                self.assertIs(core._loans[response.ticket], response)
                state['finish'] = 1
                self.assertEqual(caller.finish(), 'append_unknown')
                before = len(calls)
                with self.assertRaises(RuntimeError):
                    caller.prepare()
                self.assertEqual(len(calls), before)
                self.assertFalse(any(name in ('finish_commit', 'prepare_commit') for _, name, _ in calls))
                self.assertIs(core._loans[10], record)
                self.assertIs(root._readers[id(reader)], reader)
                state['borrow'] = False
                self.assertTrue(all(t.close() for t in reversed(transfers)))
                self.assertTrue(facts.close())

    def test_missing_index_or_dependent_body_is_not_scoped_absence_or_query_failed(self):
        helper = original_fixture.ReaderFactsTests()
        for missing in (self.index_key, self.request_key, self.attempt_key):
            with self.subTest(missing=missing), helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
                reader = helper.transfer_ready(root, final)
                _, _, projection, _, transfers, caller, calls, state, packets = self.bridge(root, reader, store)
                store._connection.execute('DELETE FROM core_bytes WHERE key=?', (missing,))
                with self.assertRaises(LocalStorageError):
                    caller.prepare()
                self.assertFalse(any(b'"kind":"not_found"' in raw or b'"kind":"query_failed"' in raw for _, raw in packets))
                self.assertIsNone(transfers[1].pending_input)
                self.assertFalse(store._connection.in_transaction)
                self.assertFalse(any(name in ('finish_commit', 'finish_observation') for _, name, _ in calls))
                state['borrow'] = False
                self.assertTrue(projection.retire_outputs())
                self.assertTrue(all(t.close() for t in reversed(transfers)))

    def test_scope_index_chain_and_publisher_rejection_are_original_owner_failures_not_python_match(self):
        helper = original_fixture.ReaderFactsTests()
        for step, code in (('lookup', -32), ('observation', -32), ('observation', -35), ('observation', -36)):
            with self.subTest(step=step, code=code), helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
                reader = helper.transfer_ready(root, final)
                core, record, _, _, transfers, caller, calls, state, packets = self.bridge(root, reader, store)
                state[step] = code
                with self.assertRaises(LocalCoreError) as error:
                    caller.prepare()
                self.assertEqual(error.exception.code, code)
                retained = transfers[0 if step == 'lookup' else 1].pending_input
                self.assertIs(core._loans[retained.ticket], retained)
                self.assertFalse(store._connection.in_transaction)
                self.assertFalse(any(name == 'finish_observation' for _, name, _ in calls))
                state['borrow'] = False
                self.assertTrue(all(t.close() for t in reversed(transfers)))
                self.assertIs(core._loans[10], record)

    def test_current_publisher_and_actual_file_mutation_refuse_before_query_or_adoption(self):
        helper = original_fixture.ReaderFactsTests()
        for when, outcome in (('before', 'denied'), ('before', 'unknown'), ('after', 'denied'), ('after', 'file')):
            with self.subTest(when=when, outcome=outcome), helper.file() as (path, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
                reader = helper.transfer_ready(root, final)
                core, record, projection, facts, transfers, caller, calls, state, packets = self.bridge(root, reader, store)
                original = facts.pending_input
                if when == 'after':
                    caller.prepare()
                if outcome == 'file':
                    os.utime(path/'payload-original', ns=(1, 1))
                else:
                    state['publisher'] = -35 if outcome == 'denied' else -36
                with self.assertRaises(LocalFileError if outcome == 'file' else LocalCoreError):
                    caller.prepare() if when == 'before' else caller.finish()
                self.assertFalse(any(name == 'finish_observation' for _, name, _ in calls))
                if when == 'before':
                    self.assertEqual(packets, [])
                    self.assertFalse(any(name == 'produce_index_key' for _, name, _ in calls))
                self.assertIs(facts.pending_input, original)
                self.assertIs(core._loans[10], record)
                self.assertFalse(store._connection.in_transaction)
                state['borrow'] = False
                self.assertTrue(projection.retire_outputs())
                self.assertTrue(all(t.close() for t in reversed(transfers)))

    def test_file_change_during_owner_finish_prevents_action_escape_and_keeps_original_loans(self):
        helper = original_fixture.ReaderFactsTests()
        with helper.file() as (path, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            core, record, _, facts, transfers, caller, calls, state, _ = self.bridge(root, reader, store)
            caller.prepare()
            metadata = facts.pending_input
            response = transfers[1].pending_input
            original_call = core._call
            def call(family, name, *args):
                result = original_call(family, name, *args)
                if family == 'publication' and name == 'finish_observation':
                    os.utime(path/'payload-original', ns=(1, 1))
                return result
            core._call = original_byte_fixture_port(call)
            with self.assertRaises(LocalFileError):
                caller.finish()
            self.assertIs(facts.pending_input, metadata)
            self.assertIs(transfers[1].pending_input, response)
            self.assertIs(core._loans[response.ticket], response)
            self.assertIs(core._loans[10], record)
            self.assertFalse(any(name == 'finish_commit' for _, name, _ in calls))
            state['borrow'] = False
            self.assertTrue(all(t.close() for t in reversed(transfers)))

    def test_finish_reports_only_core_action_and_bad_owner_scalar_never_becomes_ack(self):
        helper = original_fixture.ReaderFactsTests()
        for code in (True, False, 0, 2, 5, None, -32, -35, -36):
            with self.subTest(code=code), helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
                reader = helper.transfer_ready(root, final)
                _, _, _, _, transfers, caller, _, state, _ = self.bridge(root, reader, store)
                caller.prepare()
                state['finish'] = code
                with self.assertRaises(LocalCoreError):
                    caller.finish()
                self.assertIsNotNone(transfers[1].pending_input)
                state['borrow'] = False
                self.assertTrue(all(t.close() for t in reversed(transfers)))

    def test_copied_inspector_foreign_transfer_and_unreserved_packet_refuse_before_store_queries(self):
        helper = original_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            _, _, projection, facts, transfers, caller, _, state, _ = self.bridge(root, reader, store)
            copied = copy.copy(caller)
            for operation in (copied.prepare, copied.finish, lambda: copied.advance(1)):
                with self.assertRaises(ValueError):
                    operation()
            with self.assertRaises(ValueError):
                OriginalStoreReconciliation(projection, (facts,), store, caller._originals,
                                            caller._publisher, copy.copy(transfers[0]), transfers[1])
            with self.assertRaises(ValueError):
                OriginalStoreReconciliation(projection, (facts,), store, caller._originals,
                                            caller._publisher, transfers[0], transfers[0])
            state['borrow'] = False
            self.assertTrue(transfers[0].close())
            with self.assertRaises(RuntimeError):
                caller.prepare()
            self.assertTrue(transfers[1].close())

    def test_original_projection_output_retirement_is_explicit_and_does_not_reopen_terminal_close(self):
        helper = original_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            core, record, projection, _, transfers, caller, calls, state, _ = self.bridge(root, reader, store)
            state['cleanup'] = False
            with self.assertRaises(LocalCoreError):
                caller.prepare()
            retained = projection.pending_outputs[0]
            self.assertIs(core._loans[retained.ticket], retained)
            with self.assertRaises(RuntimeError):
                projection.project_index_lookup_key(lambda _: self.fail('No replacement loan'))
            self.assertFalse(projection.retire_outputs())
            state['cleanup'] = True
            self.assertTrue(projection.retire_outputs())
            self.assertFalse(projection._closing)
            self.assertTrue(projection.close())
            self.assertTrue(projection.retire_outputs())
            with self.assertRaises(RuntimeError):
                projection.count()
            state['borrow'] = False
            self.assertTrue(all(t.close() for t in reversed(transfers)))
            self.assertIs(core._loans[10], record)


if __name__ == '__main__':
    unittest.main()
