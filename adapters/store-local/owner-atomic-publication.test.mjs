// Actual private binding and disposable local Store. Resource/contract ports
// remain explicit fixtures; this is not installed Host or execution admission.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports, createRequire} from 'node:module';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {buildNodeDirectoryNative} from '../../scripts/build-node-directory-native.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore, prepareLocalPublicationStoreOwnership,
  closePreparedLocalPublicationStoreOwnership} from './publication-store.mjs';

test.before(() => buildNodeDirectoryNative());
const configuration = directory => ({directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
  capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
  maxContractNodes: 256, maxContractDepth: 32});
for (const mode of ['empty', 'partial', 'lease']) {
  test(`interrupted ${mode} owner publication never exposes incomplete final metadata`, async () => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'owner-atomic-', label: 'new disposable Store owner interruption'});
    const directory = join(scratch.path, 'store');
    if (mode !== 'lease') {
      const initial = await openLocalPublicationStore(configuration(directory), createPublicationContractControlFixture());
      await initial.close();
    }
    const child = spawn(process.execPath, [fileURLToPath(new URL('./fixtures/owner-interrupted.fixture.mjs', import.meta.url)),
      directory, mode], {stdio: ['ignore', 'pipe', 'pipe']});
    const stdout = [], stderr = [];
    child.stdout.on('data', bytes => stdout.push(bytes)); child.stderr.on('data', bytes => stderr.push(bytes));
    const [code, signal] = await once(child, 'close');
    assert.equal(code, null, Buffer.concat(stderr).toString()); assert.equal(signal, 'SIGKILL');
    const observation = JSON.parse(Buffer.concat(stdout).toString());
    assert.equal(observation.boundary, 'owner-write');
    assert.equal((await fs.readFile(observation.path)).length, observation.bytes);
    const reopened = await openLocalPublicationStore(configuration(directory), createPublicationContractControlFixture());
    try {
      assert.equal(reopened.status().closed, false);
      assert.equal((await fs.readdir(directory)).some(name => name.startsWith('.owner-opening-')), false);
    } finally {await reopened.close();}
    scratch.passed();
  });
}

for (const mode of ['false', 'throw']) {
  test(`unpublished owner retains its same ${mode}-close writer and excludes a successor`, async t => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'owner-close-', label: 'actual pending owner writer'});
    const directory = join(scratch.path, 'store'), originalOpen = fs.open;
    const primary = Object.assign(new Error('OriginalOwnerClosePending'), {code: 'EIO'});
    let permitted = false, writer, writes = 0, failure;
    fs.open = async (...args) => {
      const handle = await originalOpen(...args), write = handle.write.bind(handle), close = handle.close.bind(handle);
      handle.write = async (...values) => {
        if (Buffer.isBuffer(values[0]) && values[0].toString().includes('actql-local-publication-store-owner/0.1')) {
          writer = handle; writes++;
        }
        return write(...values);
      };
      handle.close = async () => {
        if (handle === writer && !permitted) {
          if (mode === 'false') return false;
          throw primary;
        }
        return close();
      };
      return handle;
    };
    syncBuiltinESMExports();
    t.after(async () => {
      permitted = true;
      fs.open = originalOpen; syncBuiltinESMExports();
      if (failure?.cleanupHandle) await failure.cleanupHandle.retry();
    });
    await assert.rejects(prepareLocalPublicationStoreOwnership(directory, {maxWireBytes: 16384, maxDirectoryEntries: 64}),
      error => {failure = error; return error.cleanupHandle?.status().pending === true;});
    assert.equal(writes, 1); assert.notEqual(writer.fd, -1);
    await assert.rejects(fs.readFile(join(directory, 'owner', 'owner.json')), {code: 'ENOENT'});
    // No format or execution owner is invented for this incomplete fresh prefix.
    await assert.rejects(prepareLocalPublicationStoreOwnership(directory, {maxWireBytes: 16384, maxDirectoryEntries: 64}),
      {code: 'UnknownPublicationStoreFormat'});
    permitted = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(writer.fd, -1); assert.equal(writes, 1);
    assert.deepEqual(await fs.readdir(directory), []);
    scratch.passed();
  });
}

test('exclusive native directory publication never replaces an existing empty or foreign owner', async () => {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'owner-exclusive-', label: 'same native Store directory no-replace'});
  const directory = join(scratch.path, 'store'); await fs.mkdir(directory, {mode: 0o700});
  const native = createRequire(import.meta.url)(fileURLToPath(new URL(
    `../../packages/local-node/_build/native/${process.platform === 'linux' ? 'local-files-linux-x64' : 'directory-darwin-' + process.arch}.node`, import.meta.url)));
  const root = native.openFileRoot(directory), stage = '.owner-opening-11111111-1111-4111-8111-111111111111';
  await fs.mkdir(join(directory, stage), {mode: 0o700});
  const original = await fs.stat(join(directory, stage), {bigint: true});
  await fs.mkdir(join(directory, 'owner'), {mode: 0o700});
  const foreign = await fs.stat(join(directory, 'owner'), {bigint: true});
  assert.throws(() => native.publishStoreOwnerDirectory(root, stage, original.dev, original.ino), {code: 'PublicationStoreBusy'});
  assert.equal((await fs.stat(join(directory, 'owner'), {bigint: true})).ino, foreign.ino);
  await fs.writeFile(join(directory, 'owner', 'owner.json'), 'foreign original');
  assert.throws(() => native.publishStoreOwnerDirectory(root, stage, original.dev, original.ino), {code: 'PublicationStoreBusy'});
  assert.equal(await fs.readFile(join(directory, 'owner', 'owner.json'), 'utf8'), 'foreign original');
  const selected = native.openFileDirectory(root, 'owner', 2), name = '.lease-11111111-1111-4111-8111-111111111111.json';
  await fs.writeFile(join(directory, 'owner', name), 'complete staged bytes', {mode: 0o600});
  const before = await fs.stat(join(directory, 'owner', 'owner.json'), {bigint: true});
  const replacement = await fs.stat(join(directory, 'owner', name), {bigint: true});
  assert.throws(() => native.replaceStoreOwnerMetadata(selected, name,
    before.dev, before.ino, before.size, before.mtimeNs, before.ctimeNs, replacement.dev, replacement.ino,
    original.dev, original.ino), {code: 'PublicationStoreOwnershipLost'}, 'equal file inputs do not replace the original directory');
  assert.equal(await fs.readFile(join(directory, 'owner', 'owner.json'), 'utf8'), 'foreign original');
  assert.equal(native.fileRootClose(selected).outcome, 'closed');
  assert.equal(native.fileRootClose(root).outcome, 'closed'); scratch.passed();
});

test('existing corrupt and live legacy owners remain refused without repair', async () => {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'owner-refusal-', label: 'final owner refusal is unchanged'});
  const directory = join(scratch.path, 'store'), config = configuration(directory);
  const initial = await openLocalPublicationStore(config, createPublicationContractControlFixture()); await initial.close();
  await fs.mkdir(join(directory, 'owner'), {mode: 0o700});
  const path = join(directory, 'owner', 'owner.json');
  for (const text of ['', '{partial', JSON.stringify({version: 'actql-local-publication-store-owner/0.1', pid: process.pid, token: 'live-original'})]) {
    await fs.writeFile(path, text, {mode: 0o600});
    await assert.rejects(openLocalPublicationStore(config, createPublicationContractControlFixture()),
      {code: text.startsWith('{"version"') ? 'PublicationStoreBusy' : 'InvalidPublicationStoreOwner'});
    assert.equal(await fs.readFile(path, 'utf8'), text);
  }
  scratch.passed();
});

for (const mode of ['false', 'throw', 'foreign']) {
  test(`lease metadata ${mode} failure keeps original identity and cleanup custody`, async t => {
    const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
      prefix: 'owner-lease-failure-', label: 'same prepared owner lease replacement'});
    const directory = join(scratch.path, 'store'), path = join(directory, 'owner', 'owner.json');
    const original = await prepareLocalPublicationStoreOwnership(directory, {maxWireBytes: 16384, maxDirectoryEntries: 64});
    const originalBytes = await fs.readFile(path), originalState = await fs.stat(path);
    const originalOpen = fs.open, primary = new Error('LeaseWriterClosePending');
    let permitted = false, writer, writes = 0, substituted = false;
    fs.open = async (...args) => {
      const handle = await originalOpen(...args), write = handle.write.bind(handle), close = handle.close.bind(handle);
      handle.write = async (...values) => {
        if (Buffer.isBuffer(values[0]) && values[0].toString().includes('leaseAnchor')) {
          writer = handle; writes++;
          if (mode === 'foreign' && !substituted) {
            substituted = true;
            await fs.rename(path, join(scratch.path, 'original-owner.json'));
            await fs.writeFile(path, originalBytes, {mode: 0o600});
          }
        }
        return write(...values);
      };
      handle.close = async () => {
        if (handle === writer && !permitted && mode !== 'foreign') {
          if (mode === 'false') return false;
          throw primary;
        }
        return close();
      };
      return handle;
    };
    syncBuiltinESMExports();
    t.after(async () => {
      permitted = true; fs.open = originalOpen; syncBuiltinESMExports();
      if (substituted) {
        await fs.unlink(path);
        await fs.rename(join(scratch.path, 'original-owner.json'), path);
      }
      assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
    });
    await assert.rejects(openLocalPublicationStore(configuration(directory), createPublicationContractControlFixture(),
      undefined, undefined, original));
    assert.equal(writes, 1);
    assert.deepEqual(await fs.readFile(path), originalBytes, 'incomplete lease bytes never replace the final owner');
    if (mode === 'foreign') {
      const foreignState = await fs.stat(path);
      assert.notEqual(foreignState.ino, originalState.ino);
      await assert.rejects(closePreparedLocalPublicationStoreOwnership(original), {code: 'PublicationStoreOwnershipLost'});
      assert.equal((await fs.stat(path)).ino, foreignState.ino, 'cleanup never unlinks a copied foreign original');
    } else {
      assert.notEqual(writer.fd, -1);
      permitted = true;
      assert.equal((await closePreparedLocalPublicationStoreOwnership(original)).pending, false);
      assert.equal(writer.fd, -1); assert.equal(writes, 1);
    }
    scratch.passed();
  });
}

test('committed lease metadata retains consumed native-close Unknown before owner retirement', async () => {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'owner-native-close-', label: 'new native metadata close uncertainty', preserve: true});
  const directory = join(scratch.path, 'store');
  const child = spawn(process.execPath, [fileURLToPath(new URL('./fixtures/owner-native-close.fixture.mjs', import.meta.url)),
    directory], {stdio: ['ignore', 'pipe', 'pipe']});
  const stdout = [], stderr = [];
  child.stdout.on('data', bytes => stdout.push(bytes)); child.stderr.on('data', bytes => stderr.push(bytes));
  const [code, signal] = await once(child, 'close');
  assert.equal(signal, null); assert.equal(code, 0, Buffer.concat(stderr).toString());
  assert.equal(Buffer.concat(stdout).toString(), 'native-close-retained\n');
  // The child ended, but its pending owner/metadata remains preserved.
  // Scratch completion is not an Owner cleanup or physical-stop ACK.
  scratch.passed();
});
