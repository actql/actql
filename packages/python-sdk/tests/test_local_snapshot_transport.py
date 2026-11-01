"""Actual SQLite frame counters with explicit Core ports, not installed authority."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import unittest
from dataclasses import replace
from threading import Thread

from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_storage import ByteFence, LocalByteStore
import test_local_original_operation_current as operation_fixture
import test_local_submission_lookup as lookup_fixture


class SnapshotTransportTests(unittest.TestCase):
    def test_frame_copy_thread_and_read_reentry_poison_only_the_original_reader(self):
        for mode in ('copy', 'thread', 'reentry'):
            with self.subTest(mode=mode), TemporaryDirectory(prefix='actql-frame-original-') as directory:
                store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                    max_record_bytes=4096, max_payload_bytes=16384)
                self.addCleanup(store.close)
                store.compare_exchange('epoch', None, b'original-epoch')
                store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
                callbacks = _JournalCallbacks(lambda: None, store)
                def inspect(reader):
                    callbacks.reader = reader
                    self.assertEqual(callbacks.begin(1, 8, 3), 0)
                    self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                    self.assertEqual(callbacks.query(), 0)
                    if mode == 'copy':
                        callbacks.reader = replace(reader)
                        self.assertEqual(callbacks.check_frame(), -41)
                    elif mode == 'thread':
                        result = []
                        thread = Thread(target=lambda: result.append(callbacks.check_frame()))
                        thread.start()
                        thread.join()
                        self.assertEqual(result, [-41])
                    else:
                        def receive(_):
                            self.assertEqual(callbacks.check_frame(), -41)
                        reader.read('original', 'one', receive)
                    self.assertIsInstance(callbacks.failure, ValueError)
                with self.assertRaises(ValueError):
                    store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                        inspect=inspect, current=lambda: None)

    def test_joined_lookup_keeps_both_failure_boundaries_and_original_cleanup(self):
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        import json
        admission = {'ref': reference, 'durability': 'durable', 'revision': 7}
        for after_copy in (False, True):
            with self.subTest(after_copy=after_copy), TemporaryDirectory(prefix='actql-lookup-fence-') as directory:
                fixture = lookup_fixture.LocalSubmissionLookupTests()
                self.addCleanup(fixture.doCleanups)
                host, core, _, _, _ = fixture.fixture(directory,
                    {'kind': 'ready', 'intentCid': 'sha256:' + 'e' * 64,
                     'admission': json.dumps(admission)}, run_reference=reference)
                failure = LocalCoreError('validate_submission_lookup', -32)
                validations = [None, failure] if after_copy else [failure]
                with patch.object(core, 'validate_submission_lookup', side_effect=validations):
                    with self.assertRaises(LocalCoreError) as failed:
                        host._read_original_reference(reference, kind=5)
                self.assertIs(failed.exception, failure)
                output = host._projections[-1]
                self.assertIs(core._loans[output.ticket], output)
                self.assertEqual(bool(core._inputs[output.ticket].payload), after_copy)
                self.assertFalse(host._run_loans)
                self.assertFalse(host._physical_work)
                self.assertTrue(host.close())

    def test_original_transport_does_not_reobserve_semantics_between_query_fences(self):
        with TemporaryDirectory(prefix='actql-snapshot-transport-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            key = store.namespaced_key('original', 'one')
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(key, None, b'original-row')
            observations = []
            def current():
                observations.append('current')
            callbacks = _JournalCallbacks(current, store)
            def inspect(reader):
                callbacks.reader = reader
                before = len(observations)
                self.assertEqual(callbacks.begin(1, 8, 3), 0)
                self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                self.assertEqual(len(observations), before)
                self.assertEqual(callbacks.query(), 0)
                self.assertGreater(len(observations), before)
                before = len(observations)
                self.assertEqual(callbacks.row_copy(0, 0, 3), b'one')
                self.assertEqual(callbacks.row_copy(1, 0, 12), b'original-row')
                self.assertEqual(len(observations), before)
                self.assertEqual(callbacks.release(), 0)
                self.assertEqual(callbacks.check_current(), 0)
                self.assertGreater(len(observations), before)
            store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                inspect=inspect, current=current)
            # A frame is not a currentness token and cannot survive its reader.
            self.assertEqual(callbacks.check_frame(), -41)
            self.assertIsInstance(callbacks.failure, ValueError)

    def test_transport_never_turns_revocation_or_failed_reader_into_permission(self):
        with TemporaryDirectory(prefix='actql-snapshot-refusal-') as directory:
            store = LocalByteStore(Path(directory) / 'original.sqlite', max_records=8,
                max_record_bytes=4096, max_payload_bytes=16384)
            self.addCleanup(store.close)
            store.compare_exchange('epoch', None, b'original-epoch')
            store.compare_exchange(store.namespaced_key('original', 'one'), None, b'original-row')
            active = [True]
            original = PermissionError('original physical current revoked')
            def current():
                if not active[0]:
                    raise original
            callbacks = _JournalCallbacks(current, store)
            def inspect(reader):
                callbacks.reader = reader
                self.assertEqual(callbacks.begin(1, 8, 3), 0)
                self.assertEqual(callbacks.query_copy(0, b'originalone'), 11)
                self.assertEqual(callbacks.query(), 0)
                row = callbacks.row
                active[0] = False
                self.assertEqual(callbacks.check_current(), -41)
                self.assertIs(callbacks.failure, original)
                with self.assertRaises(ValueError):
                    callbacks.row_copy(1, 0, 12)
                self.assertIs(callbacks.row, row)
                self.assertEqual(callbacks.release(), -41)
                active[0] = True
            with self.assertRaises(PermissionError) as failed:
                store.inspect_namespaces((ByteFence('epoch', 0, b'original-epoch'),),
                    inspect=inspect, current=current)
            self.assertIs(failed.exception, original)

    def test_original_operation_observation_joins_its_two_adjacent_current_checks(self):
        fixture = operation_fixture.OriginalOperationCurrentTests()
        self.addCleanup(fixture.doCleanups)
        _, core, _, binding, _ = fixture.fixture()
        def consume(current):
            core._invoking = True
            try:
                with patch.object(binding, '_physical_current', wraps=binding._physical_current) as physical:
                    self.assertEqual(core._journal_current_operation(current.ticket), core._host_operation_id)
                    self.assertEqual(physical.call_count, 1)
            finally:
                core._invoking = False
        with core._host_operation():
            binding.inspect(consume)

    def test_reference_produce_and_copy_share_only_the_adjacent_validation(self):
        fixture = lookup_fixture.LocalSubmissionLookupTests()
        self.addCleanup(fixture.doCleanups)
        reference = {'namespaceId': 'local', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'd' * 64}
        import json
        admission = {'ref': reference, 'durability': 'durable', 'revision': 7}
        with TemporaryDirectory(prefix='actql-lookup-handoff-') as directory:
            host, core, _, counts, _ = fixture.fixture(directory,
                {'kind': 'ready', 'intentCid': 'sha256:' + 'e' * 64,
                 'admission': json.dumps(admission)}, run_reference=reference)
            self.assertEqual(json.loads(host._read_original_reference(reference, kind=5)), admission)
            self.assertEqual(counts, {'produce': 1, 'validate': 2})
            self.assertFalse(host._run_loans)
            self.assertFalse(host._physical_work)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
