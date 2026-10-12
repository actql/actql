"""Public wheel consumers. This file imports no repository implementation."""
import asyncio
import json
import inspect
import os
from pathlib import Path
import ssl
import sys
from actql_sdk import (AsyncClient, Client, ClientError, Observation, get_check_input,
                        get_submission_check_observation, resolve_check_location, resolve_check_text_range,
                        explain_check_reason)

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


def authoring_program():
    return {'version': 'actql/0.1', 'id': 'python-authoring', 'params': {'x': {'type': 'number'}},
            'stages': [{'id': 'first', 'inputs': {}, 'steps': [
                {'values': {'schema': {'id': {'type': 'number', 'nullable': False}}, 'rows': [{'id': 1}]}, 'as': 'seed'},
                {'derive': {'n': 'id + $x'}}, {'select': ['n'], 'as': 'output'}],
                'results': {'out': {'from': 'output', 'fields': ['n']}}}],
            'results': {'out': {'from': {'stage': 'first', 'result': 'out'}}}}


def structured_checks(client):
    for scope in ['template_only', 'bound_input']:
        for missing in [True, False]:
            program = authoring_program()
            if missing:
                del program['stages'][0]['steps']
            else:
                program['stages'][0]['steps'] = None
            checked = yield client.check(program, kind='program', scope=scope)
            assert checked['report']['verdict'] == 'invalid'
            reason = checked['report']['reasons'][0]
            assert reason['code'] == 'program_structure_invalid'
            assert dict(reason['facts']) == {'issue': 'missing_field' if missing else 'unexpected_null'}
            pointer = '/stages/0' if missing else '/stages/0/steps'
            assert reason['location']['pointer'] == pointer
            assert resolve_check_location(checked, reason['location'])['pointer'] == pointer
            assert resolve_check_text_range(checked, reason['location']) is None
    key = 'e\u0301/~😀'
    program = authoring_program()
    program['params'] = {'payload': {'type': 'object', 'fields': {key: {'type': 'number'}}}}
    program['stages'][0]['steps'][1]['derive']['n'] = '$payload'
    for value, actual in [('private-leaf', 'string'), (None, 'null')]:
        parameters = {'payload': {key: value}}
        pending = client.check(program, kind='program', scope='bound_input', parameters=parameters)
        parameters['payload'][key] = 23
        checked = yield pending
        assert checked['report']['verdict'] == 'invalid'
        reason = checked['report']['reasons'][0]
        assert dict(reason['facts']) == {'parameter': 'payload', 'expected_type': 'number', 'actual_type': actual}
        assert reason['location']['pointer'] == '/payload/e\u0301~1~0😀'
        owned = get_check_input(checked, 'parameters')
        assert owned['value']['payload'][key] == value
        assert get_check_input(Observation(checked.to_dict()), 'parameters') is None
        assert resolve_check_location(checked, dict(reason['location'], revision='rev:' + '0' * 64)) is None
        assert 'private-leaf' not in json.dumps(checked.to_dict(), ensure_ascii=False)
        assert 'private-leaf' not in json.dumps(dict(explain_check_reason(reason)))
    absent = yield client.check(program, kind='program', scope='bound_input', parameters={})
    assert absent['report']['verdict'] == 'undetermined'
    assert absent['report']['requirements'][0]['location']['pointer'] == '/params/payload'
    assert 'payload' not in get_check_input(absent, 'parameters')['value']


def authored_executions(client):
    program = authoring_program()
    del program['params']
    program['stages'][0]['steps'][1]['derive']['n'] = 'id + 1'
    run = yield client.start(program,
        submission_ref=client.new_submission(nonce='python-program-' + facade))
    assert (yield run.wait())['status'] == 'succeeded'
    assert (yield run.result('out').all(max_rows=1)) == [{'n': 2}]
    text = 'WITH seed AS (SELECT 1 AS n) FROM seed |> EXTEND n + 1 AS value |> SELECT value |> RESULT answer'
    run = yield client.start_source(text, format='aql-text',
        submission_ref=client.new_submission(nonce='python-aql-' + facade))
    assert (yield run.wait())['status'] == 'succeeded'
    assert (yield run.result('answer').all(max_rows=1)) == [{'value': 2}]


def number_roundtrips(client):
    for sign in [1, -1]:
        number = sign * float.fromhex('0x1p+63')
        run = yield client.start_source('SELECT @x AS n', format='sql',
            submission_ref=client.new_submission(nonce=f'python-number-{facade}-{sign}'),
            parameter_declarations={'x': {'type': 'number'}}, parameters={'x': number})
        assert (yield run.wait())['status'] == 'succeeded'
        rows = yield run.result('answer').all(max_rows=1)
        assert rows == [{'n': number}]
        assert type(rows[0]['n']) is float
        assert rows[0]['n'].hex() == number.hex()


async def run_async_steps(steps):
    value = None
    while True:
        try:
            pending = steps.send(value)
        except StopIteration:
            return
        value = await pending if inspect.isawaitable(pending) else pending


def run_sync_steps(steps):
    value = None
    while True:
        try:
            value = steps.send(value)
        except StopIteration:
            return


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
        elif phase == 'structured':
            await run_async_steps(structured_checks(client))
        elif phase == 'numbers':
            await run_async_steps(number_roundtrips(client))
        elif phase == 'authored':
            await run_async_steps(authored_executions(client))
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
        elif phase == 'structured':
            run_sync_steps(structured_checks(client))
        elif phase == 'numbers':
            run_sync_steps(number_roundtrips(client))
        elif phase == 'authored':
            run_sync_steps(authored_executions(client))
        else:
            raise AssertionError('Unknown public phase')


try:
    if facade == 'async':
        asyncio.run(asynchronous())
    elif facade == 'sync':
        synchronous()
    else:
        raise AssertionError('Unknown facade')
except ClientError as error:
    checked = get_submission_check_observation(error)
    document = checked.to_dict() if checked is not None else {}
    report = document.get('report', document.get('partial_report', {}))
    raise AssertionError(json.dumps({'phase': phase, 'code': error.code,
        'reasons': report.get('reasons', []), 'requirements': report.get('requirements', [])})) from None
print(json.dumps({'phase': phase, 'facade': facade, 'success': True}))
