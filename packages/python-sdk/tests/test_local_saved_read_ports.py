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
from actql_sdk._local_sdk_delivery_storage import OriginalSDKDeliveryStore
import test_local_commit_store_caller as export_fixture
import test_local_reader_facts as physical_fixture
import test_local_submission_lookup as host_fixture


class SavedReadPortsTests(unittest.TestCase):
    def _record_preparation_ports(self, *, deny_at=None, fail_produce=False):
        # Actual saved caller/current wrappers through record materialization;
        # Core, installation and metadata parsing are explicit semantic ports.
        # This does not claim a complete saved read, physical IO or authority.
        class StopAfterRecord(Exception): pass
        events, currents = [], []
        source, record, current = object(), object(), object()
        original_failure = PermissionError('same original current refused')
        producer_failure = OSError('same original record producer failure')
        class Core:
            _inputs = {7: SimpleNamespace(payload=b'original-source-metadata')}
            def validate_submission_lookup(self, actual_source, actual_current):
                events.append('source-current')
                self_test.assertIs(actual_source, parent)
                self_test.assertIs(actual_current, current)
                currents.append(True)
                if len(currents) == deny_at: raise original_failure
            def reserve_saved_payload_record(self, actual_source, *, cleanup):
                self_test.assertIs(actual_source, parent)
                events.append('reserve-record')
                return record
            def produce_payload_record(self, actual, configuration):
                self_test.assertIs(actual, saved._record)
                self_test.assertIs(actual, record)
                self_test.assertEqual(configuration, 31)
                events.append('produce-record')
                if fail_produce: raise producer_failure
            def read_payload_record(self, actual, configuration):
                self_test.assertIs(actual, saved._record)
                self_test.assertEqual(configuration, 31)
                events.append('validate-and-copy-record')
                return b'original-record'
        self_test = self
        parent = SimpleNamespace(ticket=7, original=source)
        def inspect(consume): consume(current)
        installation = SimpleNamespace(_store=SimpleNamespace(_max_payload_bytes=8192),
            _results=object(), binding=SimpleNamespace(inspect=inspect))
        host = SimpleNamespace(_core=Core(), _active=lambda: installation,
            _configuration=SimpleNamespace(sdk=True, handle=31),
            _retain_original_result_read=lambda *_: parent, _reserve=lambda acquire: acquire())
        saved = OriginalSavedResultRead(host)
        def parse(raw, limit):
            if limit == 1048576:
                self.assertEqual(raw, b'original-source-metadata')
                return {'resultOrdinal': '0', 'bindingOrdinal': '0'}
            self.assertEqual((raw, limit), (b'original-record', 65536))
            raise StopAfterRecord()
        with patch('actql_sdk._local_saved_read._object', side_effect=parse), patch.object(
                OriginalCommitProjection, 'from_saved_read', return_value=object()):
            try: saved.prepare({}, 'answer', 'jsonl', 'original-attempt')
            except BaseException as error: result = error
            else: self.fail('Finite fixture must stop before subsequent physical reader work')
        return saved, parent, record, result, StopAfterRecord, events, currents, original_failure, producer_failure

    def test_saved_record_produce_and_validated_copy_share_one_original_current_frame(self):
        saved, parent, record, result, stop, events, currents, _, _ = self._record_preparation_ports()
        self.assertIsInstance(result, stop)
        self.assertEqual(len(currents), 4)  # metadata pair, then materialization pair
        self.assertEqual(events, ['source-current', 'source-current', 'reserve-record',
            'source-current', 'produce-record', 'validate-and-copy-record', 'source-current'])
        self.assertIs(saved._source, parent)
        self.assertIs(saved._record, record)
        self.assertFalse(saved._preparing)

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
