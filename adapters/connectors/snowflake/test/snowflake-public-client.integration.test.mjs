// Source-qualified public callers, not an installed npm/Local Python release.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {inspect} from 'node:util';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {connect} from '../../../../packages/sdk/index.mjs';
import {installedSnowflakeFixture} from './installed-snowflake.fixture.mjs';
import {decimal38, pending, resultBody} from './snowflake-read.fixture.mjs';

const source = 'SELECT ACCOUNT_ID AS account_id, ACTIVE_USERS AS active_users, TREND AS trend ' +
  'FROM snowflake.usage_30d |> RESULT usage';
const expected = [{account_id: 'a1', active_users: decimal38, trend: 'down'},
  {account_id: 'a2', active_users: '0', trend: null}];
const expectedColumns = [
  {name: 'account_id', contract: {type: 'string', nullable: false}},
  {name: 'active_users', contract: {type: 'decimal', nullable: false, precision: 38, scale: 0}},
  {name: 'trend', contract: {type: 'string', nullable: true}}];

async function publicFixture(t, entrance) {
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
  let client, host, server, priorCa;
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
    client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
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
  return {...f, client, installation, observations};
}

for (const entrance of ['Local', 'HTTPS']) test(
  `public ${entrance} Snowflake SQL preserves decimal38 and NULL through Named Result and attach`, async t => {
    const f = await publicFixture(t, entrance);
    assert.equal(f.state.resolutions, 0); assert.equal(f.state.requests.length, 0);
    const report = await f.client.check(source, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(report.report?.verdict, 'verified', inspect(report, {depth: 6}));
    assert.deepEqual(report.report.runnable, {verdict: 'yes', reasons: []});
    assert.equal(f.state.requests.length, 0, 'check cannot contact Snowflake');
    f.state.onRequest = () => f.state.requests.length === 1
      ? {status: 202, body: pending('public-source-original')}
      : {body: resultBody({handle: 'public-source-original'})};
    const submissionRef = f.client.newSubmission({nonce: `snowflake-public-${entrance.toLowerCase()}`});
    const execution = await f.client.startSource(source, {format: 'sql', submissionRef});
    const state = await execution.wait({signal: AbortSignal.timeout(20000)});
    if (state.status !== 'succeeded') t.diagnostic(inspect({
      requests: f.state.requests.map(({method, path}) => ({method, path})),
      observations: f.observations}, {depth: 8, maxStringLength: 3000}));
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 8}));
    const result = execution.result('usage');
    assert.deepEqual((await result.describe()).columns, expectedColumns);
    assert.deepEqual(await result.all(), expected);
    assert.deepEqual(await result.all(), expected);
    const attached = await f.client.attach(execution.ref);
    assert.deepEqual(await attached.result('usage').all(), expected);
    const sameSubmission = await f.client.startSource(source, {format: 'sql', submissionRef});
    assert.deepEqual(sameSubmission.ref, execution.ref);
    assert.deepEqual(await sameSubmission.result('usage').all(), expected);
    assert.deepEqual(f.state.requests.map(r => r.method), ['POST', 'GET'],
      'read, attach and same-submission lookup never replay the Provider');
    assert.equal(f.state.requests[1].path, '/api/v2/statements/public-source-original');
    await f.client.close();
    const cleanup = f.observations.filter(([name]) => name === 'dispatch_cleanup_completed');
    assert.equal(cleanup.length, 1, 'same dispatch cleanup completes exactly once');
    const usage = cleanup[0][1].resourceUsage;
    // Holding issuance is cumulative; physical bytes and live reservations retire.
    assert.equal(usage.holdings, '2', 'capture and Compute issuance is never refunded');
    for (const field of ['heldBytes', 'reservedTransferBytes',
      'reservedRetentionBytes', 'reservedExecutionBytes', 'uncertainTransferBytes']) {
      assert.equal(usage[field], '0', `original ledger cleanup: ${field}`);
    }
    assert(BigInt(usage.transferredBytes) > 0n, 'actual Provider input was charged');
    t.diagnostic(JSON.stringify({entrance, providerRequests: f.state.requests.length,
      repeatedRead: true, attachedOriginal: true, sameSubmissionLookup: true, usage}));
  });
