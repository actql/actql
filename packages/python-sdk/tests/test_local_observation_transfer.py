"""Actual SQLite and original input/workspace facade; Core decisions are mocked."""
import copy
import json
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_observation_transfer import OriginalObservationTransfer
from actql_sdk._local_storage import LocalByteStore
import test_local_commit_store_caller as original_fixture
import test_local_reader_facts as facts_fixture


class ObservationTransferTests(unittest.TestCase):
    index = b'{"e\xcc\x81/~\xf0\x9f\x98\x80":null,"n":9007199254740993}\r\n'
    request = b'{"text":"e\xcc\x81\\r\\n","absent":{},"null":null}\n'
    attempt = b'{"attempt":"original-older","time":"2026-09-17T00:00:00Z"}\r'
    reference = b'sha256:' + b'e' * 64

    def bridge(self, *, source=1024, packet=2048):
        core, parent, publisher, projection, calls, state, _, _, _ = original_fixture.OriginalCommitStoreCallerTests.bridge(self)
        core._retired = False
        state.update(workspace=0, reserve_input=0, fill=0, seal=0, prepare=0,
                     borrow=False, cleanup_input=True, cleanup_workspace=True, trap=None,
                     require_json_seal=False, bounded_fill=False)
        original_call = core._call
        handles, packets = {}, []
        def call(family, name, *args):
            if family in ('workspace', 'publication') or (family == 'buffer' and name != 'byte'):
                calls.append((family, name, args))
                if name == 'reserve':
                    ticket = args[0]
                    if state['trap'] == family:
                        core._closing = True
                        raise OSError('Original reservation outcome unknown')
                    refusal = state['workspace' if family == 'workspace' else 'reserve_input']
                    if refusal:
                        return refusal
                    handle = 1000 + ticket
                    handles[handle] = ticket
                    return handle
                if name in ('fill', 'seal'):
                    if name == 'fill' and state['bounded_fill'] and args[2] > 16384:
                        return -6
                    if name == 'seal' and state['require_json_seal']:
                        try:
                            json.loads(core._inputs[handles[args[0]]].payload)
                        except (ValueError, UnicodeError):
                            return -8
                    return state[name]
                if name in ('prepare_lookup', 'prepare_observation'):
                    self.assertEqual((args[0], args[2], args[3]), (23, 17, 31))
                    packets.append(core._inputs[handles[args[1]]].payload)
                    state['borrow'] = True
                    return state['prepare']
                if name == 'close':
                    if family == 'buffer' and state['borrow']:
                        return -9
                    if core._cleanup(handles[args[0]]) != 0:
                        return -9
                    del handles[args[0]]
                    return 0
                self.fail(f'Unexpected physical transfer operation: {family}/{name}')
            return original_call(family, name, *args)
        core._call = call
        transfer = OriginalObservationTransfer(
            projection, publisher, max_source_bytes=source, max_packet_bytes=packet,
            cleanup=lambda: state['cleanup_input'], stopped=lambda _: not state['borrow'],
            workspace_cleanup=lambda: state['cleanup_workspace'], workspace_stopped=lambda: True)
        return core, parent, publisher, transfer, calls, state, packets

    def test_raw_cid_reference_is_retained_without_json_admission_before_closed_packet(self):
        core, _, _, transfer, calls, state, packets = self.bridge()
        state['require_json_seal'] = True
        transfer.reserve()
        reference = transfer.retain_source(self.reference)
        index = transfer.retain_source(self.index)
        self.assertFalse(any(name == 'seal' for _, name, _ in calls))
        self.assertIs(core._loans[reference.ticket], reference)
        transfer.transfer_lookup_inputs(reference, index)
        self.assertEqual(json.loads(packets[0]), {
            'identity': self.reference.decode(), 'index': self.index.decode()})
        self.assertEqual(sum(name == 'seal' for _, name, _ in calls), 1)
        state['borrow'] = False
        self.assertTrue(transfer.close())

    def test_original_rows_and_envelope_use_in_order_bounded_fill_chunks(self):
        core, _, _, transfer, calls, state, packets = self.bridge(source=40000, packet=50000)
        state['bounded_fill'] = state['require_json_seal'] = True
        raw = b'{"text":"' + b'x' * 17000 + b'"}'
        transfer.reserve()
        reference = transfer.retain_source(self.reference)
        index = transfer.retain_source(raw)
        transfer.transfer_lookup_inputs(reference, index)
        self.assertEqual(json.loads(packets[0])['index'].encode(), raw)
        fills = [args for _, name, args in calls if name == 'fill']
        for value in (reference, index, transfer.pending_input):
            chunks = [(start, count) for handle, start, count in fills if handle == value.handle]
            offset = 0
            for start, count in chunks:
                self.assertEqual(start, offset)
                self.assertLessEqual(count, 16384)
                offset += count
            self.assertEqual(offset, value.length)
        state['borrow'] = False
        self.assertTrue(transfer.close())

    def test_original_unicode_crlf_null_and_large_number_bytes_roundtrip_without_identity_parse(self):
        core, parent, publisher, transfer, calls, state, packets = self.bridge()
        transfer.reserve()
        workspace = transfer.pending_workspace
        transfer.transfer_lookup(self.reference, self.index)
        self.assertEqual(json.loads(packets[0]), {'identity': self.reference.decode(), 'index': self.index.decode()})
        self.assertIn(b'e\xcc\x81/~\xf0\x9f\x98\x80', packets[0])
        self.assertIn(b'9007199254740993', packets[0])
        self.assertIn(b'\\u000d\\u000a', packets[0])
        self.assertIs(core._loans[workspace.ticket], workspace)
        self.assertEqual(calls[0], ('workspace', 'reserve', (8, 9216)))
        self.assertEqual([name for _, name, _ in calls], ['reserve', 'reserve', 'fill', 'seal', 'prepare_lookup'])
        self.assertIs(core._loans[7], parent)
        self.assertIs(core._loans[6], publisher)
        self.assertFalse(transfer.close())
        self.assertIs(transfer.pending_workspace, workspace)
        state['borrow'] = False
        self.assertTrue(transfer.close())
        self.assertIsNone(transfer.pending_input)
        self.assertIsNone(transfer.pending_workspace)
        before = len(calls)
        self.assertTrue(transfer.close())
        self.assertEqual(len(calls), before)

    def test_same_sqlite_snapshot_after_lost_ack_forwards_actual_old_attempt_and_original_bytes(self):
        core, parent, _, transfer, calls, state, packets = self.bridge()
        with TemporaryDirectory() as directory, LocalByteStore(
                Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=256, max_payload_bytes=1024) as store:
            originals = facts_fixture.ReaderFactsTests().original(store)
            for key, raw in (('stored-request', self.request), ('stored-attempt', self.attempt), ('stored-index', self.index)):
                store.compare_exchange(key, None, raw)
            # The write is physically committed; its response was lost. Inspection
            # must not rewrite those rows or substitute a new attempt/index.
            with self.assertRaises(OSError):
                raise OSError('Original ACK lost after COMMIT')
            transfer.reserve()
            rows, sql = [], []
            store._connection.set_trace_callback(sql.append)
            def inspect(read):
                for key in ('stored-request', 'stored-attempt', 'stored-index'):
                    read(key, lambda row: rows.append(transfer.retain_source(row.payload)))
                transfer.transfer_stored_inputs(*rows)
                rows.clear()
            store.inspect_publication_projected_attached(inspect, originals, current=lambda: None)
            self.assertEqual(json.loads(packets[0]), {'kind': 'stored', 'request': self.request.decode(),
                                                    'attempt': self.attempt.decode(), 'index': self.index.decode()})
            self.assertEqual(sql.count('BEGIN'), 1)
            self.assertEqual(sql.count('ROLLBACK'), 1)
            self.assertFalse(any(q.startswith(('COMMIT', 'INSERT', 'UPDATE', 'DELETE')) for q in sql))
            self.assertFalse(any(name in ('finish_commit', 'finish_observation', 'advance_observation') for _, name, _ in calls))
            self.assertIs(core._loans[7], parent)
            state['borrow'] = False
            self.assertTrue(transfer.close())

    def test_confirmed_not_found_and_query_failure_have_different_closed_packets_no_ack(self):
        for query_failure, expected in ((False, b'{"kind":"not_found"}'), (True, b'{"kind":"query_failed"}')):
            with self.subTest(query_failure=query_failure):
                _, _, _, transfer, calls, state, packets = self.bridge()
                transfer.reserve()
                if query_failure:
                    transfer.transfer_query_failure()
                else:
                    transfer.transfer_not_found()
                self.assertEqual(packets, [expected])
                self.assertEqual(calls[-1][1], 'prepare_observation')
                self.assertFalse(any(name in ('finish_commit', 'finish_observation') for _, name, _ in calls))
                state['borrow'] = False
                self.assertTrue(transfer.close())

    def test_bounds_escaping_and_source_type_refuse_before_input_reservation(self):
        for raw, source, packet in ((b'x' * 9, 8, 512), (b'\x00' * 10, 256, 64),
                                    (bytearray(b'original'), 256, 512)):
            with self.subTest(raw=raw):
                core, parent, _, transfer, calls, _, _ = self.bridge(source=source, packet=packet)
                transfer.reserve()
                workspace = transfer.pending_workspace
                with self.assertRaises(ValueError):
                    transfer.transfer_lookup(b'id', raw)
                self.assertEqual([name for _, name, _ in calls], ['reserve'])
                self.assertIs(transfer.pending_workspace, workspace)
                self.assertIsNone(transfer.pending_input)
                self.assertIs(core._loans[7], parent)
                self.assertTrue(transfer.close())
        _, _, _, transfer, _, state, packets = self.bridge()
        transfer.reserve()
        raw = bytes(range(32)) + b'"\\/end'
        transfer.transfer_stored(raw, b'null', b'{}')
        self.assertEqual(json.loads(packets[0])['request'].encode(), raw)
        state['borrow'] = False
        self.assertTrue(transfer.close())

    def test_original_workspace_is_required_before_transfer_and_refusal_allocates_no_input(self):
        _, _, _, transfer, calls, state, _ = self.bridge()
        with self.assertRaises(RuntimeError):
            transfer.transfer_query_failure()
        self.assertEqual(calls, [])
        state['workspace'] = -4
        with self.assertRaises(LocalCoreError):
            transfer.reserve()
        self.assertIsNone(transfer.pending_input)
        self.assertIsNone(transfer.pending_workspace)
        self.assertEqual(len(calls), 1)
        self.assertTrue(transfer.close())

    def test_parse_scope_publisher_and_transfer_failure_keep_exact_loans_no_replacement(self):
        for step, code in (('prepare', -32), ('prepare', -35), ('prepare', -36), ('fill', -4), ('seal', -33)):
            with self.subTest(step=step, code=code):
                core, parent, _, transfer, calls, state, _ = self.bridge()
                transfer.reserve()
                workspace = transfer.pending_workspace
                state[step] = code
                with self.assertRaises(LocalCoreError):
                    transfer.transfer_lookup(self.reference, self.index)
                original_input = transfer.pending_input
                self.assertIs(core._loans[original_input.ticket], original_input)
                before = len(calls)
                with self.assertRaises(RuntimeError):
                    transfer.transfer_not_found()
                self.assertEqual(len(calls), before)
                state['borrow'] = False
                state['cleanup_input'] = False
                self.assertFalse(transfer.close())
                self.assertIs(transfer.pending_input, original_input)
                self.assertIs(transfer.pending_workspace, workspace)
                state['cleanup_input'] = True
                state['cleanup_workspace'] = False
                self.assertFalse(transfer.close())
                self.assertIsNone(transfer.pending_input)
                self.assertIs(transfer.pending_workspace, workspace)
                state['cleanup_workspace'] = True
                self.assertTrue(transfer.close())
                self.assertIs(core._loans[7], parent)

    def test_reserve_traps_retain_uncertain_original_ticket_until_actual_pool_retirement(self):
        for family in ('workspace', 'buffer'):
            with self.subTest(family=family):
                core, parent, _, transfer, calls, state, _ = self.bridge()
                if family == 'buffer':
                    transfer.reserve()
                state['trap'] = family
                with self.assertRaises(OSError):
                    transfer.reserve() if family == 'workspace' else transfer.transfer_query_failure()
                ticket = transfer.uncertain_acquisition_ticket
                self.assertIsNotNone(ticket)
                self.assertIn(ticket, core._inputs)
                self.assertFalse(transfer.close())
                self.assertIs(core._loans[7], parent)
                # A callback alone cannot prove that Core retired its pool.
                self.assertEqual(core._cleanup(ticket), 0)
                self.assertFalse(transfer.close())
                core._retired = True
                if transfer.pending_workspace:
                    core._inputs.pop(transfer.pending_workspace.ticket)
                self.assertTrue(transfer.close())

    def test_nominal_copies_configuration_and_publisher_are_rejected_before_io(self):
        core, parent, publisher, transfer, calls, _, _ = self.bridge()
        copied = copy.copy(transfer)
        for action in (copied.reserve, copied.close, copied.transfer_query_failure):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(calls, [])
        with self.assertRaises(ValueError):
            OriginalObservationTransfer(transfer._projection, copy.copy(publisher),
                                        max_source_bytes=64, max_packet_bytes=64, cleanup=lambda: True,
                                        stopped=lambda _: True, workspace_cleanup=lambda: True,
                                        workspace_stopped=lambda: True)
        transfer._projection._publication = copy.copy(parent)
        with self.assertRaises(ValueError):
            transfer.reserve()
        self.assertEqual(calls, [])

    def test_cleanup_during_transfer_cannot_return_live_workspace_or_original_input(self):
        _, _, _, transfer, calls, state, _ = self.bridge()
        transfer.reserve()
        original = transfer._packet
        def reentrant(fields):
            with self.assertRaises(RuntimeError):
                transfer.close()
            return original(fields)
        transfer._packet = reentrant
        transfer.transfer_query_failure()
        state['borrow'] = False
        self.assertTrue(transfer.close())
        self.assertFalse(any(name in ('retire_lookup', 'retire_observation', 'close_pool', 'cancel') for _, name, _ in calls))


if __name__ == '__main__':
    unittest.main()
