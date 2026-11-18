"""New SDK cancellation lookup through actual raw Wasm and fresh SQLite.

Preparation/Run admission is real; this fixture never dispatches that Run.
It qualifies neither cancellation issuance/physical stop nor a normal image.
Only the second lookup's output-cleanup observation is controlled.
"""
import asyncio
import hashlib
import json
from pathlib import Path
import sys
from tempfile import mkdtemp
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._async import AsyncClient
from actql_sdk._local_core import LocalCore, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending, _ordinary_core_limits


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


async def main():
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
    scratch = Path(sys.argv[2])
    scratch.mkdir(parents=True, exist_ok=True)
    state = Path(mkdtemp(prefix='original-', dir=scratch))
    host = client = None
    cleanup_ready = False
    cases = []
    try:
        try:
            host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
                observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        except LocalProductCleanupPending as failure:
            host = failure.cleanup_host
            raise
        reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original-cancellation-lookup'}
        run, admission_raw = host._accept_original(reference,
            encode({'kind': 'aql', 'input': {'format': 'sql', 'text': 'SELECT 41 AS n'},
                    'parameters': None}), run_id='original-cancellation-lookup')
        assert run is not None and not host._physical_work
        admission = json.loads(admission_raw)
        client = await AsyncClient._connect_local(host)
        execution = await client.attach(admission['ref'])
        cancel_ref = {**admission['ref'], 'cancelId': 'not-recorded', 'expectedRevision': 0}
        store = host._installation._store
        assert store is not None
        changed = store._connection.total_changes
        originals = (tuple(host._run_loans), tuple(host._prepared_inputs))
        observed = await execution.lookup_cancellation(cancel_ref)
        assert observed.to_dict() == {'kind': 'unknown', 'cancelRef': cancel_ref}
        assert store._connection.total_changes == changed
        assert (tuple(host._run_loans), tuple(host._prepared_inputs)) == originals
        assert not host._physical_work
        cases.append('actual_sdk_same_run_unknown_lookup_without_write_or_dispatch')

        reserve = core.reserve_submission_projection
        cleanup_attempts = []

        def controlled_projection(configuration, source, kind, *, cleanup):
            def physical_cleanup():
                cleanup_attempts.append(cleanup_ready)
                return cleanup() if cleanup_ready else False
            return reserve(configuration, source, kind,
                cleanup=physical_cleanup if kind == 11 else cleanup)

        with patch.object(core, 'reserve_submission_projection', side_effect=controlled_projection):
            try:
                await host.open('lookup-cancellation', encode({
                    'connection': {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                                   'consentRefs': [], 'runners': []},
                    'ref': admission['ref'], 'cancelId': 'not-recorded', 'expectedRevision': 0}))
            except LocalProductCleanupPending as failure:
                assert failure.cleanup_host is host
            else:
                raise AssertionError('Pending physical output cleanup was acknowledged')
        pending = host._projections[-1]
        source = host._append_sources[pending.ticket]
        assert core._loans[pending.ticket] is pending and core._loans[source.ticket] is source
        assert not core._retired and cleanup_attempts == [False]
        assert store._connection.total_changes == changed
        cleanup_ready = True
        await client.aclose()
        assert core._retired and cleanup_attempts[-1] is True
        cases.append('actual_lookup_output_pending_retains_same_core_and_input_until_close')
    finally:
        primary = sys.exc_info()[1]
        cleanup_ready = True
        try:
            closed = host.close() if host is not None else core.close()
            if not closed:
                raise AssertionError('Original cancellation lookup cleanup remains pending')
        except BaseException:
            if primary is None:
                raise
            print('Cleanup failed; original primary and fresh state retained', file=sys.stderr)
    assert len(cases) == 2
    print(json.dumps({'success': True, 'actualCases': len(cases), 'cases': cases,
        'module_sha256': digest, 'state': str(state),
        'qualification': 'raw matching Wasm/Python/SQLite SDK lookup and close component; no dispatch, cancellation write, physical stop or normal image'}))


asyncio.run(main())
