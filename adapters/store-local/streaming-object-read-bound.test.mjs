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
    async close() {
      closes++;
      if (options.closeFailure) throw options.closeFailure;
    },
  };
  const verify = runInNewContext(`(() => {${functionBody(source)} return verifyObject;})()`, {
    constants, quantity, fail,
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
  return {verify, counts: () => ({
    reads, hashed, closes, retiredStreams, createdStreams,
  })};
}
const corrupt = error => error?.code === 'PublicationObjectCorrupt';
const invalid = error => error?.code === 'InvalidPublicationStoreObject';

test('object verifier hashes exact declared bytes and retires its original stream',
  async () => {
    const f = fixture();
    const result = await f.verify('original');
    assert.equal(result.bytes, 4);
    assert.deepEqual(f.counts(), {
      reads: 2, hashed: 4, closes: 1, retiredStreams: 1, createdStreams: 1,
    });
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
      reads: 2, hashed: 3, closes: 1, retiredStreams: 1, createdStreams: 1,
    });
  });

test('changed FD identity or size rejects before allocating a read stream',
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

// Use the actual filesystem and FileHandle/ReadStream. Only the mutation
// timing is controlled; these cases do not fabricate Store or Run authority.
async function physicalVerifier(t, change) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-bounded-object-race-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const path = join(directory, 'original-object');
  await writeFile(path, 'abcd');
  let handle, hashed = 0;
  t.after(async () => { if (handle !== undefined && handle.fd !== -1) await handle.close(); });
  const verify = runInNewContext(`(() => {${functionBody(current)} return verifyObject;})()`, {
    constants, quantity, fail, configuration: {maxObjectBytes: 4},
    objectPath: () => path, lstat,
    async open(value, flags) {
      if (change === 'fifo') {
        await unlink(path);
        execFileSync('mkfifo', [path]);
      }
      handle = await open(value, flags);
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
    cidHex: () => createHash('sha256').update('abcd').digest('hex'),
  });
  return {verify, hashed: () => hashed, fd: () => handle?.fd};
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

// Observe acquisition, not just returned chunk length: the selected Node
// stream can allocate its default backing and then copy a smaller result.
async function originalReadAllocations(action) {
  const original = Buffer.allocUnsafeSlow;
  const sizes = [];
  Buffer.allocUnsafeSlow = function(length) {
    const result = Reflect.apply(original, Buffer, [length]);
    if (new Error().stack.includes('internal/fs/streams')) sizes.push(length);
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
    assert.ok(sizes.length > 0);
    assert.ok(sizes.every(size => size <= 5));
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
    assert.ok(sizes.length > 0);
    assert.ok(sizes.every(size => size <= 5));
    assert.equal(f.hashed(), 0, 'the original growth law is unchanged');
    assert.equal(f.fd(), -1);
  });
