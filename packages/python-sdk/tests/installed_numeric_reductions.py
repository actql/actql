"""Verify the public source-free numeric profile in a normal wheel install."""
from collections.abc import Mapping
import json
import os
from pathlib import Path
import stat
import sys

from actql import Client
from actql_sdk._local_distribution import installed_local_components


PIVOT = """WITH r AS (
  SELECT 'east' AS side, 1 AS v UNION ALL
  SELECT 'west', 2 UNION ALL SELECT 'west', 3
)
FROM r |> PIVOT(SUM(v) FOR side IN ('east','west'))"""
VALUES = 'WITH r AS (SELECT 1 AS v UNION ALL SELECT 2 UNION ALL SELECT 3)'
CASES = (
    ('pivot', PIVOT, 'aql-text', [{'east': 1, 'west': 5}]),
    ('sum', VALUES + ' SELECT SUM(v) AS n FROM r', 'sql', [{'n': 6}]),
    ('count', VALUES + ' SELECT COUNT(v) AS n FROM r', 'sql', [{'n': 3}]),
)


def plain(value):
    if isinstance(value, Mapping):
        return {key: plain(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(item) for item in value]
    return value


def result(run, expected):
    actual = run.result('answer').all(max_rows=1)
    assert json.dumps(actual, sort_keys=True) == json.dumps(expected, sort_keys=True)


def initial(client):
    unsupported = client.check("SELECT PARSE_TIMESTAMP('yyyy-MM-dd', '2026-01-02') AS x",
                               kind='text', scope='bound_input', format='sql')
    assert unsupported.outcome == 'completed'
    assert unsupported.report.to_dict()['verdict'] == 'undetermined'
    originals = {}
    for name, statement, syntax, expected in CASES:
        check = client.check(statement, kind='text', scope='bound_input', format=syntax)
        assert check.outcome == 'completed'
        report = check.report.to_dict()
        assert report['verdict'] == 'verified' and not report['requirements'], name
        submission = client.new_submission()
        run = client.start_source(statement, format=syntax, submission_ref=submission)
        assert run.wait()['status'] == 'succeeded', name
        result(run, expected)
        originals[name] = {'submission': plain(submission), 'run': plain(run.ref)}
    return originals


def saved(client, originals):
    for name, _, _, expected in CASES:
        item = originals[name]
        observed = client.lookup_submission(item['submission'])
        assert observed['kind'] == 'ready'
        assert plain(observed['admission']['ref']) == item['run']
        run = client.attach(item['run'])
        assert plain(run.ref) == item['run'] and run.status()['status'] == 'succeeded'
        result(run, expected)


def main(phase, source, module):
    seal = installed_local_components()
    assert (seal.source_sha, seal.module_sha256) == (source, module)
    receipt = Path.cwd() / 'originals.json'
    state = receipt.with_name('state')
    if phase == 'initial':
        assert not os.path.lexists(receipt) and not os.path.lexists(state)
        with Client.open(state_dir=state) as client:
            originals = initial(client)
        data = (json.dumps({'pid': os.getpid(), 'originals': originals}) + '\n').encode()
        assert len(data) <= 65536
        with os.fdopen(os.open(receipt, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600), 'wb') as out:
            out.write(data)
    else:
        assert phase == 'saved'
        with os.fdopen(os.open(receipt, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as original:
            info = os.fstat(original.fileno())
            assert stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and not info.st_mode & 0o077
            data = original.read(65537)
        assert len(data) == info.st_size <= 65536
        body = json.loads(data)
        assert type(body['pid']) is int and body['pid'] > 0 and body['pid'] != os.getpid()
        assert set(body['originals']) == {case[0] for case in CASES}
        with Client.open(state_dir=state) as client:
            saved(client, body['originals'])
    print(json.dumps({'phase': phase, 'pid': os.getpid(), 'source': source, 'module': module,
                      'cases': [case[0] for case in CASES], 'first_close': True}), flush=True)


if __name__ == '__main__':
    main(*sys.argv[1:])
