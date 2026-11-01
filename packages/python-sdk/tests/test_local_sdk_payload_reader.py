"""Actual bounded FD/SQLite transport; scalar Core, no real codec or SDK sink."""
import copy
import os
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_sdk_payload_reader import (
    OriginalSDKPayloadReader, SDKPayloadReaderCleanupPending,
)
import test_local_sdk_payload_store as store_fixture
import test_local_reader_facts as file_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKPayloadReaderTests(unittest.TestCase):
    def bridge(self, root, final):
        files = file_fixture.ReaderFactsTests()
        helper = store_fixture.SDKPayloadStorePortTests()
        helper.addCleanup = self.addCleanup
        holder, store, core, request, first, _, clock, _, state = helper.bridge(
            root, files.transfer_ready(root, final))
        fact = holder._observation._facts[0]
        previous = core._call
        outputs, calls = {}, []
        confirmations = {}
        confirmed_total = [0]
        expected_payloads = (b'', b'{"n":1}\n', b'')
        state['binding_status'] = 0
        def call(family, name, *args):
            if name == 'bind_sdk_payload_record':
                self.assertEqual(args, (first.handle, fact._record.handle, 31, 0, 0))
                calls.append((name, args))
                return state['binding_status']
            if name == 'produce_sdk_payload_chunk':
                frame = core._journal_callbacks(holder._observation._binding._current.ticket).reader
                self.assertIs(frame.owner, store)
                self.assertTrue(store._connection.in_transaction)
                calls.append((name, args))
                if state['payload_status']:
                    return state['payload_status']
                # Independent responses for original 4/4/1 input slices. This
                # transport double does not execute or duplicate the codec.
                if args[0] not in outputs:
                    outputs[args[0]] = expected_payloads[len(outputs)]
                return 0
            if name == 'confirm_sdk_payload_chunk':
                calls.append((name, args))
                if args[0] not in confirmations:
                    confirmed_total[0] += len(outputs[args[0]])
                    confirmations[args[0]] = confirmed_total[0]
                return confirmations[args[0]]
            if name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return holder, store, core, request, first, fact, clock, state, calls

    def test_exact_descriptor_advances_only_after_sink_and_core_loans_return(self):
        files = file_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            holder, store, core, request, first, fact, clock, _, calls = self.bridge(root, final)
            changes = store._connection.total_changes
            stream = OriginalSDKPayloadReader(holder, request, clock, fact)
            original_reader = fact._reader
            self.assertIsNot(stream._reader, original_reader)
            self.assertEqual(root._used_slots(), 3)
            self.assertFalse(holder.close_original_first(request))
            raw_reads = []
            pread = os.pread
            def observed(fd, size, offset):
                raw_reads.append((size, offset))
                return pread(fd, size, offset)
            with patch('actql_sdk._local_files.os.pread', side_effect=observed):
                for expected_offset in (0, 4, 8):
                    output, payload = stream.offer(clock)
                    self.assertEqual(stream._reader.offset, expected_offset)
                    with self.assertRaises(RuntimeError):
                        stream.offer(clock)
                    self.assertEqual(payload, b'{"n":1}\n' if expected_offset == 4 else b'')
                    self.assertEqual(stream.accept(output), 0 if expected_offset == 0 else 8)
            self.assertEqual(raw_reads, [(4, 0), (4, 4), (1, 8)])
            self.assertTrue(stream._reader.eof)
            self.assertEqual('sha256:' + stream._reader.hash.hexdigest(),
                             'sha256:8cd664de3db2ebc3a68f6507c3d786addcdaffc9393fea9ce94364129ba27a98')
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(root._readers[id(original_reader)], original_reader)
            self.assertEqual(store._connection.total_changes, changes)
            self.assertTrue(stream.close())
            self.assertTrue(stream.close())
            self.assertEqual(root._used_slots(), 2)
            self.assertTrue(holder.close_original_first(request))
            self.assertTrue(holder.close())
            self.assertFalse(any(name in ('produce_sdk_payload_receipt', 'finish_commit')
                                 for name, _ in calls))

    def test_denial_precedes_fd_read_and_cleanup_keeps_original_descriptor_and_workspace(self):
        files = file_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            holder, _, core, request, first, fact, clock, state, _ = self.bridge(root, final)
            stream = OriginalSDKPayloadReader(holder, request, clock, fact)
            state['payload_status'] = -35
            with patch('actql_sdk._local_files.os.pread', side_effect=AssertionError('Unauthorized physical read')):
                with self.assertRaises(LocalCoreError):
                    stream.offer(clock)
            self.assertIsNone(stream._reader.chunk)
            state['payload_status'] = 0
            output, _ = stream.offer(clock)
            chunk = stream._chunk
            raw = stream._input
            state['cleanup'] = False
            with self.assertRaises(SDKPayloadReaderCleanupPending):
                stream.accept(output)
            self.assertIs(stream._chunk, chunk)
            self.assertIs(stream._input, raw)
            self.assertEqual(stream._reader.offset, 0)
            self.assertFalse(holder.close_original_first(request))
            self.assertIs(core._loans[first.ticket], first)
            state['cleanup'] = True
            self.assertEqual(stream.accept(output), 0)
            self.assertEqual(stream._reader.offset, 4)
            output, _ = stream.offer(clock)
            raw = stream._input
            close_input = core.close_input
            attempts = []
            def cleanup_once(value):
                if value is raw and not attempts:
                    attempts.append(value)
                    return False
                return close_input(value)
            with patch.object(core, 'close_input', side_effect=cleanup_once):
                with self.assertRaises(SDKPayloadReaderCleanupPending):
                    stream.accept(output)
                self.assertNotIn(output.ticket, core._loans)
                self.assertIs(core._loans[raw.ticket], raw)
                self.assertEqual(stream._reader.offset, 4)
                self.assertEqual(stream.accept(output), 8)
            self.assertEqual(attempts, [raw])
            self.assertEqual(stream._reader.offset, 8)
            self.assertTrue(stream.close())
            self.assertTrue(holder.close())

    def test_copies_and_constructor_source_denial_cannot_get_descriptor_or_drop_borrow(self):
        files = file_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            holder, _, core, request, first, fact, clock, state, _ = self.bridge(root, final)
            state['binding_status'] = -32
            with patch('actql_sdk._local_files.os.open', side_effect=AssertionError('Unselected descriptor')):
                with self.assertRaises(SDKPayloadReaderCleanupPending) as error:
                    OriginalSDKPayloadReader(holder, request, clock, fact)
            stream = error.exception.cleanup_reader
            self.assertIs(holder._payload_reader_borrows[request.ticket], stream)
            self.assertIsNone(stream._reader)
            self.assertFalse(holder.close_original_first(request))
            with self.assertRaises(ValueError):
                copy.copy(stream).close()
            self.assertIs(core._loans[first.ticket], first)
            self.assertTrue(stream.close())
            self.assertTrue(holder.close())

    def test_empty_output_refusal_cannot_be_inferred_as_ack_or_advance_the_descriptor(self):
        files = file_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            holder, _, core, request, first, fact, clock, _, _ = self.bridge(root, final)
            stream = OriginalSDKPayloadReader(holder, request, clock, fact)
            output, payload = stream.offer(clock)
            self.assertEqual(payload, b'')
            chunk, raw = stream._chunk, stream._input
            previous = core._call
            def refuse(family, name, *args):
                if name == 'confirm_sdk_payload_chunk':
                    return -32
                return previous(family, name, *args)
            core._call = original_byte_fixture_port(refuse)
            with self.assertRaises(LocalCoreError) as error:
                stream.accept(output)
            self.assertEqual(error.exception.code, -32)
            self.assertEqual(stream._reader.offset, 0)
            self.assertIs(stream._chunk, chunk)
            self.assertIs(stream._input, raw)
            self.assertIs(stream._output, output)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[raw.ticket], raw)
            self.assertTrue(stream.close())
            self.assertTrue(holder.close())
