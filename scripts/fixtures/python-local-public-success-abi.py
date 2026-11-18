"""Actual succeeded public execution/typed Result after worker-control changes.

Uses the unchanged source-free Local route and a real SQLite-backed Host. This
raw-module check does not qualify an installed package or a new Host profile.
"""
import asyncio
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import sys
from tempfile import mkdtemp
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient, ClientError
from actql_sdk._local_core import LocalCore, LocalCoreError, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, _ordinary_core_limits


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
    if len(sys.argv) != 3:
        raise ValueError('Expected original module and fresh scratch')
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    scratch = Path(sys.argv[2]); scratch.mkdir(parents=True, exist_ok=True)
    state = Path(mkdtemp(prefix='succeeded-', dir=scratch))
    core = new_core(raw, digest)
    host = client = primary = None
    try:
        host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
            observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        client = await AsyncClient._connect_local(host)
        execution = await client.start_source(
            'WITH seed AS (SELECT 41 AS n) FROM seed |> SELECT n |> RESULT answer', format='aql')
        final = (await execution.wait(until='terminal')).to_dict()
        assert final['status'] == 'succeeded' and final['result_available']
        assert await execution.result('answer').all(schema=Row, max_rows=2) == [Row(n=41)]
        assert (await execution.status()).to_dict() == final
        reference = dict(execution.ref)
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
            assert await saved.result('answer').all(schema=Row, max_rows=2) == [Row(n=41)]
    finally:
        if saved_client is not None:
            await saved_client.aclose()
        if saved_host is not None:
            await saved_host.aclose()
        elif not reopened.close():
            raise AssertionError('Saved succeeded Core close remains pending')
    assert reopened._closed
    print(json.dumps({'success': True, 'actualCases': 1,
        'case': 'public_succeeded_execute_typed_result_same_saved_and_close',
        'module_sha256': digest, 'state': str(state),
        'qualification': 'actual source SDK/raw Wasm/SQLite; no installed normal package acceptance'}))


asyncio.run(main())
