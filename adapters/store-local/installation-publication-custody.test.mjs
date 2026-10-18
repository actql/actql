// Actual Store, files, encryption, holdings and a fresh Node process. Semantic
// binding and contract control are explicit fixtures, NOT Common/Host admission.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {open, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

const execute = promisify(execFile);
const digest = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
const coldProbe = fileURLToPath(new URL('./installation-publication-cold.fixture.mjs', import.meta.url));
// This is deliberately not an invented installation-publication schema. The
// existing semantic Owner must supply its actual closed record and holding key.
const wire = '{"physical_test_only":"original snapshot: e\u0301 / \\u0000"}';
const binding = Object.freeze({name: 'installation_publication',
  semanticCid: digest('explicit semantic binding fixture'),
  holdingCid: digest('explicit owner holding fixture'), wire});

async function fixture(t, hooks) {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'installation-publication-', label: 'installation publication physical custody',
  });
  const configuration = Object.freeze({directory: join(scratch.path, 'store'),
    storeAuthorityCid: digest('explicit physical Store authority fixture'),
    capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
    maxContractNodes: 256, maxContractDepth: 32});
  const stores = [];
  const acquire = async () => {
    const store = await openLocalPublicationStore({...configuration,
      privateEvidenceKey: Buffer.alloc(32, 7)}, createPublicationContractControlFixture(), hooks);
    stores.push(store);
    return store;
  };
  const store = await acquire();
  t.after(async () => {
    for (const owned of stores) {
      if (!owned.status().closed) assert.equal(await owned.close(), true);
    }
    // The owned scratch preserves failed/uncertain state; verification also
    // selects ACTQL_TEST_PRESERVE_SCRATCH=1 to keep successful original records.
  });
  return {store, configuration, acquire, scratch,
    async cold(patch = {}, keyByte = 7) {
      const result = await execute(process.execPath, [coldProbe,
        JSON.stringify({configuration, binding: {...binding, ...patch}, keyByte})],
      {timeout: 20000, maxBuffer: 1024 * 1024});
      assert.equal(result.stderr, '');
      return JSON.parse(result.stdout);
    }};
}

test('installation publication survives fresh-process cold read without metadata acquisition', async t => {
  const f = await fixture(t);
  const owner = preparePrivatePublicationHolding(f.store, binding);
  const record = await owner.commit();
  assert.equal(record.namespace, 'publication-private');
  assert.equal(record.manifest_cid, binding.semanticCid);
  assert.equal(owner.status().committed, true);
  const cipherPath = join(f.configuration.directory, 'objects', record.objects[0].cid.slice(7));
  const ciphertext = await readFile(cipherPath);
  assert.equal(ciphertext.includes(Buffer.from(wire)), false);
  assert.equal(await f.store.close(), true);
  const cold = await f.cold();
  assert.notEqual(cold.pid, process.pid);
  assert.equal(cold.holdingCid, binding.holdingCid);
  assert.equal(cold.bytes, Buffer.byteLength(wire));
  assert.equal(cold.digest, digest(wire).slice(7));
  assert.deepEqual(await readFile(cipherPath), ciphertext);
  f.scratch.passed();
});

for (const [name, patch, keyByte, code] of [
  ['wrong Store key', {}, 8, 'PublicationPrivateEvidenceCorrupt'],
  ['missing Store key', {}, null, 'PublicationPrivateEvidenceKeyUnavailable'],
  ['Run source_evidence is not the installation purpose', {name: 'source_evidence'}, 7,
    'PublicationPrivateEvidenceCorrupt'],
  ['foreign semantic identity', {semanticCid: digest('foreign semantic fixture')}, 7,
    'PublicationPrivateEvidenceUnavailable'],
  ['foreign holding', {holdingCid: digest('foreign original holding fixture')}, 7,
    'PublicationPrivateEvidenceUnavailable'],
]) {
  test(`cold installation publication refuses ${name}`, async t => {
    const f = await fixture(t);
    await preparePrivatePublicationHolding(f.store, binding).commit();
    assert.equal(await f.store.close(), true);
    await assert.rejects(f.cold(patch, keyByte), error => error.stderr.includes(code));
    // The original authenticated record survives every refused cold consumer.
    const cold = await f.cold();
    assert.equal(cold.digest, digest(wire).slice(7));
    f.scratch.passed();
  });
}

test('installation holding admits only its exact purpose, not prefixes or arbitrary kinds', async t => {
  const f = await fixture(t);
  for (const name of ['installation', 'installation_publication_copy', 'Installation_publication']) {
    assert.throws(() => preparePrivatePublicationHolding(f.store, {...binding, name}),
      {code: 'InvalidPrivatePublicationHolding'});
    await assert.rejects(f.store.confirmPrivateEvidence({...binding, name}),
      {code: 'InvalidPublicationPrivateEvidence'});
  }
  assert.equal(f.store.status().storedBytes, 0);
  assert.equal(await f.store.close(), true);
  f.scratch.passed();
});

test('unknown installation commit retains the same preparation until original durability confirms', async t => {
  let refuse = false;
  const fault = Object.assign(new Error('OriginalInstallationHoldingDirectoryAckLost'), {code: 'EIO'});
  const f = await fixture(t, {async syncDirectory(path) {
    if (refuse && path === join(f.configuration.directory, 'physical-holdings')) throw fault;
    const fd = await open(path, 'r');
    try { await fd.sync(); } finally { await fd.close(); }
  }});
  let preparations = 0;
  const owner = preparePrivatePublicationHolding({
    confirmPrivateEvidence: value => f.store.confirmPrivateEvidence(value),
    preparePrivateEvidence(...args) {
      preparations++;
      return f.store.preparePrivateEvidence(...args);
    },
    commitPhysicalHolding: (...args) => f.store.commitPhysicalHolding(...args),
  }, binding);
  refuse = true;
  await assert.rejects(owner.commit(), error => error.cleanupHandle === owner);
  assert.equal(owner.status().committed, false);
  assert.equal(owner.status().preparedPending, true);
  const original = await f.store.inspectPhysicalHolding(binding.holdingCid);
  const path = join(f.configuration.directory, 'objects', original.objects[0].cid.slice(7));
  const originalBytes = await readFile(path);
  await assert.rejects(owner.retry(), error => error.cleanupHandle === owner);
  assert.equal(preparations, 1);
  await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
  refuse = false;
  assert.deepEqual(await owner.retry(), original);
  assert.equal(owner.status().committed, true);
  assert.equal(owner.status().preparedPending, false);
  assert.equal(preparations, 1);
  assert.deepEqual(await readFile(path), originalBytes);
  assert.equal(await f.store.close(), true);
  assert.equal((await f.cold()).digest, digest(wire).slice(7));
  f.scratch.passed();
});

for (const outcome of ['false', 'reject']) {
  test(`${outcome} installation evidence FD close retains the original read duty`, async t => {
    const f = await fixture(t);
    const record = await preparePrivatePublicationHolding(f.store, binding).commit();
    const path = join(f.configuration.directory, 'objects', record.objects[0].cid.slice(7));
    const ciphertext = await readFile(path);
    const probe = await open(path, 'r');
    const prototype = Object.getPrototypeOf(probe), stat = prototype.stat;
    await probe.close();
    let original, nativeClose, cleanup, closeCalls = 0, reads = 0, holdClose = true;
    const closeFailure = new Error('OriginalInstallationEvidenceCloseRefused');
    prototype.stat = function(...args) {
      if (original === undefined && new Error().stack.split('\n')[2]?.includes('consumeObject')) {
        original = this;
        nativeClose = this.close;
        const read = this.read;
        this.read = function(...readArgs) {
          reads++;
          return Reflect.apply(read, this, readArgs);
        };
        this.close = function(...closeArgs) {
          // Node's stream destroy has a separate notification. Control only
          // the Store's original close, not a synthetic replacement FD.
          if (new Error().stack.split('\n')[2]?.includes('node:internal/fs/streams:')) {
            return Reflect.apply(nativeClose, this, closeArgs);
          }
          closeCalls++;
          if (holdClose) return outcome === 'false'
            ? Promise.resolve(false) : Promise.reject(closeFailure);
          return Reflect.apply(nativeClose, this, closeArgs);
        };
      }
      return Reflect.apply(stat, this, args);
    };
    t.after(async () => {
      prototype.stat = stat;
      holdClose = false;
      if (cleanup?.status().pending) await cleanup.retry();
      assert(original === undefined || original.fd === -1);
    });
    await assert.rejects(f.store.readPrivateEvidence(binding.name,
      binding.semanticCid, binding.holdingCid), error => {
      cleanup = error.cleanupHandle;
      return cleanup?.status().pending === true;
    });
    assert(original.fd >= 0);
    assert.equal(closeCalls, 1);
    await assert.rejects(f.store.close(), {code: 'PublicationStoreCleanupPending'});
    assert.deepEqual(await readFile(path), ciphertext);
    const originalReads = reads;
    holdClose = false;
    await cleanup.retry();
    assert.equal(cleanup.status().pending, false);
    assert.equal(original.fd, -1);
    assert.equal(closeCalls, 2);
    assert.equal(reads, originalReads, 'cleanup closes only; no metadata or ciphertext reread');
    await cleanup.retry();
    assert.equal(closeCalls, 2);
    assert.deepEqual(await f.store.inspectPhysicalHolding(binding.holdingCid), record);
    assert.equal(await f.store.close(), true);
    f.scratch.passed();
  });
}
