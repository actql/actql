"""An installed lightweight SDK talks directly to the original HTTPS Host."""
import asyncio
from dataclasses import dataclass
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import ssl
import sys

from actql_sdk import AsyncClient, Client, get_submission_input
import actql_sdk

phase, facade, endpoint, token, ca_path, custody = sys.argv[1:]
trust = ssl.create_default_context(cafile=ca_path)
path = Path(custody)
short_query = os.environ.get('ACTQL_TEST_PYTHON_SHORT_QUERY') == '1'
text = ('SELECT ACCOUNT_ID AS account_id, ACTIVE_USERS AS active_users, TREND AS trend '
        'FROM snowflake.usage_30d |> RESULT usage')
expected = [{'account_id': 'a1', 'active_users': '99999999999999999999999999999999999999', 'trend': 'down'},
            {'account_id': 'a2', 'active_users': '0', 'trend': None}]


@dataclass(frozen=True)
class Usage:
    account_id: str
    active_users: str
    trend: str | None


class UsageSchema:
    """Application-owned validation, without optional schema dependencies."""
    @staticmethod
    def validate_python(value, *, strict):
        assert strict is True
        assert set(value) == {'account_id', 'active_users', 'trend'}
        assert type(value['account_id']) is str and type(value['active_users']) is str
        assert value['trend'] is None or type(value['trend']) is str
        return Usage(**value)


def save(reference, run):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        json.dump({'submission': dict(reference, epoch=dict(reference['epoch'])), 'run': dict(run.ref)}, output)


async def asynchronous():
    async with await AsyncClient.connect(endpoint, token, verify=trust) as client:
        if phase == 'normal':
            checked = await client.check(text, kind='text', scope='bound_input', format='sql')
            assert checked['report']['verdict'] == 'verified'
            assert dict(checked['report']['runnable']) == {'verdict': 'yes', 'reasons': ()}
            reference = client.new_submission(nonce='snowflake-python-async')
            if short_query:
                query = client.sql(text, submission_ref=reference, result='usage')
                assert query.execution is None
                assert get_submission_input(query)['readOnly'] is True
                assert await query.all(max_rows=2) == expected
                run = query.execution
                assert run is not None
            else:
                run = await client.start_source(text, format='sql', submission_ref=reference)
            state = await run.wait()
            assert state.status == 'succeeded' and type(state.revision) is int
            result = run.result('usage')
            assert await result.all(max_rows=2) == expected
            async with result.rows() as reader:
                assert await anext(reader) == expected[0]
            try:
                await anext(reader)
            except StopAsyncIteration:
                pass
            else:
                raise AssertionError('Closed reader resumed')
            assert await result.all(schema=UsageSchema, max_rows=2) == [Usage(**row) for row in expected]
            save(reference, run)
        elif phase == 'attach':
            original = json.loads(path.read_text())
            lookup = await client.lookup_submission(original['submission'])
            assert lookup['kind'] == 'ready' and dict(lookup['admission']['ref']) == original['run']
            run = await client.attach(original['run'])
            assert (await run.status()).status == 'succeeded'
            assert await run.result('usage').all(max_rows=2) == expected
            if short_query:
                query = client.sql(text, submission_ref=original['submission'], result='usage')
                assert query.execution is None
                assert await query.all(max_rows=2) == expected
                duplicate = query.execution
                assert duplicate is not None
            else:
                duplicate = await client.start_source(text, format='sql', submission_ref=original['submission'])
            assert dict(duplicate.ref) == original['run']
            assert await duplicate.result('usage').all(max_rows=2) == expected
        else:
            raise AssertionError('Unknown phase')


def synchronous():
    with Client.connect(endpoint, token, verify=trust) as client:
        if phase == 'normal':
            checked = client.check(text, kind='text', scope='bound_input', format='sql')
            assert checked['report']['verdict'] == 'verified'
            assert dict(checked['report']['runnable']) == {'verdict': 'yes', 'reasons': ()}
            reference = client.new_submission(nonce='snowflake-python-sync')
            if short_query:
                query = client.sql(text, submission_ref=reference, result='usage')
                assert query.execution is None
                assert get_submission_input(query)['readOnly'] is True
                assert query.all(max_rows=2) == expected
                run = query.execution
                assert run is not None
            else:
                run = client.start_source(text, format='sql', submission_ref=reference)
            state = run.wait()
            assert state.status == 'succeeded' and type(state.revision) is int
            result = run.result('usage')
            assert result.all(max_rows=2) == expected
            with result.rows() as reader:
                assert next(reader) == expected[0]
            try:
                next(reader)
            except StopIteration:
                pass
            else:
                raise AssertionError('Closed reader resumed')
            assert result.all(schema=UsageSchema, max_rows=2) == [Usage(**row) for row in expected]
            save(reference, run)
        elif phase == 'attach':
            original = json.loads(path.read_text())
            lookup = client.lookup_submission(original['submission'])
            assert lookup['kind'] == 'ready' and dict(lookup['admission']['ref']) == original['run']
            run = client.attach(original['run'])
            assert run.status().status == 'succeeded'
            assert run.result('usage').all(max_rows=2) == expected
            if short_query:
                query = client.sql(text, submission_ref=original['submission'], result='usage')
                assert query.execution is None
                assert query.all(max_rows=2) == expected
                duplicate = query.execution
                assert duplicate is not None
            else:
                duplicate = client.start_source(text, format='sql', submission_ref=original['submission'])
            assert dict(duplicate.ref) == original['run']
            assert duplicate.result('usage').all(max_rows=2) == expected
        else:
            raise AssertionError('Unknown phase')


# The SDK-only environment must actually lack the optional Local engines.
assert importlib.util.find_spec('wasmtime') is None
assert importlib.util.find_spec('actql_local_runtime') is None
assert 'actql_sdk._local_core' not in sys.modules
if facade == 'async':
    asyncio.run(asynchronous())
elif facade == 'sync':
    synchronous()
else:
    raise AssertionError('Unknown facade')
assert 'actql_sdk._local_core' not in sys.modules
print(json.dumps({'phase': phase, 'facade': facade, 'success': True, 'pid': os.getpid(),
                  'surface': 'sql' if short_query else 'start_source',
                  'sdk': str(Path(actql_sdk.__file__).resolve()),
                  'version': importlib.metadata.version('actql-sdk')}))
