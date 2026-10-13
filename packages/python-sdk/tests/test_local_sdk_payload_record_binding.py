"""Nominal record selection plumbing; scalar Core, no byte disclosure."""
import copy
import unittest

from actql_sdk._local_core import (
    LocalCoreError, _Output, _PUBLICATION_COMMIT_EXPORT_SIGNATURES,
)
import test_local_sdk_read_original as fixture
import test_local_sdk_payload_store as store_fixture
import test_local_reader_facts as file_fixture


class SDKPayloadRecordBindingTests(unittest.TestCase):
    def bridge(self):
        core, _, first, calls, status = fixture.SDKReadOriginalTests.bridge(self)
        record = _Output(core._identity, 5, 29, 65536, 'payload_record')
        core._loans[5] = record
        return core, first, record, calls, status

    def test_closed_source_record_signature_and_original_inventory_proposal(self):
        core, first, record, calls, _ = self.bridge()
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['bind_sdk_payload_record'],
                         ('i64 i32 i32 i32 i32 i32', 'i32'))
        core.bind_publication_sdk_payload_record(first, record, 23, 2, 2)
        self.assertEqual(calls, [('publication_commit_export', 'bind_sdk_payload_record',
                                 (19, 29, 23, 2, 2))])
        self.assertIs(core._loans[first.ticket], first)
        self.assertIs(core._loans[record.ticket], record)

    def test_copies_wrong_record_family_and_invalid_ordinals_refuse_before_core(self):
        core, first, record, calls, _ = self.bridge()
        for original, source, configuration, result, binding in (
            (copy.copy(first), record, 23, 0, 0),
            (first, copy.copy(record), 23, 0, 0),
            (first, first, 23, 0, 0),
            (first, record, True, 0, 0),
            (first, record, 23, True, 0),
            (first, record, 23, 0, -1),
        ):
            with self.assertRaises(ValueError):
                core.bind_publication_sdk_payload_record(original, source, configuration,
                                                        result, binding)
        self.assertEqual(calls, [])

    def test_source_refusal_unknown_current_denial_and_reentry_do_not_adopt_record(self):
        core, first, record, calls, status = self.bridge()
        for code in (-32, -33, -35, -5, -9, 1):
            status[0] = code
            with self.assertRaises(LocalCoreError) as error:
                core.bind_publication_sdk_payload_record(first, record, 23, 0, 0)
            self.assertEqual(error.exception.code, code)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[record.ticket], record)
        status[0] = False
        with self.assertRaisesRegex(RuntimeError, 'payload binding status'):
            core.bind_publication_sdk_payload_record(first, record, 23, 0, 0)
        def close_source(*_):
            del core._loans[record.ticket]
            return 0
        core._call = close_source
        with self.assertRaises(ValueError):
            core.bind_publication_sdk_payload_record(first, record, 23, 0, 0)


class SDKPayloadRecordStoreTests(unittest.TestCase):
    def test_actual_same_store_uses_exact_inventory_fact_and_preserves_denied_record_custody(self):
        files = file_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            helper = store_fixture.SDKPayloadStorePortTests()
            helper.addCleanup = self.addCleanup
            holder, store, core, request, first, _, clock, _, state = helper.bridge(
                root, files.transfer_ready(root, final))
            fact = holder._observation._facts[0]
            previous = core._call
            calls = []
            def call(family, name, *args):
                if name == 'bind_sdk_payload_record':
                    frame = core._journal_callbacks(holder._observation._binding._current.ticket).reader
                    self.assertIs(frame.owner, store)
                    self.assertTrue(store._connection.in_transaction)
                    self.assertIs(holder._payload_facts[request.ticket], fact)
                    calls.append(args)
                    return state['payload_status']
                return previous(family, name, *args)
            core._call = call
            changes = store._connection.total_changes
            with self.assertRaises(ValueError):
                holder.bind_original_payload(request, clock, copy.copy(fact))
            self.assertEqual(calls, [])
            state['payload_status'] = -32
            with self.assertRaises(LocalCoreError):
                holder.bind_original_payload(request, clock, fact)
            self.assertIs(holder._payload_facts[request.ticket], fact)
            state['payload_status'] = 0
            holder.bind_original_payload(request, clock, fact)
            self.assertEqual(calls, [(first.handle, fact._record.handle, 31, 0, 0)] * 2)
            self.assertEqual(store._connection.total_changes, changes)
            self.assertFalse(store._connection.in_transaction)
            self.assertTrue(holder.close_original_first(request))
            self.assertNotIn(request.ticket, holder._payload_facts)
            self.assertTrue(holder.close())
