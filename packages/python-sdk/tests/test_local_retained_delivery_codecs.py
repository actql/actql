"""Same-Store retained-first codec plumbing; scalar Core, actual Wasm absent."""
import copy
import unittest

from actql_sdk._local_core import LocalCoreError, _PUBLICATION_COMMIT_EXPORT_SIGNATURES
import test_local_sdk_delivery_storage as storage_fixture
import test_local_sdk_read_original as core_fixture
import test_local_reader_facts as file_fixture


class RetainedDeliveryCodecPortTests(unittest.TestCase):
    def test_exact_original_loans_and_closed_status_before_any_payload_io(self):
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['prepare_sdk_payload_codecs'],
                         ('i64 i32 i32 i32', 'i32'))
        core, clock, first, calls, status = core_fixture.SDKReadOriginalTests.bridge(self)
        for candidate, tick, current in ((copy.copy(first), clock, 23),
                                         (first, copy.copy(clock), 23), (first, clock, True)):
            with self.assertRaises(ValueError):
                core.prepare_publication_sdk_payload_codecs(candidate, tick, current)
        self.assertEqual(calls, [])
        core.prepare_publication_sdk_payload_codecs(first, clock, 23)
        self.assertEqual(calls, [('publication_commit_export', 'prepare_sdk_payload_codecs', (19, 17, 23))])
        for code in (-35, -42, -41, -32, -4, -9, -33, 1):
            status[0] = code
            with self.assertRaises(LocalCoreError) as issue:
                core.prepare_publication_sdk_payload_codecs(first, clock, 23)
            self.assertEqual(issue.exception.code, code)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[clock.ticket], clock)
        status[0] = False
        with self.assertRaisesRegex(RuntimeError, 'codec status'):
            core.prepare_publication_sdk_payload_codecs(first, clock, 23)


class RetainedDeliveryCodecStoreTests(unittest.TestCase):
    def bridge(self, root, reader):
        fixture = storage_fixture.SDKDeliveryStorageTests()
        fixture.addCleanup = self.addCleanup
        holder, store, core, observation, request, _, state, _, rows = fixture.bridge(root, reader)
        holder.persist(request, 37)
        first = holder.original_first_output(request)
        clock = core.reserve_input(b'{"observed_at":"2026-10-13T00:00:05.000Z"}',
                                  cleanup=lambda: True, stopped=lambda _: True)
        previous = core._call
        calls = []
        state['codec_status'] = 0
        state['on_codec'] = lambda: None
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'prepare_sdk_payload_codecs':
                self.assertEqual(args, (first.handle, clock.handle, 31))
                binding = observation._binding
                frame = core._journal_callbacks(binding._current.ticket).reader
                self.assertIs(frame.owner, store)
                retained = []
                frame.read(rows[3]['table'], rows[3]['key'], retained.append)
                self.assertEqual(retained[0][1].payload, rows[3]['body'].encode())
                self.assertIs(core._loans[first.ticket], first)
                self.assertIs(core._loans[clock.ticket], clock)
                calls.append(args)
                state['on_codec']()
                return state['codec_status']
            return previous(family, name, *args)
        core._call = call
        return holder, store, core, observation, request, first, clock, calls, state

    def test_actual_same_store_read_frame_preserves_first_without_writes_or_new_attempt(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, _, request, first, clock, calls, _ = self.bridge(root, helper.transfer_ready(root, final))
            before = store._connection.total_changes
            holder.prepare_original_codecs(request, clock)
            self.assertEqual(len(calls), 1)
            self.assertEqual(store._connection.total_changes, before)
            self.assertFalse(store._connection.in_transaction)
            self.assertIs(holder.original_first_output(request), first)
            self.assertTrue(core.close_input(clock))
            self.assertTrue(holder.close_original_first(request))
            self.assertTrue(holder.close())

    def test_current_denial_and_close_reentry_keep_same_loans_without_success_or_retry(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            holder, store, core, _, request, first, clock, calls, state = self.bridge(root, helper.transfer_ready(root, final))
            before = store._connection.total_changes
            state['codec_status'] = -35
            with self.assertRaises(LocalCoreError) as issue:
                holder.prepare_original_codecs(request, clock)
            self.assertEqual(issue.exception.code, -35)
            self.assertIs(holder.original_first_output(request), first)
            state['codec_status'] = 0
            def close_reentry():
                self.assertFalse(holder.close())
            state['on_codec'] = close_reentry
            with self.assertRaisesRegex(RuntimeError, 'storage is closing'):
                holder.prepare_original_codecs(request, clock)
            self.assertEqual(len(calls), 2)
            self.assertEqual(store._connection.total_changes, before)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[clock.ticket], clock)
            self.assertTrue(core.close_input(clock))
            self.assertTrue(holder.close())
