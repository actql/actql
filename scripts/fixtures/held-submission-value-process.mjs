// Each phase uses the ordinary Client and installed Host in a fresh process.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createPrivateKey, sign} from 'node:crypto';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
const options = JSON.parse(await new Promise(resolve => {
  let input = ''; process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => {input += chunk;});
  process.stdin.on('end', () => resolve(input));
}));
const {root, phase, entrance, runtime, text, parameters, recoveryTarget} = options;
const {connect, RequestHeld} = await import(runtime.client);
const {openInstalledRemoteHttpHost} = await import(runtime.httpHost);
const owner = userInfo().username;
const keys = JSON.parse(await readFile(join(root, 'keys.json'), 'utf8'));
const authorization = {
  accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: 'held-values', entries: [{entry_id: 'acceptance', outcome: 'delegate',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: owner,
    publicKey: keys.reviewerPublic}], reviewReaders: [owner],
  hostKey: {keyId: 'host', privateKey: keys.hostPrivate},
  resumeAfterAnswer: phase === 'resume' || phase === 'lookup',
  observe(name) {if (name === 'computed') computes++;},
};
let client, host, server, computes = 0;
const until = async inspect => {
  const end = Date.now() + 20000;
  for (;;) {
    const result = await inspect(); if (result) return result;
    assert.ok(Date.now() < end, 'Held values did not resume within the existing bounded wait');
    await new Promise(resolve => setTimeout(resolve, 50));
  }
};
const requestId = 'original-held-values';
let report;
try {
  const installation = {directory: join(root, phase === 'foreign' ? 'other-host' : 'host'), authorization};
  if (entrance === 'https') {
    const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(root, name))));
    setDefaultCACertificates([...getCACertificates('default'), cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation, authenticate: () => owner});
    server = createServer({key, cert}, host.handler);
    // A persisted target names the original endpoint; a restarted fixture
    // reopens that exact endpoint instead of rewriting the saved locator.
    const port = recoveryTarget === undefined ? 0 : Number(new URL(recoveryTarget.lookupContext.endpoint).port);
    await new Promise((resolve, reject) => {server.once('error', reject); server.listen(port, '127.0.0.1', resolve);});
    client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      durability: 'durable', token: 'fixture-owner'});
  } else client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
  if (phase === 'initial' || phase === 'foreign') {
    let held;
    await assert.rejects(client.startSource(text, {format: 'json', requestId, parameters}),
      error => {held = error; return error instanceof RequestHeld;});
    const recovery = client.recoverRequest(held);
    assert.equal(recovery.target.requestId, requestId);
    if (phase === 'foreign') {
      assert.notEqual(client.profile.scopeRef, recoveryTarget.lookupContext.scopeRef);
      // The same request ID exists here, but the saved origin is another root.
      // A synchronous refusal occurs before any recovery lookup is requested.
      assert.throws(() => client.recoverRequest(recoveryTarget), {code: 'RequestRecoveryScopeMismatch'});
      report = {scopeRef: client.profile.scopeRef, target: recovery.target, originRefused: true};
    } else {
      const [checkpoint] = (await client.checkpoints()).items;
      assert.equal(checkpoint.checkpointCid, held.held.checkpoint.checkpointCid);
      const review = await client.reviewCheckpoint(checkpoint);
      const lookup = await recovery.lookup();
      await assert.rejects(recovery.attach(lookup), {code: 'InvalidRequestRecoveryObservation'});
      assert.throws(() => client.recoverRequest({...recovery.target,
        lookupContext: {...recovery.target.lookupContext, scopeRef: owner}}),
      {code: 'RequestRecoveryScopeMismatch'});
      report = {lookup, checkpoint, target: recovery.target,
        reviewWire: new TextDecoder().decode(review.bytes)};
    }
  } else if (phase === 'approve') {
    const recovery = client.recoverRequest(recoveryTarget);
    assert.equal((await recovery.lookup()).kind, 'held');
    const [checkpoint] = (await client.checkpoints()).items;
    const review = await client.reviewCheckpoint(checkpoint);
    const answered = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}],
      {signer: {keyId: 'reviewer', reviewerId: 'reviewer',
        sign: bytes => sign(null, bytes, createPrivateKey(keys.reviewerPrivate))}});
    report = {checkpoint, reviewWire: new TextDecoder().decode(review.bytes),
      resolutions: answered.results};
  } else {
    const recovery = client.recoverRequest(recoveryTarget);
    const lookup = await until(async () => {
      const found = await recovery.lookup();
      return found.kind === 'found' ? found : undefined;
    });
    const run = await recovery.attach(lookup);
    const state = await run.wait({signal: AbortSignal.timeout(20000)});
    const rows = await run.result('answer').all();
    report = {lookup, state, rows, target: recovery.target};
  }
  report.computes = computes;
} catch (error) {report = {error: error.code ?? error.message, stack: error.stack};}
finally {
  await client?.close();
  if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
  await host?.close();
}
await writeFile(join(root, `${phase}.json`), JSON.stringify(report));
process.exit(report.error === undefined ? 0 : 1);
