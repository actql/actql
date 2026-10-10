// Authored public consumer fixture. All product code comes from installed
// distributions; the fixture never supplies a completed capture or Ref.
import assert from 'node:assert/strict';
import {createPrivateKey, createPublicKey, createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect as connectLocal} from '@actql/local-node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {connect as connectRemote} from '@actql/sdk';
import {canonicalJson} from '@actql/sdk/host-port';
import {fixtureCertificates} from '../../adapters/site-node/https-exchange-fixture.mjs';
import {checkGcsAcceptanceEnvironment, gcsAcceptancePrograms} from '../gcs-files-content-environment.mjs';
import {createGcsAcceptanceCredential} from '../gcs-files-content-credential.mjs';

const configuration = JSON.parse(await readFile(process.argv[2], 'utf8'));
const phase = process.argv[3];
assert.ok(['capture', 'read'].includes(phase));
assert.ok(['Local', 'HTTPS'].includes(configuration.entrance));
const manifest = checkGcsAcceptanceEnvironment(configuration.manifest);
const deadline = configuration.deadlineUnixMs;
assert.ok(Number.isSafeInteger(deadline) && Date.now() < deadline);
const signal = AbortSignal.timeout(deadline - Date.now());
const pageBytes = 8192;
const credential = phase === 'capture' ? createGcsAcceptanceCredential(manifest,
  {maxResponseBytesPerCall: pageBytes}) : undefined;
let forbiddenCredentialCalls = 0, client, host, server, previousCertificates;
const keys = createPrivateKey(configuration.privateKey);
const principalId = userInfo().username;
const canonical = value => canonicalJson(value, {dataKeys: true});
const sourceProfilePath = join(configuration.root, 'source.json');
const siteProfilePath = join(configuration.root, 'site.json');
const authorization = {accountConfiguration: canonical({version: 'actql-execution-account-config/0.1',
  account_id: 'packed-gcs-host', entries: [{entry_id: 'run', outcome: 'allow', exclusions: [],
    principal: {all: true}, connection: {all: true}, resource: {all: true},
    operation: {any_of: ['read', 'write']}}]}),
reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
  publicKey: createPublicKey(keys).export({type: 'spki', format: 'pem'})}],
hostKey: {keyId: 'host', privateKey: configuration.privateKey}};
const hostLookupExecutionPolicy = {version: 'actql-lookup-execution-policy/0.1',
  max_network_attempts_per_request: 3, max_request_bytes_per_attempt: 4096,
  max_total_request_bytes: 73728, max_total_response_bytes: 49152,
  max_total_decoded_response_bytes: 49152, max_total_duration_ms: 30000};
const installation = {directory: join(configuration.root, 'host'), sourceProfilePath,
  authorization, hostLookupExecutionPolicy,
  resolveSourceSecret: credential?.resolveSecret ?? (() => {
    forbiddenCredentialCalls++;
    throw new Error('PackedGcsRestartMustNotReacquire');
  })};
const result = {phase, entrance: configuration.entrance, pid: process.pid, complete: false, cases: []};
try {
  if (phase === 'capture') {
    assert.ok(manifest.expectedObjects.length <= 3 &&
      manifest.expectedObjects.every(object => object.sizeBytes <= pageBytes));
    const privateKeyPath = join(configuration.root, 'site-key.pem');
    await writeFile(privateKeyPath, configuration.privateKey, {flag: 'wx', mode: 0o600});
    await writeFile(siteProfilePath, JSON.stringify({version: 'actql-installed-gcs-site/0.1',
      credentialAuthorityId: 'packed-gcs', credentialKeyId: 'packed-gcs',
      credentialPrivateKeyPath: privateKeyPath, environment: 'authorized-packed-gcs',
      journalRoot: join(configuration.root, 'credential-journal'), namespaceId: 'packed-gcs',
      siteGeneration: 1, siteKey: configuration.entrance, tokenEnvironment: 'ACTQL_GCS_UNUSED_TOKEN'}),
    {flag: 'wx', mode: 0o600});
    await writeFile(sourceProfilePath, JSON.stringify({version: 'actql-installed-gcs-source/0.1',
      connectorId: 'gcs-acceptance', project: manifest.project, bucket: manifest.bucket, prefix: manifest.prefix,
      mediaType: manifest.expectedObjects[0].mediaType, siteProfilePath,
      accountConfigurationWire: canonical({version: 'actql-execution-account-config/0.1',
        account_id: 'packed-gcs-read', entries: [{entry_id: 'read', outcome: 'allow', exclusions: [],
          principal: {all: true}, connection: {any_of: [`gcs:${manifest.project}/${manifest.bucket}`]},
          resource: {any_of: ['contents', 'files']}, operation: {any_of: ['read']}}]}),
      limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
        maxListingBytes: 32768, maxDurationMs: 30000, maxPathBytes: 1024,
        maxPageBytes: pageBytes, maxPageItems: 1, maxRequestBytes: 4096,
        maxContentBytes: Math.min(pageBytes, manifest.limits.maxObjectBytes)}}), {flag: 'wx', mode: 0o600});
  }
  if (configuration.entrance === 'Local') {
    client = await connectLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
  } else {
    const tlsRoot = join(configuration.root, `tls-${phase}`);
    await mkdir(tlsRoot, {mode: 0o700});
    const {key, cert, ca} = await fixtureCertificates(tlsRoot);
    previousCertificates = getCACertificates('default');
    setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer packed-gcs-fixture' ? principalId : undefined});
    server = createServer({key, cert}, host.handler);
    await new Promise((resolve, reject) => {
      server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
    });
    client = await connectRemote({mode: 'remote', durability: 'durable',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'packed-gcs-fixture'});
  }
  if (phase === 'capture') {
    for (const [name, program] of Object.entries(gcsAcceptancePrograms(manifest))) {
      const before = credential.observation();
      assert.equal((await client.check(program, {kind: 'program', scope: 'bound_input'})).report.verdict, 'verified');
      assert.deepEqual(credential.observation(), before);
      const run = await client.start(program);
      assert.equal((await run.wait({signal})).status, 'succeeded');
      const description = await run.result('files').describe();
      const rows = await run.result('files').all();
      const expected = name === 'capture' ? manifest.expectedObjects : [];
      assert.deepEqual(description.columns.map(column => column.name), ['name', 'content']);
      assert.equal(description.columns[1].contract.type, 'content_ref');
      assert.deepEqual(rows.map(row => row.name), expected.map(object => object.name));
      for (const [index, row] of rows.entries()) {
        assert.equal(row.content.$actql_ref, 'content');
        assert.equal(row.content.media_type, expected[index].mediaType);
        assert.equal(row.content.metadata.content_cid, expected[index].contentCid);
        assert.equal(row.content.metadata.size_bytes, expected[index].sizeBytes);
        assert.equal(row.content.metadata.truncated, false);
        assert.equal(row.content.metadata.issuer_evidence.issuer_kind, 'connector_capture');
      }
      assert.deepEqual(await (await client.attach(run.ref)).result('files').all(), rows);
      if (name === 'empty') assert.deepEqual(credential.observation(), before);
      result.cases.push({name, runRef: run.ref, rows, description});
    }
    await writeFile(join(configuration.root, 'originals.json'), JSON.stringify(result.cases), {flag: 'wx', mode: 0o600});
  } else {
    for (const expected of JSON.parse(await readFile(join(configuration.root, 'originals.json'), 'utf8'))) {
      const run = await client.attach(expected.runRef);
      assert.deepEqual(run.ref, expected.runRef);
      assert.equal((await run.status()).status, 'succeeded');
      assert.deepEqual(await run.result('files').describe(), expected.description);
      const rows = await run.result('files').all();
      assert.deepEqual(rows, expected.rows);
      result.cases.push({name: expected.name, runRef: run.ref, rows: rows.length,
        orderedRowsSha256: createHash('sha256').update(canonical(rows)).digest('hex')});
    }
    assert.equal(forbiddenCredentialCalls, 0);
  }
} finally {
  await client?.close();
  if (server?.listening) { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
  await host?.close();
  if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
  result.credential = credential?.observation() ?? {credentialResolutions: forbiddenCredentialCalls, tokenMints: 0};
  credential?.close();
}
result.complete = true;
console.log(JSON.stringify(result));
