import assert from 'node:assert/strict';
import {mkdtemp, mkdir, opendir, readFile, readdir, rm, writeFile} from
  'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {admitHostRootFormat} from './host-root-format.mjs';

test('new and current Host roots use one exact marker', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-host-format-'));
  const root = join(parent, 'host');
  try {
    assert.equal(await admitHostRootFormat(root), 'new');
    assert.equal(await admitHostRootFormat(root), 'current');
    assert.deepEqual(await readdir(root), ['host-format.json']);
    assert.deepEqual(JSON.parse(await readFile(join(root,
      'host-format.json'), 'utf8')), {
      version: 'actql-local-host-root/0.1',
      isolation: 'execution-namespace',
    });
  } finally {
    await rm(parent, {recursive: true, force: true});
  }
});

test('unmarked prior state and unknown roots are refused without writes',
  async () => {
    const parent = await mkdtemp(join(tmpdir(), 'actql-host-format-'));
    try {
      for (const [name, code] of [
        ['requests', 'LegacyHostRootFormat'],
        ['unrecognized', 'UnknownHostRootFormat'],
      ]) {
        const root = join(parent, name);
        await mkdir(root);
        const entry = name === 'requests' ? 'requests' : 'other-file';
        const value = Buffer.from(`preserve-${name}`);
        await writeFile(join(root, entry), value);
        const before = await readdir(root);
        await assert.rejects(admitHostRootFormat(root), error =>
          error.code === code && error.root === root);
        assert.deepEqual(await readdir(root), before);
        assert.deepEqual(await readFile(join(root, entry)), value);
      }
    } finally {
      await rm(parent, {recursive: true, force: true});
    }
  });

test('a malformed marker is not reinitialized', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-host-format-'));
  try {
    const root = join(parent, 'host');
    await mkdir(root);
    await writeFile(join(root, 'host-format.json'), 'wrong-format');
    await assert.rejects(admitHostRootFormat(root), error =>
      error.code === 'UnsupportedHostRootFormat');
    assert.equal(await readFile(join(root, 'host-format.json'), 'utf8'),
      'wrong-format');
  } finally {
    await rm(parent, {recursive: true, force: true});
  }
});

test('format selection reads one Dirent and preserves marker/legacy priority without listing all entries', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-host-format-bounded-'));
  const root = join(parent, 'host');
  try {
    await mkdir(root);
    for (let index = 0; index < 128; index++) await writeFile(join(root, 'unknown-' + index), 'original');
    await writeFile(join(root, 'requests'), 'legacy-original');
    let reads = 0, closes = 0;
    const openDirectory = async (path, options) => {
      assert.deepEqual(options, {bufferSize: 1});
      const original = await opendir(path, options), read = original.read, close = original.close;
      original.read = function () { reads++; return Reflect.apply(read, this, []); };
      original.close = function () { closes++; return Reflect.apply(close, this, []); };
      return original;
    };
    await assert.rejects(admitHostRootFormat(root, {openDirectory}), {code: 'LegacyHostRootFormat'});
    assert.equal(reads, 1); assert.equal(closes, 1);
    await writeFile(join(root, 'host-format.json'), JSON.stringify({
      version: 'actql-local-host-root/0.1', isolation: 'execution-namespace'}));
    assert.equal(await admitHostRootFormat(root, {openDirectory}), 'current');
    assert.equal(reads, 2); assert.equal(closes, 2);
    assert.equal(await readFile(join(root, 'requests'), 'utf8'), 'legacy-original');
  } finally { await rm(parent, {recursive: true, force: true}); }
});

test('a pending real Dir close refuses admission and retries only its captured original receiver', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-host-format-dir-close-'));
  const root = join(parent, 'host');
  let pending;
  try {
    await mkdir(root);
    let original, reads = 0, closes = 0;
    const openDirectory = async (path, options) => {
      original = await opendir(path, options);
      const read = original.read, close = original.close;
      original.read = function () { reads++; return Reflect.apply(read, this, []); };
      original.close = function () {
        assert.equal(this, original); closes++;
        if (closes === 1) return false;
        return Reflect.apply(close, this, []);
      };
      return original;
    };
    await assert.rejects(admitHostRootFormat(root, {openDirectory}), cause => {
      pending = cause.cleanupHandle; return cause.cleanupPending === true;
    });
    assert.equal(pending.status().pending, true);
    assert.equal(reads, 1); assert.equal(closes, 1);
    assert.deepEqual(await readdir(root), []);
    original.close = () => { throw new Error('ReplacementMustNotRetireDir'); };
    assert.equal((await pending.retry()).pending, false);
    assert.equal(closes, 2); assert.equal(reads, 1);
    assert.equal(await admitHostRootFormat(root), 'new');
  } finally {
    if (pending?.status().pending) await pending.retry();
    await rm(parent, {recursive: true, force: true});
  }
});

test('an acquired Dir read failure with ENOENT is not absence or permission to create a marker', async () => {
  const parent = await mkdtemp(join(tmpdir(), 'actql-host-format-dir-read-'));
  const root = join(parent, 'host');
  try {
    await mkdir(root);
    const cause = Object.freeze(Object.assign(new Error('OriginalDirRead'), {code: 'ENOENT'}));
    let closes = 0;
    const openDirectory = async (path, options) => {
      const original = await opendir(path, options), close = original.close;
      original.read = () => { throw cause; };
      original.close = function () { closes++; return Reflect.apply(close, this, []); };
      return original;
    };
    await assert.rejects(admitHostRootFormat(root, {openDirectory}), value => value === cause);
    assert.equal(closes, 1); assert.deepEqual(await readdir(root), []);
  } finally { await rm(parent, {recursive: true, force: true}); }
});
