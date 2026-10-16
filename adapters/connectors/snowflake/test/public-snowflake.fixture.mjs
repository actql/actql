// Private shared installation fixture; original Host/Site/Run Owners remain real.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {connect} from '../../../../packages/sdk/index.mjs';
import {installedSnowflakeFixture} from './installed-snowflake.fixture.mjs';

export async function publicSnowflakeInstallation(t) {
  const f = await installedSnowflakeFixture(t);
  const view = f.row.originals.declared.views[0];
  await writeFile(f.path, JSON.stringify({...f.profile, queryAliases: [{
    name: 'snowflake.usage_30d', sourceRef: view.source_ref,
    sourceViewContractCid: view.view_cid, schemaContractCid: view.carrier_schema_cid}]}));
  const keys = generateKeyPairSync('ed25519');
  const principal = userInfo().username;
  const observations = [];
  const authorization = {accountConfiguration: canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'snowflake-public-fixture',
    entries: [{entry_id: 'run-and-read', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read', 'write']}}]}),
  hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: principal,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  observe(name, detail) { observations.push([name, detail]); }};
  const installation = {directory: join(f.root, 'public-host'), sourceProfilePath: f.path,
    resolveSourceSecret: f.options.credential.resolveSecret, authorization,
    retainedRelationOutput: true};
  return {...f, installation, observations};
}

export async function publicSnowflakeFixture(t, entrance, installationFixture = publicSnowflakeInstallation) {
  const f = await installationFixture(t);
  const {installation, observations} = f;
  const principal = userInfo().username;
  let client, host, server, priorCa, endpoint;
  t.after(async () => {
    await client?.close();
    if (server?.listening) {
      server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
    if (priorCa !== undefined) setDefaultCACertificates(priorCa);
  });
  try {
  if (entrance === 'Local') client = await connectEmbeddedLocal({
    mode: 'local', owner: 'local', durability: 'durable', installation});
  else {
    const [key, cert] = await Promise.all(['server.key', 'server.crt'].map(name => readFile(join(f.root, name))));
    priorCa = getCACertificates('default'); setDefaultCACertificates([...priorCa, cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer snowflake-public-test' ? principal : undefined});
    server = createServer({key, cert}, host.handler);
    await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
    endpoint = `https://127.0.0.1:${server.address().port}/`;
    client = await connect({mode: 'remote', endpoint,
      token: 'snowflake-public-test', durability: 'durable'});
  }
  } catch (error) {
    const causes = [];
    for (let value = error; value && causes.length < 8; value = value.cause) {
      causes.push({name: value.name, code: value.code, message: value.message, stack: value.stack});
    }
    t.diagnostic(JSON.stringify({initializationFailure: causes,
      cleanup: error.cleanupHandle?.status?.()}));
    if (error.cleanupHandle?.status?.().pending) t.after(async () => {
      await error.cleanupHandle.retry();
      assert.equal(error.cleanupHandle.status().pending, false);
    });
    throw error;
  }
  return {...f, client, installation, observations,
    remote: endpoint === undefined ? undefined : Object.freeze({endpoint,
      token: 'snowflake-public-test', caPath: join(f.root, 'server.crt')})};
}
