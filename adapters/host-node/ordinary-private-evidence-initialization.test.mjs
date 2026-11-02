import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, writeFile, rename, stat, open} from 'node:fs/promises';
import {readFileSync, existsSync} from 'node:fs';
import {tmpdir, userInfo} from 'node:os';
import {join, dirname, resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {parse} from 'acorn';
import {preparePrivateEvidenceKeyInstallation, PRIVATE_EVIDENCE_KEY_FILE}
  from './local-continuation-evidence.mjs';
import {prepareOrdinaryHostJournal, ordinaryHostJournalInstallation} from './ordinary-host-journal.mjs';
import {withOriginalFile} from './source-profile-json.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
import {snapshotHostCapacityPolicy, snapshotHostLookupExecutionPolicy, selectInstalledHostEnvironment} from './installed-host-policy.mjs';
import {originalInitialControlClose, retainInstalledHostInitializationFailure} from './installed-host-cleanup.mjs';
import {prepareOrdinaryHostResult} from './ordinary-host-result.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const authority = 'sha256:' + 'a'.repeat(64);
const hash = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
async function fixture(root, forwardOwnership = true, storeAuthorityCid = authority) {
  root ??= await mkdtemp(join(tmpdir(), 'actql-ordinary-evidence-key-'));
  const originals = {host: {}, installation: {root}, generation: {}, supplier() {}, moduleLifetime: import.meta};
  const journal = prepareOrdinaryHostJournal(originals);
  let key, store;
  try {await journal.admitRootFormat(root); await journal.openRequestJournal(join(root, 'requests'), {});}
  catch (cause) {await journal.close(); throw cause;}
  const directory = join(root, 'checkpoints'), storeDirectory = join(root, 'publication');
  const preparedOwnership = forwardOwnership ? journal.publicationOwnership() : undefined;
  return {root, directory, journal, originals, options: {storeDirectory, storeAuthorityCid,
    preparedOwnership, assertCurrent: () => journal.assertInitializationCurrent(),
    assertFirstInitialization: () => journal.assertPrivateEvidenceFirstInitialization()},
  async prepare() {
    key = await preparePrivateEvidenceKeyInstallation(directory, this.options); return key;
  }, async adopt() {
    store = await openLocalPublicationStore({directory: storeDirectory, storeAuthorityCid,
      capacityBytes: 1048576, maxObjectBytes: 65536, maxObjects: 32,
      maxContractNodes: 1000, maxContractDepth: 64, privateEvidenceKey: key?.key},
    createPublicationContractControlFixture(), undefined, undefined, preparedOwnership);
    await key?.adoptStore(store);
  }, async close() {
    await journal.close(); await store?.close();
    assert.equal((await journal.close()).pending, false);
    key?.key.fill(0);
  }};
}

test('ordinary key setup persists real owner-only material and reopens the same adopted Store generation', async () => {
  const first = await fixture(); let saved, generation, intent, receipt;
  try {
    const key = await first.prepare();
    saved = await readFile(join(first.directory, PRIVATE_EVIDENCE_KEY_FILE));
    assert.equal(saved.length, 32); assert.deepEqual(key.key, saved);
    assert.equal((await stat(join(first.directory, PRIVATE_EVIDENCE_KEY_FILE))).mode & 0o777, 0o600);
    generation = key.keyId; assert.equal(generation, hash(saved));
    intent = await readFile(join(first.directory, 'private-evidence-initialization.json'));
    await first.adopt();
    receipt = await readFile(join(first.directory, 'private-evidence-adopted.json'));
  } finally {await first.close();}
  const reopened = await fixture(first.root);
  try {
    const key = await reopened.prepare(); assert.equal(key.keyId, generation); assert.deepEqual(key.key, saved);
    await reopened.adopt();
    assert.deepEqual(await readFile(join(reopened.directory, 'private-evidence-initialization.json')), intent);
    assert.deepEqual(await readFile(join(reopened.directory, 'private-evidence-adopted.json')), receipt);
  } finally {saved.fill(0); await reopened.close();}
});

test('ordinary adopted key loss refuses without regenerating from absence or its retained intent', async () => {
  const first = await fixture();
  try {await first.prepare(); await first.adopt();} finally {await first.close();}
  const path = join(first.directory, PRIVATE_EVIDENCE_KEY_FILE);
  await rename(path, path + '.test-owned-original');
  const reopened = await fixture(first.root);
  try {
    await assert.rejects(reopened.prepare(), {code: 'PrivateEvidenceKeyUnavailable'});
    await assert.rejects(stat(path), {code: 'ENOENT'});
    assert.equal((await stat(path + '.test-owned-original')).size, 32);
  } finally {await reopened.close();}
});

test('ordinary lost Store and key directories cannot become another first key initialization', async () => {
  const first = await fixture();
  try {await first.prepare(); await first.adopt();} finally {await first.close();}
  const publication = join(first.root, 'publication');
  await rename(publication, publication + '.test-owned-original');
  await rename(first.directory, first.directory + '.test-owned-original');
  const reopened = await fixture(first.root);
  try {
    assert.equal(await reopened.prepare(), undefined);
    await assert.rejects(stat(reopened.directory), {code: 'ENOENT'});
    assert.equal((await stat(join(first.directory + '.test-owned-original', PRIVATE_EVIDENCE_KEY_FILE))).size, 32);
    assert.equal((await stat(join(publication + '.test-owned-original', 'store.json'))).isFile(), true);
  } finally {await reopened.close();}
});

test('ordinary interrupted key setup cannot generate a replacement for missing original material', async () => {
  const first = await fixture();
  try {await first.prepare();} finally {await first.close();}
  const path = join(first.directory, PRIVATE_EVIDENCE_KEY_FILE);
  await rename(path, path + '.test-owned-original');
  const reopened = await fixture(first.root);
  try {
    await assert.rejects(reopened.prepare(), {code: 'PrivateEvidenceKeyUnavailable'});
    await assert.rejects(stat(path), {code: 'ENOENT'});
    await assert.rejects(stat(join(first.directory, 'private-evidence-adopted.json')), {code: 'ENOENT'});
  } finally {await reopened.close();}
});

test('ordinary adopted key corruption refuses the changed generation without overwriting it', async () => {
  const first = await fixture();
  try {await first.prepare(); await first.adopt();} finally {await first.close();}
  const path = join(first.directory, PRIVATE_EVIDENCE_KEY_FILE), wrong = Buffer.alloc(32, 7);
  await rename(path, path + '.test-owned-original'); await writeFile(path, wrong, {mode: 0o600});
  const reopened = await fixture(first.root);
  try {
    await assert.rejects(reopened.prepare(), {code: 'PrivateEvidenceKeyGenerationMismatch'});
    assert.deepEqual(await readFile(path), wrong);
  } finally {await reopened.close();}
});

test('ordinary existing no-key Store cannot infer first adoption from missing key metadata', async () => {
  const first = await fixture();
  try {await first.adopt();} finally {await first.close();}
  const reopened = await fixture(first.root);
  try {
    assert.equal(await reopened.prepare(), undefined);
    await assert.rejects(stat(reopened.directory), {code: 'ENOENT'});
    await reopened.adopt();
  } finally {await reopened.close();}
});

test('ordinary no-key Store stays open for Results but refuses Content before preparation', async () => {
  const first = await fixture();
  try {await first.adopt();} finally {await first.close();}
  const reopened = await fixture(first.root, false);
  const control = createPublicationContractControlFixture();
  const view = prepareOrdinaryHostResult(reopened.originals,
    {root: reopened.root, control, storeAuthorityCid: authority}, () => assert.fail('No business Run'));
  try {
    await view.initialize();
    const store = await view.openStore({directory: join(reopened.root, 'publication'), storeAuthorityCid: authority,
      capacityBytes: 1048576, maxObjectBytes: 65536, maxObjects: 32,
      maxContractNodes: 1000, maxContractDepth: 64}, control);
    view.assertCurrent(); assert.equal(store.status().closed, false);
    assert.throws(() => view.assertContentCurrent(), {message: 'InstalledContentEvidenceUnavailable'});
    await assert.rejects(stat(reopened.directory), {code: 'ENOENT'});
  } finally {await reopened.journal.close(); await view.close(); await reopened.close();}
});

test('ordinary key first setup refuses another Owner or directory before key creation', async () => {
  const f = await fixture();
  try {
    await assert.rejects(preparePrivateEvidenceKeyInstallation(f.directory,
      {...f.options, preparedOwnership: {}}), {code: 'PublicationStoreOwnershipLost'});
    await assert.rejects(preparePrivateEvidenceKeyInstallation(join(f.root, 'other'), f.options),
      {code: 'InvalidPrivateEvidenceInstallation'});
    await assert.rejects(stat(f.directory), {code: 'ENOENT'});
  } finally {await f.close();}
});

test('ordinary concurrent setup cannot pass the same Store exclusion or replace its key', async () => {
  const first = await fixture();
  try {
    await first.prepare();
    const before = await readFile(join(first.directory, PRIVATE_EVIDENCE_KEY_FILE));
    // Another Owner cannot explain the first Owner's fresh, owner-only
    // prefix as a valid existing Store. Keep that earlier format refusal.
    await assert.rejects(fixture(first.root), {code: 'UnknownPublicationStoreFormat'});
    assert.deepEqual(await readFile(join(first.directory, PRIVATE_EVIDENCE_KEY_FILE)), before);
    await first.adopt();
    await assert.rejects(fixture(first.root), {code: 'PublicationStoreBusy'});
    assert.deepEqual(await readFile(join(first.directory, PRIVATE_EVIDENCE_KEY_FILE)), before);
    before.fill(0);
  } finally {await first.close();}
});

// Exact existing-owner writer body with an explicit close-fault port around a
// real FileHandle. This is physical FD custody, not a full Host qualification.
const ownerSource = readFileSync(new URL('./local-continuation-evidence.mjs', import.meta.url), 'utf8');
const declaration = parse(ownerSource, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'writePrivateEvidenceInitializationFile');
assert(declaration);
function originalWriter(openFile) {
  return new Function('withOriginalFile', 'openFile', 'dirname',
    ownerSource.slice(declaration.start, declaration.end) + ';return writePrivateEvidenceInitializationFile;')
  (withOriginalFile, openFile, dirname);
}

test('ordinary key writer retains the same close and never rewrites after a close refusal', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-key-close-')), path = join(root, 'intent');
  let handle, port, closeCalls = 0, writes = 0, replacementCalls = 0;
  const write = originalWriter(async (name, flags, mode) => {
    assert.equal(name, path); handle = await open(name, flags, mode);
    const close = handle.close;
    return port = {writeFile(bytes) {writes++; return handle.writeFile(bytes);}, sync: () => handle.sync(),
      async close() {assert.strictEqual(this, port); closeCalls++;
        if (closeCalls === 1) return false; await Reflect.apply(close, handle, []);}};
  });
  let original;
  await assert.rejects(write(path, Buffer.from('original-intent'), () => {}), error => {
    original = error; return error.cleanupPending === true;
  });
  assert.equal(original.cleanupHandle.status().pending, true);
  assert.equal((await handle.stat()).isFile(), true);
  // The fixture's original captured function stays in the custody helper;
  // another diagnostic callback cannot settle or replace it.
  port.close = () => {replacementCalls++; throw new Error('ReplacementMustNotRun');};
  await original.cleanupHandle.retry();
  assert.equal(original.cleanupHandle.status().pending, false);
  assert.equal(closeCalls, 2); assert.equal(writes, 1); assert.equal(replacementCalls, 0);
  assert.deepEqual(await readFile(path), Buffer.from('original-intent'));
  await assert.rejects(handle.stat(), {code: 'EBADF'});
});

test('ordinary key partial write keeps its primary failure and close-only original cleanup', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-key-partial-')), path = join(root, 'intent');
  const primary = new Error('OriginalPartialKeyIntentWrite');
  let handle, closeCalls = 0, writes = 0;
  const write = originalWriter(async (name, flags, mode) => {
    handle = await open(name, flags, mode); const close = handle.close;
    return {async writeFile(bytes) {writes++; await handle.writeFile(bytes.subarray(0, 3)); throw primary;},
      sync() {assert.fail('Partial write cannot confirm sync');},
      async close() {closeCalls++; if (closeCalls === 1) return false; await Reflect.apply(close, handle, []);}};
  });
  let held;
  await assert.rejects(write(path, Buffer.from('original-intent'), () => {}), error => {
    held = error; return error.cleanupPending === true && error.cause === primary;
  });
  assert.strictEqual(held.cleanupHandle.primaryFailure, primary);
  assert.equal((await handle.stat()).isFile(), true);
  await held.cleanupHandle.retry();
  assert.equal(held.cleanupHandle.status().pending, false);
  assert.deepEqual(await readFile(path), Buffer.from('ori'));
  assert.equal(writes, 1); assert.equal(closeCalls, 2);
});

test('ordinary key sync failure retains its original FD without repeating sync on cleanup', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-key-sync-')), path = join(root, 'original');
  await writeFile(path, Buffer.from('original-key-intent'), {mode: 0o600});
  const primary = new Error('OriginalKeySyncFailure');
  const syncDeclaration = parse(ownerSource, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'syncPrivateEvidenceInitializationPath');
  let handle, closeCalls = 0, syncCalls = 0;
  const sync = new Function('withOriginalFile', 'openFile', 'dirname',
    ownerSource.slice(syncDeclaration.start, syncDeclaration.end) + ';return syncPrivateEvidenceInitializationPath;')
  (withOriginalFile, async (name, flags) => {
    assert.equal(name, path); handle = await open(name, flags); const close = handle.close;
    return {sync() {syncCalls++; throw primary;},
      async close() {closeCalls++; if (closeCalls === 1) return false; await Reflect.apply(close, handle, []);}};
  }, dirname);
  let held;
  await assert.rejects(sync(path, () => {}), error => {
    held = error; return error.cleanupPending === true && error.cause === primary;
  });
  assert.strictEqual(held.cleanupHandle.primaryFailure, primary);
  await held.cleanupHandle.retry();
  assert.equal(held.cleanupHandle.status().pending, false);
  assert.equal(syncCalls, 1); assert.equal(closeCalls, 2);
  assert.deepEqual(await readFile(path), Buffer.from('original-key-intent'));
});

test('ordinary Journal retains the same exclusion until a partial key FD closes independently', async () => {
  const f = await fixture(undefined, false), path = join(f.root, 'partial-key-intent');
  const ownerPath = join(f.root, 'publication', 'owner', 'owner.json');
  let handle, allowClose = false, closeCalls = 0, writes = 0, keyAttempts = 0;
  const writer = originalWriter(async (name, flags, mode) => {
    handle = await open(name, flags, mode); const close = handle.close;
    return {writeFile(bytes) {writes++; return handle.writeFile(bytes);}, sync: () => handle.sync(),
      async close() {closeCalls++; if (!allowClose) return false; await Reflect.apply(close, handle, []);}};
  });
  const resultSource = readFileSync(new URL('./ordinary-host-result.mjs', import.meta.url), 'utf8');
  const resultDeclaration = parse(resultSource, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(node => node.type === 'ExportNamedDeclaration' && node.declaration?.id?.name === 'prepareOrdinaryHostResult').declaration;
  const prepare = new Function('join', 'ordinaryHostJournalInstallation', 'openLocalPublicationStore',
    'preparePrivateEvidenceKeyInstallation', resultSource.slice(resultDeclaration.start, resultDeclaration.end) +
    ';return prepareOrdinaryHostResult;')(join, ordinaryHostJournalInstallation,
    () => assert.fail('Partial key FD precedes Store construction'), async (_directory, options) => {
      keyAttempts++; await writer(path, Buffer.from('original-key-intent'), options.assertCurrent);
      assert.fail('Original close is still pending');
    });
  const control = Object.freeze({}), subject = {root: f.root, storeAuthorityCid: authority, control};
  const view = prepare(f.originals, subject, () => assert.fail('No business Run'));
  let held;
  try {
    await assert.rejects(view.initialize(),
      error => {held = error; return error.code === 'HostResultPublicationCleanupPending';});
    const owner = await readFile(ownerPath);
    const afterJournal = await f.journal.close();
    assert.equal(afterJournal.journalPending, false);
    assert.equal(afterJournal.privateEvidencePending, true);
    assert.equal(afterJournal.pending, true);
    assert.deepEqual(await readFile(ownerPath), owner);
    assert.equal((await handle.stat()).isFile(), true);
    allowClose = true;
    assert.equal((await held.cleanupHandle.retry()).pending, false);
    assert.equal((await f.journal.close()).pending, false);
    await assert.rejects(stat(ownerPath), {code: 'ENOENT'});
    assert.equal(keyAttempts, 1); assert.equal(writes, 1); assert.equal(closeCalls, 2);
  } finally {
    allowClose = true;
    await view.close(); await f.close();
  }
});

// Execute the actual public caller and private setup declarations. Profile I/O
// and the Core contract control are explicit ports; Root/Store/key filesystem
// initialization and original cleanup below use their production owners.
function publicEffectPublisher(publishProfile, {kind = 'Effect', resultPreparation = prepareOrdinaryHostResult} = {}) {
  const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const declaration = name => ast.body.map(node => node.declaration ?? node)
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
  const names = ['localPublicationStoreAuthorityCid', 'localPublicationStoreOptions',
    'preparePublicationRoot', 'publishInstalled' + kind];
  const declarations = names.map(declaration).filter(Boolean).map(node =>
    source.slice(node.start, node.end).replaceAll('import.meta', 'moduleLifetime')).join('\n');
  const control = createPublicationContractControlFixture();
  return new Function('resolve', 'join', 'userInfo', 'readFile', 'admitHostRootFormat',
    'runtimeUrl', 'packageRoot', 'snapshotHostCapacityPolicy', 'snapshotHostLookupExecutionPolicy',
    'selectInstalledHostEnvironment', 'publishInstalled' + kind + 'Profile',
    'prepareOrdinaryHostJournal', 'prepareOrdinaryHostResult', 'runtimeCore',
    'originalInitialControlClose', 'retainInstalledHostInitializationFailure',
    'readHostResultPublicationRunRequirements', 'readHostEffectResultPublicationRunRequirements',
    'localOutputLimits', 'cid', 'moduleLifetime', `
      const localStateRoot=()=>{throw Error('No default Root selected');};
      const assertInstalledConnectorTable=()=>{throw Error('No custom catalogue selected');};
      ${declarations}
return publishInstalled${kind};
    `)(resolve, join, userInfo, readFile, admitHostRootFormat,
    new URL('data:text/javascript,export const fixture=true;'),
    new URL('../../', import.meta.url).pathname, snapshotHostCapacityPolicy, snapshotHostLookupExecutionPolicy,
    selectInstalledHostEnvironment, publishProfile,
    prepareOrdinaryHostJournal, resultPreparation, () => ({publicationControl: control}),
    originalInitialControlClose, retainInstalledHostInitializationFailure,
    () => {throw Error('Publication setup grants no Pure Run');},
    () => {throw Error('Publication setup grants no Effect Run');},
    {maxWireBytes: 10000000}, value => 'sha256:' + createHash('sha256')
      .update(JSON.stringify(value)).digest('hex'), import.meta);
}

test('public Effect publication initializes its original key and Store before provider publication', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-publication-root-'));
  const keyPath = join(root, 'checkpoints', PRIVATE_EVIDENCE_KEY_FILE);
  let calls = 0;
  const publish = publicEffectPublisher(async (_path, options) => {
    assert.equal(options.root, root);
    calls++;
    assert.equal(existsSync(keyPath), true, 'The first publisher must not spend first setup on only the Root marker');
    assert.equal((await stat(keyPath)).size, 32);
    assert.equal((await stat(keyPath)).mode & 0o777, 0o600);
    assert.equal(existsSync(join(root, 'publication', 'store.json')), true);
    assert.equal(existsSync(join(root, 'requests')), false, 'Publication setup does not open a business Journal');
    return {published: true};
  });
  assert.deepEqual(await publish({directory: root, effectProfilePath: 'explicit-fixture-profile'}), {published: true});
  assert.equal(calls, 1);
  const before = await readFile(keyPath);
  const publishedContract = JSON.parse(await readFile(join(root, 'publication', 'store.json')));
  const next = {host: {}, installation: {root}, generation: {}, supplier() {}, moduleLifetime: import.meta};
  const journal = prepareOrdinaryHostJournal(next);
  let key;
  try {
    assert.equal(await journal.admitRootFormat(root), 'current');
    key = await preparePrivateEvidenceKeyInstallation(join(root, 'checkpoints'), {
      storeDirectory: join(root, 'publication'), storeAuthorityCid: publishedContract.store_authority_cid,
      preparedOwnership: journal.privateEvidenceInitializationOwnership(),
      assertCurrent: () => journal.assertInitializationCurrent(),
      assertFirstInitialization: () => journal.assertPrivateEvidenceFirstInitialization(),
    });
    assert.ok(key);
    assert.deepEqual(key.key, before, 'A later Host reopens the same durable original generation');
  } finally {
    key?.key.fill(0); before.fill(0);
    assert.equal((await journal.close()).pending, false);
  }
});


test('public Source then Effect publication keeps the same adopted key without a business Journal', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-publication-source-effect-'));
  const keyPath = join(root, 'checkpoints', PRIVATE_EVIDENCE_KEY_FILE);
  let calls = 0;
  const published = async () => {calls++; return calls;};
  const source = publicEffectPublisher(published, {kind: 'Source'});
  assert.equal(await source({directory: root, sourceProfilePath: 'source-fixture'}), 1);
  const key = await readFile(keyPath);
  try {
    const effect = publicEffectPublisher(published);
    assert.equal(await effect({directory: root, effectProfilePath: 'effect-fixture'}), 2);
    assert.deepEqual(await readFile(keyPath), key);
    assert.equal(existsSync(join(root, 'requests')), false);
  } finally {key.fill(0);}
});

test('public publication preserves existing no-key Store refusal without inferring a new key', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-publication-no-key-'));
  const storeAuthorityCid = hash(JSON.stringify({version: 'actql-local-store-owner/0.1',
    root, principalId: userInfo().username}));
  const first = await fixture(root, true, storeAuthorityCid);
  try {await first.adopt();} finally {await first.close();}
  const publish = publicEffectPublisher(async () => 'published');
  assert.equal(await publish({directory: first.root, effectProfilePath: 'effect-fixture'}), 'published');
  assert.equal(existsSync(join(first.directory, PRIVATE_EVIDENCE_KEY_FILE)), false);
});

test('public publication retains original Store cleanup and cannot publish before its close ACK', async () => {
  const root = await mkdtemp(join(tmpdir(), 'actql-publication-close-'));
  let closeCalls = 0, published = 0, original;
  const publish = publicEffectPublisher(async () => {published++;}, {
    resultPreparation(...args) {
      original = prepareOrdinaryHostResult(...args);
      const close = original.close;
      return {initialize: () => original.initialize(), openStore: (...values) => original.openStore(...values),
        async close() {
          closeCalls++;
          if (closeCalls <= 2) return {pending: true};
          return Reflect.apply(close, original, []);
        }};
    },
  });
  let failure;
  await assert.rejects(publish({directory: root, effectProfilePath: 'effect-fixture'}), cause => {
    failure = cause;
    return cause.cleanupPending === true && cause.cleanupHandle.status().pending === true;
  });
  assert.equal(published, 0);
  assert.equal(closeCalls, 2);
  const other = prepareOrdinaryHostJournal({host: {}, installation: {root}, generation: {}});
  try {await assert.rejects(other.admitRootFormat(root), {code: 'PublicationStoreBusy'});}
  finally {assert.equal((await other.close()).pending, false);}
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(closeCalls, 3);
  assert.equal(published, 0, 'Cleanup never retries provider publication');
  assert.throws(() => original.assertCurrent(), {code: 'HostResultPublicationUnavailable'});
});
