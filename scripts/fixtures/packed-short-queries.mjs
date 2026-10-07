// Fresh external consumers exercise the real installed Local and TLS HTTPS
// owners. Only independently expected rows and observed Compute counts pass.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {setImmediate} from 'node:timers/promises';
import {connect, open, RequestHeld} from '@actql/node';
import {getSubmissionInput} from '@actql/sdk';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';

function authorization(outcome = 'allow') {
  const keys = generateKeyPairSync('ed25519');
  let computes = 0;
  return {count: () => computes, value: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: `short-${outcome}`, entries: [{entry_id: 'write', outcome,
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(name) {if (name === 'computed') computes++;},
  }};
}

const defaults = await open();
try {
  assert.equal(defaults.info.stateDir, resolve('.actql'));
  assert.deepEqual(await defaults.sql('SELECT 0 AS id').all(), [{id: 0}]);
} finally {await defaults.close();}

async function exercise(db, counter, label) {
  const query = db.sql('SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id', undefined,
    {requestId: `${label}-original`});
  const savedId = query.requestId;
  assert.ok(query instanceof Promise);
  const [first, repeated] = await Promise.all([query, query]);
  assert.equal(first, repeated);
  assert.equal(first.then, undefined);
  assert.equal(getSubmissionInput(first).requestId, savedId);
  assert.deepEqual(await query.all(), [{id: 1}, {id: 2}]);
  assert.deepEqual(await query.all(), [{id: 1}, {id: 2}]);
  const one = first.rows(), two = first.rows();
  assert.notEqual(one.attemptId, two.attemptId);
  assert.deepEqual(await Array.fromAsync(one), [{id: 1}, {id: 2}]);
  assert.deepEqual(await Array.fromAsync(two), [{id: 1}, {id: 2}]);
  await assert.rejects(query.all({maxRows: 1}), {code: 'ResultRetainedLimit', rowsYielded: 0});
  assert.deepEqual(await Array.fromAsync(first.rows()), [{id: 1}, {id: 2}]);
  assert.deepEqual((await db.lookupRequest(savedId)).ref, first.execution.ref);
  assert.deepEqual(await (await db.attach(first.ref.run)).result(first.ref.resultName).all(),
    [{id: 1}, {id: 2}]);
  await setImmediate();
  assert.equal(counter.count(), 1, `${label}: repeated awaits/reads must not repeat Compute`);
  const named = await db.aql('SELECT @id AS id |> RESULT named', {id: 3},
    {requestId: `${label}-named`, result: 'named', parameterDeclarations: {id: {type: 'number'}}});
  assert.deepEqual(await named.all(), [{id: 3}]);
  assert.equal(named.ref.resultName, 'named');
  const low = await db.startSource('SELECT 4 AS id',
    {format: 'sql', requestId: `${label}-low`});
  assert.equal((await low.wait()).status, 'succeeded');
  assert.deepEqual(await low.result('answer').all(), [{id: 4}]);
  await setImmediate();
  assert.equal(counter.count(), 3);
  return first.ref;
}

const localAuthorization = authorization();
const localOptions = {stateDir: resolve('short-local'), installation: {
  authorization: localAuthorization.value}};
let local = await open(localOptions);
assert.equal(local.info.stateDir, localOptions.stateDir);
const saved = await exercise(local, localAuthorization, 'local');
await local.close();
local = await open(localOptions);
try {
  assert.deepEqual((await local.lookupRequest('local-original')).ref, saved.run);
  assert.deepEqual(await (await local.attach(saved.run)).result(saved.resultName).all(),
    [{id: 1}, {id: 2}]);
  assert.equal(localAuthorization.count(), 3, 'reopen/attach must not repeat Compute');
} finally {await local.close();}

const remoteAuthorization = authorization();
const host = await openInstalledRemoteHttpHost({directory: resolve('short-remote'),
  authorization: remoteAuthorization.value,
  authenticate: header => header === 'Bearer short-token' ? userInfo().username : undefined});
const server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let remote;
try {
  remote = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'short-token'});
  await exercise(remote, remoteAuthorization, 'https');
  const originalFetch = globalThis.fetch;
  let lost = false;
  globalThis.fetch = async (...args) => {
    const response = await originalFetch(...args);
    if (!lost && new URL(args[0]).pathname.endsWith('/submit')) {
      lost = true; await response.body.cancel();
      throw new TypeError('Test-owned acceptance reply lost');
    }
    return response;
  };
  try {
    const query = remote.sql('SELECT 5 AS id', undefined, {requestId: 'https-lost'});
    let original;
    await assert.rejects(query, error => {
      original = error; assert.equal(error.code, 'SubmissionUnknown');
      assert.equal(getSubmissionInput(error).requestId, 'https-lost'); return true;
    });
    await assert.rejects(query.all(), error => error === original);
    const found = await remote.lookupRequest('https-lost');
    assert.equal(found.kind, 'found');
    const execution = await remote.attach(found.ref);
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(), [{id: 5}]);
    await setImmediate();
    assert.equal(remoteAuthorization.count(), 4, 'lost reply must not cause resubmission');
  } finally {globalThis.fetch = originalFetch;}
} finally {
  await remote?.close(); server.closeAllConnections();
  await new Promise(resolve => server.close(resolve)); await host.close();
}

const heldAuthorization = authorization('delegate');
const held = await open({stateDir: resolve('short-held'), installation: {authorization: heldAuthorization.value}});
try {
  const query = held.sql('SELECT 6 AS id', undefined, {requestId: 'held-query'});
  let original;
  await assert.rejects(query, error => {
    original = error; assert.ok(error instanceof RequestHeld);
    assert.equal(error.execution, undefined); assert.equal(error.executionRef, undefined);
    assert.equal(getSubmissionInput(error).requestId, 'held-query'); return true;
  });
  await assert.rejects(query, error => error === original);
  const observation = await held.lookupRequest('held-query');
  assert.equal(observation.kind, 'held');
  assert.equal(observation.prepareAttemptId, original.held.prepareAttemptId);
  assert.equal(heldAuthorization.count(), 0);
} finally {await held.close();}
console.log('Packed short-query Local/HTTPS: default open, rows, same Run, read limits, lost reply and held request passed');
