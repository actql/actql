// Read-only original input capture shared by the existing native producers.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants, closeSync, fstatSync, lstatSync, openSync, readSync, realpathSync} from 'node:fs';
import {dirname} from 'node:path';

export function original(path: string, maximum: number, capture = false) {
  assert.equal(realpathSync(dirname(path)), dirname(path), `Original parent required: ${path}`);
  const before = lstatSync(path);
  assert(before.isFile() && !before.isSymbolicLink() && before.size > 0 && before.size <= maximum,
    `Invalid original input: ${path}`);
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const opened = fstatSync(fd), hash = createHash('sha256'), chunks = [];
    assert.equal(opened.dev, before.dev); assert.equal(opened.ino, before.ino); assert.equal(opened.size, before.size);
    const buffer = Buffer.alloc(65536);
    let bytes = 0, count;
    while ((count = readSync(fd, buffer, 0, Math.min(buffer.length, opened.size + 1 - bytes), null)) > 0) {
      bytes += count; assert(bytes <= opened.size, `Original grew: ${path}`);
      hash.update(buffer.subarray(0, count));
      if (capture) chunks.push(Buffer.from(buffer.subarray(0, count)));
    }
    assert.equal(bytes, opened.size);
    const after = fstatSync(fd), named = lstatSync(path);
    for (const key of ['dev', 'ino', 'size', 'mtimeMs', 'ctimeMs'] as const) {
      assert.equal(after[key], opened[key]); assert.equal(named[key], opened[key]);
    }
    assert(named.isFile() && !named.isSymbolicLink());
    return {identity: {bytes, sha256: hash.digest('hex')}, ...(capture ? {raw: Buffer.concat(chunks)} : {})};
  } finally {closeSync(fd);}
}

type HeaderReceipt = {stage?: {outputs?: {'sqlite3.h'?: unknown}}};
type HeaderRecipe = {upstream?: {members?: {'sqlite3.h'?: {bytes: unknown; sha256: unknown}}}};

export function requireNativeLocalHeader(bytes: Uint8Array, sqlite: HeaderReceipt, sourceRecipe: HeaderRecipe) {
  const selected = {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')};
  const pin = sourceRecipe.upstream?.members?.['sqlite3.h'];
  assert(pin, 'Original SQLite header pin required');
  assert.deepEqual(selected, {bytes: pin.bytes, sha256: pin.sha256}, 'Original SQLite header mismatch');
  assert.deepEqual(sqlite.stage?.outputs?.['sqlite3.h'], selected, 'Staged SQLite header receipt mismatch');
  return selected;
}

