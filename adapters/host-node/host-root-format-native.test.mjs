import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createHostJournalDirectoryInspector} from './host-journal-directory.mjs';
import {admitHostRootFormat} from './host-root-format.mjs';

async function fixture({outcome = 'closed', current} = {}) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'host-root-native-first-', label: 'selected Host root first-entry custody'});
  const root = join(scratch.path, 'host');
  let names = [], opens = 0, reads = 0, closes = 0, offset = 0;
  const original = {};
  const native = {
    open(path, entries, nameBytes, work) {
      assert.equal(path, root); assert.equal(entries, 1);
      assert.equal(nameBytes, 1024); assert.equal(work, 4096);
      opens++; offset = 0; return original;
    },
    next(handle) {
      assert.strictEqual(handle, original); reads++;
      assert.ok(offset < 1, 'Format admission must not list beyond its first entry');
      return names.length === 0 ? null : Buffer.from(names[offset++]);
    },
    current(handle) { assert.strictEqual(handle, original); current?.(); },
    close(handle) { assert.strictEqual(handle, original); closes++; return {outcome}; },
  };
  const directoryInspection = createHostJournalDirectoryInspector(native,
    {maxEntries: 1, maxNameBytes: 1024, maxWork: 4096, maxInspections: 2}, () => {});
  return {scratch, root, directoryInspection,
    options: {directoryInspection, openDirectory() { assert.fail('Selected route must not open stock Dir'); }},
    names(value) { names = value; }, counts: () => ({opens, reads, closes})};
}

// Real fresh marker/FS with explicit native-operation/current fixtures. No
// operational disposition, physical native close or whole Host is supplied.
test('selected Root format uses one nominal native entry rather than stock Dir', async () => {
  const f = await fixture();
  assert.equal(await admitHostRootFormat(f.root, f.options), 'new');
  f.names(['host-format.json', 'must-not-list']);
  assert.equal(await admitHostRootFormat(f.root, f.options), 'current');
  assert.deepEqual(f.counts(), {opens: 2, reads: 2, closes: 2});
  assert.deepEqual(await fs.readdir(f.root), ['host-format.json']);
  f.scratch.passed();
});

test('selected format refuses a foreign first-entry function before filesystem acquisition', async () => {
  const f = await fixture();
  let traps = 0;
  await assert.rejects(admitHostRootFormat(f.root,
    {directoryInspection() { traps++; }, openDirectory() { traps++; assert.fail(); }}),
  {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(traps, 0);
  await assert.rejects(fs.lstat(f.root), {code: 'ENOENT'});
  f.scratch.passed();
});

test('selected marker and legacy priority do not depend on listing the remaining names', async () => {
  const f = await fixture();
  await fs.mkdir(f.root);
  await fs.writeFile(join(f.root, 'requests'), 'unchanged legacy bytes');
  f.names(['unknown-first', 'requests', 'must-not-list']);
  await assert.rejects(admitHostRootFormat(f.root, f.options), {code: 'LegacyHostRootFormat'});
  await fs.writeFile(join(f.root, 'host-format.json'),
    '{"version":"actql-local-host-root/0.1","isolation":"execution-namespace"}');
  assert.equal(await admitHostRootFormat(f.root, f.options), 'current');
  assert.deepEqual(f.counts(), {opens: 2, reads: 2, closes: 2});
  assert.equal(await fs.readFile(join(f.root, 'requests'), 'utf8'), 'unchanged legacy bytes');
  f.scratch.passed();
});

test('selected emptiness does not decode unrelated name bytes before marker precedence', async () => {
  const f = await fixture();
  await fs.mkdir(f.root);
  await fs.writeFile(join(f.root, 'host-format.json'),
    '{"version":"actql-local-host-root/0.1","isolation":"execution-namespace"}');
  f.names([Buffer.from([0xff]), 'must-not-list']);
  assert.equal(await admitHostRootFormat(f.root, f.options), 'current');
  assert.deepEqual(f.counts(), {opens: 1, reads: 1, closes: 1});
  f.scratch.passed();
});

test('selected first-entry close Unknown prevents marker creation and is observation-only', async () => {
  const f = await fixture({outcome: 'unknown'});
  await fs.mkdir(f.root);
  let failure;
  await assert.rejects(admitHostRootFormat(f.root, f.options), error => {
    failure = error; return error.code === 'HostJournalDirectoryCleanupPending';
  });
  assert.equal(failure.cleanupHandle.retry().pending, true);
  assert.equal(failure.cleanupHandle.retry().pending, true);
  assert.deepEqual(f.counts(), {opens: 1, reads: 1, closes: 1});
  assert.deepEqual(await fs.readdir(f.root), []);
  f.scratch.passed();
});
