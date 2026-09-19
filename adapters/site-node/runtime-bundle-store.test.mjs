import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {
  mkdtemp,
  readFile,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteRuntimeBundle} from
  './remote-bundle-signature.mjs';
import {openRuntimeBundleStore} from './runtime-bundle-store.mjs';

const control = runtimeCore(moon).remoteBundleControl;
const targetTriple = 'aarch64-apple-darwin';
const componentCid = bytes =>
  `sha256:${createHash('sha256').update(bytes).digest('hex')}`;

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-runtime-bundles-'));
  const stores = [];
  const keys = generateKeyPairSync('ed25519');
  const bundleAuthorities = new Map([
    ['bundle-authority-a', new Map([['key-a', keys.publicKey]])],
  ]);
  t.after(async () => {
    for (const store of stores.reverse()) store.close();
    await rm(root, {recursive: true, force: true});
  });
  const open = async durability => {
    const store = await openRuntimeBundleStore(join(root, 'store'), {
      bundleAuthorities,
      targetTriple,
      maxBundles: 16,
      maxOwners: 16,
      maxComponentBytes: 1024n,
    }, durability);
    stores.push(store);
    return store;
  };
  const prepare = async (revision, bytes, suffix = revision) => {
    const sourcePath = join(root, `component-${suffix}`);
    await writeFile(sourcePath, bytes, {mode: 0o600});
    const manifest = control.prepare({
      issuerAuthority: 'bundle-authority-a',
      bundleName: 'site-runtime',
      revision,
      targetTriple,
      componentCid: componentCid(bytes),
      componentBytes: BigInt(bytes.byteLength),
      connectorRegistration: 'duckdb',
      connectorRevision: `duckdb/${revision}`,
      strategyRevision: 'strategy/1',
    });
    const signed = signRemoteRuntimeBundle(manifest, control, {
      keyId: 'key-a',
      privateKey: keys.privateKey,
    });
    return Object.freeze({
      sourcePath,
      manifest,
      signed,
      runtimeBundleCid: control.identity(manifest),
    });
  };
  return Object.freeze({open, prepare});
}

test('bundle activation drains old code and survives restart', async t => {
  const {open, prepare} = await fixture(t);
  const first = await prepare('1', Buffer.from('runtime-one'));
  const second = await prepare('2', Buffer.from('runtime-two'));
  const store = await open();

  await store.install(first.sourcePath, first.signed, control);
  store.activate(first.runtimeBundleCid, control);
  store.retain(first.runtimeBundleCid, 'dispatch-a', 'attempt', control);
  await store.install(second.sourcePath, second.signed, control);
  store.activate(second.runtimeBundleCid, control);

  assert.deepEqual(
    control.recordProjection(
      store.inspect(first.runtimeBundleCid, control).record,
    ),
    ['3', '2', '1'],
  );
  assert.equal(
    control.identity(store.active(control).manifest),
    second.runtimeBundleCid,
  );

  store.close();
  const reopened = await open();
  assert.equal(
    control.identity(reopened.active(control).manifest),
    second.runtimeBundleCid,
  );
  assert.equal(reopened.release('dispatch-a', control), true);
  reopened.rollback(first.runtimeBundleCid, control);
  reopened.activate(second.runtimeBundleCid, control);
  const reclaimed = await reopened.reclaim(first.runtimeBundleCid, control);
  assert.deepEqual(control.recordProjection(reclaimed.record), ['7', '3', '0']);
  await reopened.verify(second.runtimeBundleCid, control);
  await assert.rejects(readFile(reclaimed.artifactPath), {code: 'ENOENT'});
});

test('bundle install rejects altered signatures and component bytes',
  async t => {
    const {open, prepare} = await fixture(t);
    const value = await prepare('1', Buffer.from('runtime-one'));
    const store = await open();
    const signature = Buffer.from(value.signed.signature, 'base64url');
    signature[0] ^= 1;
    await assert.rejects(
      store.install(value.sourcePath, {
        ...value.signed,
        signature: signature.toString('base64url'),
      }, control),
      {code: 'RemoteBundleSignatureRejected'},
    );

    await writeFile(value.sourcePath, Buffer.from('runtime-two'));
    await assert.rejects(
      store.install(value.sourcePath, value.signed, control),
      {code: 'RemoteBundleComponentMismatch'},
    );
    assert.equal(store.list(control).length, 0);
  });

test('bundle reclaim keeps responsibility until physical retry succeeds',
  async t => {
    const {open, prepare} = await fixture(t);
    const value = await prepare('1', Buffer.from('runtime-one'));
    let failArtifactRemoval = true;
    const durability = Object.freeze({
      async remove(path) {
        if (failArtifactRemoval && path.includes('/artifacts/')) {
          failArtifactRemoval = false;
          throw Object.assign(new Error('injected removal failure'), {
            code: 'EIO',
          });
        }
        return unlink(path);
      },
      async syncDirectory(path) {
        const {open} = await import('node:fs/promises');
        const descriptor = await open(path, 'r');
        try { await descriptor.sync(); }
        finally { await descriptor.close(); }
      },
    });
    const store = await open(durability);
    await store.install(value.sourcePath, value.signed, control);
    await assert.rejects(
      store.reclaim(value.runtimeBundleCid, control),
      {code: 'EIO'},
    );
    const pending = store.inspect(value.runtimeBundleCid, control);
    assert.equal(pending.reclaimPending, true);
    assert.deepEqual(control.recordProjection(pending.record), ['0', '0', '0']);

    const reclaimed = await store.reclaim(value.runtimeBundleCid, control);
    assert.equal(reclaimed.reclaimPending, false);
    assert.deepEqual(control.recordProjection(reclaimed.record), ['1', '3', '0']);
    await assert.rejects(readFile(reclaimed.artifactPath), {code: 'ENOENT'});
  });

test('shared component remains until its last bundle is reclaimed',
  async t => {
    const {open, prepare} = await fixture(t);
    const bytes = Buffer.from('shared-runtime');
    const first = await prepare('1', bytes, 'shared');
    const second = await prepare('2', bytes, 'shared');
    const store = await open();
    const installed = await store.install(
      first.sourcePath,
      first.signed,
      control,
    );
    await store.install(second.sourcePath, second.signed, control);
    await store.reclaim(first.runtimeBundleCid, control);
    await store.verify(second.runtimeBundleCid, control);
    await store.reclaim(second.runtimeBundleCid, control);
    await assert.rejects(readFile(installed.artifactPath), {code: 'ENOENT'});
  });
