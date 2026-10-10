"""Public wheel consumers. This file imports no repository implementation."""
import asyncio
import json
import os
from pathlib import Path
import ssl
import sys
from actql_sdk import (AsyncClient, Client, ClientError, Observation, get_check_input,
                        get_submission_check_observation, resolve_check_location, explain_check_reason)

phase, facade, endpoint, ca_path, custody_path = sys.argv[1:]
trust = ssl.create_default_context(cafile=ca_path)
path = Path(custody_path)


def retain_original(reference, run):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        json.dump({'submission': dict(reference, epoch=dict(reference['epoch'])), 'run': dict(run.ref)}, output)


def verify_diagnostic(error):
    assert error.code == 'SubmissionNotAccepted', error.code
    check = get_submission_check_observation(error)
    assert check['outcome'] == 'completed'
    assert check['report']['verdict'] == 'invalid'
    assert get_check_input(check, 'source')['text'] == 'SELECT ('
    assert get_check_input(Observation(check.to_dict()), 'source') is None
    reasons = check['report']['reasons']
    assert len(reasons) == 1
    assert reasons[0]['code'] == 'query_syntax_invalid'
    location = resolve_check_location(check, reasons[0]['location'])
    assert location is not None
    assert location['start_byte'] == 8 and location['end_byte'] == 8
    assert explain_check_reason(reasons[0])['kind'] == 'known'


async def asynchronous():
    async with await AsyncClient.connect(endpoint, 'fixture-token', verify=trust) as client:
        if phase == 'normal':
            reference = client.new_submission(nonce='python-async')
            run = await client.start_source('SELECT 1 AS n', format='sql', submission_ref=reference)
            assert (await run.wait())['status'] == 'succeeded'
            assert await run.result('answer').all(max_rows=10) == [{'n': 1}]
            retain_original(reference, run)
        elif phase == 'reattach':
            original = json.loads(path.read_text())
            lookup = await client.lookup_submission(original['submission'])
            assert lookup['kind'] == 'ready'
            assert dict(lookup['admission']['ref']) == original['run']
            run = await client.attach(original['run'])
            assert (await run.status())['status'] == 'succeeded'
            assert await run.result('answer').all(max_rows=10) == [{'n': 1}]
        elif phase == 'diagnostics':
            try:
                await client.start_source('SELECT (', format='sql', submission_ref=client.new_submission(nonce='python-async-invalid'))
            except ClientError as error:
                verify_diagnostic(error)
            else:
                raise AssertionError('Invalid input was admitted')
        else:
            raise AssertionError('Unknown public phase')


def synchronous():
    with Client.connect(endpoint, 'fixture-token', verify=trust) as client:
        if phase == 'normal':
            reference = client.new_submission(nonce='python-sync')
            run = client.start_source('SELECT 1 AS n', format='sql', submission_ref=reference)
            assert run.wait()['status'] == 'succeeded'
            assert run.result('answer').all(max_rows=10) == [{'n': 1}]
            retain_original(reference, run)
        elif phase == 'reattach':
            original = json.loads(path.read_text())
            lookup = client.lookup_submission(original['submission'])
            assert lookup['kind'] == 'ready'
            assert dict(lookup['admission']['ref']) == original['run']
            run = client.attach(original['run'])
            assert run.status()['status'] == 'succeeded'
            assert run.result('answer').all(max_rows=10) == [{'n': 1}]
        elif phase == 'diagnostics':
            try:
                client.start_source('SELECT (', format='sql', submission_ref=client.new_submission(nonce='python-sync-invalid'))
            except ClientError as error:
                verify_diagnostic(error)
            else:
                raise AssertionError('Invalid input was admitted')
        else:
            raise AssertionError('Unknown public phase')


if facade == 'async':
    asyncio.run(asynchronous())
elif facade == 'sync':
    synchronous()
else:
    raise AssertionError('Unknown facade')
print(json.dumps({'phase': phase, 'facade': facade, 'success': True}))
