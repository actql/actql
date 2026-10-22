import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {prepareLocalPublicationStoreOwnership, closePreparedLocalPublicationStoreOwnership}
  from './publication-store.mjs';

async function fixture() {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'ownership-retirement-read-', label: 'same original bounded ownership retirement read'});
  const directory = join(scratch.path, 'publication');
  const original = await prepareLocalPublicationStoreOwnership(directory,
    {maxWireBytes: 16384, maxDirectoryEntries: 64});
  const path = join(directory, 'owner', 'owner.json');
  return {scratch, directory, original, path, wire: await fs.readFile(path)};
}

// Fresh real ownership and FS. Bounds/currentness are explicit diagnostic
// conditions, not a selected operational Root or business permission.
test('selected ownership retirement never returns to unbounded readFile', async () => {
  const f = await fixture(), readFile = fs.readFile;
  let unbounded = 0;
  fs.readFile = async function(path, ...args) {
    if (path === f.path) { unbounded++; throw Error('UnboundedOwnerReadMustNotRun'); }
    return Reflect.apply(readFile, this, [path, ...args]);
  };
  syncBuiltinESMExports();
  try {
    assert.equal((await closePreparedLocalPublicationStoreOwnership(f.original)).pending, false);
    assert.equal(unbounded, 0);
  } finally {
    fs.readFile = readFile; syncBuiltinESMExports();
    await closePreparedLocalPublicationStoreOwnership(f.original);
  }
  f.scratch.passed();
});

test('oversized selected owner refuses before payload allocation and preserves exclusion', async () => {
  const f = await fixture();
  await fs.writeFile(f.path, JSON.stringify({...JSON.parse(f.wire), padding: 'x'.repeat(8192)}));
  try {
    await assert.rejects(closePreparedLocalPublicationStoreOwnership(f.original),
      {code: 'InvalidPublicationStoreObject'});
    assert.ok((await fs.stat(f.path)).size > 4096);
  } finally {
    // Restore only this test's recorded original after a refusal. A removed
    // original is not reconstructed if the old product wrongly released it.
    try {
      await fs.stat(f.path);
      await fs.writeFile(f.path, f.wire);
    } catch (cause) { if (cause.code !== 'ENOENT') throw cause; }
    await closePreparedLocalPublicationStoreOwnership(f.original);
  }
  f.scratch.passed();
});

test('retirement retains the same failed metadata close before another read or owner removal', async () => {
  const f = await fixture(), open = fs.open;
  const cause = new Error('OriginalRetirementReadClosePending');
  let original, allowClose = false, opens = 0, closes = 0, replacements = 0;
  fs.open = async function(path, ...args) {
    const handle = await Reflect.apply(open, this, [path, ...args]);
    if (path !== f.path) return handle;
    opens++;
    if (original !== undefined) return handle;
    original = handle;
    const close = handle.close;
    handle.close = async function() {
      assert.strictEqual(this, original); closes++;
      if (!allowClose) throw cause;
      return Reflect.apply(close, this, []);
    };
    return handle;
  };
  syncBuiltinESMExports();
  try {
    await assert.rejects(closePreparedLocalPublicationStoreOwnership(f.original), error => error === cause);
    assert.equal(opens, 1); assert.equal(closes, 1);
    await original.stat();
    original.close = async () => { replacements++; };
    await assert.rejects(closePreparedLocalPublicationStoreOwnership(f.original), error => error === cause);
    assert.equal(opens, 1); assert.equal(closes, 2); assert.equal(replacements, 0);
    assert.deepEqual(await fs.readFile(f.path), f.wire);
    allowClose = true;
    assert.equal((await closePreparedLocalPublicationStoreOwnership(f.original)).pending, false);
    await assert.rejects(original.stat(), {code: 'EBADF'});
    assert.equal(opens, 2); assert.equal(closes, 3); assert.equal(replacements, 0);
  } finally {
    allowClose = true; fs.open = open; syncBuiltinESMExports();
    await closePreparedLocalPublicationStoreOwnership(f.original);
  }
  f.scratch.passed();
});
