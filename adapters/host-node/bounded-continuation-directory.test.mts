import assert from 'node:assert/strict';
import {mkdtemp, opendir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {listContinuationLedgerNamesBounded} from './bounded-continuation-directory.mjs';
import type {TestContext} from 'node:test';

// Test views over the SAME actual Dir prototype and original thrown carrier.
interface TestDirectory {
  path: string | Buffer;
  read(this: TestDirectory, ...args: unknown[]): Promise<unknown>;
  close(this: TestDirectory, ...args: unknown[]): Promise<unknown>;
}
interface CleanupFailure {
  code?: unknown; cause?: unknown; cleanupError?: unknown;
  cleanupHandle: {status(): Readonly<{pending: boolean}>; retry(): Promise<Readonly<{pending: boolean}>>};
}


async function fixture(t: TestContext) {
  const path = await mkdtemp(join(tmpdir(), 'actql-c-bounded-ledger-directory-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  return path;
}
const source = await readFile(new URL('./bounded-continuation-directory.mjs', import.meta.url), 'utf8');
const body = source.slice(source.indexOf('export async function ')).replace('export async', 'async');
function synthetic(entries: readonly {name: Uint8Array}[], options: {onRead?: (reads: number) => void} = {}) {
  let opens = 0, reads = 0, closes = 0;
  const fn = runInNewContext(`(${body})`, {
    Uint8Array, TextDecoder, AbortSignal,
    count: (n: number) => Number.isSafeInteger(n) && n >= 0,
    fail: (code: string) => { throw Object.assign(new Error(code), {code}); },
    async opendir(_path: string, selected: {encoding: string; bufferSize: number}) {
      opens++;
      assert.deepEqual({...selected}, {encoding: 'buffer', bufferSize: 1});
      return {
        async read() {
          reads++;
          options.onRead?.(reads);
          return entries[reads - 1] ?? null;
        },
        async close() { closes++; },
      };
    },
  }) as typeof listContinuationLedgerNamesBounded;
  return {fn, counts: () => ({opens, reads, closes})};
}

test('bounded ledger directory real empty and exact count/name bytes preserve sorted existing names', async t => {
  const path = await fixture(t);
  assert.deepEqual(await listContinuationLedgerNamesBounded(path,
    {maxDirectoryEntries: 0, maxWireBytes: 0}), []);
  for (const name of ['z.json', 'a.json', 'ignore.tmp']) await writeFile(join(path, name), '');
  // Independent ASCII names: 6 + 6 + 10 = 22 bytes, ALL three entries count.
  assert.deepEqual(await listContinuationLedgerNamesBounded(path,
    {maxDirectoryEntries: 3, maxWireBytes: 22}), ['a', 'z']);
  await assert.rejects(listContinuationLedgerNamesBounded(path,
    {maxDirectoryEntries: 2, maxWireBytes: 22}), {code: 'ContinuationDirectoryEntriesLimit'});
  await assert.rejects(listContinuationLedgerNamesBounded(path,
    {maxDirectoryEntries: 3, maxWireBytes: 21}), {code: 'ContinuationDirectoryWireLimit'});
});

test('bounded ledger directory missing/invalid limits and pre-abort perform zero open', async () => {
  const f = synthetic([]);
  for (const limits of [undefined, {}, {maxDirectoryEntries: 1},
    {maxDirectoryEntries: -1, maxWireBytes: 20}, {maxDirectoryEntries: 1, maxWireBytes: Infinity},
    {maxDirectoryEntries: 1, maxWireBytes: 20, grant: true}]) {
    await assert.rejects(f.fn('original', limits), {code: 'InvalidContinuationDirectoryBounds'});
  }
  const abort = new AbortController(), reason = new Error('OriginalCancelled');
  abort.abort(reason);
  await assert.rejects(f.fn('original', {maxDirectoryEntries: 1, maxWireBytes: 20}, abort.signal),
    error => error === reason);
  assert.deepEqual(f.counts(), {opens: 0, reads: 0, closes: 0});
});

test('bounded ledger directory excess ignored entry and cancellation stop before the next read', async () => {
  const entries = ['not-a-ledger', 'a.json', 'b.json'].map(name => ({name: Buffer.from(name)}));
  const f = synthetic(entries);
  await assert.rejects(f.fn('original', {maxDirectoryEntries: 1, maxWireBytes: 40}),
    {code: 'ContinuationDirectoryEntriesLimit'});
  assert.deepEqual(f.counts(), {opens: 1, reads: 2, closes: 1});
  const abort = new AbortController(), reason = new Error('OriginalCancelled');
  const stopped = synthetic(entries, {onRead: () => abort.abort(reason)});
  await assert.rejects(stopped.fn('original', {maxDirectoryEntries: 3, maxWireBytes: 40}, abort.signal),
    error => error === reason);
  assert.deepEqual(stopped.counts(), {opens: 1, reads: 1, closes: 1});
});

test('bounded ledger directory strict names reject malformed UTF8 and missing directory is unavailable', async t => {
  const f = synthetic([{name: Buffer.from([0xff])}]);
  await assert.rejects(f.fn('original', {maxDirectoryEntries: 1, maxWireBytes: 1}),
    {code: 'InvalidContinuationDirectoryName'});
  assert.deepEqual(f.counts(), {opens: 1, reads: 1, closes: 1});
  const path = await fixture(t);
  await assert.rejects(listContinuationLedgerNamesBounded(join(path, 'missing'),
    {maxDirectoryEntries: 0, maxWireBytes: 0}), error =>
    (error as {code: unknown}).code === 'ContinuationDirectoryUnavailable' && (error as {cause: {code: unknown}}).cause.code === 'ENOENT');
});

test('bounded ledger directory actual cancellation plus failed close retains original Dir single-flight', async t => {
  const path = await fixture(t);
  await writeFile(join(path, 'a.json'), '');
  const probe = await opendir(path);
  const prototype = Object.getPrototypeOf(probe) as TestDirectory, read = prototype.read, close = prototype.close;
  await probe.close();
  const abort = new AbortController(), reason = Object.freeze(new Error('OriginalCancelled'));
  const closeFailure = new Error('OriginalDirClosePending');
  let original: TestDirectory | undefined, failure: CleanupFailure | undefined, reads = 0, closes = 0, rejectClose = true;
  t.after(async () => {
    prototype.read = read;
    prototype.close = close;
    rejectClose = false;
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
    else if (original) await Reflect.apply(close, original, []).catch(() => {});
  });
  prototype.read = async function(this: TestDirectory, ...args: unknown[]) {
    if (this.path !== path) return Reflect.apply(read, this, args);
    original = this;
    reads++;
    const value = await Reflect.apply(read, this, args);
    abort.abort(reason);
    return value;
  };
  prototype.close = function(this: TestDirectory, ...args: unknown[]) {
    // Dir.close() uses its callback overload internally when making a Promise.
    // Observe outer close requests once, not that internal callback dispatch.
    if (typeof args[0] === 'function') return Reflect.apply(close, this, args);
    if (this.path !== path) return Reflect.apply(close, this, args);
    closes++;
    if (rejectClose) return Promise.reject(closeFailure);
    return Reflect.apply(close, this, args);
  };
  await assert.rejects(listContinuationLedgerNamesBounded(path,
    {maxDirectoryEntries: 1, maxWireBytes: 6}, abort.signal), error => {
    failure = error as CleanupFailure;
    return (error as CleanupFailure).cause === reason && (error as CleanupFailure).cleanupError === closeFailure;
  });
  assert.equal(reads, 1);
  assert.equal(closes, 1);
  const cleanup = failure!.cleanupHandle;
  const flight = cleanup.retry();
  assert.strictEqual(cleanup.retry(), flight);
  await assert.rejects(flight, error => error === closeFailure);
  assert.equal(cleanup.status().pending, true);
  rejectClose = false;
  assert.equal((await cleanup.retry()).pending, false);
  await cleanup.retry();
  assert.equal(reads, 1);
  assert.equal(closes, 3);
});
