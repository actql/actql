"""Explicit original-status lookup: real Store/File, stub Core, no public E2E."""
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_storage import ByteWrite, LocalStorageCommitUnknown, LocalStorageError
import test_local_product_store_observation as original_fixture


class ProductPublicationLookupTests(unittest.TestCase):
    def host(self, path, *, stored):
        fixture = original_fixture.ProductStoreObservationTests()
        self.addCleanup(fixture.doCleanups)
        host, core, held, projection, store, scope, packets, faults, calls = fixture.host(path, stored=stored)
        # Simulate only the retained original physical-attempt routing fact.
        # Actual COMMIT-loss behavior is covered by ProductCommitStoreTests;
        # a routing alias here cannot create a Core index or grant.
        host._pending_publication_write = projection
        host._pending_publication_publisher = host._publishers[0]
        host._publication_write_attempts.add(held.publication.ticket)
        return host, core, held, projection, store, scope, packets, faults, calls

    def test_complete_original_index_retires_only_the_host_attempt_blocker(self):
        with TemporaryDirectory() as directory:
            host, core, held, projection, store, _, _, _, calls = self.host(Path(directory), stored=True)
            publisher = host._pending_publication_publisher
            sql = []
            store._connection.set_trace_callback(sql.append)
            host._ensure_original_publication_observation(projection)
            self.assertIsNone(host._pending_publication_write)
            self.assertIsNone(host._pending_publication_publisher)
            observation = host._store_observations[held.publication.ticket]
            self.assertIs(observation._projection, projection)
            self.assertIs(observation._publisher, publisher)
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertIn(held.publication.ticket, host._publication_write_attempts)
            self.assertIn(projection, host._commit_projections)
            self.assertIn(publisher, host._publishers)
            self.assertEqual(sum(name == 'produce_observed_index' for _, name, _ in calls), 2)
            self.assertFalse(any(statement.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT')) for statement in sql))
            facts = host._original_commit_reader_facts(projection)
            before = list(sql)
            with self.assertRaises(LocalStorageError):
                host._store_original_commit(projection, facts, ((held.row, held.capacity),), publisher)
            self.assertEqual(sql, before)
            self.assertTrue(host.close())

    def test_index_export_refusal_keeps_exact_pending_attempt_and_original_loans(self):
        with TemporaryDirectory() as directory:
            host, core, held, projection, _, _, _, faults, calls = self.host(Path(directory), stored=True)
            publisher = host._pending_publication_publisher
            faults['produce_observed_index'] = -35
            with self.assertRaises(LocalCoreError) as failed:
                host._ensure_original_publication_observation(projection)
            self.assertEqual(failed.exception.code, -35)
            self.assertIs(host._pending_publication_write, projection)
            self.assertIs(host._pending_publication_publisher, publisher)
            observation = host._store_observations[held.publication.ticket]
            self.assertIs(observation._publisher, publisher)
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertIn(held.publication.ticket, host._publication_write_attempts)
            self.assertEqual(sum(name == 'produce_observed_index' for _, name, _ in calls), 1)
            self.assertTrue(host.close())

    def test_unknown_action_does_not_retire_pending_attempt_or_export_an_index(self):
        with TemporaryDirectory() as directory:
            host, _, held, projection, _, _, _, faults, calls = self.host(Path(directory), stored=True)
            publisher = host._pending_publication_publisher
            faults['finish_observation'] = 1
            host._ensure_original_publication_observation(projection)
            self.assertIs(host._pending_publication_write, projection)
            self.assertIs(host._pending_publication_publisher, publisher)
            self.assertIn(held.publication.ticket, host._publication_write_attempts)
            self.assertFalse(any(name == 'produce_observed_index' for _, name, _ in calls))
            self.assertTrue(host.close())

    def test_same_pending_write_looks_up_actual_older_index_once_without_replay_or_ack(self):
        with TemporaryDirectory() as directory:
            host, core, held, projection, store, scope, packets, _, calls = self.host(Path(directory), stored=True)
            sql = []
            store._connection.set_trace_callback(sql.append)
            before = len(calls)
            self.assertIsNone(host._ensure_original_publication_observation(projection))
            original = host._store_observations[held.publication.ticket]
            self.assertEqual(packets[0], ('prepare_lookup', {'identity': original_fixture.INDEX_CID.decode(),
                'index': original_fixture.STORED_INDEX.decode()}))
            self.assertEqual(packets[1][1]['attempt'], original_fixture.STORED_ATTEMPT.decode())
            self.assertEqual(store.read(scope).payload, original_fixture.INDEX_CID)
            self.assertFalse(any(statement.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT')) for statement in sql))
            self.assertFalse(any(family in ('source', 'task', 'compute') for family, _, _ in calls[before:]))
            self.assertFalse(any(name == 'finish_commit' for _, name, _ in calls[before:]))
            self.assertIsNone(host._pending_publication_write)
            self.assertIsNone(host._pending_publication_publisher)
            self.assertIs(host._store_observations[held.publication.ticket]._publisher, host._publishers[0])
            before_queries = list(sql)
            host._ensure_original_publication_observation(projection)
            self.assertEqual(sql, before_queries)
            self.assertIs(host._store_observations[held.publication.ticket], original)
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertTrue(host.close())

    def test_confirmed_miss_does_not_write_clear_pending_or_invent_success(self):
        with TemporaryDirectory() as directory:
            host, _, held, projection, store, scope, packets, _, calls = self.host(Path(directory), stored=False)
            sql = []
            store._connection.set_trace_callback(sql.append)
            before = len(calls)
            self.assertIsNone(host._ensure_original_publication_observation(projection))
            self.assertEqual(packets, [('prepare_observation', {'kind': 'not_found'})])
            self.assertIsNone(store.read(scope))
            self.assertIs(host._pending_publication_write, projection)
            self.assertIn(held.publication.ticket, host._publication_write_attempts)
            self.assertFalse(any(statement.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT')) for statement in sql))
            self.assertFalse(any(name == 'finish_commit' for _, name, _ in calls[before:]))
            self.assertTrue(host.close())

    def test_actual_atomic_commit_reply_loss_uses_original_lookup_without_resending(self):
        with TemporaryDirectory() as directory:
            host, core, held, projection, store, scope, packets, _, _ = self.host(Path(directory), stored=False)
            host._publication_write_attempts.clear()
            host._pending_publication_write = host._pending_publication_publisher = None
            facts = host._original_commit_reader_facts(projection)
            originals = ((held.row, held.capacity),)
            binding = host._installation.binding
            previous = core._call
            commits = []
            def call(family, name, *args):
                if family == 'publisher' and name == 'authorize' and args[2] == 1:
                    self.assertEqual(args, (host._publishers[0].handle, host._configuration.handle,
                                            1, held.publication.handle))
                    self.assertIsNotNone(core._journal_callbacks(binding._current.ticket).reader)
                    commits.append(args)
                    return 0
                return previous(family, name, *args)
            core._call = call
            # Independent older-attempt bytes; scalar Core validates the chain
            # only in this fixture. Physical writes still use actual same-TX
            # current checks, and this is not an actual Wasm/publisher claim.
            writes = tuple(ByteWrite(key, None, raw) for key, raw in (
                (scope, original_fixture.INDEX_CID),
                *((store.namespaced_key('publication_contract', cid.decode()), raw)
                  for cid, raw in ((original_fixture.INDEX_CID, original_fixture.STORED_INDEX),
                                   (original_fixture.REQUEST_CID, original_fixture.STORED_REQUEST),
                                   (original_fixture.ATTEMPT_CID, original_fixture.STORED_ATTEMPT))),
            ))
            def lose_reply(count, project, attached, fences, *, inspect, current, before_commit):
                self.assertIs(attached[0][0], originals[0][0])
                result = store.compare_exchange_many_inspected(writes, fences,
                    inspect=lambda reader: binding.inspect_reader(reader, lambda _: before_commit()),
                    current=current)
                self.assertEqual(result, (0, 0, 0, 0))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'store_publication_projected_inspected', side_effect=lose_reply) as write:
                with self.assertRaises(LocalStorageCommitUnknown):
                    host._store_original_commit(projection, facts, originals, host._publishers[0])
                host._ensure_original_publication_observation(projection)
                with self.assertRaises(LocalStorageError):
                    host._store_original_commit(projection, facts, originals, host._publishers[0])
                self.assertEqual(write.call_count, 1)
            self.assertEqual(len(commits), 1)
            self.assertEqual(store.read(scope).payload, original_fixture.INDEX_CID)
            self.assertEqual(packets[1][1]['attempt'], original_fixture.STORED_ATTEMPT.decode())
            self.assertIs(host._pending_publication_write, projection)
            self.assertTrue(host.close())

    def test_failed_lookup_keeps_same_holder_and_is_not_retried_on_next_status(self):
        with TemporaryDirectory() as directory:
            host, core, held, projection, store, _, _, faults, _ = self.host(Path(directory), stored=False)
            faults['prepare_observation'] = -35
            with self.assertRaises(LocalCoreError):
                host._ensure_original_publication_observation(projection)
            original = host._store_observations[held.publication.ticket]
            transfers = tuple(host._observation_transfers)
            self.assertIs(host._pending_publication_write, projection)
            with patch.object(store, 'inspect_publication_projected_inspected', side_effect=AssertionError('Repeated lookup')):
                # Existing unfinished Core state still refuses public export;
                # routing the same holder itself is not a completion claim.
                host._ensure_original_publication_observation(projection)
            self.assertIs(host._store_observations[held.publication.ticket], original)
            self.assertEqual(tuple(host._observation_transfers), transfers)
            self.assertIs(core._loans[held.record.ticket], held.record)
            faults.clear()
            self.assertTrue(host.close())

    def test_unattempted_or_copied_publisher_cannot_start_a_lookup(self):
        with TemporaryDirectory() as directory:
            host, _, held, projection, store, _, _, _, _ = self.host(Path(directory), stored=True)
            publisher = host._pending_publication_publisher
            with patch.object(store, 'inspect_publication_projected_inspected', side_effect=AssertionError('Untrusted lookup')):
                host._publication_write_attempts.clear()
                with self.assertRaises(ValueError): host._ensure_original_publication_observation(projection)
                host._publication_write_attempts.add(held.publication.ticket)
                for candidate in (None, copy.copy(publisher), True):
                    host._pending_publication_publisher = candidate
                    with self.assertRaises(ValueError): host._ensure_original_publication_observation(projection)
            self.assertFalse(host._store_observations)
            self.assertFalse(host._observation_attempts)
            host._pending_publication_publisher = publisher
            self.assertTrue(host.close())
