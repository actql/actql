import assert from 'node:assert/strict';
import {mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile}
  from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import test from 'node:test';

// Exercise the actual bounded reader with real files. Only the physical close
// call is faulted in the isolated import tree; no parser or Owner is replaced.
async function readerFixture(t, contents) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-profile-close-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const original = fileURLToPath(new URL('./', import.meta.url));
  const host = join(root, 'adapters', 'host-node');
  await mkdir(host, {recursive: true});
  await symlink(fileURLToPath(new URL('../host-common', import.meta.url)),
    join(root, 'adapters', 'host-common'));
  await symlink(fileURLToPath(new URL('../connectors', import.meta.url)),
    join(root, 'adapters', 'connectors'));
  await symlink(fileURLToPath(new URL('../connectors-builtin', import.meta.url)),
    join(root, 'adapters', 'connectors-builtin'));
  for (const entry of await readdir(original, {withFileTypes: true})) {
    if (entry.isFile() && entry.name.endsWith('.mjs') &&
        entry.name !== 'installed-effect.mjs') {
      await symlink(join(original, entry.name), join(host, entry.name));
    }
  }
  const source = await readFile(join(original, 'installed-effect.mjs'), 'utf8');
  const importLine = "import {open, readFile} from 'node:fs/promises';";
  assert.equal(source.split(importLine).length, 2);
  await writeFile(join(host, 'installed-effect.mjs'), source.replace(importLine,
    "import {open, readFile} from './profile-close-io.fixture.mjs';"));
  await writeFile(join(host, 'profile-close-io.fixture.mjs'), `
    import {open as physicalOpen} from 'node:fs/promises';
    export {readFile} from 'node:fs/promises';
    export const state = {remaining: 2, calls: 0, released: 0};
    export const closeFailure = new Error('InjectedProfileCloseFailure');
    export async function open(...args) {
      const file = await physicalOpen(...args);
      return {read: (...values) => file.read(...values), async close() {
        state.calls++;
        if (state.remaining > 0) { state.remaining--; throw closeFailure; }
        await file.close(); state.released++;
      }};
    }
  `);
  const path = join(root, 'profile.json');
  await writeFile(path, contents);
  const loader = await import(pathToFileURL(join(host, 'installed-effect.mjs')).href);
  const io = await import(pathToFileURL(join(host, 'profile-close-io.fixture.mjs')).href);
  return {loader, io, path};
}

for (const malformed of [false, true]) {
  test(`Effect profile close failure retains retry custody after ${malformed ? 'parse refusal' : 'successful read'}`, async t => {
    const {loader, io, path} = await readerFixture(t, malformed ? '{' : '{}');
    let failure;
    await assert.rejects(loader.loadInstalledEffect(path, {}), error => {
      failure = error;
      assert.equal(error.code, 'InvalidInstalledEffectProfile');
      assert.equal(error.cleanupPending, true);
      assert.equal(error.cleanupHandle.status().pending, true);
      if (malformed) assert.equal(error.primaryFailure.name, 'SyntaxError');
      else assert.equal(error.primaryFailure, io.closeFailure);
      return true;
    });
    assert.equal(io.state.released, 0);
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(io.state.released, 1);
    const calls = io.state.calls;
    await failure.cleanupHandle.retry();
    assert.equal(io.state.calls, calls, 'successful release is never repeated');
  });
}
