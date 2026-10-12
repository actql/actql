// Actual compiled original Scope/Model checks with explicitly synthetic
// installation amounts. No heap adequacy, new reservation or public profile.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';
import {selectOriginalInferMetadataAcquisition} from './infer-operation.mjs';

const declared = () => ({metadata: {maxWireBytes: 512, maxLedgerEntries: 3},
  directory: {maxWireBytes: 512, maxDirectoryEntries: 4},
  retainedBytes: 7000n, workspaceBytes: 3000n});
const unavailable = {code: 'InferOriginalMetadataAcquisitionUnavailable'};

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
