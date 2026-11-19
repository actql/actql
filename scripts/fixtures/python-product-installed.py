"""Run inside an external installed consumer; never load repository assets."""
from __future__ import annotations

import argparse
import asyncio
from collections.abc import Mapping
from contextlib import nullcontext
from importlib import metadata
import json
import os
from pathlib import Path
import stat
import sys
import threading
from typing import Any


_RECORD_FIELDS = {'version', 'producer_pid', 'producer_facade', 'submission', 'run'}
_CANCEL_RECORD_FIELDS = _RECORD_FIELDS | {'case', 'initial_status', 'cancellation', 'terminal'}
_ACTIVE_STATUSES = {'preparing', 'running', 'waiting_checkpoint', 'resuming'}
_CANCEL_SOURCE = 'SELECT n FROM UNNEST([' + ','.join(str(n) for n in range(512)) + ']) AS n'


class ActiveCancellationCoverageUnavailable(AssertionError):
    """A single legal race missed active coverage; never retry the submission."""


class _ClosedTaskDriveObservation:
    """One installed initial case; observe calls without replacing an entrance."""

    def __init__(self, host):
        from actql_sdk._local_core import LocalCore, _ClosedWasmExports
        from actql_sdk._local_product import InstalledLocalHost
        from actql_sdk._local_host_binding import _InvocationObservation
        from actql_sdk._local_work import OriginalLocalWork
        if type(host) is not InstalledLocalHost or type(host._core) is not LocalCore:
            raise AssertionError('Closed task control requires the original installed Host')
        core = host._core
        receipt = core._closed_wasm_exports
        export = core._exports['actql_task_drive']
        if (type(receipt) is not _ClosedWasmExports
                or not receipt._matches('actql_task_drive', export, full=True)
                or 'drive_task' in vars(core) or '_call' in vars(core)):
            raise AssertionError('Closed task control requires original runtime methods')
        self.host, self.core, self.receipt, self.export = host, core, receipt, export
        self.work_type = OriginalLocalWork
        self.span_type = _InvocationObservation
        self.drive_method, self.call_method = LocalCore.drive_task, LocalCore._call
        self.drive_code = self.drive_method.__code__
        self.export_code = type(export).__call__.__code__
        self.counts = [0, 0, 0, 0, 0]
        self.refusal_bits = 0
        self.valid = True
        self.failure = None
        self.restored = False
        self.profile = self._profile
        self.previous = (sys.getprofile(), threading.getprofile())

    def _profile(self, frame, event, argument):
        # No Core/Wasmtime/SQLite call, fuel operation, payload copy or formatter
        # runs here. Python disables recursive profiling inside this callback.
        try:
            code = frame.f_code
            if event not in ('call', 'return'):
                return
            if code is self.drive_code and frame.f_locals.get('self') is self.core:
                self.counts[0 if event == 'call' else 1] += 1
            elif code is self.export_code and frame.f_locals.get('self') is self.export:
                self.counts[2 if event == 'call' else 3] += 1
                span = self.core._invocation_observation
                original = (object.__getattribute__(span, 'wasm_export')
                            if type(span) is self.span_type else None)
                retained = self.core._host_retained_work
                works, rows = self.host._physical_work, self.host._run_rows
                span_original = type(original) is tuple and len(original) == 4
                export_original = (span_original and original[0] is self.receipt
                                   and type(original[1]) is str and original[1] == 'actql_task_drive'
                                   and original[2] is self.export and original[3] is self.export._func)
                retained_original = (type(retained) is tuple and len(retained) == 3
                                     and type(retained[0]) is self.work_type)
                holder_original = (retained_original and type(works) is list and type(rows) is list
                                   and len(works) <= 16 and len(rows) <= 16
                                   and any(work is retained[0] for work in works)
                                   and any(run is retained[0]._owner for run, _ in rows))
                # Fixed predicate bits only, never the tuple, holder, rows,
                # original exception or a formatter inside this callback.
                for passed, bit in ((span_original, 1), (export_original, 2),
                                    (retained_original, 4), (holder_original, 8)):
                    if not passed:
                        self.refusal_bits |= bit
                same = span_original and export_original and retained_original and holder_original
                self.valid = self.valid and same
                if event == 'call' and same:
                    self.counts[4] += 1
            if any(count > 1024 for count in self.counts):
                self.refusal_bits |= 16
                self.valid = False
                self.counts[:] = [min(count, 1025) for count in self.counts]
        except BaseException as failure:
            self.refusal_bits |= 32
            self.valid = False
            if self.failure is None:
                self.failure = failure

    def __enter__(self):
        if any(previous is not None for previous in self.previous):
            raise AssertionError('Closed task control cannot replace another profiler')
        try:
            sys.setprofile(self.profile)
            threading.setprofile(self.profile)
        except BaseException:
            self._finish()
            raise
        return self

    def _finish(self):
        try:
            if (self.core.drive_task.__func__ is not self.drive_method
                    or self.core._call.__func__ is not self.call_method
                    or self.core._closed_wasm_exports is not self.receipt
                    or not self.receipt._matches('actql_task_drive', self.export, full=True)):
                self.refusal_bits |= 64
                self.valid = False
        except BaseException as failure:
            self.refusal_bits |= 256
            self.valid = False
            if self.failure is None:
                self.failure = failure
        finally:
            # Both restorations are attempted even if one fails. No observer
            # failure replaces an in-flight execution or cleanup primary.
            for restore, previous in ((sys.setprofile, self.previous[0]),
                                      (threading.setprofile, self.previous[1])):
                try:
                    restore(previous)
                except BaseException as failure:
                    self.refusal_bits |= 128
                    self.valid = False
                    if self.failure is None:
                        self.failure = failure
            self.restored = (sys.getprofile() is self.previous[0]
                             and threading.getprofile() is self.previous[1])
            # Do not retain extra runtime/Host references into public close.
            self.host = self.core = self.receipt = self.export = None

    def __exit__(self, kind, primary, trace):
        self._finish()
        return False

    def result(self):
        entered, returned, wasm_entered, wasm_returned, retained = self.counts
        if (not self.valid or not self.restored or self.failure is not None or not 0 < entered <= 1024
                or entered != returned or entered != wasm_entered
                or entered != wasm_returned or entered != retained):
            # Emit only already-bounded qualification DATA after the original
            # public close. Never inspect/format an opaque callback failure or
            # serialize a Host, Core, holder, reference, row or runtime value.
            counts = ([count if type(count) is int and 0 <= count <= 1025 else None
                       for count in self.counts] if type(self.counts) is list and len(self.counts) == 5
                      else [None] * 5)
            witness = {'stage': 'closed-task-drive-refusal', 'counts': counts,
                       'valid': self.valid is True, 'profilers_restored': self.restored is True,
                       'failure_present': self.failure is not None,
                       'refusal_bits': (self.refusal_bits if type(self.refusal_bits) is int
                                        and 0 <= self.refusal_bits <= 511 else None)}
            raise AssertionError('Closed task drive observation is unqualified: '
                                 + json.dumps(witness, sort_keys=True))
        return {'actual_closed_task_drive': True, 'drive_calls': entered,
                'drive_returns': returned, 'wasm_entries': wasm_entered,
                'wasm_returns': wasm_returned, 'retained_holder_checks': retained,
                'methods_unchanged': True, 'profilers_restored': True,
                'per_drive_fuel_observed': False, 'hash_count_observed': False}


def _plain(value: Any) -> Any:
    """Serialize public references only; this copy creates no diagnostic custody."""
    if isinstance(value, Mapping):
        return {key: _plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_plain(item) for item in value]
    return value


def _rows(value: Any) -> None:
    if (type(value) is not list or len(value) != 1 or type(value[0]) is not dict
            or set(value[0]) != {'n'} or type(value[0]['n']) is not int or value[0]['n'] != 1):
        raise AssertionError('SELECT1 rows differ from the independent expected integer result')


def _record(path: Path, *, version: str, facade: str, submission: Mapping[str, Any], run: Mapping[str, Any],
            details: Mapping[str, Any] | None = None) -> None:
    body = {'version': version, 'producer_pid': os.getpid(), 'producer_facade': facade,
            'submission': _plain(submission), 'run': _plain(run)}
    if details is not None:
        if set(details) & _RECORD_FIELDS:
            raise AssertionError('Cancellation receipt replaced an original reference field')
        body.update(_plain(details))
    encoded = (json.dumps(body, ensure_ascii=False, allow_nan=False) + '\n').encode('utf-8')
    if len(encoded) > 65536:
        raise AssertionError('Original public references exceed the receipt bound')
    # Acceptance custody: a private fresh file, never a Local Host/Store option.
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), 'wb') as target:
        target.write(encoded)


def _saved(path: Path, version: str, *, fields: set[str] | None = None) -> dict[str, Any]:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in items:
            if key in value:
                raise AssertionError('Duplicate original consumer receipt field')
            value[key] = item
        return value
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as source:
        before = os.fstat(source.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
                or before.st_mode & 0o077 or not 0 < before.st_size <= 65536):
            raise AssertionError('Unavailable private original consumer receipt')
        encoded = source.read(65537)
        after = os.fstat(source.fileno())
    if (len(encoded) != before.st_size or (before.st_dev, before.st_ino, before.st_size,
            before.st_mtime_ns, before.st_ctime_ns) != (after.st_dev, after.st_ino, after.st_size,
            after.st_mtime_ns, after.st_ctime_ns)):
        raise AssertionError('Original consumer receipt changed during capture')
    body = json.loads(encoded, object_pairs_hook=pairs)
    if (type(body) is not dict or set(body) != (_RECORD_FIELDS if fields is None else fields) or body['version'] != version
            or type(body['producer_pid']) is not int or body['producer_pid'] <= 0
            or body['producer_pid'] == os.getpid() or body['producer_facade'] not in ('sync', 'async')
            or type(body['submission']) is not dict or type(body['run']) is not dict):
        raise AssertionError('Resume requires an original receipt from a different Python process')
    return body


def _sync(version: str, phase: str, receipt: Path) -> dict[str, Any] | None:
    from actql import Client
    saved = _saved(receipt, version) if phase == 'resume' else None
    with Client.open() as client:
        with (_ClosedTaskDriveObservation(client._client._local_host)
              if saved is None else nullcontext(None)) as control:
            if saved is None:
                submission = client.new_submission()
                run = client.start_source('SELECT 1 AS n', format='sql', submission_ref=submission)
            else:
                submission = saved['submission']
                observed = client.lookup_submission(submission)
                if observed['kind'] != 'ready' or _plain(observed['admission']['ref']) != saved['run']:
                    raise AssertionError('Lookup did not return the original admitted Run')
                run = client.attach(saved['run'])
            if saved is None:
                _record(receipt.with_name(receipt.name + '.submitted'), version=version,
                        facade='sync', submission=submission, run=_plain(run.ref))
            state = run.wait()
            if state['status'] != 'succeeded':
                raise AssertionError('Original Run did not succeed')
            _rows(run.result('answer').all(max_rows=1))
            _rows(run.result('answer').all(max_rows=1))
            original = _plain(run.ref)
            if saved is not None and original != saved['run']:
                raise AssertionError('Attach replaced the original Run')
            if saved is None:
                second_submission = client.new_submission()
                if _plain(second_submission) == _plain(submission):
                    raise AssertionError('Second submission must have a distinct original reference')
                second = client.start_source('SELECT 1 AS n', format='sql', submission_ref=second_submission)
                _record(receipt.with_name(receipt.name + '.second.submitted'), version=version,
                        facade='sync', submission=second_submission, run=_plain(second.ref))
                if _plain(second.ref) == original or second.wait()['status'] != 'succeeded':
                    raise AssertionError('Second distinct Run did not succeed on the same Host')
                # all() consumes through EOF and refuses any extra row at this bound.
                _rows(second.result('answer').all(max_rows=1))
    observed = control.result() if control is not None else None
    if saved is None:
        _record(receipt, version=version, facade='sync', submission=submission, run=original)

    return observed


async def _async(version: str, phase: str, receipt: Path) -> None:
    from actql import AsyncClient
    saved = _saved(receipt, version) if phase == 'resume' else None
    async with await AsyncClient.open() as client:
        if saved is None:
            submission = client.new_submission()
            run = await client.start_source('SELECT 1 AS n', format='sql', submission_ref=submission)
        else:
            submission = saved['submission']
            observed = await client.lookup_submission(submission)
            if observed['kind'] != 'ready' or _plain(observed['admission']['ref']) != saved['run']:
                raise AssertionError('Lookup did not return the original admitted Run')
            run = await client.attach(saved['run'])
        if saved is None:
            _record(receipt.with_name(receipt.name + '.submitted'), version=version,
                    facade='async', submission=submission, run=_plain(run.ref))
        state = await run.wait()
        if state['status'] != 'succeeded':
            raise AssertionError('Original Run did not succeed')
        _rows(await run.result('answer').all(max_rows=1))
        _rows(await run.result('answer').all(max_rows=1))
        original = _plain(run.ref)
        if saved is not None and original != saved['run']:
            raise AssertionError('Attach replaced the original Run')
        if saved is None:
            second_submission = client.new_submission()
            if _plain(second_submission) == _plain(submission):
                raise AssertionError('Second submission must have a distinct original reference')
            second = await client.start_source('SELECT 1 AS n', format='sql', submission_ref=second_submission)
            _record(receipt.with_name(receipt.name + '.second.submitted'), version=version,
                    facade='async', submission=second_submission, run=_plain(second.ref))
            if _plain(second.ref) == original or (await second.wait())['status'] != 'succeeded':
                raise AssertionError('Second distinct Run did not succeed on the same Host')
            # all() consumes through EOF and refuses any extra row at this bound.
            _rows(await second.result('answer').all(max_rows=1))
    if saved is None:
        _record(receipt, version=version, facade='async', submission=submission, run=original)


def _active_revision(value: Any) -> tuple[str, int]:
    state = _plain(value)
    if state.get('status') not in _ACTIVE_STATUSES:
        raise ActiveCancellationCoverageUnavailable('No admitted nonterminal Run was observed')
    control = state.get('control')
    if (type(control) is not dict or type(control.get('revision')) is not int
            or not 0 <= control['revision'] <= 2147483647
            or control.get('cancellation_requested') is not False):
        raise AssertionError('Original public cancellation revision is unavailable')
    return state['status'], control['revision']


def _cancellation_payload(value: Any, reference: Any) -> dict[str, Any]:
    cancellation, original = _plain(value), _plain(reference)
    if (type(original) is not dict or type(cancellation) is not dict
            or set(cancellation) != {'ref', 'kind', 'revision', 'cancelRef'}
            or cancellation['kind'] != 'accepted' or cancellation['ref'] != original
            or type(cancellation['revision']) is not int or not 0 <= cancellation['revision'] <= 2147483647):
        raise AssertionError('Cancellation did not retain the original admitted Run')
    cancel_ref = cancellation['cancelRef']
    if (type(cancel_ref) is not dict or set(cancel_ref) != set(original) | {'cancelId', 'expectedRevision'}
            or any(cancel_ref[key] != item for key, item in original.items())
            or type(cancel_ref['cancelId']) is not str or not cancel_ref['cancelId']
            or type(cancel_ref['expectedRevision']) is not int
            or not 0 <= cancel_ref['expectedRevision'] <= 2147483647
            or cancellation['revision'] <= cancel_ref['expectedRevision']):
        raise AssertionError('Cancellation lookup reference differs from its original Run')
    return cancellation


def _accepted_cancellation(value: Any, reference: Any) -> dict[str, Any]:
    observed = _plain(value)
    if (observed.get('kind') == 'already_satisfied'
            and observed.get('cancellation', {}).get('kind') == 'already_terminal'):
        raise ActiveCancellationCoverageUnavailable('Run became terminal before cancellation admission')
    if observed.get('kind') != 'accepted':
        raise AssertionError('Original public cancellation was not accepted')
    return _cancellation_payload(observed.get('cancellation'), reference)


def _cancelled_terminal(value: Any) -> dict[str, Any]:
    state = _plain(value)
    control = state.get('control')
    if (state.get('status') != 'cancelled' or state.get('result_available') is not False
            or type(control) is not dict or type(control.get('revision')) is not int
            or not 0 <= control['revision'] <= 2147483647
            or control.get('cancellation_requested') is not True
            or control.get('physical_stop') not in ('unknown', 'confirmed')):
        raise AssertionError('Original Run did not expose its cancelled terminal state')
    return state


def _same_cancellation_lookup(value: Any, cancellation: dict[str, Any]) -> None:
    if _plain(value) != {'kind': 'found', 'cancellation': cancellation}:
        raise AssertionError('Lookup did not return the same original accepted cancellation')


def _cancel_saved(path: Path, version: str, facade: str) -> dict[str, Any]:
    body = _saved(path, version, fields=_CANCEL_RECORD_FIELDS)
    if (body['case'] != 'cancellation' or body['producer_facade'] != facade
            or body['initial_status'] not in _ACTIVE_STATUSES):
        raise AssertionError('Resume requires the original active cancellation case')
    _cancellation_payload(body['cancellation'], body['run'])
    _cancelled_terminal(body['terminal'])
    return body


def _same_saved_cancelled(value: Any, saved: dict[str, Any]) -> dict[str, Any]:
    state = _cancelled_terminal(value)
    original = saved['terminal']
    for key in ('version', 'run_id', 'status', 'result_available'):
        if state.get(key) != original.get(key):
            raise AssertionError('Saved cancelled Run facts differ from the original')
    if state['control']['revision'] != original['control']['revision']:
        raise AssertionError('Saved cancellation control revision changed')
    if original['control']['physical_stop'] == 'confirmed' and state['control']['physical_stop'] != 'confirmed':
        raise AssertionError('Saved physical stop observation regressed')
    return state


def _sync_cancellation(version: str, phase: str, receipt: Path) -> dict[str, Any]:
    from actql import Client
    saved = _cancel_saved(receipt, version, 'sync') if phase == 'resume' else None
    with Client.open(state_dir=receipt.with_name(receipt.name + '.state')) as client:
        if saved is None:
            submission = client.new_submission()
            run = client.start_source(_CANCEL_SOURCE, format='sql', submission_ref=submission)
            reference = _plain(run.ref)
            _record(receipt.with_name(receipt.name + '.submitted'), version=version,
                    facade='sync', submission=submission, run=reference)
            initial_status, revision = _active_revision(run.status())
            cancellation = _accepted_cancellation(run.cancel(expected_revision=revision), reference)
            _same_cancellation_lookup(run.lookup_cancellation(cancellation['cancelRef']), cancellation)
            terminal = _cancelled_terminal(run.wait())
            # Cancellation does not poison this SAME public Client. This is a
            # distinct healthy Run, never a cancellation retry or replacement.
            healthy = client.start_source('SELECT 1 AS n', format='sql')
            if _plain(healthy.ref) == reference or healthy.wait()['status'] != 'succeeded':
                raise AssertionError('Post-cancellation healthy Run did not remain distinct')
            _rows(healthy.result('answer').all(max_rows=1))
        else:
            observed = client.lookup_submission(saved['submission'])
            if observed['kind'] != 'ready' or _plain(observed['admission']['ref']) != saved['run']:
                raise AssertionError('Saved submission lookup replaced the original cancelled Run')
            run = client.attach(saved['run'])
            if _plain(run.ref) != saved['run']:
                raise AssertionError('Saved attach replaced the original cancelled Run')
            terminal = _same_saved_cancelled(run.status(), saved)
            _same_cancellation_lookup(run.lookup_cancellation(saved['cancellation']['cancelRef']), saved['cancellation'])
    # Success is recorded only AFTER this first public close returned. No retry
    # turns failed cleanup into a green case, and close never requests cancel.
    if saved is None:
        _record(receipt, version=version, facade='sync', submission=submission, run=reference,
                details={'case': 'cancellation', 'initial_status': initial_status,
                         'cancellation': cancellation, 'terminal': terminal})
    return terminal


async def _async_cancellation(version: str, phase: str, receipt: Path) -> dict[str, Any]:
    from actql import AsyncClient
    saved = _cancel_saved(receipt, version, 'async') if phase == 'resume' else None
    async with await AsyncClient.open(state_dir=receipt.with_name(receipt.name + '.state')) as client:
        if saved is None:
            submission = client.new_submission()
            run = await client.start_source(_CANCEL_SOURCE, format='sql', submission_ref=submission)
            reference = _plain(run.ref)
            _record(receipt.with_name(receipt.name + '.submitted'), version=version,
                    facade='async', submission=submission, run=reference)
            initial_status, revision = _active_revision(await run.status())
            cancellation = _accepted_cancellation(await run.cancel(expected_revision=revision), reference)
            _same_cancellation_lookup(await run.lookup_cancellation(cancellation['cancelRef']), cancellation)
            terminal = _cancelled_terminal(await run.wait())
            healthy = await client.start_source('SELECT 1 AS n', format='sql')
            if _plain(healthy.ref) == reference or (await healthy.wait())['status'] != 'succeeded':
                raise AssertionError('Post-cancellation healthy Run did not remain distinct')
            _rows(await healthy.result('answer').all(max_rows=1))
        else:
            observed = await client.lookup_submission(saved['submission'])
            if observed['kind'] != 'ready' or _plain(observed['admission']['ref']) != saved['run']:
                raise AssertionError('Saved submission lookup replaced the original cancelled Run')
            run = await client.attach(saved['run'])
            if _plain(run.ref) != saved['run']:
                raise AssertionError('Saved attach replaced the original cancelled Run')
            terminal = _same_saved_cancelled(await run.status(), saved)
            _same_cancellation_lookup(await run.lookup_cancellation(saved['cancellation']['cancelRef']), saved['cancellation'])
    if saved is None:
        _record(receipt, version=version, facade='async', submission=submission, run=reference,
                details={'case': 'cancellation', 'initial_status': initial_status,
                         'cancellation': cancellation, 'terminal': terminal})
    return terminal


def installed(version: str, mode: str, *, facade: str | None = None,
              phase: str | None = None, receipt: Path | None = None,
              case: str = 'execution') -> None:
    if metadata.version('actql-sdk') != version:
        raise AssertionError('Installed SDK cohort differs')
    if mode == 'sdk-only':
        if facade is not None or phase is not None or receipt is not None or case != 'execution':
            raise AssertionError('SDK-only inspection does not run a Local scenario')
        for package in ('actql', 'actql-local-runtime', 'wasmtime', 'duckdb'):
            try:
                metadata.version(package)
            except metadata.PackageNotFoundError:
                pass
            else:
                raise AssertionError('Lightweight installation contains Local distribution: ' + package)
        import actql_sdk  # noqa: F401
        if 'wasmtime' in sys.modules or 'duckdb' in sys.modules:
            raise AssertionError('Lightweight SDK imported a Local engine')
        print(json.dumps({'mode': mode, 'version': version, 'sdk_only': True, 'local_executed': False}))
        return
    if (mode != 'local' or case not in ('execution', 'cancellation')
            or facade not in ('sync', 'async') or phase not in ('initial', 'resume')
            or receipt is None):
        raise AssertionError('Local consumer requires an explicit facade/phase/private receipt')
    if phase == 'initial' and (os.path.lexists(receipt) or os.path.lexists(receipt.with_name(receipt.name + '.submitted'))):
        raise AssertionError('Initial consumer requires a fresh receipt, not a repeated submission')
    if (phase == 'initial' and case == 'cancellation'
            and os.path.lexists(receipt.with_name(receipt.name + '.state'))):
        raise AssertionError('Initial cancellation consumer requires fresh public state')
    if metadata.version('actql') != version or metadata.version('actql-local-runtime') != version:
        raise AssertionError('Installed product/runtime cohort differs')
    if case == 'cancellation':
        terminal = (_sync_cancellation(version, phase, receipt) if facade == 'sync'
                    else asyncio.run(_async_cancellation(version, phase, receipt)))
        print(json.dumps({'mode': mode, 'version': version, 'case': case, 'actualCases': 1,
            'facade': facade, 'phase': phase, 'pid': os.getpid(),
            'admitted_inflight': phase == 'initial', 'original_cancel_accepted': True,
            'cancel_lookup_same': True, 'original_run_reused': phase == 'resume',
            'same_host_healthy_after_cancel': phase == 'initial', 'saved_read_only': phase == 'resume',
            'first_close': True, 'closed': True,
            'reported_physical_stop': terminal['control']['physical_stop']}))
        return
    closed_drive = None
    if facade == 'sync':
        closed_drive = _sync(version, phase, receipt)
    else:
        asyncio.run(_async(version, phase, receipt))
    print(json.dumps({'mode': mode, 'version': version, 'facade': facade, 'phase': phase,
        'pid': os.getpid(), 'select1': phase == 'initial', 'reread': True,
        'original_run_reused': phase == 'resume', 'same_host_second_run': phase == 'initial', 'closed': True,
        **({'closed_task_drive': closed_drive} if closed_drive is not None else {})}))


def _observe_closed() -> None:
    # The same original process acknowledges the observation after its close;
    # an exited child's empty descriptor snapshot is never sufficient.
    print(json.dumps({'stage': 'closed', 'pid': os.getpid()}), flush=True)
    if sys.stdin.readline().strip() != 'observed':
        raise RuntimeError('Original installed consumer close observation incomplete')
    print(json.dumps({'stage': 'close-observation-ack', 'pid': os.getpid()}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--mode', choices=('sdk-only', 'local'), required=True)
    parser.add_argument('--facade', choices=('sync', 'async'))
    parser.add_argument('--phase', choices=('initial', 'resume'))
    parser.add_argument('--case', choices=('execution', 'cancellation'), default='execution')
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--await-close-observation', action='store_true')
    options = parser.parse_args()
    installed(options.version, options.mode, facade=options.facade, phase=options.phase,
              receipt=options.receipt, case=options.case)
    if options.await_close_observation:
        _observe_closed()
