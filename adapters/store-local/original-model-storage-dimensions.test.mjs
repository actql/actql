import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from './publication-store.mjs';

// Real Store/configuration and filesystem, explicit protocol-control double.
// These DATA dimensions neither authenticate storage nor supply a byte grant.
async function fixture(t, suffix, withKey = true) {
  const root = await mkdtemp(join(tmpdir(), 'actql-c-store-dimensions-'));
  const directory = join(root, suffix);
  const options = {directory,
    storeAuthorityCid: `sha256:${'a'.repeat(64)}`,
    capacityBytes: 65536, maxObjectBytes: 16384, maxObjects: 8,
    maxContractNodes: 128, maxContractDepth: 16,
    ...(withKey ? {privateEvidenceKey: Buffer.alloc(32, 7)} : {})};
  const store = await openLocalPublicationStore(options,
    createPublicationContractControlFixture());
  t.after(async () => {
    assert.equal(await store.close(), true);
    await rm(root, {recursive: true, force: true});
  });
  return {store, root, directory, options};
}

test('dimensions come from the immutable original Store and distinguish UTF16 from UTF8', async t => {
  // Independent suffix oracle: e + combining acute + supplementary scalar.
  // Preserve the NFD spelling; no configuration NFC canonicalizer is involved.
  const {store, root, directory, options} = await fixture(t, 'e\u0301\u{1f600}');
  const expected = {directoryCodeUnits: root.length + 1 + 4,
    directoryUtf8Bytes: Buffer.byteLength(root) + 1 + 7,
    privateNamespaceCodeUnits: 26, privateNamespaceUtf8Bytes: 26,
    privateKeyBytes: 32};
  const before = store.status();
  const names = await readdir(directory);
  assert.deepEqual(store.originalModelStorageDimensions(), expected);
  const projected = store.originalModelStorageDimensions();
  assert.equal(Object.isFrozen(projected), true);
  assert.equal(Object.values(projected).every(Number.isSafeInteger), true);
  assert.throws(() => { projected.directoryCodeUnits = 0; }, TypeError);
  options.directory = '/not-the-original-store';
  options.privateEvidenceKey = Buffer.alloc(1);
  assert.deepEqual(store.originalModelStorageDimensions(), expected);
  assert.deepEqual(store.status(), before, 'no reservation, publication or release');
  assert.deepEqual(await readdir(directory), names, 'projection creates no storage evidence');
});

test('different actual Store receivers project their own dimensions, never an argument', async t => {
  const first = await fixture(t, 'a');
  const second = await fixture(t, 'longer-name');
  const one = first.store.originalModelStorageDimensions({directoryCodeUnits: 0});
  const two = second.store.originalModelStorageDimensions(one);
  assert.equal(one.directoryCodeUnits, first.directory.length);
  assert.equal(two.directoryCodeUnits, second.directory.length);
  assert.equal(one.privateKeyBytes, 32);
  assert.equal(two.privateKeyBytes, 32);
  assert.deepEqual(Object.keys(one).sort(), ['directoryCodeUnits', 'directoryUtf8Bytes',
    'privateKeyBytes', 'privateNamespaceCodeUnits', 'privateNamespaceUtf8Bytes'].sort());
});

test('missing key and closed original Store refuse instead of manufacturing dimensions', async t => {
  const {store} = await fixture(t, 'without-key', false);
  const before = store.status();
  assert.throws(() => store.originalModelStorageDimensions(),
    {code: 'PublicationPrivateEvidenceKeyUnavailable'});
  assert.deepEqual(store.status(), before);
  assert.equal(await store.close(), true);
  assert.throws(() => store.originalModelStorageDimensions(),
    {code: 'PublicationStoreClosed'});
});
