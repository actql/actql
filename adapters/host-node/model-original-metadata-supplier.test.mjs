// Actual compiled original Scope/Model checks with explicitly synthetic
// installation amounts. No heap adequacy, new reservation or public profile.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';
import {selectOriginalInferMetadataAcquisition, selectOriginalInferStoreBootstrapAcquisition,
  selectOriginalInferResourceCodecAcquisition} from './infer-operation.mjs';

const declared = () => ({metadata: {maxWireBytes: 512, maxLedgerEntries: 3},
  directory: {maxWireBytes: 512, maxDirectoryEntries: 4},
  retainedBytes: 7000n, workspaceBytes: 3000n});
const unavailable = {code: 'InferOriginalMetadataAcquisitionUnavailable'};

test('pre-park Store bootstrap borrows exact handed-off Scope without granting metadata or a park', async () => {
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl,
    'prepark-bootstrap', {metadataAcquisition: declared(),
      storeBootstrap: {maxWireBytes: 4096, maxDirectoryEntries: 22}});
  const handle = f.operation.originalStoreBootstrapAcquisition();
  assert.strictEqual(f.operation.originalStoreBootstrapAcquisition(), handle);
  assert.equal(handle.kind, 'original-infer-store-bootstrap-acquisition');
  const selected = selectOriginalInferStoreBootstrapAcquisition(handle,
    'model-prepark-bootstrap', f.runDefinition.identity);
  assert.deepEqual(selected, {maxWireBytes: 4096, maxDirectoryEntries: 22});
  assert.ok(Object.isFrozen(selected));
  assert.throws(() => selectOriginalInferMetadataAcquisition(handle), unavailable);
  assert.throws(() => selectOriginalInferResourceCodecAcquisition(handle), unavailable);
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle, 'model-foreign'), unavailable);
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle,
    'model-prepark-bootstrap', 'sha256:' + '0'.repeat(64)), unavailable);
  for (const copy of [{...handle}, selected, true, undefined]) {
    assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(copy), unavailable);
  }
  // The handle is not a park and cannot follow the later phase transition.
  const park = f.operation.parkOriginalResources();
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle), unavailable);
  assert.throws(() => f.operation.originalStoreBootstrapAcquisition(), unavailable);
  const parked = f.operation.originalMetadataAcquisition(park);
  assert.notStrictEqual(parked, handle);
  assert.equal(f.sends(), 0);
  await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure');
  assert.equal(f.operation.cleanupPending(), true);
});

test('pre-park Store bootstrap refuses missing original shortage and cancellation without a new claim', async () => {
  for (const [name, extra] of [
    ['missing', {}],
    ['retained', {metadataAcquisition: {...declared(), retainedBytes: 7001n}}],
    ['workspace', {metadataAcquisition: {...declared(), workspaceBytes: 3001n}}],
    ['bootstrap', {metadataAcquisition: declared(), storeBootstrap: undefined}],
  ]) {
    const options = {storeBootstrap: {maxWireBytes: 4096, maxDirectoryEntries: 22}, ...extra};
    if (name === 'bootstrap') delete options.storeBootstrap;
    const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl,
      `prepark-${name}`, options);
    assert.throws(() => f.operation.originalStoreBootstrapAcquisition(), unavailable);
    assert.equal(f.sends(), 0);
  }
  const abort = new AbortController();
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl,
    'prepark-cancel', {metadataAcquisition: declared(),
      storeBootstrap: {maxWireBytes: 4096, maxDirectoryEntries: 22}, signal: abort.signal});
  const handle = f.operation.originalStoreBootstrapAcquisition();
  abort.abort();
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle), unavailable);
  assert.throws(() => f.operation.originalStoreBootstrapAcquisition(), unavailable);
  assert.equal(f.sends(), 0);
});

test('installed original metadata supplier uses one nominal handle and immutable whole envelope', async () => {
  const source = declared();
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl,
    'metadata-original', {metadataAcquisition: source});
  const park = f.operation.parkOriginalResources();
  const handle = f.operation.originalMetadataAcquisition(park);
  const selected = selectOriginalInferMetadataAcquisition(handle);
  assert.deepEqual(selected, declared());
  assert.ok(Object.isFrozen(selected) && Object.isFrozen(selected.metadata) && Object.isFrozen(selected.directory));
  source.metadata.maxWireBytes = 999999;
  source.directory.maxDirectoryEntries = 999999;
  source.retainedBytes = 999999n;
  assert.strictEqual(f.operation.originalMetadataAcquisition(park), handle);
  assert.strictEqual(selectOriginalInferMetadataAcquisition(handle), selected);
  assert.strictEqual(selectOriginalInferMetadataAcquisition(handle, 'model-metadata-original', f.runDefinition.identity), selected);
  assert.throws(() => selectOriginalInferMetadataAcquisition(handle, 'model-other'), unavailable);
  assert.throws(() => selectOriginalInferMetadataAcquisition(handle, 'model-metadata-original', 'sha256:' + '0'.repeat(64)), unavailable);
  for (const copied of [undefined, true, 'sha256:' + '0'.repeat(64), {...handle}, selected,
    {current: () => true, ...handle}]) {
    assert.throws(() => selectOriginalInferMetadataAcquisition(copied), unavailable);
  }
  assert.throws(() => f.operation.originalMetadataAcquisition({...park}), unavailable);
  assert.equal(f.sends(), 0);
  await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure');
  // A pending close is not resource release. The original record remains held,
  // but current acquisition is refused; it does not issue another operation.
  assert.equal(f.operation.cleanupPending(), true);
  assert.throws(() => selectOriginalInferMetadataAcquisition(handle), unavailable);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
});

test('metadata supplier missing copied foreign selection and same token capacity shortage refuse before I/O', async () => {
  for (const [name, options] of [
    ['missing', {}],
    ['copied-original', {metadataAcquisition: declared(), copiedOriginal: true}],
    ['copied-selection', {metadataAcquisition: declared(), copiedNodeInstallation: true}],
    ['retained-shortage', {metadataAcquisition: {...declared(), retainedBytes: 7001n}}],
    ['workspace-shortage', {metadataAcquisition: {...declared(), workspaceBytes: 3001n}}],
  ]) {
    const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl, `metadata-${name}`, options);
    const park = f.operation.parkOriginalResources();
    assert.throws(() => f.operation.originalMetadataAcquisition(park), unavailable);
    assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
    assert.equal(f.sends(), 0);
    await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure');
    assert.equal(f.operation.cleanupPending(), true);
  }
});

test('separate Store bootstrap limits use the same nominal handle and immutable original', async () => {
  const bootstrap = {maxWireBytes: 4096, maxDirectoryEntries: 8};
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl,
    'store-bootstrap', {metadataAcquisition: declared(), storeBootstrap: bootstrap});
  assert.deepEqual(Object.keys(f.selected).sort(),
    ['installation', 'layout', 'layoutArtifactCid', 'probability', 'runtimeArtifactCid']);
  const park = f.operation.parkOriginalResources();
  const handle = f.operation.originalMetadataAcquisition(park);
  const selected = selectOriginalInferStoreBootstrapAcquisition(handle,
    'model-store-bootstrap', f.runDefinition.identity);
  assert.deepEqual(selected, {maxWireBytes: 4096, maxDirectoryEntries: 8});
  assert.ok(Object.isFrozen(selected));
  assert.notStrictEqual(selected, selectOriginalInferMetadataAcquisition(handle).directory);
  bootstrap.maxWireBytes = 999999;
  bootstrap.maxDirectoryEntries = 999999;
  assert.strictEqual(selectOriginalInferStoreBootstrapAcquisition(handle), selected);
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle, 'model-other'), unavailable);
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle,
    'model-store-bootstrap', 'sha256:' + '0'.repeat(64)), unavailable);
  for (const copied of [undefined, true, 'sha256:' + '0'.repeat(64), {...handle}, selected]) {
    assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(copied), unavailable);
  }
  await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure');
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle), unavailable);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
});

test('missing Store bootstrap does not borrow metadata clamps or widen the same original capacity', async () => {
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl,
    'store-bootstrap-missing', {metadataAcquisition: declared()});
  const park = f.operation.parkOriginalResources();
  const handle = f.operation.originalMetadataAcquisition(park);
  assert.deepEqual(selectOriginalInferMetadataAcquisition(handle), declared());
  assert.throws(() => selectOriginalInferStoreBootstrapAcquisition(handle), unavailable);
  for (const [name, change] of [['retained', {retainedBytes: 7001n}], ['workspace', {workspaceBytes: 3001n}]]) {
    const short = await currentResourceFixture(moon, runtimeCore(moon).publicationControl,
      `store-bootstrap-${name}`, {metadataAcquisition: {...declared(), ...change},
        storeBootstrap: {maxWireBytes: 4096, maxDirectoryEntries: 8}});
    const shortPark = short.operation.parkOriginalResources();
    assert.throws(() => short.operation.originalMetadataAcquisition(shortPark), unavailable);
    await assert.rejects(short.operation.close(), error => error.code === 'MoonBitHostFailure');
    assert.equal(short.sends(), 0);
  }
  await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure');
  assert.equal(f.sends(), 0);
});

test('Store bootstrap declaration rejects missing NULL unknown fields and invalid finite limits', async () => {
  for (const invalid of [null, {}, {maxWireBytes: 4096}, {maxDirectoryEntries: 8},
    {maxWireBytes: 4096, maxDirectoryEntries: 8, extra: true},
    {maxWireBytes: 0, maxDirectoryEntries: 8}, {maxWireBytes: -1, maxDirectoryEntries: 8},
    {maxWireBytes: 4096, maxDirectoryEntries: -1}, {maxWireBytes: 4096, maxDirectoryEntries: 1.5},
    {maxWireBytes: Number.MAX_SAFE_INTEGER + 1, maxDirectoryEntries: 8}]) {
    await assert.rejects(currentResourceFixture(moon, runtimeCore(moon).publicationControl,
      'store-bootstrap-invalid', {metadataAcquisition: declared(), storeBootstrap: invalid}),
    {name: 'TypeError', message: 'InvalidInstalledInferStoreBootstrap'});
  }
});
