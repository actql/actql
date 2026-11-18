"""Original Submission observation through real Python/Wasm and fresh SQLite.

This is a raw-module component, not an installed image, public Run execution,
or ordinary-package acceptance. Core calls, ABI admission, original Host/File/
Store constructors and journal reads are real. Only the final physical output
cleanup callback is given a controlled pending observation.
"""
import hashlib
import json
from pathlib import Path
import sys
from tempfile import mkdtemp
from unittest.mock import patch
import wasmtime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_core import LocalCore, LocalCoreError, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import (
    InstalledLocalHost, LocalProductCleanupPending, _ordinary_core_limits,
)


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')


def identity(intent):
    # Independent fixed-domain preimage. No product CID supplies this oracle.
    preimage = json.dumps({'version': 'actql-submitted-intent/0.1', 'intent': intent},
        ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')
    return 'sha256:' + hashlib.sha256(preimage).hexdigest()


fuel_calls = 0
fuel_store = None
fuel_amount = None
set_fuel = wasmtime.Store.set_fuel


def observe_fuel(store, amount):
    # Saturating observation, not an unbounded event history or a replacement
    # fuel policy. Delegate the original operation on the SAME actual Store.
    global fuel_calls, fuel_store, fuel_amount
    if fuel_calls == 0:
        fuel_store, fuel_amount = store, amount
    fuel_calls = min(2, fuel_calls + 1)
    return set_fuel(store, amount)


with patch.object(wasmtime.Store, 'set_fuel', observe_fuel):
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    # One explicit diagnostic allowance from the existing profile, consumed by
    # initialization and every case together. No refill and no default-fuel or
    # ordinary installed-image qualification is inferred from this raw component.
    # Match the existing installed factory's transfer/slot profile. Raw-module
    # execution and the explicit one-shot fuel remain separately qualified.
    core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
    host = None
    cases = []
    scratch = Path(sys.argv[2])
    scratch.mkdir(parents=True, exist_ok=True)
    temporary = mkdtemp(prefix='original-', dir=scratch)
    try:
        try:
            host = InstalledLocalHost(core, Path(temporary), now=lambda: 1_800_000_000_000,
                observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        except LocalProductCleanupPending as failure:
            host = failure.cleanup_host
            raise
        reference = {'epoch': host.profile()['submissionEpoch'], 'nonce': 'original-observation'}
        intent = {'kind': 'aql', 'input': {'format': 'sql', 'text': 'SELECT 41 AS n'},
                  'parameters': {'note': 'e\u0301/~😀\r\n'}}
        intent_cid = identity(intent)

        def observe(selected=intent, expected=None):
            return json.loads(host._read_original_reference(reference, kind=4,
                intent=encode(selected), intent_cid=identity(selected) if expected is None else expected))

        missing = observe()
        assert missing['action'] == 'missing' and missing['intentCid'] == intent_cid
        assert missing['outcome'] == {'kind': 'unresolvable', 'submissionRef': reference,
            'problem': {'code': 'submission_history_unresolvable'}}
        assert not host._run_loans and not host._prepared_inputs and not host._physical_work
        cases.append('actual_missing_is_unresolved_not_execution')

        # Explicit original intent retention, not acceptance or physical start.
        appended = host._retain_intent(reference, encode(intent))
        # The physical write has consumed these transport bytes. The existing
        # original plan/input borrow remains retained; this is not a Run ACK.
        assert core.retire_submission_append_output(appended)
        retained = observe()
        assert retained['action'] == 'recorded' and retained['intentCid'] == intent_cid
        assert retained['outcome'] == {'kind': 'preparing', 'submissionRef': reference,
                                      'intentCid': intent_cid}
        assert not host._run_loans and not host._prepared_inputs and not host._physical_work
        cases.append('actual_same_saved_preparing_original')

        foreign = {**intent, 'parameters': {'note': 'é/~😀\n'}}
        conflict = observe(foreign)
        assert conflict['action'] == 'conflict' and conflict['intentCid'] == identity(foreign)
        assert conflict['outcome'] == retained['outcome']
        cases.append('actual_foreign_original_conflict')

        before = len(host._projections)
        try:
            observe(expected='sha256:' + 'd' * 64)
        except LocalCoreError as error:
            assert error.code == -31
        else:
            raise AssertionError('A foreign claimed identity was accepted')
        assert len(host._projections) == before + 1
        rejected = host._projections[-1]
        assert core._loans[rejected.ticket] is rejected
        # Never reinvoke the failed producer; it stays available only to cleanup.
        assert host._close_projection(rejected)
        assert rejected.ticket not in core._loans
        cases.append('actual_wrong_claim_refuses_then_original_cleanup')

        ready = False
        cleanup_attempts = []
        reserve = core.reserve_submission_projection

        def controlled_projection(configuration, source, kind, *, cleanup):
            def physical_cleanup():
                cleanup_attempts.append(ready)
                return cleanup() if ready else False
            return reserve(configuration, source, kind,
                cleanup=physical_cleanup if kind == 4 else cleanup)

        with patch.object(core, 'reserve_submission_projection', side_effect=controlled_projection):
            try:
                observe()
            except LocalProductCleanupPending as failure:
                assert failure.cleanup_host is host
            else:
                raise AssertionError('Pending physical cleanup was acknowledged')
        pending = host._projections[-1]
        source = host._append_sources[pending.ticket]
        assert core._loans[pending.ticket] is pending and core._loans[source.ticket] is source
        original_store = core._store
        assert original_store is not None and not core._retired
        assert cleanup_attempts and not cleanup_attempts[-1]
        ready = True
        assert host.close() is True
        assert cleanup_attempts[-1] and core._retired
        cases.append('actual_same_handle_pending_then_cleanup')
    finally:
        primary = sys.exc_info()[1]
        try:
            closed = host.close() if host is not None else core.close()
            if not closed and primary is None:
                raise AssertionError('Original component cleanup remains pending')
            if not closed:
                print('Original cleanup pending; primary failure and fresh state retained', file=sys.stderr)
        except BaseException:
            if primary is None:
                raise
            print('Cleanup failed; primary failure and fresh state retained', file=sys.stderr)

    assert fuel_calls == 1 and fuel_store is original_store
    assert fuel_amount == _NORMAL_HOST_OPERATION_FUEL
    cases.append('actual_one_shot_fuel_without_refill')
    assert len(cases) == 6
    print(json.dumps({'success': True, 'module_sha256': digest, 'cases': cases,
        'initial_diagnostic_fuel': _NORMAL_HOST_OPERATION_FUEL, 'fuel_refills': fuel_calls - 1,
    'qualification': 'real raw Wasm/Python/SQLite observation component; no normal image or Run acceptance'}))
