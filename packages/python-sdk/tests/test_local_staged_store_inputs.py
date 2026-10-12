"""Original raw-row input custody with mocked Core and actual SQLite callers."""
import copy
import unittest

from actql_sdk._local_core import LocalCoreError
import test_local_observation_transfer as transfer_fixture


class StagedStoreInputTests(unittest.TestCase):
    bridge = transfer_fixture.ObservationTransferTests.bridge
    index, request, attempt = transfer_fixture.ObservationTransferTests.index, transfer_fixture.ObservationTransferTests.request, transfer_fixture.ObservationTransferTests.attempt
    reference = transfer_fixture.ObservationTransferTests.reference

    def test_raw_rows_are_nominal_sealed_inputs_before_aggregate_original_packet(self):
        core, parent, _, transfer, calls, state, packets = self.bridge()
        transfer.reserve()
        request = transfer.retain_source(self.request)
        attempt = transfer.retain_source(self.attempt)
        index = transfer.retain_source(self.index)
        self.assertEqual(transfer.pending_sources, (request, attempt, index))
        self.assertTrue(all(core._loans[v.ticket] is v for v in transfer.pending_sources))
        self.assertEqual([name for _, name, _ in calls], ['reserve'] + ['reserve', 'fill', 'seal'] * 3)
        transfer.transfer_stored_inputs(request, attempt, index)
        observed = transfer.pending_input
        self.assertIs(core._loans[observed.ticket], observed)
        self.assertEqual(len(packets), 1)
        self.assertFalse(transfer.close())
        self.assertEqual(transfer.pending_sources, (request, attempt, index))
        state['borrow'] = False
        state['cleanup_input'] = False
        self.assertFalse(transfer.close())
        self.assertIs(transfer.pending_input, observed)
        self.assertEqual(transfer.pending_sources, (request, attempt, index))
        state['cleanup_input'] = True
        self.assertTrue(transfer.close())
        self.assertEqual(transfer.pending_sources, ())
        self.assertIs(core._loans[7], parent)
        closes = [args[0] for family, name, args in calls if family == 'buffer' and name == 'close']
        self.assertEqual(closes[-4:], [observed.handle, index.handle, attempt.handle, request.handle])

    def test_cross_transfer_borrow_copies_only_to_another_original_input_without_store_refetch(self):
        core, _, publisher, first, calls, state, _ = self.bridge()
        first.reserve()
        reference = first.retain_source(self.reference)
        index = first.retain_source(self.index)
        first.transfer_lookup_inputs(reference, index)
        from actql_sdk._local_observation_transfer import OriginalObservationTransfer
        second = OriginalObservationTransfer(
            first._projection, publisher, max_source_bytes=1024, max_packet_bytes=2048,
            cleanup=lambda: state['cleanup_input'], stopped=lambda _: not state['borrow'],
            workspace_cleanup=lambda: state['cleanup_workspace'], workspace_stopped=lambda: True)
        second.reserve()
        handles = []
        first.consume_source(index, lambda raw: handles.append(second.retain_source(raw)))
        self.assertEqual(len(handles), 1)
        self.assertIs(core._inputs[handles[0].ticket].payload, core._inputs[index.ticket].payload)
        self.assertIs(core._loans[index.ticket], index)
        self.assertIs(core._loans[handles[0].ticket], handles[0])
        self.assertFalse(any(name in ('retire_lookup', 'finish_commit', 'finish_observation') for _, name, _ in calls))
        state['borrow'] = False
        self.assertTrue(second.close())
        self.assertTrue(first.close())

    def test_copied_other_transfer_and_foreign_source_loans_refuse_before_aggregate_io(self):
        core, _, publisher, transfer, calls, state, _ = self.bridge()
        transfer.reserve()
        source = transfer.retain_source(self.index)
        from actql_sdk._local_observation_transfer import OriginalObservationTransfer
        other = OriginalObservationTransfer(
            transfer._projection, publisher, max_source_bytes=1024, max_packet_bytes=2048,
            cleanup=lambda: True, stopped=lambda _: True,
            workspace_cleanup=lambda: True, workspace_stopped=lambda: True)
        other.reserve()
        other_source = other.retain_source(self.request)
        foreign, _, _, foreign_transfer, _, _, _ = self.bridge()
        foreign_transfer.reserve()
        foreign_source = foreign_transfer.retain_source(self.attempt)
        before = len(calls)
        for value in (copy.copy(source), other_source, foreign_source, core._loans[7]):
            with self.assertRaises(ValueError):
                transfer.transfer_lookup_inputs(source, value)
            with self.assertRaises(ValueError):
                transfer.consume_source(value, lambda _: self.fail('Foreign input reached consumer'))
        self.assertEqual(len(calls), before)
        self.assertTrue(other.close())
        self.assertTrue(transfer.close())
        self.assertTrue(foreign_transfer.close())

    def test_zero_length_row_count_and_cumulative_raw_bytes_are_bounded_before_reservation(self):
        for source_limit, raws in ((1, [b'', b'', b'']), (3, [b'a', b'bc'])):
            with self.subTest(source_limit=source_limit):
                _, _, _, transfer, calls, _, _ = self.bridge(source=source_limit)
                transfer.reserve()
                for raw in raws:
                    transfer.retain_source(raw)
                before = len(calls)
                with self.assertRaises(ValueError):
                    transfer.retain_source(b'' if source_limit == 1 else b'x')
                self.assertEqual(len(calls), before)
                self.assertEqual(len(transfer.pending_sources), len(raws))
                self.assertTrue(transfer.close())

    def test_raw_fill_and_uncertain_reserve_keep_prior_inputs_until_same_owner_cleanup(self):
        for outcome in ('fill', 'trap'):
            with self.subTest(outcome=outcome):
                core, parent, _, transfer, calls, state, _ = self.bridge()
                transfer.reserve()
                original = transfer.retain_source(self.request)
                if outcome == 'fill':
                    state['fill'] = -4
                else:
                    state['trap'] = 'buffer'
                with self.assertRaises(LocalCoreError if outcome == 'fill' else OSError):
                    transfer.retain_source(self.attempt)
                self.assertIs(transfer.pending_sources[0], original)
                before = len(calls)
                with self.assertRaises(RuntimeError):
                    transfer.transfer_query_failure()
                self.assertEqual(len(calls), before)
                if outcome == 'fill':
                    state['cleanup_input'] = False
                    self.assertFalse(transfer.close())
                    self.assertEqual(len(transfer.pending_sources), 2)
                    state['cleanup_input'] = True
                    self.assertTrue(transfer.close())
                else:
                    ticket = transfer.uncertain_acquisition_ticket
                    self.assertFalse(transfer.close())
                    self.assertIn(ticket, core._inputs)
                    self.assertIs(core._loans[original.ticket], original)
                self.assertIs(core._loans[7], parent)

    def test_failed_raw_consumer_keeps_same_input_and_blocks_replacement_projection(self):
        for outcome in ('bool', 'exception', 'reentrant'):
            with self.subTest(outcome=outcome):
                _, _, _, transfer, calls, _, _ = self.bridge()
                transfer.reserve()
                original = transfer.retain_source(self.index)
                def consume(raw):
                    self.assertIs(raw, self.index)
                    if outcome == 'exception':
                        raise OSError('Original raw transfer pending')
                    if outcome == 'reentrant':
                        transfer.close()
                    return True
                with self.assertRaises(OSError if outcome == 'exception' else
                                       RuntimeError if outcome == 'reentrant' else ValueError):
                    transfer.consume_source(original, consume)
                self.assertEqual(transfer.pending_sources, (original,))
                before = len(calls)
                with self.assertRaises(RuntimeError):
                    transfer.retain_source(self.attempt)
                self.assertEqual(len(calls), before)
                self.assertTrue(transfer.close())


if __name__ == '__main__':
    unittest.main()
