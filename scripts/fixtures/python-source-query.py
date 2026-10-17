"""Outside-root normal SDK-only wheel consumer; actual Remote HTTPS, not Local."""
import asyncio
import inspect
import json
from pathlib import Path
import ssl
import sys

from actql_sdk import AsyncClient, Client, ClientError, get_submission_input
from pydantic import BaseModel

phase, facade, endpoint, ca, custody = sys.argv[1:]
trust = ssl.create_default_context(cafile=ca)
path = Path(custody)
import actql_sdk
assert Path(actql_sdk.__file__).resolve().is_relative_to(Path(sys.prefix).resolve())
assert not Path(actql_sdk.__file__).resolve().is_relative_to(Path.cwd() / 'packages')


class Row(BaseModel):
    n: int


class Value(BaseModel):
    value: int


def steps(client):
    if phase == 'query':
        sql = client.sql('SELECT @n AS n', {'n': 7}, request_id='lazy-sql-' + facade,
            parameter_declarations={'n': {'type': 'number', 'nullable': False}})
        aql = client.aql('WITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer',
            request_id='lazy-aql-' + facade)
        assert sql.execution is None and aql.execution is None
        assert get_submission_input(sql)['readOnly'] is True
        assert get_submission_input(aql)['readOnly'] is True
        assert (yield sql.all(schema=Row, max_rows=10)) == [Row(n=7)]
        assert (yield sql.all(max_rows=10)) == [{'n': 7}]
        reader = aql.rows(schema=Value)
        # The exact existing reader owns local interruption/cleanup. No Run
        # cancellation, Host completion or remote physical stop is inferred.
        if facade == 'async':
            async def prefix():
                async with reader:
                    assert await anext(reader) == Value(value=2)
                    assert reader.rows_yielded == 1
            yield prefix()
        else:
            with reader:
                assert next(reader) == Value(value=2)
                assert reader.rows_yielded == 1
        assert (yield aql.all(max_rows=10)) == [{'value': 2}]
        saved = []
        for query in (sql, aql):
            original = get_submission_input(query)
            saved.append({'ref': dict(query.execution.ref),
                'submission': {'epoch': dict(original['submissionRef']['epoch']),
                               'nonce': original['submissionRef']['nonce']},
                'intentCid': original['intentCid']})
        path.write_text(json.dumps(saved))
    elif phase == 'restore':
        for saved, expected in zip(json.loads(path.read_text()), [[{'n': 7}], [{'value': 2}]]):
            lookup = yield client.lookup_submission(saved['submission'])
            assert lookup['kind'] == 'ready'
            assert lookup['intentCid'] == saved['intentCid']
            assert dict(lookup['admission']['ref']) == saved['ref']
            execution = yield client.attach(saved['ref'])
            state = yield execution.status()
            assert state.status == 'succeeded'
            assert (yield execution.result('answer').all(max_rows=10)) == expected
    else:
        raise AssertionError('Unknown query phase')


async def asynchronous():
    args = (endpoint,) if endpoint.startswith('actql://token:') else (endpoint, 'fixture-token')
    if phase == 'refusal':
        try:
            async with await AsyncClient.connect(*args, verify=trust):
                raise AssertionError('Foreign Workspace connected')
        except ClientError as failure:
            assert failure.code == 'ClientConnectionDenied'
        return
    async with await AsyncClient.connect(*args, verify=trust) as client:
        program = steps(client); value = None
        while True:
            try: pending = program.send(value)
            except StopIteration: return
            value = await pending if inspect.isawaitable(pending) else pending


def synchronous():
    args = (endpoint,) if endpoint.startswith('actql://token:') else (endpoint, 'fixture-token')
    if phase == 'refusal':
        try:
            with Client.connect(*args, verify=trust):
                raise AssertionError('Foreign Workspace connected')
        except ClientError as failure:
            assert failure.code == 'ClientConnectionDenied'
        return
    with Client.connect(*args, verify=trust) as client:
        program = steps(client); value = None
        while True:
            try: value = program.send(value)
            except StopIteration: return


if facade == 'async': asyncio.run(asynchronous())
elif facade == 'sync': synchronous()
else: raise AssertionError('Unknown facade')
print(json.dumps({'phase': phase, 'facade': facade, 'success': True}))
