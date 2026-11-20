"""Actual public SDK cancellation through the retained Local worker.

An explicit physical lock scheduling barrier holds the worker after one actual
incomplete provider quantum and after its reader/lock return. No Core decision,
task, request, cancellation, stop observation or provider outcome is mocked.
This raw-module component is not an installed normal-profile acceptance.
"""
import asyncio
import copy
from contextlib import nullcontext
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from tempfile import mkdtemp
from threading import Event, current_thread, local
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient, ClientError
from actql_sdk._local_core import LocalCore, LocalCoreError, LocalTaskProgress, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import (
    InstalledLocalHost, _OriginalExecution, _LOCAL_SELECTION, _ordinary_core_limits,
)
from actql_sdk._local_storage import LocalStorageCommitUnknown


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()


def assert_original_cancellation_worker(work, host, *, precommit):
    """Check the selected physical exit; terminal Run/cleanup assertions follow."""
    work._nominal()
    failure = work._future.exception()
    original = work._invoke
    same_stop = (type(original) is _OriginalExecution and original.host is host
                 and original.run is work._owner and original.stop_interest is not None)
    name = None if failure is None else type(failure).__name__
    detail = {'workerSucceeded': failure is None,
              'workerFailureType': name if name is None or (
                  name.isascii() and name.isidentifier() and len(name) <= 80) else 'unprojected',
              'sameOriginalStopInterest': same_stop}
    if isinstance(failure, LocalCoreError):
        operation, code = failure.operation, failure.code
        detail.update(operation=operation if type(operation) is str and (
            operation.isascii() and operation.isidentifier() and len(operation) <= 80) else 'unprojected',
            code=code if type(code) is int and -(2**31) <= code < 2**31 else None)
    print(json.dumps({'latePublicationObservation' if precommit else
                      'managedCancellationObservation': detail}), file=sys.stderr)
    if precommit:
        # This barrier is after task retirement and immediately before actual
        # publication. The original publication guard must still refuse.
        assert isinstance(failure, LocalCoreError) and failure.code == -35
    else:
        # Acknowledged managed cancellation selects the SAME invocation's
        # original stop/retirement path, not an artificial normal-drive error.
        # A genuine worker failure remains a failure even with stop interest.
        assert same_stop
        assert failure is None


class OriginalQuantumBarrier:
    """Retain the same physical RLock; pause only after its full release."""

    def __init__(self, lock, binding, *, after_start=False):
        self.original = lock
        self.binding = binding
        self.depth = local()
        self.entered, self.resume = Event(), Event()
        self.armed = self.paused = False
        self.latest = None
        self.after_start = after_start

    def acquire(self, *args, **kwargs):
        acquired = self.original.acquire(*args, **kwargs)
        if acquired:
            self.depth.count = getattr(self.depth, 'count', 0) + 1
        return acquired

    def release(self):
        self.depth.count -= 1
        self.original.release()
        if (self.depth.count == 0 and self.armed and not self.paused
                and current_thread().name == 'actql-local-original-work'):
            self.paused = True
            if self.binding._observed_reader is not None:
                raise AssertionError('A physical reader escaped its bounded quantum')
            if not self.after_start and (self.latest is None or self.latest.complete):
                raise AssertionError('The worker did not return its lock between provider quanta')
            self.entered.set()
            if not self.resume.wait(30):
                raise TimeoutError('Original incomplete provider was not resumed')

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, *args):
        self.release()


async def main():
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] not in ('default-state', 'fault-state', 'partial-state', 'process-state', 'precommit-state', 'drive-start-state')):
        raise ValueError('Expected raw module, fresh scratch and optional state selection')
    default_state = len(sys.argv) == 4
    selection = sys.argv[3] if default_state else 'explicit'
    precommit = selection == 'precommit-state'
    after_start = selection == 'drive-start-state'
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    scratch = Path(sys.argv[2]); scratch.mkdir(parents=True, exist_ok=True)
    state = Path(mkdtemp(prefix='original-', dir=scratch))
    core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
    host = client = barrier = None
    primary = None
    try:
        host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
            observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        client = await AsyncClient._connect_local(host)
        barrier = OriginalQuantumBarrier(core._lock, host._installation.binding, after_start=after_start)
        core._lock = barrier
        original_drive = core.drive_task

        def observe_quantum(task, quantum):
            complete = original_drive(task, quantum)
            # Read the SAME original bounded provider observation. Startup and
            # input-feed steps have no provider progress and cannot arm this
            # barrier. Task completion remains the separate drive result.
            fields = [core._call('task', 'progress', task.handle, index) for index in range(4)]
            if after_start and not barrier.armed:
                # Actual activation returned; the same task has no provider
                # advance observation yet. Absence is not fabricated progress.
                assert not complete and fields[0] == -33
                assert core._call('task', 'started', task.handle) == 0
                barrier.armed = True
                return complete
            if fields[0] in (0, 1) and fields[1] in (0, 1) and min(fields[2:]) >= 0:
                progress = LocalTaskProgress(fields[0] == 1, fields[1] == 1, fields[2], fields[3])
                barrier.latest = progress
                if not precommit and not progress.complete and not progress.waiting and progress.work > 0:
                    barrier.armed = True
            return complete

        original_commit = host._store_original_commit
        def pause_original_commit(*args, **kwargs):
            if host._installation.binding._observed_reader is not None or barrier.original._is_owned():
                raise AssertionError('Publication scheduling retained an original reader or Core lock')
            barrier.entered.set()
            if not barrier.resume.wait(30):
                raise TimeoutError('Original prepared publication was not resumed')
            return original_commit(*args, **kwargs)

        with patch.object(core, 'drive_task', side_effect=observe_quantum), \
                (patch.object(host, '_store_original_commit', side_effect=pause_original_commit)
                 if precommit else nullcontext()):
            query = ('SELECT 1 AS n' if precommit else
                     'SELECT n FROM UNNEST([' + ','.join(str(n) for n in range(512)) + ']) AS n')
            execution = await client.start_source(query, format='sql')
            if not await asyncio.to_thread(barrier.entered.wait, 30):
                for pending in host._physical_work:
                    if pending._future.done() and not pending._future.cancelled():
                        failure = pending._future.exception()
                        if isinstance(failure, LocalCoreError):
                            print(json.dumps({'beforeSchedulingFailure': failure.operation,
                                              'code': failure.code}), file=sys.stderr)
                raise AssertionError('Original worker did not reach the selected physical boundary')
            assert len(host._physical_work) == 1
            work = host._physical_work[0]
            assert not work.stopped
            if after_start:
                assert barrier.latest is None
            else:
                assert barrier.latest is not None and barrier.latest.complete is precommit
            assert work._owner is host._public_run_references[0].run
            rows = []
            with core._lock:
                host._installation.binding.inspect(lambda current:
                    core._journal_callbacks(current.ticket).reader.scan_after('client_runs', '', rows.append))
            assert len(rows) == 1 and rows[0] is not None
            revision = rows[0][1].generation
            if default_state:
                if selection in ('fault-state', 'partial-state'):
                    store = host._installation._store
                    original_write = store.compare_exchange_many_inspected
                    writes = []
                    unknown = LocalStorageCommitUnknown(store)
                    original_close = core.close_input
                    refused = False
                    def write_once(values, *args, **kwargs):
                        if host._state_observing:
                            writes.append(values)
                        result = original_write(values, *args, **kwargs)
                        if selection == 'fault-state' and len(writes) == 1:
                            raise unknown
                        return result
                    def close_original(value):
                        nonlocal refused
                        if (selection == 'partial-state' and not refused
                                and any(held.source is value for held in host._run_state_custody.values())):
                            refused = True
                            return False  # No ACK or Core close is performed.
                        return original_close(value)
                    with patch.object(store, 'compare_exchange_many_inspected', side_effect=write_once):
                        with patch.object(core, 'close_input', side_effect=close_original):
                            try:
                                await execution.status()
                            except ClientError:
                                pass
                            else:
                                raise AssertionError('Original metadata physical failure was hidden')
                        assert len(writes) == 1 and len(host._run_state_custody) == 1
                        held = next(iter(host._run_state_custody.values()))
                        source, output = held.source, held.output
                        assert held.write_attempted and source in host._inputs and output is not None
                        if selection == 'fault-state':
                            assert held.first_failure is unknown and not held.metadata_confirmed
                            assert core._loans[output.ticket] is output
                        else:
                            assert refused and held.metadata_confirmed
                            assert core._loans.get(output.ticket) is None
                            assert any(original is output for original in host._projections)
                            try:
                                host._close_projection(copy.copy(output))
                            except ValueError:
                                pass
                            else:
                                raise AssertionError('Copied retired projection closed the original input')
                        recovered = await execution.status()
                        assert recovered['status'] == 'running'
                        assert len(writes) == 1 and not host._run_state_custody
                        assert source not in host._inputs
                running = await execution.status()
                assert running['status'] == 'running' and not running['result_available']
                assert running['control'] == {'revision': revision,
                    'cancellation_requested': False, 'physical_stop': 'unknown'}
            wrong = dict(execution.ref)
            wrong['runDefinitionCid'] = 'sha256:' + 'f' * 64
            with patch.object(core, '_call', side_effect=AssertionError('Foreign active control reached Core')):
                try:
                    await host.open('cancel', encode({'connection': _LOCAL_SELECTION, 'ref': wrong,
                        'cancelId': 'foreign', 'expectedRevision': revision,
                        'attemptRef': {'operation': 'cancel', 'attemptId': 'foreign'}}))
                except ValueError:
                    pass
                else:
                    raise AssertionError('Foreign reference borrowed the original worker')
            accepted = (await execution.cancel(cancel_id='public-active',
                **({} if default_state else {'expected_revision': revision}),
                attempt_id='public-active-attempt')).to_dict()
            assert accepted['kind'] == 'accepted' and not work.stopped
            original = accepted['cancellation']
            found = (await execution.lookup_cancellation(original['cancelRef'])).to_dict()
            assert found == {'kind': 'found', 'cancellation': original}
            assert not work.stopped
            barrier.resume.set()
            await work.wait_stopped()
            assert_original_cancellation_worker(work, host, precommit=precommit)
            assert work._exit_error is None and work._cleanup_error is None
            # The actual close port returned zero only after its SAME provider's
            # stopped, settled and cleanup observations. This inventory check
            # verifies no original task loan was lost on that path.
            assert not host._tasks and not core._task_loans
            assert core._host_retained_work is None
            if default_state:
                final = (await execution.status()).to_dict()
                assert final['status'] == 'cancelled' and not final['result_available']
                assert final['control'] == {'revision': revision + 1,
                    'cancellation_requested': True, 'physical_stop': 'confirmed'}
                assert final['revision'] == running['revision'] + 1
                assert all(item['state'] == 'unavailable' and item['reason'] == 'not_published'
                           for item in final['result_availability'].values())
                assert (await execution.status()).to_dict() == final
                saved_reference = dict(execution.ref)
    except BaseException as error:
        primary = error
        if host is not None:
            for held in host._run_state_custody.values():
                failure = held.first_failure
                if isinstance(failure, LocalCoreError):
                    print(json.dumps({'originalStateFailure': failure.operation,
                                      'code': failure.code}), file=sys.stderr)
                elif failure is not None:
                    print(json.dumps({'originalStateFailureType': type(failure).__name__}), file=sys.stderr)
        raise
    finally:
        if barrier is not None:
            barrier.resume.set()
        try:
            if client is not None:
                await client.aclose()
            if host is not None:
                await host.aclose()
            elif not core.close():
                raise AssertionError('Original Core cleanup remains pending')
        except BaseException:
            if primary is None:
                raise
            print('Original public failure and fresh state KEEP; cleanup pending', file=sys.stderr)
    assert core._closed
    if selection in ('process-state', 'precommit-state'):
        # The correspondence document is outside the managed State inventory.
        # The child opens the same saved originals, never another invocation.
        handoff = scratch / (state.name + '-saved.json')
        with handoff.open('x') as output:
            json.dump({'state': str(state), 'ref': saved_reference, 'expected': final}, output)
        child = subprocess.run([sys.executable,
            str(ROOT / 'scripts/fixtures/python-local-saved-state-abi.py'),
            str(Path(sys.argv[1]).resolve()), str(handoff.resolve())],
            capture_output=True, text=True, timeout=90, check=False)
        if child.returncode != 0:
            raise AssertionError('Saved child refused: ' + child.stderr[-8192:])
        result = json.loads(child.stdout)
        assert result['success'] and result['actualCases'] == 1
        assert result['module_sha256'] == digest
    elif default_state:
        # A fresh Core/process-local Host observes the exact saved terminal.
        # This is not executable restoration or another submitted invocation.
        reopened = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
            slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
        saved_host = InstalledLocalHost(reopened, state, now=lambda: 1_800_000_000_000,
            observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        saved_client = await AsyncClient._connect_local(saved_host)
        try:
            original_call = reopened._call
            def only_saved(family, name, *args):
                if family in ('program', 'run', 'compute', 'task'):
                    raise AssertionError('Saved cancellation prepared or invoked another Run')
                return original_call(family, name, *args)
            with patch.object(reopened, '_call', side_effect=only_saved):
                saved_execution = await saved_client.attach(saved_reference)
                assert (await saved_execution.status()).to_dict() == final
        finally:
            await saved_client.aclose()
            await saved_host.aclose()
        assert reopened._closed
    print(json.dumps({'success': True, 'actualCases': 1,
        'case': (('public_state_commit_reply_loss_original_readback_without_rewrite' if selection == 'fault-state' else
                  'public_state_partial_input_close_same_original_retirement' if selection == 'partial-state' else
                  'public_default_cancel_separate_process_saved_without_reprepare' if selection == 'process-state' else
                  'public_cancel_between_derived_drives_before_first_input_feed' if after_start else
                  'public_cancel_before_original_publication_commit_refuses_write_and_retires_same_work' if precommit else
                  'public_default_cancel_status_terminal_same_saved_original_without_reprepare')
                 if default_state else 'public_submit_active_provider_cancel_same_lookup_original_stop_cleanup_and_close'),
        'module_sha256': digest, 'state': str(state),
        'qualification': ('actual public SDK/raw Wasm/SQLite default cancellation and separate-process Saved; controlled physical thread scheduling, no installed normal acceptance'
                          if selection in ('process-state', 'precommit-state') else
                          'actual public SDK/raw Wasm/SQLite default cancellation, terminal and fresh-Core Saved; controlled physical thread scheduling, no separate-process or installed normal acceptance'
                          if default_state else 'actual public SDK/raw Wasm/SQLite with controlled physical thread scheduling; explicit revision only, no status/terminal or installed normal acceptance')}))


if __name__ == '__main__':
    asyncio.run(main())
