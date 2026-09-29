import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, readdir, rm, writeFile} from
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
