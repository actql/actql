// Actual Common original Scope with synthetic byte declarations. No physical
// Store, Provider, normal profile, restoration or send authority is issued.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';
import {selectOriginalInferResourceCodecAcquisition} from './infer-operation.mjs';

const codec = Object.freeze({quantum: 1, comparisonWork: 5,
  decode: Object.freeze({maxWork: 20000,
    parse: Object.freeze({max_input_bytes: 4096, max_nodes: 100, max_depth: 20}),
    tree: Object.freeze({max_nodes: 100, max_depth: 20, max_string_bytes: 4096, max_total_string_bytes: 4096})})});
const metadata = {metadata: {maxWireBytes: 1024, maxLedgerEntries: 4},
  directory: {maxWireBytes: 1024, maxDirectoryEntries: 8}, retainedBytes: 7000n, workspaceBytes: 3000n};

test('original resource codec selection borrows the same installation and current Scope only', async () => {
  const abort = new AbortController();
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl, 'codec-original',
    {metadataAcquisition: metadata, currentStateCodec: codec, signal: abort.signal});
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const handle = f.operation.originalMetadataAcquisition(park);
  const selected = selectOriginalInferResourceCodecAcquisition(handle, 'model-codec-original', f.runDefinition.identity);
  assert.strictEqual(selected, f.originalPreparation.metadataInstallation.currentStateCodec);
  assert.equal(selected.decode.parse.max_input_bytes, 4096);
  assert.equal(f.originalPreparation.metadataInstallation.metadataAcquisition.metadata.maxWireBytes, 1024);
  for (const foreign of [undefined, true, {...handle}]) {
    assert.throws(() => selectOriginalInferResourceCodecAcquisition(foreign),
      {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  }
  assert.throws(() => selectOriginalInferResourceCodecAcquisition(handle, 'model-foreign', f.runDefinition.identity),
    {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  assert.throws(() => selectOriginalInferResourceCodecAcquisition(handle, 'model-codec-original', 'sha256:'+'0'.repeat(64)),
    {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  abort.abort();
  assert.throws(() => selectOriginalInferResourceCodecAcquisition(handle),
    {code: 'InferOriginalMetadataAcquisitionUnavailable'});
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
});

test('missing original resource codec is unavailable rather than a metadata or legacy fallback', async () => {
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl, 'codec-missing',
    {metadataAcquisition: metadata});
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const handle = f.operation.originalMetadataAcquisition(park);
  assert.throws(() => selectOriginalInferResourceCodecAcquisition(handle),
    {code: 'InferOriginalStateCodecUnavailable'});
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
});
