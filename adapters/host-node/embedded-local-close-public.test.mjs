import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir, userInfo} from 'node:os';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

test('embedded final close releases the physical owner and reopens the same saved Run', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-client-close-',
    label: 'Local Client lifecycle'});
  const keys = generateKeyPairSync('ed25519');
  let computations = 0;
  let computed;
  const firstComputation = new Promise(resolve => {computed = resolve;});
  const installation = {directory: scratch.path, authorization: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'client-close', entries: [{entry_id: 'write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
      {entry_id: 'write-read', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    // Count the awaited physical boundary, not best-effort diagnostics: the
    // public committed Result can become visible before diagnostics arrive.
    faultInjection(name) {
      if (name === 'computed') {computations++; computed();}
    },
  }};
  const options = {mode: 'local', owner: 'local', durability: 'durable', installation};
  const text = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8');
  const a = await connectEmbeddedLocal(options), b = await connectEmbeddedLocal(options);
  await assert.rejects(connectEmbeddedLocal({...options,
    installation: {...installation, retainedRelationOutput: true}}),
  {message: 'InstalledHostConfigurationMismatch'});
  let c;
  t.after(async () => {await a.close(); await b.close(); await c?.close();});
  const submissionRef = a.newSubmission({nonce: 'original'});
  const run = await a.startSource(text, {format: 'json', submissionRef});
  assert.equal((await run.wait()).status, 'succeeded');
  let computationDeadline;
  try {
    await Promise.race([firstComputation, new Promise((_, reject) => {
      computationDeadline = setTimeout(() =>
        reject(new Error('ComputedPhaseNotReached')), 5000);
    })]);
  } finally {clearTimeout(computationDeadline);}
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
  assert.deepEqual((await c.lookupSubmission(submissionRef)).admission.ref, run.ref);
  const repeated = await c.startSource(text, {format: 'json', submissionRef});
  assert.deepEqual(repeated.ref, run.ref);
  assert.deepEqual(await repeated.result('answer').all(), [{id: 1}, {id: 2}]);
  await c.close();
  assert.equal(computations, 1);
  await assert.rejects(readFile(ownerPath), {code: 'ENOENT'});
  const changed = await connectEmbeddedLocal({...options,
    installation: {...installation, retainedRelationOutput: true}});
  await changed.close();
  scratch.passed();
});

test('embedded close preserves refusal of an unsupported pre-Run wait for the next Host', async t => {
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-held-close-',
    label: 'Local held request lifecycle'});
  const keys = generateKeyPairSync('ed25519');
  let computations = 0;
  const installation = {directory: scratch.path, authorization: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'held-close', entries: [{entry_id: 'write', outcome: 'delegate',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []},
      {entry_id: 'write-read', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['read']}, exclusions: []}]}),
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
  const submissionRef = first.newSubmission({nonce: 'held-original'});
  await assert.rejects(first.startSource(text, {format: 'json', submissionRef}),
    error => {
      assert.equal(error.code, 'SubmissionPreparationFailed');
      assert.equal(error.outcome.problem.code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
      return true;
    });
  // The original-intent owner explicitly forbids this pre-Run deferral.
  // Actual Run-scoped Effect/Model approval recovery has separate public cases;
  // do not revive a legacy request route merely to manufacture a held reply.
  const before = await first.lookupSubmission(submissionRef);
  assert.equal(before.kind, 'preparation_failed');
  assert.equal(before.problem.code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
  assert.deepEqual((await first.checkpoints()).items, []);
  await first.close();
  next = await connectEmbeddedLocal(options);
  const after = await next.lookupSubmission(submissionRef);
  assert.deepEqual(after, before);
  assert.deepEqual((await next.checkpoints()).items, []);
  await assert.rejects(next.startSource(text, {format: 'json', submissionRef}),
    {code: 'SubmissionPreparationFailed'});
  assert.deepEqual(await next.lookupSubmission(submissionRef), before);
  assert.equal(computations, 0);
  await next.close();
  scratch.passed();
});
