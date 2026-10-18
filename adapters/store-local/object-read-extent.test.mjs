// Actual consumeObject body and OS FD. Store/Run authority is not issued here.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, mkdtemp, writeFile, open, rm} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {join} from 'node:path';
import {tmpdir} from 'node:os';

const source = await readFile(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const start = source.indexOf('  const consumeObject = async (');
const end = source.indexOf('\n  const withCommittedResult = async (', start);
assert.ok(start >= 0 && end > start);
const body = source.slice(start, end);

async function exercise(t, {original = 'abcd', changed, injected,
  maxRead = Infinity, onAccept} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-object-read-extent-'));
  const path = join(directory, 'original');
  await writeFile(path, original);
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  let stats = 0, streams = 0, reads = 0, passed = false;
  const accepted = [], aliases = [], allocations = [], destinations = [];
  const slow = Buffer.allocUnsafeSlow;
  Buffer.allocUnsafeSlow = function(length) {
    const bytes = Reflect.apply(slow, Buffer, [length]);
    if (new Error().stack.includes('consumeObject')) allocations.push(length);
    return bytes;
  };
  const restore = () => { Buffer.allocUnsafeSlow = slow; };
  t.after(async () => {
    restore();
    if (handle.fd >= 0) await handle.close();
    if (passed) await rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved object read extent failure: ${directory}`);
  });
  const consume = runInNewContext(`(() => {${body} return consumeObject;})()`, {
    Buffer, constants, createHash, configuration: {maxObjectBytes: 131072},
    active() {}, quantity: n => Number.isSafeInteger(n) && n >= 0,
    fail(code) { throw Object.assign(new Error(code), {code}); },
    objectPath: () => path, cidHex: () => createHash('sha256').update(original).digest('hex'),
    async open() {
      return {
        async stat() {
          const result = await handle.stat();
          if (stats++ === 0 && changed !== undefined) await writeFile(path, changed);
          return result;
        },
        createReadStream(options) {
          streams++;
          return handle.createReadStream(options);
        },
        read(buffer, offset, length, position) {
          reads++;
          destinations.push({buffer, offset, length, position});
          if (injected !== undefined) return Promise.resolve({bytesRead: injected});
          return handle.read(buffer, offset, Math.min(length, maxRead), position);
        },
        close: () => handle.close(),
      };
    },
  });
  let result, failure;
  try {
    result = await consume('original', async bytes => {
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
