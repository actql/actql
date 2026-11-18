"""Actual public SDK cancellation through the retained Local worker.

An explicit physical lock scheduling barrier holds the worker after one actual
incomplete provider quantum and after its reader/lock return. No Core decision,
task, request, cancellation, stop observation or provider outcome is mocked.
This raw-module component is not an installed normal-profile acceptance.
"""
import asyncio
import hashlib
import json
from pathlib import Path
import sys
from tempfile import mkdtemp
from threading import Event, current_thread, local
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient
from actql_sdk._local_core import LocalCore, LocalCoreError, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, _LOCAL_SELECTION, _ordinary_core_limits


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()


class OriginalQuantumBarrier:
    """Retain the same physical RLock; pause only after its full release."""

    def __init__(self, lock, binding):
        self.original = lock
        self.binding = binding
        self.depth = local()
        self.entered, self.resume = Event(), Event()
        self.armed = self.paused = False
        self.latest = None

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
            if self.latest is None or self.latest.complete:
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
        barrier = OriginalQuantumBarrier(core._lock, host._installation.binding)
        core._lock = barrier
        original_advance = core.advance_task

        def observe_quantum(*args, **kwargs):
            progress = original_advance(*args, **kwargs)
            if not kwargs.get('finalization', False):
                barrier.latest = progress
                if not progress.complete and not progress.waiting:
                    barrier.armed = True
            return progress

        with patch.object(core, 'advance_task', side_effect=observe_quantum):
            query = 'SELECT n FROM UNNEST([' + ','.join(str(n) for n in range(512)) + ']) AS n'
            execution = await client.start_source(query, format='sql')
            assert await asyncio.to_thread(barrier.entered.wait, 30)
            assert len(host._physical_work) == 1
            work = host._physical_work[0]
            assert not work.stopped and barrier.latest is not None and not barrier.latest.complete
            assert work._owner is host._public_run_references[0].run
            rows = []
            with core._lock:
                host._installation.binding.inspect(lambda current:
                    core._journal_callbacks(current.ticket).reader.scan_after('client_runs', '', rows.append))
            assert len(rows) == 1 and rows[0] is not None
            revision = rows[0][1].generation
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
                expected_revision=revision, attempt_id='public-active-attempt')).to_dict()
            assert accepted['kind'] == 'accepted' and not work.stopped
            original = accepted['cancellation']
            found = (await execution.lookup_cancellation(original['cancelRef'])).to_dict()
            assert found == {'kind': 'found', 'cancellation': original}
            assert not work.stopped
            barrier.resume.set()
            await work.wait_stopped()
            failure = work._future.exception()
            assert isinstance(failure, LocalCoreError) and failure.code == -35
            assert work._exit_error is None and work._cleanup_error is None
            # The actual close port returned zero only after its SAME provider's
            # stopped, settled and cleanup observations. This inventory check
            # verifies no original task loan was lost on that path.
            assert not host._tasks and not core._task_loans
            assert core._host_retained_work is None
    except BaseException as error:
        primary = error
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
    print(json.dumps({'success': True, 'actualCases': 1,
        'case': 'public_submit_active_provider_cancel_same_lookup_original_stop_cleanup_and_close',
        'module_sha256': digest, 'state': str(state),
        'qualification': 'actual public SDK/raw Wasm/SQLite with controlled physical thread scheduling; explicit revision only, no status/terminal or installed normal acceptance'}))


asyncio.run(main())
