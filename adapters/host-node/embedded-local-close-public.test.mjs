import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir, userInfo} from 'node:os';
import {setImmediate} from 'node:timers/promises';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {RequestHeld} from '../../packages/sdk/index.mjs';

test('embedded final close releases the physical owner and reopens the same saved Run', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-client-close-',
    label: 'Local Client lifecycle'});
  const keys = generateKeyPairSync('ed25519');
  let computations = 0;
  const installation = {directory: scratch.path, authorization: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'client-close', entries: [{entry_id: 'write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(name) {if (name === 'computed') computations++;},
  }};
  const options = {mode: 'local', owner: 'local', durability: 'durable', installation};
  const text = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8');
  const a = await connectEmbeddedLocal(options), b = await connectEmbeddedLocal(options);
  await assert.rejects(connectEmbeddedLocal({...options,
    installation: {...installation, retainedRelationOutput: true}}),
  {message: 'InstalledHostConfigurationMismatch'});
  let c;
  t.after(async () => {await a.close(); await b.close(); await c?.close();});
  const run = await a.aql(text, {format: 'json', requestId: 'original'});
  assert.equal((await run.wait()).status, 'succeeded');
  await setImmediate();
  assert.equal(computations, 1);
  const ownerPath = join(scratch.path, 'publication/owner/owner.json');
  const firstOwner = await readFile(ownerPath, 'utf8');
  const reader = run.result('answer').rows(), iterator = reader[Symbol.asyncIterator]();
  assert.deepEqual((await iterator.next()).value, {id: 1});
  await a.close();
  assert.equal(await readFile(ownerPath, 'utf8'), firstOwner);
  assert.deepEqual(await iterator.next(), {done: true, value: undefined});
  const attached = await b.attach(run.ref);
  assert.deepEqual(await attached.result('answer').all(), [{id: 1}, {id: 2}]);
  assert.equal((await attached.status()).status, 'succeeded');
  await b.close();
  await assert.rejects(readFile(ownerPath), {code: 'ENOENT'});
  c = await connectEmbeddedLocal(options);
  assert.notEqual(await readFile(ownerPath, 'utf8'), firstOwner);
  assert.deepEqual((await c.lookupRequest('original')).ref, run.ref);
  const repeated = await c.aql(text, {format: 'json', requestId: 'original'});
  assert.deepEqual(repeated.ref, run.ref);
  assert.deepEqual(await repeated.result('answer').all(), [{id: 1}, {id: 2}]);
  await setImmediate();
  assert.equal(computations, 1);
  await c.close();
  await assert.rejects(readFile(ownerPath), {code: 'ENOENT'});
  const changed = await connectEmbeddedLocal({...options,
    installation: {...installation, retainedRelationOutput: true}});
  await changed.close();
  scratch.passed();
});

test('embedded close preserves an unanswered Checkpoint for the next Host', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-held-close-',
    label: 'Local held request lifecycle'});
  const keys = generateKeyPairSync('ed25519');
  let computations = 0;
  const installation = {directory: scratch.path, authorization: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'held-close', entries: [{entry_id: 'write', outcome: 'delegate',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    reviewReaders: [userInfo().username],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(name) {if (name === 'computed') computations++;},
  }};
  const options = {mode: 'local', owner: 'local', durability: 'durable', installation};
  const text = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8');
  const first = await connectEmbeddedLocal(options);
  let next;
  t.after(async () => {await first.close(); await next?.close();});
  await assert.rejects(first.aql(text, {format: 'json', requestId: 'held-original'}),
    error => error instanceof RequestHeld);
  const before = await first.lookupRequest('held-original');
  assert.equal(before.kind, 'held');
  assert.equal(before.state, 'waiting_checkpoint');
  const [checkpoint] = (await first.checkpoints()).items;
  const review = await first.reviewCheckpoint(checkpoint);
  await first.close();
  next = await connectEmbeddedLocal(options);
  const after = await next.lookupRequest('held-original');
  assert.equal(after.kind, 'held');
  assert.equal(after.state, 'waiting_checkpoint');
  assert.equal(after.prepareAttemptId, before.prepareAttemptId);
  assert.equal((await next.checkpoints()).items[0].checkpointCid, checkpoint.checkpointCid);
  assert.deepEqual((await next.reviewCheckpoint(checkpoint)).bytes, review.bytes);
  assert.equal(computations, 0);
  await next.close();
  scratch.passed();
});
