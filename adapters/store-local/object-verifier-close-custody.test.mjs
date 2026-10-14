import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, open, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

// Actual Store, physical object, stream and OS FileHandle. Contract control
// remains the existing independent double, not original Core admission.
async function fixture(t, {failures = 2, primary, falseClose = false, pause = false} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-c-verifier-custody-'));
  const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
  const bytes = Buffer.from('abcd');
  const store = await openLocalPublicationStore({directory,
    storeAuthorityCid: digest('verifier custody authority'), capacityBytes: 1024 * 1024,
    maxObjectBytes: 4096, maxObjects: 16, maxContractNodes: 4096, maxContractDepth: 64},
  createPublicationContractControlFixture());
  const writer = store.createObjectWriter(bytes.length);
  await writer.append(bytes);
  const stored = await writer.seal(digest(bytes));
  const path = join(directory, 'objects', stored.cid.slice(7));
  const probe = await open(path, 'r');
  const prototype = Object.getPrototypeOf(probe), stat = prototype.stat;
  await probe.close();
  const entered = Promise.withResolvers(), proceed = Promise.withResolvers();
  if (!pause) proceed.resolve();
  let original, nativeClose, attempts = 0, stats = 0, streams = 0;
  let allowClose = false, passed = false, caught;
  const closeFailure = Object.assign(new Error('OriginalVerifierClosePending'), {code: 'EIO'});
  prototype.stat = function(...args) {
    if (original === undefined && new Error().stack.split('\n')[2]?.includes('verifyObject')) {
      original = this;
      nativeClose = this.close;
      const stream = this.createReadStream;
      this.createReadStream = function(options) {
        streams++;
        return Reflect.apply(stream, this, [options]);
      };
      this.close = function(...closeArgs) {
        // FileHandle close emits the original ReadStream's native close
        // notification. It is not another product cleanup request.
        if (new Error().stack.split('\n')[2]?.includes('node:internal/fs/streams:')) {
          return Reflect.apply(nativeClose, this, closeArgs);
        }
        attempts++;
        if (!allowClose && attempts <= failures) {
          return falseClose ? Promise.resolve(false) : Promise.reject(closeFailure);
        }
        return Reflect.apply(nativeClose, this, closeArgs);
      };
    }
    if (this !== original) return Reflect.apply(stat, this, args);
    stats++;
    entered.resolve();
    return proceed.promise.then(() => {
      if (primary !== undefined) throw primary;
      return Reflect.apply(stat, this, args);
    });
  };
  t.after(async () => {
    prototype.stat = stat;
    proceed.resolve();
    allowClose = true;
    if (caught?.cleanupHandle?.status().pending) await caught.cleanupHandle.retry();
    if (original?.fd >= 0) await Reflect.apply(nativeClose, original, []);
    if (!store.status().closed) await store.close();
    if (passed) await rm(directory, {recursive: true});
    else t.diagnostic(`Preserved verifier custody failure: ${directory}`);
  });
  return {store, bytes, stored, path, closeFailure, entered, proceed,
    fd: () => original?.fd, counts: () => ({attempts, stats, streams}),
    async read() {
      try { return await store.verifyObject(stored.cid); }
      catch (error) { caught = error; throw error; }
    },
    pass() { passed = true; }};
}

test('Store close retains and drives the same failed verifier FD without another read', async t => {
  const f = await fixture(t);
  await assert.rejects(f.read(), error => error === f.closeFailure);
  assert(f.fd() >= 0);
  const before = f.counts();
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  assert.equal(f.store.status().closed, false);
  assert(f.fd() >= 0);
  const one = f.store.close();
  assert.strictEqual(f.store.close(), one);
  assert.equal(await one, true);
  assert.equal(f.fd(), -1);
  assert.deepEqual(f.counts(), {...before, attempts: 3});
  assert.deepEqual(await readFile(f.path), f.bytes);
  assert.equal(await f.store.close(), true);
  assert.equal(f.counts().attempts, 3);
  f.pass();
});
