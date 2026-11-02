import assert from 'node:assert/strict';
import fs, {mkdtemp, readFile, rm, stat} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {publishStandardRestBarrier} from './cancel-conformance.mjs';

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-rest-marker-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return join(root, 'marker.json');
}

test('REST marker publishes exact complete bytes and removes only its staging name', async t => {
  const path = await fixture(t), body = '{"returned":true,"note":"e\u0301 / 東京"}\n';
  await publishStandardRestBarrier(path, body);
  assert.deepEqual(await readFile(path), Buffer.from(body));
  assert.equal((await stat(path)).nlink, 1);
  await assert.rejects(readFile(path + '.pending'), {code: 'ENOENT'});
});

test('REST marker final-name collision preserves the first bytes and physical original', async t => {
  const path = await fixture(t), first = '{"first":true}\n', second = '{"second":true}\n';
  await publishStandardRestBarrier(path, first);
  const original = await stat(path);
  await assert.rejects(publishStandardRestBarrier(path, second), {code: 'EEXIST'});
  const after = await stat(path);
  assert.deepEqual(await readFile(path), Buffer.from(first));
  assert.deepEqual([after.dev, after.ino, after.mode, after.mtimeMs],
    [original.dev, original.ino, original.mode, original.mtimeMs]);
  assert.deepEqual(await readFile(path + '.pending'), Buffer.from(second));
});

test('REST marker preserves the original write failure without a published name', async t => {
  const path = await fixture(t), originalWrite = fs.writeFile;
  const primary = Object.assign(new Error('synthetic original write failed'), {code: 'EIO'});
  t.mock.method(fs, 'writeFile', (candidate, ...args) => candidate === path + '.pending'
    ? Promise.reject(primary) : originalWrite(candidate, ...args));
  syncBuiltinESMExports();
  try {
    await assert.rejects(publishStandardRestBarrier(path, '{"returned":true}\n'), cause => cause === primary);
    await assert.rejects(readFile(path), {code: 'ENOENT'});
    await assert.rejects(readFile(path + '.pending'), {code: 'ENOENT'});
  } finally {t.mock.restoreAll();syncBuiltinESMExports();}
});
