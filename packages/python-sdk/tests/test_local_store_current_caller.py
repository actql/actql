"""Actual File/SQLite/binding composition; scalar Core, not Wasm/Account proof."""
import unittest

from actql_sdk._local_commit_projection import OriginalCommitProjection
from actql_sdk._local_core import LocalCoreError, _Output
from actql_sdk._local_observation_transfer import OriginalObservationTransfer
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_storage import ByteFence, CapacityReservation, StoredBytes
from actql_sdk._local_store_reconciliation import OriginalStoreReconciliation
import test_local_host_binding as binding_fixture
import test_local_reader_facts as file_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class StoreCurrentCallerTests(unittest.TestCase):
    def fixture(self, root, reader):
        _, store, core, _, _, _, _, _, codes, _, binding = binding_fixture.OriginalHostBindingTests.fixture(self)
        core._retired = False
        pub = _Output(core._identity, core._next_ticket, 4001, 1048576, 'publication')
        core._next_ticket += 1
        publisher = _Output(core._identity, core._next_ticket, 4002, 8192, 'publisher')
        core._next_ticket += 1
        record = _Output(core._identity, core._next_ticket, 4003, 65536, 'payload_record')
        core._next_ticket += 1
        for value in (pub, publisher, record): core._loans[value.ticket] = value
        projection = OriginalCommitProjection(core, pub, 31, cleanup=lambda: True)
        facts = OriginalReaderFacts(projection, record, root, reader, 0, 0,
            'sha256:' + '1' * 64, 'sha256:' + '3' * 64, cleanup=lambda: True, stopped=lambda _: True)
        refs = [b'sha256:' + c * 64 for c in (b'e', b'f', b'9')]
        raw = [b'{"actual":"stored-old-index"}', b'{"request":"original e\xcc\x81"}', b'{"attempt":"older"}']
        scope = store.namespaced_key('public_index', 'd' * 64)
        for key, body in [(scope, refs[0])] + [
                (store.namespaced_key('publication_contract', ref.decode()), body)
                for ref, body in zip(refs, raw)]: store.compare_exchange(key, None, body)
        sealed = store.namespaced_key('payload_record', 'original')
        store.compare_exchange(sealed, None, b'original-sealed')
        store.reserve_capacity('publication_payload', sealed, 64, 1, 128, 2)
        originals = ((ByteFence(sealed, 0, b'original-sealed'),
                      CapacityReservation('publication_payload', sealed, 64, 1)),)
        before = core._call
        frames, packets = [], []
        def call(family, name, *args):
            if family == 'publication_commit_export' and name == 'result_count': return 1
            if family in ('publication', 'publisher', 'payload_record', 'publication_commit_export'):
                frame = core._journal_callbacks(binding._current.ticket).reader
                self.assertIsNotNone(frame, (family, name))
                self.assertIs(frame.owner, store)
                frames.append((name, frame))
                if family == 'publication_commit_export':
                    if name == 'reserve': return 200 + args[1]
                    if name == 'produce_index_key': body = b'd' * 64
                    elif name == 'produce_lookup_reference': body = refs[1 + args[2]]
                    elif name in ('length', 'close'):
                        return (len(core._inputs[args[0] - 200].payload) if name == 'length'
                                else before('buffer', 'close', args[0]))
                    else: return 0
                    core._inputs[args[0] - 200].payload = body
                    return 0
                if family == 'publication':
                    if name in ('prepare_lookup', 'prepare_observation'):
                        packets.append(core._inputs[args[1] - 200].payload)
                    if name == 'observation_progress': return (1, 1)[args[1]]
                    if name == 'finish_observation': return 4
                return 0
            if family == 'buffer':
                if name in ('fill', 'seal'): return 0
                if name == 'byte': return core._inputs[args[0] - 200].payload[args[1]]
            return before(family, name, *args)
        core._call = original_byte_fixture_port(call)
        transfers = [OriginalObservationTransfer(projection, publisher,
            max_source_bytes=512, max_packet_bytes=512, cleanup=lambda: True,
            stopped=lambda _: True, workspace_cleanup=lambda: True, workspace_stopped=lambda: True)
            for _ in range(2)]
        for transfer in transfers: transfer.reserve()
        caller = OriginalStoreReconciliation(projection, (facts,), store, originals, publisher, *transfers)
        return store, core, binding, codes, caller, frames, packets, originals, transfers, scope

    def test_same_original_binding_survives_lookup_and_is_fresh_for_advance_finish(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            store, core, binding, _, caller, frames, packets, originals, _, scope = self.fixture(root, reader)
            changes = store._connection.total_changes
            caller.prepare(binding=binding)
            lookup_frames = {id(frame) for _, frame in frames}
            self.assertEqual(len(lookup_frames), 1)
            self.assertIn(b'stored-old-index', packets[0])
            self.assertIn(b'older', packets[1])
            self.assertEqual(caller.advance(16).work, 1)
            self.assertEqual(caller.finish(), 'adopt_committed_index')
            later = [frame for name, frame in frames if name in ('advance_observation', 'finish_observation')]
            self.assertEqual(len(later), 2)
            self.assertTrue(all(id(frame) not in lookup_frames for frame in later))
            self.assertIsNot(later[0], later[1])
            self.assertEqual(store._connection.total_changes, changes)
            self.assertEqual(store.read(scope), StoredBytes(0, b'sha256:' + b'e' * 64))
            self.assertEqual(store.read_capacity(originals[0][1].namespace, originals[0][1].key), originals[0][1])
            self.assertIsNone(core._journal_callbacks(binding._current.ticket).reader)

    def test_current_revocation_before_finish_preserves_same_transfers_without_new_lookup(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            store, _, binding, codes, caller, frames, packets, _, transfers, _ = self.fixture(root, reader)
            caller.prepare(binding=binding)
            loans = [(transfer.pending_input, transfer.pending_sources) for transfer in transfers]
            codes['current', 'bind'] = -32
            before = len(frames)
            with self.assertRaises(LocalCoreError): caller.finish()
            self.assertEqual(len(packets), 2)
            self.assertFalse(any(name == 'finish_observation' for name, _ in frames[before:]))
            self.assertEqual([(transfer.pending_input, transfer.pending_sources) for transfer in transfers], loans)
            self.assertFalse(store._connection.in_transaction)

    def test_foreign_binding_refuses_before_query_or_marking_attempt_entered(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final):
            reader = helper.transfer_ready(root, final)
            store, _, binding, _, caller, frames, packets, _, _, _ = self.fixture(root, reader)
            _, _, _, _, _, _, _, _, _, _, foreign = binding_fixture.OriginalHostBindingTests.fixture(self)
            with self.assertRaises(ValueError): caller.prepare(binding=foreign)
            self.assertFalse(caller._entered)
            self.assertEqual((frames, packets), ([], []))
            self.assertFalse(store._connection.in_transaction)
            caller.prepare(binding=binding)
            self.assertEqual(len(packets), 2)


if __name__ == '__main__':
    unittest.main()
