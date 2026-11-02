import assert from 'node:assert/strict';
import {generateKeyPairSync,createHash} from 'node:crypto';
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
import {gcsAcceptancePrograms} from '../../../../scripts/gcs-files-content-environment.mjs';
import {selectInstalledHostEnvironment} from '../../../host-node/installed-host-policy.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {installedSourceFixtureLifetime} from '../../../host-node/fixtures/installed-source-initialization.mjs';
import {observeOwnScopedStateFds} from '../../../../scripts/fixtures/external-rest/conformance.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const baseEnvironmentWire = await readFile(new URL('../../../../spec/local-check-environment.json',
  import.meta.url), 'utf8');
// Host policy covers the declared three rows, two keyed pages and 8192-byte
// pages, not just the expected object or an empty selection.
const hostLookupExecutionPolicy = Object.freeze({version: 'actql-lookup-execution-policy/0.1',
  max_network_attempts_per_request: 3, max_request_bytes_per_attempt: 4096,
  max_total_request_bytes: 73728, max_total_response_bytes: 49152,
  max_total_decoded_response_bytes: 49152, max_total_duration_ms: 30000});

function installationFailure(t, error) {
  // Preserve the original failure and cleanup carrier. Emit only closed code
  // names, never account/profile/key/credential values from nested errors.
  const codes = [];
  let current = error;
  for (let index = 0; index < 8 && current !== undefined; index++) {
    const code = current?.code ?? current?.message;
    codes.push(typeof code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(code)
      ? code : '<non-code>');
    current = current?.cause;
  }
  t.diagnostic(`Original installation failure codes: ${JSON.stringify(codes)}`);
  throw error;
}

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
  const declared = restoreGcsSourceDeclaration(moon, profile, undefined, {includeObjects: true}).declared;
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
  const loaded=[],closers=[];let closeInitial,initialized;
  const lifetime=installedSourceFixtureLifetime({after(close){closeInitial=close;},diagnostic:(...args)=>t.diagnostic(...args)});
  t.after(async()=>{
    const failures=[];
    try{for(const close of closers)await close();await closeInitial();}catch(cause){failures.push(cause);}
    assert.equal(observeOwnScopedStateFds([scratch.path]).scopedStateFd0,true);
    if(failures.length)throw new AggregateError(failures,'GcsFixtureCleanupUnconfirmed');
    scratch.passed();
  });
  const load=async()=>{
    const runtimeBundleCid='sha256:'+createHash('sha256').update(await readFile(runtimeUrl)).digest('hex');
    initialized??=lifetime.open({root:scratch.path,principalId:userInfo().username,moon,baseEnvironmentWire,runtimeBundleCid,
      installation:installedConnectors.find(value=>value.name==='gcs')});
    try{
      const source=await loadInstalledSource(profilePath,{root:scratch.path,principalId:userInfo().username,moon,runtimeUrl,
        baseEnvironmentWire,resolveSecret,installationServices:initialized.installationServices});
      loaded.push(source);lifetime.sources.push(source);return source;
    }catch(cause){
      const pending=[cause],seen=new Set(),errors=[];while(pending.length&&errors.length<8){
        const value=pending.shift();if(!value||typeof value!=='object'||seen.has(value))continue;
        seen.add(value);errors.push({name:value.name,code:value.code,stack:typeof value.stack==='string'?value.stack.split('\n').slice(0,8):undefined});
        pending.push(value.cause,value.primaryFailure);
      }
      t.diagnostic(JSON.stringify({originalInitializationErrors:errors}));throw cause;
    }
  };
  return {scratch, site, siteProfilePath, profile, profilePath, declared, queryAliases,load,
    loaded, closers, authorization, secretCalls: () => secretCalls, resolveSecret,
    options: {root: scratch.path, principalId: userInfo().username, moon, runtimeUrl,
      baseEnvironmentWire, resolveSecret}};
}

function acceptancePrograms(value) {
  return gcsAcceptancePrograms({version: 'actql-gcs-files-content-acceptance/0.1',
    project: value.profile.project, bucket: value.profile.bucket, prefix: value.profile.prefix,
    credential: {kind: 'gcloud-impersonation', account: 'fixture@example.invalid',
      serviceAccount: 'actql-content-test@fixture-project.iam.gserviceaccount.com',
      executable: '/fixture/gcloud'}, permissions: ['list', 'read_metadata', 'read_content'],
    limits: {maxRequests: 200, maxResponseBytes: 10485760, maxDurationMs: 900000, maxObjectBytes: 1048576},
    costLimitUsd: 1, expectedObjects: [{name: value.profile.prefix + 'fixture.pdf',
      mediaType: 'application/pdf', contentCid: `sha256:${'1'.repeat(64)}`, sizeBytes: 3}]},
  value.profile.connectorId);
}

async function connectFixture(t, entrance, value) {
  const installation = {directory: join(value.scratch.path, 'host'), sourceProfilePath: value.profilePath,
    resolveSourceSecret: value.resolveSecret, authorization: value.authorization, hostLookupExecutionPolicy};
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
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable', installation})
      .catch(error => installationFailure(t, error));
  } else {
    const {key, cert, ca} = await fixtureCertificates(value.scratch.path);
    previousCertificates = getCACertificates('default');
    setDefaultCACertificates([...previousCertificates, ca.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer gcs-fixture' ? userInfo().username : undefined})
      .catch(error => installationFailure(t, error));
    server = createServer({key, cert}, host.handler);
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    client = await connectRemote({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'gcs-fixture', durability: 'durable'});
  }
  return client;
}

test('standard GCS Connector loads its three declared read Resources without provider or credential I/O', async t => {
  const value = await fixture(t);
  const source=await value.load();
  assert.equal(source.connectorRegistration, 'gcs');
  assert.equal(source.connectorRevision, 'gcs/0.1');
  assert.deepEqual(source.sourceReadAccesses.map(({resource}) => resource).sort(), ['contents', 'files', 'objects']);
  assert.ok(source.admitsSource(value.declared.views.find(view => view.resource === 'files').source_ref));
  assert.ok(source.admitsSource(value.declared.views.find(view => view.resource === 'contents').source_ref));
  assert.equal(source.admitsSource('source:foreign'), false);
  const environment = JSON.parse(source.environmentWire);
  assert.equal(environment.connector_catalogs[0].source_views.length, 3);
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
  await assert.rejects(value.load(),cause=>{assert.equal(cause.primaryFailure?.code,'InvalidInstalledGcsSite');assert.equal(cause.cleanupPending,false);return true;});
  assert.equal(value.secretCalls(), 0);
});

for (const entrance of ['Local', 'HTTPS']) {
test(`public ${entrance} GCS acceptance keyed Programs check against the installed declaration without credential I/O`, async t => {
  const value = await fixture(t);
  // Synthetic expected bytes are never consumed here. This case establishes
  // real public Check/declaration connectivity, not a successful GCS read.
  // Lookup policy is an explicit Host decision, not a Source-adapter default
  // or a caller Program claim. Use the same bounded selection for preparation
  // and both public entrances.
  const baseEnvironmentWire = selectInstalledHostEnvironment(moon,
    value.options.baseEnvironmentWire.trimEnd(), undefined, hostLookupExecutionPolicy);
  const installed = await loadInstalledSource(value.profilePath, {...value.options, baseEnvironmentWire});
  value.loaded.push(installed);
  const environment = moon.clientProgramCheckEnvironment(installed.environmentWire,
    JSON.parse(installed.environmentWire).evidence_bundle_cid,
    false, false, true, false, false, false, false);
  const client = await connectFixture(t, entrance, value);
  for (const program of Object.values(acceptancePrograms(value))) {
    const prepared = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),
      'json', environment, undefined);
    assert.ok(moon.clientProgramPreparationReady(prepared),
      inspect(moon.clientProgramPreparationIssue(prepared), {depth: 8, maxStringLength: 3000}));
    // The private typed Owner projection is DATA, not an enum-layout read or
    // a release/minifier-dependent constructor name. Other outcomes are None.
    assert.equal(typeof moon.clientProgramPreparationDecodedResponseLimitJson, 'function');
    assert.equal(moon.clientProgramPreparationDecodedResponseLimitJson(prepared), undefined);
    const invalidFormat = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),
      'not-a-program-format', environment, undefined);
    assert.equal(moon.clientProgramPreparationReady(invalidFormat), undefined);
    assert.equal(moon.clientProgramPreparationDecodedResponseLimitJson(invalidFormat), undefined);
    // A single missing decoded byte must still refuse the admitted extent.
    // Neither exact path literals nor an empty result can narrow its declared
    // capacity; the independent 3 * 2 * 8192 obligation remains unchanged.
    const insufficientWire = selectInstalledHostEnvironment(moon,
      installed.environmentWire, undefined,
      {...hostLookupExecutionPolicy, max_total_decoded_response_bytes: 49151});
    const insufficientEnvironment = moon.clientProgramCheckEnvironment(insufficientWire,
      JSON.parse(insufficientWire).evidence_bundle_cid,
      false, false, true, false, false, false, false);
    const insufficient = moon.clientProgramPrepareEffectFreeWithParameters(JSON.stringify(program),
      'json', insufficientEnvironment, undefined);
    assert.equal(moon.clientProgramPreparationReady(insufficient), undefined);
    const limit = moon.clientProgramPreparationDecodedResponseLimitJson(insufficient);
    assert.equal(typeof limit, 'string');
    assert.equal(limit, '{"stageIndex":0,"stepIndex":2}',
      'the same checked Program must retain its exact original stage and join-step cause');
    const checked = await client.check(program, {kind: 'program', scope: 'bound_input'});
    assert.equal(checked.report?.verdict, 'verified', inspect(checked, {depth: 8, maxStringLength: 3000}));
  }
  assert.equal(value.secretCalls(), 0, 'public Check cannot mint a token or contact GCS');
});
test(`public ${entrance} GCS explicit selectors check without namespace disclosure authority`, async t => {
  const value = await fixture(t);
  const client = await connectFixture(t, entrance, value);
  for (const program of Object.values(acceptancePrograms(value))) {
    const checked = await client.check(program, {kind: 'program', scope: 'bound_input'});
    assert.equal(checked.report?.verdict, 'verified', inspect(checked, {depth: 8, maxStringLength: 3000}));
  }
  assert.equal(value.secretCalls(), 0, 'selector disclosure cannot mint a token or contact GCS');
});
test(`public ${entrance} GCS selector metadata remains protected without namespace authority`, async t => {
  const value = await fixture(t);
  const client = await connectFixture(t, entrance, value);
  for (const program of Object.values(acceptancePrograms(value))) {
    // Keep the original protected-boundary control on an independent Host
    // without metadata disclosure authority, rather than widening read grants.
    const omitted = structuredClone(program);
    delete omitted.stages[0].inputs.files.view;
    delete omitted.stages[0].inputs.contents.view;
    const protectedCheck = await client.check(omitted, {kind: 'program', scope: 'bound_input'});
    assert.equal(protectedCheck.report?.verdict, 'undetermined');
    assert.deepEqual(protectedCheck.report.coverage.unresolved,
      [{boundary: 'source_resolution', reason: 'unresolved_protected'}]);
    assert.deepEqual(protectedCheck.report.reasons, []);
  }
  assert.equal(value.secretCalls(), 0, 'public Check cannot mint a token or contact GCS');
});
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


test('registered GCS native completion keeps complete Command Mapping and original close result',async t=>{
  const value=await fixture(t),source=await value.load(),wire=source.environmentWire;
  const environment=JSON.parse(wire);
  assert.equal(environment.command_contracts.length,1);
  assert.equal(environment.mapping_contracts.length,1);
  assert.notEqual(moon.clientProgramCheckEnvironment(wire,environment.evidence_bundle_cid,
    false,false,true,false,false,false,false),undefined);
  assert.deepEqual(source.publishedStoreTargets,[{targetRef:'connector://storage/objects',
    mappingRef:'mapping:storage.gcs.objects.upload.v1',commandRef:'command:storage.gcs.upload.v1'}]);
  assert.equal(typeof source.issueOriginalCollectionReference,'function');
  const closing=source.close();
  assert.equal(typeof closing?.then,'function','Forward the original Source close instead of dropping its pending observation');
  assert.equal(await closing,undefined,'The original synchronous Site uses Unit, not an invented Boolean ACK');
  assert.equal(value.secretCalls(),0);
});
