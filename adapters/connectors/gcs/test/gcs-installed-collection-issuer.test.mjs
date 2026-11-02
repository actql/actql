import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {inspect} from 'node:util';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import * as fixtureMoon from '../../../../_build/js/release/build/connectors/gcs/fixtures/original_reference_node/original_reference_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {loadInstalledSource} from '../../../host-node/installed-source.mjs';
import {installedSourceFixtureLifetime} from '../../../host-node/fixtures/installed-source-initialization.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
import {observeOwnScopedStateFds} from '../../../../scripts/fixtures/external-rest/conformance.mjs';
import {installRowSourceAuthorization, openRowSourceCredentialSite} from '../../../host-node/installed-row-source.mjs';
import {openSqliteCredentialJournal} from '../../../site-node/sqlite-credential-journal.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {loadInstalledGcsSource} from '../host/installed-gcs-source.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const baseEnvironmentWire = (await readFile(new URL('../../../../spec/local-check-environment.json',
  import.meta.url), 'utf8')).trimEnd();

async function fixture(t,{installation=installedConnectors.find(entry=>entry.name==='gcs')}={}) {
  const scratch = await createOwnedScratch({parent: new URL('../../../../_build/', import.meta.url).pathname,
    prefix: 'gcs-original-collection-', label: 'GCS original installed collection issuer'});
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
  // Reference custody is not dispatch permission. An empty account cannot
  // authorize a GCS read/write, and this fixture never asks it to do so.
  const accountConfigurationWire = canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'fixture', entries: []});
  const profile = {version: 'actql-installed-gcs-source/0.1', connectorId: 'storage',
    project: 'fixture-project', bucket: 'actql-fixture', prefix: 'test/e\u0301/',
    mediaType: 'application/pdf', siteProfilePath, accountConfigurationWire,
    limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
      maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
      maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}};
  let secrets = 0;
  const loaded = [];
  let closeInitial,initialized;
  const lifetime=installedSourceFixtureLifetime({after(close){closeInitial=close;},diagnostic:(...args)=>t.diagnostic(...args)});
  const runtimeBundleCid='sha256:'+(await import('node:crypto')).createHash('sha256').update(await readFile(runtimeUrl)).digest('hex');
  const initialize=()=>initialized??=lifetime.open({root:scratch.path,principalId:userInfo().username,moon,
    installation,runtimeBundleCid,baseEnvironmentWire});
  const options = {root: scratch.path, principalId: userInfo().username, moon, runtimeUrl,
    baseEnvironmentWire, resolveSecret() { secrets++; assert.fail('No credential or GCS I/O'); }};
  const open = async (name, changes = {}, overrides = {}) => {
    const path = join(scratch.path, name);
    await writeFile(path, JSON.stringify({...profile, ...changes}));
    const source=await loadInstalledSource(path,{...options,...overrides,installationServices:initialize().installationServices});
    loaded.push(source);lifetime.sources.push(source);
    return source;
  };
  t.after(async () => {
    await closeInitial();
    assert.equal(observeOwnScopedStateFds([scratch.path]).scopedStateFd0,true);
    assert.equal(secrets, 0);
    scratch.passed();
  });
  return {open,profile,site,options,scratch,
    direct(selected){return initialize().load(loadInstalledGcsSource,selected,{...options,runtimeBundleCid});}};
}

function originalPair(source) {
  const wire = source.environmentWire;
  const environment = moon.clientProgramCheckEnvironment(wire,
    JSON.parse(wire).evidence_bundle_cid, false, false, true, false, false, false, false);
  assert.notEqual(environment, undefined, 'actual Common must admit the complete installed environment');
  return checked(fixtureMoon.fixtureGcsOriginalStorePair(environment));
}

test('ordinary installed GCS supplies its original checked collection without token resolution or send', async t => {
  const {open} = await fixture(t);
  const source = await open('source.json');
  assert.deepEqual(source.publishedStoreTargets, [{targetRef: 'connector://storage/objects',
    mappingRef: 'mapping:storage.gcs.objects.upload.v1', commandRef: 'command:storage.gcs.upload.v1'}]);
  const pair = originalPair(source);
  const original = source.issueOriginalCollectionReference(pair, 1000000);
  assert.equal(fixtureMoon.fixtureGcsReferenceAvailable(original), true);
  const reference = JSON.parse(fixtureMoon.fixtureGcsReferenceWire(original));
  assert.equal(reference.provider_namespace, 'gcs');
  assert.equal(reference.resource_kind, 'file_collection');
  assert.equal(reference.boundary_cid, JSON.parse(source.environmentWire).connector_catalogs[0].catalog_cid);
  assert.deepEqual(source.sourceReadAccesses.map(value => value.resource).sort(),
    ['contents', 'files', 'objects'], 'objects is a real read Source, never a fabricated target field');
  assert.equal(source.admitsSource('connector://storage/objects'), false);
  assert.throws(() => source.issueOriginalCollectionReference(pair, 1),
    {code: 'GcsCollectionReferenceCapacityExceeded'});
  for (const maxWork of [undefined, 0, -1, 0.5, Infinity, 2 ** 32 + 1]) {
    assert.throws(() => source.issueOriginalCollectionReference(pair, maxWork),
      {code: 'GcsCollectionReferenceInvalidLimits'});
  }
  await source.close();
  assert.equal(fixtureMoon.fixtureGcsReferenceAvailable(original), false);
  assert.throws(() => source.issueOriginalCollectionReference(pair, 1000000),
    {code: 'GcsCollectionReferenceUnavailable'});
});

test('a different installed scope cannot substitute its actual Common collection pair', async t => {
  const firstFixture=await fixture(t),foreignFixture=await fixture(t);
  const first=await firstFixture.open('first.json');
  const foreign=await foreignFixture.open('foreign.json',{prefix:'test/é/'});
  const pair = originalPair(foreign);
  assert.throws(() => first.issueOriginalCollectionReference(pair, 1000000),
    {code: 'GcsForeignCollectionSelection'});
  const original = foreign.issueOriginalCollectionReference(pair, 1000000);
  assert.equal(fixtureMoon.fixtureGcsReferenceAvailable(original), true);
  await first.close();
  assert.equal(fixtureMoon.fixtureGcsReferenceAvailable(original), true,
    'closing another installation does not retire the original issuer');
});

test('the same credential Site invalidates reference currentness before failed close and retains close-only retry', async t => {
  const {profile, site: siteProfile, options, scratch} = await fixture(t);
  const authorization = await installRowSourceAuthorization({root: scratch.path,
    principalId: options.principalId, connectorRegistration: 'gcs',
    accountConfiguration: profile.accountConfigurationWire});
  const failure = new Error('same original credential journal close failed');
  let closes = 0;
  const site = await openRowSourceCredentialSite({profile: {...siteProfile,
    resourceOrigin: 'https://storage.googleapis.com'}, principalId: options.principalId,
    authorization, connection: 'gcs:fixture-project/actql-fixture',
    connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
    runtimeBundleCid: `sha256:${'7'.repeat(64)}`, commonMoon: moon,
    resolveSecret: options.resolveSecret, admitsApprovalTarget: () => false,
    openCredentialJournal(root, journalOptions) {
      const original = openSqliteCredentialJournal(root, journalOptions);
      return Object.freeze({...original, close() {
        closes++;
        if (closes === 1) throw failure;
        return original.close();
      }});
    }});
  t.after(() => site.close());
  assert.equal(site.referenceCurrent(), true);
  assert.throws(() => site.close(), error => error === failure);
  assert.equal(site.referenceCurrent(), false);
  assert.equal(closes, 1, 'failed close is not physical release');
  assert.throws(() => site.issueReadGrant({}), {code: 'RowSourceSiteClosed'});
  site.close();
  assert.equal(closes, 2, 'the same original journal owns the retry');
  assert.equal(site.referenceCurrent(), false);
});

test('only an explicitly source-only installation under original initialization can omit the collection provider',async t=>{
  const required=await fixture(t);
  await assert.rejects(required.direct({...required.profile,
    siteProfilePath:join(required.scratch.path,'must-not-be-read.json')}),{code:'GcsCollectionProviderUnavailable'});
  const value=await fixture(t,{installation:Object.freeze({registration:'gcs',revision:'gcs/0.1',responseHeaders:[]})});
  const legacy=await value.direct(value.profile);
  assert.equal(legacy.issueOriginalCollectionReference,undefined);
  assert.equal(legacy.publishedStoreTargets,undefined);
  assert.equal(JSON.parse(legacy.environmentWire).connector_catalogs[0].commands.length,0);
  assert.equal(legacy.sourceReadAccesses.length,2);
});

for (const variant of ['resource issuer throws', 'collection issuer throws', 'issuer ABI missing']) {
  test(`acquired original Site retains cleanup when ${variant}`, async t => {
    const {open} = await fixture(t);
    const primary = Object.freeze(new Error(`original ${variant}`));
    const closeFailure = Object.freeze(new Error('same original SQLite close pending'));
    const originalExec = DatabaseSync.prototype.exec;
    const originalClose = DatabaseSync.prototype.close;
    let database, databaseClosed = false, allowClose=false, closeAttempts = 0, issuerCalls = 0;
    // Observe only this fresh fixture's actual connection. No replacement
    // journal, credential grant, historical DB or physical operation is used.
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql.includes('CREATE TABLE IF NOT EXISTS journal_metadata')) {
        assert.equal(database ?? this, this);
        database = this;
      }
      return originalExec.call(this, sql);
    });
    t.mock.method(DatabaseSync.prototype, 'close', function() {
      assert.equal(this, database, 'cleanup must keep the acquired original database');
      closeAttempts++;
      if (!allowClose) throw closeFailure;
      originalClose.call(this);
      databaseClosed = true;
    });
    // A failing pre-fix diagnostic has no exported Site carrier. Its test
    // teardown still closes the exact observed fresh DB, never an old Run.
    t.after(() => {
      if (database !== undefined && !databaseClosed) {
        originalClose.call(database);
        databaseClosed = true;
      }
    });
    const originalIssuer = moon.clientProgramResourceReferenceIssuer;
    const testMoon = {...moon, clientProgramResourceReferenceIssuer:
      variant === 'issuer ABI missing' ? undefined : (...args) => {
        issuerCalls++;
        if (issuerCalls === (variant === 'resource issuer throws' ? 1 : 2)) throw primary;
        return originalIssuer(...args);
      }};
    let failure;
    await assert.rejects(open('constructor-failure.json', {}, {moon: testMoon}), error => {
      failure = error;
      const chain=[];let cursor=error;for(let i=0;i<6&&cursor&&typeof cursor==='object';i++,cursor=cursor.primaryFailure??cursor.cause){chain.push({code:cursor.code,name:cursor.name,stack:typeof cursor.stack==='string'?cursor.stack.split('\n').slice(0,6):undefined});}t.diagnostic(JSON.stringify({originalConstructorFailure:chain}));
      assert.equal(error.code, 'InstalledHostInitializationFailed');
      assert.equal(error.cleanupPending, true);
      if (variant === 'issuer ABI missing') assert.ok(error.primaryFailure instanceof TypeError);
      else assert.equal(error.primaryFailure, primary);
      return true;
    });
    assert.notEqual(database, undefined, 'the actual Site was acquired before failure');
    assert.equal(issuerCalls, variant === 'resource issuer throws' ? 1 :
      variant === 'collection issuer throws' ? 2 : 0);
    assert.equal(closeAttempts,2,
      'Original module catch and outer loader each drain the SAME pending cleanup, without acknowledging it');
    const pending = failure.cleanupHandle.status();
    assert.equal(pending.pending, true);
    assert.deepEqual(pending.owners,['initialization']);
    assert.equal(pending.errors[0].owner,'source-profile');
    assert.equal(pending.errors[0].error, closeFailure);
    assert.equal(databaseClosed, false, 'failed close does not retire its handle');
    allowClose=true;
    const retry = failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.retry(), retry, 'the existing cleanup stays single-flight');
    assert.equal((await retry).pending, false);
    assert.equal(closeAttempts,3,'Retry closes the same acquired Site without reconstruction');
    assert.equal(databaseClosed, true);
    await failure.cleanupHandle.retry();
    assert.equal(closeAttempts,3,'Settled cleanup does not close or construct another Site');
    assert.equal(pending.pending, true, 'the previously returned status snapshot remains frozen');
  });
}


test('two GCS scopes on the same original initializer retain their own collection and close independently',async t=>{
  const value=await fixture(t),first=await value.open('first.json');
  let second;
  try{second=await value.open('second.json',{prefix:'test/é/'});}
  catch(error){
    // The Core PreparationCapacityIssue/LedgerIssue enums carry no business
    // values. This bounded failure observation never chooses a product branch.
    const chain=[];let cursor=error;
    for(let index=0;index<6&&cursor&&typeof cursor==='object';index++,cursor=cursor.primaryFailure??cursor.cause){
      chain.push({name:cursor.name,code:cursor.code,
        stack:typeof cursor.stack==='string'?cursor.stack.split('\n').slice(0,7):undefined,
        capacityIssue:cursor.code==='MoonBitHostFailure'?inspect(cursor.cause,
          {depth:2,customInspect:false,getters:false,maxArrayLength:0}):undefined});
    }
    t.diagnostic(JSON.stringify({sameParentOriginalFailure:chain}));throw error;
  }
  const pair=originalPair(second);
  assert.throws(()=>first.issueOriginalCollectionReference(pair,1000000),{code:'GcsForeignCollectionSelection'});
  const original=second.issueOriginalCollectionReference(pair,1000000);
  assert.equal(fixtureMoon.fixtureGcsReferenceAvailable(original),true);
  await first.close();
  assert.equal(fixtureMoon.fixtureGcsReferenceAvailable(original),true);
  await second.close();
  assert.equal(fixtureMoon.fixtureGcsReferenceAvailable(original),false);
});
