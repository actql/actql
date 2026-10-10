import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {inspect} from 'node:util';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {loadInstalledSource, installedSourceIdentity} from '../../../host-node/installed-source.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from '../../../host-node/embedded-local.mjs';
import {connect as connectRemote} from '../../../../packages/sdk/index.mjs';
import {fixtureCertificates} from '../../../site-node/https-exchange-fixture.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {restoreGcsSourceDeclaration} from '../host/gcs-source-declaration.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const baseEnvironmentWire = await readFile(new URL('../../../../spec/local-check-environment.json',
  import.meta.url), 'utf8');

async function fixture(t) {
  const scratch = await createOwnedScratch({parent: new URL('../../../../_build/', import.meta.url).pathname,
    prefix: 'gcs-installed-', label: 'GCS standard Source installation fixture'});
  const siteProfilePath = join(scratch.path, 'site.json');
  const keyPath = join(scratch.path, 'credential.key');
  const keys = generateKeyPairSync('ed25519');
  await writeFile(keyPath, keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const site = {version: 'actql-installed-gcs-site/0.1', credentialAuthorityId: 'fixture-authority',
    credentialKeyId: 'fixture-key', credentialPrivateKeyPath: keyPath,
    environment: 'fixture', journalRoot: join(scratch.path, 'credential-journal'),
    namespaceId: 'fixture', siteGeneration: 1, siteKey: 'fixture-site',
    tokenEnvironment: 'ACTQL_GCS_TEST_ONLY_TOKEN'};
  await writeFile(siteProfilePath, JSON.stringify(site));
  const accountConfigurationWire = canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'fixture', entries: [{entry_id: 'read', outcome: 'allow', exclusions: [],
      principal: {all: true}, connection: {any_of: ['gcs:fixture-project/actql-fixture']},
      resource: {any_of: ['contents', 'files']}, operation: {any_of: ['read']}}]});
  const profile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
    project: 'fixture-project', bucket: 'actql-fixture', prefix: 'test/e\u0301/',
    mediaType: 'application/pdf', siteProfilePath, accountConfigurationWire,
    limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
      maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
      maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}};
  const profilePath = join(scratch.path, 'source.json');
  const declared = restoreGcsSourceDeclaration(moon, profile).declared;
  const queryAliases = declared.views.map(view => ({name: `docs.${view.resource}`,
    sourceRef: view.source_ref, sourceViewContractCid: view.view_cid,
    schemaContractCid: view.carrier_schema_cid}));
  await writeFile(profilePath, JSON.stringify({...profile, queryAliases}));
  let secretCalls = 0;
  const resolveSecret = () => { secretCalls++; assert.fail('No real credential or GCS request is authorized'); };
  // Run acceptance is a separate Host decision from the Connector's read grant.
  const hostAccount = canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'gcs-public-fixture', entries: [{entry_id: 'run', outcome: 'allow',
      exclusions: [], principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['read', 'write']}}]});
  const authorization = {accountConfiguration: hostAccount,
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}};
  const loaded = [], closers = [];
  t.after(async () => {
    for (const close of closers) await close();
    for (const source of loaded) await source.close();
    scratch.passed();
  });
  return {scratch, site, siteProfilePath, profile, profilePath, declared, queryAliases,
    loaded, closers, authorization, secretCalls: () => secretCalls, resolveSecret,
    options: {root: scratch.path, principalId: userInfo().username, moon, runtimeUrl,
      baseEnvironmentWire, resolveSecret}};
}

test('standard GCS Connector loads both declared Resources without provider or credential I/O', async t => {
  const value = await fixture(t);
  const source = await loadInstalledSource(value.profilePath, value.options);
  value.loaded.push(source);
  assert.equal(source.connectorRegistration, 'gcs');
  assert.equal(source.connectorRevision, 'gcs/0.1');
  assert.deepEqual(source.sourceReadAccesses.map(({resource}) => resource).sort(), ['contents', 'files']);
  assert.ok(source.admitsSource(value.declared.views.find(view => view.resource === 'files').source_ref));
  assert.ok(source.admitsSource(value.declared.views.find(view => view.resource === 'contents').source_ref));
  assert.equal(source.admitsSource('source:foreign'), false);
  const environment = JSON.parse(source.environmentWire);
  assert.equal(environment.connector_catalogs[0].source_views.length, 2);
  assert.equal(value.secretCalls(), 0);
});

test('standard GCS installation identity preserves exact scope and observes Site generation', async t => {
  const value = await fixture(t);
  const original = await installedSourceIdentity(value.profilePath);
  await writeFile(value.profilePath, JSON.stringify({...value.profile, queryAliases: value.queryAliases,
    prefix: 'test/é/'}));
  assert.notEqual(await installedSourceIdentity(value.profilePath), original,
    'configuration NFC cannot merge distinct object prefixes');
  await writeFile(value.profilePath, JSON.stringify({...value.profile, queryAliases: value.queryAliases}));
  assert.equal(await installedSourceIdentity(value.profilePath), original);
  await writeFile(value.siteProfilePath, JSON.stringify({...value.site, siteGeneration: 2}));
  assert.notEqual(await installedSourceIdentity(value.profilePath), original);
  assert.equal(value.secretCalls(), 0);
});

test('standard GCS Site rejects arbitrary origins and unknown profile fields before credential use', async t => {
  const value = await fixture(t);
  await writeFile(value.siteProfilePath, JSON.stringify({...value.site, apiOrigin: 'https://foreign.example'}));
  await assert.rejects(loadInstalledSource(value.profilePath, value.options), {code: 'InvalidInstalledGcsSite'});
  assert.equal(value.secretCalls(), 0);
});

for (const entrance of ['Local', 'HTTPS']) {
test(`public ${entrance} LIST_FILES paths=[] uses the standard GCS installation with zero credential calls`, async t => {
  const value = await fixture(t);
  const installation = {directory: join(value.scratch.path, 'host'), sourceProfilePath: value.profilePath,
    resolveSourceSecret: value.resolveSecret, authorization: value.authorization};
  let client, host, server, previousCertificates;
  value.closers.push(async () => {
    await client?.close();
    if (server?.listening) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    await host?.close();
    if (previousCertificates !== undefined) setDefaultCACertificates(previousCertificates);
  });
  if (entrance === 'Local') {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation});
  } else {
    const {key, cert, ca} = await fixtureCertificates(value.scratch.path);
    previousCertificates = getCACertificates('default');
    setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer gcs-fixture' ? userInfo().username : undefined});
    server = createServer({key, cert}, host.handler);
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    client = await connectRemote({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'gcs-fixture', durability: 'durable'});
  }
  for (const [format, source] of [
    ['sql', 'SELECT f.name FROM LIST_FILES(docs.files, paths => ARRAY<STRING>[]) AS f |> RESULT files'],
    ['aql-text', 'FROM LIST_FILES(docs.files, paths => ARRAY<STRING>[]) AS f |> SELECT f.name |> RESULT files'],
  ]) {
    const check = await client.check(source, {kind: 'text', scope: 'bound_input', format});
    assert.equal(check.report?.verdict, 'verified', inspect(check, {depth: 8, maxStringLength: 3000}));
    const execution = await client.startSource(source, {format})
      .catch(error => assert.fail(inspect(error, {depth: 8, maxStringLength: 2000})));
    const state = await execution.wait({signal: AbortSignal.timeout(20000)});
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 8}));
    const expectedColumns = [{name: 'name', contract: {type: 'string', nullable: false}}];
    assert.deepEqual((await execution.result('files').describe()).columns, expectedColumns);
    assert.deepEqual(await execution.result('files').all(), []);
    const attached = await client.attach(execution.ref);
    assert.deepEqual((await attached.result('files').describe()).columns, expectedColumns);
    assert.deepEqual(await attached.result('files').all(), []);
  }
  for (const source of [
    'SELECT name FROM LIST_FILES(docs.unknown, paths => ARRAY<STRING>[])',
    'SELECT name FROM LIST_FILES(docs.contents, paths => ARRAY<STRING>[])',
  ]) {
    const refused = await client.check(source, {kind: 'text', scope: 'bound_input', format: 'sql'});
    assert.notEqual(refused.report?.verdict, 'verified', inspect(refused, {depth: 8}));
    await assert.rejects(client.startSource(source, {format: 'sql'}), {code: 'SubmissionNotAccepted'});
  }
  assert.equal(value.secretCalls(), 0, 'empty exact selection performs no GCS operation');
});
}
