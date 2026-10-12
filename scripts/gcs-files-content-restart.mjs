// A genuinely fresh public Host over the original Run and Store. Provider
// credentials are unavailable: reading a retained Result must not reacquire.
import assert from 'node:assert/strict';
import {createHash, createPrivateKey, createPublicKey} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../adapters/host-node/embedded-local.mjs';
import {connect as connectRemote} from '../packages/sdk/index.mjs';
import {fixtureCertificates} from '../adapters/site-node/https-exchange-fixture.mjs';
import {canonicalJson} from '../packages/sdk/host-port.mjs';

const configuration = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.equal(configuration.version, 'actql-gcs-content-restart-fixture/0.1');
assert.ok(['Local', 'HTTPS'].includes(configuration.entrance));
const keys = createPrivateKey(await readFile(configuration.privateKeyPath));
const principalId = userInfo().username;
let credentialCalls = 0, client, host, server, previousCertificates;
const installation = {...configuration.installation,
  resolveSourceSecret() {
    credentialCalls++;
    throw Object.assign(new Error('RestartMustNotReacquireGcs'), {code: 'RestartMustNotReacquireGcs'});
  }, authorization: {...configuration.authorization,
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
      publicKey: createPublicKey(keys).export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.export({type: 'pkcs8', format: 'pem'})}}};
const result = {version: 'actql-gcs-content-restart-observation/0.1', pid: process.pid,
  entrance: configuration.entrance, complete: false, cases: []};
try {
  if (configuration.entrance === 'Local') {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
  } else {
    const tlsRoot = join(configuration.evidenceDirectory, 'restart-tls');
    await mkdir(tlsRoot, {mode: 0o700});
    const {key, cert, ca} = await fixtureCertificates(tlsRoot);
    previousCertificates = getCACertificates('default');
    setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer restart-fixture-only' ? principalId : undefined});
    server = createServer({key, cert}, host.handler);
    await new Promise((resolve, reject) => {
      server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
    });
    client = await connectRemote({mode: 'remote', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'restart-fixture-only'});
  }
  for (const expected of configuration.cases) {
    const run = await client.attach(expected.runRef);
    assert.deepEqual(run.ref, expected.runRef);
    assert.equal((await run.status()).status, 'succeeded');
    const description = await run.result('files').describe();
    const rows = await run.result('files').all();
    assert.deepEqual(description, expected.description);
    assert.deepEqual(rows, expected.rows);
    result.cases.push({name: expected.name, runRef: run.ref, rows: rows.length,
      orderedRowsSha256: createHash('sha256').update(canonicalJson(rows, {dataKeys: true})).digest('hex')});
  }
  assert.equal(credentialCalls, 0, 'Restoring the same public Results cannot read GCS again');
} finally {
  await client?.close();
  if (server?.listening) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  await host?.close();
  if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
}
result.complete = true;
result.credentialCalls = credentialCalls;
await writeFile(join(configuration.evidenceDirectory, 'restart-observation.json'),
  JSON.stringify(result, null, 2) + '\n', {flag: 'wx', mode: 0o600});
console.log(JSON.stringify(result));
