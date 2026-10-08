import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, unlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteRuntimeBundle} from './remote-bundle-signature.mjs';
import {openRuntimeBundleStore} from './runtime-bundle-store.mjs';

const control = runtimeCore(moon).remoteBundleControl;
const targetTriple = 'aarch64-apple-darwin';
const cid = character => `sha256:${character.repeat(64)}`;
const ownedId = binding =>
  `set-retention:${control.holdBindingIdentity(binding)}`;

function database(path, action) {
  const connection = new DatabaseSync(path);
  try { return action(connection); }
  finally { connection.close(); }
}

const row = (store, sql, ...values) => database(store.path,
  connection => connection.prepare(sql).get(...values));
const change = (store, sql, ...values) => database(store.path,
  connection => connection.prepare(sql).run(...values));
const held = store => row(store,
  'SELECT COUNT(*) AS count FROM bundle_holds').count;
const state = (store, value) => control.recordProjection(
  store.inspect(value.runtimeBundleCid, control).record,
);

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-bundle-retention-'));
  const stores = [];
  const keys = generateKeyPairSync('ed25519');
  const bundleAuthorities = new Map([
    ['bundle-authority-a', new Map([['key-a', keys.publicKey]])],
  ]);
  t.after(async () => {
    for (const store of stores.reverse()) store.close();
    await rm(root, {recursive: true, force: true});
  });
  const open = async (name = 'store', options = {}) => {
    const store = await openRuntimeBundleStore(join(root, name), {
      bundleAuthorities,
      targetTriple,
      maxBundles: 16,
      maxOwners: 16,
      maxComponentBytes: 1024n,
      ...options,
    });
    stores.push(store);
    return store;
  };
  const prepare = async (revision, bytes = Buffer.from(`runtime-${revision}`)) => {
    const sourcePath = join(root, `component-${revision}`);
    await writeFile(sourcePath, bytes, {mode: 0o600});
    const manifest = control.prepare({
      issuerAuthority: 'bundle-authority-a',
      bundleName: 'site-runtime',
      revision,
      targetTriple,
      componentCid: `sha256:${createHash('sha256').update(bytes).digest('hex')}`,
      componentBytes: BigInt(bytes.byteLength),
      connectorRegistration: 'duckdb',
      connectorRevision: `duckdb/${revision}`,
      strategyRevision: 'strategy/1',
    });
    return Object.freeze({
      sourcePath,
      manifest,
      signed: signRemoteRuntimeBundle(manifest, control, {
        keyId: 'key-a', privateKey: keys.privateKey,
      }),
      runtimeBundleCid: control.identity(manifest),
    });
  };
  const install = async (store, value) => {
    await store.install(value.sourcePath, value.signed, control);
    store.activate(value.runtimeBundleCid, control);
  };
  return Object.freeze({open, prepare, install});
}

async function member(store, value, overrides = {}) {
  const context = await store.retentionContext(value.runtimeBundleCid, control);
  const options = {
    distribution: control.prepareDistribution([value.runtimeBundleCid]),
    catalogIncarnation: context.catalogIncarnation,
    coordinatorAuthority: 'coordinator-a',
    workspaceId: 'workspace-a',
    authorityScopeCid: cid('a'),
    environment: 'test',
    setRevisionCid: cid('b'),
    runtimeBundleCid: value.runtimeBundleCid,
    siteKey: 'site-a',
    siteGeneration: 1,
    initialRevision: context.initialRevision,
    attemptId: 'attempt-a',
    ...overrides,
  };
  return Object.freeze({binding: control.prepareHoldBinding(options), options});
}

test('owned bundle holds persist exact retries across activation and reopen',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const first = await prepare('first');
    const second = await prepare('second');
    const store = await open();
    await install(store, first);
    const {binding, options} = await member(store, first);
    assert.equal((await store.inspectMemberHold(binding, control)).status,
      'unresolved');
    assert.equal(held(store), 0);
    const retained = await store.retainMember(binding, control);
    assert.equal(retained.status, 'retained');
    assert.equal(retained.bindingCid, control.holdBindingIdentity(binding));
    assert.equal(Object.isFrozen(retained), true);
    assert.deepEqual(await store.retainMember(binding, control), retained);
    assert.equal(held(store), 1);
    await install(store, second);
    store.close();

    const reopened = await open();
    assert.equal((await reopened.retentionContext(second.runtimeBundleCid,
      control)).catalogIncarnation, options.catalogIncarnation);
    assert.equal((await reopened.inspectMemberHold(binding, control)).status,
      'retained');
    assert.equal((await reopened.retainMember(binding, control)).status,
      'retained');
    assert.equal(state(reopened, first)[2], '1');
    const released = reopened.releaseMember(binding, control);
    assert.equal(released.status, 'fenced');
    assert.deepEqual(reopened.releaseMember(binding, control), released);
    assert.deepEqual(await reopened.inspectMemberHold(binding, control),
      released);
    assert.deepEqual(await reopened.retainMember(binding, control), released);
    assert.equal(held(reopened), 0);
    await reopened.reclaim(first.runtimeBundleCid, control);
  });

test('release before retain durably fences delayed delivery without tombstones',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('release-first');
    const store = await open();
    await install(store, value);
    const {binding} = await member(store, value);
    const before = state(store, value);
    const released = store.releaseMember(binding, control);
    assert.equal(released.status, 'fenced');
    assert.deepEqual(state(store, value),
      [String(Number(before[0]) + 1), before[1], before[2]]);
    assert.equal(held(store), 0);
    store.close();

    const reopened = await open();
    assert.deepEqual(reopened.releaseMember(binding, control), released);
    assert.deepEqual(await reopened.retainMember(binding, control), released);
    assert.deepEqual(await reopened.inspectMemberHold(binding, control),
      released);
    assert.equal(held(reopened), 0);
  });

test('another owner or scope cannot release an exact owned hold', async t => {
  const {open, prepare, install} = await fixture(t);
  const value = await prepare('scoped');
  const store = await open();
  await install(store, value);
  const {binding, options} = await member(store, value);
  await store.retainMember(binding, control);
  for (const altered of [
    {coordinatorAuthority: 'coordinator-b'},
    {workspaceId: 'workspace-b'},
    {authorityScopeCid: cid('c')},
    {environment: 'production'},
    {setRevisionCid: cid('d')},
    {siteKey: 'site-b'},
    {siteGeneration: 2},
    {attemptId: 'attempt-b'},
  ]) {
    const other = control.prepareHoldBinding({...options, ...altered});
    assert.notEqual(control.holdBindingIdentity(other),
      control.holdBindingIdentity(binding));
    assert.equal(store.releaseMember(other, control).status, 'fenced');
    assert.equal((await store.inspectMemberHold(binding, control)).status,
      'retained');
    assert.equal(held(store), 1);
  }
  assert.throws(() => store.release(ownedId(binding), control),
    {code: 'InvalidRemoteBundleHold'});
  assert.throws(() => store.retain(value.runtimeBundleCid,
    ownedId(binding), 'attempt', control), {code: 'InvalidRemoteBundleHold'});
  store.retain(value.runtimeBundleCid, 'dispatch-existing', 'attempt', control);
  assert.equal(store.release('dispatch-existing', control), true);
  assert.equal(store.release('dispatch-existing', control), false);
  assert.equal(store.releaseMember(binding, control).status, 'fenced');
});

test('release fences a retain already verifying bytes and duplicate retain is one owner',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('interleaved');
    const store = await open();
    await install(store, value);
    const {binding: cancelled} = await member(store, value);
    const delayedRetain = store.retainMember(cancelled, control);
    const released = store.releaseMember(cancelled, control);
    assert.equal(released.status, 'fenced');
    assert.deepEqual(await delayedRetain, released);
    assert.equal(held(store), 0);
    const {binding: next} = await member(store, value, {attemptId: 'next'});
    const [first, duplicate] = await Promise.all([
      store.retainMember(next, control), store.retainMember(next, control),
    ]);
    assert.equal(first.status, 'retained');
    assert.deepEqual(duplicate, first);
    assert.equal(held(store), 1);
    assert.equal(state(store, value)[2], '1');
  });

test('same derived hold ID with changed stored binding rejects every operation',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('collision');
    const store = await open();
    await install(store, value);
    const {binding, options} = await member(store, value);
    await store.retainMember(binding, control);
    const changed = control.prepareHoldBinding({...options,
      coordinatorAuthority: 'coordinator-b'});
    change(store, 'UPDATE bundle_holds SET kind = ? WHERE hold_id = ?',
      control.holdBindingJson(changed), ownedId(binding));
    await assert.rejects(store.retainMember(binding, control),
      {code: 'RemoteBundleHoldCollision'});
    await assert.rejects(store.inspectMemberHold(binding, control),
      {code: 'RemoteBundleHoldCollision'});
    assert.throws(() => store.releaseMember(binding, control),
      {code: 'RemoteBundleHoldCollision'});
    assert.equal(held(store), 1);
    assert.equal(state(store, value)[2], '1');
  });

test('replacement catalog never acknowledges an old hold as released', async t => {
  const {open, prepare, install} = await fixture(t);
  const value = await prepare('replacement');
  const original = await open();
  await install(original, value);
  const {binding, options} = await member(original, value);
  await original.retainMember(binding, control);
  const replacement = await open('replacement');
  await install(replacement, value);
  const context = await replacement.retentionContext(value.runtimeBundleCid,
    control);
  assert.notEqual(context.catalogIncarnation, options.catalogIncarnation);
  assert.equal((await replacement.inspectMemberHold(binding, control)).status,
    'unavailable');
  assert.equal((await replacement.retainMember(binding, control)).status,
    'unavailable');
  assert.equal(replacement.releaseMember(binding, control).status, 'unavailable');
  assert.equal(held(replacement), 0);
  assert.deepEqual(state(replacement, value), ['1', '1', '0']);
  assert.equal((await original.inspectMemberHold(binding, control)).status,
    'retained');
});

test('legacy catalog requires explicit opt-in and keeps ordinary dispatch holds',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('legacy');
    const store = await open();
    await install(store, value);
    store.close();
    change(store, 'DELETE FROM metadata WHERE key IN (?, ?)',
      'owned_retention_version', 'catalog_incarnation');
    const legacy = await open();
    legacy.retain(value.runtimeBundleCid, 'legacy-dispatch', 'attempt', control);
    await assert.rejects(legacy.retentionContext(value.runtimeBundleCid, control),
      {code: 'RemoteBundleRetentionUninitialized'});
    assert.equal(legacy.release('legacy-dispatch', control), true);
    const before = state(legacy, value);
    const incarnation = legacy.initializeRetention(control);
    assert.equal(control.catalogIncarnationValid(incarnation), true);
    assert.equal(legacy.initializeRetention(control), incarnation);
    assert.deepEqual(state(legacy, value), before);
    const {binding} = await member(legacy, value);
    assert.equal((await legacy.retainMember(binding, control)).status, 'retained');
    legacy.close();
    const reopened = await open();
    assert.equal(reopened.initializeRetention(control), incarnation);
    assert.equal(reopened.releaseMember(binding, control).status, 'fenced');
  });

test('legacy opt-in refuses conflicting reserved hold rows', async t => {
  const {open, prepare, install} = await fixture(t);
  const value = await prepare('legacy-conflict');
  const store = await open();
  await install(store, value);
  store.retain(value.runtimeBundleCid, 'old-dispatch', 'attempt', control);
  store.close();
  change(store, 'DELETE FROM metadata WHERE key IN (?, ?)',
    'owned_retention_version', 'catalog_incarnation');
  change(store, 'UPDATE bundle_holds SET hold_id = ? WHERE hold_id = ?',
    'set-retention:legacy', 'old-dispatch');
  const reopened = await open();
  assert.throws(() => reopened.initializeRetention(control),
    {code: 'RemoteBundleRetentionUnavailable'});
  assert.equal(row(reopened, 'SELECT value FROM metadata WHERE key = ?',
    'catalog_incarnation'), undefined);
  assert.equal(held(reopened), 1);
  assert.equal(state(reopened, value)[2], '1');
});

test('missing or invalid initialized metadata fails closed after reopen', async t => {
  const {open, prepare, install} = await fixture(t);
  const value = await prepare('metadata');
  for (const mode of ['missing', 'invalid']) {
    const store = await open(mode);
    await install(store, value);
    const {binding} = await member(store, value);
    await store.retainMember(binding, control);
    store.close();
    if (mode === 'missing') {
      change(store, 'DELETE FROM metadata WHERE key = ?', 'catalog_incarnation');
    } else {
      change(store, 'UPDATE metadata SET value = ? WHERE key = ?',
        'invalid-incarnation', 'catalog_incarnation');
    }
    const reopened = await open(mode);
    await assert.rejects(reopened.retentionContext(value.runtimeBundleCid,
      control), {code: 'RemoteBundleRetentionUnavailable'});
    assert.throws(() => reopened.initializeRetention(control),
      {code: 'RemoteBundleRetentionUnavailable'});
    assert.equal((await reopened.retainMember(binding, control)).status,
      'unavailable');
    assert.equal((await reopened.inspectMemberHold(binding, control)).status,
      'unavailable');
    assert.equal(reopened.releaseMember(binding, control).status, 'unavailable');
    assert.equal(held(reopened), 1);
    assert.equal(state(reopened, value)[2], '1');
  }
});

test('missing bytes block custody claims but permit exact held cleanup', async t => {
  const {open, prepare, install} = await fixture(t);
  const value = await prepare('missing-bytes');
  const store = await open();
  await install(store, value);
  const {binding} = await member(store, value);
  await store.retainMember(binding, control);
  await unlink(store.inspect(value.runtimeBundleCid, control).artifactPath);
  assert.equal((await store.retainMember(binding, control)).status, 'unavailable');
  assert.equal((await store.inspectMemberHold(binding, control)).status,
    'unavailable');
  assert.equal(held(store), 1);
  assert.equal(store.releaseMember(binding, control).status, 'fenced');
  assert.equal(held(store), 0);
});

test('failed durable release rolls back both the hold and owner transition',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('release-rollback');
    const store = await open();
    await install(store, value);
    const {binding} = await member(store, value);
    await store.retainMember(binding, control);
    const before = state(store, value);
    database(store.path, connection => connection.exec(`
      CREATE TRIGGER fail_owned_release BEFORE DELETE ON bundle_holds
      BEGIN SELECT RAISE(ABORT, 'injected release failure'); END
    `));
    assert.throws(() => store.releaseMember(binding, control),
      /injected release failure/);
    assert.deepEqual(state(store, value), before);
    assert.equal(held(store), 1);
    assert.equal((await store.inspectMemberHold(binding, control)).status,
      'retained');
    database(store.path, connection =>
      connection.exec('DROP TRIGGER fail_owned_release'));
    assert.equal(store.releaseMember(binding, control).status, 'fenced');
    assert.equal(held(store), 0);
  });

test('invalid signature and inconsistent owner count preserve cleanup custody',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('corrupt-record');
    const store = await open();
    await install(store, value);
    const {binding} = await member(store, value);
    await store.retainMember(binding, control);
    change(store, 'UPDATE bundles SET owners = ? WHERE runtime_bundle_cid = ?',
      2, value.runtimeBundleCid);
    assert.equal((await store.inspectMemberHold(binding, control)).status,
      'unavailable');
    assert.equal(store.releaseMember(binding, control).status, 'unavailable');
    assert.equal(held(store), 1);
    change(store, 'UPDATE bundles SET owners = ?, signature = ? ' +
      'WHERE runtime_bundle_cid = ?', 1, 'invalid', value.runtimeBundleCid);
    assert.equal((await store.inspectMemberHold(binding, control)).status,
      'unavailable');
    assert.equal(store.releaseMember(binding, control).status, 'unavailable');
    assert.equal(held(store), 1);
  });

test('missing records and regressed revisions remain unavailable', async t => {
  const {open, prepare, install} = await fixture(t);
  const value = await prepare('regressed');
  const store = await open();
  await install(store, value);
  const {binding} = await member(store, value);
  change(store, 'UPDATE bundles SET record_revision = ? ' +
    'WHERE runtime_bundle_cid = ?', 0, value.runtimeBundleCid);
  assert.equal((await store.inspectMemberHold(binding, control)).status,
    'unavailable');
  assert.equal((await store.retainMember(binding, control)).status, 'unavailable');
  assert.equal(store.releaseMember(binding, control).status, 'unavailable');
  change(store, 'DELETE FROM bundles WHERE runtime_bundle_cid = ?',
    value.runtimeBundleCid);
  assert.equal((await store.inspectMemberHold(binding, control)).status,
    'unavailable');
  assert.equal(store.releaseMember(binding, control).status, 'unavailable');
  assert.equal(held(store), 0);
});

test('shared members retain custody until the last owned and dispatch hold release',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('shared-member');
    const store = await open();
    await install(store, value);
    const {binding: first} = await member(store, value);
    await store.retainMember(first, control);
    const {binding: second} = await member(store, value, {
      setRevisionCid: cid('c'), attemptId: 'attempt-b',
    });
    await store.retainMember(second, control);
    store.retain(value.runtimeBundleCid, 'dispatch-shared', 'attempt', control);
    store.drain(value.runtimeBundleCid, control);
    assert.equal(store.releaseMember(first, control).status, 'fenced');
    await assert.rejects(store.reclaim(value.runtimeBundleCid, control));
    assert.equal((await store.inspectMemberHold(second, control)).status,
      'retained');
    assert.equal(store.releaseMember(second, control).status, 'fenced');
    await assert.rejects(store.reclaim(value.runtimeBundleCid, control));
    assert.equal(store.release('dispatch-shared', control), true);
    const reclaimed = await store.reclaim(value.runtimeBundleCid, control);
    await assert.rejects(readFile(reclaimed.artifactPath), {code: 'ENOENT'});
    assert.equal(held(store), 0);
  });

test('new owned holds use existing active admission and owner quota', async t => {
  const {open, prepare, install} = await fixture(t);
  const value = await prepare('quota');
  const store = await open('store', {maxOwners: 1});
  await install(store, value);
  const {binding: first} = await member(store, value);
  await store.retainMember(first, control);
  const {binding: second} = await member(store, value, {attemptId: 'attempt-b'});
  await assert.rejects(store.retainMember(second, control),
    {code: 'MoonBitHostFailure'});
  assert.equal(held(store), 1);
  assert.equal((await store.retainMember(first, control)).status, 'retained');
  store.releaseMember(first, control);
  store.drain(value.runtimeBundleCid, control);
  const {binding: inactive} = await member(store, value, {attemptId: 'inactive'});
  await assert.rejects(store.retainMember(inactive, control),
    {code: 'MoonBitHostFailure'});
  assert.equal(held(store), 0);
});

test('revision exhaustion refuses fences and preserves the final live hold',
  async t => {
    const {open, prepare, install} = await fixture(t);
    const value = await prepare('exhausted');
    const store = await open();
    await install(store, value);
    change(store, 'UPDATE bundles SET record_revision = ? ' +
      'WHERE runtime_bundle_cid = ?', 2147483647, value.runtimeBundleCid);
    const {binding: exhausted} = await member(store, value);
    assert.throws(() => store.releaseMember(exhausted, control),
      {code: 'MoonBitHostFailure'});
    await assert.rejects(store.retainMember(exhausted, control),
      {code: 'MoonBitHostFailure'});
    assert.equal(held(store), 0);
    assert.deepEqual(state(store, value), ['2147483647', '1', '0']);
    change(store, 'UPDATE bundles SET record_revision = ? ' +
      'WHERE runtime_bundle_cid = ?', 2147483646, value.runtimeBundleCid);
    const {binding: final} = await member(store, value, {attemptId: 'final'});
    assert.equal((await store.retainMember(final, control)).status, 'retained');
    assert.equal((await store.retainMember(final, control)).status, 'retained');
    assert.throws(() => store.releaseMember(final, control),
      {code: 'MoonBitHostFailure'});
    assert.equal((await store.inspectMemberHold(final, control)).status, 'retained');
    assert.equal(held(store), 1);
    assert.deepEqual(state(store, value), ['2147483647', '1', '1']);
  });
