// Actual local Store/filesystem and process interruption; protocol admission
// uses the explicit contract-control fixture, not genuine Core or Model grants.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {readdir, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';
const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;

for (const mode of ['empty', 'partial']) {
  test(`interrupted ${mode} holding metadata never becomes a final ownership record`, async t => {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: `holding-atomic-${mode}-`, label: 'physical holding interrupted publication'});
    const directory = join(scratch.path, 'store');
    const child = spawn(process.execPath, [new URL('./fixtures/physical-holding-interrupted.fixture.mjs',
      import.meta.url).pathname, directory, mode], {stdio: ['ignore', 'pipe', 'pipe']});
    const stdout = [], stderr = [];
    child.stdout.on('data', bytes => stdout.push(bytes));
    child.stderr.on('data', bytes => stderr.push(bytes));
    const [code, signal] = await once(child, 'close');
    assert.equal(signal, null);
    assert.equal(code, 77, Buffer.concat(stderr).toString('utf8'));
    const observation = JSON.parse(Buffer.concat(stdout).toString('utf8'));
    assert.equal(observation.boundary, 'holding-record-before-complete-write');
    assert.equal((await readFile(observation.path)).length, mode === 'empty' ? 0 : 11);
    const finalNames = await readdir(join(directory, 'physical-holdings'));
    assert.deepEqual(finalNames, [], 'Only complete bytes may occupy a final holding name');
    const store = await openLocalPublicationStore({directory,
      storeAuthorityCid: cid('atomic holding authority'), capacityBytes: 65536,
      maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
    createPublicationContractControlFixture());
    t.after(async () => { if (!store.status().closed) await store.close(); });
    assert.equal(await store.inspectPhysicalHolding(cid('atomic original holding')), undefined);
    assert.deepEqual(await readdir(join(directory, 'staging')), []);
    await store.close();
    scratch.passed();
  });
}

for (const mode of ['false', 'rejected']) {
  test(`holding publication retains the same ${mode}-close FD without publishing or rewriting`, async t => {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: `holding-atomic-close-${mode}-`, label: 'physical holding failed-close publication'});
    const directory = join(scratch.path, 'store');
    const store = await openLocalPublicationStore({directory,
      storeAuthorityCid: cid('atomic holding authority'), capacityBytes: 65536,
      maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
    createPublicationContractControlFixture());
    const bytes = Buffer.from('original byte payload\n');
    const writer = store.createPreparedObjectWriter(bytes.length);
    await writer.append(bytes);
    const physical = await writer.seal(cid(bytes));
    const record = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
      holding_cid: cid('atomic original holding'), manifest_cid: cid('atomic original manifest'),
      objects: [{cid: cid(bytes), byte_count: bytes.length}]};
    const originalOpen = fs.open;
    const primary = Object.freeze(Object.assign(new Error('Original metadata close refused'), {code: 'EIO'}));
    let refusing = true, writes = 0, closes = 0, fd;
    fs.open = async (...args) => {
      const handle = await originalOpen(...args);
      const write = handle.write.bind(handle), close = handle.close.bind(handle);
      let holding = false;
      handle.write = async (...values) => {
        if (Buffer.isBuffer(values[0]) && values[0].toString('utf8').includes(
          '"version":"actql-local-physical-holding/0.1"')) {
          holding = true;
          assert.equal(fd ??= handle.fd, handle.fd);
          writes++;
        }
        return write(...values);
      };
      handle.close = async () => {
        if (holding) {
          assert.equal(handle.fd, fd);
          closes++;
          if (refusing) {
            if (mode === 'false') return false;
            throw primary;
          }
        }
        return close();
      };
      return handle;
    };
    syncBuiltinESMExports();
    let failure;
    try {
      await assert.rejects(store.commitPhysicalHolding(record, [physical.prepared]), error => {
        failure = error;
        return error.code === 'PublicationStoreCleanupPending';
      });
      assert.equal(failure.cleanupHandle.status().pending, true);
      if (mode === 'rejected') assert.equal(failure.primaryFailure, primary);
      assert.deepEqual(await readdir(join(directory, 'physical-holdings')), []);
      assert.equal(physical.prepared.status().pending, true);
      assert.equal(store.status().storedBytes, bytes.length);
      await assert.rejects(store.commitPhysicalHolding(record, [physical.prepared]),
        {code: 'PublicationStoreCleanupPending'});
      assert.equal(writes, 1);
      // This prepared payload has never been published; its original owner
      // can retire it. The separate original metadata FD remains Store-owned.
      assert.equal(await physical.prepared.release(), true);
      await assert.rejects(store.close(), {code: 'PublicationStoreCleanupPending'});
      assert.equal(store.status().closed, false);
      refusing = false;
      if (mode === 'false') {
        // Even a sanitized/discarded error cannot lose this Store's original
        // duty: shutdown drives the same close-only cleanup itself.
        await store.close();
        assert.equal(failure.cleanupHandle.status().pending, false);
      } else {
        const first = failure.cleanupHandle.retry(), second = failure.cleanupHandle.retry();
        assert.equal(first, second, 'one flight closes the same original FD');
        assert.equal((await first).pending, false);
      }
      assert.equal((await failure.cleanupHandle.retry()).pending, false);
      assert.equal(writes, 1, 'cleanup never repeats metadata writes');
      assert.ok(closes >= 3);
      assert.deepEqual(await readdir(join(directory, 'staging')), []);
      await store.close();
      scratch.passed();
    } finally {
      refusing = false;
      fs.open = originalOpen;
      syncBuiltinESMExports();
      if (failure?.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
      if (physical.prepared.status().pending) await physical.prepared.release();
      if (!store.status().closed) await store.close();
    }
  });
}

test('an already corrupt final holding remains refused without deletion or repair', async () => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'holding-atomic-corrupt-', label: 'preexisting corrupt holding refusal'});
  const directory = join(scratch.path, 'store');
  const configuration = {directory, storeAuthorityCid: cid('atomic holding authority'),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32};
  const store = await openLocalPublicationStore(configuration, createPublicationContractControlFixture());
  await store.close();
  const path = join(directory, 'physical-holdings', cid('atomic original holding').slice(7) + '.json');
  await fs.writeFile(path, Buffer.alloc(0), {flag: 'wx', mode: 0o600});
  await assert.rejects(openLocalPublicationStore(configuration, createPublicationContractControlFixture()),
    {code: 'InvalidPublicationPhysicalHoldingStore'});
  assert.equal((await readFile(path)).length, 0);
  scratch.passed();
});
