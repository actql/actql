"""Actual original SDK Run/task cancellation fence between bounded quanta.

This raw Wasm component does not claim ordinary installed execution or a public
cancelled terminal. The existing task operations must physically close before
their original Core and Store can retire.
"""
import asyncio
import hashlib
import json
from pathlib import Path
import sys
from tempfile import mkdtemp

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient
from actql_sdk._local_core import LocalCore, LocalCoreError, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, _ordinary_core_limits


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()


async def main():
    if len(sys.argv) not in (3, 4) or (len(sys.argv) == 4 and sys.argv[3] != 'active-provider'):
        raise ValueError('Expected raw module, fresh scratch and optional active-provider selection')
    active_provider = len(sys.argv) == 4
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    scratch = Path(sys.argv[2]); scratch.mkdir(parents=True, exist_ok=True)
    state = Path(mkdtemp(prefix='original-', dir=scratch))
    core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
    host = client = None
    primary = None
    try:
        host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
            observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        client = await AsyncClient._connect_local(host)
        reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'active-task-cancel'}
        query = ('SELECT n FROM UNNEST([' + ','.join(str(n) for n in range(64)) + ']) AS n'
                 if active_provider else 'SELECT 41 AS n')
        run, admission_raw = host._accept_original(reference,
            encode({'kind': 'aql', 'input': {'format': 'sql', 'text': query},
                    'parameters': None}), run_id='active-task-cancel')
        assert run is not None
        admission = json.loads(admission_raw)
        compute = host._configure_original_compute(run)
        preflight, publisher = host._prepare_original_publication(compute)
        binding = host._installation.binding
        configuration = host._configuration
        selected = []
        binding.inspect(lambda _: selected.append(core.reserve_next_sdk_task(compute.core, configuration.handle)))
        task = selected[0]
        assert task is not None
        host._tasks.append(task)
        binding.inspect(lambda _: core.start_task(task))
        binding.inspect(lambda _: core.feed_task(task, 1))
        if active_provider:
            progress = []
            binding.inspect(lambda _: progress.append(core.advance_task(task, 1)))
            assert not progress[0].complete and not progress[0].waiting
        rows = []
        binding.inspect(lambda current: core._journal_callbacks(current.ticket).reader.scan_after(
            'client_runs', '', rows.append))
        assert len(rows) == 1 and rows[0] is not None
        # This expected-revision DATA comes from the fresh original physical
        # row; Common independently checks the complete control/census tuple.
        revision = rows[0][1].generation
        execution = await client.attach(admission['ref'])
        accepted = (await execution.cancel(cancel_id='same-active-task',
            expected_revision=revision, attempt_id='same-active-task-attempt')).to_dict()
        assert accepted['kind'] == 'accepted'
        assert accepted['cancellation']['revision'] == revision + 1
        try:
            binding.inspect(lambda _: core.advance_task(task, 1))
        except LocalCoreError as error:
            assert error.operation == 'advance' and error.code == -35
        else:
            raise AssertionError('Cancelled original Run advanced its active task')
        assert core._task_loans[task.handle] is task
        for _ in range(8):
            if core.close_task(task):
                break
            assert core._task_loans[task.handle] is task
        else:
            raise AssertionError('Original active task still retains stop/cleanup responsibility')
        host._tasks.remove(task)
        assert task.handle not in core._task_loans
    except BaseException as error:
        primary = error
        raise
    finally:
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
            print('Cleanup remains pending; original primary and fresh state KEEP', file=sys.stderr)
    print(json.dumps({'success': True, 'actualCases': 1,
        'case': ('same_saved_cancellation_fences_active_provider_then_bounded_original_stop_and_cleanup'
                 if active_provider else
                 'same_saved_cancellation_fences_active_original_task_before_next_quantum_then_actual_close'),
        'module_sha256': digest, 'state': str(state),
        'qualification': 'raw actual Core/SDK/SQLite task-boundary component; no public terminal or normal acceptance'}))


asyncio.run(main())
