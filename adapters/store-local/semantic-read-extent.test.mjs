import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {link, lstat, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';

// Actual private semantic reader and real FileHandle/ReadStream. The original
// content hash plus hard-link identity replaces a duplicate physical hash.
const source = await readFile(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const start = source.indexOf('  const readSemanticBytes = async cid => {');
const end = source.indexOf('\n  // Private evidence uses', start);
assert.ok(start >= 0 && end > start);
const body = source.slice(start, end);

async function exercise(t, {original = 'abcd', changed, maximum = 16384,
  injected, closeFailure} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-semantic-read-extent-'));
  const path = join(directory, 'contract');
  const object = join(directory, 'physical-object');
  await writeFile(path, original);
  await link(path, object);
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  const allocations = [];
  let stats = 0, streams = 0, verified = 0, closes = 0, hashed = 0, passed = false;
  let allowClose = false;
  const slow = Buffer.allocUnsafeSlow;
  Buffer.allocUnsafeSlow = function(length) {
    const result = Reflect.apply(slow, Buffer, [length]);
    if (new Error().stack.includes('internal/fs/streams')) allocations.push(length);
    return result;
  };
  const restore = () => { Buffer.allocUnsafeSlow = slow; };
  t.after(async () => {
    restore();
    if (handle.fd >= 0) await handle.close();
    if (passed) await rm(directory, {recursive: true, force: true});
    else t.diagnostic(`Preserved semantic read extent failure: ${directory}`);
  });
  const read = runInNewContext(`(() => {const activeSemanticReaders = new Set();
    ${body} return readSemanticBytes;})()`, {
    Buffer, constants, configuration: {maxObjectBytes: maximum},
    active() {},
    quantity: value => Number.isSafeInteger(value) && value >= 0,
    fail(code) { throw Object.assign(new Error(code), {code}); },
    contractPath: () => path, objectPath: () => object, lstat,
    async open() {
      return {
        async stat() {
          const snapshot = await handle.stat();
          if (stats++ === 0 && changed !== undefined) await writeFile(path, changed);
          return snapshot;
        },
        createReadStream(options) {
          streams++;
          if (injected !== undefined) return (async function*() { yield injected; })();
          return handle.createReadStream(options);
        },
        async close() {
          closes++;
          if (closeFailure !== undefined && !allowClose) throw closeFailure;
          await handle.close();
        },
      };
    },
    createHash() {
      const hash = createHash('sha256');
      return {
        update(bytes) { hashed += bytes.byteLength; hash.update(bytes); },
        digest: encoding => hash.digest(encoding),
      };
    },
    async verifyObject(cid) {
      verified++;
      assert.equal(cid, 'sha256:' + createHash('sha256').update(original).digest('hex'));
    },
  });
  let result, failure;
  try { result = await read('original'); }
  catch (error) { failure = error; }
  finally { restore(); }
  t.diagnostic(JSON.stringify({allocations, stats, streams, verified, closes, hashed,
    returnedBytes: result?.byteLength ?? null,
    returnedBacking: result?.buffer.byteLength ?? null,
    normalNumericProfile: null, publicE2E: 0}));
  return {result, failure, allocations,
    counts: () => ({stats, streams, verified, closes, hashed}),
    fd: () => handle.fd,
    async retryClose() {
      allowClose = true;
      return failure.cleanupHandle.retry();
    },
    pass() {
      passed = true;
    }};
}

test('small semantic read bounds stream backing before allocation and returns exact dedicated bytes',
  async t => {
    const f = await exercise(t);
    assert.equal(f.failure, undefined);
    assert.equal(f.result.toString(), 'abcd');
    assert.ok(f.allocations.length > 0);
    assert.ok(f.allocations.every(size => size <= 4), 'original extent precedes allocator');
    assert.equal(f.result.byteOffset, 0);
    assert.equal(f.result.buffer.byteLength, 4);
    assert.deepEqual(f.counts(), {stats: 2, streams: 1, verified: 0, closes: 1, hashed: 4});
    assert.equal(f.fd(), -1);
    f.pass();
  });

test('semantic reader refuses actual FD growth and truncation without returning partial bytes', async t => {
  for (const changed of ['abcdefghi', 'ab']) {
    const f = await exercise(t, {changed});
    assert.equal(f.failure?.code, 'PublicationContractCorrupt');
    assert.equal(f.result, undefined);
    assert.ok(f.allocations.every(size => size <= 4));
    assert.equal(f.counts().verified, 0);
    assert.equal(f.counts().closes, 1);
    assert.equal(f.fd(), -1);
    f.pass();
  }
});

test('empty semantic bytes preserve stat identity and one content hash without stream allocation', async t => {
  const f = await exercise(t, {original: ''});
  assert.equal(f.failure, undefined);
  assert.equal(f.result.byteLength, 0);
  assert.deepEqual(f.allocations, []);
  assert.deepEqual(f.counts(), {stats: 2, streams: 0, verified: 0, closes: 1, hashed: 0});
  assert.equal(f.fd(), -1);
  f.pass();
});

test('one-short semantic object refuses before data stream and physical verification', async t => {
  const f = await exercise(t, {maximum: 3});
  assert.equal(f.failure?.code, 'InvalidPublicationContractObject');
  assert.deepEqual(f.allocations, []);
  assert.deepEqual(f.counts(), {stats: 1, streams: 0, verified: 0, closes: 1, hashed: 0});
  assert.equal(f.fd(), -1);
  f.pass();
});

test('injected overflow refuses before semantic hash or byte return', async t => {
  const f = await exercise(t, {injected: Buffer.from('abcde')});
  assert.equal(f.failure?.code, 'PublicationContractCorrupt');
  assert.equal(f.result, undefined);
  assert.equal(f.counts().hashed, 0);
  assert.equal(f.counts().verified, 0);
  assert.equal(f.fd(), -1);
  f.pass();
});

test('semantic close failure remains failure rather than a completed read', async t => {
  const failure = new Error('OriginalClosePending');
  const f = await exercise(t, {closeFailure: failure});
  assert.equal(f.failure, failure);
  assert.equal(f.result, undefined);
  assert.notEqual(f.fd(), -1);
  assert.equal(f.counts().closes, 1);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal((await f.retryClose()).pending, false);
  assert.equal(f.fd(), -1);
  assert.equal(f.counts().closes, 2);
  f.pass();
});
