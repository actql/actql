"""Actual File/SQLite observed-index transport with scalar Core, not Run ACK."""
import copy
import os
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_product import InstalledLocalHost
import test_local_reader_facts as file_fixture
import test_local_store_reconciliation as observation_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class ObservedIndexCallerTests(unittest.TestCase):
    def bridge(self, root, reader, store):
        fixture = observation_fixture.StoreReconciliationTests()
        values = fixture.bridge(root, reader, store)
        core, _, projection, _, _, caller, calls, state, _ = values
        previous = core._call
        observed = {}
        state['observed_checked'] = False
        def call(family, name, *args):
            if family == 'publication' and name == 'finish_observation':
                code = previous(family, name, *args)
                state['observed_checked'] = code == 4
                return code
            if family == 'publication_commit_export' and name == 'produce_observed_index':
                calls.append((family, name, args))
                self.assertEqual(args[1], 31)
                if not state['observed_checked']:
                    return -32
                if state['publisher']:
                    return state['publisher']
                self.assertIn(args[2], (0, 3))
                observed[args[0]] = fixture.ref if args[2] == 3 else fixture.index
                if args[2] == 3 and 'after_identity' in state:
                    state['after_identity']()
                return 0
            if family == 'publication_commit_export' and name == 'length' and args[0] in observed:
                return len(observed[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in observed:
                return observed[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        caller.prepare()
        # Physical consumer stop allows cleanup; this scalar fixture does not
        # model the real Core's distinct observation/output borrow tickets.
        state['borrow'] = False
        host = InstalledLocalHost.__new__(InstalledLocalHost)
        host._sdk_read_evidence = {}
        host._sdk_deliveries = {}
        host._original, host._closing, host._core = host, False, core
        host._installation = SimpleNamespace()
        host._store_observations = {projection._publication.ticket: caller}
        return values, host

    def ready(self, caller):
        self.assertTrue(caller.advance(7).ready)
        self.assertEqual(caller.finish(), 'adopt_committed_index')

    def cleanup(self, projection, facts, transfers):
        self.assertTrue(projection.retire_outputs())
        self.assertTrue(all(value.close() for value in reversed(transfers)))
        self.assertTrue(facts.close())

    def test_host_forwards_only_actual_old_index_under_original_reader_loans(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            values, host = self.bridge(root, reader, store)
            core, record, projection, facts, transfers, caller, calls, state, _ = values
            self.ready(caller)
            before = len(calls)
            consumed = []
            def consume(identity, body):
                self.assertEqual(identity, observation_fixture.StoreReconciliationTests.ref)
                self.assertEqual(body, observation_fixture.StoreReconciliationTests.index)
                self.assertEqual(len(projection.pending_outputs), 2)
                self.assertIs(root._readers[id(reader)], reader)
                self.assertIs(core._loans[record.ticket], record)
                consumed.append(True)
            host._project_original_observed_index(projection, consume)
            self.assertEqual(consumed, [True])
            self.assertEqual(projection.pending_outputs, ())
            self.assertFalse(any(name in ('produce_material', 'finish_commit') for _, name, _ in calls[before:]))
            self.cleanup(projection, facts, transfers)

    def test_unfinished_observation_cannot_project_candidate_or_release_loan(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            values, host = self.bridge(root, helper.transfer_ready(root, final), store)
            core, _, projection, facts, transfers, _, _, _, _ = values
            consumed = []
            with self.assertRaises(LocalCoreError) as failed:
                host._project_original_observed_index(projection, lambda *_: consumed.append(True))
            self.assertEqual(failed.exception.code, -32)
            self.assertEqual(consumed, [])
            self.assertEqual(len(projection.pending_outputs), 1)
            self.assertIs(core._loans[projection.pending_outputs[0].ticket], projection.pending_outputs[0])
            self.cleanup(projection, facts, transfers)

    def test_current_publisher_revocation_rejects_even_after_original_finish(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            values, host = self.bridge(root, helper.transfer_ready(root, final), store)
            _, _, projection, facts, transfers, caller, calls, state, _ = values
            self.ready(caller)
            state['publisher'] = -35
            before = len(calls)
            with self.assertRaises(LocalCoreError):
                host._project_original_observed_index(projection, lambda *_: self.fail('Revoked bytes escaped'))
            self.assertFalse(any(name == 'produce_observed_index' for _, name, _ in calls[before:]))
            self.cleanup(projection, facts, transfers)

    def test_file_change_during_consumer_keeps_same_outputs_until_cleanup(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (path, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            values, host = self.bridge(root, helper.transfer_ready(root, final), store)
            core, _, projection, facts, transfers, caller, _, _, _ = values
            self.ready(caller)
            def change(*_):
                os.utime(path/'payload-original', ns=(1, 1))
            with self.assertRaises(file_fixture.LocalFileError):
                host._project_original_observed_index(projection, change)
            self.assertEqual(len(projection.pending_outputs), 2)
            self.assertTrue(all(core._loans[value.ticket] is value for value in projection.pending_outputs))
            self.cleanup(projection, facts, transfers)

    def test_publisher_revoked_between_fields_never_delivers_a_mixed_pair(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            values, host = self.bridge(root, helper.transfer_ready(root, final), store)
            _, _, projection, facts, transfers, caller, _, state, _ = values
            self.ready(caller)
            state['after_identity'] = lambda: state.update(publisher=-35)
            with self.assertRaises(LocalCoreError) as failed:
                host._project_original_observed_index(projection, lambda *_: self.fail('Mixed pair escaped'))
            self.assertEqual(failed.exception.code, -35)
            self.assertEqual(len(projection.pending_outputs), 2)
            self.cleanup(projection, facts, transfers)

    def test_failed_output_cleanup_keeps_original_handles_without_reprojection(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            values, host = self.bridge(root, helper.transfer_ready(root, final), store)
            core, _, projection, facts, transfers, caller, calls, state, _ = values
            self.ready(caller)
            state['cleanup'] = False
            with self.assertRaises(LocalCoreError) as failed:
                host._project_original_observed_index(projection, lambda *_: None)
            self.assertEqual(failed.exception.code, -9)
            outputs = projection.pending_outputs
            self.assertEqual(len(outputs), 2)
            before = len(calls)
            with self.assertRaises(RuntimeError):
                host._project_original_observed_index(projection, lambda *_: None)
            self.assertEqual(projection.pending_outputs, outputs)
            self.assertFalse(any(name == 'produce_observed_index' for _, name, _ in calls[before:]))
            self.assertTrue(all(core._loans[value.ticket] is value for value in outputs))
            state['cleanup'] = True
            self.cleanup(projection, facts, transfers)

    def test_copied_host_or_reconciliation_cannot_use_original_index(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (_, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            values, host = self.bridge(root, helper.transfer_ready(root, final), store)
            _, _, projection, facts, transfers, caller, calls, _, _ = values
            self.ready(caller)
            before = len(calls)
            for action in (lambda: copy.copy(host)._project_original_observed_index(projection, lambda *_: None),
                           lambda: copy.copy(caller).project_observed_index(lambda *_: None)):
                with self.assertRaises(ValueError): action()
            self.assertEqual(len(calls), before)
            self.cleanup(projection, facts, transfers)


if __name__ == '__main__':
    unittest.main()
