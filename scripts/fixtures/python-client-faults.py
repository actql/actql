"""Original-operation faults against a real Host, with shared facade fixtures."""
import asyncio
import inspect
import json
import os
from pathlib import Path
import ssl
import sys
from actql_sdk import AsyncClient, Client, ClientError, get_submission_input

phase, facade, endpoint, ca_path, custody_path = sys.argv[1:]
trust = ssl.create_default_context(cafile=ca_path)
path = Path(custody_path)


def retain(value):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        json.dump(value, output)


def exercise(client):
    if phase == 'issue':
        reference = client.new_submission(nonce='python-expired-' + facade)
        retain({'submission': dict(reference, epoch=dict(reference['epoch']))})
        return
    if phase == 'submit-loss':
        reference = client.new_submission(nonce='python-response-loss-' + facade)
        retain({'submission': dict(reference, epoch=dict(reference['epoch']))})
        try:
            yield client.start_source('SELECT 1 AS n', format='sql', submission_ref=reference, attempt_id='original-attempt')
        except ClientError as error:
            assert error.code == 'SubmissionUnknown'
            assert error.submission_ref == reference
            assert dict(error.attempt_ref) == {'operation': 'submit', 'attemptId': 'original-attempt'}
            assert get_submission_input(error)['input']['text'] == 'SELECT 1 AS n'
        else:
            raise AssertionError('Submission response was not lost')
        return
    original = json.loads(path.read_text())
    if phase == 'expired':
        try:
            yield client.start_source('SELECT 1 AS n', format='sql', submission_ref=original['submission'], attempt_id='expired-attempt')
        except ClientError as error:
            assert error.code == 'SubmissionRefused'
            assert error.outcome['reason'] == 'epoch_expired'
            assert error.outcome['guarantee'] == 'attempt_uncommitted_unconsumed'
            assert error.submission_ref == original['submission']
        else:
            raise AssertionError('Expired epoch was accepted')
        return
    lookup = yield client.lookup_submission(original['submission'])
    assert lookup['kind'] == 'ready'
    run = yield client.attach(lookup['admission']['ref'])
    if phase == 'malformed':
        try:
            yield run.status()
        except ClientError as error:
            assert error.code == 'InvalidHostRunState'
        else:
            raise AssertionError('Foreign status field was accepted')
        return
    assert (yield run.wait())['status'] == 'succeeded'
    if phase == 'cancel-loss':
        state = yield run.status()
        expected = dict(run.ref, cancelId='original-cancel', expectedRevision=state['control']['revision'])
        try:
            yield run.cancel(cancel_id='original-cancel', expected_revision=expected['expectedRevision'], attempt_id='original-cancel-attempt')
        except ClientError as error:
            assert error.code == 'CancellationUnknown'
            assert dict(error.cancel_ref) == expected
            assert dict(error.attempt_ref) == {'operation': 'cancel', 'attemptId': 'original-cancel-attempt'}
        else:
            raise AssertionError('Cancellation response was not lost')
        found = yield run.lookup_cancellation(expected)
        assert found['kind'] == 'found'
        assert dict(found['cancellation']['cancelRef']) == expected
        assert (yield run.status())['status'] == 'succeeded'
    elif phase == 'read-loss':
        reader = run.result('answer').rows()
        advance = reader.__anext__ if facade == 'async' else reader.__next__
        try:
            assert (yield advance()) == {'n': 1}
            try:
                yield advance()
            except ClientError as error:
                assert error.code in ('IncompleteResultStream', 'ReadOutcomeUnknown')
                assert error.attempt_id == reader.attempt_id
                assert error.rows_yielded == 1
            else:
                raise AssertionError('Interrupted stream was treated as complete')
        finally:
            yield reader.aclose() if facade == 'async' else reader.close()
        delivery = yield reader.delivery_attempt()
        assert delivery['kind'] == 'found'
        assert delivery['attempt']['attempt_id'] == reader.attempt_id
        assert delivery['record'] is None or delivery['record']['state'] != 'succeeded'
    else:
        assert phase == 'lookup'
        assert (yield run.result('answer').all(max_rows=1)) == [{'n': 1}]


async def asynchronous():
    try:
        client = await AsyncClient.connect(endpoint, 'owner-token', verify=trust)
    except ClientError as error:
        assert phase == 'revoked' and error.code == 'ClientAuthenticationDenied'
        return
    assert phase != 'revoked'
    async with client:
        steps, value, failure = exercise(client), None, None
        while True:
            try:
                pending = steps.throw(failure) if failure is not None else steps.send(value)
            except StopIteration:
                return
            failure = None
            try:
                value = await pending if inspect.isawaitable(pending) else pending
            except BaseException as error:
                failure = error


def synchronous():
    try:
        client = Client.connect(endpoint, 'owner-token', verify=trust)
    except ClientError as error:
        assert phase == 'revoked' and error.code == 'ClientAuthenticationDenied'
        return
    assert phase != 'revoked'
    with client:
        steps, value = exercise(client), None
        while True:
            try:
                value = steps.send(value)
            except StopIteration:
                return


if facade == 'async':
    asyncio.run(asynchronous())
else:
    assert facade == 'sync'
    synchronous()
print(json.dumps({'phase': phase, 'facade': facade, 'success': True}))
