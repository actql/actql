// Actual Store consumeObject on an original OS FileHandle.
import assert from 'node:assert/strict';
import test from 'node:test';
import fs, {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {tmpdir} from 'node:os';

import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

async function exercise(t, {original = 'abcd', changed, injected,
  maxRead = Infinity, onAccept} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-object-read-extent-'));
  const originalOpen = fs.open, slow = Buffer.allocUnsafeSlow;
  let store, handle, passed = false;
  const restore = () => {
    fs.open = originalOpen;
    Buffer.allocUnsafeSlow = slow;
    syncBuiltinESMExports();
  };
  t.after(async () => {
    restore();
    if (handle?.fd >= 0) await handle.close();
    if (store !== undefined) assert.equal(await store.close(), true);
    if (passed) await rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved object read extent failure: ${directory}`);
  });
  store = await openLocalPublicationStore({directory,
    storeAuthorityCid: cid('original object extent fixture'),
    capacityBytes: 1024 * 1024, maxObjectBytes: 131072, maxObjects: 16,
    maxContractNodes: 4096, maxContractDepth: 64}, createPublicationContractControlFixture());
  const writer = store.createObjectWriter(Buffer.byteLength(original));
  await writer.append(original);
  const stored = await writer.seal(cid(original));
  const path = join(directory, 'objects', stored.cid.slice(7));
  let stats = 0, streams = 0, reads = 0;
  const accepted = [], aliases = [], allocations = [], destinations = [];
  Buffer.allocUnsafeSlow = function(length) {
    const bytes = Reflect.apply(slow, Buffer, [length]);
    if (new Error().stack.includes('consumeObject')) allocations.push(length);
    return bytes;
  };
  fs.open = async (...args) => {
    const selected = await originalOpen(...args);
    if (args[0] !== path) return selected;
    assert.equal(handle, undefined, 'acquire the selected original once');
    handle = selected;
    const stat = handle.stat, stream = handle.createReadStream, read = handle.read;
    handle.stat = async function(...args) {
      const result = await Reflect.apply(stat, this, args);
      if (stats++ === 0 && changed !== undefined) await writeFile(path, changed);
      return result;
    };
    handle.createReadStream = function(options) {
      streams++;
      return Reflect.apply(stream, this, [options]);
    };
    handle.read = function(buffer, offset, length, position) {
      reads++;
      destinations.push({buffer, offset, length, position});
      if (injected !== undefined) return Promise.resolve({bytesRead: injected});
      return Reflect.apply(read, this, [buffer, offset, Math.min(length, maxRead), position]);
    };
    return handle;
  };
  syncBuiltinESMExports();
  let result, failure;
  try {
    result = await store.consumeObject(stored.cid, async bytes => {
      accepted.push(Buffer.from(bytes));
      aliases.push(bytes);
      await onAccept?.({bytes, reads: () => reads, allocations: () => [...allocations]});
    });
  } catch (error) { failure = error; }
  finally { restore(); }
  assert.equal(handle.fd, -1, 'same actual FD closes on both success and refusal');
  const received = Buffer.concat(accepted);
  return {result, failure, received, aliases, allocations, destinations, reads, streams, stats,
    pass() {
      t.diagnostic(JSON.stringify({expectedBytes: Buffer.byteLength(original),
        receivedBytes: received.length, allocations, streams,
        qualification: injected === undefined ? 'Actual original FD and bounded filled reads' : 'Actual FD, invalid read-count result',
        normalNumericProfile: null, publicE2E: 0}));
      passed = true;
    }};
}

test('small fixed object read allocates no default64KiB backing before accept', async t => {
  const f = await exercise(t);
  assert.equal(f.failure, undefined);
  assert.equal(f.result.bytes, 4);
  assert.equal(f.received.toString(), 'abcd');
  assert.ok(f.allocations.length > 0, 'observe the actual piece allocator');
  assert.ok(f.allocations.every(n => n <= 4), 'original four-byte envelope precedes allocation');
  assert.equal(f.streams, 0);
  assert.equal(f.reads, 1);
  f.pass();
});

test('actual FD growth after stat cannot deliver tail bytes before version refusal', async t => {
  const f = await exercise(t, {changed: 'abcdefghijklmnop'});
  assert.equal(f.failure?.code, 'PublicationObjectCorrupt');
  assert.equal(f.received.toString(), 'abcd');
  assert.ok(f.allocations.every(n => n <= 4));
  f.pass();
});

test('empty object skips allocation/read but retains original stat hash and FD close', async t => {
  const f = await exercise(t, {original: ''});
  assert.equal(f.failure, undefined);
  assert.equal(f.result.bytes, 0);
  assert.equal(f.received.length, 0);
  assert.equal(f.streams, 0);
  assert.equal(f.reads, 0);
  assert.equal(f.stats, 2);
  assert.deepEqual(f.allocations, []);
  f.pass();
});

test('truncated original object remains corrupt within its admitted read extent', async t => {
  const f = await exercise(t, {changed: 'ab'});
  assert.equal(f.failure?.code, 'PublicationObjectCorrupt');
  assert.equal(f.received.toString(), 'ab');
  assert.ok(f.allocations.every(n => n <= 4));
  f.pass();
});

test('oversize original read count is refused before the consumer callback', async t => {
  const f = await exercise(t, {injected: 6});
  assert.equal(f.failure?.code, 'PublicationObjectCorrupt');
  assert.equal(f.received.length, 0);
  f.pass();
});

test('short reads fill the same dedicated piece with no read-ahead or alias reuse', async t => {
  const original = Buffer.alloc(65549);
  for (let index = 0; index < original.length; index++) original[index] = index % 251;
  const f = await exercise(t, {original, maxRead: 997,
    async onAccept({reads, allocations}) {
      const readCount = reads(), pieces = allocations();
      // Let any queued read-ahead run while the original consumer is pending.
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(reads(), readCount);
      assert.deepEqual(allocations(), pieces);
    }});
  assert.equal(f.failure, undefined);
  assert.equal(f.result.bytes, original.length);
  assert.deepEqual(f.received, original);
  assert.deepEqual(f.allocations, [65536, 13]);
  assert.equal(f.streams, 0);
  assert.equal(f.aliases.length, 2);
  assert.notStrictEqual(f.aliases[0].buffer, f.aliases[1].buffer);
  assert.deepEqual(f.aliases[0], original.subarray(0, 65536), 'earlier escaped bytes are not overwritten');
  assert.equal(f.aliases[0].buffer.byteLength, 65536);
  assert.equal(f.aliases[1].buffer.byteLength, 13);
  let expectedPosition = 0;
  for (const read of f.destinations) {
    assert.equal(read.position, expectedPosition);
    assert.strictEqual(read.buffer, f.aliases[expectedPosition < 65536 ? 0 : 1]);
    assert.equal(read.offset, expectedPosition < 65536 ? expectedPosition : 0);
    expectedPosition += Math.min(read.length, 997);
  }
  assert.equal(expectedPosition, original.length);
  f.pass();
});

test('a truncated short piece retains its original backing without a shrink copy', async t => {
  const f = await exercise(t, {changed: 'ab', maxRead: 1});
  assert.equal(f.failure?.code, 'PublicationObjectCorrupt');
  assert.equal(f.received.toString(), 'ab');
  assert.deepEqual(f.allocations, [4]);
  assert.equal(f.aliases[0].byteLength, 2);
  assert.equal(f.aliases[0].buffer.byteLength, 4);
  assert.strictEqual(f.aliases[0].buffer, f.destinations[0].buffer.buffer);
  assert.equal(f.reads, 3);
  assert.equal(f.streams, 0);
  f.pass();
});
