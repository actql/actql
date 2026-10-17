// Actual public callers over source-qualified runtime loans, not a release gate.
import assert from 'node:assert/strict';
import test from 'node:test';
import {inspect} from 'node:util';
import {generateKeyPairSync} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {userInfo} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../../../host-node/embedded-local.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {connect} from '../../../../packages/sdk/index.mjs';
import {installedKintoneFixture} from './installed-kintone.fixture.mjs';

const executeFile = promisify(execFile);
const source = 'SELECT `$id`, Subject, Tags, RecordNumber FROM kintone.inquiries |> RESULT records';
const columns = [
  {name: '$id', contract: {type: 'string', nullable: false}},
  {name: 'Subject', contract: {type: 'string', nullable: false}},
  {name: 'Tags', contract: {type: 'array', nullable: false, items: {type: 'string', nullable: false}}},
  {name: 'RecordNumber', contract: {type: 'string', nullable: false}},
];
const expected = ['9007199254740992', '9007199254740993', '9007199254740994'].map((id, i) => ({
  $id: id, Subject: '東京\r\nnext', Tags: ['red', '東京', 'red'], RecordNumber: `APP-${i + 7}`}));

async function fixture(t, entrance) {
  const f = await installedKintoneFixture(t);
  // Alias publication uses the admitted original declaration's evidence, never
  // reconstructed contract identities or an example provider row.
  const declared = await f.load();
  const environment = JSON.parse(declared.environmentWire);
  const view = environment.schema_snapshots.find(value =>
    value.source_ref === declared.sourceReadAccesses[0].sourceRef);
  await declared.close();
  await writeFile(f.path, JSON.stringify({...f.profile, queryAliases: [{
    name: 'kintone.inquiries', sourceRef: view.source_ref,
    sourceViewContractCid: view.source_view_contract_cid,
    schemaContractCid: view.carrier_schema_contract_cid}]}));
  const keys = generateKeyPairSync('ed25519'), observations = [], principal = userInfo().username;
  const authorization = {accountConfiguration: canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'kintone-public-test',
    entries: [{entry_id: 'run-read-write', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read', 'write']}}]}),
  hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: principal,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  observe(name, detail) { observations.push([name, detail]); }};
  const installation = {directory: join(f.root, 'public-host'), sourceProfilePath: f.path,
    resolveSourceSecret: f.resolveSecret, authorization, retainedRelationOutput: true};
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
    if (entrance === 'Local') {
      client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
    } else {
      const [key, cert] = await Promise.all(['resource.key', 'resource.crt'].map(name => readFile(join(dirname(f.tls.caPath), name))));
      priorCa = getCACertificates('default'); setDefaultCACertificates([...priorCa, f.tls.ca.toString('utf8')]);
      host = await openInstalledRemoteHttpHost({...installation,
        authenticate: header => header === 'Bearer kintone-public-test' ? principal : undefined});
      server = createServer({key, cert}, host.handler);
      await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
      client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
        token: 'kintone-public-test', durability: 'durable'});
    }
  } catch (error) {
    const causes = [];
    for (let cause = error; cause && causes.length < 8; cause = cause.cause) {
      causes.push({name: cause.name, code: cause.code, message: cause.message});
    }
    t.diagnostic(inspect({initializationFailure: causes, cleanup: error.cleanupHandle?.status?.()}, {depth: 8}));
    if (error.cleanupHandle?.status?.().pending) t.after(async () => {
      await error.cleanupHandle.retry();
      assert.equal(error.cleanupHandle.status().pending, false);
    });
    throw error;
  }
  const closeHost = async () => {
    await client.close();
    if (server?.listening) {
      server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
  };
  return {...f, client, observations, installation, closeHost};
}

for (const entrance of ['Local', 'HTTPS']) test(
  `public ${entrance} kintone preserves full values through Named Result and original Run lookup`, async t => {
    const f = await fixture(t, entrance);
    const report = await f.client.check(source, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.equal(report.report?.verdict, 'verified', inspect(report, {depth: 8}));
    assert.deepEqual(report.report.runnable, {verdict: 'yes', reasons: []});
    assert.equal(f.tls.seen().length, 0); assert.equal(f.state.resolutions, 0);
    const submissionRef = f.client.newSubmission({nonce: `kintone-public-${entrance.toLowerCase()}`});
    const execution = await f.client.startSource(source, {format: 'sql', submissionRef});
    const state = await execution.wait({signal: AbortSignal.timeout(20000)});
    if (state.status !== 'succeeded') t.diagnostic(inspect({state, observations: f.observations},
      {depth: 8, maxStringLength: 3000}));
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 8}));
    const result = execution.result('records');
    assert.deepEqual((await result.describe()).columns, columns);
    assert.deepEqual(await result.all(), expected);
    assert.deepEqual(await result.all(), expected);
    const attached = await f.client.attach(execution.ref);
    assert.deepEqual(await attached.result('records').all(), expected);
    const original = await f.client.startSource(source, {format: 'sql', submissionRef});
    assert.deepEqual(original.ref, execution.ref);
    assert.deepEqual(await original.result('records').all(), expected);
    assert.deepEqual(f.tls.seen().map(value => value.pathname), [
      '/k/v1/app/form/fields.json', '/k/v1/records.json', '/k/v1/app/form/fields.json',
      '/k/v1/records.json', '/k/v1/app/form/fields.json']);
    assert.equal(f.state.resolutions, 5, 'result and original Run lookup cannot replay provider acquisition');
    await f.client.close();
    const cleanup = f.observations.filter(([name]) => name === 'dispatch_cleanup_completed');
    assert.equal(cleanup.length, 1);
    const usage = cleanup[0][1].resourceUsage;
    assert.equal(usage.holdings, '2');
    for (const field of ['heldBytes', 'reservedTransferBytes', 'reservedRetentionBytes',
      'reservedExecutionBytes', 'uncertainTransferBytes']) assert.equal(usage[field], '0', field);
    assert(BigInt(usage.transferredBytes) > 0n);
    if (entrance === 'Local') {
      await f.closeHost();
      const restartPath = join(f.root, 'original-host-restart.json');
      await writeFile(restartPath, JSON.stringify({installation: f.installation,
        ref: execution.ref}), {flag: 'wx', mode: 0o600});
      const launched = executeFile(process.execPath,
        ['adapters/connectors/kintone/test/kintone-client-restart.fixture.mjs', restartPath],
        {cwd: new URL('../../../../', import.meta.url), timeout: 10000,
          killSignal: 'SIGTERM', maxBuffer: 1024 * 1024});
      let child;
      try {child = await launched;}
      catch (error) {
        await Promise.all(['stdout', 'stderr'].map(stream => writeFile(
          join(f.root, `restart-child.${stream}.log`), error[stream] ?? '',
          {flag: 'wx', mode: 0o600})));
        throw error;
      }
      await Promise.all(['stdout', 'stderr'].map(stream => writeFile(
        join(f.root, `restart-child.${stream}.log`), child[stream],
        {flag: 'wx', mode: 0o600})));
      await writeFile(join(f.root, 'restart-child-result.json'), JSON.stringify({
        pid: launched.child.pid, exitCode: 0, secretResolutions: 0,
        source: 'kintone-client-restart.fixture.mjs'}), {flag: 'wx', mode: 0o600});
      const restored = JSON.parse(child.stdout);
      assert.deepEqual(restored, {sameRun: true, secretResolutions: 0,
        columns, rows: expected});
      assert.equal(f.tls.seen().length, 5, 'a fresh process restores the original capture without Provider replay');
    }
    t.diagnostic(JSON.stringify({entrance, providerRequests: f.tls.seen().length,
      sameRunLookup: true, repeatedRead: true, usage}));
  });
