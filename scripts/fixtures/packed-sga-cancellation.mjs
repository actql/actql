// Runs unchanged in the clean installation. Only the installed SDK and Host
// check, admit and control the independent machine-input Reach Program.
import assert from 'node:assert/strict';
import {generateKeyPairSync, randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';

const source = await readFile('sga-source-fixtures/reach-selector.expected-program.json',
  'utf8');
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
};

for (const mode of ['local', 'remote']) {
  const entered = deferred();
  const release = deferred();
  const steps = [];
  const keys = generateKeyPairSync('ed25519');
  const reviewer = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: JSON.stringify({
      version: 'actql-execution-account-config/0.1',
      account_id: `sga-cancel-${mode}`, entries: [{
        entry_id: 'run', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['read', 'write']},
        exclusions: [], outcome: 'allow',
      }],
    }),
    reviewers: [{keyId: 'sga-cancel-reviewer', reviewerId: 'reviewer',
      principalId: userInfo().username, publicKey: reviewer.publicKey.export({
        type: 'spki', format: 'pem'})}],
    reviewReaders: [userInfo().username],
    hostKey: {keyId: 'sga-cancel-host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    async faultInjection(name) {
      steps.push(name);
      if (name === 'dispatch_reserved') {
        entered.resolve();
        await release.promise;
      }
    },
  };
  let host;
  let server;
  let client;
  let submission;
  try {
    const directory = resolve(`sga-cancel-${mode}-state`);
    let options;
    if (mode === 'local') {
      options = {mode, owner: 'local', durability: 'durable',
        installation: {directory, authorization}};
    } else {
      host = await openInstalledRemoteHttpHost({directory, authorization,
        authenticate: header => header === 'Bearer sga-cancel-token'
          ? userInfo().username : undefined});
      server = createServer({key: await readFile('remote.key'),
        cert: await readFile('remote.crt')}, host.handler);
      await new Promise(done => server.listen(0, '127.0.0.1', done));
      options = {mode, durability: 'durable', token: 'sga-cancel-token',
        endpoint: `https://127.0.0.1:${server.address().port}/`};
    }
    client = await connect(options);
    const requestId = `sga-cancel-${mode}-${randomUUID()}`;
    submission = client.aql(source, {format: 'json', requestId});
    // Record a rejection immediately, even if intake fails before the hook.
    const submitFailure = submission.then(() => new Promise(() => {}),
      error => { throw error; });
    await Promise.race([entered.promise, submitFailure,
      delay(30000, undefined, {ref: false}).then(() => {
        throw new Error('SgaCancellationBoundaryNotReached');
      })]);
    const lookup = await client.lookupRequest(requestId);
    assert.equal(lookup.kind, 'found');
    const execution = await client.attach(lookup.ref);
    assert.equal((await execution.status()).status, 'running');
    const cancelled = await execution.cancel();
    assert.equal(cancelled.kind, 'accepted');
    assert.equal((await execution.status()).control.cancellation_requested, true);
    release.resolve();
    const accepted = await submission;
    assert.deepEqual(accepted.ref, execution.ref);
    const terminal = await execution.wait({signal: AbortSignal.timeout(30000)});
    assert.equal(terminal.status, 'cancelled', JSON.stringify(terminal));
    assert.equal(terminal.control.physical_stop, 'confirmed');
    assert.equal(terminal.result_available, false);
    // This access-controlled Host requires a committed publication index.
    // A pre-start cancellation has none, so lookup is denied without payload.
    await assert.rejects(execution.result('answer').all(),
      error => error.code === 'ResultAccessDenied');
    assert.deepEqual((await client.aql(source,
      {format: 'json', requestId})).ref, execution.ref);
    assert.deepEqual((await client.lookupRequest(requestId)).ref, execution.ref);
    assert.equal((await (await client.attach(execution.ref)).status()).status,
      'cancelled');
    if (mode === 'local') {
      // Closing the last in-process Client drains and closes its installed
      // Host. Reconnect reads the durable cancelled Run instead of dispatching.
      await client.close();
      client = await connect(options);
      assert.deepEqual((await client.lookupRequest(requestId)).ref, execution.ref);
      const restored = await client.attach(execution.ref);
      assert.equal((await restored.status()).status, 'cancelled');
      assert.deepEqual((await client.aql(source,
        {format: 'json', requestId})).ref, execution.ref);
    }
    assert.equal(steps.filter(name => name === 'dispatch_reserved').length, 1);
    assert.equal(steps.filter(name => name === 'physical_start_reserved').length,
      0);
    assert.equal(steps.filter(name => name === 'computed').length, 0);
    console.log(`packed ${mode} Reach Run cancellation before physical start passed`);
  } finally {
    release.resolve();
    await submission?.catch(() => {});
    await client?.close();
    if (server !== undefined) {
      server.closeAllConnections();
      await new Promise(done => server.close(done));
    }
    await host?.close();
  }
}
