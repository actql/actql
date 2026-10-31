import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {createObjectWriterOwner} from './object-writer-owner.mjs';

const digest = value => `sha256:${createHash('sha256')
  .update(value).digest('hex')}`;
const failure = code => Object.assign(new Error(code), {code});

test('writer open failure stays observed before the payload caller resumes', () => {
  // The payload reader may yield before its first writer operation. Exercise
  // the actual owner in another process so an unobserved rejection cannot be
  // hidden by the test runner's rejection listener. These are operation ports,
  // not real Store, FD or Resource admission evidence.
  const moduleUrl = new URL('./object-writer-owner.mjs', import.meta.url).href;
  for (const primitive of [false, true]) {
    execFileSync(process.execPath, ['--unhandled-rejections=strict', '--input-type=module', '-e', `
      import assert from 'node:assert/strict';
      import {createObjectWriterOwner} from ${JSON.stringify(moduleUrl)};
      const original = ${primitive ? 'undefined' : "Object.freeze(new Error('OriginalOpenFailure'))"};
      let held = true, opens = 0, releases = 0;
      const reservation = {get held() { return held; }, release() {
        assert.equal(held, true); held = false; releases++; return true;
      }};
      const writer = createObjectWriterOwner(1, false, reservation, {
        stagingDirectory: '/not-opened',
        async open() { opens++; throw original; },
        fail(code) { throw Object.assign(new Error(code), {code}); },
      });
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(writer.status().finished, true);
      assert.equal(writer.status().reservationHeld, false);
      assert.equal(writer.status().cleanupPending, false);
      await assert.rejects(writer.seal(), cause => cause === original);
      await assert.rejects(writer.append('x'), {code: 'PublicationObjectWriterClosed'});
      assert.equal(await writer.cancel(), false);
      assert.equal(await writer.cancel(), false);
      assert.equal(opens, 1); assert.equal(releases, 1);
    `], {encoding: 'utf8', stdio: 'pipe'});
  }
});

test('a fresh successful seal retires its redundant staging alias without another directory ACK',async()=>{
  const {writer,counts}=fixture();
  await writer.append('data');
  assert.deepEqual(await writer.seal(digest('data')),{cid:digest('data'),bytes:4,created:true});
  assert.equal(writer.status().reservationHeld,false);
  assert.deepEqual(counts(),{releases:1,closeCalls:1,unlinkCalls:1,syncCalls:1,linked:1});
});

test('failed alias unlink after a real final-name ACK keeps the same reservation and cleanup',async()=>{
  const {writer,counts,failUnlink}=fixture();
  await writer.append('data');failUnlink();
  await assert.rejects(writer.seal(digest('data')),{code:'UNLINK_FAILED'});
  assert.equal(writer.status().cleanupPending,true);assert.equal(writer.status().reservationHeld,true);
  assert.deepEqual(counts(),{releases:0,closeCalls:1,unlinkCalls:1,syncCalls:1,linked:1});
  assert.equal(await writer.cancel(),true);assert.equal(await writer.cancel(),false);
  assert.deepEqual(counts(),{releases:1,closeCalls:1,unlinkCalls:2,syncCalls:2,linked:1});
});

function fixture(maxBytes = 4) {
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
  const writes = [];
  const handle = {
    async write(buffer, offset, length) {
      if (emptyWrites-- > 0) return {bytesWritten: 0};
      writes.push({buffer, offset, length});
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
    writer: createObjectWriterOwner(maxBytes, false, reservation, operations),
    writes: () => writes,
    failClose: () => { closeFailures++; },
    failUnlink: () => { unlinkFailures++; },
    failSync: () => { syncFailures++; },
    failWrite: () => { emptyWrites++; },
    counts: () => ({
      releases, closeCalls, unlinkCalls, syncCalls, linked,
    }),
  };
}

test('queued mutable frames keep independent exact backing and original bytes',
  async () => {
    // These are operations doubles, not real FD/Store or Resource admission.
    const {writer, writes} = fixture(6);
    const buffer = Buffer.from([1, 0, 255]);
    const source = new Uint8Array([9, 2, 0, 254, 9]);
    const view = source.subarray(1, 4);
    const first = writer.append(buffer);
    const second = writer.append(view);
    buffer.fill(7);
    source.fill(8);
    await Promise.all([first, second]);
    const observed = writes();
    assert.equal(observed.length, 2);
    assert.deepEqual([...observed[0].buffer], [1, 0, 255]);
    assert.deepEqual([...observed[1].buffer], [2, 0, 254]);
    for (const write of observed) {
      assert.equal(write.offset, 0);
      assert.equal(write.length, 3);
      assert.equal(write.buffer.byteOffset, 0);
      assert.equal(write.buffer.buffer.byteLength, 3);
      assert.notEqual(write.buffer.buffer, buffer.buffer);
      assert.notEqual(write.buffer.buffer, source.buffer);
    }
    assert.notEqual(observed[0].buffer.buffer, observed[1].buffer.buffer);
    const result = await writer.seal(digest(new Uint8Array([1, 0, 255, 2, 0, 254])));
    assert.equal(result.bytes, 6);
    assert.equal(writer.status().reservationHeld, false);
  });

test('typed snapshots measure their actual extent despite a shadowed byteLength',
  async () => {
    for (const frame of [Buffer.from([1, 2]), new Uint8Array([1, 2])]) {
      const {writer, writes} = fixture();
      Object.defineProperty(frame, 'byteLength', {value: 4});
      try {
        await writer.append(frame);
        // Inspect the extent first; a failing candidate never prints or
        // hashes an uninitialized tail as expected test material.
        assert.equal(writes()[0].buffer.byteLength, 2);
        assert.deepEqual([...writes()[0].buffer], [1, 2]);
        assert.equal(writes()[0].buffer.buffer.byteLength, 2);
        const result = await writer.seal(digest(new Uint8Array([1, 2])));
        assert.equal(result.bytes, 2);
        assert.equal(writer.status().reservationHeld, false);
      } finally {
        await writer.cancel();
      }
    }
  });

test('a shadowed byteLength cannot admit an oversized typed frame or allocate',
  async () => {
    const {writer, writes, counts} = fixture(2);
    const frame = new Uint8Array([1, 2, 3]);
    Object.defineProperty(frame, 'byteLength', {value: 1});
    const allocate = Buffer.allocUnsafeSlow;
    let allocations = 0;
    Buffer.allocUnsafeSlow = function(size) {
      allocations++;
      return Reflect.apply(allocate, Buffer, [size]);
    };
    try {
      await assert.rejects(async () => writer.append(frame),
        {code: 'PublicationObjectLimit'});
      assert.equal(allocations, 0);
      assert.equal(writes().length, 0);
      assert.equal(writer.status().bytes, 0);
      assert.equal(writer.status().reservationHeld, true);
    } finally {
      Buffer.allocUnsafeSlow = allocate;
      await writer.cancel();
    }
    assert.equal(counts().releases, 1);
  });

test('string snapshot retains exact UTF8 bytes without normalization or a slab',
  async () => {
    const {writer, writes} = fixture();
    await writer.append('e\u0301\0');
    const [{buffer}] = writes();
    assert.deepEqual([...buffer], [0x65, 0xcc, 0x81, 0]);
    assert.equal(buffer.byteOffset, 0);
    assert.equal(buffer.buffer.byteLength, 4);
    const result = await writer.seal(digest(new Uint8Array([0x65, 0xcc, 0x81, 0])));
    assert.equal(result.bytes, 4);
    assert.equal(writer.status().reservationHeld, false);
  });

test('empty frame and one-short limit preserve the original writer and cleanup',
  async () => {
    const {writer, writes, counts} = fixture(3);
    await writer.append(new Uint8Array(0));
    await assert.rejects(writer.append('data'), {code: 'PublicationObjectLimit'});
    assert.equal(writes().length, 0);
    assert.equal(writer.status().bytes, 0);
    assert.equal(writer.status().finished, false);
    assert.equal(writer.status().reservationHeld, true);
    await writer.append(new Uint8Array([1, 0, 255]));
    assert.equal(writes()[0].buffer.buffer.byteLength, 3);
    const result = await writer.seal(digest(new Uint8Array([1, 0, 255])));
    assert.equal(result.bytes, 3);
    assert.equal(counts().releases, 1);
  });

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
