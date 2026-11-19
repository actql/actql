"""Real same-Store CAS with scalar Core, not physical Wasm/start admission."""
import copy
import asyncio
import importlib.util
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
import sys
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError, _Input, _Output, _PhysicalInput, _Workspace
from actql_sdk._local_journal_port import _JournalCallbacks
from actql_sdk._local_product import InstalledLocalHost, _OriginalExecution
from actql_sdk._local_work import OriginalLocalWork
from actql_sdk._local_storage import LocalByteStore, LocalStorageCommitUnknown, LocalStorageError
import test_local_finite_run as fixture
import test_local_submission_append as append_fixture
from local_abi_declaration_fixture import original_byte_fixture_port

BINDING = b'{"opaque":"original Core publication binding e\xcc\x81/~","null":null}'
DISPATCH = b'{"opaque":"original Core dispatch e\xcc\x81/~","null":null}'
CLAIM = b'{"opaque":"original Core physical claim e\xcc\x81/~","null":null}'


class SDKStartAssemblyTests(unittest.TestCase):
    def test_imported_three_live_journal_census_handles_mixed_loans_and_current(self):
        source = Path(__file__).resolve().parents[3] / 'scripts/fixtures/python-local-public-success-abi.py'
        spec = importlib.util.spec_from_file_location('original_three_live_fixture', source)
        module = importlib.util.module_from_spec(spec)
        with patch.object(sys, 'path', [str(source.parent), *sys.path]), patch.object(
                asyncio, 'run', side_effect=lambda coroutine: coroutine.close()):
            spec.loader.exec_module(module)
        with TemporaryDirectory() as directory:
            store = LocalByteStore(Path(directory) / 'census.sqlite', max_records=8,
                max_record_bytes=8192, max_payload_bytes=65536)
            try:
                owner = object()
                current = _Output(owner, 3, 30, 64, 'current')
                callbacks = _JournalCallbacks(lambda: None, store)
                current_input = _PhysicalInput(b'', lambda: True, lambda _: True, journal=callbacks)
                core = SimpleNamespace(
                    _loans={1: _Input(owner, 1, 10, 1),
                        2: _Workspace(owner, 2, 20), 3: current},
                    _inputs={3: current_input})
                host = SimpleNamespace(_core=core, _admission_observations={}, _journal_outputs=[])
                observer = object.__new__(module.ParentReturnTrace)
                observer.host = host
                run = SimpleNamespace(handle=50)
                self.assertFalse(any(observer.journal_inventory(run).values()))
                journal = _Output(owner, 4, 40, 64, 'journal')
                core._loans[4] = journal
                core._inputs[4] = _PhysicalInput(b'', lambda: True, lambda _: True, journal=callbacks)
                inventory = observer.journal_inventory(run)
                self.assertTrue(inventory['core_journal_loans'])
                self.assertTrue(inventory['core_journal_inputs'])
                del core._loans[4]
                inventory = observer.journal_inventory(run)
                self.assertFalse(inventory['core_journal_loans'])
                self.assertTrue(inventory['core_journal_inputs'])  # Orphan remains visible.
                del core._inputs[4]
                self.assertFalse(any(observer.journal_inventory(run).values()))
                # Only an actual original _Output can exempt a current ticket.
                core._loans[3] = SimpleNamespace(ticket=3, family='current')
                self.assertTrue(observer.journal_inventory(run)['core_journal_inputs'])
                core._loans[3] = current
                self.assertIs(core._inputs[3], current_input)
                self.assertIs(core._loans[3], current)
            finally:
                store.close()

    def test_post_current_failure_after_start_reserve_keeps_both_original_inventories(self):
        originals = []
        initialize = _OriginalExecution.__init__
        def init(original, *args, **kwargs):
            initialize(original, *args, **kwargs)
            originals.append(original)
        with TemporaryDirectory() as directory:
            with patch.object(_OriginalExecution, '__init__', init):
                host, core, run, events, _ = self.host(Path(directory))
            original = originals[0]
            original.reference = host._register_original_run_reference(run,
                host._read_original_saved_admission(run))
            binding = host._installation.binding
            current = binding._physical_current
            primary = RuntimeError('Original post-consume current refusal')
            def post_current():
                current()
                if host._runs._starts:
                    raise primary
            work = OriginalLocalWork(original, on_exit=core._finish_work_operation, owner=run)
            host._physical_work.append(work)
            try:
                with patch.object(binding, '_physical_current', side_effect=post_current), patch.object(
                        InstalledLocalHost, '_execute_original_admitted_run',
                        lambda receiver, selected: receiver._configure_original_compute(selected)):
                    core._retain_work_operation(work)
                    work.start()
                    work._thread.join(2)
                    self.assertTrue(work.stopped)
                self.assertIs(work._future.exception(), primary)
                self.assertEqual(len(host._runs._starts), 1)
                start = next(iter(host._runs._starts.values()))
                self.assertIs(original.physical_start, start)
                self.assertIn(start, host._physical_starts)
                self.assertNotIn(('run', 'confirm_physical_start'), events)
                self.assertFalse(host._source_free_computes)
                self.assertTrue(host.close())
                self.assertFalse(host._runs._starts)
            finally:
                # Fixture-only teardown also returns the original loan on a
                # failing pre-fix assertion; no production repair is inserted.
                if work.stopped:
                    for start in tuple(host._runs._starts.values()):
                        if host._runs.close_physical_start(start):
                            if start in host._physical_starts:
                                host._physical_starts.remove(start)
                host.close()

    def test_real_active_cancellation_fixture_forwards_same_nominal_run_in_both_modes(self):
        source = Path(__file__).resolve().parents[3] / 'scripts/fixtures/python-local-active-task-cancellation-abi.py'
        spec = importlib.util.spec_from_file_location('original_active_task_fixture', source)
        module = importlib.util.module_from_spec(spec)
        # Import the actual callable without running its CLI. No source slice
        # or reconstructed function; the coroutine is simply never entered.
        with patch.object(asyncio, 'run', side_effect=lambda coroutine: coroutine.close()):
            spec.loader.exec_module(module)
        class ReachedOriginalRunBoundary(RuntimeError):
            pass
        for mode in (None, 'active-provider'):
            with self.subTest(mode=mode), TemporaryDirectory() as directory:
                originals = []
                initialize = _OriginalExecution.__init__
                def init(original, *args, **kwargs):
                    initialize(original, *args, **kwargs)
                    originals.append(original)
                with patch.object(_OriginalExecution, '__init__', init):
                    host, core, run, _, _ = self.host(Path(directory))
                original = originals[0]
                admission = host._read_original_saved_admission(run)
                selected = []
                def compute(actual):
                    host._runs._run(actual)  # Actual nominal guard, not duck typing.
                    self.assertIs(actual, run)
                    selected.append(actual)
                    raise ReachedOriginalRunBoundary()
                raw = Path(directory) / 'source-port.wasm'
                raw.write_bytes(b'\0asm\x01\0\0\0')
                argv = [str(source), str(raw), str(Path(directory) / 'fresh-cli-state')]
                if mode is not None:
                    argv.append(mode)
                # Explicit constructor/admission ports for the imported CLI
                # caller only. No engine, raw provider or cancellation runs.
                with patch.object(module, 'LocalCore', return_value=core), patch.object(
                        module, 'InstalledLocalHost', return_value=host), patch.object(
                        host, '_accept_original', return_value=(original, admission)), patch.object(
                        host, '_configure_original_compute', side_effect=compute), patch.object(sys, 'argv', argv):
                    with self.assertRaises(ReachedOriginalRunBoundary):
                        asyncio.run(module.main())
                self.assertEqual(selected, [run])
                self.assertTrue(core._closed)

    def test_same_execution_retains_start_and_step_before_original_callbacks(self):
        originals = []
        initialize = _OriginalExecution.__init__
        def init(original, *args, **kwargs):
            initialize(original, *args, **kwargs)
            originals.append(original)
        with TemporaryDirectory() as directory:
            with patch.object(_OriginalExecution, '__init__', init):
                host, core, run, _, _ = self.host(Path(directory))
            self.assertEqual(len(originals), 1)
            original = originals[0]
            self.assertIs(original.run, run)
            self.assertIsNone(original.reference)
            original.reference = host._register_original_run_reference(run,
                host._read_original_saved_admission(run))
            previous = core._call
            observed = []
            def before_callback(family, name, *args):
                if (family, name) == ('material', 'produce') and original.start_step is not None:
                    self.assertEqual(args, (original.start_step.handle,))
                    self.assertIs(core._loans[original.start_step.ticket], original.start_step)
                    observed.append('step')
                if (family, name) == ('run', 'confirm_physical_start'):
                    self.assertIs(original.physical_start, host._physical_starts[-1])
                    self.assertIs(original.physical_start.run, run)
                    self.assertEqual(args, (original.physical_start.handle,))
                    observed.append('start')
                return previous(family, name, *args)
            work = OriginalLocalWork(original, on_exit=core._finish_work_operation, owner=run)
            host._physical_work.append(work)
            with patch.object(core, '_call', side_effect=before_callback), patch.object(
                    InstalledLocalHost, '_execute_original_admitted_run',
                    lambda receiver, selected: receiver._configure_original_compute(selected)):
                core._retain_work_operation(work)
                work.start()
                work._thread.join(2)
                self.assertTrue(work.stopped)
                work._future.result(timeout=0)
            self.assertEqual(observed, ['step', 'start'])
            self.assertIs(original.physical_start, original.compute.start)
            self.assertTrue(host.close())

    def host(self, path):
        host, core, _, _ = fixture.FiniteRunAssemblyTests().assembly(path)
        reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original'}
        execution, _ = host._accept_original(reference, append_fixture.INTENT, run_id='original-run')
        run = execution.run
        self.addCleanup(host.close)
        previous = core._call
        kinds, candidates = {}, {}
        events = []
        failures = {}
        def actual():
            reader = core._journal_callbacks(host._configuration.current.ticket).reader
            self.assertIsNotNone(reader)
            values = []
            reader.read('client_runs', fixture.RUN_KEY, lambda row: values.append(row))
            self.assertEqual(len(values), 1)
            return values[0][1]
        def call(family, name, *args):
            if family == 'material' and name == 'reserve':
                self.assertEqual(args[0], run.handle)
                self.assertIn(args[1], (9, 5, 7, 8))
                handle = 100 + args[2]
                kinds[handle] = args[1]
                return handle
            if family == 'material' and args[0] in kinds:
                handle = args[0]
                kind = kinds[handle]
                before, after, revision = ((fixture.RUN_BODY, BINDING, 0) if kind == 9 else
                    (BINDING, DISPATCH, 1) if kind == 7 else (DISPATCH, CLAIM, 2))
                events.append((kind, name))
                code = failures.get((kind, name))
                if isinstance(code, BaseException): raise code
                if code is not None: return code
                if kind == 5:
                    if name == 'produce':
                        self.assertEqual((actual().payload, actual().generation), (BINDING, 1))
                        return 0
                    if name == 'close': return core._cleanup(handle - 100)
                    raise AssertionError((kind, name))
                if name == 'produce':
                    row = actual()
                    self.assertEqual((row.payload, row.generation), (before, revision))
                    candidates[handle] = json.dumps({'kind': 'publication' if kind == 9 else 'dispatch' if kind == 7 else 'claim',
                        'key': fixture.RUN_KEY, 'revision': str(revision), 'body': after.decode()},
                        ensure_ascii=False).encode()
                    return 0
                if name in ('validate_sdk_start', 'validate_sdk_publication'):
                    row = actual()
                    return 0 if (row.payload, row.generation) == (before, revision) else -35
                if name in ('confirm_sdk_start', 'confirm_sdk_publication'):
                    row = actual()
                    return 0 if (row.payload, row.generation) == (after, revision + 1) else -35
                if name == 'length': return len(candidates[handle])
                if name in ('retire_output', 'close'): return core._cleanup(handle - 100)
            if family == 'buffer' and name == 'byte' and args[0] in candidates:
                return candidates[args[0]][args[1]]
            if family == 'run' and name in ('reserve_sdk_physical_start', 'confirm_physical_start',
                                            'physical_start_ready', 'close_physical_start'):
                events.append(('run', name))
                if name != 'close_physical_start':
                    self.assertEqual((actual().payload, actual().generation), (CLAIM, 3))
                if name == 'reserve_sdk_physical_start': return 1500000
                return 0
            if family == 'compute' and name in ('reserve_source_free', 'configure_source_free', 'configured', 'close'):
                events.append(('compute', name))
                if name == 'reserve_source_free': return 1600000
                return 0
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return host, core, run, events, failures

    def row(self, host):
        store = host._installation._store
        return store.read(store.namespaced_key('client_runs', fixture.RUN_KEY))

    def test_original_dispatch_and_claim_are_saved_before_compute_configuration(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, events, _ = self.host(Path(directory))
            compute = host._configure_original_compute(run)
            self.assertEqual((self.row(host).payload, self.row(host).generation), (CLAIM, 3))
            self.assertEqual(events.count((7, 'confirm_sdk_start')), 1)
            self.assertEqual(events.count((8, 'confirm_sdk_start')), 1)
            self.assertIs(compute.start.run, run)
            self.assertIs(compute.start.input, run.input)
            self.assertIs(host._source_free_computes[0], compute)
            self.assertLess(events.index((8, 'confirm_sdk_start')), events.index(('run', 'reserve_sdk_physical_start')))
            self.assertLess(events.index(('run', 'physical_start_ready')), events.index(('compute', 'configure_source_free')))
            self.assertFalse(any(name in ('advance', 'prepare_invocation', 'start_task') for _, name in events))
            # Both consumed outputs are gone physically; original Core loans
            # stay reachable until the same Compute/start/material cleanup.
            self.assertNotIn(host._step_outputs[0].ticket, core._inputs)
            self.assertIs(core._loans[host._step_outputs[0].ticket], host._step_outputs[0])
            self.assertTrue(host.close())

    def test_original_normalization_is_produced_and_retired_before_dispatch(self):
        with TemporaryDirectory(prefix='actql-sdk-normalization-') as directory:
            host, _, run, events, _ = self.host(Path(directory))
            host._configure_original_compute(run)
            self.assertEqual(events.count((5, 'produce')), 1)
            self.assertEqual(events.count((5, 'close')), 1)
            self.assertLess(events.index((9, 'confirm_sdk_publication')), events.index((5, 'produce')))
            self.assertLess(events.index((5, 'close')), events.index((7, 'produce')))
            self.assertFalse(any(name in ('validate_sdk_start', 'confirm_sdk_start')
                                 for kind, name in events if kind == 5))
            self.assertTrue(host.close())

    def test_original_normalization_failure_keeps_same_loan_without_dispatch(self):
        with TemporaryDirectory(prefix='actql-sdk-normalization-') as directory:
            host, core, run, events, failures = self.host(Path(directory))
            failures[5, 'produce'] = -34
            with self.assertRaises(LocalCoreError): host._configure_original_compute(run)
            output = host._step_outputs[0]
            self.assertIs(core._loans[output.ticket], output)
            self.assertEqual(events.count((5, 'produce')), 1)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))
            self.assertEqual((self.row(host).payload, self.row(host).generation), (BINDING, 1))
            self.assertTrue(host.close())

    def test_normalization_transport_pending_keeps_same_cleanup_before_dispatch(self):
        with TemporaryDirectory(prefix='actql-sdk-normalization-') as directory:
            host, core, run, events, failures = self.host(Path(directory))
            failures[5, 'close'] = -9
            from actql_sdk._local_product import LocalProductCleanupPending
            with self.assertRaises(LocalProductCleanupPending): host._configure_original_compute(run)
            output = host._step_outputs[0]
            self.assertIs(core._loans[output.ticket], output)
            self.assertFalse(host.close())
            self.assertIs(host._step_outputs[0], output)
            self.assertFalse(any(kind in (7, 8, 'run', 'compute') for kind, _ in events))
            del failures[5, 'close']
            self.assertTrue(host.close())
            self.assertEqual(events.count((5, 'produce')), 1)

    def test_dispatch_commit_reply_loss_keeps_original_step_and_prevents_claim(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, events, _ = self.host(Path(directory))
            store = host._installation._store
            write = store.compare_exchange_many_inspected
            attempts = []
            def lose(*args, **kwargs):
                result = write(*args, **kwargs)
                if self.row(host).payload == BINDING: return result
                attempts.append(result)
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._configure_original_compute(run)
                with self.assertRaisesRegex(LocalStorageError, 'new Compute'):
                    host._configure_original_compute(run)
            self.assertEqual(len(attempts), 1)
            self.assertEqual(self.row(host).payload, DISPATCH)
            self.assertEqual(len(host._step_outputs), 1)
            self.assertIs(core._loans[host._pending_start_write.ticket], host._pending_start_write)
            self.assertFalse(any(kind in (8, 'run', 'compute') for kind, _ in events))

    def test_saved_claim_must_be_confirmed_before_start_or_compute(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, events, failures = self.host(Path(directory))
            failures[8, 'confirm_sdk_start'] = -41
            with self.assertRaises(LocalCoreError) as failure: host._configure_original_compute(run)
            self.assertEqual(failure.exception.code, -41)
            self.assertEqual(self.row(host).payload, CLAIM)
            self.assertIs(core._loans[host._pending_start_write.ticket], host._pending_start_write)
            self.assertFalse(any(kind in ('run', 'compute') for kind, _ in events))

    def test_changed_current_rejects_before_dispatch_write(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, _, run, events, failures = self.host(Path(directory))
            failures[7, 'validate_sdk_start'] = -32
            with self.assertRaises(LocalCoreError): host._configure_original_compute(run)
            self.assertEqual(self.row(host).payload, BINDING)
            self.assertFalse(any(name == 'confirm_sdk_start' for _, name in events))

    def test_foreign_run_copy_refuses_before_any_new_projection(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, _, run, events, _ = self.host(Path(directory))
            before = len(events)
            with self.assertRaises(ValueError): host._configure_original_compute(copy.copy(run))
            self.assertEqual(len(events), before)

    def test_retirement_failure_retains_same_claim_and_blocks_parent_cleanup(self):
        with TemporaryDirectory(prefix='actql-sdk-start-') as directory:
            host, core, run, _, failures = self.host(Path(directory))
            failures[8, 'retire_output'] = -9
            from actql_sdk._local_product import LocalProductCleanupPending
            with self.assertRaises(LocalProductCleanupPending): host._configure_original_compute(run)
            claim = host._step_outputs[0]
            self.assertIn(claim.ticket, core._inputs)
            self.assertIs(core._loans[claim.ticket], claim)
            self.assertEqual(len(host._physical_starts), 1)
            self.assertFalse(host._source_free_computes)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
