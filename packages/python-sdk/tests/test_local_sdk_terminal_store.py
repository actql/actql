"""Actual SQLite successor/ACK-loss transport; scalar Core, no real Wasm."""
import copy
import json
import sqlite3
import unittest
from unittest.mock import patch

from actql_sdk._local_core import _Output, LocalCoreError, _PUBLICATION_COMMIT_EXPORT_SIGNATURES
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError, StoredBytes
import test_local_sdk_read_original as nominal_fixture
import test_local_retained_delivery_codecs as delivery_fixture
import test_local_reader_facts as file_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKTerminalPortTests(unittest.TestCase):
    def test_exact_signatures_loans_and_no_boolean_status(self):
        core, clock, first, calls, status = nominal_fixture.SDKReadOriginalTests.bridge(self)
        output = _Output(core._identity, 8, 31, 1048576, 'publication_commit_export')
        core._loans[8] = output
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['produce_sdk_terminal_storage'],
                         ('i64 i32 i32 i32 i32', 'i32'))
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['observe_sdk_terminal'],
                         ('i64 i32 i32', 'i32'))
        for child, original, tick, config in ((copy.copy(output), first, clock, 23),
                (output, copy.copy(first), clock, 23), (output, first, copy.copy(clock), 23),
                (first, first, clock, 23), (output, first, clock, True)):
            with self.assertRaises(ValueError):
                core.produce_publication_sdk_terminal_storage(child, original, tick, config)
        self.assertEqual(calls, [])
        core.produce_publication_sdk_terminal_storage(output, first, clock, 23)
        core.observe_publication_sdk_terminal(first, 23)
        self.assertEqual(calls, [('publication_commit_export', 'produce_sdk_terminal_storage',
                                (31, 19, 17, 23)),
                               ('publication_commit_export', 'observe_sdk_terminal', (19, 23))])
        for result in (True, False, None, 0.0):
            status[0] = result
            with self.assertRaises(RuntimeError): core.observe_publication_sdk_terminal(first, 23)
        for result in (-41, -35, -9, 1):
            status[0] = result
            with self.assertRaises(LocalCoreError) as error:
                core.observe_publication_sdk_terminal(first, 23)
            self.assertEqual(error.exception.code, result)
            self.assertIs(core._loans[first.ticket], first)

    def test_callback_cannot_close_original_then_return_success(self):
        core, clock, first, _, _ = nominal_fixture.SDKReadOriginalTests.bridge(self)
        def close(*_):
            del core._loans[first.ticket]
            return 0
        core._call = original_byte_fixture_port(close)
        with self.assertRaises(ValueError): core.observe_publication_sdk_terminal(first, 23)
        self.assertIs(core._loans[clock.ticket], clock)


class SDKTerminalStoreTests(unittest.TestCase):
    def bridge(self, root, reader):
        fixture = delivery_fixture.RetainedDeliveryCodecStoreTests()
        fixture.addCleanup = self.addCleanup
        holder, store, core, observation, request, first, clock, _, state = fixture.bridge(root, reader)
        receipt, record, head = ['sha256:' + c * 64 for c in '562']
        rows = [dict(table='publication_contract', key=receipt, revision=None, body='opaque-receipt'),
                dict(table='publication_contract', key=record, revision=None, body='opaque-terminal'),
                dict(table='delivery_record_head', key=head, revision=0, body='opaque-terminal')]
        raw = json.dumps(rows).encode()
        previous = core._call
        outputs, calls = {}, []
        state.update(terminal_status=0, on_terminal=lambda: None)
        def saved(frame):
            for row in rows:
                found = []
                frame.read(row['table'], row['key'], found.append)
                if (not found or found[0][1] is None
                        or found[0][1].generation != (1 if row['table'] == 'delivery_record_head' else 0)
                        or found[0][1].payload != row['body'].encode()):
                    return -41
            return 0
        def call(family, name, *args):
            if name in ('produce_sdk_terminal_storage', 'observe_sdk_terminal'):
                frame = core._journal_callbacks(observation._binding._current.ticket).reader
                self.assertIs(frame.owner, store)
                self.assertTrue(store._connection.in_transaction)
                self.assertIs(core._loans[first.ticket], first)
                calls.append((name, args))
                state['on_terminal']()
                if state['terminal_status']: return state['terminal_status']
                if name == 'observe_sdk_terminal': return saved(frame)
                if args[0] in outputs: return saved(frame)
                self.assertIs(holder._payload_outputs[request.ticket], core._loans[
                    holder._payload_outputs[request.ticket].ticket])
                outputs[args[0]] = raw
                return 0
            if name == 'length' and args[0] in outputs: return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return holder, store, core, request, first, clock, state, calls, rows

    def test_success_is_observed_in_new_transaction_not_precommit_callback(self):
        files = file_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            holder, store, core, request, first, clock, _, calls, rows = self.bridge(root, files.transfer_ready(root, final))
            changes = store._connection.total_changes
            holder.persist_original_terminal(request, clock)
            self.assertEqual(store._connection.total_changes - changes, 3)
            self.assertEqual([name for name, _ in calls], ['produce_sdk_terminal_storage'] * 2 + ['observe_sdk_terminal'])
            self.assertEqual(calls[0], calls[1])
            for row in rows:
                self.assertEqual(store.read(store.namespaced_key(row['table'], row['key'])),
                    StoredBytes(1 if row['table'] == 'delivery_record_head' else 0, row['body'].encode()))
            self.assertFalse(store._connection.in_transaction)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[clock.ticket], clock)
            self.assertTrue(holder.close())

    def test_commit_lost_ack_lookup_only_and_cleanup_retains_same_child(self):
        files = file_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            holder, store, core, request, first, clock, state, calls, _ = self.bridge(root, files.transfer_ready(root, final))
            physical = store.compare_exchange_projected_inspected
            def lose(*args, **kwargs):
                physical(*args, **kwargs)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_projected_inspected', side_effect=lose) as write:
                with self.assertRaises(LocalStorageCommitUnknown): holder.persist_original_terminal(request, clock)
                with self.assertRaises(LocalStorageError): holder.persist_original_terminal(request, clock)
                holder.observe_original_terminal(request, clock)
                self.assertEqual(write.call_count, 1)
            child = holder._payload_outputs[request.ticket]
            state['cleanup'] = False
            self.assertFalse(holder.close_original_first(request))
            self.assertIs(core._loans[child.ticket], child)
            self.assertIs(core._loans[first.ticket], first)
            state['cleanup'] = True
            before = len(calls)
            self.assertTrue(holder.close_original_first(request))
            self.assertEqual(len(calls), before)
            self.assertTrue(holder.close())

    def test_lookup_failure_and_changed_head_do_not_retry_commit(self):
        files = file_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            holder, store, _, request, _, clock, state, calls, rows = self.bridge(root, files.transfer_ready(root, final))
            holder.persist_original_terminal(request, clock)
            changes = store._connection.total_changes
            state['on_terminal'] = lambda: (_ for _ in ()).throw(sqlite3.OperationalError('query failed'))
            with self.assertRaises(sqlite3.OperationalError): holder.observe_original_terminal(request, clock)
            self.assertEqual(store._connection.total_changes, changes)
            state['on_terminal'] = lambda: None
            key = store.namespaced_key(rows[2]['table'], rows[2]['key'])
            store.compare_exchange(key, 1, b'foreign-terminal')
            with self.assertRaises(LocalCoreError) as error: holder.observe_original_terminal(request, clock)
            self.assertEqual(error.exception.code, -41)
            with self.assertRaises(LocalStorageError): holder.persist_original_terminal(request, clock)
            self.assertEqual(sum(name == 'produce_sdk_terminal_storage' for name, _ in calls), 2)
            self.assertTrue(holder.close())

    def test_precommit_revocation_rolls_back_but_keeps_registered_original_output(self):
        files = file_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            holder, store, core, request, first, clock, state, calls, rows = self.bridge(root, files.transfer_ready(root, final))
            def revoke():
                if len(calls) == 2: state['terminal_status'] = -35
            state['on_terminal'] = revoke
            with self.assertRaises(LocalCoreError) as error: holder.persist_original_terminal(request, clock)
            self.assertEqual(error.exception.code, -35)
            self.assertIsNone(store.read(store.namespaced_key(rows[0]['table'], rows[0]['key'])))
            self.assertEqual(store.read(store.namespaced_key(rows[2]['table'], rows[2]['key'])), StoredBytes(0, b'opaque-streaming'))
            self.assertIs(core._loans[first.ticket], first)
            child = holder._payload_outputs[request.ticket]
            self.assertIs(core._loans[child.ticket], child)
            with self.assertRaises(LocalStorageError): holder.persist_original_terminal(request, clock)
            self.assertTrue(holder.close())
