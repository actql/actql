// Formal staging metadata only. No package build, installer, Native witness or
// authority acquisition occurs in these functions.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {chmod, lstat, open, opendir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {inventory} from './package-release.mjs';
import {PRODUCT_MEMBERS_FILE, productMembersBody, readProductMembers,
  productMembersCensus} from '../packages/native-cli/lib/product-members.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');

const same = (a, b) => a.dev === b.dev && a.ino === b.ino && a.size === b.size &&
  a.mode === b.mode && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs;

// Only bounded producer/verification scratch is observed here. This does not
// retain an OriginalRoot or substitute for Native generation/current fences.
async function observeMember(directory, item, collect = false) {
  const path = join(directory, item.path), before = await lstat(path);
  assert(before.isFile() && !before.isSymbolicLink() && before.size === item.bytes &&
    (before.mode & 0o7777) === item.mode);
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const opened = await file.stat(); assert(same(before, opened));
    const hasher = createHash('sha256'), chunk = Buffer.alloc(65536);
    const body = collect ? Buffer.alloc(item.bytes) : undefined;
    let count = 0;
    while (true) {
      const {bytesRead} = await file.read(chunk, 0, chunk.length, null);
      if (bytesRead === 0) break;
      assert(count + bytesRead <= item.bytes);
      hasher.update(chunk.subarray(0, bytesRead));
      if (collect) chunk.copy(body, count, 0, bytesRead);
      count += bytesRead;
    }
    assert.equal(count, item.bytes);
    assert.equal(hasher.digest('hex'), item.sha256);
    assert(same(opened, await file.stat()) && same(opened, await lstat(path)));
    return body;
  } finally {
    // No result is returned if this same handle's close is unconfirmed.
    await file.close();
  }
}

async function stageCensus(directory, census) {
  for (const selected of census) {
    const path = join(directory, selected.path), before = await lstat(path);
    assert(before.isDirectory() && !before.isSymbolicLink());
    const expected = new Map(selected.entries.map(v => [v.name, v.kind]));
    const seen = new Set();
    const stream = await opendir(path, {bufferSize: 1});
    try {
      while (true) {
        const entry = await stream.read(); if (entry === null) break;
        const kind = expected.get(entry.name);
        assert(kind !== undefined && !seen.has(entry.name));
        const stat = await lstat(join(path, entry.name));
        assert(!stat.isSymbolicLink() && (kind === 'file' ? stat.isFile() : stat.isDirectory()));
        seen.add(entry.name);
      }
      assert.equal(seen.size, expected.size);
      assert(same(before, await lstat(path)));
    } finally {await stream.close();}
  }
}

// Called on the producer's own complete, private stage before ordinary pack.
// Its original formal inventory is unchanged; only the one descriptor is added.
export async function stageProductMembers(directory, selected) {
  const files = await inventory(directory);
  const body = productMembersBody({...selected, files});
  // Detect file/directory conflicts before writing the new private descriptor.
  productMembersCensus({...selected, files});
  await writeFile(join(directory, PRODUCT_MEMBERS_FILE), body, {flag: 'wx', mode: 0o644});
  await chmod(join(directory, PRODUCT_MEMBERS_FILE), 0o644);
  const metadata = {path: PRODUCT_MEMBERS_FILE, bytes: Buffer.byteLength(body), sha256: digest(body)};
  await verifyStagedProductMembers(directory, selected, metadata);
  return metadata;
}

// The existing formal release verifier owns the extracted stage. A successful
// comparison is package verification, not an opaque Native OriginalRoot fact.
export async function verifyStagedProductMembers(directory, selected, metadata) {
  assert(metadata && typeof metadata === 'object' && !Array.isArray(metadata));
  assert.deepEqual(Object.keys(metadata).sort(), ['bytes', 'path', 'sha256']);
  assert.equal(metadata.path, PRODUCT_MEMBERS_FILE);
  assert(Number.isSafeInteger(metadata.bytes) && metadata.bytes > 0 && metadata.bytes <= 65536);
  assert.match(metadata.sha256, /^[a-f0-9]{64}$/u);
  const bytes = await observeMember(directory, {...metadata, mode: 0o644}, true);
  const value = readProductMembers(bytes.toString('utf8'), selected);
  await stageCensus(directory, productMembersCensus(value));
  for (const item of value.files) await observeMember(directory, item);
  return value;
}

// Current finite Local acceptance has one selected platform. Preserve ordinary
// multi-platform Remote packaging rather than invent a platform wildcard or a
// cyclic set of launcher descriptors. Multiple Local profiles have no complete
// launcher witness until a separate exact format is admitted and verified.
export function launcherMemberPlatform(records) {
  if (records.length === 1) return records[0].platform;
  const local = records.filter(v => v.localRuntime !== undefined);
  return local.length === 1 ? local[0].platform : undefined;
}
