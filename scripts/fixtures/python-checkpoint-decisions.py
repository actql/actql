"""Installed Remote consumer; the application, not the SDK, owns Ed25519."""
import asyncio
import inspect
import json
import os
from pathlib import Path
import ssl
import sys

from cryptography.hazmat.primitives.serialization import load_pem_private_key
import actql_sdk
from actql_sdk import AsyncClient, Client, Signer

assert Path(actql_sdk.__file__).resolve().is_relative_to(
    Path('/private/tmp/actql-e-checkpoint-https-installed-20261017'))
assert 'actql_sdk._local_core' not in sys.modules

phase, facade, decision, endpoint, installation_path, custody_path = sys.argv[1:]
installation = json.loads(Path(installation_path).read_text())
custody = Path(custody_path)
original = None if phase == 'submit' else json.loads(custody.read_text())
key = load_pem_private_key(installation['reviewerPrivateKey'].encode(), password=None)
signed = []


def sign(raw):
    signed.append(raw)
    return key.sign(raw)


# The prior accepted Run carries this same Host's original authority scope.
# It is not inferred from an ID, a freshly minted Run or a changed profile.
signer = Signer('reviewer-key', 'reviewer', sign,
                None if original is None else original['run']['authorityScopeCid'])
trust = ssl.create_default_context(cafile=installation['hostTls']['certificatePath'])


def save(value):
    with os.fdopen(os.open(custody, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
        json.dump(value, output)


def exercise(client):
    if phase == 'submit':
        submission = client.new_submission(nonce='checkpoint-' + facade + '-' + decision)
        run = yield client.start(json.loads(installation['program']), submission_ref=submission)
        state = yield run.wait()
        assert state.status == 'waiting_checkpoint', state.status
        save({'submission': dict(submission, epoch=dict(submission['epoch'])),
              'run': dict(run.ref), 'revision': state.revision,
              'checkpoint': dict(state.checkpoint)})
        assert not signed
        return
    lookup = yield client.lookup_submission(original['submission'])
    assert lookup['kind'] == 'ready'
    assert dict(lookup['admission']['ref']) == original['run']
    run = yield client.attach(original['run'])
    if phase == 'decide':
        answer = yield getattr(client, decision)(original['checkpoint']['checkpointId'])
        item, = answer['signed']
        resolution = json.loads(item['resolutionWire'])
        assert resolution['checkpoint_id'] == original['checkpoint']['checkpointId']
        assert resolution['checkpoint_cid'] == original['checkpoint']['checkpointCid']
        assert resolution['run_id'] == original['run']['runId']
        assert resolution['decision'] == ('approved' if decision == 'approve' else 'rejected')
        if decision == 'approve':
            assert item['approvalEvidenceWire'] != ''
        else:
            assert item['approvalEvidenceWire'] == ''
        result, = answer['results']
        assert result['status'] == 'committed'
        assert result['resolutionCid'] == resolution['resolution_cid']
        assert len(signed) == (2 if decision == 'approve' else 1)
        return
    assert phase in ('finish', 'observe')
    state = yield run.wait(since=original['revision'])
    assert state.status == ('succeeded' if decision == 'approve' else 'cancelled'), state.status
    assert state.revision > original['revision']
    if decision == 'approve' and phase == 'finish':
        rows = yield run.result('updates').all(max_rows=3)
        assert rows == [{'Id': 'a00000000000001', 'next_name': 'key-1-processed'},
                        {'Id': 'a00000000000003', 'next_name': 'key-3-processed'}]
    assert not signed, 'Recovery and observation never sign or resolve another answer'


async def asynchronous():
    async with await AsyncClient.connect(endpoint, 'owner-token', verify=trust, signer=signer) as client:
        steps = exercise(client)
        value = None
        while True:
            try:
                pending = steps.send(value)
            except StopIteration:
                return
            value = await pending if inspect.isawaitable(pending) else pending


def synchronous():
    with Client.connect(endpoint, 'owner-token', verify=trust, signer=signer) as client:
        steps = exercise(client)
        value = None
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
print(json.dumps({'phase': phase, 'facade': facade, 'decision': decision, 'signatures': len(signed)}))
