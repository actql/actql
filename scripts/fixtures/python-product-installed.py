"""Run inside an external installed consumer; never load repository assets."""
from __future__ import annotations

import argparse
import asyncio
from collections.abc import Mapping
from importlib import metadata
import json
import os
from pathlib import Path
import stat
import sys
from typing import Any


_RECORD_FIELDS = {'version', 'producer_pid', 'producer_facade', 'submission', 'run'}


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


def _record(path: Path, *, version: str, facade: str, submission: Mapping[str, Any], run: Mapping[str, Any]) -> None:
    body = {'version': version, 'producer_pid': os.getpid(), 'producer_facade': facade,
            'submission': _plain(submission), 'run': _plain(run)}
    encoded = (json.dumps(body, ensure_ascii=False, allow_nan=False) + '\n').encode('utf-8')
    if len(encoded) > 65536:
        raise AssertionError('Original public references exceed the receipt bound')
    # Acceptance custody: a private fresh file, never a Local Host/Store option.
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), 'wb') as target:
        target.write(encoded)


def _saved(path: Path, version: str) -> dict[str, Any]:
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
    if (type(body) is not dict or set(body) != _RECORD_FIELDS or body['version'] != version
            or type(body['producer_pid']) is not int or body['producer_pid'] <= 0
            or body['producer_pid'] == os.getpid() or body['producer_facade'] not in ('sync', 'async')
            or type(body['submission']) is not dict or type(body['run']) is not dict):
        raise AssertionError('Resume requires an original receipt from a different Python process')
    return body


def _sync(version: str, phase: str, receipt: Path) -> None:
    from actql import Client
    saved = _saved(receipt, version) if phase == 'resume' else None
    with Client.open() as client:
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


def installed(version: str, mode: str, *, facade: str | None = None,
              phase: str | None = None, receipt: Path | None = None) -> None:
    if metadata.version('actql-sdk') != version:
        raise AssertionError('Installed SDK cohort differs')
    if mode == 'sdk-only':
        if facade is not None or phase is not None or receipt is not None:
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
    if (mode != 'local' or facade not in ('sync', 'async') or phase not in ('initial', 'resume')
            or receipt is None):
        raise AssertionError('Local consumer requires an explicit facade/phase/private receipt')
    if phase == 'initial' and (os.path.lexists(receipt) or os.path.lexists(receipt.with_name(receipt.name + '.submitted'))):
        raise AssertionError('Initial consumer requires a fresh receipt, not a repeated submission')
    if metadata.version('actql') != version or metadata.version('actql-local-runtime') != version:
        raise AssertionError('Installed product/runtime cohort differs')
    if facade == 'sync':
        _sync(version, phase, receipt)
    else:
        asyncio.run(_async(version, phase, receipt))
    print(json.dumps({'mode': mode, 'version': version, 'facade': facade, 'phase': phase,
        'pid': os.getpid(), 'select1': phase == 'initial', 'reread': True,
        'original_run_reused': phase == 'resume', 'same_host_second_run': phase == 'initial', 'closed': True}))


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
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--await-close-observation', action='store_true')
    options = parser.parse_args()
    installed(options.version, options.mode, facade=options.facade, phase=options.phase, receipt=options.receipt)
    if options.await_close_observation:
        _observe_closed()
