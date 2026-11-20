"""Actual SDK/Wasm/SQLite cancellation request, original lookup and custody.

The sole original Run is prepared/admitted but never dispatched. Accepted is
request admission only, not physical stop, Result/terminal or normal acceptance.
COMMIT-reply loss and pre-write transport failure are controlled physical faults.
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
from actql_sdk import AsyncClient, ClientError
from actql_sdk._local_core import LocalCore, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending, _ordinary_core_limits
from actql_sdk._local_storage import LocalStorageCommitUnknown


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


def contains_original(error, original):
    for _ in range(8):
        if error is original:
            return True
        error = getattr(error, '__context__', None)
        if error is None:
            return False
    return False


async def main():
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    scratch = Path(sys.argv[2]); scratch.mkdir(parents=True, exist_ok=True)
    state = Path(mkdtemp(prefix='original-', dir=scratch))
    host = core = client = None
    cases = []

    async def open_original():
        nonlocal core, host, client
        core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
            slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
        try:
            host = InstalledLocalHost(core, state, now=lambda: 1_800_000_000_000,
                observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        except LocalProductCleanupPending as failure:
            host = failure.cleanup_host
            raise
        client = await AsyncClient._connect_local(host)

    try:
        await open_original()
        reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original-cancellation-append'}
        run, admission_raw = host._accept_original(reference,
            encode({'kind': 'aql', 'input': {'format': 'sql', 'text': 'SELECT 41 AS n'},
                    'parameters': None}), run_id='original-cancellation-append')
        assert run is not None and not host._physical_work
        admission = json.loads(admission_raw)
        execution = await client.attach(admission['ref'])
        store = host._installation._store
        assert store is not None
        invoke = store.compare_exchange_many_inspected
        writes = []

        # A genuine owned Submission projection is not cancellation readback.
        # Refuse the wrong family before touching current or calling Core.
        submission = next(value for value in host._projections if value.family == 'submission_append')
        core._owned_output(submission, 'submission_append')
        with patch.object(core, '_call', side_effect=AssertionError('Wrong family reached Core')):
            try:
                core.confirm_cancellation_append(submission, host._configuration.current)
            except ValueError:
                pass
            else:
                raise AssertionError('Submission output became a cancellation confirmation')
        cases.append('genuine_submission_output_refuses_cancellation_confirmation_before_core')

        def observe_writes(values, *args, **kwargs):
            writes.append(len(values))
            return invoke(values, *args, **kwargs)

        cancel_id = '😀' * 128
        attempt_id = 'e\u0301' * 128
        cancel_ref = {**admission['ref'], 'cancelId': cancel_id, 'expectedRevision': 0}
        with patch.object(store, 'compare_exchange_many_inspected', side_effect=observe_writes):
            accepted = (await execution.cancel(cancel_id=cancel_id, expected_revision=0,
                                               attempt_id=attempt_id)).to_dict()
            assert accepted == {'kind': 'accepted',
                'attemptRef': {'operation': 'cancel', 'attemptId': attempt_id},
                'cancellation': {'ref': admission['ref'], 'cancelRef': cancel_ref,
                                 'kind': 'accepted', 'revision': 1}}
            assert writes == [4] and host._pending_cancellation_write is None
            lookup = (await execution.lookup_cancellation(cancel_ref)).to_dict()
            assert lookup == {'kind': 'found', 'cancellation': accepted['cancellation']}
            replay = (await execution.cancel(cancel_id=cancel_id, expected_revision=0,
                                            attempt_id='replay-attempt')).to_dict()
            assert replay['kind'] == 'accepted' and replay['cancellation'] == accepted['cancellation']
            assert writes == [4] and not host._physical_work
        cases.append('original_request_recorded_atomically_and_replayed_without_another_write_or_stop')

        with patch.object(store, 'compare_exchange_many_inspected', side_effect=observe_writes):
            already = (await execution.cancel(cancel_id='next-cancel', expected_revision=1,
                                             attempt_id='next-attempt')).to_dict()
            assert already['kind'] == 'already_satisfied'
            assert already['cancellation']['kind'] == 'already_requested'
            assert already['cancellation']['revision'] == 1
            assert writes == [4, 3]
            conflict = (await execution.cancel(cancel_id='conflicting-revision', expected_revision=99,
                                              attempt_id='conflict-attempt')).to_dict()
            assert conflict['kind'] == 'conflict' and conflict['reason'] == 'control_revision'
            assert writes == [4, 3]
        cases.append('existing_requested_and_revision_conflict_have_original_closed_outcomes')

        original_failure = LocalStorageCommitUnknown(store)
        lost_calls = 0

        def lose_reply(values, *args, **kwargs):
            nonlocal lost_calls
            lost_calls += 1
            invoke(values, *args, **kwargs)
            raise original_failure

        lost_ref = {**admission['ref'], 'cancelId': 'lost-reply', 'expectedRevision': 1}
        with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose_reply):
            try:
                await execution.cancel(cancel_id='lost-reply', expected_revision=1, attempt_id='lost-attempt')
            except ClientError as failure:
                assert failure.code == 'CancellationUnknown' and dict(failure.cancel_ref) == lost_ref
                assert contains_original(failure.original_error, original_failure)
            else:
                raise AssertionError('Lost COMMIT reply was acknowledged')
        pending = host._pending_cancellation_write
        assert lost_calls == 1 and pending is not None
        original_source = host._append_sources[pending.ticket]
        assert core._loans[pending.ticket] is pending and core._loans[original_source.ticket] is original_source
        found = (await execution.lookup_cancellation(lost_ref)).to_dict()
        assert found['kind'] == 'found' and found['cancellation']['kind'] == 'already_requested'
        assert lost_calls == 1 and host._pending_cancellation_write is None
        cases.append('lost_commit_reply_preserves_original_then_explicit_lookup_observes_without_resend')

        before_failure = OSError('Original physical invocation failed before a write reply')
        missing_ref = {**admission['ref'], 'cancelId': 'unobserved', 'expectedRevision': 1}
        with patch.object(store, 'compare_exchange_many_inspected', side_effect=before_failure):
            try:
                await execution.cancel(cancel_id='unobserved', expected_revision=1, attempt_id='unobserved-attempt')
            except ClientError as failure:
                assert failure.code == 'CancellationUnknown'
                assert contains_original(failure.original_error, before_failure)
            else:
                raise AssertionError('Physical failure was turned into acceptance')
        pending = host._pending_cancellation_write
        assert pending is not None
        missing = (await execution.lookup_cancellation(missing_ref)).to_dict()
        assert missing == {'kind': 'unknown', 'cancelRef': missing_ref}
        assert host._pending_cancellation_write is pending
        assert core._loans[pending.ticket] is pending
        cases.append('missing_history_retains_pending_original_without_nonexecution_or_retry_claim')

        await client.aclose()
        assert core._retired
        await open_original()
        assert not host._run_loans and not host._prepared_inputs and not host._physical_work
        saved = await client.attach(admission['ref'])
        cold = (await saved.lookup_cancellation(cancel_ref)).to_dict()
        assert cold == lookup
        assert not host._run_loans and not host._prepared_inputs and not host._physical_work
        await client.aclose()
        assert core._retired
        cases.append('fresh_core_reads_same_durable_original_without_reprepare_or_dispatch_and_closes')
    finally:
        primary = sys.exc_info()[1]
        try:
            closed = host.close() if host is not None else core.close() if core is not None else True
            if not closed:
                raise AssertionError('Original cancellation cleanup remains pending')
        except BaseException:
            if primary is None:
                raise
            print('Cleanup failed; original primary and fresh state retained', file=sys.stderr)
    assert len(cases) == 6
    print(json.dumps({'success': True, 'actualCases': len(cases), 'cases': cases,
        'module_sha256': digest, 'state': str(state),
        'qualification': 'actual matching raw Wasm/SDK/SQLite cancellation request and original Saved lookup; no dispatch, physical stop, terminal Result, installed image or normal acceptance'}))


asyncio.run(main())
