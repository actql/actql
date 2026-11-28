"""Verify the installed public Local lease and crash recovery in separate processes."""
import argparse
from collections.abc import Mapping
from contextlib import closing
from errno import EACCES, EAGAIN
import fcntl
from hashlib import sha256
from importlib import metadata
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys

_ROW = b'a' * 4096
_UNCOMMITTED_ROW = 'retained-open-control:uncommitted'
_KEY = 'retained-open-control:'
_COUNT = 64
_MAGIC = bytes.fromhex('d9d505f920a163d7')


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    return value


def file_original(path):
    observed = path.stat()
    with path.open('rb') as source:
        digest = sha256(source.read(16 * 1024 * 1024 + 1)).hexdigest()
    if observed.st_size > 16 * 1024 * 1024:
        raise AssertionError('Unexpected fixture extent')
    return observed.st_dev, observed.st_ino, observed.st_size, digest


def spill(path):
    original = file_original(path)
    journal = path.with_name(path.name + '-journal')
    # No other descriptor on the DB is closed while the child owns SQLite locks.
    with (path.open('rb') as observed,
          closing(sqlite3.connect(path, isolation_level=None)) as connection):
        assert connection.execute('PRAGMA journal_mode').fetchone() == ('delete',)
        connection.execute('PRAGMA synchronous=EXTRA')
        connection.execute('PRAGMA cache_size=2')
        connection.execute('PRAGMA cache_spill=1')
        connection.execute('BEGIN IMMEDIATE')
        connection.execute('UPDATE core_bytes SET payload=? WHERE key LIKE ?',
                           (b'b' * 4096, _KEY + '%'))
        connection.execute('INSERT INTO core_bytes VALUES (?, 0, ?)', (_UNCOMMITTED_ROW, b'new'))
        assert journal.read_bytes()[:8] == _MAGIC
        assert sha256(observed.read()).hexdigest() != original[3]
        print(json.dumps({'pid': os.getpid(), 'database': original, 'journal': file_original(journal)}),
              flush=True)
        os.kill(os.getpid(), signal.SIGKILL)


def require_versions(version):
    for name in ('actql', 'actql-sdk', 'actql-local-runtime'):
        if metadata.version(name) != version:
            raise AssertionError('Installed retained-Store fixture cohort changed')


def reopen(state, version, receipt, blocked=False):
    require_versions(version)
    from actql import Client
    from actql_sdk import ClientError

    original = json.loads(receipt.read_bytes())
    installation = state.stat()
    database = state / 'state/client.sqlite3'
    lock_events = []

    def audit(event, args):
        if event == 'fcntl.flock':
            observed = os.fstat(args[0])
            lock_events.append((observed.st_dev, observed.st_ino, args[1]))

    sys.addaudithook(audit)
    if blocked:
        try:
            client = Client.open(state_dir=state)
        except ClientError as refusal:
            failure = refusal.original_error
            while failure is not None and not isinstance(failure, OSError):
                failure = failure.__cause__
            if not isinstance(failure, OSError) or failure.errno not in (EAGAIN, EACCES):
                raise AssertionError('Competing process did not observe the original lease refusal') from refusal
            close = refusal.cleanup_client
            if close is not None:
                close.close()
            reason = refusal.code
        else:
            client.close()
            raise AssertionError('Competing ordinary Local Host acquired the live installation')
        original_lease = (installation.st_dev, installation.st_ino)
        if not any(event[:2] == original_lease and event[2] == (fcntl.LOCK_EX | fcntl.LOCK_NB)
                   for event in lock_events):
            raise AssertionError('Competing process did not reach the exact physical installation lease')
        return {'pid': os.getpid(), 'refused': reason, 'physicalLease': original_lease,
                'firstClose': True}

    db_before = file_original(database)
    client = Client.open(state_dir=state)
    try:
        known = client.lookup_submission(original['submission'])
        if known['kind'] != 'ready' or plain(known['admission']['ref']) != original['run']:
            raise AssertionError('Recovered installation changed the admitted Run')
        run = client.attach(original['run'])
        assert plain(run.ref) == original['run'] and run.status()['status'] == 'succeeded'
        assert run.result('answer').all(max_rows=1) == [{'n': 1}]
        host = client._client._local_host
        database_connection = host._active()._store._connection
        assert database_connection.execute('PRAGMA journal_mode').fetchone() == ('delete',)
        assert database_connection.execute('PRAGMA synchronous').fetchone() == (3,)
    finally:
        client.close()
    assert host._core._closed and not host._core._loans
    assert file_original(database)[:2] == db_before[:2]
    return {'pid': os.getpid(), 'run': original['run'], 'firstClose': True, 'database': db_before[:2]}


def child(*args, code=0):
    captured = subprocess.run([sys.executable, '-I', '-B', __file__, *map(str, args)],
                             timeout=90, capture_output=True, text=True)
    if captured.returncode != code:
        raise AssertionError((captured.returncode, captured.stdout, captured.stderr))
    lines = captured.stdout.splitlines()
    if len(lines) != 1:
        raise AssertionError('Expected one completed child observation')
    return json.loads(lines[0])


def verify(directory, version):
    require_versions(version)
    from actql import Client

    state = directory / 'installation'
    receipt = directory / 'public-original.json'
    client = Client.open(state_dir=state)
    database = state / 'state/client.sqlite3'
    try:
        submission = client.new_submission()
        run = client.start_source('SELECT 1 AS n', format='sql', submission_ref=submission)
        assert run.wait()['status'] == 'succeeded'
        assert run.result('answer').all(max_rows=1) == [{'n': 1}]
        original = {'submission': plain(submission), 'run': plain(run.ref)}
        with receipt.open('x') as file:
            json.dump(original, file)
        before = file_original(database)
        competitor = child('blocked', state, version, receipt)
        assert competitor['pid'] != os.getpid() and file_original(database) == before
        assert not database.with_name(database.name + '-journal').exists()
        host = client._client._local_host
    finally:
        client.close()
    assert host._core._closed and not host._core._loans

    with closing(sqlite3.connect(database, isolation_level=None)) as sqlite:
        assert sqlite.execute('PRAGMA journal_mode').fetchone() == ('delete',)
        sqlite.execute('BEGIN IMMEDIATE')
        sqlite.executemany('INSERT INTO core_bytes VALUES (?, 0, ?)',
                           ((f'{_KEY}{ordinal:03}', _ROW) for ordinal in range(_COUNT)))
        sqlite.execute('COMMIT')
    committed = file_original(database)
    killed = child('spill', database, code=-signal.SIGKILL)
    journal = database.with_name(database.name + '-journal')
    assert tuple(killed['database']) == committed
    assert tuple(killed['journal']) == file_original(journal)
    assert file_original(database)[:2] == committed[:2] and file_original(database)[3] != committed[3]
    recovered = child('reopen', state, version, receipt)
    assert len({os.getpid(), competitor['pid'], killed['pid'], recovered['pid']}) == 4
    assert recovered['firstClose'] and recovered['run'] == original['run']
    assert tuple(recovered['database']) == committed[:2]
    assert not journal.exists()
    with closing(sqlite3.connect(database.as_uri() + '?mode=ro&immutable=1', uri=True)) as sqlite:
        rows = sqlite.execute('SELECT key,generation,payload FROM core_bytes WHERE key LIKE ? ORDER BY key',
                              (_KEY + '%',)).fetchall()
    expected = [(f'{_KEY}{ordinal:03}', 0, _ROW) for ordinal in range(_COUNT)]
    assert rows == expected
    return {'pid': os.getpid(), 'version': version, 'sqlite': sqlite3.sqlite_version, 'run': original['run'],
            'firstClose': True, 'competing': competitor, 'killed': killed, 'reopened': recovered,
            'recoveredCommittedRows': len(rows), 'recoveredUncommittedRows': 0}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('verify', 'blocked', 'reopen', 'spill'))
    parser.add_argument('directory', type=Path)
    parser.add_argument('version', nargs='?')
    parser.add_argument('receipt', nargs='?', type=Path)
    args = parser.parse_args()
    if args.phase == 'spill':
        spill(args.directory)
        raise AssertionError('SQLite child returned without crashing')
    if args.phase == 'verify':
        observed = verify(args.directory, args.version)
    else:
        observed = reopen(args.directory, args.version, args.receipt, args.phase == 'blocked')
    print(json.dumps(observed), flush=True)
