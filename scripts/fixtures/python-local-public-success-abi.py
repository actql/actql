"""Actual succeeded public execution/typed Result after worker-control changes.

Uses the unchanged source-free Local route and a real SQLite-backed Host. This
raw-module check does not qualify an installed package or a new Host profile.
"""
import asyncio
from contextlib import ExitStack
from dataclasses import dataclass
import hashlib
import json
import sqlite3
from pathlib import Path
import sys
from tempfile import mkdtemp
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient, ClientError
from actql_sdk._local_core import LocalCore, LocalCoreError, _NORMAL_HOST_OPERATION_FUEL
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


def new_core(raw, digest):
    return LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)


async def main():
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] not in ('commit-unknown', 'task-drive')):
        raise ValueError('Expected original module, fresh scratch and optional COMMIT-loss control')
    commit_unknown = len(sys.argv) == 4 and sys.argv[3] == 'commit-unknown'
    task_drive = len(sys.argv) == 4 and sys.argv[3] == 'task-drive'
    expected_n = 2 if task_drive else 41
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    scratch = Path(sys.argv[2]); scratch.mkdir(parents=True, exist_ok=True)
    state = Path(mkdtemp(prefix='succeeded-', dir=scratch))
    core = new_core(raw, digest)
    host = client = primary = None
    driver_checks = ExitStack()
    driven = {}
    try:
        host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
            observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        client = await AsyncClient._connect_local(host)
        if task_drive:
            original_drive = core.drive_task
            def one_original_quantum(task, quantum):
                reader = host._installation.binding._observed_reader
                assert reader is not None and core._task_loans[task.handle] is task
                assert any(original is task for original in host._tasks)
                before = core._store.get_fuel()
                complete = original_drive(task, 1)
                assert core._store.get_fuel() <= before
                assert host._installation.binding._observed_reader is reader
                assert core._task_loans[task.handle] is task
                counts = driven.setdefault(task.handle, [0, 0])
                assert counts[1] == 0  # No normal call re-drives a completed task.
                counts[0] += 1
                counts[1] += int(complete)
                return complete
            driver_checks.enter_context(patch.object(core, 'drive_task', side_effect=one_original_quantum))
            for method in ('start_task', 'feed_task', 'advance_task',
                           'prepare_task_finalization', 'complete_task'):
                driver_checks.enter_context(patch.object(core, method,
                    side_effect=AssertionError('Python reconstructed the original task lifecycle')))
        store = host._installation._store
        original_store = store.store_publication_projected_inspected
        atomic_observations = []
        publication_writes = []
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
                raise lost_reply  # Actual SQLite COMMIT returned; only its reply is lost.
            return result
        with patch.object(store, 'store_publication_projected_inspected', side_effect=observe_original_transaction) as commit_calls:
            execution = await client.start_source(
                ('WITH seed AS (SELECT 1 AS n) FROM seed AS l |> JOIN seed AS r ON l.n = r.n '
                 'MAX_OUTPUT_ROWS 1 |> SELECT l.n + r.n AS n |> RESULT answer' if task_drive else
                 'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer'), format='aql')
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
                        raise AssertionError('Uncertain publication lookup reissued execution')
                    return original_call(family, name, *args)
                with patch.object(core, '_call', side_effect=only_lookup):
                    final = (await execution.wait(until='terminal')).to_dict()
                assert host._pending_publication_write is None
            else:
                final = (await execution.wait(until='terminal')).to_dict()
            assert final['status'] == 'succeeded' and final['result_available']
            assert await execution.result('answer').all(schema=Row, max_rows=2) == [Row(n=expected_n)]
            assert (await execution.status()).to_dict() == final
            reference = dict(execution.ref)
            assert len(publication_writes) == 1
        # Result delivery evidence uses this SAME physical primitive too.
        # Every observed final validation must exclude another writer; an
        # arbitrary private callback count is not a publication contract.
        assert atomic_observations and commit_calls.call_count == len(atomic_observations)
        if task_drive:
            assert len(driven) >= 2 and all(calls > 1 and completed == 1 for calls, completed in driven.values())
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
        try:
            original_close = core.close_task
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
            if host is not None:
                await host.aclose()
            elif not core.close():
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

    # The old manifested Saved path remains executable-read free. No cancelled
    # state, absent Manifest or replacement invocation substitutes for success.
    reopened = new_core(raw, digest)
    saved_host = saved_client = None
    try:
        saved_host = InstalledLocalHost(reopened, state, now=lambda: 1_800_000_000_000,
            observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        saved_client = await AsyncClient._connect_local(saved_host)
        original_call = reopened._call

        def only_saved(family, name, *args):
            if family in ('program', 'run', 'compute', 'task'):
                raise AssertionError('Succeeded Saved read reissued execution')
            return original_call(family, name, *args)

        with patch.object(reopened, '_call', side_effect=only_saved):
            saved = await saved_client.attach(reference)
            assert (await saved.status()).to_dict() == final
            assert await saved.result('answer').all(schema=Row, max_rows=2) == [Row(n=expected_n)]
    finally:
        if saved_client is not None:
            await saved_client.aclose()
        if saved_host is not None:
            await saved_host.aclose()
        elif not reopened.close():
            raise AssertionError('Saved succeeded Core close remains pending')
    assert reopened._closed
    print(json.dumps({'success': True, 'actualCases': 1,
        'case': ('public_core_derived_task_drive_quantum_one_joined_result_same_saved' if task_drive else
                 'public_commit_reply_loss_original_lookup_same_result_without_reexecution' if commit_unknown else
                 'public_succeeded_execute_typed_result_same_saved_and_close'),
        'module_sha256': digest, 'state': str(state), 'atomic_precommit_writer_exclusion': True,
        'commit_reply_loss_readback_without_reexecution': commit_unknown,
        **({'core_owned_lifecycle': True, 'quantum': 1, 'original_tasks': len(driven)} if task_drive else {}),
        'qualification': 'actual source SDK/raw Wasm/SQLite; no installed normal package acceptance'}))


asyncio.run(main())
