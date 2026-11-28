"""Actual succeeded public execution/typed Result after worker-control changes.

Uses the existing source-free Local route with the selected platform image
and a real SQLite-backed Host. Installed wheel acceptance runs separately.
"""
import argparse
import asyncio
from contextlib import ExitStack
from dataclasses import dataclass
from importlib.util import module_from_spec, spec_from_file_location
import json
import os
import re
import sqlite3
from pathlib import Path
import sys
from tempfile import mkdtemp
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def fixture_arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('module')
    parser.add_argument('scratch', type=Path)
    parser.add_argument('mode', nargs='?',
        choices=('commit-unknown', 'task-drive-mixed', 'repeat-live-three', 'installed-commit-unknown'))
    parser.add_argument('--platform-artifact', type=Path)
    args = parser.parse_args()
    if args.mode == 'installed-commit-unknown':
        if args.platform_artifact is not None or re.fullmatch(r'[0-9a-f]{40}', args.module) is None:
            parser.error('The installed fixture requires the original source SHA without a platform artifact')
    elif args.platform_artifact is None:
        parser.error('The source fixture requires the original --platform-artifact')
    return args


ARGS = fixture_arguments()
INSTALLED = ARGS.mode == 'installed-commit-unknown'
if not INSTALLED:
    sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient, ClientError
from actql_sdk._local_core import LocalCore, LocalCoreError, _Output, _TaskDrive, _NORMAL_HOST_BOOTSTRAP_FUEL
from actql_sdk._local_distribution import _execution_component_platform, _read_file
from actql_sdk._local_engine import _InstalledImageInput, _checked_installed_image
from actql_sdk._local_product import InstalledLocalHost, _ordinary_core_limits
from actql_sdk._local_storage import LocalStorageCommitUnknown


@dataclass(frozen=True)
class Row:
    n: int

    @classmethod
    def model_validate(cls, value, *, strict):
        if strict is not True or type(value) is not dict or set(value) != {'n'} or type(value['n']) is not int:
            raise ValueError('Expected the original integer row contract')
        return cls(value['n'])


def selected_image(module: Path, artifact: Path) -> _InstalledImageInput:
    spec = spec_from_file_location('python_local_runtime_recipe',
        ROOT / 'scripts/prepare-python-local-runtime.py')
    if spec is None or spec.loader is None:
        raise ValueError('Original Python Local runtime recipe is unavailable')
    recipe = module_from_spec(spec)
    spec.loader.exec_module(recipe)
    components = recipe.verify_artifact(artifact,
        target_platform=_execution_component_platform())
    _read_file(module, maximum=32 * 1024 * 1024, digest=components.module_sha256)
    return _checked_installed_image(components)


def installed_identity(source):
    import actql
    import actql_sdk
    from actql_sdk._local_distribution import installed_local_components

    prefix = Path(sys.prefix).resolve()
    assert sys.prefix != sys.base_prefix, 'The installed fixture requires the selected virtual environment'
    assert all(Path(module.__file__).resolve().is_relative_to(prefix) for module in (actql, actql_sdk))
    assert actql.AsyncClient is AsyncClient, 'Installed public facade required'
    original = installed_local_components()
    assert original.source_sha == source, 'Foreign installed publication fixture source'
    return dict(source=source, module=original.module_sha256, image=original.image_sha256, pid=os.getpid())


def new_core(image: _InstalledImageInput) -> LocalCore:
    return LocalCore(None, digest=image.recipe.module_sha256, _compiled_image=image,
        _ordinary_host=True, transfer_capacity=12 * 1024 * 1024,
        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_BOOTSTRAP_FUEL)


def open_original(core: LocalCore, state: Path) -> InstalledLocalHost:
    with core._host_operation(initial=True):
        return InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
            observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)


class ParentReturnTrace:
    """Passive, fixed-three fixture observations of the original close ports.

    No constructor, retirement, Work wait or confirmation is supplied here.
    Each wrapper returns the actual original result unchanged.
    """
    def __init__(self, host, stack):
        self.host = host
        self.records = []
        accept = host._accept_original
        def observe_accept(*args, **kwargs):
            original, admission = accept(*args, **kwargs)
            assert original is not None and len(self.records) < 3
            run = original.run
            # This successful original call already ACK-closed its admission
            # Journal. With this fixture's sequential calls there is no other
            # Journal borrower at the accept/return boundary.
            with host._core._lock:
                journal_inventory = self.journal_inventory(run)
                assert not any(journal_inventory.values()), journal_inventory
            self.records.append({'original': original, 'run': run,
                'prepared': run.preparation, 'submission': original.submission,
                'rows_input': original.rows_input,
                'submission_input': host._append_sources[original.submission.ticket],
                'rows': next(value for owner, value in host._run_rows if owner is run),
                'journal_inventory_after_accept': journal_inventory,
                'acks': [], 'loans': {}})
            return original, admission
        stack.enter_context(patch.object(host, '_accept_original', side_effect=observe_accept))
        ports = ((host._runs, 'close_physical_start', 'start'),
            (host._core, 'close_material', 'material'),
            (host._runs, 'close_run', 'run'),
            (host._preparation, 'close_preparation', 'preparation'),
            (host, '_close_projection', 'submission'),
            (host._core, 'close_input', 'input'))
        for owner, name, kind in ports:
            method = getattr(owner, name)
            def observe(loan, *, method=method, kind=kind):
                selected = []
                for record in self.records:
                    original, run = record['original'], record['run']
                    candidates = {
                        'start': (('physical_start', original.physical_start),),
                        'material': (('start_step', original.start_step), ('rows', record['rows']),
                            ('binding', next((value for parent, value in host._publication_bindings
                                              if parent is run), None))),
                        'run': (('run', run),),
                        'preparation': (('preparation', record['prepared']),),
                        'submission': (('submission', record['submission']),),
                        'input': (('submission_input', record['submission_input']),
                            ('rows_input', record['rows_input']), ('run_input', run.input),
                            ('preparation_input', record['prepared'].input)),
                    }[kind]
                    for label, parent in candidates:
                        if loan is parent:
                            selected.append((record, label))
                result = method(loan)
                for record, label in selected:
                    record['acks'].append({'parent': label, 'returned': result is True})
                    record['loans'][label] = loan
                return result
            stack.enter_context(patch.object(owner, name, side_effect=observe))

    def journal_inventory(self, run):
        # The Host-current constructor intentionally retains journal callbacks
        # for the whole Host. Exclude only its actual nominal output tickets;
        # an unassociated Journal input still counts as retained here.
        current_tickets = {value.ticket for value in self.host._core._loans.values()
            if type(value) is _Output and value.family == 'current'}
        return {
            'host_selected_journal': run.handle in self.host._admission_observations,
            'host_journal_outputs': bool(self.host._journal_outputs),
            'core_journal_loans': any(type(value) is _Output and value.family == 'journal'
                for value in self.host._core._loans.values()),
            'core_journal_inputs': any(ticket not in current_tickets and value.journal is not None
                for ticket, value in self.host._core._inputs.items()),
        }

    def assert_returned(self, index):
        record = self.records[index]
        original, run, prepared = record['original'], record['run'], record['prepared']
        expected = {'physical_start', 'start_step', 'binding', 'rows', 'run',
            'preparation', 'submission', 'submission_input', 'rows_input', 'run_input',
            'preparation_input'}
        with self.host._core._lock:
            acks = record['acks']
            inventory = {
                'host_run': any(value is run for value in self.host._run_loans),
                'core_run': self.host._runs._runs.get(run.handle) is run,
                'host_preparation': any(value is prepared for value in self.host._prepared_inputs),
                'core_preparation': self.host._preparation._preparations.get(prepared.handle) is prepared,
                'host_submission': any(value is record['submission'] for value in self.host._projections),
                'host_work': any(work._invoke is original for work in self.host._physical_work),
                'selected_start': original.physical_start is not None,
                'selected_start_step': original.start_step is not None,
                **self.journal_inventory(run),
            }
            for label, source in (('submission_input', record['submission_input']),
                    ('rows_input', record['rows_input']), ('run_input', run.input),
                    ('preparation_input', prepared.input)):
                inventory['host_' + label] = any(value is source for value in self.host._inputs)
                inventory['core_' + label] = source.ticket in self.host._core._inputs
            observation = {'execution': index + 1, 'original_parent_acks': list(acks),
                'journal_inventory_after_accept': record['journal_inventory_after_accept'],
                'selected_parent_inventory_retained': inventory}
            print(json.dumps({'parent_return_before_host_close': observation}), file=sys.stderr)
            assert len(acks) == len(expected) and {item['parent'] for item in acks} == expected
            assert all(item['returned'] for item in acks)
            assert not any(inventory.values()), inventory
            assert original.physical_start is original.start_step is original.submission is original.rows_input is None
            return observation


async def main():
    args = ARGS
    commit_unknown = INSTALLED or args.mode == 'commit-unknown'
    task_drive = args.mode == 'task-drive-mixed'
    repeat_live = args.mode == 'repeat-live-three'
    trace = None
    if task_drive:
        from python_local_task_drive_trace import MixedTaskDriveTrace
        trace = MixedTaskDriveTrace()
    def phase(name):
        if trace is not None:
            trace.mark(name)
    phase('fixture-start')
    expected_n = 2 if task_drive else 41
    identity = installed_identity(args.module) if INSTALLED else None
    image = None if INSTALLED else selected_image(Path(args.module), args.platform_artifact)
    digest = identity['module'] if INSTALLED else image.recipe.module_sha256
    args.scratch.mkdir(parents=True, exist_ok=True)
    state = Path(mkdtemp(prefix='succeeded-', dir=args.scratch))
    phase('first-core-begin')
    core = host = client = primary = None
    driver_checks = ExitStack()
    driven = {}
    try:
        if INSTALLED:
            client = await AsyncClient.open(state_dir=state)
            host = client._local_host
            core = host._core
            assert core._installed_image_sha256 == identity['image'], 'Foreign live publication image'
            phase('first-core-ready')
        else:
            core = new_core(image)
            phase('first-core-ready')
            host = open_original(core, state)
            client = await AsyncClient._connect_local(host)
        phase('first-host-ready')
        parent_trace = ParentReturnTrace(host, driver_checks) if repeat_live else None
        parent_observations = []
        references = []
        if task_drive:
            original_drive = core.drive_task_step
            def scheduled_original_quantum(task, quantum):
                reader = host._installation.binding._observed_reader
                assert reader is not None and core._task_loans[task.handle] is task
                assert any(original is task for original in host._tasks)
                counts = driven.setdefault(task.handle, [0, 0, 0, 0])
                assert counts[1] == 0  # No normal call re-drives a completed task.
                assert quantum == 256
                # A deterministic TEST input schedule, never a runtime fallback
                # on failure, fuel, progress or a Host-selected task phase.
                selected_quantum = 1 if counts[0] < 8 else 256
                before_code = core._call('task', 'progress', task.handle, 0)
                before_progress = (core._call('task', 'progress', task.handle, 2)
                                   if before_code >= 0 else None)
                before = core._store.get_fuel()
                outcome = original_drive(task, selected_quantum)
                assert outcome in (_TaskDrive.PROGRESSED, _TaskDrive.COMPLETE)
                complete = outcome is _TaskDrive.COMPLETE
                assert core._store.get_fuel() <= before
                after_code = core._call('task', 'progress', task.handle, 0)
                after_progress = (core._call('task', 'progress', task.handle, 2)
                                  if after_code >= 0 else None)
                assert before_code in (-33, 0, 1) and after_code in (-33, 0, 1)
                if before_progress is not None and after_progress is not None:
                    assert 0 <= before_progress <= after_progress
                if after_code == -33:
                    assert before_code in (-33, 1)
                    counts[3] += int(before_code == 1)
                if complete:
                    assert before_code == after_code == 1 and counts[3] == 1
                assert host._installation.binding._observed_reader is reader
                assert core._task_loans[task.handle] is task
                counts[0] += 1
                counts[1] += int(complete)
                counts[2] += int(selected_quantum == 1)
                return outcome
            driver_checks.enter_context(patch.object(core, 'drive_task_step', side_effect=scheduled_original_quantum))
            for method in ('start_task', 'feed_task', 'advance_task',
                           'prepare_task_finalization', 'complete_task'):
                driver_checks.enter_context(patch.object(core, method,
                    side_effect=AssertionError('Python reconstructed the original task lifecycle')))
        store = host._installation._store
        original_store = store.store_publication_projected_inspected
        atomic_observations = []
        publication_writes = []
        publication_loss = []
        reissued = []
        lost_reply = LocalStorageCommitUnknown(store)
        def observe_original_transaction(*args, before_commit, **kwargs):
            pending = host._pending_publication_write
            original_publication = pending is not None and getattr(args[1], '__self__', None) is pending
            if original_publication:
                publication_writes.append(pending)
            def fenced_original_commit():
                assert store._connection.in_transaction
                peer = sqlite3.connect(store._physical_path.as_uri() + '?mode=rw',
                    uri=True, timeout=0, isolation_level=None)
                try:
                    try:
                        peer.execute('BEGIN IMMEDIATE')
                    except sqlite3.OperationalError as error:
                        assert error.sqlite_errorcode & 0xff in (sqlite3.SQLITE_BUSY, sqlite3.SQLITE_LOCKED)
                    else:
                        peer.rollback()
                        raise AssertionError('Final publication validation did not exclude another SQLite writer')
                finally:
                    peer.close()
                before_commit()
                assert store._connection.in_transaction
                atomic_observations.append(True)
            result = original_store(*args, before_commit=fenced_original_commit, **kwargs)
            if commit_unknown and original_publication:
                assert len(publication_writes) == 1
                assert not store._connection.in_transaction
                publication_loss.append({'sqliteTransactionOpen': store._connection.in_transaction})
                raise lost_reply  # Actual SQLite COMMIT returned; only its reply is lost.
            return result
        with patch.object(store, 'store_publication_projected_inspected', side_effect=observe_original_transaction) as commit_calls:
            for execution_index in range(3 if repeat_live else 1):
                phase('execution-begin')
                execution = await client.start_source(
                    ('WITH seed AS (SELECT 1 AS n) FROM seed AS l |> JOIN seed AS r ON l.n = r.n '
                     'MAX_OUTPUT_ROWS 1 |> SELECT l.n + r.n AS n |> RESULT answer' if task_drive else
                     'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer'), format='aql')
                phase('submission-returned')
                if repeat_live:
                    print(json.dumps({'live_execution_started': execution_index + 1,
                        'original_ref_before_wait': dict(execution.ref)}), file=sys.stderr)
                if commit_unknown:
                    assert len(host._physical_work) == 1
                    work = host._physical_work[0]
                    await work.wait_stopped()
                    assert work._future.exception() is lost_reply and work._exit_error is None
                    retained = host._pending_publication_write
                    assert retained is publication_writes[0] and retained in host._commit_projections
                    assert host._pending_publication_publisher is not None and core._compute_loans
                    original_call = core._call
                    def only_lookup(family, name, *args):
                        if family in ('program', 'run', 'compute', 'task'):
                            reissued.append((family, name))
                            raise AssertionError('Uncertain publication lookup reissued execution')
                        return original_call(family, name, *args)
                    with patch.object(core, '_call', side_effect=only_lookup):
                        final = (await execution.wait(until='terminal')).to_dict()
                    assert host._pending_publication_write is None
                    publication_loss[0].update(retainedOriginal=retained is publication_writes[0],
                        sameUnknown=work._future.exception() is lost_reply, outcome=type(lost_reply).__name__)
                else:
                    final = (await execution.wait(until='terminal')).to_dict()
                phase('terminal-returned')
                assert final['status'] == 'succeeded' and final['result_available']
                live_result = await execution.result('answer').all(schema=Row, max_rows=2)
                assert live_result == [Row(n=expected_n)]
                assert (await execution.status()).to_dict() == final
                phase('result-checked')
                reference = dict(execution.ref)
                assert len(publication_writes) == execution_index + 1
                if repeat_live:
                    assert len(parent_trace.records) == execution_index + 1
                    parent_observations.append(parent_trace.assert_returned(execution_index))
                    assert reference not in references
                    references.append(reference)
        # Result delivery evidence uses this SAME physical primitive too.
        # Every observed final validation must exclude another writer; an
        # arbitrary private callback count is not a publication contract.
        assert atomic_observations and commit_calls.call_count == len(atomic_observations)
        if task_drive:
            assert len(driven) >= 2 and all(calls > 8 and completed == 1 and small == 8 and phases == 1
                                          for calls, completed, small, phases in driven.values())
    except BaseException as error:
        primary = error
        if isinstance(error, ClientError):
            print(json.dumps({'publicFailure': error.code}), file=sys.stderr)
        if host is not None:
            for work in host._physical_work:
                if work._future.done() and not work._future.cancelled():
                    failure = work._future.exception()
                    if isinstance(failure, LocalCoreError):
                        print(json.dumps({'originalWorkerFailure': failure.operation,
                                          'code': failure.code}), file=sys.stderr)
        raise
    finally:
        driver_checks.close()
        phase('first-cleanup-begin')
        try:
            original_close = None if core is None else core.close_task
            def observe_task_close(task):
                before = core.task_cleanup_continuation(task)
                result = original_close(task)
                if not result:
                    print(json.dumps({'pendingTaskRetirement': {
                        'before': before, 'after': core.task_cleanup_continuation(task),
                        'progress': core._call('task', 'progress', task.handle, 4),
                        'issue': core._call('task', 'issue', task.handle)}}), file=sys.stderr)
                return result
            if client is not None:
                with patch.object(core, 'close_task', side_effect=observe_task_close):
                    await client.aclose()
                assert core._closed
            if host is not None and not INSTALLED:
                await host.aclose()
            elif host is None and core is not None and not core.close():
                raise AssertionError('Original succeeded Core close remains pending')
        except BaseException:
            if host is not None:
                print(json.dumps({'retainedCleanup': {name: len(getattr(host, name)) for name in (
                    '_response_streams', '_commit_projections', '_sdk_read_evidence', '_sdk_deliveries',
                    '_store_observations', '_payloads', '_publications', '_result_exports', '_tasks',
                    '_source_free_invocations', '_source_free_computes', '_run_loans')}}), file=sys.stderr)
            if primary is None:
                raise
            print('Original succeeded-path failure retained; physical cleanup remains pending', file=sys.stderr)
    assert core._closed
    phase('first-cleanup-returned')

    if repeat_live:
        assert len(references) == len(parent_observations) == 3
        print(json.dumps({'success': True, 'actualCases': 1,
            'case': 'public_three_live_successes_original_parent_returns_and_first_close',
            'module_sha256': digest, 'image_sha256': image.sha256, 'state': str(state),
            'completed_distinct_executions': len(references),
            'same_live_host': True, 'first_core_closed': core._closed,
            'atomic_precommit_writer_exclusion': True,
            'parent_returns': parent_observations,
            'qualification': 'actual source SDK/selected platform image/SQLite; not normal distribution, bare-wait population, warm100 or performance'}))
        return

    # The old manifested Saved path remains executable-read free. No cancelled
    # state, absent Manifest or replacement invocation substitutes for success.
    phase('saved-core-begin')
    reopened = saved_host = saved_client = None
    try:
        if INSTALLED:
            saved_client = await AsyncClient.open(state_dir=state)
            saved_host = saved_client._local_host
            reopened = saved_host._core
            assert reopened._installed_image_sha256 == identity['image'], 'Foreign Saved publication image'
            phase('saved-core-ready')
        else:
            reopened = new_core(image)
            phase('saved-core-ready')
            saved_host = open_original(reopened, state)
            saved_client = await AsyncClient._connect_local(saved_host)
        phase('saved-host-ready')
        original_call = reopened._call

        def only_saved(family, name, *args):
            if family in ('program', 'run', 'compute', 'task'):
                reissued.append((family, name))
                raise AssertionError('Succeeded Saved read reissued execution')
            return original_call(family, name, *args)

        with patch.object(reopened, '_call', side_effect=only_saved):
            phase('saved-read-begin')
            saved = await saved_client.attach(reference)
            saved_reference = dict(saved.ref)
            assert saved_reference == reference
            saved_state = (await saved.status()).to_dict()
            assert saved_state == final
            saved_result = await saved.result('answer').all(schema=Row, max_rows=2)
            assert saved_result == [Row(n=expected_n)]
            phase('saved-read-checked')
    finally:
        phase('saved-cleanup-begin')
        if saved_client is not None:
            await saved_client.aclose()
            assert reopened._closed
        if saved_host is not None and not INSTALLED:
            await saved_host.aclose()
        elif saved_host is None and reopened is not None and not reopened.close():
            raise AssertionError('Saved succeeded Core close remains pending')
    assert reopened._closed
    phase('saved-cleanup-returned')
    if INSTALLED:
        print(json.dumps({**identity, 'boundary': {'protocol': {
            'kind': 'installed-python-publication-reply-loss/1', 'facade': 'AsyncClient', 'resultName': 'answer',
            'fixture': 'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer'}},
            'publication': publication_loss, 'originalPublicationWrites': len(publication_writes),
            'atomicPrecommitObservations': len(atomic_observations), 'reissued': reissued,
            'originalRun': reference, 'savedRun': saved_reference, 'terminal': final['status'],
            'savedTerminal': saved_state['status'], 'liveResult': [{'n': row.n} for row in live_result],
            'savedResult': [{'n': row.n} for row in saved_result], 'firstClose': core._closed,
            'savedClose': reopened._closed}))
        return
    print(json.dumps({'success': True, 'actualCases': 1,
        'case': ('public_core_derived_task_drive_mixed_quanta_joined_result_same_saved' if task_drive else
                 'public_commit_reply_loss_original_lookup_same_result_without_reexecution' if commit_unknown else
                 'public_succeeded_execute_typed_result_same_saved_and_close'),
        'module_sha256': digest, 'image_sha256': image.sha256, 'state': str(state),
        'first_core_closed': True, 'saved_first_core_closed': True,
        'atomic_precommit_writer_exclusion': True,
        'commit_reply_loss_readback_without_reexecution': commit_unknown,
        **({'core_owned_lifecycle': True, 'initial_quantum': 1, 'initial_drives_per_task': 8,
            'continuation_quantum': 256, 'original_tasks': len(driven),
            'actual_initial_quantum_drives': sum(counts[2] for counts in driven.values()),
            'observed_phase_transitions': sum(counts[3] for counts in driven.values()),
            'monotonic_progress': True} if task_drive else {}),
        'qualification': 'actual source SDK/selected platform image/SQLite; no installed normal package acceptance'}))


asyncio.run(main())
