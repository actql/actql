import assert from 'node:assert/strict';
import fs, {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import type {TestContext} from 'node:test';
import type {FileHandle} from 'node:fs/promises';
import type {FixtureCleanupFailure, FixtureFailureFields, FixtureReadArguments} from './fixtures/store-file-ports.d.mts';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {retainInstalledHostInitializationFailure} from '../host-node/installed-host-cleanup.mjs';

type OpeningFailure = FixtureCleanupFailure & Readonly<{cause: Error & FixtureFailureFields}>;

async function fixture(t: TestContext) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-store-contract-custody-'));
  t.after(() => rm(directory, {recursive: true}));
  const configuration = {directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 100, maxContractDepth: 10};
  const control = createPublicationContractControlFixture();
  const initial = await openLocalPublicationStore(configuration, control);
  await initial.close();
  return {directory, configuration, control};
}

for (const readFailure of [undefined, Object.freeze(new Error('OriginalStoreContractReadFailed'))]) {
  test(`actual pre-owner format failure retains the same FD${readFailure ? ' and frozen primary' : ''} through initialization retry`, async t => {
    const openOriginal = fs.open;
    let original: FileHandle | undefined, nativeClose: FileHandle['close'] | undefined,
      allowClose = false, failure: OpeningFailure | undefined, opens = 0, closes = 0, reads = 0;
    const blocked = Object.assign(new Error('OriginalStoreContractCloseFailed'), {code: 'EIO'});
    const restoreOpen = () => { fs.open = openOriginal; syncBuiltinESMExports(); };
    t.after(async () => {
      restoreOpen();
      allowClose = true;
      if (failure?.cleanupHandle?.status().pending) await failure!.cleanupHandle.retry();
      if ((original?.fd as number) >= 0) await Reflect.apply(nativeClose!, original, []);
    });
    const f = await fixture(t);
    const path = join(f.directory, 'store.json');
    const saved = await readFile(path);
    fs.open = async (...args) => {
      if (args[0] !== path) return Reflect.apply(openOriginal, fs, args);
      assert.equal(original, undefined, 'pending cleanup must never acquire another contract FD');
      const handle = await Reflect.apply(openOriginal, fs, args);
      original = handle;
      opens++;
      nativeClose = handle.close;
      const read = handle.read;
      handle.read = (function(this: FileHandle, ...args: FixtureReadArguments) {
        reads++;
        if (readFailure) return Promise.reject(readFailure);
        return Reflect.apply(read, this, args);
      }) as FileHandle['read'];
      handle.close = function(this: FileHandle, ...args: Parameters<FileHandle['close']>) {
        closes++;
        if (!allowClose) return Promise.reject(blocked);
        return Reflect.apply(nativeClose!, this, args);
      };
      return handle;
    };
    syncBuiltinESMExports();
    await assert.rejects(openLocalPublicationStore(f.configuration, f.control), error => {
      failure = error as OpeningFailure;
      return (error as FixtureFailureFields).code === 'UnknownPublicationStoreFormat';
    });
    assert.strictEqual(failure!.cleanupHandle, failure!.cause.cleanupHandle);
    assert.strictEqual(failure!.primaryFailure, failure!.cause);
    assert.strictEqual(failure!.cleanupError, blocked);
    if (readFailure) assert.strictEqual(failure!.cause.cause, readFailure);
    else assert.strictEqual(failure!.cause, blocked);
    assert.equal(failure!.cleanupHandle.status().pending, true);
    assert((original as FileHandle | undefined)!.fd >= 0);
    // Store ownership was not acquired; no artificial owner or reopen exists.
    await assert.rejects(readFile(join(f.directory, 'owner', 'owner.json')), {code: 'ENOENT'});
    const installed = await retainInstalledHostInitializationFailure(failure!, {});
    assert.strictEqual(installed.primaryFailure, failure!.primaryFailure);
    assert.deepEqual(installed.cleanupHandle.status().owners, ['initialization']);
    assert.equal(installed.cleanupHandle.status().pending, true);
    assert.equal(closes, 2);
    const originalReads = reads;
    // A pathname replacement cannot make close-only retry read new metadata.
    await rm(path);
    await writeFile(path, 'not an accepted Store');
    allowClose = true;
    const retry = installed.cleanupHandle.retry();
    assert.strictEqual(installed.cleanupHandle.retry(), retry);
    assert.equal((await retry).pending, false);
    assert.equal((original as FileHandle | undefined)!.fd, -1);
    assert.equal(closes, 3);
    assert.equal(reads, originalReads);
    assert.equal(opens, 1);
    await installed.cleanupHandle.retry();
    assert.equal(closes, 3);
    restoreOpen();
    // The ordinary entry still diagnoses invalid format. This is not a
    // continuation of failed initialization and does not issue a read grant.
    await assert.rejects(openLocalPublicationStore(f.configuration, f.control),
      {code: 'UnknownPublicationStoreFormat'});
    await writeFile(path, saved);
    const reopened = await openLocalPublicationStore(f.configuration, f.control);
    await reopened.close();
  });
}
