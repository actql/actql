"""Actual same-Store read frame with scalar Core; no real grant/VM acceptance."""
import asyncio
from contextlib import contextmanager
import json
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileRoot
from actql_sdk._local_sdk_delivery_storage import OriginalSDKDeliveryStore
import test_local_submission_lookup as fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SavedDeliveryLookupTests(unittest.TestCase):
    def host(self, directory):
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        packet = fixture.saved_coordinates_wire(reference['runDefinitionCid'], 'answer')
        helper = fixture.LocalSubmissionLookupTests()
        helper.addCleanup = self.addCleanup
        host, core, calls, counts, _ = helper.fixture(directory, packet,
            run_reference=reference, result_name='answer')
        @contextmanager
        def original_allowance():
            core._host_operation_scope = object()
            core._host_fuel_phase = 'operation'
            try:
                yield
            finally:
                core._host_operation_scope = None
                core._host_fuel_phase = None

        core._host_operation = original_allowance
        core._host_cleanup_depth = 0
        base = core._call
        children = {}
        observed = []
        state = {'produce': 0, 'close': 0}
        wire = b'{"kind":"not_found"}'
        def call(family, name, *args):
            if family == 'publication_commit_export':
                observed.append((name, args))
                if name == 'reserve':
                    return -4  # Available capacity does not cover the general 1 MiB output.
                if name == 'reserve_bounded':
                    self.assertIsNotNone(core._journal_callbacks(
                        host._installation.binding._current.ticket).reader)
                    handle = 10000 + args[1]
                    children[handle] = args[1]
                    self.assertEqual(args[0], host._saved_result_reads[-1]._source.handle)
                    self.assertEqual(args[2], 8192)
                    return handle
                if name == 'produce_sdk_delivery_lookup':
                    frame = core._journal_callbacks(host._installation.binding._current.ticket).reader
                    self.assertIs(frame.owner, host._installation._store)
                    self.assertTrue(host._installation._store._connection.in_transaction)
                    self.assertEqual(args[2], host._saved_result_reads[-1]._source.handle)
                    return state['produce']
                if name == 'length':
                    return len(wire)
                if name == 'close':
                    return state['close'] or core._cleanup(children[args[0]])
                raise AssertionError((family, name))
            if family == 'buffer' and name == 'byte' and args[0] in children:
                return wire[args[1]]
            return base(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return host, reference, observed, state, counts

    def test_public_saved_lookup_is_same_snapshot_read_without_payload_grant_or_write(self):
        with TemporaryDirectory() as directory:
            host, reference, calls, _, _ = self.host(directory)
            core = host._core
            initial_loans = dict(core._loans)
            initial_projections = tuple(host._projections)

            async def lookup():
                for attempt in ('first-attempt', 'second-attempt'):
                    response = await host._open_ordinary_saved('delivery-attempt', {
                        'ref': reference, 'resultName': 'answer', 'attemptId': attempt})
                    try:
                        self.assertFalse(host._saved_result_reads)
                        self.assertEqual(tuple(host._projections), initial_projections)
                        stream = response.stream
                        self.assertIn(stream, host._response_streams)
                        self.assertIs(core._loans[stream._loan.ticket], stream._loan)
                        self.assertEqual(json.loads(await response.aread()), {'kind': 'not_found'})
                    finally:
                        await response.aclose()
                    self.assertEqual(core._loans, initial_loans)

            with (patch.object(LocalFileRoot, 'open_saved_payload', side_effect=AssertionError('payload')),
                  patch.object(OriginalSDKDeliveryStore, '__init__', side_effect=AssertionError('grant'))):
                asyncio.run(lookup())
            self.assertEqual([name for name, _ in calls if name.startswith('reserve')],
                             ['reserve_bounded', 'reserve_bounded'])
            self.assertEqual(sum(name == 'produce_sdk_delivery_lookup' for name, _ in calls), 2)
            self.assertFalse(host._run_loans)
            self.assertFalse(host._prepared_inputs)
            self.assertTrue(host.close())

    def test_lookup_close_refusal_keeps_same_unattached_response_and_unreturned_loans(self):
        with TemporaryDirectory() as directory:
            host, reference, calls, _, _ = self.host(directory)
            core = host._core
            original_close = core.close_input
            refused = []
            allow_return = False

            def close_input(value):
                if not allow_return and value is host._saved_result_reads[-1]._request:
                    refused.append(value)
                    return False
                return original_close(value)

            with patch.object(core, 'close_input', side_effect=close_input):
                with self.assertRaisesRegex(RuntimeError, 'saved delivery lookup cleanup'):
                    asyncio.run(host._open_ordinary_saved('delivery-attempt', {
                        'ref': reference, 'resultName': 'answer', 'attemptId': 'same-attempt'}))
                held, = host._saved_result_reads
                stream, = host._response_streams
                request, = refused
                self.assertIs(held._request, request)
                self.assertIsNone(held._clock)
                self.assertFalse(stream._attached)
                self.assertIs(core._loans[stream._loan.ticket], stream._loan)
                source = held._source
                self.assertIs(host._projections[-1], source)
                self.assertFalse(host.close())
                self.assertIs(host._saved_result_reads[0], held)
                self.assertIs(held._source, source)
                self.assertIs(core._loans[request.ticket], request)
                self.assertEqual(refused, [request, request])
                allow_return = True
                self.assertTrue(host.close())
            self.assertEqual(sum(name == 'produce_sdk_delivery_lookup' for name, _ in calls), 1)

    def test_failed_lookup_keeps_same_child_and_source_until_actual_return(self):
        with TemporaryDirectory() as directory:
            host, reference, calls, state, _ = self.host(directory)
            state.update(produce=-32, close=-9)
            with self.assertRaises(LocalCoreError):
                asyncio.run(host._open_ordinary_saved('delivery-attempt', {
                    'ref': reference, 'resultName': 'answer', 'attemptId': 'same-failed-attempt'}))
            held = host._saved_result_reads[0]
            child = held._projection.pending_outputs[0]
            self.assertFalse(host.close())
            self.assertIs(held._projection.pending_outputs[0], child)
            self.assertFalse(held._source_closed)
            state['close'] = 0
            self.assertTrue(host.close())
            self.assertEqual([name for name, _ in calls if name.startswith('reserve')], ['reserve_bounded'])
            self.assertEqual(sum(name == 'produce_sdk_delivery_lookup' for name, _ in calls), 1)


if __name__ == '__main__':
    unittest.main()
