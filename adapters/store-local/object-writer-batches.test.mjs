import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, open, link, unlink, readFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createObjectWriterOwner} from './object-writer-owner.mjs';

const text = '[{"id":1},{"id":2}]';
const cid = 'sha256:7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770';
async function physicalFixture(t, {partial = 32, hold = false, failSecond = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-physical-batch-'));
  let held = true, releases = 0, writes = 0, attempts = 0, bytes = 0, closePending = false;
  let entered, resume;
  const firstWrite = new Promise(resolve => { entered = resolve; });
  const continued = new Promise(resolve => { resume = resolve; });
  const original = Object.freeze(Object.assign(new Error('original partial write failure'), {code: 'EIO'}));
  const reservation = {get held() { return held; }, release() {
    assert(held); held = false; releases++; return true;
  }};
  const writer = createObjectWriterOwner(32, false, reservation, {
    stagingDirectory: root, objectsDirectory: root,
    async open(path, flags, mode) {
      const fd = await open(path, flags, mode);
      return {
        async write(buffer, offset, length, position) {
          assert(buffer.byteLength <= 32);
          assert.equal(buffer.buffer.byteLength, buffer.byteLength);
          attempts++;
          if (failSecond && attempts === 2) throw original;
          const result = await fd.write(buffer, offset, Math.min(length, partial), position);
          writes++; bytes += result.bytesWritten;
          if (writes === 1) { entered(); if (hold) await continued; }
          return result;
        },
        sync: () => fd.sync(), stat: () => fd.stat(),
        close() { if (closePending) { closePending = false; return false; } return fd.close(); },
      };
    },
    link, unlink,
    async syncDirectory(path) { const fd = await open(path, 'r'); try { await fd.sync(); } finally { await fd.close(); } },
    fail(code) { throw Object.assign(new Error(code), {code}); },
    objectPath: () => join(root, 'sealed'), isReclaiming: () => false,
    accountInstalled() {},
    async verifyObject() { throw new Error('no duplicate object in fresh fixture'); },
  });
  t.after(async () => {
    resume();
    await writer.cancel();
    assert.equal(writer.status().reservationHeld, false);
    await rm(root, {recursive: true});
  });
  return {writer, firstWrite, resume, original,
    pendingClose() { closePending = true; },
    counts: () => ({writes, bytes, releases}),
    read: () => readFile(join(root, 'sealed'), 'utf8')};
}

test('physical writer commits a coalesced canonical frame and tail with two completed writes', async t => {
  const f = await physicalFixture(t);
  await f.writer.append(text.slice(0, -1));
  await f.writer.append(']');
  assert.deepEqual(f.counts(), {writes: 2, bytes: 19, releases: 0});
  assert.deepEqual(await f.writer.seal(cid), {cid, bytes: 19, created: true});
  assert.equal(await f.read(), text);
  assert.equal(f.counts().releases, 1);
});

test('physical batch append acknowledges only the full original partial-write loop', async t => {
  const f = await physicalFixture(t, {partial: 3, hold: true});
  let acknowledged = false;
  const append = f.writer.append(text.slice(0, -1)).then(() => { acknowledged = true; });
  await f.firstWrite;
  assert.equal(acknowledged, false);
  assert.equal(f.writer.status().bytes, 0);
  assert.deepEqual(f.counts(), {writes: 1, bytes: 3, releases: 0});
  f.resume(); await append;
  assert.equal(f.writer.status().bytes, 18);
  await f.writer.append(']'); await f.writer.seal(cid);
  assert.equal(await f.read(), text);
  assert.deepEqual(f.counts(), {writes: 7, bytes: 19, releases: 1});
});

test('failed physical batch retains original error and pending FD reservation until cleanup', async t => {
  const f = await physicalFixture(t, {partial: 3, failSecond: true});
  await assert.rejects(f.writer.append(text.slice(0, -1)), error => error === f.original);
  assert.equal(f.writer.status().bytes, 0);
  await assert.rejects(f.writer.seal(cid), {code: 'PublicationObjectWriterClosed'});
  f.pendingClose();
  await assert.rejects(f.writer.cancel(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(f.writer.status().cleanupPending, true);
  assert.equal(f.writer.status().reservationHeld, true);
  assert.deepEqual(f.counts(), {writes: 1, bytes: 3, releases: 0});
  assert.equal(await f.writer.cancel(), true);
  assert.equal(f.writer.status().reservationHeld, false);
  assert.equal(f.counts().releases, 1);
});
