import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createObjectWriterOwner} from './object-writer-owner.mjs';

const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;
const failure = code => Object.assign(new Error(code), {code});

function fixture() {
  let held = true;
  let releases = 0;
  let closeFailures = 0;
  let unlinkFailures = 0;
  let syncFailures = 0;
  let emptyWrites = 0;
  let closeCalls = 0;
  let unlinkCalls = 0;
  let syncCalls = 0;
  let linked = 0;
  let size = 0;
  const handle = {
    async write(_bytes, _offset, length) {
      if (emptyWrites-- > 0) return {bytesWritten: 0};
      size += length;
      return {bytesWritten: length};
    },
    async sync() {},
    async stat() { return {isFile: () => true, size}; },
    async close() {
      closeCalls++;
      if (closeFailures-- > 0) throw failure('CLOSE_FAILED');
    },
  };
  const reservation = Object.freeze({
    get held() { return held; },
    release() {
      if (!held) return false;
      held = false;
      releases++;
      return true;
    },
  });
  const operations = {
    stagingDirectory: '/writer-staging',
    objectsDirectory: '/writer-objects',
    async open() { return handle; },
    async link() { linked++; },
    async unlink() {
      unlinkCalls++;
      if (unlinkFailures-- > 0) throw failure('UNLINK_FAILED');
    },
    async syncDirectory() {
      syncCalls++;
      if (syncFailures-- > 0) throw failure('SYNC_FAILED');
    },
    fail(code) { throw failure(code); },
    objectPath: cid => `/writer-objects/${cid}`,
    isReclaiming: () => false,
    async registerCustody() { throw new Error('unexpected custody'); },
    async reclaimCustody() { throw new Error('unexpected reclaim'); },
    async verifyObject() { throw new Error('unexpected duplicate'); },
    accountInstalled() {},
  };
  return {
    writer: createObjectWriterOwner(4, false, reservation, operations),
    failClose: () => { closeFailures++; },
    failUnlink: () => { unlinkFailures++; },
    failSync: () => { syncFailures++; },
    failWrite: () => { emptyWrites++; },
    counts: () => ({
      releases, closeCalls, unlinkCalls, syncCalls, linked,
    }),
  };
}

test('writer owner retains its reservation after close failure and retries '
    + 'only cleanup',
  async () => {
    const {writer, failClose, counts} = fixture();
    await writer.append('data');
    failClose();
    await assert.rejects(writer.cancel(), {code: 'CLOSE_FAILED'});
    assert.equal(writer.status().cleanupPending, true);
    assert.equal(writer.status().reservationHeld, true);
    assert.deepEqual(counts(), {
      releases: 0, closeCalls: 1, unlinkCalls: 0, syncCalls: 0, linked: 0,
    });
    assert.equal(await writer.cancel(), true);
    assert.equal(await writer.cancel(), false);
    assert.equal(writer.status().cleanupPending, false);
    assert.equal(writer.status().reservationHeld, false);
    assert.deepEqual(counts(), {
      releases: 1, closeCalls: 2, unlinkCalls: 1, syncCalls: 1, linked: 0,
    });
  });

test('seal preserves its primary identity error while failed unlink remains '
    + 'owned',
  async () => {
    const {writer, failUnlink, counts} = fixture();
    await writer.append('data');
    failUnlink();
    await assert.rejects(writer.seal(digest('other')),
      {code: 'PublicationObjectIdentityMismatch'});
    assert.equal(writer.status().cleanupPending, true);
    assert.equal(writer.status().reservationHeld, true);
    assert.equal(counts().releases, 0);
    assert.equal(await writer.cancel(), true);
    assert.equal(writer.status().cleanupPending, false);
    assert.deepEqual(counts(), {
      releases: 1, closeCalls: 1, unlinkCalls: 2, syncCalls: 1, linked: 0,
    });
  });

test('writer owner retains its reservation until directory sync is confirmed',
  async () => {
    const {writer, failSync, counts} = fixture();
    await writer.append('data');
    failSync();
    await assert.rejects(writer.cancel(), {code: 'SYNC_FAILED'});
    assert.equal(writer.status().reservationHeld, true);
    assert.equal(counts().releases, 0);
    assert.equal(await writer.cancel(), true);
    assert.equal(writer.status().reservationHeld, false);
    assert.deepEqual(counts(), {
      releases: 1, closeCalls: 1, unlinkCalls: 2, syncCalls: 2, linked: 0,
    });
  });

test('failed append cannot be retried as a write and cleanup releases once',
  async () => {
    const {writer, failWrite, counts} = fixture();
    failWrite();
    await assert.rejects(writer.append('data'),
      {code: 'IncompletePublicationWrite'});
    assert.equal(writer.status().finished, true);
    assert.equal(writer.status().reservationHeld, true);
    await assert.rejects(writer.append('data'),
      {code: 'PublicationObjectWriterClosed'});
    assert.equal(await writer.cancel(), true);
    assert.equal(await writer.cancel(), false);
    assert.deepEqual(counts(), {
      releases: 1, closeCalls: 1, unlinkCalls: 1, syncCalls: 1, linked: 0,
    });
  });
