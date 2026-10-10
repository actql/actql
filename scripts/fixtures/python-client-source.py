"""External wheel acceptance; the application owns the signing key."""
import asyncio
import inspect
import json
import os
from pathlib import Path
import ssl
import sys
import time
from cryptography.hazmat.primitives.serialization import load_pem_private_key
from actql_sdk import AsyncClient, Client, Signer

phase, facade, endpoint, installation_path, custody_path = sys.argv[1:]
installation = json.loads(Path(installation_path).read_text())
trust = ssl.create_default_context(cafile=installation['hostTls']['certificatePath'])
custody = Path(custody_path)


def save_original(value):
    with os.fdopen(os.open(custody, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        json.dump(value, output, ensure_ascii=False)


def exercise(client):
    if phase == 'submit':
        reference = client.new_submission(nonce='python-source-' + facade)
        save_original({'submission': dict(reference, epoch=dict(reference['epoch']))})
        run = yield client.start(json.loads(installation['program']), submission_ref=reference)
        original = json.loads(custody.read_text())
        original['run'] = dict(run.ref)
        with custody.open('w') as output:
            json.dump(original, output)
        target = 'waiting_checkpoint'
    else:
        original = json.loads(custody.read_text())
        lookup = yield client.lookup_submission(original['submission'])
        assert lookup['kind'] == 'ready'
        assert dict(lookup['admission']['ref']) == original['run']
        run = yield client.attach(original['run'])
        target = 'succeeded'
        if phase == 'approve':
            page = yield client.checkpoints()
            assert len(page['items']) == 1
            checkpoint = page['items'][0]
            assert checkpoint['kind'] == 'effect_set'
            review = yield client.review_checkpoint(checkpoint)
            assert len(review['bytes']) > 0
            key = load_pem_private_key(installation['reviewerPrivateKey'].encode(), password=None)
            signer = Signer('reviewer-key', 'reviewer', key.sign, original['run']['authorityScopeCid'])
            answer = yield client.resolve_checkpoints([{'checkpoint': dict(checkpoint), 'decision': 'approved'}], signer=signer)
            assert len(answer['results']) == 1
            assert answer['results'][0]['status'] == 'committed'
            # The shared installation deliberately sets resumeAfterAnswer=False.
            # The next real Host startup owns continuation of the saved answer.
            return
        elif phase == 'cancel':
            before = yield run.status()
            assert before['status'] == 'waiting_checkpoint'
            conflict = yield run.cancel(cancel_id='future-revision',
                expected_revision=before['control']['revision'] + 1, attempt_id='conflict-invocation')
            assert conflict['kind'] == 'conflict'
            assert conflict['reason'] == 'control_revision'
            assert (yield run.status())['status'] == 'waiting_checkpoint'
            accepted = yield run.cancel(cancel_id='waiting-run-cancel',
                expected_revision=before['control']['revision'], attempt_id='cancel-invocation')
            assert accepted['kind'] == 'accepted'
            assert accepted['cancellation']['kind'] == 'accepted'
            cancellation = accepted['cancellation']['cancelRef']
            found = yield run.lookup_cancellation(cancellation)
            assert found['kind'] == 'found'
            assert found['cancellation'] == accepted['cancellation']
            original['cancellation'] = dict(cancellation)
            with custody.open('w') as output:
                json.dump(original, output)
            target = 'cancelled'
        elif phase == 'cancelled':
            found = yield run.lookup_cancellation(original['cancellation'])
            assert found['kind'] == 'found'
            assert dict(found['cancellation']['cancelRef']) == original['cancellation']
            target = 'cancelled'
        else:
            assert phase == 'finish'
    deadline = time.monotonic() + 60
    while True:
        state = yield run.status()
        if state['status'] == target:
            break
        assert state['status'] not in ('failed', 'cancelled', 'needs_reconciliation'), state['status']
        assert time.monotonic() < deadline, 'Source acceptance timed out'
        yield asyncio.sleep(.025) if facade == 'async' else time.sleep(.025)
    if target == 'cancelled':
        assert len((yield client.checkpoints())['items']) == 0
        return
    if phase != 'submit':
        # Independent values from the three initial provider records and the
        # authored filter/concat, never a copy of a previous product reply.
        rows = yield run.result('updates').all(max_rows=3)
        assert rows == [
            {'Id': 'a00000000000001', 'next_name': 'key-1-processed'},
            {'Id': 'a00000000000003', 'next_name': 'key-3-processed'}]


async def asynchronous():
    async with await AsyncClient.connect(endpoint, 'owner-token', verify=trust) as client:
        steps = exercise(client)
        value = None
        while True:
            try:
                pending = steps.send(value)
            except StopIteration:
                break
            value = await pending if inspect.isawaitable(pending) else pending


def synchronous():
    with Client.connect(endpoint, 'owner-token', verify=trust) as client:
        steps = exercise(client)
        value = None
        while True:
            try:
                value = steps.send(value)
            except StopIteration:
                break


if facade == 'async':
    asyncio.run(asynchronous())
else:
    assert facade == 'sync'
    synchronous()
print(json.dumps({'phase': phase, 'facade': facade, 'success': True}))
