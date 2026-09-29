import assert from 'node:assert/strict';
import {sign, createPrivateKey} from 'node:crypto';
import {appendFileSync, readFileSync} from 'node:fs';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {connect, RequestHeld} from '@actql/node';

const step = process.argv[2];
const requestId = 'packed-embedded-values';
const authorization = JSON.parse(readFileSync('authorization.json', 'utf8'));
authorization.resumeAfterAnswer = step === 'resume' || step === 'recheck';
authorization.faultInjection = name => {
  appendFileSync('embedded-events.log', `${name}\n`);
};
const client = await connect({mode: 'local', owner: 'local',
  durability: 'durable', installation: {
    directory: join(process.cwd(), 'state'), authorization,
  }});
const document = readFileSync('values.json', 'utf8');
const expected = JSON.parse(readFileSync('expected.json', 'utf8'));
const pause = () => new Promise(resolve => setTimeout(resolve, 25));

try {
  if (step === 'hold') {
    await assert.rejects(client.aql(document, {format: 'json', requestId}),
      error => {
        assert.equal(error instanceof RequestHeld, true);
        assert.equal(error.requestId, requestId);
        assert.equal(error.held.state, 'waiting_checkpoint');
        assert.equal('ref' in error.held, false);
        return true;
      });
    const lookup = await client.lookupRequest(requestId);
    assert.equal(lookup.kind, 'held');
    assert.equal(lookup.state, 'waiting_checkpoint');
    console.log('held');
  } else if (step === 'approve') {
    const {items} = await client.checkpoints();
    const checkpoint = items.find(item =>
      item.subject.requestId === requestId);
    assert.ok(checkpoint);
    const review = await client.reviewCheckpoint(checkpoint);
    const projection = JSON.parse(new TextDecoder().decode(review.bytes));
    assert.equal(projection.displayed_scope.request_id, requestId);
    assert.deepEqual(JSON.parse(projection.displayed_scope.document),
      JSON.parse(document));
    const key = createPrivateKey(readFileSync('reviewer.key', 'utf8'));
    const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
      sign: bytes => sign(null, bytes, key)};
    const answered = await client.resolveCheckpoints([
      {checkpoint, decision: 'approved'}], {signer});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed']);
    assert.equal((await client.lookupRequest(requestId)).state, 'resuming');
    console.log('approved');
  } else if (step === 'resume' || step === 'recheck') {
    let lookup;
    for (let attempt = 0; attempt < 400; attempt++) {
      lookup = await client.lookupRequest(requestId);
      if (lookup.kind === 'found') break;
      await pause();
    }
    assert.equal(lookup.kind, 'found', JSON.stringify(lookup));
    assert.equal(lookup.ref.namespaceId, 'local');
    const execution = await client.attach(lookup.ref);
    let state;
    for (let attempt = 0; attempt < 400; attempt++) {
      state = await execution.wait();
      if (state.status === 'succeeded') break;
      await pause();
    }
    assert.equal(state.status, 'succeeded');
    assert.equal((await execution.status()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(), expected);
    assert.equal((await execution.cancel()).kind, 'already_terminal');
    assert.equal((await client.cancelRequest(requestId)).kind,
      'already_terminal');
    console.log('published');
  } else {
    assert.fail(`Unknown packed step: ${step}`);
  }
} finally {
  await client.close();
}
