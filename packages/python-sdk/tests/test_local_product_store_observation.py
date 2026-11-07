"""Original Host pipeline into actual same-Store lookup; scalar Core only."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_storage import LocalStorageError
import test_local_product_commit_candidate as candidate_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


INDEX_CID = b'sha256:' + b'e' * 64
REQUEST_CID = b'sha256:' + b'f' * 64
ATTEMPT_CID = b'sha256:' + b'9' * 64
STORED_INDEX = b'{"actual":"older stored index e\xcc\x81/~"}'
STORED_REQUEST = b'{"actual":"original request"}'
STORED_ATTEMPT = b'{"actual":"older attempt"}'


class ProductStoreObservationTests(unittest.TestCase):
    def host(self, path, *, stored):
        fixture = candidate_fixture.ProductCommitCandidateTests()
        self.addCleanup(fixture.doCleanups)
        host, core, held, preflight, calls, _, _, _ = fixture.host(path)
        host._prepare_original_commit_candidate(held.publication, preflight)
        self.assertIsNone(host._advance_original_commit_candidate(held.publication))
        projection = host._advance_original_commit_candidate(held.publication)
        store = host._installation._store
        scope = store.namespaced_key('public_index', 'd' * 64)
        if stored:
            for key, body in [(scope, INDEX_CID), *[(store.namespaced_key('publication_contract', cid.decode()), body)
                    for cid, body in [(INDEX_CID, STORED_INDEX), (REQUEST_CID, STORED_REQUEST), (ATTEMPT_CID, STORED_ATTEMPT)]]]:
                self.assertIsNotNone(store.compare_exchange(key, None, body))
        previous = core._call
        outputs, packets, faults = {}, [], {}
        def input_bytes(handle):
            source = next(value for value in core._loans.values() if value.handle == handle)
            return core._inputs[source.ticket].payload
        def call(family, name, *args):
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][1][args[1]]
            if family == 'payload_record' and name == 'validate_snapshot':
                actual = json.loads(input_bytes(args[1]))
                self.assertEqual(actual['material_generation_cid'], held.generation)
                self.assertEqual(actual['physical_digest'], held.finalization.result.physical_digest)
                return 0
            if family == 'publication_commit_export':
                calls.append((family, name, args))
                if name == 'result_count': return 1
                if name == 'count': return 8
                if name == 'reserve':
                    handle = 100 + args[1]
                    outputs[handle] = (args[1], b'')
                    return handle
                if name == 'produce_index_key':
                    outputs[args[0]] = (outputs[args[0]][0], b'd' * 64)
                    return 0
                if name == 'produce_lookup_reference':
                    outputs[args[0]] = (outputs[args[0]][0], REQUEST_CID if args[2] == 0 else ATTEMPT_CID)
                    return 0
                if name == 'produce_observed_index':
                    # Explicit original Core export port, not an action-code
                    # substitute for the complete stored-index validation.
                    if 'produce_observed_index' in faults:
                        return faults['produce_observed_index']
                    if not stored or faults.get('finish_observation', 4) != 4:
                        return -32
                    outputs[args[0]] = (outputs[args[0]][0],
                        INDEX_CID if args[2] == 3 else STORED_INDEX)
                    return 0
                if name == 'length': return len(outputs[args[0]][1])
                if name == 'close': return core._cleanup(outputs.pop(args[0])[0])
                if name == 'validate_payload_binding':
                    self.assertEqual(args[1], held.record.handle)
                    self.assertEqual(args[3:], (0, 0))
                    return 0
            if family == 'publication' and name in ('prepare_lookup', 'prepare_observation',
                    'advance_observation', 'observation_progress', 'finish_observation', 'retire_observation', 'retire_lookup'):
                calls.append((family, name, args))
                if name in faults: return faults[name]
                if name in ('prepare_lookup', 'prepare_observation'):
                    packets.append((name, json.loads(input_bytes(args[1]))))
                if name == 'observation_progress': return 1
                if name == 'finish_observation': return 4 if stored else 3
                return 0
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return host, core, held, projection, store, scope, packets, faults, calls

    def test_confirmed_same_key_not_found_returns_only_owner_action_without_write_or_replay(self):
        with TemporaryDirectory(prefix='actql-store-observation-') as directory:
            host, _, held, projection, store, scope, packets, _, calls = self.host(Path(directory), stored=False)
            sql = []
            store._connection.set_trace_callback(sql.append)
            before = len(calls)
            host._prepare_original_store_observation(projection, host._publishers[0])
            self.assertEqual(packets, [('prepare_observation', {'kind': 'not_found'})])
            self.assertEqual(host._advance_original_store_observation(projection), 'confirm_uncommitted_failure')
            self.assertIsNone(store.read(scope))
            self.assertFalse(any(statement.startswith(('INSERT', 'UPDATE', 'DELETE')) for statement in sql))
            self.assertFalse(any(f in ('source', 'task') for f, _, _ in calls[before:]))
            self.assertFalse(host._publication_write_attempts)
            self.assertIsNotNone(held.reader.descriptor)
            self.assertTrue(host.close())

    def test_lookup_uses_actual_saved_older_index_and_contracts_never_candidate_or_new_attempt(self):
        with TemporaryDirectory(prefix='actql-store-observation-') as directory:
            host, core, held, projection, store, scope, packets, _, _ = self.host(Path(directory), stored=True)
            host._prepare_original_store_observation(projection, host._publishers[0])
            observation = host._store_observations[held.publication.ticket]
            self.assertEqual(packets, [('prepare_lookup', {'identity': INDEX_CID.decode(), 'index': STORED_INDEX.decode()}),
                ('prepare_observation', {'kind': 'stored', 'request': STORED_REQUEST.decode(),
                    'attempt': STORED_ATTEMPT.decode(), 'index': STORED_INDEX.decode()})])
            self.assertEqual(host._advance_original_store_observation(projection), 'adopt_committed_index')
            self.assertIs(host._store_observations[held.publication.ticket], observation)
            self.assertEqual(store.read(scope).payload, INDEX_CID)
            self.assertIs(core._loans[held.record.ticket], held.record)
            with self.assertRaises(LocalStorageError):
                host._prepare_original_store_observation(projection, host._publishers[0])
            self.assertFalse(host._publication_write_attempts)
            self.assertTrue(host.close())

    def test_bounded_observation_quantum_retains_owner_until_core_is_ready(self):
        with TemporaryDirectory(prefix='actql-store-observation-') as directory:
            host, core, held, projection, _, _, _, faults, calls = self.host(Path(directory), stored=True)
            host._prepare_original_store_observation(projection, host._publishers[0])
            original = host._store_observations[held.publication.ticket]
            previous = core._call
            remaining = 513
            used = 0
            def advance(family, name, *args):
                nonlocal remaining, used
                if (family, name) == ('publication', 'advance_observation'):
                    self.assertEqual(args, (held.publication.handle, host._configuration.handle, 256))
                    used = min(remaining, args[-1])
                    remaining -= used
                    return 0
                if (family, name) == ('publication', 'observation_progress'):
                    return int(remaining == 0) if args[-1] == 0 else used
                return previous(family, name, *args)
            core._call = advance
            for _ in range(2):
                self.assertIsNone(host._advance_original_store_observation(projection))
                self.assertIs(host._store_observations[held.publication.ticket], original)
                self.assertFalse(any(name == 'finish_observation' for _, name, _ in calls))
            self.assertEqual(host._advance_original_store_observation(projection), 'adopt_committed_index')
            self.assertEqual(remaining, 0)
            self.assertIs(host._store_observations[held.publication.ticket], original)
            self.assertTrue(host.close())

    def test_observation_borrow_cleanup_failure_keeps_original_transfers_reader_and_capacity(self):
        with TemporaryDirectory(prefix='actql-store-observation-') as directory:
            host, core, held, projection, _, _, _, faults, _ = self.host(Path(directory), stored=True)
            host._prepare_original_store_observation(projection, host._publishers[0])
            observation = host._store_observations[held.publication.ticket]
            transfers, reader, capacity = tuple(host._observation_transfers), held.reader, held.capacity
            faults['retire_observation'] = -9
            self.assertFalse(host.close())
            self.assertIs(host._store_observations[held.publication.ticket], observation)
            self.assertEqual(tuple(host._observation_transfers), transfers)
            self.assertIs(held.reader, reader)
            self.assertIs(held.capacity, capacity)
            self.assertTrue(all(transfer.pending_input is not None for transfer in transfers))
            self.assertIs(core._loans[held.record.ticket], held.record)
            faults.clear()
            with patch.object(host._installation._store, 'inspect_publication_projected_inspected',
                    side_effect=AssertionError('Cleanup repeated lookup')):
                self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
