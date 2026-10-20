import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, writeFile, rename, stat, open} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {createHash} from 'node:crypto';
import {parse} from 'acorn';
import {preparePrivateEvidenceKeyInstallation, PRIVATE_EVIDENCE_KEY_FILE}
  from './local-continuation-evidence.mjs';
import {prepareOrdinaryHostJournal, ordinaryHostJournalInstallation} from './ordinary-host-journal.mjs';
import {withOriginalFile} from './source-profile-json.mjs';
import {prepareOrdinaryHostResult} from './ordinary-host-result.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const authority = 'sha256:' + 'a'.repeat(64);
const hash = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
async function fixture(root, forwardOwnership = true) {
  root ??= await mkdtemp(join(tmpdir(), 'actql-ordinary-evidence-key-'));
  const originals = {host: {}, installation: {root}, generation: {}, supplier() {}, moduleLifetime: import.meta};
  const journal = prepareOrdinaryHostJournal(originals);
  let key, store;
  try {await journal.admitRootFormat(root); await journal.openRequestJournal(join(root, 'requests'), {});}
  catch (cause) {await journal.close(); throw cause;}
  const directory = join(root, 'checkpoints'), storeDirectory = join(root, 'publication');
  const preparedOwnership = forwardOwnership ? journal.publicationOwnership() : undefined;
  return {root, directory, journal, originals, options: {storeDirectory, storeAuthorityCid: authority,
    preparedOwnership, assertCurrent: () => journal.assertInitializationCurrent()},
  async prepare() {
    key = await preparePrivateEvidenceKeyInstallation(directory, this.options); return key;
  }, async adopt() {
    store = await openLocalPublicationStore({directory: storeDirectory, storeAuthorityCid: authority,
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
    await assert.rejects(view.openStore({directory: join(f.root, 'publication'), storeAuthorityCid: authority}, control),
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
