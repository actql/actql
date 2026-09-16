import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rmdir, readFile, writeFile, rename, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createLocalRetainedStore} from './files.mjs';
import {withVerifiedDelegatedFile} from './direct-file.mjs';

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-direct-file-'));
  const store = await createLocalRetainedStore({parentDirectory: directory, capacityBytes: 100, maxFrameBytes: 4});
  const writer = store.reserve(100);
  await writer.start(); await writer.append('[1]');
  const body = await writer.seal({bytes: 3, cid: `sha256:${createHash('sha256').update('[1]').digest('hex')}`});
  const borrow = body.delegateRead('owned-session');
  t.after(async () => { borrow.confirmStopped(); store.close(); await store.cleanup(); await rmdir(directory); });
  return {store, body, borrow};
}

test('direct access retains the exact borrow until callback and verified receipt settle', async t => {
  const {body, borrow} = await fixture(t);
  const result = await withVerifiedDelegatedFile(borrow.descriptor, async file => {
    assert.equal(await readFile(file.path, 'utf8'), '[1]');
    assert.equal(file.bytes, 3);
    assert.throws(() => body.delegateRead('another-session'), {code: 'StoreReaderBusy'});
    return 'provisional-result';
  });
  assert.equal(result.value, 'provisional-result');
  assert.equal(borrow.finish(result.report).cid, body.cid);
});

test('corrupt bytes are refused before native access', async t => {
  const {borrow} = await fixture(t);
  await writeFile(borrow.descriptor.path, '[2]');
  let called = false;
  await assert.rejects(withVerifiedDelegatedFile(borrow.descriptor, () => { called = true; }),
    {code: 'RetainedBodyChanged'});
  assert.equal(called, false);
});

test('physical read admission rejects before opening or hashing the file', async t => {
  const {borrow} = await fixture(t);
  const rejected = Error('transfer budget exceeded');
  let calls = 0, native = false;
  // A nonexistent path would fail with ENOENT if physical I/O started first.
  await assert.rejects(withVerifiedDelegatedFile({...borrow.descriptor,
    path: borrow.descriptor.path + '-missing'}, () => { native = true; }, undefined,
  bytes => { calls++; assert.equal(bytes, 3); throw rejected; }), error => error === rejected);
  assert.equal(calls, 1);
  assert.equal(native, false);
  const result = await withVerifiedDelegatedFile(borrow.descriptor, () => {
    assert.equal(calls, 2); return 'admitted';
  }, undefined, bytes => { calls++; assert.equal(bytes, 3); });
  assert.equal(result.value, 'admitted');
});

test('mutation during native use cannot return a successful receipt', async t => {
  const {borrow} = await fixture(t);
  await assert.rejects(withVerifiedDelegatedFile(borrow.descriptor, async file => {
    await writeFile(file.path, '[2]');
    return true;
  }), {code: 'RetainedBodyChanged'});
});

test('same-size pathname replacement is refused and the original remains owned', async t => {
  const {borrow} = await fixture(t);
  const path = borrow.descriptor.path, moved = path + '-original';
  try {
    await assert.rejects(withVerifiedDelegatedFile(borrow.descriptor, async () => {
      await rename(path, moved); await writeFile(path, '[1]');
    }), {code: 'ForeignStoreFile'});
  } finally { await unlink(path); await rename(moved, path); }
});

test('cancellation and callback failure cannot be turned into success', async t => {
  const {borrow} = await fixture(t);
  const controller = new AbortController();
  const reason = Error('cancelled');
  await assert.rejects(withVerifiedDelegatedFile(borrow.descriptor, () => {
    controller.abort(reason);
    return true;
  }, controller.signal), error => error === reason);
  const failure = Error('native execution failed');
  await assert.rejects(withVerifiedDelegatedFile(borrow.descriptor, () => { throw failure; }),
    error => error === failure);
});
