"""Actual File/SQLite read frame; scalar Core, no actual sink or Store ACK."""
import unittest

from actql_sdk._local_core import LocalCoreError
import test_local_retained_delivery_codecs as codec_fixture
import test_local_reader_facts as file_fixture


class SDKPayloadStorePortTests(unittest.TestCase):
    def bridge(self, root, reader):
        helper = codec_fixture.RetainedDeliveryCodecStoreTests()
        helper.addCleanup = self.addCleanup
        holder, store, core, observation, request, first, clock, _, state = helper.bridge(root, reader)
        chunk = core.reserve_input(b'[{"n":1}]', cleanup=lambda: True, stopped=lambda _: True)
        previous = core._call
        calls = []
        state['payload_status'] = 0
        state['on_payload'] = lambda: None
        def call(family, name, *args):
            if name in ('prepare_sdk_payload_input', 'produce_sdk_payload_chunk',
                        'produce_sdk_payload_receipt'):
                frame = core._journal_callbacks(observation._binding._current.ticket).reader
                self.assertIs(frame.owner, store)
                self.assertTrue(store._connection.in_transaction)
                self.assertIs(core._loans[first.ticket], first)
                self.assertIs(core._loans[clock.ticket], clock)
                if name != 'prepare_sdk_payload_input':
                    output = holder._payload_outputs[request.ticket]
                    self.assertIs(core._loans[output.ticket], output)
                    self.assertEqual(args[0], output.handle)
                calls.append((name, args))
                state['on_payload']()
                return state['payload_status']
            if name == 'confirm_sdk_payload_chunk':
                calls.append((name, args))
                return 8
            return previous(family, name, *args)
        core._call = call
        return holder, store, core, request, first, chunk, clock, calls, state

    def test_same_store_chunk_confirmation_and_receipt_keep_originals_without_writes(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, request, first, chunk, clock, calls, _ = self.bridge(
                root, helper.transfer_ready(root, final))
            changes = store._connection.total_changes
            holder.prepare_original_input(request, clock)
            output = holder.produce_original_chunk(request, chunk, clock, eof=True)
            self.assertEqual(holder.confirm_original_chunk(request, output), 8)
            with self.assertRaisesRegex(RuntimeError, 'cleanup is pending'):
                holder.produce_original_receipt(request, clock)
            self.assertTrue(holder.close_original_payload_output(request))
            receipt = holder.produce_original_receipt(request, clock)
            self.assertIs(holder._payload_outputs[request.ticket], receipt)
            self.assertIs(holder.original_first_output(request), first)
            self.assertEqual(store._connection.total_changes, changes)
            self.assertFalse(store._connection.in_transaction)
            self.assertEqual([name for name, _ in calls], [
                'prepare_sdk_payload_input', 'produce_sdk_payload_chunk',
                'confirm_sdk_payload_chunk', 'produce_sdk_payload_receipt'])
            self.assertTrue(holder.close_original_payload_output(request))
            self.assertTrue(core.close_input(chunk))
            self.assertTrue(core.close_input(clock))
            self.assertTrue(holder.close_original_first(request))
            self.assertTrue(holder.close())

    def test_postcheck_close_reentry_and_cleanup_failure_keep_exact_child_before_parent(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, request, first, chunk, clock, calls, state = self.bridge(
                root, helper.transfer_ready(root, final))
            changes = store._connection.total_changes
            state['payload_status'] = -35
            with self.assertRaises(LocalCoreError):
                holder.produce_original_chunk(request, chunk, clock, eof=False)
            child = holder._payload_outputs[request.ticket]
            self.assertIs(core._loans[child.ticket], child)
            state['cleanup'] = False
            self.assertFalse(holder.close_original_payload_output(request))
            self.assertIs(holder._payload_outputs[request.ticket], child)
            self.assertIs(core._loans[first.ticket], first)
            state['cleanup'] = True
            self.assertTrue(holder.close_original_payload_output(request))
            state['payload_status'] = 0
            state['on_payload'] = lambda: self.assertFalse(holder.close())
            with self.assertRaisesRegex(RuntimeError, 'storage is closing'):
                holder.produce_original_chunk(request, chunk, clock, eof=False)
            child = holder._payload_outputs[request.ticket]
            self.assertIs(core._loans[child.ticket], child)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[chunk.ticket], chunk)
            self.assertIs(core._loans[clock.ticket], clock)
            self.assertEqual(len(calls), 2)
            self.assertEqual(store._connection.total_changes, changes)
            state['cleanup'] = False
            self.assertFalse(holder.close())
            self.assertIs(core._loans[first.ticket], first)
            state['cleanup'] = True
            self.assertTrue(holder.close())
            self.assertTrue(core.close_input(chunk))
            self.assertTrue(core.close_input(clock))
