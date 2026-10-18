import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {installedRuntimeBundleCid, readBoundedConfigurationText,
  readBoundedConfigurationUtf8} from './source-profile-json.mjs';

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-original-file-close-'));
  const path = join(directory, 'source.txt'), text = 'original 雪\n';
  await writeFile(path, text);
  const file = await open(path, 'r');
  const physicalClose = file.close;
  // Even a failed ownership counter closes its own real FD before removing
  // disposable input. This is fixture cleanup, not the product's close ACK.
  t.after(async () => {
    await Reflect.apply(physicalClose, file, []);
    await rm(directory, {recursive: true, force: true});
  });
  const counts = {opens: 0, reads: 0, originalClose: 0, replacementClose: 0};
  const handle = {
    async read(...args) { counts.reads++; return file.read(...args); },
    async close() {
      assert.equal(this, handle); counts.originalClose++;
      await Reflect.apply(physicalClose, file, []);
    },
  };
  const openFile = async (name, flags) => {
    assert.equal(name, path); assert.equal(flags, 'r'); counts.opens++;
    return handle;
  };
  return {path, text, file, physicalClose, handle, counts, openFile};
}

for (const kind of ['configuration', 'runtime']) {
  test(`${kind} read captures original close before its first awaited read`, async t => {
    const f = await fixture(t);
    let entered, release;
    const reading = new Promise(resolve => { entered = resolve; });
    const pending = new Promise(resolve => { release = resolve; });
    f.handle.read = async (...args) => {
      f.counts.reads++;
      if (f.counts.reads === 1) { entered(); await pending; }
      return f.file.read(...args);
    };
    const result = kind === 'runtime'
      ? installedRuntimeBundleCid(f.path, {openFile: f.openFile})
      : readBoundedConfigurationText(f.path, {maxBytes: 128, openFile: f.openFile});
    await reading;
    f.handle.close = async function() {
      assert.equal(this, f.handle); f.counts.replacementClose++;
    };
    release();
    assert.equal(await result, kind === 'runtime'
      ? `sha256:${createHash('sha256').update(f.text).digest('hex')}` : f.text);
    assert.equal(f.counts.originalClose, 1);
    assert.equal(f.counts.replacementClose, 0);
    assert.equal(f.counts.opens, 1);
    await assert.rejects(f.file.stat(), {code: 'EBADF'});
  });
}

test('close-only retry retains the same original method and cannot acknowledge its replacement', async t => {
  const f = await fixture(t);
  let pending = true, failure;
  f.handle.close = async function() {
    assert.equal(this, f.handle); f.counts.originalClose++;
    if (pending) return false;
    await Reflect.apply(f.physicalClose, f.file, []);
  };
  await assert.rejects(installedRuntimeBundleCid(f.path, {openFile: f.openFile}), error => {
    failure = error; return error.cleanupHandle.status().pending === true;
  });
  const reads = f.counts.reads;
  f.handle.close = async () => { f.counts.replacementClose++; };
  await assert.rejects(failure.cleanupHandle.retry(), {message: 'InstalledSourceProfileCleanupPending'});
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(f.counts.originalClose, 2);
  assert.equal(f.counts.replacementClose, 0);
  assert.equal((await f.file.stat()).isFile(), true);
  pending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(f.counts.originalClose, 3);
  assert.equal(f.counts.reads, reads);
  assert.equal(f.counts.opens, 1);
  await assert.rejects(f.file.stat(), {code: 'EBADF'});
});

test('unobserved close getter failure retains the FD without beginning intake and retries observation once', async t => {
  const f = await fixture(t), cause = new Error('original close getter');
  let gets = 0, pending = true, failure;
  Object.defineProperty(f.handle, 'close', {configurable: true, get() {
    gets++;
    if (gets === 1) throw cause;
    return async function() {
      assert.equal(this, f.handle); f.counts.originalClose++;
      if (pending) return false;
      await Reflect.apply(f.physicalClose, f.file, []);
    };
  }});
  await assert.rejects(readBoundedConfigurationUtf8(f.path, {maxBytes: 128, openFile: f.openFile}), error => {
    failure = error; return error.cleanupHandle.primaryFailure === cause;
  });
  assert.equal(gets, 1);
  assert.equal(f.counts.reads, 0);
  assert.equal(failure.cleanupHandle.status().pending, true);
  await assert.rejects(failure.cleanupHandle.retry(), {message: 'InstalledSourceProfileCleanupPending'});
  assert.equal(gets, 2);
  assert.equal(f.counts.originalClose, 1);
  // Only a failed observation may be retried. Successful capture cannot later
  // switch to another getter result, even while physical close stays pending.
  Object.defineProperty(f.handle, 'close', {get() { throw new Error('replacement getter'); }});
  pending = false;
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(gets, 2);
  assert.equal(f.counts.originalClose, 2);
  assert.equal(f.counts.reads, 0);
  await assert.rejects(f.file.stat(), {code: 'EBADF'});
});
