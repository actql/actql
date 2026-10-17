// Controlled peer/configuration fixture. The caller supplies only the normal
// public package namespaces; no Core, RowRun, Ledger or credential grant is
// manufactured here. The actual installed Host owns those responsibilities.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {tmpdir, userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {metadataBody, readLimits, resultBody} from './snowflake-response.fixture.mjs';
import configuration from './snowflake-public-alias.fixture.json' with {type: 'json'};

export async function publicSnowflakePackageFixture(t, entrance, node, httpHost) {
  assert(['Local', 'HTTPS'].includes(entrance));
  assert.equal(typeof node.open, 'function');
  assert.equal(typeof node.connect, 'function');
  assert.equal(typeof httpHost.openInstalledRemoteHttpHost, 'function');
  const root = await mkdtemp(join(tmpdir(), 'actql-snowflake-public-installed-'));
  t.diagnostic(`Retained Snowflake public installation: ${root}`);
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', 'server.key', '-out', 'server.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
  const [key, cert] = await Promise.all(['server.key', 'server.crt'].map(name => readFile(join(root, name))));
  const state = {requests: [], sockets: new Set(), secret: 'snowflake-fixture-secret',
    resolutions: 0, responseBytes: 0, onRequest: undefined};
  const provider = createServer({key, cert}, async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const entry = {method: request.method, path: request.url,
      headers: {...request.headers}, body: Buffer.concat(chunks).toString('utf8')};
    state.requests.push(entry);
    try {
      const answer = state.onRequest ? await state.onRequest(entry, request, response)
        : {body: resultBody()};
      if (answer === undefined) return;
      if (answer.destroy) { response.destroy(); return; }
      const body = Buffer.from(answer.body);
      state.responseBytes += body.byteLength;
      response.writeHead(answer.status ?? 200, {'content-type': 'application/json', ...(answer.headers ?? {})});
      response.end(body);
    } catch (error) { response.destroy(error); }
  });
  provider.on('connection', socket => {
    state.sockets.add(socket); socket.once('close', () => state.sockets.delete(socket));
  });
  let client, host, server, priorCa;
  t.after(async () => {
    try {
      await client?.close();
      if (server?.listening) {
        server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
      }
      await host?.close();
    } finally {
      if (priorCa !== undefined) setDefaultCACertificates(priorCa);
      // These peer socket events are not remote-statement termination or a
      // Run/capacity ACK. The positive oracle requires the original final SQL
      // response and the Host's separate cleanup observation.
      const stopped = Promise.all([...state.sockets].map(socket =>
        new Promise(resolve => socket.once('close', resolve))));
      if (provider.listening) await new Promise(resolve => provider.close(resolve));
      await stopped;
      assert.equal(state.sockets.size, 0);
    }
  });
  await new Promise((resolve, reject) => {
    provider.once('error', reject); provider.listen(0, '127.0.0.1', resolve);
  });
  const apiOrigin = `https://127.0.0.1:${provider.address().port}`;
  const siteKeys = generateKeyPairSync('ed25519');
  const credentialPrivateKeyPath = join(root, 'installed-credential.key');
  await writeFile(credentialPrivateKeyPath, siteKeys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const site = {version: 'actql-installed-snowflake-site/0.1', apiOrigin,
    warehouse: 'ANALYTICS', role: 'READER', authenticationType: 'OAUTH',
    credentialAuthorityId: 'installed-fixture', credentialKeyId: 'key', credentialPrivateKeyPath,
    environment: 'test', journalRoot: join(root, 'installed-journal'), namespaceId: 'installed-fixture',
    siteGeneration: 1, siteKey: 'installed-site', tokenEnvironment: 'ACTQL_SNOWFLAKE_TEST_TOKEN',
    caPath: join(root, 'server.crt')};
  const siteProfilePath = join(root, 'installed-site.json');
  await writeFile(siteProfilePath, JSON.stringify(site));
  const metadataPath = join(root, 'installed-metadata.json');
  await writeFile(metadataPath, JSON.stringify({version: 'actql-snowflake-read-metadata/0.1',
    connectorId: 'snowflake', resource: 'usage_30d', database: 'PRODUCT', schema: 'USAGE',
    table: 'USAGE_30D', apiOrigin, bodies: [metadataBody().toString('base64')]}));
  const sourceProfilePath = join(root, 'installed-source.json');
  await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-snowflake-source/0.1',
    connectorId: 'snowflake', resource: 'usage_30d', database: 'PRODUCT', schema: 'USAGE', table: 'USAGE_30D',
    metadataPath, siteProfilePath, accountConfigurationWire: configuration.sourceAccountWire,
    limits: {...readLimits, maxRows: 3, maxTotalRows: 3, maxDescriptionBytes: 4096,
      maxDeclarationBytes: 200000, maxDeclarationNodes: 20000},
    queryAliases: [configuration.alias]}));
  const keys = generateKeyPairSync('ed25519'), principal = userInfo().username, observations = [];
  const installation = {sourceProfilePath, retainedRelationOutput: true,
    resolveSourceSecret: async () => { state.resolutions++; return state.secret; },
    authorization: {accountConfiguration: configuration.hostAccountWire,
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: principal,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(name, detail) { observations.push([name, detail]); }}};
  try {
    if (entrance === 'Local') {
      client = await node.open({stateDir: join(root, 'public-host'), durability: 'durable', installation});
    } else {
      priorCa = getCACertificates('default'); setDefaultCACertificates([...priorCa, cert.toString('utf8')]);
      host = await httpHost.openInstalledRemoteHttpHost({...installation,
        directory: join(root, 'public-host'),
        authenticate: header => header === 'Bearer snowflake-public-test' ? principal : undefined});
      server = createServer({key, cert}, host.handler);
      await new Promise((resolve, reject) => {
        server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
      });
      client = await node.connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
        token: 'snowflake-public-test', durability: 'durable'});
    }
  } catch (error) {
    t.diagnostic(JSON.stringify({initializationFailure: {code: error.code, message: error.message},
      cleanup: error.cleanupHandle?.status?.()}));
    if (error.cleanupHandle?.status?.().pending) t.after(async () => {
      await error.cleanupHandle.retry();
      assert.equal(error.cleanupHandle.status().pending, false);
    });
    throw error;
  }
  return {root, client, state, observations, installation};
}
