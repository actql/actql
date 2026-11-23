"""Actual same-Store metadata CAS with a scalar Core protocol fixture.

No actual Wasm, physical payload availability, installed Host or wheel result.
The portable Owner cases separately validate state/key/counter semantics.
"""
from contextlib import nullcontext
import asyncio
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from threading import Event
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError, _Task, _ResultExport
from actql_sdk._local_run import LocalRunCustody, _PhysicalStart
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending, _OriginalExecution, _RunStateCustody
from actql_sdk._local_work import OriginalLocalWork
from actql_sdk._local_storage import LocalStorageCommitUnknown
from actql_sdk._values import wire_bytes
import test_local_public_run_observation as fixture
import test_local_submission_append as submission_fixture
from local_abi_declaration_fixture import original_byte_fixture_port

SAVED_STATE = b'{"opaque":"same original Core saved state","revision":0}'


class SDKRunStateStoreTests(unittest.IsolatedAsyncioTestCase):
    async def test_parent_constructor_retains_same_submission_and_rows_before_callbacks(self):
        originals = []
        initialize = _OriginalExecution.__init__
        prepare = LocalRunCustody.prepare_sdk
        reserve_rows = LocalRunCustody.reserve_submitted_rows
        def init(original, *args, **kwargs):
            initialize(original, *args, **kwargs)
            originals.append(original)
        def before_prepare(custody, run, submission):
            self.assertEqual(len(originals), 1)
            original = originals[0]
            self.assertIs(original.run, run)
            self.assertIs(original.submission, submission)
            self.assertIsNone(original.reference)
            self.assertFalse(original.host._physical_work)
            return prepare(custody, run, submission)
        def before_rows(custody, run, current, source, **kwargs):
            self.assertIs(originals[0].rows_input, source)
            self.assertIs(originals[0].run, run)
            return reserve_rows(custody, run, current, source, **kwargs)
        with TemporaryDirectory() as directory:
            with patch.object(_OriginalExecution, '__init__', init), patch.object(
                    LocalRunCustody, 'prepare_sdk', before_prepare), patch.object(
                    LocalRunCustody, 'reserve_submitted_rows', before_rows):
                host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            await asyncio.wait_for(host._physical_work[0].wait_stopped(), 2)
            self.assertIs(original, originals[0])
            self.assertIs(original.reference.run, run)
            observe(lambda _: None)
            self.assertIsNone(original.submission)
            self.assertIsNone(original.rows_input)
            await client.aclose()

    async def test_parent_retirement_keeps_shared_restored_and_pending_originals(self):
        for reason in ('shared', 'restored', 'pending'):
            with self.subTest(reason=reason), TemporaryDirectory() as directory:
                host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
                original = self.selected_execution(host, run)
                work = host._physical_work[0]
                await asyncio.wait_for(work.wait_stopped(), 2)
                other = None
                if reason == 'shared':
                    source = host._copy(b'original second invocation input')
                    other = host._runs.reserve(run.configuration, run.preparation, source)
                    host._run_loans.append(other)
                elif reason == 'restored':
                    # Explicit negative inventory port, not actual restored
                    # admission/material. Presence must never permit cleanup.
                    host._runs._run_restorations[run.handle] = object()
                else:
                    host._pending_start_write = next(value for owner, value in host._run_rows if owner is run)
                observe(lambda _: None)
                self.assertIn(original.reference, host._public_run_references)
                self.assertIn(run, host._run_loans)
                self.assertIn(run.preparation, host._prepared_inputs)
                self.assertIn(original.publication, host._publications)
                self.assertIsNone(work._cleanup_error)
                if other is not None:
                    self.assertTrue(host._runs.close_run(other))
                    host._run_loans.remove(other)
                host._runs._run_restorations.pop(run.handle, None)
                host._pending_start_write = None
                await client.aclose()

    async def test_parent_retirement_keeps_original_unpublished_state_projection(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, _, _, _, _, _ = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            reference = json.loads(core._inputs[original.reference.source.ticket].payload)
            source = host._copy(wire_bytes({**reference, 'run': run.handle,
                'observed_at': '2026-11-18T00:00:00.000Z'}))
            output = core.reserve_submission_projection(host._configuration.handle, source, 12,
                cleanup=lambda: True)
            host._projections.append(output)
            host._append_sources[output.ticket] = source
            held = _RunStateCustody(run, None, source, output=output)
            host._run_state_custody[run.handle] = held
            original.state = held
            # A genuine constructor/nominal slot through explicit scalar
            # ports, not a completed or physically pending write certificate.
            with patch.object(core, 'close_unpublished_state', side_effect=AssertionError('Unpublished owner was discarded')):
                self.assertFalse(host._retire_original_execution(original))
            self.assertIs(host._run_state_custody[run.handle], held)
            self.assertIs(core._loans[output.ticket], output)
            self.assertIn(original.reference, host._public_run_references)
            self.assertIn(run, host._run_loans)
            await client.aclose()

    async def test_parent_ack_order_and_retry_skip_only_acknowledged_originals(self):
        for boundary in ('start', 'run', 'preparation', 'rows_input'):
            with self.subTest(boundary=boundary), TemporaryDirectory() as directory:
                host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
                original = self.selected_execution(host, run)
                work = host._physical_work[0]
                await asyncio.wait_for(work.wait_stopped(), 2)
                rows = next(value for owner, value in host._run_rows if owner is run)
                submission, prepared, rows_input = original.submission, run.preparation, original.rows_input
                previous = core._call
                materials, events, declined = {}, [], [True]
                def port(family, name, *args):
                    if (family, name) == ('material', 'reserve'):
                        handle = 6000000 + args[2]
                        materials[handle] = (args[1], args[2])
                        return handle
                    label = None
                    if (family, name) == ('run', 'close_physical_start'):
                        label = 'start'
                    elif (family, name) == ('material', 'close') and args[0] in materials:
                        label = str(materials[args[0]][0])
                    elif (family, name, args) == ('journal', 'close', (journal.handle,)):
                        label = 'journal'
                    elif (family, name, args) == ('material', 'close', (rows.handle,)):
                        label = 'rows'
                    elif (family, name, args) == ('run', 'close', (run.handle,)):
                        label = 'run'
                    elif (family, name, args) == ('program', 'close_preparation', (prepared.handle,)):
                        label = 'preparation'
                    elif (family, name, args) == ('submission', 'close', (submission.handle,)):
                        label = 'submission'
                    elif (family, name, args) == ('buffer', 'close', (rows_input.handle,)):
                        label = 'rows_input'
                    if label is not None:
                        events.append(label)
                        if label == boundary and declined[0]:
                            return -9
                    if (family, name) == ('run', 'close_physical_start'):
                        return 0
                    if (family, name) == ('material', 'close') and args[0] in materials:
                        return core._cleanup(materials[args[0]][1])
                    return previous(family, name, *args)
                # Explicit original scalar Core ports, not actual physical
                # start/Journal admission. Constructor capture is exercised
                # separately through the imported start caller.
                journal = core.reserve_journal_observation(rows, host._configuration.handle,
                    store=host._installation._store, current=host._installation.binding._current_observer,
                    cleanup=lambda: True)
                host._journal_outputs.append(journal)
                host._admission_observations[run.handle] = journal
                with patch.object(core, '_call', side_effect=port):
                    step = core.reserve_material(run.handle, 8, cleanup=lambda: True)
                    binding = core.reserve_material(run.handle, 9, cleanup=lambda: True)
                    host._step_outputs.append(step)
                    host._publication_bindings.append((run, binding))
                    original.start_step = step
                    start = _PhysicalStart(host._runs._identity, 9900201, run, run.configuration, run.input)
                    host._runs._starts[start.handle] = start
                    host._physical_starts.append(start)
                    original.physical_start = start
                    with self.assertRaises(LocalProductCleanupPending) as failed:
                        observe(lambda _: None)
                    self.assertIn(work, host._physical_work)
                    self.assertNotIn(original.reference, host._public_run_references)
                    self.assertIs(work._cleanup_error, failed.exception)
                    if boundary in ('preparation', 'rows_input'):
                        self.assertNotIn(run.handle, host._runs._runs)
                    if boundary == 'preparation':
                        self.assertIn(prepared.handle, host._preparation._preparations)
                    if boundary == 'rows_input':
                        self.assertNotIn(prepared.handle, host._preparation._preparations)
                        self.assertIs(original.rows_input, rows_input)
                    declined[0] = False
                    self.assertTrue(host._retire_original_execution(original))
                expected = ['start', '8', '9', 'journal', 'rows', 'run', 'preparation', 'submission', 'rows_input']
                expected.insert(expected.index(boundary), boundary)
                self.assertEqual(events, expected)
                self.assertNotIn(work, host._physical_work)
                self.assertIsNone(original.physical_start)
                self.assertIsNone(original.start_step)
                self.assertIsNone(original.submission)
                self.assertIsNone(original.rows_input)
                await client.aclose()

    async def test_parent_retirement_returns_same_fresh_run_and_preparation_after_child_ack(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            preparation = run.preparation
            configuration, environment = host._configuration, host._environment
            observe(lambda _: None)
            self.assertNotIn(run, host._run_loans)
            self.assertNotIn(run.handle, host._runs._runs)
            self.assertNotIn(preparation, host._prepared_inputs)
            self.assertNotIn(preparation.handle, host._preparation._preparations)
            self.assertNotIn(run.input.ticket, core._loans)
            self.assertNotIn(preparation.input.ticket, core._loans)
            self.assertFalse(host._run_rows)
            self.assertNotIn(work, host._physical_work)
            self.assertEqual(store.read(key).payload, SAVED_STATE)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
            self.assertIs(host._configuration, configuration)
            self.assertIs(host._environment, environment)
            await client.aclose()

    async def test_failed_worker_returns_confirmed_state_transport_before_read_admission(self):
        failure = LocalStorageCommitUnknown(object())
        with TemporaryDirectory() as directory:
            with patch.object(_OriginalExecution, '__call__', side_effect=failure):
                host, core, client, run, store, key, calls, codes, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            held = []
            codes['during_produce'] = lambda: held.append((original.state.source, original.state.output))
            observe(lambda _: None)
            source, output = held[0]
            self.assertNotIn(output.ticket, core._loans)
            self.assertNotIn(source.ticket, core._loans)
            self.assertNotIn(run.handle, host._run_state_custody)
            self.assertIsNone(original.state)
            self.assertIs(work._future.exception(), failure)
            self.assertIn(original.reference, host._public_run_references)
            self.assertIn(work, host._physical_work)
            self.assertIn(original.publication, host._publications)
            self.assertEqual(store.read(key).payload, SAVED_STATE)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
            rows = next(value for owner, value in host._run_rows if owner is run)
            # Same actual constructor as the ordinary failed frontier, with
            # explicit scalar Core ports. This neither models a numeric quota
            # nor claims a physical Journal/installed Result acceptance.
            journal = core.reserve_journal_observation(rows, host._configuration.handle,
                store=store, current=host._installation.binding._current_observer,
                cleanup=lambda: True)
            self.assertTrue(core.close_journal_observation(journal))
            await client.aclose()

    async def test_failed_worker_state_transport_false_ack_keeps_same_original_custody(self):
        for boundary in ('output', 'input'):
            with self.subTest(boundary=boundary), TemporaryDirectory() as directory:
                primary = RuntimeError('Original physical invocation failure')
                with patch.object(_OriginalExecution, '__call__', side_effect=primary):
                    host, core, client, run, store, key, calls, codes, observe = await self.bridge(directory)
                original = self.selected_execution(host, run)
                work = host._physical_work[0]
                await asyncio.wait_for(work.wait_stopped(), 2)
                captured = []
                codes['during_produce'] = lambda: captured.append((original.state.source, original.state.output))
                previous = core._call
                def refuse(family, name, *args):
                    if captured:
                        source, output = captured[0]
                        if (boundary == 'output' and (family, name, args) ==
                                ('publication_commit_export', 'close', (output.handle,))):
                            return -9
                        if (boundary == 'input' and (family, name, args) ==
                                ('buffer', 'close', (source.handle,))):
                            return -9
                    return previous(family, name, *args)
                with patch.object(core, '_call', side_effect=refuse):
                    with self.assertRaises(LocalProductCleanupPending):
                        observe(lambda _: None)
                source, output = captured[0]
                held = host._run_state_custody[run.handle]
                self.assertIs(original.state, held)
                self.assertIs(core._loans[source.ticket], source)
                self.assertIs(held.output, output if boundary == 'output' else None)
                self.assertEqual(output.ticket in core._loans, boundary == 'output')
                self.assertIs(work._future.exception(), primary)
                self.assertIn(original.reference, host._public_run_references)
                self.assertIn(original.publication, host._publications)
                self.assertEqual(store.read(key).payload, SAVED_STATE)
                self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
                await client.aclose()  # Existing whole-Host cleanup retries only remaining originals.
                self.assertTrue(core._closed)

    def selected_execution(self, host, run):
        # The public fixture admitted one original work but supplies its Core
        # publication separately. Associate that exact scalar-port original;
        # this does not claim execution of the installed Core/physical driver.
        original = host._execution_for_run(run)
        self.assertIsNotNone(original)
        original.publication = host._commit_projections[0]._publication
        return original

    async def test_retirement_waits_for_real_thread_exit_after_future_completion(self):
        done, release = Event(), Event()
        initialize = OriginalLocalWork.__init__
        def init(work, *args, **kwargs):
            initialize(work, *args, **kwargs)
            complete = work._future.set_result
            def complete_before_exit(value):
                complete(value)
                done.set()
                if not release.wait(3):
                    raise AssertionError('Bounded original worker fixture was not released')
            work._future.set_result = complete_before_exit
        with TemporaryDirectory() as directory:
            with patch.object(OriginalLocalWork, '__init__', init):
                host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = next(work for work in host._physical_work if work._invoke is original)
            try:
                self.assertTrue(done.wait(1))
                self.assertTrue(work._future.done())
                self.assertTrue(work._thread.is_alive())
                self.assertFalse(work.stopped)
                observe(lambda _: None)
                self.assertIn(original.reference, host._public_run_references)
                self.assertIs(host._run_state_custody[run.handle], original.state)
                self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            finally:
                release.set()
                await asyncio.wait_for(work.wait_stopped(), 2)
            observe(lambda _: None)
            self.assertNotIn(original.reference, host._public_run_references)
            self.assertNotIn(work, host._physical_work)
            self.assertNotIn(original.publication, host._publications)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 2)
            self.assertEqual(store.read(key).payload, SAVED_STATE)
            await client.aclose()

    async def test_retirement_worker_input_is_bound_before_original_driver_handoff(self):
        copied = []
        invoke = _OriginalExecution.__call__
        def entered(original):
            host = original.host
            with host._core._lock:
                self.assertIs(host._current_execution(), original)
                source = host._copy(b'original-worker-input')
                self.assertIs(host._core._inputs[source.ticket].cleanup.__self__, original)
                copied.append(source)
            invoke(original)
        with TemporaryDirectory() as directory:
            with patch.object(_OriginalExecution, '__call__', entered):
                host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            self.assertIsNone(work._future.exception())
            self.assertEqual(len(copied), 1)
            self.assertIs(core._loans[copied[0].ticket], copied[0])
            observe(lambda _: None)
            self.assertNotIn(copied[0].ticket, core._loans)
            self.assertNotIn(copied[0], host._inputs)
            self.assertNotIn(work, host._physical_work)
            await client.aclose()

    async def test_retirement_keeps_one_confirmation_and_active_original_reader(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = next(work for work in host._physical_work if work._invoke is original)
            await asyncio.wait_for(work.wait_stopped(), 2)
            publication = original.publication
            # Explicit existing delivery pin port: neither poll may close it.
            delivery = SimpleNamespace(_active=False, _payload_reader_borrows={7: object()}, close=lambda: True)
            host._sdk_deliveries[publication.ticket] = delivery
            observe(lambda _: None)
            held, output = original.state, original.state.output
            saved = store.read(key)
            observe(lambda _: None)
            self.assertIs(original.state, held)
            self.assertIs(held.output, output)
            self.assertIs(core._loans[output.ticket], output)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 2)
            self.assertEqual(store.read(key), saved)
            self.assertIn(original.reference, host._public_run_references)
            delivery._payload_reader_borrows.clear()
            observe(lambda _: None)
            self.assertNotIn(publication, host._publications)
            self.assertNotIn(work, host._physical_work)
            self.assertFalse(host._run_state_custody)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            await client.aclose()

    async def test_retirement_current_refusal_keeps_same_output_and_live_route(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, _, _, calls, codes, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            await asyncio.wait_for(host._physical_work[0].wait_stopped(), 2)
            codes['confirm_sdk_run_state'] = -35
            with self.assertRaises(LocalCoreError):
                observe(lambda _: self.fail('Refused confirmation escaped'))
            held = original.state
            self.assertFalse(held.metadata_confirmed)
            self.assertIs(core._loans[held.output.ticket], held.output)
            self.assertIn(original.reference, host._public_run_references)
            del codes['confirm_sdk_run_state']
            observe(lambda _: None)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            self.assertNotIn(original.reference, host._public_run_references)
            await client.aclose()

    async def test_retirement_does_not_erase_original_failed_worker_for_saved_state(self):
        with TemporaryDirectory() as directory:
            primary = RuntimeError('original physical invocation failure')
            with patch.object(_OriginalExecution, '__call__', side_effect=primary):
                host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            self.assertIs(work._future.exception(), primary)
            # This explicit Core port still returns its ordinary state bytes.
            # They cannot erase a separately retained physical failure.
            observe(lambda _: None)
            self.assertIn(original.reference, host._public_run_references)
            self.assertIn(work, host._physical_work)
            self.assertIsNone(original.state)
            self.assertNotIn(run.handle, host._run_state_custody)
            self.assertIs(work._future.exception(), primary)
            await client.aclose()

    async def test_retirement_close_refusal_keeps_same_owner_and_saved_fallback(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            publication = original.publication
            reference = json.loads(core._inputs[original.reference.source.ticket].payload)
            previous = core._call
            def refuse(family, name, *args):
                if (family, name) == ('publication', 'close'):
                    return -9
                return previous(family, name, *args)
            with patch.object(core, '_call', side_effect=refuse):
                with self.assertRaises(LocalProductCleanupPending) as failed:
                    observe(lambda _: None)
            self.assertIs(work._cleanup_error, failed.exception)
            self.assertIs(original.publication, publication)
            self.assertIn(publication, host._publications)
            self.assertIn(work, host._physical_work)
            self.assertNotIn(original.reference, host._public_run_references)
            with patch.object(host, '_read_original_reference', return_value=wire_bytes(fixture.STATE)) as saved:
                state = await client._request('status', {'ref': reference})
                self.assertEqual(state['status'], 'succeeded')
                saved.assert_called_once_with(reference, kind=7)
            self.assertTrue(host._retire_original_execution(original))
            self.assertNotIn(work, host._physical_work)
            self.assertNotIn(publication, host._publications)
            self.assertIs(work._cleanup_error, failed.exception)
            await client.aclose()
            self.assertTrue(core._closed)
            self.assertFalse(host._physical_work)

    async def test_retirement_closes_only_construction_associated_inputs(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            await asyncio.wait_for(host._physical_work[0].wait_stopped(), 2)
            first = host._copy(b'owned-before', execution=original)
            unrelated = host._copy(b'independent-original')
            last = host._copy(b'owned-after', execution=original)
            self.assertIs(core._inputs[first.ticket].cleanup.__self__, original)
            before = len(host._inputs)
            with self.assertRaises(ValueError):
                host._copy(b'foreign-copy', execution=copy.copy(original))
            self.assertEqual(len(host._inputs), before)
            observe(lambda _: None)
            self.assertNotIn(first, host._inputs)
            self.assertNotIn(last, host._inputs)
            self.assertNotIn(first.ticket, core._loans)
            self.assertNotIn(last.ticket, core._loans)
            self.assertIn(unrelated, host._inputs)
            self.assertIs(core._loans[unrelated.ticket], unrelated)
            self.assertEqual(core._inputs[unrelated.ticket].payload, b'independent-original')
            self.assertNotIn(run, host._run_loans)  # Only this fresh private Run's parents.
            with self.assertRaises(ValueError):
                host._retire_original_execution(original)
            await client.aclose()

    async def test_retirement_throw_keeps_original_output_and_retry_does_not_reconfirm(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, _, _, calls, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            failure = LocalCoreError('close_publication_commit_export', -33)
            with patch.object(core, 'close_publication_commit_export', side_effect=failure):
                with self.assertRaises(LocalCoreError) as failed:
                    observe(lambda _: None)
            self.assertIs(failed.exception, failure)
            held = original.state
            self.assertIs(host._run_state_custody[run.handle], held)
            self.assertIs(core._loans[held.output.ticket], held.output)
            self.assertIs(work._cleanup_error, failure)
            self.assertNotIn(original.reference, host._public_run_references)
            self.assertTrue(host._retire_original_execution(original))
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
            self.assertIs(work._cleanup_error, failure)
            await client.aclose()

    async def test_retirement_export_ack_precedes_task_and_pending_task_retries_same_original(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, _, _, _, _, observe = await self.bridge(directory)
            original = self.selected_execution(host, run)
            work = host._physical_work[0]
            await asyncio.wait_for(work.wait_stopped(), 2)
            # Explicit scalar Core cleanup originals, not real Task admission,
            # execution or physical ACK. The actual imported close adapters,
            # nominal maps and Host reverse-retirement caller execute below.
            task = _Task(core._identity, 9900101)
            result = _ResultExport(core._identity, 9900102)
            core._task_loans[task.handle] = task
            core._result_loans[result.handle] = result
            host._tasks.append(task)
            host._result_exports.append(result)
            original.tasks, original.results = [task], [result]
            previous = core._call
            pending = [True]
            returned = []
            def port(family, name, *args):
                if (family, name) == ('result', 'close'):
                    self.assertEqual(args, (result.handle,))
                    returned.append(result)
                    return 0
                if (family, name) == ('task', 'progress'):
                    self.assertEqual(args, (task.handle, 5))
                    return -1
                if (family, name) == ('task', 'close'):
                    self.assertEqual(args, (task.handle,))
                    self.assertNotIn(result.handle, core._result_loans)
                    returned.append(task)
                    return -9 if pending[0] else 0
                return previous(family, name, *args)
            core._call = original_byte_fixture_port(port)
            with self.assertRaises(LocalProductCleanupPending):
                observe(lambda _: None)
            self.assertEqual(returned, [result, task])
            self.assertFalse(original.results)
            self.assertEqual(original.tasks, [task])
            self.assertIs(core._task_loans[task.handle], task)
            self.assertIn(work, host._physical_work)
            self.assertIn(run, host._run_loans)
            pending[0] = False
            self.assertTrue(host._retire_original_execution(original))
            self.assertEqual(returned, [result, task, task])
            self.assertNotIn(task.handle, core._task_loans)
            self.assertNotIn(work, host._physical_work)
            self.assertNotIn(run, host._run_loans)
            await client.aclose()

    async def test_confirmed_response_guard_and_transfer_share_original_read_frame(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = core._call
            entered = []
            confirmed = []
            def guarded(family, name, *args):
                if family == 'publication_commit_export' and name == 'confirm_sdk_run_state':
                    confirmed.append(core._journal_callbacks(host._configuration.current.ticket).reader)
                if family == 'publication' and name == 'validate_run':
                    callbacks = core._journal_callbacks(host._configuration.current.ticket)
                    if callbacks.check_current() != 0:
                        return -41
                    entered.append(callbacks.reader)
                return original(family, name, *args)
            core._call = original_byte_fixture_port(guarded)
            states = []
            def consume(raw):
                core.validate_publication_run(
                    host._commit_projections[0]._publication,
                    run.handle, host._configuration.handle)
                self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
                self.assertFalse(host.close())
                self.assertFalse(host._closing)
                states.append(raw)
            observe(consume)
            self.assertEqual(states, [wire_bytes(fixture.STATE)])
            self.assertEqual(store.read(key).payload, SAVED_STATE)
            self.assertEqual(len(confirmed), 1)
            self.assertIsNot(entered[0], confirmed[0])
            self.assertIs(entered[-1], confirmed[0])
            self.assertIsNone(core._journal_callbacks(host._configuration.current.ticket).reader)
            with self.assertRaises(ValueError):
                entered[-1].current()
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_final_original_run_guard_refusal_does_not_publish_confirmed_bytes(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = core._call
            def refuse(family, name, *args):
                if (family == 'publication' and name == 'validate_run'
                        and calls.count('confirm_sdk_run_state') == 1):
                    callbacks = core._journal_callbacks(host._configuration.current.ticket)
                    self.assertEqual(callbacks.check_current(), 0)
                    return -2
                return original(family, name, *args)
            core._call = original_byte_fixture_port(refuse)
            states = []
            def consume(raw):
                core.validate_publication_run(host._commit_projections[0]._publication,
                    run.handle, host._configuration.handle)
                states.append(raw)
            with self.assertRaises(LocalCoreError):
                observe(consume)
            self.assertEqual(states, [])
            self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
            self.assertEqual(store.read(key).payload, SAVED_STATE)
            held = host._run_state_custody[run.handle]
            self.assertTrue(held.write_attempted)
            self.assertIs(core._loans[held.output.ticket], held.output)
            await client.aclose()
            self.assertTrue(core._closed)

    async def bridge(self, directory):
        case = fixture.PublicRunObservationTests()
        self.addCleanup(case.doCleanups)
        host, core, _, _ = case.host(Path(directory))
        client, execution = await case.start(host)
        self.addAsyncCleanup(client.aclose)
        run, projection, _, _ = case.publication(host, core, execution)
        def current():
            self.assertIsNotNone(core._journal_callbacks(host._configuration.current.ticket).reader)
        observation = SimpleNamespace(_projection=projection, _facts=(), _originals=(),
            _serialized_facts=nullcontext, _before_lookup=current, _validate_facts=lambda: None)
        host._store_observations[projection._publication.ticket] = observation
        store = host._installation._store
        key = store.namespaced_key('client_submitted_intents', submission_fixture.REQUEST)
        previous = core._call
        outputs, bounds, packets, calls, codes = {}, {}, {}, [], {}
        def actual():
            callbacks = core._journal_callbacks(host._configuration.current.ticket)
            self.assertIsNotNone(callbacks.reader)
            rows = []
            callbacks.reader.read('client_submitted_intents', submission_fixture.REQUEST,
                                  lambda row: rows.append(row[1]))
            return rows[0]
        def call(family, name, *args):
            if family == 'publication' and name in ('retire_observation', 'retire_lookup'):
                self.assertEqual(args, (projection._publication.handle,))
                self.assertTrue(all(ticket not in core._loans for ticket in outputs.values()))
                return 0
            if family == 'publication_commit_export' and name in ('reserve', 'reserve_bounded'):
                self.assertEqual(args[0], projection._publication.handle)
                if name == 'reserve_bounded' and args[2] > 1 and 'reserve_body' in codes:
                    return codes['reserve_body']
                handle = 4000000 + args[1]
                outputs[handle] = args[1]
                if name == 'reserve_bounded':
                    bounds[handle] = args[2]
                return handle
            if family == 'publication_commit_export' and args[0] in outputs:
                handle = args[0]
                calls.append(name)
                if name == 'measure_sdk_run_state':
                    self.assertEqual((args[1], args[3]), (run.handle, host._configuration.handle))
                    self.assertEqual(bounds[handle], 1)
                    if 'during_produce' in codes:
                        codes['during_produce']()
                    row = actual()
                    packets[handle] = wire_bytes({'kind': 'retained' if row.payload == SAVED_STATE else 'replace',
                        'key': submission_fixture.REQUEST, 'revision': str(row.generation),
                        'body': SAVED_STATE.decode(), 'state': wire_bytes(fixture.STATE).decode()})
                    return codes.get(name, len(packets[handle]))
                if name == 'emit_sdk_run_state':
                    self.assertEqual(args[2], host._configuration.handle)
                    self.assertEqual(bounds[handle], len(packets[args[1]]))
                    packets[handle] = packets[args[1]]
                    return codes.get(name, 0)
                if name == 'validate_sdk_run_state':
                    actual()
                    return codes.get(name, 0)
                if name == 'confirm_sdk_run_state':
                    row = actual()
                    return codes.get(name, 0) if row.payload == SAVED_STATE else -35
                if name == 'length': return len(packets[handle])
                if name == 'close': return core._cleanup(outputs[handle])
            if family == 'buffer' and name == 'byte' and args[0] in packets:
                return packets[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        def observe(consume):
            InstalledLocalHost._project_original_sdk_run_state(host, run, projection, consume)
        return host, core, client, run, store, key, calls, codes, observe

    async def test_commit_confirm_and_same_original_reobservation_do_not_rewrite(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            before = store.read(key)
            states = []
            observe(lambda raw: states.append(json.loads(raw)))
            saved = store.read(key)
            self.assertEqual((saved.payload, saved.generation), (SAVED_STATE, before.generation + 1))
            self.assertEqual(states, [fixture.STATE])
            self.assertFalse(host._run_state_custody)
            observe(lambda raw: states.append(json.loads(raw)))
            self.assertEqual(store.read(key), saved)
            self.assertEqual(states, [fixture.STATE, fixture.STATE])
            self.assertEqual(calls.count('measure_sdk_run_state'), 2)
            self.assertEqual(calls.count('emit_sdk_run_state'), 2)
            self.assertEqual(calls.count('validate_sdk_run_state'), 1)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 2)
            self.assertIs(host._runs._runs[run.handle], run)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_lost_commit_reply_keeps_same_output_for_lookup_without_second_write(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, _, observe = await self.bridge(directory)
            original = store.compare_exchange_many_inspected
            def lose(*args, **kwargs):
                original(*args, **kwargs)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose) as write:
                with self.assertRaises(LocalStorageCommitUnknown): observe(lambda _: self.fail('Unknown state escaped'))
            held = host._run_state_custody[run.handle]
            self.assertTrue(held.write_attempted)
            self.assertIs(core._loans[held.output.ticket], held.output)
            committed = store.read(key)
            states = []
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=AssertionError('Metadata write replay')):
                observe(lambda raw: states.append(json.loads(raw)))
            self.assertEqual(store.read(key), committed)
            self.assertEqual(states, [fixture.STATE])
            self.assertEqual(write.call_count, 1)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            self.assertFalse(host._run_state_custody)
            await client.aclose()

    async def test_measured_state_reservation_refusal_keeps_prepared_owner_and_skips_cas(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, codes, observe = await self.bridge(directory)
            before = store.read(key)
            codes['reserve_body'] = -4
            with self.assertRaises(LocalCoreError) as refusal:
                observe(lambda _: self.fail('Refused body reached the consumer'))
            self.assertEqual(refusal.exception.code, -4)
            held = host._run_state_custody[run.handle]
            self.assertIsNotNone(held.output)
            self.assertIs(core._loans[held.output.ticket], held.output)
            self.assertIsNone(held.body_output)
            self.assertFalse(held.write_attempted)
            self.assertEqual(store.read(key), before)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            self.assertNotIn('emit_sdk_run_state', calls)
            codes.clear()
            with self.assertRaises(LocalProductCleanupPending):
                observe(lambda _: self.fail('Retried original state preparation'))
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_prior_row_refusal_keeps_original_without_write_or_replay(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, codes, observe = await self.bridge(directory)
            before = store.read(key)
            codes['validate_sdk_run_state'] = -35
            with self.assertRaises(LocalCoreError): observe(lambda _: self.fail('Refused state escaped'))
            held = host._run_state_custody[run.handle]
            source, output = held.source, held.output
            self.assertEqual(store.read(key), before)
            codes.clear()
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=AssertionError('Metadata write replay')):
                with self.assertRaises(LocalCoreError): observe(lambda _: self.fail('Uncommitted state escaped'))
            self.assertIs(host._run_state_custody[run.handle], held)
            self.assertIs(core._loans[source.ticket], source)
            self.assertIs(core._loans[output.ticket], output)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_confirm_refusal_retries_only_same_committed_observation(self):
        with TemporaryDirectory() as directory:
            host, core, client, run, store, key, calls, codes, observe = await self.bridge(directory)
            codes['confirm_sdk_run_state'] = -35
            with self.assertRaises(LocalCoreError): observe(lambda _: self.fail('Unconfirmed state escaped'))
            held = host._run_state_custody[run.handle]
            committed = store.read(key)
            self.assertIs(core._loans[held.output.ticket], held.output)
            codes.clear()
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=AssertionError('Metadata write replay')):
                observe(lambda _: None)
            self.assertEqual(store.read(key), committed)
            self.assertEqual(calls.count('measure_sdk_run_state'), 1)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 2)
            await client.aclose()

    async def test_same_callback_cannot_close_parent_during_actual_state_operation(self):
        with TemporaryDirectory() as directory:
            host, core, client, _, _, _, _, codes, observe = await self.bridge(directory)
            results = []
            def reenter():
                results.append(host.close())
                self.assertFalse(host._closing)
                self.assertTrue(host._state_observing)
            codes['during_produce'] = reenter
            observe(lambda _: None)
            self.assertEqual(results, [False])
            self.assertFalse(host._state_observing)
            self.assertFalse(host._run_state_custody)
            await client.aclose()
            self.assertTrue(core._closed)

    async def test_retained_state_at_maximum_sql_generation_needs_no_successor(self):
        with TemporaryDirectory() as directory:
            _, _, client, _, store, key, calls, _, observe = await self.bridge(directory)
            store._connection.execute('UPDATE core_bytes SET generation=?,payload=? WHERE key=?',
                                      (2**63 - 1, SAVED_STATE, key))
            before = store.read(key)
            states = []
            with patch.object(store, 'compare_exchange_many_inspected',
                              side_effect=AssertionError('Retained metadata was rewritten')):
                observe(lambda raw: states.append(json.loads(raw)))
            self.assertEqual(store.read(key), before)
            self.assertEqual(states, [fixture.STATE])
            self.assertNotIn('validate_sdk_run_state', calls)
            self.assertEqual(calls.count('confirm_sdk_run_state'), 1)
            await client.aclose()

    async def test_original_observation_callback_cannot_close_parent_before_produce(self):
        with TemporaryDirectory() as directory:
            host, core, client, _, _, _, _, _, observe = await self.bridge(directory)
            original = host._original_sdk_read_observation
            results = []
            def inspect(*args):
                results.append(host.close())
                self.assertTrue(host._state_observing)
                self.assertFalse(host._closing)
                return original(*args)
            with patch.object(host, '_original_sdk_read_observation', side_effect=inspect):
                observe(lambda _: None)
            self.assertEqual(results, [False])
            self.assertFalse(host._state_observing)
            await client.aclose()
            self.assertTrue(core._closed)


if __name__ == '__main__':
    unittest.main()
