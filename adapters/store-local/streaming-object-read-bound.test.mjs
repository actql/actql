import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, mkdtemp, open, readFile, rm, unlink, writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';

// Run the real private verifier with controlled FileHandle timing. The
// separate physical Store fixtures execute its actual filesystem callers.
const current = await readFile(new URL('./publication-store.mjs', import.meta.url),
  'utf8');
function functionBody(source) {
  const start = source.indexOf('  const verifyObject = async cid => {');
  const end = source.indexOf('\n  // One bounded metadata snapshot.', start);
  assert(start >= 0 && end > start);
  return source.slice(start, end);
}
const fail = code => { throw Object.assign(new Error(code), {code}); };
const quantity = value => Number.isSafeInteger(value) && value >= 0;
const state = changes => ({
  isFile: () => true, size: 4, dev: 1, ino: 2, mtimeMs: 3, ...changes,
});
function fixture(source = current, options = {}) {
  let reads = 0, hashed = 0, closes = 0, retiredStreams = 0, createdStreams = 0;
  const chunks = (options.chunks ?? ['ab', 'cd']).map(chunk => Buffer.from(chunk));
  const destinations = [];
  let selected = 0, offset = 0;
  const handle = {
    async stat() { return reads === 0 ? state(options.before) : state(options.after); },
    createReadStream() {
      createdStreams++;
      return (async function* () {
        try {
          for (const chunk of options.chunks ?? ['ab', 'cd']) {
            reads++;
            yield Buffer.from(chunk);
          }
        } finally { retiredStreams++; }
      })();
    },
    async read(buffer, start, length, position) {
      reads++;
      destinations.push({buffer, start, length, position});
      if (options.readCount !== undefined) return {bytesRead: options.readCount};
      while (selected < chunks.length && offset === chunks[selected].byteLength) {
        selected++;
        offset = 0;
      }
      if (selected === chunks.length) return {bytesRead: 0};
      const count = Math.min(length, chunks[selected].byteLength - offset);
      chunks[selected].copy(buffer, start, offset, offset + count);
      offset += count;
      return {bytesRead: count};
    },
    async close() {
      closes++;
      if (options.closeFailure) throw options.closeFailure;
    },
  };
  const verify = runInNewContext(`(() => {${functionBody(source)} return verifyObject;})()`, {
    Buffer, constants, quantity, fail,
    active() {}, activeSemanticReaders: new Set(),
    configuration: {maxObjectBytes: options.maximum ?? 4},
    objectPath: () => 'original-object',
    async lstat() { return state(options.path); },
    async open() { return handle; },
    createHash() {
      const hash = createHash('sha256');
      return {
        update(chunk) { hashed += chunk.byteLength; hash.update(chunk); },
        digest: encoding => hash.digest(encoding),
      };
    },
    cidHex: () => createHash('sha256').update(options.expected ?? 'abcd').digest('hex'),
  });
  return {verify, destinations, counts: () => ({
    reads, hashed, closes, retiredStreams, createdStreams,
  })};
}
const corrupt = error => error?.code === 'PublicationObjectCorrupt';
const invalid = error => error?.code === 'InvalidPublicationStoreObject';

test('object verifier hashes exact declared bytes using one original read backing',
  async () => {
    const f = fixture();
    const result = await f.verify('original');
    assert.equal(result.bytes, 4);
    assert.deepEqual(f.counts(), {
      reads: 3, hashed: 4, closes: 1, retiredStreams: 0, createdStreams: 0,
    });
    assert.equal(f.destinations.length, 3);
    assert(f.destinations.every(read => read.buffer === f.destinations[0].buffer));
    assert.equal(f.destinations[0].buffer.buffer.byteLength, 5);
    assert.deepEqual(f.destinations.map(read => [read.start, read.length, read.position]),
      [[0, 5, 0], [0, 3, 2], [0, 1, 4]]);
  });

test('fixed verifier baseline hashes growing input; new guard stops before overflow hash',
  async () => {
    // Byte-exact accepted-main witness, not a dependency on a private Git
    // object or a rewritten copy of the old algorithm.
    const original = JSON.parse(await readFile(new URL(
      './streaming-object-read-original.fixture.json', import.meta.url,
    ), 'utf8'));
    assert.equal(createHash('sha256').update(original.body).digest('hex'),
      original.sha256);
    const previous = fixture(original.body +
      '\n  // One bounded metadata snapshot.', {chunks: ['abc', 'def', 'ghi']});
    await assert.rejects(previous.verify('original'), corrupt);
    assert.equal(previous.counts().hashed, 9);
    assert.equal(previous.counts().reads, 3);
    const current = fixture(undefined, {chunks: ['abc', 'def', 'ghi']});
    await assert.rejects(current.verify('original'), corrupt);
    assert.deepEqual(current.counts(), {
      reads: 2, hashed: 3, closes: 1, retiredStreams: 0, createdStreams: 0,
    });
  });

test('changed FD identity or size rejects before acquiring payload bytes',
  async () => {
    for (const before of [
      {isFile: () => false}, {ino: 99}, {size: 5}, {mtimeMs: 99},
    ]) {
      const f = fixture(undefined, {before});
      await assert.rejects(f.verify('original'), invalid);
      assert.equal(f.counts().hashed, 0);
      assert.equal(f.counts().createdStreams, 0);
      assert.equal(f.counts().closes, 1);
    }
  });

test('empty object works; one-short, truncation and mutation remain refusals',
  async () => {
    const empty = fixture(undefined, {
      path: {size: 0}, before: {size: 0}, after: {size: 0}, chunks: [],
      maximum: 0, expected: '',
    });
    assert.equal((await empty.verify('empty')).bytes, 0);
    const short = fixture(undefined, {maximum: 3});
    await assert.rejects(short.verify('original'), invalid);
    assert.equal(short.counts().createdStreams, 0);
    for (const options of [{chunks: ['ab']}, {after: {mtimeMs: 99}}]) {
      const f = fixture(undefined, options);
      await assert.rejects(f.verify('original'), corrupt);
      assert.equal(f.counts().closes, 1);
    }
  });

test('original close failure propagates and is not verifier completion',
  async () => {
    const failure = new Error('ClosePending');
    const f = fixture(undefined, {closeFailure: failure});
    await assert.rejects(f.verify('original'), error => error === failure);
    assert.equal(f.counts().closes, 1);
  });

// Use the actual filesystem and FileHandle. Only the mutation
// timing is controlled; these cases do not fabricate Store or Run authority.
async function physicalVerifier(t, change, {original = 'abcd', maxRead = Infinity,
  closeOutcomes = []} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-bounded-object-race-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'original-object');
  await writeFile(path, original);
  const maximum = Buffer.byteLength(original);
  let handle, hashed = 0, reads = 0, streams = 0, closes = 0;
  const destinations = [], readerDuties = new Set();
  const closeFailure = new Error('OriginalVerifierClosePending');
  t.after(async () => {
    closeOutcomes.length = 0;
    if (handle !== undefined && handle.fd !== -1) await handle.close();
  });
  const verify = runInNewContext(`(() => {${functionBody(current)} return verifyObject;})()`, {
    Buffer, constants, quantity, fail, configuration: {maxObjectBytes: maximum},
    active() {}, activeSemanticReaders: readerDuties,
    objectPath: () => path, lstat,
    async open(value, flags) {
      if (change === 'fifo') {
        await unlink(path);
        execFileSync('mkfifo', [path]);
      }
      handle = await open(value, flags);
      const read = handle.read, stream = handle.createReadStream, close = handle.close;
      handle.read = function(buffer, start, length, position) {
        reads++;
        destinations.push({buffer, start, length, position});
        return Reflect.apply(read, this, [buffer, start, Math.min(length, maxRead), position]);
      };
      handle.createReadStream = function(...args) {
        streams++;
        return Reflect.apply(stream, this, args);
      };
      handle.close = function(...args) {
        const outcome = closeOutcomes[closes++];
        if (outcome === 'false') return Promise.resolve(false);
        if (outcome === 'reject') return Promise.reject(closeFailure);
        return Reflect.apply(close, this, args);
      };
      if (change === 'growth') {
        const originalStat = handle.stat.bind(handle);
        let first = true;
        handle.stat = async (...args) => {
          const snapshot = await originalStat(...args);
          if (first) {
            first = false;
            await writeFile(path, 'abcdefghi');
          }
          return snapshot;
        };
      }
      return handle;
    },
    createHash() {
      const hash = createHash('sha256');
      return {
        update(chunk) { hashed += chunk.byteLength; hash.update(chunk); },
        digest: encoding => hash.digest(encoding),
      };
    },
    cidHex: () => createHash('sha256').update(original).digest('hex'),
  });
  return {verify, closeFailure, destinations, readerDuties,
    hashed: () => hashed, fd: () => handle?.fd,
    counts: () => ({reads, streams, closes})};
}

test('real growing object rejects before hashing and closes its actual FileHandle',
  {timeout: 5000}, async t => {
    const f = await physicalVerifier(t, 'growth');
    await assert.rejects(f.verify('original'), corrupt);
    assert.equal(f.hashed(), 0);
    assert.equal(f.fd(), -1);
  });

test('raced-in FIFO refuses without blocking open or returning verified bytes',
  {timeout: 5000, skip: process.platform === 'win32'}, async t => {
    const f = await physicalVerifier(t, 'fifo');
    await assert.rejects(f.verify('original'), invalid);
    assert.equal(f.hashed(), 0);
    assert.equal(f.fd(), -1);
  });

// Observe acquisition, not just returned byte length: the original verifier
// must keep one dedicated backing including its separate growth probe.
async function originalReadAllocations(action) {
  const original = Buffer.allocUnsafeSlow;
  const sizes = [];
  Buffer.allocUnsafeSlow = function(length) {
    const result = Reflect.apply(original, Buffer, [length]);
    if (new Error().stack.includes('verifyObject')) sizes.push(length);
    return result;
  };
  try { await action(); }
  finally { Buffer.allocUnsafeSlow = original; }
  return sizes;
}

test('small actual verifier bounds acquisition including its one-byte overflow probe',
  async t => {
    const f = await physicalVerifier(t, 'unchanged');
    const sizes = await originalReadAllocations(async () => {
      assert.equal((await f.verify('original')).bytes, 4);
    });
    t.diagnostic(JSON.stringify({originalBytes: 4, readAllocations: sizes,
      normalNumericProfile: null, publicE2E: 0}));
    assert.deepEqual(sizes, [5]);
    assert.equal(f.hashed(), 4);
    assert.equal(f.fd(), -1);
  });

test('growing actual verifier bounds the sentinel without hashing overflow bytes',
  async t => {
    const f = await physicalVerifier(t, 'growth');
    const sizes = await originalReadAllocations(async () => {
      await assert.rejects(f.verify('original'), corrupt);
    });
    t.diagnostic(JSON.stringify({originalBytes: 4, readAllocations: sizes,
      normalNumericProfile: null, publicE2E: 0}));
    assert.deepEqual(sizes, [5]);
    assert.equal(f.hashed(), 0, 'the original growth law is unchanged');
    assert.equal(f.fd(), -1);
  });

test('actual multi-piece short reads reuse one verifier backing and keep the original overflow probe', async t => {
  const original = Buffer.alloc(65549);
  for (let index = 0; index < original.byteLength; index++) original[index] = index % 251;
  const f = await physicalVerifier(t, 'unchanged', {original, maxRead: 997});
  const sizes = await originalReadAllocations(async () => {
    assert.equal((await f.verify('original')).bytes, original.byteLength);
  });
  assert.deepEqual(sizes, [65536]);
  assert(f.destinations.every(read => read.buffer === f.destinations[0].buffer));
  assert.equal(f.destinations[0].buffer.buffer.byteLength, 65536);
  assert.equal(f.destinations.at(-1).position, original.byteLength);
  assert.equal(f.destinations.at(-1).length, 1);
  assert.equal(f.counts().streams, 0);
  assert.equal(f.hashed(), original.byteLength);
  assert.equal(f.fd(), -1);
  assert.equal(f.readerDuties.size, 0);
});

for (const outcome of ['false', 'reject']) {
  test(`actual verifier ${outcome}-close retains its same FD and close-only retry`, async t => {
    const f = await physicalVerifier(t, 'unchanged',
      {maxRead: 1, closeOutcomes: [outcome, outcome]});
    let failure;
    await assert.rejects(f.verify('original'), error => {
      failure = error;
      return outcome === 'false' ? error.code === 'PublicationStoreCleanupPending' : error === f.closeFailure;
    });
    assert.equal(f.hashed(), 4);
    assert.equal(f.counts().reads, 5);
    assert(f.fd() >= 0);
    assert.equal(f.readerDuties.size, 1);
    const cleanup = failure.cleanupHandle, counts = f.counts();
    assert.equal(cleanup.status().pending, true);
    const pending = cleanup.retry();
    assert.strictEqual(cleanup.retry(), pending);
    await assert.rejects(pending, error =>
      outcome === 'false' ? error.code === 'PublicationStoreCleanupPending' : error === f.closeFailure);
    assert.deepEqual(f.counts(), {...counts, closes: 2});
    assert.equal(cleanup.status().pending, true);
    assert(f.fd() >= 0);
    await cleanup.retry();
    assert.equal(cleanup.status().pending, false);
    assert.equal(f.fd(), -1);
    assert.equal(f.readerDuties.size, 0);
    assert.deepEqual(f.counts(), {...counts, closes: 3});
    await cleanup.retry();
    assert.deepEqual(f.counts(), {...counts, closes: 3});
  });
}
