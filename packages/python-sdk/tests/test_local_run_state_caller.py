"""Actual File/SQLite transport with scalar Core; not public Run or Store ACK."""
import copy
from contextlib import contextmanager
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError
import test_local_reader_facts as file_fixture
import test_local_observed_index_caller as index_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class RunStateCallerTests(unittest.TestCase):
    # Independent wire and physical clock constants, not captured product output.
    state_wire = b'{"version":"actql-run-state/0.1","status":"succeeded","result_available":false}'
    clock_wire = b'{"observed_at":"2026-09-17T00:00:03.000Z"}'

    @contextmanager
    def fixture(self):
        helper = file_fixture.ReaderFactsTests()
        with helper.file() as (path, root, _, final), TemporaryDirectory() as directory, helper.store(Path(directory)/'original.sqlite') as store:
            reader = helper.transfer_ready(root, final)
            index = index_fixture.ObservedIndexCallerTests()
            values, host = index.bridge(root, reader, store)
            core, record, projection, facts, transfers, caller, calls, state, _ = values
            previous = core._call
            projected = {}
            clocks = []
            state['run_read'] = 0
            def call(family, name, *args):
                if family == 'publication_commit_export' and name == 'produce_run_state':
                    calls.append((family, name, args))
                    self.assertEqual(args[2], 31)
                    clocks.append(core._inputs[args[1]-500].payload)
                    if not state['observed_checked']: return -32
                    if state['run_read']: return state['run_read']
                    projected[args[0]] = self.state_wire
                    return 0
                if family == 'publication_commit_export' and name == 'length' and args[0] in projected:
                    return len(projected[args[0]])
                if family == 'buffer' and name == 'byte' and args[0] in projected:
                    return projected[args[0]][args[1]]
                return previous(family, name, *args)
            core._call = original_byte_fixture_port(call)
            host._inputs = []
            host._uncertain_ticket = None
            host._now = lambda: 1789603203000
            try:
                yield path, root, host, core, record, projection, caller, calls, state, clocks
            finally:
                state['cleanup'] = True
                index.cleanup(projection, facts, transfers)
                for source in tuple(host._inputs):
                    self.assertTrue(core.close_input(source))
                    host._inputs.remove(source)

    def ready(self, caller):
        self.assertTrue(caller.advance(7).ready)
        self.assertEqual(caller.finish(), 'adopt_committed_index')

    def test_same_store_frame_transports_owner_bytes_without_python_status_or_ack(self):
        with self.fixture() as (_, root, host, core, record, projection, caller, calls, _, clocks):
            self.ready(caller)
            consumed = []
            def consume(raw):
                self.assertEqual(raw, self.state_wire)
                self.assertEqual(len(projection.pending_outputs), 1)
                self.assertEqual(len(host._inputs), 1)
                self.assertIs(core._loans[record.ticket], record)
                self.assertTrue(root._readers)
                consumed.append(True)
            before = len(calls)
            host._project_original_run_state(projection, consume)
            self.assertEqual(consumed, [True])
            self.assertEqual(clocks, [self.clock_wire])
            self.assertEqual(projection.pending_outputs, ())
            self.assertEqual(host._inputs, [])
            self.assertFalse(any(name in ('prepare_commit', 'finish_commit', 'reserve_next_sdk_task')
                                 for _, name, _ in calls[before:]))

    def test_unfinished_chain_keeps_output_and_clock_without_candidate_fallback(self):
        with self.fixture() as (_, _, host, core, _, projection, _, _, _, _):
            with self.assertRaises(LocalCoreError) as error:
                host._project_original_run_state(projection, lambda _: self.fail('Unfinished state escaped'))
            self.assertEqual(error.exception.code, -32)
            self.assertEqual(len(projection.pending_outputs), 1)
            self.assertEqual(len(host._inputs), 1)
            self.assertIs(core._loans[host._inputs[0].ticket], host._inputs[0])

    def test_independent_read_denial_cannot_be_replaced_by_publish_or_physical_commit(self):
        with self.fixture() as (_, _, host, _, _, projection, caller, _, state, _):
            self.ready(caller)
            state['run_read'] = -35
            with self.assertRaises(LocalCoreError) as error:
                host._project_original_run_state(projection, lambda _: self.fail('Denied state escaped'))
            self.assertEqual(error.exception.code, -35)
            self.assertEqual(len(host._inputs), 1)

    def test_file_change_during_consumer_preserves_same_loans_for_cleanup(self):
        with self.fixture() as (path, _, host, core, _, projection, caller, _, _, _):
            self.ready(caller)
            def change(_):
                os.utime(path/'payload-original', ns=(1, 1))
            with self.assertRaises(file_fixture.LocalFileError):
                host._project_original_run_state(projection, change)
            self.assertEqual(len(projection.pending_outputs), 1)
            self.assertIs(core._loans[host._inputs[0].ticket], host._inputs[0])

    def test_preoutput_current_denial_reclaims_clock_without_replay_or_new_output(self):
        with self.fixture() as (_, _, host, _, _, projection, caller, calls, state, _):
            self.ready(caller)
            state['publisher'] = -35
            before = len(calls)
            for _ in range(2):
                with self.assertRaises(LocalCoreError):
                    host._project_original_run_state(projection, lambda _: self.fail('Denied state escaped'))
                self.assertEqual(host._inputs, [])
                self.assertEqual(projection.pending_outputs, ())
            self.assertFalse(any(name in ('produce_run_state', 'finish_commit', 'prepare_commit')
                                 for _, name, _ in calls[before:]))

    def test_cleanup_failure_blocks_reprojection_and_retains_original_clock(self):
        with self.fixture() as (_, _, host, core, _, projection, caller, calls, state, _):
            self.ready(caller)
            state['cleanup'] = False
            with self.assertRaises(LocalCoreError) as error:
                host._project_original_run_state(projection, lambda _: None)
            self.assertEqual(error.exception.code, -9)
            outputs = projection.pending_outputs
            before = len(calls)
            with self.assertRaises(RuntimeError):
                host._project_original_run_state(projection, lambda _: None)
            self.assertEqual(projection.pending_outputs, outputs)
            self.assertEqual(len(host._inputs), 1)
            self.assertFalse(any(name == 'produce_run_state' for _, name, _ in calls[before:]))
            self.assertTrue(all(core._loans[source.ticket] is source for source in host._inputs))

    def test_copy_or_invalid_clock_refuses_before_any_projection(self):
        with self.fixture() as (_, _, host, _, _, projection, caller, calls, _, _):
            self.ready(caller)
            before = len(calls)
            with self.assertRaises(ValueError):
                copy.copy(host)._project_original_run_state(projection, lambda _: None)
            for now in (True, -1, 253402300800000):
                host._now = lambda: now
                with self.assertRaises(ValueError):
                    host._project_original_run_state(projection, lambda _: None)
            self.assertEqual(calls[before:], [])
            self.assertEqual(host._inputs, [])

    def test_copied_reconciliation_and_retaining_consumer_refuse_original_custody(self):
        with self.fixture() as (_, _, host, _, _, projection, caller, _, _, _):
            self.ready(caller)
            with self.assertRaises(ValueError):
                copy.copy(caller).project_run_state(None, lambda _: None)
            with self.assertRaises(ValueError):
                host._project_original_run_state(projection, lambda _: True)
            self.assertEqual(len(projection.pending_outputs), 1)
            self.assertEqual(len(host._inputs), 1)
