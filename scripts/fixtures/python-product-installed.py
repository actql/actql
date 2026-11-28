"""Run inside an external installed consumer; never load repository assets."""
from __future__ import annotations

import argparse
import asyncio
from collections.abc import Mapping
from importlib import metadata
from hashlib import sha256
import json
import os
from pathlib import Path
import stat
import sys
import threading
from time import monotonic_ns
from typing import Any


_RECORD_FIELDS = {'version', 'producer_pid', 'producer_facade', 'submission', 'run'}
_CANCEL_RECORD_FIELDS = _RECORD_FIELDS | {'case', 'initial_status', 'cancellation', 'terminal'}
_MODEL_RECORD_FIELDS = _RECORD_FIELDS | {'case_sha256', 'rows_sha256', 'delivery'}
_MODEL_LOSS_RECORD_FIELDS = _RECORD_FIELDS | {'case_sha256', 'rows_sha256'}
_ACTIVE_STATUSES = {'preparing', 'running', 'waiting_checkpoint', 'resuming'}
_CANCEL_SOURCE = 'SELECT n FROM UNNEST([' + ','.join(str(n) for n in range(512)) + ']) AS n'


class ActiveCancellationCoverageUnavailable(AssertionError):
    """A single legal race missed active coverage; never retry the submission."""


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


def _sync_initial_phase(enabled: bool, phase: str, origin_ns: int | None = None) -> None:
    """Optional closed boundaries and elapsed time, never runtime authority."""
    if enabled is not True or type(phase) is not str or phase not in (
            'facade-import-enter', 'facade-import-return', 'factory-enter', 'factory-return',
            'first-start-enter', 'first-start-return',
            'first-wait-enter', 'first-wait-return', 'first-result-enter', 'first-result-return',
            'first-reread-enter', 'first-reread-return', 'second-start-enter', 'second-start-return',
            'second-state-enter', 'second-state-return', 'second-result-enter', 'second-result-return',
            'first-close-enter', 'first-close-return'):
        return
    if type(origin_ns) is not int or not 0 <= origin_ns <= (1 << 63) - 1:
        return
    try:
        now_ns = monotonic_ns()
        if type(now_ns) is not int:
            return
        elapsed_ns = now_ns - origin_ns
        if not 0 <= elapsed_ns <= (1 << 63) - 1:
            return  # Missing timing is not a fabricated zero or a new origin.
        sys.stderr.write(json.dumps({'stage': 'installed-sync-initial-phase', 'phase': phase,
                                     'elapsed_ns': elapsed_ns}) + '\n')
        sys.stderr.flush()
    except BaseException:
        pass  # Optional observation cannot replace an operation or close failure.


def _sync(version: str, phase: str, receipt: Path) -> None:
    initial = phase == 'initial'
    origin_ns = None
    if initial:
        try:
            origin_ns = monotonic_ns()
        except BaseException:
            pass  # Optional timing cannot replace an original operation failure.
    _sync_initial_phase(initial, 'facade-import-enter', origin_ns)
    from actql import Client
    _sync_initial_phase(initial, 'facade-import-return', origin_ns)
    saved = _saved(receipt, version) if phase == 'resume' else None
    _sync_initial_phase(initial, 'factory-enter', origin_ns)
    with Client.open() as client:
        _sync_initial_phase(initial, 'factory-return', origin_ns)
        try:
            if saved is None:
                submission = client.new_submission()
                _sync_initial_phase(initial, 'first-start-enter', origin_ns)
                run = client.start_source('SELECT 1 AS n', format='sql', submission_ref=submission)
                _sync_initial_phase(initial, 'first-start-return', origin_ns)
            else:
                submission = saved['submission']
                observed = client.lookup_submission(submission)
                if observed['kind'] != 'ready' or _plain(observed['admission']['ref']) != saved['run']:
                    raise AssertionError('Lookup did not return the original admitted Run')
                run = client.attach(saved['run'])
            if saved is None:
                _record(receipt.with_name(receipt.name + '.submitted'), version=version,
                        facade='sync', submission=submission, run=_plain(run.ref))
            _sync_initial_phase(initial, 'first-wait-enter', origin_ns)
            state = run.wait()
            _sync_initial_phase(initial, 'first-wait-return', origin_ns)
            if state['status'] != 'succeeded':
                raise AssertionError('Original Run did not succeed')
            _sync_initial_phase(initial, 'first-result-enter', origin_ns)
            _rows(run.result('answer').all(max_rows=1))
            _sync_initial_phase(initial, 'first-result-return', origin_ns)
            _sync_initial_phase(initial, 'first-reread-enter', origin_ns)
            _rows(run.result('answer').all(max_rows=1))
            _sync_initial_phase(initial, 'first-reread-return', origin_ns)
            original = _plain(run.ref)
            if saved is not None and original != saved['run']:
                raise AssertionError('Attach replaced the original Run')
            if saved is None:
                second_submission = client.new_submission()
                if _plain(second_submission) == _plain(submission):
                    raise AssertionError('Second submission must have a distinct original reference')
                _sync_initial_phase(initial, 'second-start-enter', origin_ns)
                second = client.start_source('SELECT 1 AS n', format='sql', submission_ref=second_submission)
                _sync_initial_phase(initial, 'second-start-return', origin_ns)
                _record(receipt.with_name(receipt.name + '.second.submitted'), version=version,
                        facade='sync', submission=second_submission, run=_plain(second.ref))
                _sync_initial_phase(initial, 'second-state-enter', origin_ns)
                if _plain(second.ref) == original or second.wait()['status'] != 'succeeded':
                    raise AssertionError('Second distinct Run did not succeed on the same Host')
                _sync_initial_phase(initial, 'second-state-return', origin_ns)
                # all() consumes through EOF and refuses any extra row at this bound.
                _sync_initial_phase(initial, 'second-result-enter', origin_ns)
                _rows(second.result('answer').all(max_rows=1))
                _sync_initial_phase(initial, 'second-result-return', origin_ns)
        finally:
            _sync_initial_phase(initial, 'first-close-enter', origin_ns)
    _sync_initial_phase(initial, 'first-close-return', origin_ns)
    if saved is None:
        _record(receipt, version=version, facade='sync', submission=submission, run=original)


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


def _named_results_fixture(fixture: Path) -> dict[str, Any]:
    with fixture.open('rb') as source:
        encoded = source.read(65537)
    if len(encoded) > 65536:
        raise AssertionError('Named Results fixture exceeds its bound')
    body = json.loads(encoded)
    if (type(body) is not dict or set(body) != {'aql', 'results'}
            or type(body['aql']) is not str or not body['aql']
            or type(body['results']) is not dict
            or set(body['results']) != {'before_change', 'after_change'}
            or any(type(rows) is not list or len(rows) != 1 for rows in body['results'].values())):
        raise AssertionError('Invalid shared named Results fixture')
    return body


_NAMED_RESULTS_REQUEST = 'original-two-result-submission'


def _named_original(run: Any, original: Any) -> None:
    if (_plain(run.ref) != _plain(original.ref)
            or _plain(run.submission['submissionRef']) != _plain(original.submission['submissionRef'])):
        raise AssertionError('Same name replaced the original Submission or Run')


def _named_status(state: Any, results: dict[str, Any]) -> None:
    if state['status'] != 'succeeded' or set(state['result_availability']) != set(results):
        raise AssertionError('Original Run did not publish both named Results')


def _named_row(name: str, actual: Any, expected: Any) -> None:
    if json.dumps(actual, sort_keys=True) != json.dumps(expected, sort_keys=True):
        raise AssertionError('Named Result differs from independent expected rows: ' + name)


def _named_saved(observed: Any, saved: dict[str, Any]) -> None:
    if (observed['kind'] != 'ready' or _plain(observed['admission']['ref']) != saved['run']
            or _plain(observed['submissionRef']) != saved['submission']):
        raise AssertionError('Lookup did not return the original named Submission and Run')


def _sync_named_results(version: str, receipt: Path, fixture: dict[str, Any],
                        saved: dict[str, Any] | None) -> None:
    from actql import Client, RequestConflict

    text, results = fixture['aql'], fixture['results']
    with Client.open() as client:
        if saved is None:
            run = client.start_source(text, format='aql-text', request_id=_NAMED_RESULTS_REQUEST)
            state = run.wait(until='terminal')
            _named_original(
                client.start_source(text, format='aql-text', request_id=_NAMED_RESULTS_REQUEST), run)
            try:
                client.start_source(text + '\n', format='aql-text', request_id=_NAMED_RESULTS_REQUEST)
            except RequestConflict:
                pass
            else:
                raise AssertionError('Changed named intent was accepted')
        else:
            _named_saved(client.lookup_submission(saved['submission']), saved)
            run = client.attach(saved['run'])
            if _plain(run.ref) != saved['run']:
                raise AssertionError('Saved attach replaced the original named Results Run')
            state = run.status()
        _named_status(state, results)
        for name, expected in results.items():
            _named_row(name, run.result(name).all(max_rows=1), expected)
    if saved is None:
        _record(receipt, version=version, facade='sync',
                submission=run.submission['submissionRef'], run=run.ref)


async def _async_named_results(version: str, receipt: Path, fixture: dict[str, Any],
                               saved: dict[str, Any] | None) -> None:
    from actql import AsyncClient, RequestConflict

    text, results = fixture['aql'], fixture['results']
    async with await AsyncClient.open() as client:
        if saved is None:
            start = client.start_source
            run, same = await asyncio.gather(
                start(text, format='aql-text', request_id=_NAMED_RESULTS_REQUEST),
                start(text, format='aql-text', request_id=_NAMED_RESULTS_REQUEST))
            _named_original(same, run)
            state = await run.wait(until='terminal')
            try:
                await start(text + '\n', format='aql-text', request_id=_NAMED_RESULTS_REQUEST)
            except RequestConflict:
                pass
            else:
                raise AssertionError('Changed named intent was accepted')
        else:
            _named_saved(await client.lookup_submission(saved['submission']), saved)
            run = await client.attach(saved['run'])
            if _plain(run.ref) != saved['run']:
                raise AssertionError('Saved attach replaced the original named Results Run')
            state = await run.status()
        _named_status(state, results)
        for name, expected in results.items():
            _named_row(name, await run.result(name).all(max_rows=1), expected)
    if saved is None:
        _record(receipt, version=version, facade='async',
                submission=run.submission['submissionRef'], run=run.ref)


def _model_case_wire(value: Any) -> bytes:
    return json.dumps(_plain(value), ensure_ascii=False, allow_nan=False, sort_keys=True,
                      separators=(',', ':')).encode('utf-8')


class _ModelEgressAudit:
    # This fixture process never extends an intermediate no-send observation
    # into a transport claim. The parent separately counts real peer activity.
    _NETWORK = {'socket.connect', 'socket.getaddrinfo', 'socket.gethostbyname',
                'socket.gethostbyaddr', 'socket.getnameinfo', 'socket.sendto', 'socket.sendmsg'}

    def __init__(self, credential: str, trust: str, cold: bool, *, source: Path | None = None):
        self.protected = {credential: 'credential', trust: 'trust'}
        self.cold = cold
        self.blocked = True
        self.events: list[str] = []
        self.source = source
        self.source_before = self._source_stamp(source) if source is not None else None
        self.source_opens = 0
        sys.addaudithook(self.observe)

    @staticmethod
    def _source_stamp(source):
        info = source.stat()
        return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns

    def observe(self, event, args):
        source = self.source
        if (source is not None and event == 'open' and isinstance(args[0], (str, bytes))
                and os.fsdecode(args[0]) in (source.name, str(source))):
            self.source_opens += 1
            if self.blocked or self.source_opens != 1:
                raise AssertionError('Unexpected Portable Model Source open')
        if not self.blocked:
            return
        if event == 'open' and isinstance(args[0], (str, bytes)):
            observed = self.protected.get(Path(os.fsdecode(args[0])).name)
        else:
            observed = event if event in self._NETWORK else None
        if observed is not None:
            self.events.append(observed)
            raise AssertionError('Model Check or cold Saved reached credential, trust or network activity')

    def begin_run(self):
        if self.cold or not self.blocked or self.events:
            raise AssertionError('Model Run requires a completed no-egress Check')
        self.blocked = False

    def observation(self) -> dict[str, Any]:
        if self.events or self.blocked != self.cold:
            raise AssertionError('Incomplete Model Check or cold Saved egress observation')
        observation = {'python_check_events': None if self.cold else [],
                       'python_cold_events': [] if self.cold else None}
        if self.source is not None:
            unchanged = self._source_stamp(self.source) == self.source_before
            if not unchanged or self.source_opens != (0 if self.cold else 1):
                raise AssertionError('Portable Model did not preserve the original Source lifecycle')
            observation.update(python_source_opens=self.source_opens, python_source_unchanged=unchanged)
        return observation


def _model_case(version: str, facade: str, phase: str, receipt: Path, fixture: Path,
                *, fields: set[str] = _MODEL_RECORD_FIELDS):
    # Everything in the case index is independently authored. The protected
    # deployment and loopback endpoint were selected by the case's parent.
    case_wire = _read_model_case_file(fixture / 'case.json')
    case = json.loads(case_wire)
    if (type(case) is not dict
            or set(case) - {'source_file'} != {
                'program_sha256', 'result_name', 'rows', 'credential_file', 'ca_file'}
            or type(case['rows']) is not list or len(case['rows']) != 1
            or type(case['rows'][0]) is not dict or set(case['rows'][0]) != {'id', 'outcome', 'value'}
            or case['rows'][0]['outcome'] != 'ok'
            or type(case['rows'][0]['value']) is not dict):
        raise AssertionError('Invalid independent Portable Model fixture')
    for key in ('credential_file', 'ca_file'):
        name = case[key]
        if type(name) is not str or Path(name).name != name or name in ('', '.', '..'):
            raise AssertionError('Invalid protected fixture marker')
    fixture = fixture.resolve(strict=True)
    if Path.cwd().resolve() != fixture / 'project':
        raise AssertionError('Portable Model consumer must use its selected project')
    original = _saved(receipt, version, fields=fields) if phase == 'resume' else None
    case_sha256 = sha256(case_wire).hexdigest()
    rows_sha256 = sha256(_model_case_wire(case['rows'])).hexdigest()
    program = None
    if original is None:
        program_wire = _read_model_case_file(fixture / 'program.json')
        if sha256(program_wire).hexdigest() != case['program_sha256']:
            raise AssertionError('Selected original Portable Model Program changed')
        program = json.loads(program_wire)
        if type(program) is not dict:
            raise AssertionError('Invalid original Portable Model Program')
    elif (os.path.lexists(fixture / 'program.json') or original['producer_facade'] != facade
            or original['case_sha256'] != case_sha256 or original['rows_sha256'] != rows_sha256):
        raise AssertionError('Cold Model read requires the same oracle and no Program')

    source = None
    if 'source_file' in case:
        name = case['source_file']
        if type(name) is not str or Path(name).name != name or name in ('', '.', '..'):
            raise AssertionError('Invalid Portable Model Source marker')
        source = fixture / 'project/data' / name
    audit = _ModelEgressAudit(case['credential_file'], case['ca_file'], original is not None, source=source)
    return fixture, case, original, case_sha256, rows_sha256, program, audit


def _sync_model_result(version: str, phase: str, receipt: Path, fixture: Path) -> dict[str, Any]:
    facade = 'sync'
    fixture, case, original, case_sha256, rows_sha256, program, audit = \
        _model_case(version, facade, phase, receipt, fixture)
    from actql import Client
    check_verdict = None
    with Client.connect(mode='local', model_deployment=fixture / 'deployment') as client:
        host = client._client._local_host
        if original is None:
            checked = client.check(program, kind='program', scope='bound_input')
            check_verdict = _verified_model_check(checked)
            submission = client.new_submission()
            audit.begin_run()
            run = client.start(program, submission_ref=submission)
            state = run.wait(until='terminal')
        else:
            submission = original['submission']
            run = client.attach(original['run'])
        result = run.result(case['result_name'])
        with result.rows() as reader:
            rows = _one_model_row(reader)
        delivery = _model_delivery(reader.delivery_attempt(), run.ref, case['result_name'])
        if original is not None:
            retained = result.delivery_attempt(original['delivery']['attempt_id'])
            _same_model_delivery(_model_delivery(retained, run.ref, case['result_name']),
                                 original['delivery'], delivery)
            state = run.status()
        lookup = client.lookup_submission(submission)
        ref = _selected_model_result(run.ref, rows, state, lookup, case, original)
    if not host._core._closed or host._core._loans:
        raise AssertionError('Original Model Host did not return all loans on first close')
    return _finish_model_result(receipt, version, facade, submission, ref, case_sha256,
                                rows_sha256, delivery, original, audit, check_verdict)


async def _async_model_result(version: str, phase: str, receipt: Path, fixture: Path) -> dict[str, Any]:
    facade = 'async'
    fixture, case, original, case_sha256, rows_sha256, program, audit = \
        _model_case(version, facade, phase, receipt, fixture)
    from actql import AsyncClient
    check_verdict = None
    async with await AsyncClient.connect(mode='local', model_deployment=fixture / 'deployment') as client:
        host = client._local_host
        if original is None:
            checked = await client.check(program, kind='program', scope='bound_input')
            check_verdict = _verified_model_check(checked)
            submission = client.new_submission()
            audit.begin_run()
            run = await client.start(program, submission_ref=submission)
            state = await run.wait(until='terminal')
        else:
            submission = original['submission']
            run = await client.attach(original['run'])
        result = run.result(case['result_name'])
        async with result.rows() as reader:
            # One exact expected row followed by real EOF.
            rows = [await anext(reader)]
            if await anext(reader, None) is not None:
                raise AssertionError('Portable Model Result supplied an extra row')
        delivery = _model_delivery(await reader.delivery_attempt(), run.ref, case['result_name'])
        if original is not None:
            retained = await result.delivery_attempt(original['delivery']['attempt_id'])
            _same_model_delivery(_model_delivery(retained, run.ref, case['result_name']),
                                 original['delivery'], delivery)
            state = await run.status()
        lookup = await client.lookup_submission(submission)
        ref = _selected_model_result(run.ref, rows, state, lookup, case, original)
    if not host._core._closed or host._core._loans:
        raise AssertionError('Original Model Host did not return all loans on first close')
    return _finish_model_result(receipt, version, facade, submission, ref, case_sha256,
                                rows_sha256, delivery, original, audit, check_verdict)


async def _wait_for_original_model_loss(host, ref) -> None:
    from actql_sdk._local_model_http import _ModelHttpTransportFailure

    selected = host._find_original_run_reference(_model_case_wire(ref))
    [work] = host._physical_work
    if selected is None or work._owner is not selected.run:
        raise AssertionError('Loss must come from the one original Model worker')
    # Observe the original worker without a public status subscriber that
    # could initiate a replacement state observation.
    try:
        await asyncio.wait_for(work.wait(), timeout=120)
    except _ModelHttpTransportFailure as failure:
        if failure.kind != 'incomplete':
            raise
    else:
        raise AssertionError('Partial HTTP response completed the original Model worker')
    if work.stopped is not True:
        raise AssertionError('Original Model worker did not stop')


def _check_original_model_loss(host, ref, original, lookup, submission):
    if (ref != original['run'] or lookup['kind'] != 'ready'
            or lookup['submissionRef'] != submission or lookup['admission']['ref'] != ref
            or host._physical_work):
        raise AssertionError('Cold reconciliation must read the original Run without starting work')


def _finish_model_loss(host, audit, original, receipt, version, facade, submission, ref, state,
                       check_verdict, case_sha256, rows_sha256):
    if not host._core._closed or host._core._loans:
        raise AssertionError('Original Model Host failed first close')
    cold = original is not None
    if not cold:
        _record(receipt, version=version, facade=facade, submission=submission, run=ref,
                details={'case_sha256': case_sha256, 'rows_sha256': rows_sha256})
    # The retained private receipt owns the submission authenticator.
    submission_cid = 'sha256:' + sha256(_model_case_wire(submission)).hexdigest()
    return {'run': ref, 'submission_cid': submission_cid, 'state': state, 'first_close': True,
            'check_verdict': check_verdict, 'worker_stopped_without_status': None if cold else True,
            'cold_original_lookup': cold, **audit.observation()}


def _sync_model_loss(version: str, phase: str, receipt: Path, fixture: Path) -> dict[str, Any]:
    from actql import Client

    facade = 'sync'
    fixture, _, original, case_sha256, rows_sha256, program, audit = _model_case(
        version, facade, phase, receipt, fixture, fields=_MODEL_LOSS_RECORD_FIELDS)
    check_verdict = state = None
    with Client.connect(mode='local', model_deployment=fixture / 'deployment') as client:
        host = client._client._local_host
        if original is None:
            check_verdict = _verified_model_check(client.check(program, kind='program', scope='bound_input'))
            submission = client.new_submission()
            audit.begin_run()
            run = client.start(program, submission_ref=submission)
            ref = _plain(run.ref)
            client._call(_wait_for_original_model_loss, host, ref)
        else:
            submission = original['submission']
            lookup = _plain(client.lookup_submission(submission))
            run = client.attach(original['run'])
            ref = _plain(run.ref)
            state = _plain(run.status())
            _check_original_model_loss(host, ref, original, lookup, submission)
    return _finish_model_loss(host, audit, original, receipt, version, facade, submission, ref,
                              state, check_verdict, case_sha256, rows_sha256)


async def _async_model_loss(version: str, phase: str, receipt: Path, fixture: Path) -> dict[str, Any]:
    from actql import AsyncClient

    facade = 'async'
    fixture, _, original, case_sha256, rows_sha256, program, audit = _model_case(
        version, facade, phase, receipt, fixture, fields=_MODEL_LOSS_RECORD_FIELDS)
    check_verdict = state = None
    async with await AsyncClient.connect(mode='local', model_deployment=fixture / 'deployment') as client:
        host = client._local_host
        if original is None:
            check_verdict = _verified_model_check(await client.check(program, kind='program', scope='bound_input'))
            submission = client.new_submission()
            audit.begin_run()
            run = await client.start(program, submission_ref=submission)
            ref = _plain(run.ref)
            await _wait_for_original_model_loss(host, ref)
        else:
            submission = original['submission']
            lookup = _plain(await client.lookup_submission(submission))
            run = await client.attach(original['run'])
            ref = _plain(run.ref)
            state = _plain(await run.status())
            _check_original_model_loss(host, ref, original, lookup, submission)
    return _finish_model_loss(host, audit, original, receipt, version, facade, submission, ref,
                              state, check_verdict, case_sha256, rows_sha256)


def _verified_model_check(checked) -> str:
    if checked.report is None or checked.report.verdict != 'verified':
        raise AssertionError('Protected Portable Model Program did not verify')
    return checked.report.verdict


def _finish_model_result(receipt, version, facade, submission, ref, case_sha256,
                         rows_sha256, delivery, original, audit, check_verdict) -> dict[str, Any]:
    egress = audit.observation()
    if original is None:
        _record(receipt, version=version, facade=facade, submission=submission, run=ref,
                details={'case_sha256': case_sha256, 'rows_sha256': rows_sha256, 'delivery': delivery})
    return {'run': ref, 'rows_sha256': rows_sha256, 'delivery': delivery,
            'original_saved_first': original is not None, 'first_close': True, 'check_verdict': check_verdict,
            **egress}


def _read_model_case_file(path: Path) -> bytes:
    with path.open('rb') as reader:
        raw = reader.read(65537)
    if not 0 < len(raw) <= 65536:
        raise AssertionError('Missing or over-bound Portable Model fixture')
    return raw


def _one_model_row(reader) -> list[Any]:
    rows = [next(reader)]
    if next(reader, None) is not None:
        raise AssertionError('Portable Model Result supplied an extra row')
    return rows


def _model_delivery(value, ref, name) -> dict[str, Any]:
    if value['kind'] != 'found' or value['record']['state'] != 'succeeded':
        raise AssertionError('Expected actual completed Model Result delivery')
    attempt, observed = value['attempt'], value['hostReleaseReceipt']
    if observed['run_definition_cid'] != ref['runDefinitionCid'] or observed['result_name'] != name:
        raise AssertionError('Model Result delivery has another original')
    return {'attempt_id': attempt['attempt_id'],
            'artifact_cid': observed['result_artifact_cid'],
            'manifest_cid': observed['result_manifest_cid'],
            'receipt_cid': observed['result_delivery_receipt_cid'],
            'bytes': observed['delivered_byte_count'], 'sha256': observed['delivered_sha256']}


def _same_model_delivery(retained, warm, cold) -> None:
    if retained != warm or cold['attempt_id'] == warm['attempt_id']:
        raise AssertionError('Cold Model replaced its original warm delivery')
    for field in ('artifact_cid', 'manifest_cid', 'bytes', 'sha256'):
        if cold[field] != warm[field]:
            raise AssertionError('Cold Model delivery differs from the original artifact')


def _selected_model_result(ref, rows, state, lookup, case, original):
    ref = _plain(ref)
    if (state['status'] != 'succeeded' or case['result_name'] not in state['result_availability']
            or lookup['kind'] != 'ready' or _plain(lookup['admission']['ref']) != ref
            or original is not None and ref != original['run']
            or _model_case_wire(rows) != _model_case_wire(case['rows'])):
        raise AssertionError('Model Result differs from the exact original and independent expected rows')
    return ref


def installed(version: str, mode: str, *, facade: str | None = None,
              phase: str | None = None, receipt: Path | None = None,
              case: str = 'execution', named_results_fixture: Path | None = None,
              model_fixture: Path | None = None) -> None:
    if metadata.version('actql-sdk') != version:
        raise AssertionError('Installed SDK cohort differs')
    if mode == 'sdk-only':
        if (facade is not None or phase is not None or receipt is not None
                or case != 'execution' or named_results_fixture is not None or model_fixture is not None):
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
    model_case = case in ('portable-model', 'portable-model-loss')
    if (mode != 'local' or (case not in ('execution', 'cancellation', 'named-results') and not model_case)
            or facade not in ('sync', 'async') or phase not in ('initial', 'resume')
            or receipt is None):
        raise AssertionError('Local consumer requires an explicit facade/phase/private receipt')
    if model_case != (model_fixture is not None):
        raise AssertionError('Portable Model requires its exact selected fixture')
    if case == 'named-results':
        if named_results_fixture is None:
            raise AssertionError('Named Results requires the shared fixture')
    elif named_results_fixture is not None:
        raise AssertionError('Named Results fixture is only admitted for its own case')
    if phase == 'initial' and (os.path.lexists(receipt) or os.path.lexists(receipt.with_name(receipt.name + '.submitted'))):
        raise AssertionError('Initial consumer requires a fresh receipt, not a repeated submission')
    if (phase == 'initial' and case == 'cancellation'
            and os.path.lexists(receipt.with_name(receipt.name + '.state'))):
        raise AssertionError('Initial cancellation consumer requires fresh public state')
    if metadata.version('actql') != version or metadata.version('actql-local-runtime') != version:
        raise AssertionError('Installed product/runtime cohort differs')
    if model_case:
        if case == 'portable-model-loss':
            observed = (_sync_model_loss(version, phase, receipt, model_fixture) if facade == 'sync'
                        else asyncio.run(_async_model_loss(version, phase, receipt, model_fixture)))
        elif facade == 'sync':
            observed = _sync_model_result(version, phase, receipt, model_fixture)
        else:
            observed = asyncio.run(_async_model_result(version, phase, receipt, model_fixture))
        print(json.dumps({'mode': mode, 'version': version, 'case': case, 'facade': facade,
            'phase': phase, 'pid': os.getpid(), **observed}))
        return
    if case == 'named-results':
        original = _saved(receipt, version) if phase == 'resume' else None
        if original is not None and original['producer_facade'] != facade:
            raise AssertionError('Saved named Results used a foreign facade receipt')
        fixture = _named_results_fixture(named_results_fixture)
        if facade == 'sync':
            _sync_named_results(version, receipt, fixture, original)
        else:
            asyncio.run(_async_named_results(version, receipt, fixture, original))
        print(json.dumps({'mode': mode, 'version': version, 'case': case, 'phase': phase,
            'facade': facade, 'pid': os.getpid(), 'results': list(fixture['results']),
            'named_submission': True, 'same_name_reused': phase == 'initial',
            'changed_intent_refused': phase == 'initial', 'original_run_reused': phase == 'resume',
            'submitted': phase == 'initial', 'first_close': True}))
        return
    if case == 'cancellation':
        if not _unprofiled():
            raise AssertionError('Expected uninstrumented installed cancellation')
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
    if not _unprofiled():
        raise AssertionError('Expected an uninstrumented installed execution')
    if facade == 'sync':
        _sync(version, phase, receipt)
    else:
        asyncio.run(_async(version, phase, receipt))
    print(json.dumps({'mode': mode, 'version': version, 'facade': facade, 'phase': phase,
        'pid': os.getpid(), 'select1': phase == 'initial', 'reread': True,
        'original_run_reused': phase == 'resume', 'same_host_second_run': phase == 'initial', 'closed': True}))


def _unprofiled() -> bool:
    return all(hook() is None for hook in (sys.getprofile, sys.gettrace,
                                         threading.getprofile, threading.gettrace))


def _history_run_key(reference: Any) -> str:
    return sha256(json.dumps(_plain(reference), sort_keys=True, separators=(',', ':'),
                             allow_nan=False).encode('utf-8')).hexdigest()


def _history_event(phase: str, **details: Any) -> None:
    print(json.dumps({'phase': phase, 'pid': os.getpid(), **details}, allow_nan=False), flush=True)


def _history_sync(state: Path, stage: str, kind: str, count: int, saved):
    from actql import Client
    with Client.open(state_dir=state) as client:
        if saved is not None:
            _named_saved(client.lookup_submission(saved['submission']), saved)
            run = client.attach(saved['run'])
            if _plain(run.ref) != saved['run'] or run.status()['status'] != 'succeeded':
                raise AssertionError('Original retained Run differs')
            _rows(run.result('answer').all(max_rows=1))
            return _history_run_key(run.ref), None
        for ordinal in range(1, count + 1):
            submission = client.new_submission()
            run = client.start_source(_CANCEL_SOURCE if kind == 'cancelled' and stage == 'seed'
                                      else 'SELECT 1 AS n', format='sql', submission_ref=submission)
            if kind == 'cancelled' and stage == 'seed':
                _, revision = _active_revision(run.status())
                cancellation = _accepted_cancellation(run.cancel(expected_revision=revision), run.ref)
                _same_cancellation_lookup(run.lookup_cancellation(cancellation['cancelRef']), cancellation)
                _cancelled_terminal(run.wait())
            elif run.wait()['status'] != 'succeeded':
                raise AssertionError('Ordinary history Run did not succeed')
            key = _history_run_key(run.ref)
            if stage == 'fresh':
                _rows(run.result('answer').all(max_rows=1))
                return key, (submission, run.ref)
            _history_event('seeded', ordinal=ordinal, key=key)


async def _history_async(state: Path, stage: str, kind: str, count: int, saved):
    from actql import AsyncClient
    async with await AsyncClient.open(state_dir=state) as client:
        if saved is not None:
            _named_saved(await client.lookup_submission(saved['submission']), saved)
            run = await client.attach(saved['run'])
            if _plain(run.ref) != saved['run'] or (await run.status())['status'] != 'succeeded':
                raise AssertionError('Original retained Run differs')
            _rows(await run.result('answer').all(max_rows=1))
            return _history_run_key(run.ref), None
        for ordinal in range(1, count + 1):
            submission = client.new_submission()
            run = await client.start_source(_CANCEL_SOURCE if kind == 'cancelled' and stage == 'seed'
                                            else 'SELECT 1 AS n', format='sql', submission_ref=submission)
            if kind == 'cancelled' and stage == 'seed':
                _, revision = _active_revision(await run.status())
                cancellation = _accepted_cancellation(await run.cancel(expected_revision=revision), run.ref)
                _same_cancellation_lookup(await run.lookup_cancellation(cancellation['cancelRef']), cancellation)
                _cancelled_terminal(await run.wait())
            elif (await run.wait())['status'] != 'succeeded':
                raise AssertionError('Ordinary history Run did not succeed')
            key = _history_run_key(run.ref)
            if stage == 'fresh':
                _rows(await run.result('answer').all(max_rows=1))
                return key, (submission, run.ref)
            _history_event('seeded', ordinal=ordinal, key=key)


def installed_history(version: str, facade: str, stage: str, kind: str, count: int,
                      state: Path, receipt: Path | None) -> None:
    if (facade not in ('sync', 'async') or stage not in ('seed', 'fresh', 'saved')
            or kind not in ('completed', 'cancelled')
            or (stage == 'seed' and (receipt is not None or not 1 <= count <= 1000))
            or (stage != 'seed' and (receipt is None or count != 1))
            or metadata.version('actql-sdk') != version
            or not _unprofiled()):
        raise AssertionError('Expected an uninstrumented installed history stage')
    saved = _saved(receipt, version) if stage == 'saved' else None
    if saved is not None and saved['producer_facade'] != facade:
        raise AssertionError('Original retained Run belongs to another facade')
    _history_event('started', facade=facade, stage=stage, kind=kind, count=count)
    result = (_history_sync(state, stage, kind, count, saved) if facade == 'sync'
              else asyncio.run(_history_async(state, stage, kind, count, saved)))
    # A completion event exists only after the original public context closed.
    key = None
    if result is not None:
        key, original = result
        if original is not None:
            submission, run = original
            _record(receipt, version=version, facade=facade, submission=submission, run=run)
    _history_event('closed', facade=facade, stage=stage, kind=kind, count=count, key=key,
                   first_close=True, submitted=stage != 'saved')


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
    parser.add_argument('--case', choices=('execution', 'cancellation', 'named-results',
                                           'portable-model', 'portable-model-loss'),
                        default='execution')
    parser.add_argument('--named-results-fixture', type=Path)
    parser.add_argument('--model-fixture', type=Path)
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--await-close-observation', action='store_true')
    parser.add_argument('--history-stage', choices=('seed', 'fresh', 'saved'))
    parser.add_argument('--history-kind', choices=('completed', 'cancelled'))
    parser.add_argument('--history-count', type=int)
    parser.add_argument('--history-state', type=Path)
    options = parser.parse_args()
    if options.history_stage is not None:
        if (options.mode != 'local' or options.case != 'execution' or options.phase is not None
                or options.model_fixture is not None or options.named_results_fixture is not None
                or options.await_close_observation or options.history_count is None
                or options.history_state is None):
            parser.error('Expected the exact installed history arguments')
        installed_history(options.version, options.facade, options.history_stage, options.history_kind,
                          options.history_count, options.history_state, options.receipt)
    else:
        if any(value is not None for value in (options.history_kind, options.history_count,
                                               options.history_state)):
            parser.error('History inputs require a history stage')
        installed(options.version, options.mode, facade=options.facade, phase=options.phase,
                  receipt=options.receipt, case=options.case, named_results_fixture=options.named_results_fixture,
                  model_fixture=options.model_fixture)
        if options.await_close_observation:
            _observe_closed()
