import assert from 'node:assert/strict';
import {chmod, lstat, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'acorn';
import {openLocalPublicationStore} from './publication-store.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';

const source = await readFile(new URL('./publication-store.mjs', import.meta.url), 'utf8');
const declaration = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'retainStoreOpeningFailure');
assert(declaration !== undefined);
const retain = runInNewContext(`(${source.slice(declaration.start, declaration.end)})`, {
  fail: code => { throw Object.assign(new Error(code), {code}); },
});
async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-store-opening-custody-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const configuration = {directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 100, maxContractDepth: 10};
  const control = createPublicationContractControlFixture();
  const initial = await openLocalPublicationStore(configuration, control);
  await initial.close();
  await writeFile(join(directory, 'staging', 'not-an-object'), 'independent invalid entry');
  return {directory, configuration, control};
}

test('actual Store opening failure releases its same ownership before reporting the primary', async t => {
  const f = await fixture(t);
  await assert.rejects(openLocalPublicationStore(f.configuration, f.control),
    {code: 'InvalidPublicationStagingObject'});
  await assert.rejects(readFile(join(f.directory, 'owner', 'owner.json')), {code: 'ENOENT'});
  await rm(join(f.directory, 'staging', 'not-an-object'));
  const reopened = await openLocalPublicationStore(f.configuration, f.control);
  await reopened.close();
});

test('actual Store failed opening cleanup retains exact ownership for same-handle retry', async t => {
  const f = await fixture(t);
  const ownershipDirectory = join(f.directory, 'owner');
  const probe = await open(f.directory, 'r');
  const prototype = Object.getPrototypeOf(probe), sync = prototype.sync;
  await probe.close();
  let blocked = false, failure;
  t.after(async () => {
    prototype.sync = sync;
    await chmod(ownershipDirectory, 0o700).catch(() => {});
    if (failure?.cleanupHandle?.status().pending) await failure.cleanupHandle.retry();
  });
  prototype.sync = async function(...args) {
    const result = await Reflect.apply(sync, this, args);
    if (!blocked && new Error().stack.includes('at async acquireStoreOwnership ')) {
      // Stage durability precedes final visibility; block the published Owner only.
      try {await lstat(ownershipDirectory);} catch (cause) {if (cause.code === 'ENOENT') return result; throw cause;}
      blocked = true;
      await chmod(ownershipDirectory, 0o500);
    }
    return result;
  };
  await assert.rejects(openLocalPublicationStore(f.configuration, f.control), error => {
    failure = error;
    return error.code === 'InvalidPublicationStagingObject';
  });
  prototype.sync = sync;
  assert(blocked);
  assert.equal(failure.cause.code, 'InvalidPublicationStagingObject');
  assert.equal(failure.cleanupError.code, 'EACCES');
  assert.equal(failure.cleanupHandle.status().pending, true);
  const owner = await readFile(join(ownershipDirectory, 'owner.json'));
  assert.equal(JSON.parse(owner).pid, process.pid);
  const first = failure.cleanupHandle.retry();
  assert.strictEqual(failure.cleanupHandle.retry(), first);
  await assert.rejects(first, {code: 'EACCES'});
  assert.deepEqual(await readFile(join(ownershipDirectory, 'owner.json')), owner);
  await assert.rejects(openLocalPublicationStore(f.configuration, f.control), {code: 'PublicationStoreBusy'});
  await chmod(ownershipDirectory, 0o700);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  await assert.rejects(readFile(join(ownershipDirectory, 'owner.json')), {code: 'ENOENT'});
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  await rm(join(f.directory, 'staging', 'not-an-object'));
  const reopened = await openLocalPublicationStore(f.configuration, f.control);
  await reopened.close();
});

test('opening cleanup preserves frozen primary and closes failed original reader before ownership', async () => {
  const events = [];
  let readerPending = true, rejectReader = true;
  const readFailure = new Error('OriginalReaderClosePending');
  const reader = {
    status: () => ({pending: readerPending}),
    async retry() {
      events.push('reader-close');
      if (rejectReader) throw readFailure;
      readerPending = false;
      return {pending: false};
    },
  };
  const cause = Object.freeze(Object.assign(new Error('OriginalOpeningFailed'),
    {code: 'OriginalOpeningFailed', cleanupHandle: reader}));
  const key = Buffer.alloc(32, 7);
  const owner = {async release() { events.push('owner-release'); return true; }};
  const failure = await retain(cause, owner, key);
  assert.strictEqual(failure.cause, cause);
  assert.strictEqual(failure.primaryFailure, cause);
  assert.strictEqual(failure.cleanupError, readFailure);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(events, ['reader-close']);
  assert.deepEqual(key, Buffer.alloc(32, 7));
  rejectReader = false;
  const retry = failure.cleanupHandle.retry();
  assert.strictEqual(failure.cleanupHandle.retry(), retry);
  assert.equal((await retry).pending, false);
  assert.deepEqual(events, ['reader-close', 'reader-close', 'owner-release']);
  assert.deepEqual(key, Buffer.alloc(32));
  await failure.cleanupHandle.retry();
  assert.equal(events.length, 3);
});

test('opening cleanup does not convert absent/unconfirmed ownership into completion', async () => {
  let releases = 0;
  const key = Buffer.alloc(32, 7);
  const cause = new Error('OriginalOpeningFailed');
  const failure = await retain(cause, {async release() { releases++; return false; }}, key);
  assert.equal(failure.cleanupError.code, 'PublicationStoreOwnershipLost');
  assert.equal(failure.cleanupHandle.status().pending, true);
  await assert.rejects(failure.cleanupHandle.retry(), {code: 'PublicationStoreOwnershipLost'});
  assert.equal(releases, 2);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(key, Buffer.alloc(32, 7));
});
