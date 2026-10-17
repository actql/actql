"""Installed public names against the real journal; no replay implementation."""
import asyncio
import inspect
import json
from pathlib import Path
import ssl
import sys

import actql_sdk
from actql_sdk import AsyncClient, Client, ClientError, RequestConflict, get_submission_input

phase, facade, surface, loss, endpoint, ca, saved_path = sys.argv[1:]
assert Path(actql_sdk.__file__).resolve().is_relative_to(Path(sys.prefix).resolve())
trust = ssl.create_default_context(cafile=ca)
path = Path(saved_path)


def plain(value):
    if hasattr(value, 'items'):
        return {key: plain(child) for key, child in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(child) for child in value]
    return value


def steps(client):
    text = 'SELECT @n AS n'
    options = {'parameters': {'n': 7}, 'request_id': 'nightly-' + facade + '-' + surface,
               'parameter_declarations': {'n': {'type': 'number', 'nullable': False}}}

    def start(**override):
        return client.start_source(text, format='sql', read_only=True, **(options | override))

    def query():
        return client.sql(text, **options)

    if phase == 'first':
        try:
            if surface == 'query':
                handle = query()
                assert handle.execution is None
                rows = yield handle.all(max_rows=10)
                execution = handle.execution
            else:
                execution = yield start()
                assert (yield execution.wait()).status == 'succeeded'
                rows = yield execution.result('answer').all(max_rows=10)
            assert loss == 'normal', 'The original named reply must be lost'
        except ClientError as failure:
            assert loss == 'lost' and failure.code == 'SubmissionUnknown', failure.code
            assert failure.request_id == options['request_id']
            assert failure.attempt_ref['operation'] == 'submit'
            assert get_submission_input(failure)['requestName'] == options['request_id']
            # Bounded fixture observation of the one original candidate. The
            # SDK has no polling/retry Owner and sends no second named request.
            for _ in range(100):
                outcome = yield client.lookup_submission(failure.submission_ref)
                if outcome['kind'] == 'ready':
                    break
                yield asyncio.sleep(0.02)
            assert outcome['kind'] == 'ready', outcome['kind']
            execution = yield client.attach(outcome['admission']['ref'])
            original_submission = plain(outcome)
            assert (yield execution.wait()).status == 'succeeded'
            rows = yield execution.result('answer').all(max_rows=10)
        else:
            original_submission = plain(execution.submission)
        assert rows == [{'n': 7}]
        saved = {'ref': plain(execution.ref), 'original': original_submission,
                 'requestName': options['request_id']}
        path.write_text(json.dumps(saved))
    elif phase == 'restore':
        saved = json.loads(path.read_text())
        if surface == 'query':
            handle = query()
            assert (yield handle.all(max_rows=10)) == [{'n': 7}]
            execution = handle.execution
        else:
            execution = yield start()
        assert plain(execution.ref) == saved['ref']
        assert plain(execution.submission['submissionRef']) == saved['original']['submissionRef']
        captured = get_submission_input(handle if surface == 'query' else execution)
        assert captured['requestName'] == saved['requestName']
        assert plain(captured['submissionRef']['epoch']) != saved['original']['submissionRef']['epoch'], 'A fresh Host proposes another epoch, but the name resolves the retained original'
        assert (yield execution.wait()).status == 'succeeded'
        for _ in range(2):
            assert (yield execution.result('answer').all(max_rows=10)) == [{'n': 7}]
        attached = yield client.attach(saved['ref'])
        assert (yield attached.result('answer').all(max_rows=10)) == [{'n': 7}]
        for override in ({'parameters': {'n': 8}}, {'stop_before': 'commit'}):
            try:
                yield start(**override)
                raise AssertionError('A changed intent replaced the original Run')
            except RequestConflict as failure:
                assert failure.code == 'RequestConflict'
                assert failure.request_id == saved['requestName']
                assert failure.outcome['kind'] == 'conflict'
        lookup = yield client.lookup_submission(saved['original']['submissionRef'])
        assert lookup['kind'] == 'ready'
        assert plain(lookup['admission']['ref']) == saved['ref']
        assert json.loads(path.read_text()) == saved
    else:
        raise AssertionError('Unknown fixture phase')


async def asynchronous():
    async with await AsyncClient.connect(endpoint, 'owner-token', verify=trust) as client:
        operations = steps(client)
        try:
            pending = next(operations)
        except StopIteration:
            return
        while True:
            try:
                value = await pending if inspect.isawaitable(pending) else pending
            except BaseException as error:
                try:
                    pending = operations.throw(error)
                except StopIteration:
                    return
            else:
                try:
                    pending = operations.send(value)
                except StopIteration:
                    return


def synchronous():
    with Client.connect(endpoint, 'owner-token', verify=trust) as client:
        operations = steps(client)
        try:
            pending = next(operations)
        except StopIteration:
            return
        while True:
            # The only coroutine on this surface is the fixture's bounded
            # observation delay, never an SDK operation or repeated submit.
            value = asyncio.run(pending) if inspect.isawaitable(pending) else pending
            try:
                pending = operations.send(value)
            except StopIteration:
                return


if facade == 'async':
    asyncio.run(asynchronous())
elif facade == 'sync':
    synchronous()
else:
    raise AssertionError('Unknown facade')
print(json.dumps({'phase': phase, 'facade': facade, 'surface': surface, 'loss': loss,
                  'success': True, 'sdk': str(Path(actql_sdk.__file__).resolve())}))
