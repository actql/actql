"""Original Native/syscall counters, not actual child/VM/funding acceptance."""
import asyncio
import copy
import os
import pickle
import unittest
from unittest.mock import AsyncMock, patch

import actql_sdk._local_worker_control_frames as frames
from actql_sdk._local_native_live_channel import _OriginalLiveChannelError
from test_local_native_live_channel import ChannelFixture


class WorkerControlFrameTests(unittest.TestCase):
    def fixture(self):
        self.f = ChannelFixture(self)
        self.channel = self.f.take()
        self.control = frames._OriginalWorkerControlFrames(self.channel)
        return self.control

    def serve(self, request, *, chunks=None, writes=None):
        self.incoming = bytearray(request)
        self.outgoing = bytearray()
        async def read(maximum):
            if chunks is not None:
                return chunks.pop(0)
            value = bytes(self.incoming[:maximum]); del self.incoming[:maximum]
            return value
        async def write(payload):
            count = len(payload) if writes is None else writes.pop(0)
            if type(count) is int and 0 < count <= len(payload):
                self.outgoing.extend(payload[:count])
            return count
        with patch.object(self.f.pipe, 'read', side_effect=read), patch.object(self.f.pipe, 'write', side_effect=write):
            asyncio.run(self.control.serve_once())
        return frames._RESPONSE.unpack(self.outgoing)

    def request(self, operation, payload=b'', *, serial=None, nonce=7):
        return frames._request(operation, self.control._serial if serial is None else serial, nonce, payload)

    def test_exact_original_channel_is_bound_once_without_pipe_or_native_operation(self):
        self.fixture(); before = list(self.f.events)
        with self.assertRaises(ValueError): frames._OriginalWorkerControlFrames(self.channel)
        with self.assertRaises(ValueError): frames._OriginalWorkerControlFrames(object())
        self.assertIs(self.channel._control_original, self.control)
        self.assertEqual(self.f.events, before)
        self.assertEqual(self.control._serial, 1)

    def test_vm_binding_forwards_exact_material_and_span_to_original_native_owner(self):
        self.fixture(); span = self.f.span()
        reply = self.serve(self.request(frames._BIND, frames._span_payload(span)))
        self.assertEqual(reply, (b'ALC1', frames._BIND, 1, 7, 0))
        self.assertIn(('bind', 7, 4096, 16777216), self.f.events)
        self.assertEqual(self.control._serial, 2)

    def test_foreign_span_is_not_repaired_and_original_binding_cannot_be_reissued(self):
        self.fixture()
        request = self.request(frames._BIND, frames._span_payload(self.f.span(recipe=b'x' * 32)))
        with self.assertRaises(frames._OriginalWorkerControlPending): self.serve(request)
        self.assertTrue(self.channel._bind_attempted)
        self.assertFalse(any(e[0] == 'bind' for e in self.f.events))
        with self.assertRaises(frames._OriginalWorkerControlPending): asyncio.run(self.control.serve_once())

    def test_admit_current_all_limits_and_both_capacities_preserve_native_values(self):
        self.fixture()
        self.assertEqual(self.serve(self.request(frames._ADMIT))[-1], 0)
        self.assertEqual(self.serve(self.request(frames._CURRENT))[-1], 0)
        for ordinal, expected in enumerate(self.f.native_limits):
            self.assertEqual(self.serve(self.request(frames._LIMIT, frames._ORDINAL.pack(ordinal)))[-1], expected)
        for ordinal, expected in enumerate(self.f.native_capacities):
            self.assertEqual(self.serve(self.request(frames._CAPACITY, frames._ORDINAL.pack(ordinal)))[-1], expected)
        self.assertGreater(self.f.native_capacities[1], 2**53)

    def test_report_preserves_original_thirteen_signed_fields_without_python_accounting(self):
        self.fixture(); usage = (2, 1, 1, 2**53 + 1, 0, 0, 0, 0, 0, 16777216, 3, 5, 7)
        self.assertEqual(self.serve(self.request(frames._REPORT, frames._USAGE.pack(*usage)))[-1], 0)
        self.assertIn(('report', usage), self.f.events)
        self.assertFalse(self.channel._stop_attempted)

    def test_closing_and_stop_are_original_facts_without_process_fd_or_domain_retirement(self):
        self.fixture(); self.f.native_state = 1
        self.assertEqual(self.serve(self.request(frames._CURRENT))[-1], 1)
        self.assertEqual(self.serve(self.request(frames._STOP))[-1], 0)
        self.assertTrue(self.channel._stop_acknowledged)
        self.assertFalse(self.channel._closed)
        self.assertFalse(self.f.domain._closed)
        self.assertFalse(self.f.process._parent_closed)
        self.assertFalse(self.f.funding._closed)

    def test_known_refusal_stays_negative_and_does_not_become_admission_or_zero_capacity(self):
        self.fixture(); self.f.issues[3] = 6
        self.assertEqual(self.serve(self.request(frames._ADMIT))[-1], -42)
        self.assertIsNone(self.channel._unknown)
        self.assertEqual(len([e for e in self.f.events if e[:2] == ('operate', 3)]), 1)

    def test_native_unknown_retains_actual_reply_and_forbids_another_exchange(self):
        self.fixture(); self.f.drop_fault = OSError('lost native reply retirement')
        with self.assertRaises(frames._OriginalWorkerControlPending):
            self.serve(self.request(frames._ADMIT))
        self.assertEqual(frames._RESPONSE.unpack(self.control._response_bytes)[-1], -41)
        self.assertIsNotNone(self.channel._unknown)
        before = list(self.f.events)
        with self.assertRaises(frames._OriginalWorkerControlPending): asyncio.run(self.control.serve_once())
        self.assertEqual(self.f.events, before)
        self.assertIs(self.control._channel, self.channel)

    def test_invalid_magic_nonce_or_sequence_refuses_before_native_dispatch(self):
        for key in ('magic', 'nonce', 'serial'):
            with self.subTest(key=key):
                self.fixture(); before = list(self.f.events)
                request = self.request(frames._ADMIT, nonce=8 if key == 'nonce' else 7,
                                       serial=2 if key == 'serial' else 1)
                if key == 'magic': request = b'xxxx' + request[4:]
                with self.assertRaises(frames._OriginalWorkerControlPending): self.serve(request)
                self.assertEqual(self.f.events, before)
                self.assertEqual(self.control._request_bytes, request)

    def test_invalid_ordinal_is_not_projected_to_a_default_or_an_owner_call(self):
        for operation, ordinal in ((frames._LIMIT, -1), (frames._LIMIT, 6), (frames._CAPACITY, 2)):
            with self.subTest(operation=operation, ordinal=ordinal):
                self.fixture(); before = list(self.f.events)
                with self.assertRaises(frames._OriginalWorkerControlPending):
                    self.serve(self.request(operation, frames._ORDINAL.pack(ordinal)))
                self.assertEqual(self.f.events, before)

    def test_partial_input_and_output_use_original_bytes_and_no_second_native_dispatch(self):
        self.fixture(); request = self.request(frames._CURRENT)
        reply = self.serve(request, chunks=[request[:2], request[2:]], writes=[1, frames._RESPONSE.size - 1])
        self.assertEqual(reply[-1], 0)
        self.assertEqual(self.control._request_bytes, request)
        self.assertEqual(self.control._written, frames._RESPONSE.size)
        self.assertEqual(sum(e[:2] == ('operate', 4) for e in self.f.events), 1)

    def test_eof_and_incomplete_payload_retain_raw_bytes_without_owner_call(self):
        for request in (b'', b'AL', frames._request(frames._LIMIT, 1, 7, frames._ORDINAL.pack(0))[:-1]):
            with self.subTest(request=request):
                self.fixture(); before = list(self.f.events)
                with self.assertRaises(frames._OriginalWorkerControlPending): self.serve(request)
                self.assertEqual(self.control._request_bytes, request)
                self.assertEqual(self.f.events, before)

    def test_lost_response_after_owner_call_is_unknown_and_never_replays_admit(self):
        self.fixture()
        with patch.object(self.f.pipe, 'write', new=AsyncMock(side_effect=OSError('lost write'))):
            request = self.request(frames._ADMIT)
            incoming = [request]
            with patch.object(self.f.pipe, 'read', new=AsyncMock(side_effect=incoming)):
                with self.assertRaises(frames._OriginalWorkerControlPending): asyncio.run(self.control.serve_once())
        self.assertEqual(frames._RESPONSE.unpack(self.control._response_bytes)[-1], 0)
        self.assertEqual(self.control._serial, 1)
        before = list(self.f.events)
        with self.assertRaises(frames._OriginalWorkerControlPending): asyncio.run(self.control.serve_once())
        self.assertEqual(self.f.events, before)
        self.assertTrue(self.channel._admit_attempted)

    def test_invalid_write_progress_is_not_an_ack_or_a_retry_loop(self):
        for progress in (0, True, -1, frames._RESPONSE.size + 1):
            with self.subTest(progress=progress):
                self.fixture()
                with self.assertRaises(frames._OriginalWorkerControlPending):
                    self.serve(self.request(frames._CURRENT), writes=[progress])
                self.assertEqual(self.control._serial, 1)
                self.assertEqual(self.control._written, 0)
                self.assertIsNotNone(self.control._response_bytes)

    def test_copy_pickle_foreign_pipe_and_reentry_cannot_acquire_original_channel(self):
        self.fixture()
        for clone in (copy.copy, copy.deepcopy, pickle.dumps):
            with self.assertRaises(TypeError): clone(self.control)
        original = self.control._pipe
        self.control._pipe = object()
        with self.assertRaises(ValueError): asyncio.run(self.control.serve_once())
        self.control._pipe = original
        self.control._active = True
        with self.assertRaises(ValueError): asyncio.run(self.control.serve_once())
        self.control._active = False

    def test_real_pipe_roundtrip_uses_existing_nonblocking_original_pipe_steps(self):
        # Real pipe bytes/FDs, with Native/funding/process identity counters.
        # No child, actual Native admission or VM is implied.
        real_close = os.close
        input_read, input_write = os.pipe()
        output_read, output_write = os.pipe()
        error_read, error_write = os.pipe()
        self.f = ChannelFixture(self)
        for fd in (input_read, input_write, output_read, output_write, error_read, error_write):
            self.addCleanup(real_close, fd)
        self.f.process._stdin[1].value = input_write
        self.f.process._stdout[0].value = output_read
        self.f.process._stderr[0].value = error_read
        self.channel = self.f.take()
        self.control = frames._OriginalWorkerControlFrames(self.channel)
        self.f.pipe.prepare()
        request = self.request(frames._CURRENT)
        self.assertEqual(os.write(output_write, request), len(request))
        asyncio.run(self.control.serve_once())
        reply = os.read(input_read, frames._RESPONSE.size)
        self.assertEqual(frames._RESPONSE.unpack(reply), (b'ALC1', frames._CURRENT, 1, 7, 0))
        self.assertFalse(self.f.pipe._active)
        self.assertFalse(self.f.process._parent_pipe_borrowed)
        self.assertFalse(self.f.process._parent_closed)

    def test_cancellation_keeps_same_exchange_and_never_starts_a_second_read(self):
        self.fixture()
        async def check():
            started = asyncio.Event()
            async def read(maximum):
                started.set()
                await asyncio.Future()
            with patch.object(self.f.pipe, 'read', side_effect=read) as reader:
                task = asyncio.create_task(self.control.serve_once())
                await started.wait()
                task.cancel()
                with self.assertRaises(frames._OriginalWorkerControlPending): await task
                self.assertIsInstance(self.control._unknown, asyncio.CancelledError)
                with self.assertRaises(frames._OriginalWorkerControlPending): await self.control.serve_once()
                self.assertEqual(reader.call_count, 1)
        asyncio.run(check())
        self.assertFalse(self.channel._closed)
        self.assertFalse(self.f.process._parent_closed)

    def test_post_read_identity_failure_retains_same_raw_request_without_native_dispatch(self):
        self.fixture(); request = self.request(frames._ADMIT); before = list(self.f.events)
        async def read(maximum):
            self.channel._control_original = object()
            return request
        with patch.object(self.f.pipe, 'read', side_effect=read):
            with self.assertRaises(frames._OriginalWorkerControlPending): asyncio.run(self.control.serve_once())
        self.assertEqual(self.control._request_bytes, request)
        self.assertEqual(self.f.events, before)

    def first_header(self, chunks):
        self.f = ChannelFixture(self)
        with patch('actql_sdk._local_worker_pipe.os.set_blocking'):
            self.f.pipe.prepare()
        with patch.object(self.f.pipe, 'read', new=AsyncMock(side_effect=chunks)):
            return asyncio.run(frames._OriginalFirstControlHeader._read_original(self.f.pipe))

    def test_initial_header_is_held_before_native_capture_and_consumed_once_with_body(self):
        header_bytes = frames._request(frames._BIND,1,7,b'x'*frames._SPAN.size)[:frames._HEADER.size]
        header=self.first_header([header_bytes[:3],header_bytes[3:]])
        self.assertEqual(self.f.events,[])
        self.assertEqual(header.nonce_data(),7)
        self.assertEqual(header._raw,header_bytes)
        self.channel=self.f.take()
        self.control=frames._OriginalWorkerControlFrames(self.channel,_initial_header=header)
        payload=frames._span_payload(self.f.span())
        reply=self.serve(payload)
        self.assertEqual(reply,(b'ALC1',frames._BIND,1,7,0))
        self.assertTrue(header._taken)
        self.assertIs(header._consumer,self.control)
        self.assertEqual(self.control._request_bytes,header_bytes+payload)
        self.assertEqual(self.serve(self.request(frames._CURRENT))[-1],0)
        self.assertEqual(sum(e[0]=='bind' for e in self.f.events),1)
        self.assertFalse(self.f.process._parent_closed or self.f.domain._closed)

    def test_invalid_first_header_never_captures_native_or_acquires_permission(self):
        for raw in (frames._HEADER.pack(b'xxxx',frames._BIND,1,7),
                    frames._HEADER.pack(b'ALC1',frames._CURRENT,1,7),
                    frames._HEADER.pack(b'ALC1',frames._BIND,2,7),
                    frames._HEADER.pack(b'ALC1',frames._BIND,1,0)):
            with self.subTest(raw=raw):
                with self.assertRaises(frames._OriginalFirstControlPending) as caught:self.first_header([raw])
                original=caught.exception.cleanup_header
                self.assertEqual(original._raw,raw)
                self.assertIs(self.f.pipe._control_header_original,original)
                self.assertEqual(self.f.events,[])
                with self.assertRaises(frames._OriginalFirstControlPending):original.nonce_data()
                with self.assertRaises(ValueError):asyncio.run(frames._OriginalFirstControlHeader._read_original(self.f.pipe))

    def test_first_header_read_loss_preserves_partial_bytes_and_original_pipe_without_reread(self):
        with self.assertRaises(frames._OriginalFirstControlPending) as caught:
            self.first_header([b'AL',OSError('lost read return')])
        original=caught.exception.cleanup_header
        self.assertEqual(original._raw,b'AL')
        self.assertIs(original._pipe,self.f.pipe)
        self.assertFalse(self.f.process._parent_closed)
        self.assertEqual(self.f.events,[])
        with patch.object(self.f.pipe,'read',new=AsyncMock()) as read:
            with self.assertRaises(ValueError):asyncio.run(frames._OriginalFirstControlHeader._read_original(self.f.pipe))
            read.assert_not_called()

    def test_header_copy_or_omission_cannot_adopt_already_read_prefix(self):
        raw=frames._HEADER.pack(b'ALC1',frames._BIND,1,7)
        header=self.first_header([raw]);self.channel=self.f.take()
        for copy_method in (copy.copy,copy.deepcopy,pickle.dumps):
            with self.assertRaises(TypeError):copy_method(header)
        clone=object.__new__(frames._OriginalFirstControlHeader);clone.__dict__.update(header.__dict__)
        with self.assertRaises(ValueError):frames._OriginalWorkerControlFrames(self.channel)
        with self.assertRaises(ValueError):frames._OriginalWorkerControlFrames(self.channel,_initial_header=clone)
        self.assertIsNone(self.channel._control_original)
        self.control=frames._OriginalWorkerControlFrames(self.channel,_initial_header=header)
        with self.assertRaises(ValueError):frames._OriginalWorkerControlFrames(self.channel,_initial_header=header)
        self.assertIs(header._consumer,self.control)

    def test_child_identity_changed_after_header_keeps_partial_control_and_never_repairs_binding(self):
        raw=frames._HEADER.pack(b'ALC1',frames._BIND,1,7)
        header=self.first_header([raw]);self.f.process._pid=5432;self.channel=self.f.take()
        with self.assertRaises(frames._OriginalWorkerControlPending) as caught:
            frames._OriginalWorkerControlFrames(self.channel,_initial_header=header)
        original=caught.exception.cleanup_control
        self.assertIs(self.channel._control_original,original)
        self.assertIs(original._initial_header,header)
        self.assertEqual(header._raw,raw)
        self.assertFalse(self.channel._closed or self.f.domain._closed)
        self.assertFalse(any(e[0]=='bind' for e in self.f.events))

    def test_header_postread_revocation_keeps_bytes_and_does_not_infer_no_child(self):
        self.f=ChannelFixture(self)
        with patch('actql_sdk._local_worker_pipe.os.set_blocking'):self.f.pipe.prepare()
        raw=frames._HEADER.pack(b'ALC1',frames._BIND,1,7)
        async def changed(maximum):self.f.process._stdout[0].close_attempted=True;return raw
        with patch.object(self.f.pipe,'read',side_effect=changed):
            with self.assertRaises(frames._OriginalFirstControlPending) as caught:
                asyncio.run(frames._OriginalFirstControlHeader._read_original(self.f.pipe))
        original=caught.exception.cleanup_header
        self.assertEqual(original._raw,raw)
        self.assertIs(self.f.pipe._control_header_original,original)
        self.assertIsNotNone(self.f.process._pid)
        self.assertFalse(self.f.process._parent_closed)

    def test_first_header_requires_existing_prepared_pipe_before_any_read(self):
        self.f=ChannelFixture(self)
        with patch.object(self.f.pipe,'read',new=AsyncMock()) as read:
            with self.assertRaises(ValueError):asyncio.run(frames._OriginalFirstControlHeader._read_original(self.f.pipe))
            read.assert_not_called()
        self.assertIsNone(self.f.pipe._control_header_original)

    def test_frame_encoders_reject_boolean_fields_unknown_ops_and_nonfixed_lengths(self):
        for args in ((True, 1, 7), (7, 1, 7), (0, 1, 7), (1, True, 7), (1, 1, True),
                     (1, 0, 7), (1, 1, 0), (1, 1, 7, b'x')):
            with self.subTest(args=args), self.assertRaises(ValueError): frames._request(*args)


if __name__ == '__main__':
    unittest.main()
