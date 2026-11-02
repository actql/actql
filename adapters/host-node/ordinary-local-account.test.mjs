import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, open, readFile, rename, rm, stat, writeFile} from 'node:fs/promises';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {admitHostRootFormat} from './host-root-format.mjs';
import {prepareOrdinaryLocalAccount} from './ordinary-local-account.mjs';
import {prepareInstalledPublicationRoot} from './installed-publication-root.mjs';
import {createLocalResultAuthorization} from './local-result-authorization.mjs';
import {openLocalPublicationStore, prepareLocalPublicationStoreOwnership,
  closePreparedLocalPublicationStoreOwnership} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

// Actual selected Common, with a test-only artifact locator when the sole
// matching producer belongs to another checkout. Never a product override or
// ordinary installed qualification. Store codec is an explicit test fixture;
// file/format/exclusion/initialization operations below are the real owners.
const runtime = process.env.ACTQL_TEST_COMMON_RUNTIME;
const moon = await import(runtime === undefined ? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href
  : pathToFileURL(runtime).href);
const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const scope = cid('ordinary local account fixture');
const subjects = {controlConnection: 'local-host', configuredConnections: ['local-files'],
  modelTasks: [['provider', cid('registered Task')]], requestTarget: ['local-host', 'realization']};
const facts = {principalId: 'person', resultName: 'answer', indexKey: {namespaceId: 'local',
  authorityScopeCid: scope, runDefinitionCid: cid('Run fixture')}};

async function fixture(t) {
  const parent = await mkdtemp(join(tmpdir(), 'actql-standard-account-'));
  const root = join(parent, 'host');
  let ownership, store, prepared, creation;
  const close = async () => {
    if (store !== undefined) {await store.close(); store = undefined;}
    if (ownership !== undefined) {
      assert.equal((await closePreparedLocalPublicationStoreOwnership(ownership)).pending, false);
      ownership = undefined;
    }
  };
  t.after(async () => {await close(); await rm(parent, {recursive: true, force: true});});
  const start = async (authorization, requestedSubjects = subjects) => {
    creation = await admitHostRootFormat(root);
    ownership = await prepareLocalPublicationStoreOwnership(join(root, 'publication'));
    prepared = await prepareOrdinaryLocalAccount({root, principal: 'person', preparedOriginal: ownership,
      rootCreation: creation, operatorAuthorization: authorization});
    store = await openLocalPublicationStore({directory: join(root, 'publication'),
      storeAuthorityCid: cid(root), capacityBytes: 1024 * 1024, maxObjectBytes: 65536,
      maxObjects: 100, maxContractNodes: 4096, maxContractDepth: 64},
    createPublicationContractControlFixture(), undefined, undefined, ownership);
    return prepared === undefined ? undefined : prepared.adopt(moon, requestedSubjects, store);
  };
  return {root, start, close, marker: join(root, 'host-format.json'),
    config: join(root, 'account', 'account.json'), intent: join(root, 'account-initialization.json'),
    initialize: async () => {
      creation = await admitHostRootFormat(root);
      ownership = await prepareLocalPublicationStoreOwnership(join(root, 'publication'));
      prepared = await prepareOrdinaryLocalAccount({root, principal: 'person', preparedOriginal: ownership,
        rootCreation: creation});
    },
  };
}

test('ordinary Local durably adopts the actual standard profile and reopens without regrant', async t => {
  const f = await fixture(t);
  const authorization = await f.start();
  const config = await readFile(f.config), intent = await readFile(f.intent), marker = await readFile(f.marker);
  assert.equal((await stat(f.config)).mode & 0o777, 0o600);
  const parsed = JSON.parse(config);
  assert.equal(parsed.bootstrap.profile_id, 'actql-local-standard');
  const authorize = createLocalResultAuthorization({moon, authorization,
    principalId: 'person', namespaceId: 'local', authorityScopeCid: scope});
  assert.equal(await authorize(facts), true);
  await f.close();
  const reopened = await f.start();
  assert.equal(reopened.accountConfig, authorization.accountConfig);
  assert.deepEqual(await readFile(f.config), config);
  assert.deepEqual(await readFile(f.intent), intent);
  assert.deepEqual(await readFile(f.marker), marker);
  await assert.rejects(stat(join(f.root, 'reviewer.pem')), {code: 'ENOENT'});
});

test('ordinary Local preserves current Deny on the same Host and after reopening', async t => {
  const f = await fixture(t);
  const authorization = await f.start();
  const authorize = createLocalResultAuthorization({moon, authorization,
    principalId: 'person', namespaceId: 'local', authorityScopeCid: scope});
  assert.equal(await authorize(facts), true);
  const config = JSON.parse(await readFile(f.config, 'utf8'));
  for (const entry of config.entries) if (entry.operation.any_of.includes('read')) entry.outcome = 'deny';
  const restricted = JSON.stringify(config);
  await writeFile(f.config, restricted);
  assert.equal(await authorize(facts), false);
  await f.close();
  const reopened = await f.start();
  assert.equal(await createLocalResultAuthorization({moon, authorization: reopened,
    principalId: 'person', namespaceId: 'local', authorityScopeCid: scope})(facts), false);
  assert.equal(await readFile(f.config, 'utf8'), restricted);
});

test('ordinary Local missing adopted configuration or intent refuses without recreation', async t => {
  for (const field of ['config', 'intent']) {
    const f = await fixture(t);
    await f.start(); await f.close();
    await rename(f[field], f[field] + '.test-owned-original');
    await assert.rejects(f.start(), {code: 'LocalAccountAdoptedStateMissing'});
    await assert.rejects(stat(f[field]), {code: 'ENOENT'});
    assert.ok((await stat(f[field] + '.test-owned-original')).size > 0);
    await f.close();
  }
});

test('ordinary Local cannot infer first initialization from an old marker alone', async t => {
  const f = await fixture(t);
  await admitHostRootFormat(f.root);
  await assert.rejects(f.start(), {code: 'LocalAccountFirstInitializationUnavailable'});
  await assert.rejects(stat(f.intent), {code: 'ENOENT'});
});

test('ordinary Local explicit Account selection replaces bootstrap without materialization', async t => {
  const f = await fixture(t);
  assert.equal(await f.start({accountConfiguration: '{invalid explicit Account'}), undefined);
  await assert.rejects(stat(f.intent), {code: 'ENOENT'});
  await assert.rejects(stat(f.config), {code: 'ENOENT'});
  assert.deepEqual(JSON.parse(await readFile(f.marker)), {
    version: 'actql-local-host-root/0.1', isolation: 'execution-namespace'});
});

test('ordinary Local retains a same pending intent across unrelated initialization failure', async t => {
  const f = await fixture(t);
  await f.initialize();
  const intent = await readFile(f.intent);
  await f.close();
  await f.start();
  assert.deepEqual(await readFile(f.intent), intent);
});

test('ordinary Local confirms the same adoption after an uncertain directory commit', async t => {
  const f = await fixture(t);
  const original = fs.promises.open;
  const originalRename = fs.promises.rename;
  let injected = false, adoptionRenamed = false;
  fs.promises.rename = async function(from, to) {
    const result = await Reflect.apply(originalRename, this, [from, to]);
    if (to === f.marker) adoptionRenamed = true;
    return result;
  };
  fs.promises.open = async function(path, flags, ...args) {
    const handle = await Reflect.apply(original, this, [path, flags, ...args]);
    if (adoptionRenamed && path === f.root && flags === 0 && !injected) {
      handle.sync = async function() {
        injected = true;
        throw Object.assign(new Error('uncertain adoption directory commit'), {code: 'EIO'});
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {await assert.rejects(f.start(), {code: 'EIO'});}
  finally {fs.promises.open = original; fs.promises.rename = originalRename; syncBuiltinESMExports();}
  assert.equal(injected, true);
  const config = await readFile(f.config), marker = await readFile(f.marker);
  await f.close();
  await f.start();
  assert.deepEqual(await readFile(f.config), config);
  assert.deepEqual(await readFile(f.marker), marker);
});

test('ordinary Local partial materialization never restores a missing configuration', async t => {
  const f = await fixture(t);
  const original = fs.promises.rename;
  fs.promises.rename = async function(from, to) {
    if (to === f.marker) throw Object.assign(new Error('interrupted initial adoption'), {code: 'EIO'});
    return Reflect.apply(original, this, [from, to]);
  };
  syncBuiltinESMExports();
  try {await assert.rejects(f.start(), {code: 'EIO'});}
  finally {fs.promises.rename = original; syncBuiltinESMExports();}
  await f.close();
  await rename(f.config, f.config + '.test-owned-original');
  await assert.rejects(f.start(), {code: 'LocalAccountAdoptedStateMissing'});
  await assert.rejects(stat(f.config), {code: 'ENOENT'});
});

// The publication entry records intent, not policy material or adoption.
test('fresh publication hands the same intent to ordinary Local Account adoption', async t => {
  const f = await fixture(t);
  await prepareInstalledPublicationRoot(f.root, 'person');
  const intent = await readFile(f.intent);
  await assert.rejects(stat(f.config), {code: 'ENOENT'});
  const authorization = await f.start();
  assert.equal(authorization.accountConfig, f.config);
  assert.deepEqual(await readFile(f.intent), intent);
  const marker = JSON.parse(await readFile(f.marker));
  assert.equal(marker.account_bootstrap.initialization_cid, cid(intent));
  await f.close();
  await f.start();
  assert.deepEqual(await readFile(f.intent), intent);
});
