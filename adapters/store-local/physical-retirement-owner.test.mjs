import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile, readFile, lstat, open, unlink, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {createPhysicalRetirementOwner} from './physical-retirement-owner.mjs';

async function fixture(t, hooks = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-retirement-owner-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'original');
  await writeFile(path, 'payload');
  const handle = await open(path, 'r'), state = await handle.stat();
  const nativeClose = handle.close.bind(handle);
  t.after(async () => { if (handle.fd >= 0) await nativeClose(); });
  const original = Object.freeze({cid: `sha256:${createHash('sha256').update('payload').digest('hex')}`,
    byte_count: 7, device: String(state.dev), inode: String(state.ino)});
  const fences = new Set();
  let closeCalls = 0, releases = 0, unlinks = 0;
  handle.close = async () => { closeCalls++; return hooks.close ? hooks.close(handle, nativeClose) : nativeClose(); };
  const owner = createPhysicalRetirementOwner(original, handle, {
    async pathState() {
      let state;
      try { state = await lstat(path); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      if (hooks.pathState) await hooks.pathState();
      return state;
    },
    async unlink() { unlinks++; await unlink(path); if (hooks.unlinked) await hooks.unlinked(path); },
    fence: value => fences.add(value),
    async releaseQuota(value) {
      assert.equal(value, original, 'only the immutable original reaches Store quota');
      if (hooks.releaseQuota) await hooks.releaseQuota(value);
      releases++;
    },
    forget: value => fences.delete(value),
  });
  owner.admit();
  return {owner, original, handle, path, directory, fences,
    counts: () => ({closeCalls, releases, unlinks}),
    async acknowledge() { const fd = await open(directory, 'r'); try { await fd.sync(); } finally { await fd.close(); } },
  };
}

test('concurrent cleanup and late ACK never unlink or refund a replacement', async t => {
  let permit, entered;
  const blocked = new Promise(resolve => { permit = resolve; });
  const observed = new Promise(resolve => { entered = resolve; });
  const f = await fixture(t, {async pathState() { entered(); await blocked; },
    async unlinked(path) { await writeFile(path, 'payload'); }});
  const first = f.owner.unlinkOriginal(), second = f.owner.unlinkOriginal();
  assert.equal(first, second, 'the exact original unlink is single-flight across callers');
  await observed; permit(); await Promise.all([first, second]);
  assert.equal((await f.handle.stat()).nlink, 0, 'real original allocation remains open after unlink');
  const replacement = await lstat(f.path);
  assert.notDeepEqual([String(replacement.dev), String(replacement.ino)], [f.original.device, f.original.inode]);
  await f.acknowledge();
  const a = f.owner.retireAfterDirectoryAck(), b = f.owner.retireAfterDirectoryAck();
  assert.equal(a, b, 'close and quota settlement have one exact owner flight');
  await Promise.all([a, b]); await f.owner.retireAfterDirectoryAck();
  assert.deepEqual(f.counts(), {closeCalls: 1, releases: 1, unlinks: 1});
  assert.equal(await readFile(f.path, 'utf8'), 'payload');
  assert.equal(f.fences.size, 0);
});

test('a lost unlink reply retries the original FD without unlinking its replacement', async t => {
  const failure = Object.assign(new Error('lost original unlink reply'), {code: 'EIO'});
  const f = await fixture(t, {unlinked() { throw failure; }});
  await assert.rejects(f.owner.unlinkOriginal(), error => error === failure);
  await writeFile(f.path, 'payload');
  await f.owner.unlinkOriginal();
  await f.acknowledge(); await f.owner.retireAfterDirectoryAck();
  assert.deepEqual(f.counts(), {closeCalls: 1, releases: 1, unlinks: 1});
  assert.equal(await readFile(f.path, 'utf8'), 'payload');
});

test('native quota uncertainty retains the fence and confirms only the original once', async t => {
  let attempts = 0;
  const f = await fixture(t, {releaseQuota() {
    if (++attempts === 1) throw Object.assign(new Error('native quota ACK unavailable'), {code: 'EIO'});
  }});
  await f.owner.unlinkOriginal(); await f.acknowledge();
  await assert.rejects(f.owner.retireAfterDirectoryAck(), {code: 'EIO'});
  assert(f.fences.has(f.owner));
  assert.equal(f.handle.fd, -1);
  await Promise.all([f.owner.retireAfterDirectoryAck(), f.owner.retireAfterDirectoryAck()]);
  assert.deepEqual(f.counts(), {closeCalls: 1, releases: 1, unlinks: 1});
  assert.equal(attempts, 2);
  assert.equal(f.fences.size, 0);
});

test('rejected real close never retries a descriptor reused by a replacement', async t => {
  const replacements = [];
  t.after(async () => { for (const handle of replacements) await handle.close(); });
  let reused, expectedFd, f;
  const failure = Object.assign(new Error('lost real close reply'), {code: 'EIO'});
  f = await fixture(t, {async close(handle, nativeClose) {
    expectedFd = handle.fd;
    await nativeClose();
    for (let i = 0; i < 64 && reused === undefined; i++) {
      const next = await open(join(f.directory, `replacement-${i}`), 'wx+');
      replacements.push(next);
      if (next.fd === expectedFd) reused = next;
    }
    assert(reused, 'the regression must actually reuse the released native descriptor');
    throw failure;
  }});
  await f.owner.unlinkOriginal(); await f.acknowledge();
  await assert.rejects(f.owner.retireAfterDirectoryAck(), error => error === failure);
  await assert.rejects(f.owner.retireAfterDirectoryAck(), error => error === failure);
  await assert.rejects(f.owner.abandon(), {code: 'PublicationStoreCleanupPending'});
  await reused.writeFile('replacement remains owned');
  assert.equal(reused.fd, expectedFd);
  assert.equal((await reused.stat()).size, 25);
  assert.deepEqual(f.counts(), {closeCalls: 1, releases: 0, unlinks: 1});
  assert(f.fences.has(f.owner), 'an unknown close cannot be replaced by vacuous later success');
});

test('retirement refuses before its actual unlink', async t => {
  const f = await fixture(t);
  await assert.rejects(f.owner.retireAfterDirectoryAck(), {code: 'PublicationStoreCleanupPending'});
  assert.deepEqual(f.counts(), {closeCalls: 0, releases: 0, unlinks: 0});
  await f.owner.unlinkOriginal(); await f.acknowledge(); await f.owner.retireAfterDirectoryAck();
});
