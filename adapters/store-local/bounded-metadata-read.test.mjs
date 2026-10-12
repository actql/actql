import assert from 'node:assert/strict';
import {constants} from 'node:fs';
import {lstat, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';

// Execute the actual private helper without loading unrelated runtime bundles.
// This is a source-backed physical primitive test, not public Run acceptance.
const source = await readFile(new URL('./publication-store.mjs', import.meta.url),
  'utf8');
const start = source.indexOf('async function readBounded(path, maximum, closed, signal, ownerOnly = false) {');
const end = source.indexOf('\nasync function processIsAlive(', start);
assert(start >= 0 && end > start);
const body = source.slice(start, end);
const fail = code => { throw Object.assign(new Error(code), {code}); };
const quantity = value => Number.isSafeInteger(value) && value >= 0;
const load = overrides => runInNewContext(`(${body})`, {
  constants, lstat, open, Buffer, quantity, fail, AbortSignal, ...overrides,
});
const invalid = error => error?.code === 'InvalidPublicationStoreObject';
const state = changes => ({
  isFile: () => true, dev: 1n, ino: 2n, size: 4n, mtimeNs: 3n, ctimeNs: 4n,
  ...changes,
});

function fixture(options = {}) {
  const allocations = [];
  const reads = [];
  const opened = [];
  let closes = 0;
  const initial = state(options.initial);
  const handle = {
    async stat() { return reads.length === 0 ? initial : state(options.after); },
    async read(buffer, offset, length, position) {
      reads.push({offset, length, position});
      if (options.readError) throw options.readError;
      const input = Buffer.from(options.content ?? 'abcd');
      const count = Math.min(length, options.chunk ?? length,
        Math.max(0, input.length - position));
      input.copy(buffer, offset, position, position + count);
      return {bytesRead: count};
    },
    async close() {
      closes++;
      if (options.closeError) throw options.closeError;
    },
  };
  const read = load({
    async open(path, flags) { opened.push(flags); return handle; },
    async lstat() { return state(options.path); },
    Buffer: {allocUnsafeSlow(size) {
      allocations.push(size);
      return Buffer.allocUnsafeSlow(size);
    }},
  });
  return {read, allocations, reads, opened, closes: () => closes};
}

test('metadata read pins the FD and requests only the declared bytes plus probe',
  async () => {
    const f = fixture({chunk: 2});
    assert.equal((await f.read('original', 4)).toString(), 'abcd');
    assert.deepEqual(f.allocations, [4, 1]);
    assert.deepEqual(f.reads, [
      {offset: 0, length: 4, position: 0},
      {offset: 2, length: 2, position: 2},
      {offset: 0, length: 1, position: 4},
    ]);
    assert.equal(f.opened[0], constants.O_RDONLY | constants.O_NOFOLLOW |
      constants.O_NONBLOCK);
    assert.equal(f.closes(), 1);
  });

test('metadata cancellation before open acquires no FD or buffer', async () => {
  const f = fixture();
  const abort = new AbortController();
  const reason = new Error('OriginalScopeCancelled');
  abort.abort(reason);
  let acknowledged = 0;
  await assert.rejects(f.read('original', 4, () => { acknowledged++; }, abort.signal),
    error => error === reason);
  assert.equal(acknowledged, 1);
  assert.deepEqual(f.allocations, []);
  assert.deepEqual(f.opened, []);
  assert.deepEqual(f.reads, []);
  assert.equal(f.closes(), 0);
});

test('metadata cancellation after a positive read does no next read or probe', async () => {
  const abort = new AbortController();
  const reason = new Error('OriginalScopeCancelled');
  const allocations = [];
  let reads = 0, closes = 0, acknowledged = 0;
  const read = load({
    async open() { return {
      async stat() { return state(); },
      async read(bytes) {
        reads++;
        bytes[0] = 97;
        abort.abort(reason);
        return {bytesRead: 1};
      },
      async close() { closes++; },
    }; },
    async lstat() { return state(); },
    Buffer: {allocUnsafeSlow(n) { allocations.push(n); return Buffer.allocUnsafeSlow(n); }},
  });
  await assert.rejects(read('original', 4, () => { acknowledged++; }, abort.signal),
    error => error === reason);
  assert.deepEqual(allocations, [4]);
  assert.equal(reads, 1);
  assert.equal(closes, 1);
  assert.equal(acknowledged, 1);
});

test('metadata growth cannot expand allocation or escape through readFile',
  async () => {
    const f = fixture({content: 'abcdefghi'});
    await assert.rejects(f.read('original', 4), invalid);
    assert.deepEqual(f.allocations, [4, 1]);
    assert.equal(f.reads.at(-1).position, 4);
    assert.equal(f.closes(), 1);
    assert(!body.includes('readFile('));
  });

test('fixed original helper reproduces over-limit growth before the bounded fix',
  async () => {
    // Captured unchanged helper from accepted main ab32290d. Keep the
    // original bytes here so shallow checkouts need no private Git object.
    const original = "async function readBounded(path, maximum) {\n  const state = await lstat(path);\n  if (!state.isFile() || state.size > maximum) {\n    fail('InvalidPublicationStoreObject');\n  }\n  return readFile(path);\n}\n";
    let unboundedReads = 0;
    const previous = runInNewContext(`(${original})`, {
      async lstat() { return {isFile: () => true, size: 4}; },
      async readFile() { unboundedReads++; return Buffer.from('abcdefghi'); },
      fail,
    });
    assert.equal((await previous('original', 4)).length, 9);
    assert.equal(unboundedReads, 1);
    await assert.rejects(fixture({content: 'abcdefghi'}).read('original', 4),
      invalid);
  });

test('oversize, nonregular, changed path and invalid maximum reject before output allocation',
  async () => {
    for (const options of [
      {initial: {size: 5n}}, {initial: {isFile: () => false}},
      {path: {ino: 9n}}, {path: {isFile: () => false}},
    ]) {
      const f = fixture(options);
      await assert.rejects(f.read('original', 4), invalid);
      assert.deepEqual(f.allocations, []);
      assert.equal(f.closes(), 1);
    }
    const f = fixture();
    await assert.rejects(f.read('original', -1), invalid);
    assert.equal(f.opened.length, 0);
  });

test('short read and same-size timestamp mutation never publish partial bytes',
  async () => {
    for (const options of [
      {content: 'ab'}, {after: {mtimeNs: 99n}}, {after: {ctimeNs: 99n}},
    ]) {
      const f = fixture(options);
      await assert.rejects(f.read('original', 4), invalid);
      assert.equal(f.closes(), 1);
    }
  });

test('read failure still awaits close and close failure is never read success',
  async () => {
    const failure = new Error('ReadFailed');
    const f = fixture({readError: failure});
    await assert.rejects(f.read('original', 4), error => error === failure);
    assert.equal(f.closes(), 1);
    const closeFailure = new Error('ClosePending');
    const pending = fixture({closeError: closeFailure});
    await assert.rejects(pending.read('original', 4),
      error => error === closeFailure);
    assert.equal(pending.closes(), 1);
  });

test('real empty and exact-fit files preserve bytes; one-short and symlink refuse',
  async () => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-c-bounded-metadata-'));
    try {
      const path = join(directory, 'metadata');
      const read = load();
      await writeFile(path, Buffer.alloc(0));
      assert.equal((await read(path, 0)).length, 0);
      const bytes = Buffer.from([0, 255, 13, 10]);
      await writeFile(path, bytes);
      assert.deepEqual(await read(path, 4), bytes);
      await assert.rejects(read(path, 3), invalid);
      const {symlink} = await import('node:fs/promises');
      await symlink(path, join(directory, 'alias'));
      await assert.rejects(read(join(directory, 'alias'), 4));
    } finally { await rm(directory, {recursive: true}); }
  });
