"""Scalar ordinal routing; no Wasm or authority is provided by these tests."""
import copy
import unittest
from unittest.mock import patch

from actql_sdk._local_files import LocalFileError
from actql_sdk._local_core import LocalCoreError, _PUBLICATION_COMMIT_EXPORT_SIGNATURES
import test_local_sdk_read_original as fixture
import test_local_sdk_payload_store as storage_fixture
import test_local_reader_facts as files_fixture


class SDKPayloadSelectionTests(unittest.TestCase):
    def test_closed_signature_and_original_routing_fields(self):
        core, _, first, calls, status = fixture.SDKReadOriginalTests.bridge(self)
        self.assertEqual(_PUBLICATION_COMMIT_EXPORT_SIGNATURES['sdk_payload_ordinal'],
                         ('i64 i32 i32 i32', 'i32'))
        status[0] = 2
        self.assertEqual(core.publication_sdk_payload_ordinal(first, 23, field='result'), 2)
        status[0] = 5
        self.assertEqual(core.publication_sdk_payload_ordinal(first, 23, field='binding'), 5)
        self.assertEqual(calls, [('publication_commit_export', 'sdk_payload_ordinal', (19, 23, 0)),
                                ('publication_commit_export', 'sdk_payload_ordinal', (19, 23, 1))])
        for selected, config, field in ((copy.copy(first), 23, 'result'), (first, True, 'result'),
                                       (first, 23, 'name'), (first, 23, True)):
            with self.assertRaises(ValueError): core.publication_sdk_payload_ordinal(selected, config, field=field)
        self.assertEqual(len(calls), 2)

    def test_boolean_out_of_profile_and_closed_original_never_route_descriptor(self):
        core, _, first, _, status = fixture.SDKReadOriginalTests.bridge(self)
        for value in (True, False, None, 0.0, 8, 2**31):
            status[0] = value
            with self.assertRaises(RuntimeError): core.publication_sdk_payload_ordinal(first, 23, field='result')
        status[0] = -35
        with self.assertRaises(LocalCoreError) as error: core.publication_sdk_payload_ordinal(first, 23, field='result')
        self.assertEqual(error.exception.code, -35)
        def release(*_):
            del core._loans[first.ticket]
            return 0
        core._call = release
        with self.assertRaises(ValueError): core.publication_sdk_payload_ordinal(first, 23, field='result')

    def test_same_store_routes_only_complete_original_inventory_without_open_or_write(self):
        files = files_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            helper = storage_fixture.SDKPayloadStorePortTests()
            helper.addCleanup = self.addCleanup
            holder, store, core, request, first, _, clock, _, _ = helper.bridge(root, files.transfer_ready(root, final))
            previous = core._call
            fields = []
            selected = [0, 0]
            def call(family, name, *args):
                if name == 'sdk_payload_ordinal':
                    frame = core._journal_callbacks(holder._observation._binding._current.ticket).reader
                    self.assertIs(frame.owner, store)
                    self.assertTrue(store._connection.in_transaction)
                    self.assertEqual(args[:2], (first.handle, 31))
                    fields.append(args[2])
                    return selected[args[2]]
                return previous(family, name, *args)
            core._call = call
            changes = store._connection.total_changes
            self.assertIs(holder.selected_original_payload(request, clock), holder._observation._facts[0])
            self.assertEqual(fields, [0, 1])
            selected[1] = 1
            with self.assertRaises(ValueError): holder.selected_original_payload(request, clock)
            self.assertEqual(store._connection.total_changes, changes)
            self.assertFalse(holder._payload_facts)
            self.assertTrue(holder.close())


class AdjacentCodecSelectionTests(unittest.TestCase):
    def fixture(self, root, reader):
        helper = storage_fixture.SDKPayloadStorePortTests()
        helper.addCleanup = self.addCleanup
        holder, store, core, request, first, _, clock, _, state = helper.bridge(root, reader)
        base = core._call
        calls, readers = [], []
        state['ordinals'] = [0, 0]
        state['after_ordinal'] = lambda _: None
        def call(family, name, *args):
            if family == 'publication_commit_export' and name in ('prepare_sdk_payload_codecs', 'sdk_payload_ordinal'):
                frame = core._journal_callbacks(holder._observation._binding._current.ticket).reader
                self.assertIs(frame.owner, store)
                self.assertTrue(store._connection.in_transaction)
                self.assertIs(core._loans[first.ticket], first)
                self.assertIs(core._loans[clock.ticket], clock)
                readers.append(frame)
                calls.append((name, args))
                if name == 'sdk_payload_ordinal':
                    state['after_ordinal'](args[2])
                    return state['ordinals'][args[2]]
            return base(family, name, *args)
        core._call = call
        return holder, store, core, request, first, clock, state, calls, readers

    def test_original_codec_and_ordinals_share_one_existing_read_snapshot(self):
        files = files_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            holder, store, core, request, first, clock, _, calls, readers = self.fixture(
                root, files.transfer_ready(root, final))
            before = store._connection.total_changes
            with patch.object(holder, 'selected_original_payload', side_effect=AssertionError('A second read frame was opened')):
                selected = holder.prepare_original_payload(request, clock)
            self.assertIs(selected, holder._observation._facts[0])
            self.assertEqual([name for name, _ in calls],
                ['prepare_sdk_payload_codecs', 'sdk_payload_ordinal', 'sdk_payload_ordinal'])
            self.assertEqual([args[-1] for name, args in calls if name == 'sdk_payload_ordinal'], [0, 1])
            self.assertEqual(len(readers), 3)
            self.assertTrue(all(reader is readers[0] for reader in readers))
            self.assertFalse(store._connection.in_transaction)
            self.assertEqual(store._connection.total_changes, before)
            self.assertFalse(holder._payload_facts)
            self.assertIs(core._loans[first.ticket], first)
            self.assertTrue(holder.close())

    def test_changed_file_or_foreign_input_cannot_escape_the_final_original_fence(self):
        files = files_fixture.ReaderFactsTests()
        with files.file() as (path, root, _, final):
            holder, store, core, request, first, clock, state, calls, _ = self.fixture(
                root, files.transfer_ready(root, final))
            with self.assertRaises(ValueError):
                holder.prepare_original_payload(request, copy.copy(clock))
            self.assertEqual(calls, [])
            before = store._connection.total_changes
            def mutate(field):
                if field == 1:
                    original = path / 'payload-original'
                    body = original.read_bytes()
                    original.write_bytes(b'X' + body[1:])
            state['after_ordinal'] = mutate
            with self.assertRaises(LocalFileError):
                holder.prepare_original_payload(request, clock)
            self.assertFalse(holder._active)
            self.assertFalse(store._connection.in_transaction)
            self.assertEqual(store._connection.total_changes, before)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[clock.ticket], clock)
            self.assertFalse(holder._payload_facts)
            self.assertTrue(holder.close())

    def test_codec_refusal_and_foreign_ordinal_preserve_same_originals_without_payload_use(self):
        files = files_fixture.ReaderFactsTests()
        with files.file() as (_, root, _, final):
            holder, store, core, request, first, clock, state, calls, _ = self.fixture(
                root, files.transfer_ready(root, final))
            before = store._connection.total_changes
            state['codec_status'] = -35
            with self.assertRaises(LocalCoreError):
                holder.prepare_original_payload(request, clock)
            self.assertEqual([name for name, _ in calls], ['prepare_sdk_payload_codecs'])
            state['codec_status'] = 0
            state['ordinals'] = [0, 1]
            with self.assertRaises(ValueError):
                holder.prepare_original_payload(request, clock)
            self.assertFalse(holder._payload_facts)
            self.assertEqual(store._connection.total_changes, before)
            self.assertIs(core._loans[first.ticket], first)
            self.assertIs(core._loans[clock.ticket], clock)
            self.assertTrue(holder.close())
