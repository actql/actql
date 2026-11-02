"""Actual File-backed stream with scalar Core/sink/terminal doubles; public0."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileRoot, LocalFileError
from actql_sdk._local_saved_read import OriginalSavedResultRead
from actql_sdk._local_sdk_payload_reader import OriginalSDKPayloadReader
from actql_sdk._local_sdk_response import OriginalLocalSDKResponseStream
from actql_sdk._local_storage import LocalStorageCommitUnknown
import test_local_reader_facts as files_fixture
import test_local_sdk_payload_reader as payload_fixture


class LocalSDKResponseTests(unittest.IsolatedAsyncioTestCase):
    def bridge(self, root, final):
        helper = payload_fixture.SDKPayloadReaderTests()
        helper.addCleanup = self.addCleanup
        holder, store, core, request, first, fact, initial_clock, state, calls = helper.bridge(root, final)
        reader = OriginalSDKPayloadReader(holder, request, initial_clock, fact)
        host = SimpleNamespace(_core=core, _inputs=[initial_clock], _response_streams=set(), _nominal=lambda: None, _active=lambda: None)
        def clock():
            tick = core.reserve_input(b'{"observed_at":"2026-10-13T00:00:06.000Z"}',
                cleanup=lambda: True, stopped=lambda _: True)
            host._inputs.append(tick)
            core.fill_input(tick, 0, tick.length)
            core.seal_input(tick)
            return tick
        host._original_sdk_delivery_clock = clock
        stream = OriginalLocalSDKResponseStream(host, reader)
        return stream, host, reader, holder, store, core, request, first, state, calls

    async def test_bytes_acceptance_precedes_terminal_and_eof_follows_saved_observation(self):
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            stream, host, reader, holder, _, _, request, _, _, calls = self.bridge(root, final)
            terminal = []
            def saved(original, clock):
                self.assertIs(original, request)
                self.assertIsNone(reader._output)
                self.assertIsNone(reader._input)
                self.assertTrue(reader._reader.eof)
                terminal.append(clock)
            with patch.object(holder, 'persist_original_terminal', side_effect=saved):
                chunks = [chunk async for chunk in stream]
            # Empty progress polls carry no bytes. Their position is not a
            # delivery acknowledgement; the exact payload and final marker are.
            self.assertEqual(chunks.count(b''), 2)
            self.assertEqual([chunk for chunk in chunks if chunk], [b'{"n":1}\n', b'\x1e'])
            self.assertEqual(len(terminal), 1)
            # Confirmation was handled by the underlying scalar fixture; EOF
            # is qualified only by the explicit saved-observation test double.
            self.assertIsNone(reader._output)
            await stream.aclose()
            self.assertNotIn(stream, host._response_streams)
            self.assertTrue(holder.close())

    async def test_commit_unknown_has_no_marker_and_no_automatic_retry(self):
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            stream, host, _, holder, store, _, _, _, _, _ = self.bridge(root, final)
            chunks = []
            with patch.object(holder, 'persist_original_terminal', side_effect=LocalStorageCommitUnknown(store)) as commit:
                with self.assertRaises(LocalStorageCommitUnknown):
                    async for chunk in stream: chunks.append(chunk)
                self.assertEqual(commit.call_count, 1)
                self.assertNotIn(b'\x1e', chunks)
                with self.assertRaises(RuntimeError): stream.__aiter__()
                await stream.aclose()
                self.assertEqual(commit.call_count, 1)
            self.assertNotIn(stream, host._response_streams)
            self.assertTrue(holder.close())

    async def test_interrupted_yield_does_not_confirm_or_commit_and_close_retries_original(self):
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            stream, host, reader, holder, _, core, _, first, state, _ = self.bridge(root, final)
            iterator = stream.__aiter__()
            with patch.object(holder, 'confirm_original_chunk', side_effect=AssertionError('No sink acceptance')) as confirm, patch.object(holder, 'persist_original_terminal', side_effect=AssertionError('No terminal write')) as commit:
                self.assertEqual(await iterator.__anext__(), b'')
                child = reader._output
                state['cleanup'] = False
                with self.assertRaises(RuntimeError): await stream.aclose()
                self.assertIs(core._loans[child.ticket], child)
                self.assertIs(core._loans[first.ticket], first)
                self.assertIn(stream, host._response_streams)
                state['cleanup'] = True
                await stream.aclose()
                await stream.aclose()
                self.assertEqual(confirm.call_count, 0)
                self.assertEqual(commit.call_count, 0)
            self.assertTrue(holder.close())
            with self.assertRaises(ValueError): copy.copy(stream).__aiter__()


    async def test_saved_response_close_releases_same_area_before_next_saved_read(self):
        # Actual directory custody and stream/payload close; scalar Core ports
        # isolate this lifetime edge, not a complete installed Saved admission.
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final), TemporaryDirectory() as directory:
            stream, host, reader, holder, _, _, _, _, _, _ = self.bridge(root, final)
            results = LocalFileRoot(Path(directory), max_files=2, max_chunk_bytes=4)
            area = results.create_area('saved-original-area')
            results.open_area(area)
            identity = results.observe_area(area)
            saved = OriginalSavedResultRead(host)
            saved._area = area
            host._installation = SimpleNamespace(_results=results)
            host._saved_result_reads = [saved]
            try:
                with self.assertRaises(LocalFileError):
                    results.restore_area(area.name, identity)
                # The production saved caller must bind this SAME carrier.
                # No new area, copied holder or cleanup callback is supplied.
                host._response_streams.discard(stream)
                stream = OriginalLocalSDKResponseStream(host, reader, saved_read=saved)
                await stream.aclose()
                self.assertTrue(saved._closed)
                self.assertIsNone(saved._area)
                self.assertNotIn(saved, host._saved_result_reads)
                self.assertNotIn(stream, host._response_streams)
                restored = results.restore_area(area.name, identity)
                self.assertEqual(results.observe_area(restored), identity)
                self.assertTrue(results.close_area(restored))
            finally:
                await stream.aclose()
                self.assertTrue(saved.close())
                self.assertTrue(holder.close())
                self.assertTrue(results.close())

    async def test_pending_saved_area_keeps_same_stream_and_skips_returned_payload_children(self):
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final), TemporaryDirectory() as directory:
            stream, host, reader, holder, _, _, _, _, _, _ = self.bridge(root, final)
            results = LocalFileRoot(Path(directory), max_files=2, max_chunk_bytes=4)
            area = results.create_area('pending-saved-area')
            results.open_area(area)
            identity = results.observe_area(area)
            saved = OriginalSavedResultRead(host)
            saved._area = area
            host._installation = SimpleNamespace(_results=results)
            host._saved_result_reads = [saved]
            host._response_streams.discard(stream)
            stream = OriginalLocalSDKResponseStream(host, reader, saved_read=saved)
            try:
                with patch.object(results, 'close_area', return_value=False) as close_area:
                    with self.assertRaises(RuntimeError):
                        await stream.aclose()
                    close_area.assert_called_once_with(area)
                self.assertTrue(stream._payload_closed)
                self.assertFalse(stream._closed)
                self.assertIs(stream._saved_read, saved)
                self.assertIs(saved._area, area)
                self.assertIn(saved, host._saved_result_reads)
                self.assertIn(stream, host._response_streams)
                with self.assertRaises(LocalFileError):
                    results.restore_area(area.name, identity)
                with patch.object(reader, 'close', side_effect=AssertionError('Returned child must not repeat')):
                    await stream.aclose()
                    await stream.aclose()
                self.assertTrue(saved._closed)
                self.assertNotIn(saved, host._saved_result_reads)
                self.assertNotIn(stream, host._response_streams)
            finally:
                await stream.aclose()
                self.assertTrue(saved.close())
                self.assertTrue(holder.close())
                self.assertTrue(results.close())

    async def test_saved_response_refuses_copied_foreign_or_unregistered_parent_before_retention(self):
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            stream, host, reader, holder, _, _, _, _, _, _ = self.bridge(root, final)
            saved = OriginalSavedResultRead(host)
            foreign = OriginalSavedResultRead(SimpleNamespace(_core=host._core))
            host._saved_result_reads = [saved, foreign]
            before = set(host._response_streams)
            for candidate in (copy.copy(saved), foreign, OriginalSavedResultRead(host)):
                with self.assertRaises(ValueError):
                    OriginalLocalSDKResponseStream(host, reader, saved_read=candidate)
                self.assertEqual(host._response_streams, before)
                self.assertFalse(reader._closed)
            await stream.aclose()
            self.assertTrue(holder.close())
