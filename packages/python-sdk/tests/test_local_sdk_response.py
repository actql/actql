"""Actual File-backed stream with scalar Core/sink/terminal doubles; public0."""
import copy
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from actql_sdk._local_sdk_payload_reader import OriginalSDKPayloadReader
from actql_sdk._local_sdk_response import OriginalLocalSDKResponseStream
from actql_sdk._local_storage import LocalStorageCommitUnknown
import test_local_reader_facts as files_fixture
import test_local_sdk_payload_reader as payload_fixture


class LocalSDKResponseTests(unittest.IsolatedAsyncioTestCase):
    def bridge(self, root, final, *, close_parent=None):
        helper = payload_fixture.SDKPayloadReaderTests()
        helper.addCleanup = self.addCleanup
        holder, store, core, request, first, fact, initial_clock, state, calls = helper.bridge(root, final)
        reader = OriginalSDKPayloadReader(holder, request, initial_clock, fact)
        host = SimpleNamespace(_core=core, _inputs=[initial_clock], _response_streams=set(), _nominal=lambda: None)
        def clock():
            tick = core.reserve_input(b'{"observed_at":"2026-10-13T00:00:06.000Z"}',
                cleanup=lambda: True, stopped=lambda _: True)
            host._inputs.append(tick)
            core.fill_input(tick, 0, tick.length)
            core.seal_input(tick)
            return tick
        host._original_sdk_delivery_clock = clock
        stream = OriginalLocalSDKResponseStream(host, reader, close_parent=close_parent)
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

    async def test_saved_parent_retires_after_reader_ack_and_allows_sequential_area_restore(self):
        from actql_sdk._local_files import LocalFileError
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]', slots=4) as (_, root, _, final):
            created = root.create_area('saved-area')
            identity = created.identity
            self.assertTrue(root.close_area(created))
            area = root.restore_area('saved-area', identity)
            closed = []
            def close_parent():
                self.assertTrue(reader._closed)
                self.assertNotIn(request.ticket, holder._payload_reader_borrows)
                closed.append(area)
                return root.close_area(area)
            stream, host, reader, holder, _, _, request, _, state, _ = self.bridge(
                root, final, close_parent=close_parent)
            iterator = stream.__aiter__()
            self.assertEqual(await anext(iterator), b'')
            # Overlap retains the same exclusive area, not a duplicate Owner.
            with self.assertRaises(LocalFileError):
                root.restore_area('saved-area', identity)
            state['cleanup'] = False
            with self.assertRaises(RuntimeError):
                await stream.aclose()
            self.assertEqual(closed, [])
            self.assertIn(stream, host._response_streams)
            self.assertIs(root._areas[id(area)], area)
            state['cleanup'] = True
            await stream.aclose()
            await stream.aclose()
            self.assertEqual(closed, [area])
            self.assertNotIn(stream, host._response_streams)
            restored = root.restore_area('saved-area', identity)
            self.assertIsNot(restored, area)
            self.assertEqual(restored.identity, identity)
            self.assertTrue(root.close_area(restored))
            self.assertTrue(holder.close())

    async def test_partial_parent_close_does_not_reuse_retired_transport_inputs(self):
        files = files_fixture.ReaderFactsTests()
        with files.file(b'[{"n":1}]') as (_, root, _, final):
            acknowledgements = iter((False, True))
            calls = []
            def close_parent():
                self.assertTrue(reader._closed)
                calls.append(reader)
                return next(acknowledgements)
            stream, host, reader, holder, _, _, _, _, _, _ = self.bridge(root, final, close_parent=close_parent)
            with patch.object(holder, 'close_original_first', wraps=holder.close_original_first) as close_first:
                with self.assertRaises(RuntimeError):
                    await stream.aclose()
                self.assertIn(stream, host._response_streams)
                self.assertTrue(stream._transport_closed)
                await stream.aclose()
                await stream.aclose()
                close_first.assert_called_once()
            self.assertEqual(calls, [reader, reader])
            self.assertNotIn(stream, host._response_streams)
            self.assertTrue(holder.close())
