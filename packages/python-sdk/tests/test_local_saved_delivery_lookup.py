"""Actual same-Store read frame with scalar Core; no real grant/VM acceptance."""
import asyncio
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
        packet = {'kind': 'result-originals', 'resultName': 'answer',
                  'resultOrdinal': '0', 'bindingOrdinal': '0',
                  'runDefinitionCid': reference['runDefinitionCid'],
                  **{key: '{}' for key in ('index', 'manifest', 'definition', 'artifact', 'retention', 'binding')}}
        helper = fixture.LocalSubmissionLookupTests()
        helper.addCleanup = self.addCleanup
        host, core, calls, counts, _ = helper.fixture(directory, packet,
            run_reference=reference, result_name='answer')
        base = core._call
        children = {}
        observed = []
        state = {'produce': 0, 'close': 0}
        wire = b'{"kind":"missing"}'
        def call(family, name, *args):
            if family == 'publication_commit_export':
                observed.append((name, args))
                if name == 'reserve':
                    self.assertIsNotNone(core._journal_callbacks(
                        host._installation.binding._current.ticket).reader)
                    handle = 10000 + args[1]
                    children[handle] = args[1]
                    self.assertEqual(args[0], host._saved_result_reads[-1]._source.handle)
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
            async def lookup():
                response = await host._open_operation('delivery-attempt', {
                    'ref': reference, 'resultName': 'answer', 'attemptId': 'same-attempt'})
                self.assertEqual(json.loads(await response.aread()), {'kind': 'missing'})
                await response.aclose()
            with (patch.object(LocalFileRoot, 'open_saved_payload', side_effect=AssertionError('payload')),
                  patch.object(OriginalSDKDeliveryStore, '__init__', side_effect=AssertionError('grant'))):
                asyncio.run(lookup())
            self.assertEqual(sum(name == 'reserve' for name, _ in calls), 1)
            self.assertEqual(sum(name == 'produce_sdk_delivery_lookup' for name, _ in calls), 1)
            self.assertFalse(host._run_loans)
            self.assertFalse(host._prepared_inputs)
            self.assertIsNone(host._saved_result_reads[0]._record)
            self.assertIsNone(host._saved_result_reads[0]._reader)
            self.assertTrue(host.close())

    def test_failed_lookup_keeps_same_child_and_source_until_actual_return(self):
        with TemporaryDirectory() as directory:
            host, reference, calls, state, _ = self.host(directory)
            state.update(produce=-32, close=-9)
            with self.assertRaises(LocalCoreError):
                asyncio.run(host._open_operation('delivery-attempt', {
                    'ref': reference, 'resultName': 'answer', 'attemptId': 'same-failed-attempt'}))
            held = host._saved_result_reads[0]
            child = held._projection.pending_outputs[0]
            self.assertFalse(host.close())
            self.assertIs(held._projection.pending_outputs[0], child)
            self.assertFalse(held._source_closed)
            state['close'] = 0
            self.assertTrue(host.close())
            self.assertEqual(sum(name == 'reserve' for name, _ in calls), 1)
            self.assertEqual(sum(name == 'produce_sdk_delivery_lookup' for name, _ in calls), 1)


if __name__ == '__main__':
    unittest.main()
