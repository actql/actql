"""Original Host delivery custody; scalar Core, real File/SQLite only."""
import copy
import json
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_sdk_delivery_storage import SDKDeliveryStorageCleanupPending
from actql_sdk._local_storage import LocalStorageError, StoredBytes
import test_local_reader_facts as file_fixture
import test_local_sdk_read_evidence_host as host_fixture
import test_local_sdk_delivery_storage as storage_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class SDKDeliveryHostTests(unittest.TestCase):
    def host(self, root, reader):
        case = host_fixture.SDKReadEvidenceHostTests()
        case.addCleanup = self.addCleanup
        host, run, values = case.host(root, reader)
        _, store, core, binding, observation, request, _, _, codes, _ = values
        rows = storage_fixture.SDKDeliveryStorageTests().rows()
        packet = json.dumps(rows).encode()
        host._publications = [observation._projection._publication]
        previous = core._call
        outputs, calls = {}, []
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'reserve_bounded':
                return storage_fixture.reserve_measured_delivery_output(self, observation._projection, packet, args)
            if (family, name) == ('publication_commit_export', 'retire_sdk_delivery_output'):
                loan = observation._projection._core._loans
                ticket = next(value.ticket for value in loan.values() if value.handle == args[0])
                return 0 if core._cleanup(ticket) == 0 else -9
            if family == 'publication_commit_export' and name in (
                    'measure_sdk_read_delivery_storage', 'emit_sdk_read_delivery_storage',
                    'validate_sdk_read_delivery_storage'):
                frame = core._journal_callbacks(binding._current.ticket).reader
                self.assertIs(frame.owner, store)
                calls.append((name, args))
                if name == 'measure_sdk_read_delivery_storage':
                    return len(packet)
                if name == 'emit_sdk_read_delivery_storage':
                    outputs[args[0]] = packet
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return host, run, values, rows, calls

    def test_same_host_run_store_and_holder_survive_original_physical_cas(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            host, run, values, rows, calls = self.host(root, helper.transfer_ready(root, final))
            _, store, core, _, observation, request, _, _, codes, _ = values
            projection = observation._projection
            holder = host._original_sdk_delivery_store(run, projection)
            before = core._next_ticket
            self.assertIs(host._original_sdk_delivery_store(run, projection), holder)
            self.assertEqual(core._next_ticket, before)
            for candidate in (copy.copy(run),):
                with self.assertRaises(ValueError): host._original_sdk_delivery_store(candidate, projection)
            host._persist_original_sdk_delivery(run, projection, request)
            self.assertEqual(len(calls), 3)
            self.assertEqual(store.read(store.namespaced_key(rows[4]['table'], rows[4]['key'])),
                             StoredBytes(0, rows[4]['body'].encode()))
            with self.assertRaises(LocalStorageError): host._persist_original_sdk_delivery(run, projection, request)
            self.assertEqual(len(calls), 3)
            codes['current', 'bind'] = -35
            with self.assertRaises(LocalCoreError): host._original_sdk_delivery_store(run, projection)
            self.assertIs(host._sdk_deliveries[projection._publication.ticket], holder)
            self.assertIs(host._runs._runs[run.handle], run)
            self.assertTrue(holder.close())

    def test_failed_reservation_is_registered_once_before_escape(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            host, run, values, _, calls = self.host(root, helper.transfer_ready(root, final))
            _, _, core, _, observation, request, _, _, codes, _ = values
            codes['workspace', 'reserve'] = -4
            with self.assertRaises(SDKDeliveryStorageCleanupPending) as failure:
                host._original_sdk_delivery_store(run, observation._projection)
            holder = failure.exception.cleanup_storage
            self.assertIs(host._sdk_deliveries[observation._projection._publication.ticket], holder)
            before = core._next_ticket
            with self.assertRaises(RuntimeError): host._persist_original_sdk_delivery(run, observation._projection, request)
            self.assertEqual(core._next_ticket, before)
            self.assertFalse(calls)
            self.assertTrue(holder.close())

    def test_child_cleanup_keeps_same_workspace_store_and_run_until_retry(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            host, run, values, _, _ = self.host(root, helper.transfer_ready(root, final))
            _, _, core, _, observation, _, _, _, _, _ = values
            holder = host._original_sdk_delivery_store(run, observation._projection)
            workspace = holder._workspace
            with patch.object(observation._projection, 'close', return_value=True), \
                    patch.object(core, 'close_workspace', return_value=False) as close, \
                    patch.object(core, 'retire_publication_observation', return_value=False) as retire:
                self.assertFalse(host.close())
                close.assert_called_once_with(workspace)
                retire.assert_not_called()
                self.assertIs(core._loans[workspace.ticket], workspace)
                self.assertIs(host._runs._runs[run.handle], run)
            with patch.object(core, 'retire_publication_observation', return_value=False) as retire:
                self.assertFalse(host.close())
                retire.assert_called_once_with(observation._projection._publication)
            self.assertFalse(host._sdk_deliveries)
            self.assertNotIn(workspace.ticket, core._loans)
            self.assertIs(host._runs._runs[run.handle], run)
