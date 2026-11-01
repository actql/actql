"""Saved caller/real FD boundary with scalar Core ports, not installed acceptance."""
import asyncio
import copy
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import httpx

from actql_sdk._local_commit_projection import OriginalCommitProjection
from actql_sdk._local_core import LocalCoreError, _Input, _Output
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_saved_read import OriginalSavedResultRead
import actql_sdk._local_saved_read as saved_read_module
from actql_sdk._local_sdk_delivery_storage import OriginalSDKDeliveryStore
import test_local_commit_store_caller as export_fixture
import test_local_reader_facts as physical_fixture
import test_local_submission_lookup as host_fixture


class SavedReadPortsTests(unittest.TestCase):
    def test_saved_metadata_uses_same_admitted_packet_without_a_second_current_parse(self):
        from tempfile import TemporaryDirectory
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        packet = {'resultOrdinal': '0', 'bindingOrdinal': '0', 'kind': 'result-originals',
                  'resultName': 'answer', 'runDefinitionCid': reference['runDefinitionCid'],
                  **{name: '{"fixture":"transport"}' for name in
                     ('index', 'manifest', 'definition', 'artifact', 'retention', 'binding')}}
        helper = host_fixture.LocalSubmissionLookupTests()
        helper.addCleanup = self.addCleanup
        failure = OSError('original next payload acquisition')
        with TemporaryDirectory(prefix='actql-saved-metadata-original-') as directory:
            host, core, _, counts, _ = helper.fixture(directory, packet,
                run_reference=reference, result_name='answer')
            saved = OriginalSavedResultRead(host)
            host._saved_result_reads.append(saved)
            with patch('actql_sdk._local_saved_read._object', wraps=saved_read_module._object) as decode, patch.object(
                    core, 'reserve_saved_payload_record', side_effect=failure) as acquire:
                with self.assertRaises(OSError) as caught:
                    saved.prepare(reference, 'answer', 'jsonl', 'original-attempt')
            self.assertIs(caught.exception, failure)
            acquire.assert_called_once()
            self.assertEqual(counts, {'produce': 1, 'validate': 2})
            decode.assert_not_called()
            source = saved._source
            self.assertIsNotNone(source)
            self.assertIs(host._projections[-1], source)
            self.assertIs(core._loans[source.ticket], source)
            self.assertIsNotNone(saved._projection)
            self.assertFalse(saved._preparing)
            self.assertTrue(host.close())

    def test_payload_output_uses_its_live_or_saved_original_parent_until_child_ack(self):
        for saved in (False, True):
            with self.subTest(saved=saved):
                core, parent, _, projection, calls, state, _, _, _ = (
                    export_fixture.OriginalCommitStoreCallerTests.bridge(self))
                if saved:
                    parent = _Output(core._identity, parent.ticket, parent.handle,
                                     parent.limit, 'submission_lookup')
                    core._loans[parent.ticket] = parent
                    projection = OriginalCommitProjection.from_saved_read(
                        core, parent, 31, cleanup=lambda: state['cleanup'])
                holder = OriginalSDKDeliveryStore.__new__(OriginalSDKDeliveryStore)
                holder._core = core
                holder._observation = SimpleNamespace(_projection=projection)
                holder._workspace_cleanup = lambda: state['cleanup']
                holder._payload_outputs, holder._uncertain_payload = {}, {}
                request = _Input(core._identity, 99, 91, 0)
                output = holder._reserve_payload_output(request)
                self.assertIs(holder._payload_outputs[request.ticket], output)
                self.assertIs(core._loans[output.ticket], output)
                self.assertIs(core._loans[parent.ticket], parent)
                self.assertFalse(holder._uncertain_payload)
                reserves = [args for family, name, args in calls
                            if family == 'publication_commit_export' and name == 'reserve']
                self.assertEqual(len(reserves), 1)
                self.assertEqual(reserves[0][0], parent.handle)
                with self.assertRaisesRegex(RuntimeError, 'cleanup is pending'):
                    holder._reserve_payload_output(request)
                state['cleanup'] = False
                self.assertFalse(holder._close_payload_output(request.ticket))
                self.assertIs(holder._payload_outputs[request.ticket], output)
                state['cleanup'] = True
                self.assertTrue(holder._close_payload_output(request.ticket))
                self.assertNotIn(output.ticket, core._loans)
                self.assertIs(core._loans[parent.ticket], parent)
                self.assertFalse(projection.pending_outputs)

    def test_partial_saved_projection_returns_before_dependent_store_workspace(self):
        from types import SimpleNamespace
        calls = []
        pending = [object()]
        ready = [False]
        class Projection:
            def close(self):
                calls.append('projection')
                if not ready[0]:
                    return False
                pending.clear()
                return True
        class Store:
            def close(self):
                calls.append('store')
                return not pending
        host = SimpleNamespace(_core=SimpleNamespace(_closing=False))
        saved = OriginalSavedResultRead(host)
        saved._projection, saved._delivery = Projection(), Store()
        self.assertFalse(saved.close())
        self.assertEqual(calls, ['projection'])
        self.assertFalse(saved._closed)
        ready[0] = True
        self.assertTrue(saved.close())
        self.assertEqual(calls, ['projection', 'projection', 'store'])
        self.assertTrue(saved._closed)

    def test_saved_projection_cannot_issue_live_publication_or_publisher_calls(self):
        files = physical_fixture.ReaderFactsTests()
        with files.file(slots=4) as (_, root, _, final):
            live_reader = files.transfer_ready(root, final)
            core, record, publisher, _, _, calls, _, _ = files.bridge(root, live_reader)
            parent = _Output(core._identity, 7, 23, 1048576, 'submission_lookup')
            core._loans[7] = parent
            saved = OriginalCommitProjection.from_saved_read(core, parent, 31, cleanup=lambda: True)
            before = len(calls)
            for action in (
                saved.count,
                saved.storage_count,
                lambda: saved.authorize_commit(publisher),
                lambda: saved.project_contract(0, lambda _: None),
                lambda: saved.project_index_lookup_key(lambda _: None),
            ):
                with self.assertRaises(ValueError):
                    action()
            with self.assertRaises(ValueError):
                OriginalCommitProjection.from_saved_read(core, copy.copy(parent), 31,
                                                         cleanup=lambda: True)
            self.assertEqual(len(calls), before)
            self.assertIs(core._loans[10], record)
            self.assertTrue(saved.close())

    def test_real_saved_descriptor_keeps_original_metadata_loan_and_current_refusal(self):
        files = physical_fixture.ReaderFactsTests()
        with files.file(slots=4) as (_, root, _, final):
            live_reader = files.transfer_ready(root, final)
            core, record, _, _, _, _, state, wires = files.bridge(root, live_reader)
            parent = _Output(core._identity, 7, 23, 1048576, 'submission_lookup')
            core._loans[7] = parent
            projection = OriginalCommitProjection.from_saved_read(core, parent, 31,
                                                                  cleanup=lambda: True)
            expected = root.observe_completed_reader(live_reader)
            reader = root.open_saved_payload(final.name, expected)
            while not reader.eof:
                chunk = root.read_original(reader)
                root.release_original_chunk(reader, chunk)
            facts = OriginalReaderFacts(projection, record, root, reader, 2, 7,
                'sha256:' + '1' * 64, 'sha256:' + '3' * 64,
                cleanup=lambda: state['meta_cleanup'], stopped=lambda _: True)
            with facts.serialized():
                facts.validate()
            original = facts.pending_input
            self.assertIsNotNone(original)
            self.assertEqual(len(wires), 1)
            state['snapshot'] = -32
            with self.assertRaises(LocalCoreError):
                facts.validate()
            self.assertIs(facts.pending_input, original)
            state['meta_cleanup'] = False
            self.assertFalse(facts.close())
            self.assertIsNotNone(reader.descriptor)
            state['meta_cleanup'] = True
            self.assertTrue(facts.close())
            self.assertEqual(root.observe_original(reader), expected)
            self.assertTrue(root.close_original(reader))
            self.assertTrue(projection.close())

    def test_public_cold_read_registers_same_carrier_without_selecting_a_live_run(self):
        from tempfile import TemporaryDirectory
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        helper = host_fixture.LocalSubmissionLookupTests()
        helper.addCleanup = self.addCleanup
        with TemporaryDirectory() as directory:
            host, _, _, _, _ = helper.fixture(directory, {'kind': 'missing'})
            seen = []
            def prepare(carrier, actual_reference, name, format, attempt):
                self.assertIs(host._saved_result_reads[-1], carrier)
                self.assertFalse(host._run_loans)
                self.assertFalse(host._prepared_inputs)
                seen.append((carrier, actual_reference, name, format, attempt))
                return httpx.Response(200, content=b'{"n":1}\n')
            with patch.object(OriginalSavedResultRead, 'prepare', prepare), patch.object(
                    host, '_select_original_run', side_effect=AssertionError('cold is not live')):
                response = asyncio.run(host._open_operation('read', {
                    'ref': reference, 'resultName': 'answer', 'format': 'jsonl', 'attemptId': 'original-read'}))
            self.assertEqual(response.content, b'{"n":1}\n')
            self.assertEqual(seen[0][1:], (reference, 'answer', 'jsonl', 'original-read'))
            response.close()
            self.assertTrue(host.close())

    def test_failed_cold_preparation_remains_in_same_host_cleanup_inventory(self):
        from tempfile import TemporaryDirectory
        helper = host_fixture.LocalSubmissionLookupTests()
        helper.addCleanup = self.addCleanup
        with TemporaryDirectory() as directory:
            host, _, _, _, _ = helper.fixture(directory, {'kind': 'missing'})
            calls = []
            def fail(carrier, *args):
                calls.append(carrier)
                raise OSError('same original supplier failure')
            with patch.object(OriginalSavedResultRead, 'prepare', fail):
                with self.assertRaises(OSError):
                    asyncio.run(host._open_operation('read', {'ref': {}, 'resultName': 'answer',
                        'format': 'jsonl', 'attemptId': 'original-failure'}))
            self.assertEqual(len(calls), 1)
            self.assertIs(host._saved_result_reads[0], calls[0])
            self.assertFalse(host._run_loans)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
