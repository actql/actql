import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, open, readFile, rm, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const clock = cid('clock commit fixture');
const at = n => `2026-10-21T01:00:00.${String(n).padStart(3, '0')}Z`;
const code = expected => error => error?.code === expected;

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-clock-commit-'));
  const probe = await open(join(directory, 'prototype'), 'wx', 0o600);
  const prototype = Object.getPrototypeOf(probe);
  const original = {sync: prototype.sync, write: prototype.write};
  const originalOpen = fs.promises.open;
  const closes = new WeakMap();
  await probe.close();
  // Restore fault injection before the SAME Store drains its real duties.
  t.after(() => {
    Object.assign(prototype, original);
    fs.promises.open = originalOpen;
    syncBuiltinESMExports();
  });
  const configuration = {directory: join(directory, 'store'),
    storeAuthorityCid: cid('authority'), capacityBytes: 1024 * 1024,
    maxObjectBytes: 64 * 1024, maxObjects: 100,
    maxContractNodes: 4096, maxContractDepth: 64};
  const control = createPublicationContractControlFixture();
  let directorySyncs = 0, fileSyncs = 0;
  let onWrite, onSync, onClose;
  prototype.sync = async function(...args) {
    if ((await this.stat()).isFile()) {
      fileSyncs++;
      if (onSync !== undefined) await onSync(this);
    }
    return Reflect.apply(original.sync, this, args);
  };
  prototype.write = async function(...args) {
    if (onWrite !== undefined) return onWrite(this, args);
    return Reflect.apply(original.write, this, args);
  };
  // FileHandle.close is an instance binding, not a prototype operation.
  // Wrap the real newly acquired handle before the Store captures it.
  fs.promises.open = async (...args) => {
    const handle = await Reflect.apply(originalOpen, fs.promises, args);
    closes.set(handle, handle.close);
    handle.close = function(...arguments_) {
      if (onClose !== undefined) return onClose(this, arguments_);
      return Reflect.apply(closes.get(this), this, arguments_);
    };
    return handle;
  };
  syncBuiltinESMExports();
  const durability = {async syncDirectory(path) {
    if (path === join(configuration.directory, 'clocks')) directorySyncs++;
    const handle = await open(path, 'r');
    try { await handle.sync(); } finally { await handle.close(); }
  }};
  const stores = [];
  const reopen = async () => {
    const store = await openLocalPublicationStore(configuration, control, durability);
    stores.push(store);
    return store;
  };
  const store = await reopen();
  t.after(async () => {
    for (const current of stores) await current.close();
    await rm(directory, {recursive: true, force: true});
  });
  directorySyncs = fileSyncs = 0;
  return {store, reopen, original, prototype,
    closeOriginal: (handle, args) => Reflect.apply(closes.get(handle), handle, args),
    path: join(configuration.directory, 'clocks', `${clock.slice(7)}.json`),
    counts: () => ({directorySyncs, fileSyncs}),
    write: hook => { onWrite = hook; }, sync: hook => { onSync = hook; },
    close: hook => { onClose = hook; }};
}

test('clock commits retain one inode and flush every accepted update', async t => {
  const f = await fixture(t);
  await f.store.observeTrustedClock(clock, at(0));
  const first = await stat(f.path, {bigint: true});
  for (let n = 1; n < 11; n++) await f.store.observeTrustedClock(clock, at(n));
  const last = await stat(f.path, {bigint: true});
  assert.equal(last.ino, first.ino);
  assert.equal(last.size, first.size);
  assert.deepEqual(f.counts(), {fileSyncs: 11, directorySyncs: 1});
  await f.store.close();
  const reopened = await f.reopen();
  await assert.rejects(reopened.observeTrustedClock(clock, at(9)),
    code('PublicationClockUncertain'));
  assert.equal((await reopened.readClockObservation(clock)).observedAt, at(10));
});

test('clock commits reject a torn in-place record live and after reopen', async t => {
  const f = await fixture(t);
  await f.store.observeTrustedClock(clock, at(0));
  assert.equal(typeof JSON.parse(await readFile(f.path, 'utf8')).contentSha256, 'string');
  const failure = Object.assign(new Error('partial clock write'), {code: 'EIO'});
  f.write(async (handle, args) => {
    f.write(undefined);
    const end = args[0].indexOf(',"contentSha256"');
    assert.ok(end > 0);
    await Reflect.apply(f.original.write, handle, [args[0], 0, end, 0]);
    throw failure;
  });
  await assert.rejects(f.store.observeTrustedClock(clock, at(1)), error => error === failure);
  await assert.rejects(f.store.readClockObservation(clock), code('InvalidPublicationClockObservation'));
  await f.store.close();
  const reopened = await f.reopen();
  await assert.rejects(reopened.observeTrustedClock(clock, at(2)),
    code('InvalidPublicationClockObservation'));
});

test('clock commits do not confirm failed data sync from visible bytes', async t => {
  const f = await fixture(t);
  await f.store.observeTrustedClock(clock, at(0));
  const failure = Object.assign(new Error('clock sync failure'), {code: 'EIO'});
  f.sync(() => { f.sync(undefined); throw failure; });
  await assert.rejects(f.store.observeTrustedClock(clock, at(1)), error => error === failure);
  assert.equal((await f.store.readClockObservation(clock)).observedAt, at(1));
  await f.store.observeTrustedClock(clock, at(1));
  assert.deepEqual(f.counts(), {fileSyncs: 3, directorySyncs: 1});
});

test('clock commits retain the same failed-close duty before another update', async t => {
  const f = await fixture(t);
  await f.store.observeTrustedClock(clock, at(0));
  let originalHandle, rejectClose = true, attempted = 0;
  f.write(async (handle, args) => {
    originalHandle = handle;
    return Reflect.apply(f.original.write, handle, args);
  });
  f.close((handle, args) => {
    if (handle === originalHandle) {
      attempted++;
      if (rejectClose) return false;
    }
    return f.closeOriginal(handle, args);
  });
  const failure = await f.store.observeTrustedClock(clock, at(1)).catch(error => error);
  assert.equal(failure.code, 'PublicationStoreCleanupPending');
  assert.equal(failure.cleanupHandle.status().pending, true);
  await assert.rejects(f.store.observeTrustedClock(clock, at(2)),
    code('PublicationStoreCleanupPending'));
  const before = attempted;
  rejectClose = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(attempted, before + 1);
  f.write(undefined);
  await f.store.observeTrustedClock(clock, at(1));
  assert.equal((await f.store.readClockObservation(clock)).observedAt, at(1));
});

test('clock commits migrate legacy records without discarding their floor', async t => {
  const f = await fixture(t);
  await f.store.observeTrustedClock(clock, at(5));
  await f.store.close();
  // A fresh fixture-only legacy file, not a historical Run or clock replay.
  await writeFile(f.path, JSON.stringify({clockContractCid: clock, observedAt: at(5)}));
  const reopened = await f.reopen();
  await assert.rejects(reopened.observeTrustedClock(clock, at(4)),
    code('PublicationClockUncertain'));
  await reopened.observeTrustedClock(clock, at(6));
  const migrated = await stat(f.path, {bigint: true});
  await reopened.observeTrustedClock(clock, at(7));
  assert.equal((await stat(f.path, {bigint: true})).ino, migrated.ino);
  assert.equal(typeof JSON.parse(await readFile(f.path, 'utf8')).contentSha256, 'string');
});

test('clock commits serialize concurrent observations on the same original floor', async t => {
  const f = await fixture(t);
  await f.store.observeTrustedClock(clock, at(0));
  const observations = await Promise.allSettled([
    f.store.observeTrustedClock(clock, at(2)),
    f.store.observeTrustedClock(clock, at(1)),
    f.store.observeTrustedClock(clock, at(3)),
  ]);
  assert.equal(observations[0].status, 'fulfilled');
  assert.equal(observations[1].reason.code, 'PublicationClockUncertain');
  assert.equal(observations[2].status, 'fulfilled');
  assert.equal((await f.store.readClockObservation(clock)).observedAt, at(3));
  assert.deepEqual(f.counts(), {fileSyncs: 3, directorySyncs: 1});
});

test('clock sampling commits after the same queued durable floor', async t => {
  const f = await fixture(t);
  const first = f.store.observeTrustedClock(clock, at(2));
  let samples = 0;
  const next = f.store.sampleTrustedClock(clock, () => { samples++; return at(3); });
  await first;
  assert.equal(await next, at(3));
  assert.equal(samples, 1);
  assert.equal((await f.store.readClockObservation(clock)).observedAt, at(3));
  assert.deepEqual(f.counts(), {fileSyncs: 2, directorySyncs: 1});
  await assert.rejects(f.store.sampleTrustedClock(clock, () => at(1)),
    code('PublicationClockUncertain'));
  await assert.rejects(f.store.sampleTrustedClock(clock, () => 'invalid'),
    code('InvalidPublicationClockObservation'));
});

test('clock commit retains Store ownership through queued and pending file sync', async t => {
  const f = await fixture(t);
  await f.store.observeTrustedClock(clock, at(0));
  let settle, entered;
  const pending = new Promise(resolve => { settle = resolve; });
  const started = new Promise(resolve => { entered = resolve; });
  f.sync(async () => { entered(); await pending; });
  const update = f.store.observeTrustedClock(clock, at(1));
  try {
    await assert.rejects(f.store.close(), code('PublicationStoreCleanupPending'));
    await started;
    await assert.rejects(f.store.close(), code('PublicationStoreCleanupPending'));
    assert.equal(f.store.status().closed, false);
  } finally { settle(); }
  await update;
  assert.equal(await f.store.close(), true);
});
