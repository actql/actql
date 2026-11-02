import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {mkdtemp, readFile, readdir, rm, stat} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareInstalledPublicationRoot} from './installed-publication-root.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';
import {prepareOrdinaryLocalAccount} from './ordinary-local-account.mjs';
import {prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership}
  from '../store-local/publication-store.mjs';

async function fixture(t) {
  const parent = await mkdtemp(join(tmpdir(), 'actql-publication-intent-'));
  t.after(() => rm(parent, {recursive: true, force: true}));
  const root = join(parent, 'host');
  return {root, intent: join(root, 'account-initialization.json'),
    owner: join(root, 'publication', 'owner', 'owner.json')};
}

async function prepareLater(root) {
  const rootCreation = await admitHostRootFormat(root);
  assert.equal(rootCreation, 'current');
  const original = await prepareLocalPublicationStoreOwnership(join(root, 'publication'));
  try {
    return await prepareOrdinaryLocalAccount({root, principal: 'person',
      preparedOriginal: original, rootCreation});
  } finally {
    assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
  }
}

test('fresh publication saves pending initialization and releases original exclusion', async t => {
  const f = await fixture(t);
  await prepareInstalledPublicationRoot(f.root, 'person');
  const intent = JSON.parse(await readFile(f.intent));
  assert.equal(intent.version, 'actql-local-account-initialization/0.1');
  assert.equal(intent.principal, 'person');
  assert.equal((await stat(f.intent)).mode & 0o777, 0o600);
  assert.deepEqual((await readdir(f.root)).sort(),
    ['account-initialization.json', 'checkpoints', 'host-format.json', 'publication']);
  assert.deepEqual(await readdir(join(f.root, 'publication')), []);
  assert.equal(typeof (await prepareLater(f.root)).adopt, 'function');
});

test('current publication does not backfill a missing intent or reopen default initialization', async t => {
  const f = await fixture(t);
  assert.equal(await admitHostRootFormat(f.root), 'new');
  await prepareInstalledPublicationRoot(f.root, 'person');
  await assert.rejects(stat(f.intent), {code: 'ENOENT'});
  await assert.rejects(prepareLater(f.root), {code: 'LocalAccountFirstInitializationUnavailable'});
});

test('later publication failure and repeated publication preserve the same pending intent', async t => {
  const f = await fixture(t);
  const providerFailure = new Error('provider failed after root preparation');
  await assert.rejects((async () => {
    await prepareInstalledPublicationRoot(f.root, 'person');
    throw providerFailure;
  })(), error => error === providerFailure);
  const saved = await readFile(f.intent);
  await prepareInstalledPublicationRoot(f.root, 'person');
  await prepareLater(f.root);
  assert.deepEqual(await readFile(f.intent), saved);
});

test('pending intent writer retains exclusion and original primary failure until actual close', async t => {
  const f = await fixture(t);
  const originalOpen = fs.promises.open;
  const writeFailure = new Error('original intent write failed');
  let canClose = false, writes = 0, closes = 0, failure;
  fs.promises.open = async function(path, ...args) {
    const handle = await Reflect.apply(originalOpen, this, [path, ...args]);
    if (path === f.intent && args[0] === 'wx') {
      const originalClose = handle.close;
      handle.writeFile = async function() { writes++; throw writeFailure; };
      handle.close = async function() {
        closes++;
        if (!canClose) throw new Error('original close pending');
        return Reflect.apply(originalClose, handle, []);
      };
    }
    return handle;
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects(prepareInstalledPublicationRoot(f.root, 'person'), error => {
      failure = error;
      return error.cleanupHandle.status().pending === true;
    });
    assert.equal(failure.primaryFailure.cause, writeFailure);
    const owner = await readFile(f.owner);
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(await readFile(f.owner), owner);
    assert.equal(writes, 1);
    canClose = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    await assert.rejects(stat(f.owner), {code: 'ENOENT'});
    assert.ok(closes >= 2);
    assert.equal(writes, 1);
    await assert.rejects(prepareLater(f.root), {code: 'LocalAccountInitializationInvalid'});
  } finally {
    canClose = true;
    await failure?.cleanupHandle.retry();
    fs.promises.open = originalOpen;
    syncBuiltinESMExports();
  }
});

test('publication continuation waits for the actual ownership release acknowledgement', async t => {
  const f = await fixture(t);
  const originalRmdir = fs.promises.rmdir;
  let canRelease = false, continued = false, failure;
  fs.promises.rmdir = async function(path, ...args) {
    if (path === join(f.root, 'publication', 'owner') && !canRelease) {
      throw new Error('ownership directory removal pending');
    }
    return Reflect.apply(originalRmdir, this, [path, ...args]);
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects((async () => {
      await prepareInstalledPublicationRoot(f.root, 'person');
      continued = true;
    })(), error => { failure = error; return error.cleanupHandle.status().pending; });
    assert.equal(continued, false);
    const intent = await readFile(f.intent);
    assert.ok((await stat(join(f.root, 'publication', 'owner'))).isDirectory());
    canRelease = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(continued, false);
    await prepareLater(f.root);
    assert.deepEqual(await readFile(f.intent), intent);
  } finally {
    canRelease = true;
    await failure?.cleanupHandle.retry();
    fs.promises.rmdir = originalRmdir;
    syncBuiltinESMExports();
  }
});
