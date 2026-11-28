"""Explicit low-fuel fault, same-original close and separate-process Saved.

Normal admission uses the shipped default in the separate pending-history case.
This negative control deliberately lowers ONE fresh operation to 1,000 fuel;
it does not change or qualify the normal product ceiling.
"""
from pathlib import Path
from ctypes import byref
import argparse
import json
import os
import sys
from unittest.mock import patch

from actql_sdk._local_core import LocalCore, LocalCoreError, _Output, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost
from actql_sdk._values import thaw
import wasmtime
from wasmtime import _ffi


def expected_fuel_trap_code():
    # The generated C enum declaration preserves zero-based C member order.
    # Python Enum.auto() values themselves are not the C numeric values.
    members = list(_ffi.wasmtime_trap_code_enum)
    return members.index(_ffi.wasmtime_trap_code_enum.WASMTIME_TRAP_CODE_OUT_OF_FUEL)


def fuel_trap_code(trap):
    code = _ffi.wasmtime_trap_code_t()
    assert _ffi.wasmtime_trap_code(trap.ptr(), byref(code)) and code.value == expected_fuel_trap_code()
    return code.value


def rows(run):
    assert run.result('answer').all(max_rows=1) == [{'n': 41}]


def initial(state, receipt, expected_fuel):
    from actql import Client, ClientError
    assert not receipt.exists() and not state.exists()
    client = Client.open(state_dir=state)
    host = client._client._local_host
    core = host._core
    store = core._store
    reference = client.new_submission()
    run = client.start_source('SELECT 41 AS n', format='sql', submission_ref=reference)
    assert run.wait()['status'] == 'succeeded'
    rows(run)
    original_ref = thaw(run.ref)
    failed_reference = client.new_submission()
    original_accept = InstalledLocalHost._accept_original
    calls = 0
    inner = None
    primary = None
    cleanup = None
    observation_failure = None
    default_observed = None
    close_observations = []

    def close_probe(frame, event, arg):
        # Read actual return locations, not a reconstructed cleanup classifier.
        try:
            if event != 'return' or arg is not False or len(close_observations) >= 16:
                return
            if frame.f_code not in (InstalledLocalHost._close_originals.__code__, LocalCore._close_output.__code__):
                return
            if frame.f_locals.get('self') not in (host, core):
                return
            row = {'method': frame.f_code.co_name, 'line': frame.f_lineno}
            value = frame.f_locals.get('value')
            if type(value) is _Output:
                row['family'] = value.family
            close_observations.append(row)
        except BaseException:
            pass  # Read-only diagnostic failure cannot change cleanup.

    def failure_kind(error):
        if error is None:
            return None
        result = {'type': type(error).__name__}
        if isinstance(error, ClientError):
            result['code'] = error.code
        if type(error) is LocalCoreError:
            result.update(operation=error.operation, code=error.code)
        frame = error.__traceback__
        stack = []
        for _ in range(32):
            if frame is None:
                break
            if len(stack) < 16:
                stack.append({'file': Path(frame.tb_frame.f_code.co_filename).name,
                              'function': frame.tb_frame.f_code.co_name, 'line': frame.tb_lineno})
            if frame.tb_frame.f_code is LocalCore._call.__code__ and frame.tb_frame.f_locals.get('self') is core:
                export = frame.tb_frame.f_locals.get('export_name')
                if type(export) is str and export in core._exports:
                    result['abiOperation'] = export
                break
            frame = frame.tb_next
        result['stack'] = stack
        return result

    def exhaust(receiver, *args, **kwargs):
        nonlocal calls, inner, default_observed
        assert receiver is host
        with core._lock:
            calls += 1
            assert calls == 1 and core._store is store and not core._invoking
            assert core._host_fuel_phase == 'operation' and core._host_operation_id > 0
            assert _NORMAL_HOST_OPERATION_FUEL == expected_fuel
            default_observed = store.get_fuel()
            assert 1_000 < default_observed <= _NORMAL_HOST_OPERATION_FUEL
            store.set_fuel(1_000)  # Explicit deliberate exhaustion, never refuel.
            try:
                return original_accept(receiver, *args, **kwargs)
            except BaseException as error:
                inner = error
                raise

    try:
        with patch.object(InstalledLocalHost, '_accept_original', exhaust):
            try:
                client.start_source('SELECT 42 AS n', format='sql', submission_ref=failed_reference)
            except ClientError as error:
                primary = error
            else:
                raise AssertionError('The intentional fuel exhaustion completed')
        assert primary is not None and primary.code == 'SubmissionUnknown'
        assert type(inner) is wasmtime.Trap
        original_trap_code = fuel_trap_code(inner)
        assert calls == 1 and core._store is store and core._closing
        remaining = store.get_fuel()
        try:
            with core._host_operation():
                raise AssertionError('A trapped original acquired normal work')
        except RuntimeError:
            pass
        assert core._store is store and core._closing and store.get_fuel() == remaining
    except BaseException as error:
        observation_failure = error
        raise
    finally:
        previous_profile = sys.getprofile()
        try:
            if previous_profile is None:
                sys.setprofile(close_probe)
            client.close()  # FIRST close only; failed/pending cleanup is a failure.
        except BaseException as error:
            cleanup = error
        finally:
            if previous_profile is None:
                sys.setprofile(None)
        if cleanup is not None:
            ticket = host._uncertain_ticket
            try:
                print(json.dumps({'primary': None if primary is None else primary.code,
                              'inner': failure_kind(inner), 'cleanup': failure_kind(cleanup),
                              'cleanupContext': failure_kind(cleanup.__context__),
                              'actualFalseCloseReturns': close_observations,
                              'retainedInputs': len(core._inputs), 'retainedLoans': len(core._loans),
                              'uncertainTicketPresent': ticket is not None,
                              'uncertainInputPresent': ticket in core._inputs,
                              'uncertainLoanPresent': ticket in core._loans,
                              'uncertainReleasedPresent': ticket in core._released,
                              'responseStreams': len(host._response_streams),
                              'stateObserving': host._state_observing,
                              'physicalWork': len(host._physical_work),
                                  'firstClose': False}), flush=True)
            except BaseException:
                pass  # Reporting never replaces the original operation/close.
            if observation_failure is not None:
                observation_failure.cleanup_error = cleanup
                observation_failure.public_primary = primary
            elif primary is not None:
                primary.cleanup_error = cleanup
                raise primary from None
            else:
                raise cleanup
    receipt.write_text(json.dumps({'pid': os.getpid(), 'run': original_ref,
        'submission': thaw(reference), 'failedSubmission': thaw(failed_reference)}, sort_keys=True)+'\n')
    return {'phase': 'initial', 'intentionalFuel': 1_000, 'defaultFuel': _NORMAL_HOST_OPERATION_FUEL,
            'defaultRemainingBeforeFault': default_observed, 'actualAttempts': calls,
            'outOfFuel': True, 'originalTrapCode': original_trap_code, 'normalFenced': True, 'sameStore': True,
            'firstClose': True, 'replayed': False, 'pid': os.getpid()}


def resume(state, receipt, expected_fuel):
    from actql import Client
    assert _NORMAL_HOST_OPERATION_FUEL == expected_fuel
    saved = json.loads(receipt.read_text())
    assert saved['pid'] != os.getpid()
    with Client.open(state_dir=state) as client:
        observed = client.lookup_submission(saved['submission'])
        assert observed['kind'] == 'ready' and thaw(observed['admission']['ref']) == saved['run']
        run = client.attach(saved['run'])
        assert thaw(run.ref) == saved['run']
        rows(run)
        missing = client.lookup_submission(saved['failedSubmission'])
        assert missing['kind'] == 'unresolvable'
        assert missing['problem']['code'] == 'submission_history_unresolvable'
        # Absence is not retry permission. No start/prepare/send occurs here.
    return {'phase': 'resume', 'sameSaved': True, 'failedAdmissionAbsent': True,
            'firstClose': True, 'replayed': False, 'pid': os.getpid()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('initial', 'resume'), required=True)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--expected-default-fuel', type=int, default=64_000_000_000)
    args = parser.parse_args()
    print(json.dumps((initial if args.phase == 'initial' else resume)(
        args.state, args.receipt, args.expected_default_fuel)), flush=True)
