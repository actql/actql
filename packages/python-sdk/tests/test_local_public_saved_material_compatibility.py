"""Existing public saved-material compatibility with File/SQLite and scalar Core.

No installed guest/runtime, permission, publication or ordinary speed acceptance.
"""
from contextlib import contextmanager
import os
import unittest
from unittest.mock import patch

from actql_sdk._local_commit_projection import OriginalCommitProjection
from actql_sdk._local_core import LocalCoreError, _Output
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_sdk_delivery_storage import OriginalSDKDeliveryStore
from actql_sdk._local_storage import ByteFence, CapacityReservation
from actql_sdk._local_store_reconciliation import OriginalStoreReconciliation
from actql_sdk._local_wasm_abi import LOCAL_CORE_ABI
import test_local_host_binding as host_fixture
import test_local_reader_facts as file_fixture
from local_abi_declaration_fixture import assert_current_local_abi


class PublicSavedMaterialCompatibilityTests(unittest.TestCase):
    @contextmanager
    def fixture(self):
        files = file_fixture.ReaderFactsTests()
        with files.file(slots=4) as (path, root, _, final):
            live = files.transfer_ready(root, final)
            expected = root.observe_completed_reader(live)
            reader = root.open_saved_payload(final.name, expected)
            while not reader.eof:
                chunk = root.read_original(reader)
                root.release_original_chunk(reader, chunk)
            helper = host_fixture.OriginalHostBindingTests()
            helper.addCleanup = self.addCleanup
            _, store, core, _, _, _, _, _, codes, _, binding = helper.fixture()
            core._retired = False
            state = dict(snapshot=0, full=0, bind=0, port=0, cleanup=True,
                         current=0, on_full=lambda: None, on_port=lambda: None,
                         on_bind=lambda: None)
            calls = []
            previous = core._call
            def call(family, name, *args):
                if family == 'publication_commit_export' and name == 'reserve':
                    return 200 + args[1]
                if ((family == 'publication_commit_export' and name in (
                        'validate_payload_binding', 'validate_reader_facts',
                        'bind_sdk_payload_record', 'prepare_sdk_payload_input',
                        'produce_sdk_payload_chunk', 'observe_sdk_terminal'))
                        or (family == 'payload_record' and name == 'validate_snapshot')):
                    frame = core._journal_callbacks(binding._current.ticket).reader
                    self.assertIs(frame.owner, store)
                    self.assertTrue(store._connection.in_transaction)
                    calls.append(name)
                    if name in ('validate_reader_facts', 'validate_snapshot'):
                        state['on_full']()
                        return state['snapshot'] if name == 'validate_snapshot' else state['full']
                    if name == 'bind_sdk_payload_record':
                        state['on_bind']()
                        return state['bind']
                    if name in ('prepare_sdk_payload_input', 'produce_sdk_payload_chunk',
                                'observe_sdk_terminal'):
                        state['on_port']()
                        return state['port']
                    return 0
                return previous(family, name, *args)
            core._call = call
            def output(handle, family):
                value = _Output(core._identity, core._next_ticket, handle, 65536, family)
                core._next_ticket += 1
                core._loans[value.ticket] = value
                return value
            # Explicit scalar fixture originals, not a relabelled live capture.
            parent = output(4001, 'submission_lookup')
            record = output(4003, 'payload_record')
            projection = OriginalCommitProjection.from_saved_read(
                core, parent, 31, cleanup=lambda: state['cleanup'])
            fact = OriginalReaderFacts(projection, record, root, reader, 0, 0,
                'sha256:' + '1' * 64, 'sha256:' + '3' * 64,
                cleanup=lambda: state['cleanup'], stopped=lambda _: True)
            key = store.namespaced_key('payload_record', 'original')
            store.compare_exchange(key, None, b'original-sealed')
            self.assertTrue(store.reserve_capacity('publication_payload', key, 64, 1, 128, 2))
            originals = ((ByteFence(key, 0, b'original-sealed'),
                          CapacityReservation('publication_payload', key, 64, 1)),)
            def current():
                state['current'] += 1
            observation = OriginalStoreReconciliation.from_saved_read(
                projection, (fact,), store, originals, binding, current=current)
            holder = OriginalSDKDeliveryStore(observation, cleanup=lambda: state['cleanup'])
            request = core.reserve_input(b'original-request', cleanup=lambda: True, stopped=lambda _: True)
            clock = core.reserve_input(b'original-clock', cleanup=lambda: True, stopped=lambda _: True)
            chunk = core.reserve_input(files.body, cleanup=lambda: True, stopped=lambda _: True)
            # The existing reserve port supplies the actual nominal first loan.
            # This component installs its typed completion; it does not issue a grant.
            first = core.reserve_saved_result_export(parent, cleanup=lambda: state['cleanup'])
            holder._first_outputs[request.ticket] = first
            try:
                yield (holder, observation, fact, store, core, request, first, clock,
                       chunk, state, calls, reader, path, codes)
            finally:
                state['cleanup'] = True
                state['on_full'] = state['on_port'] = lambda: None
                self.assertTrue(holder.close())
                self.assertFalse(holder._payload_binding_originals)
                for value in (chunk, clock, request):
                    self.assertTrue(core.close_input(value))
                self.assertTrue(fact.close())
                self.assertTrue(root.close_original(reader))

    def test_public_two_validator_order_and_failed_second_call_keep_same_input(self):
        with self.fixture() as (holder, observation, fact, _, core, request, _, clock,
                                _, state, calls, _, _, _):
            assert_current_local_abi(self, LOCAL_CORE_ABI)
            self.assertFalse(hasattr(core, 'validate_payload_reader_facts'))
            state['snapshot'] = -32
            for _ in range(2):
                before = len(calls)
                with self.assertRaises(LocalCoreError) as issue:
                    with observation._serialized_facts():
                        observation._current_call(fact.validate)
                self.assertEqual(issue.exception.operation, 'validate_payload_snapshot')
                self.assertEqual(calls[before:], ['validate_payload_binding', 'validate_snapshot'])
                self.assertIsNone(fact._original_material)
                self.assertNotIn(request.ticket, holder._payload_binding_originals)
            original = fact.pending_input
            self.assertTrue(fact._sealed)
            state['snapshot'] = 0
            holder.bind_original_payload(request, clock, fact)
            self.assertIs(fact.pending_input, original)
            self.assertIsNotNone(fact._original_material)
            self.assertIn(request.ticket, holder._payload_binding_originals)

    def test_public_second_post_bind_validator_failure_is_cleanup_only(self):
        with self.fixture() as (holder, _, fact, _, core, request, first, clock,
                                _, state, calls, _, _, _):
            state['on_bind'] = lambda: state.update(snapshot=-32)
            with self.assertRaises(LocalCoreError):
                holder.bind_original_payload(request, clock, fact)
            self.assertEqual(calls, ['validate_payload_binding', 'validate_snapshot',
                'bind_sdk_payload_record', 'validate_payload_binding', 'validate_snapshot'])
            self.assertIs(holder._payload_facts[request.ticket], fact)
            self.assertIsNone(fact._original_material)
            self.assertNotIn(request.ticket, holder._payload_binding_originals)
            self.assertIs(core._loans[first.ticket], first)
            original = fact.pending_input
            state['on_bind'] = lambda: None
            state['snapshot'] = 0
            holder.prepare_original_input(request, clock)
            self.assertEqual(calls.count('validate_snapshot'), 4)
            self.assertNotIn(request.ticket, holder._payload_binding_originals)
            self.assertIs(fact.pending_input, original)

    def test_public_final_current_failure_discards_material_and_binding_success(self):
        with self.fixture() as (holder, observation, fact, _, core, request, first, clock,
                                _, state, _, _, _, _):
            binding = observation._binding
            # Mutate only at the original final current fence, after both
            # validators and the scalar bind have otherwise succeeded.
            original = binding._core.validate_host_current
            def failed_final(value):
                original(value)
                raise LocalCoreError('public_final_current', -35)
            with patch.object(core, 'validate_host_current', side_effect=failed_final):
                with self.assertRaises(LocalCoreError):
                    holder.bind_original_payload(request, clock, fact)
            self.assertIsNone(fact._original_material)
            self.assertNotIn(request.ticket, holder._payload_binding_originals)
            self.assertIs(holder._payload_facts[request.ticket], fact)
            self.assertIs(holder.original_first_output(request), first)
            self.assertIsNotNone(fact.pending_input)

    def test_public_bound_byte_ports_keep_frames_current_and_physical_observations(self):
        with self.fixture() as (holder, observation, fact, store, core, request, first,
                                clock, chunk, state, calls, _, _, _):
            holder.bind_original_payload(request, clock, fact)
            before = len(calls)
            changes = store._connection.total_changes
            observe = fact._root.observe_original
            physical_current = observation._binding._physical_current
            with patch.object(fact._root, 'observe_original', wraps=observe) as physical, patch.object(
                    observation._binding, '_physical_current', wraps=physical_current) as current:
                holder.prepare_original_input(request, clock)
                output = holder.produce_original_chunk(request, chunk, clock, eof=True)
                with patch.object(core, 'read_publication_commit_material', return_value=b'original'):
                    self.assertEqual(holder.read_original_chunk(
                        request, chunk, clock, output, eof=True), b'original')
                holder.observe_original_terminal(request, clock)
                self.assertEqual(physical.call_count, 12)
                self.assertGreaterEqual(current.call_count, 4)
            self.assertEqual(calls[before:], ['prepare_sdk_payload_input', 'produce_sdk_payload_chunk',
                                           'produce_sdk_payload_chunk', 'observe_sdk_terminal'])
            state['port'] = -35
            with self.assertRaises(LocalCoreError):
                holder.prepare_original_input(request, clock)
            self.assertIsNone(fact._original_material)
            self.assertIs(holder.original_first_output(request), first)
            self.assertEqual(store._connection.total_changes, changes)
            self.assertFalse(store._connection.in_transaction)

    def test_bound_material_keeps_original_full_file_current_refusal(self):
        with self.fixture() as (holder, _, fact, _, _, request, first, clock,
                                _, _, calls, _, _, _):
            holder.bind_original_payload(request, clock, fact)
            before = len(calls)
            selected = holder._observation._binding._selected[0]
            root = holder._observation._binding._source._root
            descriptor = os.open(selected.name, os.O_WRONLY | os.O_TRUNC,
                                 dir_fd=root._open())
            try:
                os.write(descriptor, b'changed')
            finally:
                os.close(descriptor)
            with self.assertRaises(LocalFileError):
                holder.prepare_original_input(request, clock)
            self.assertEqual(calls[before:], [])
            self.assertIsNone(fact._original_material)
            self.assertIs(holder.original_first_output(request), first)


    def test_saved_lookup_reuses_original_material_and_keeps_current_before_action(self):
        with self.fixture() as (holder, observation, fact, _, core, request, first,
                                clock, _, state, calls, _, _, _):
            holder.bind_original_payload(request, clock, fact)
            original_input = fact.pending_input
            self.assertIsNotNone(original_input)
            before = len(calls)
            current_before = state['current']
            physical = fact._root.observe_original
            with observation._serialized_facts(), patch.object(
                    fact._root, 'observe_original', wraps=physical) as observed:
                observation._current_call(observation._before_lookup)
                self.assertGreater(observed.call_count, 0)
            self.assertEqual(calls[before:], [])
            self.assertEqual(state['current'] - current_before, 2)
            self.assertIs(fact.pending_input, original_input)
            self.assertIs(holder.original_first_output(request), first)
            self.assertIs(core._loans[original_input.ticket], original_input)


if __name__ == '__main__':
    unittest.main()
