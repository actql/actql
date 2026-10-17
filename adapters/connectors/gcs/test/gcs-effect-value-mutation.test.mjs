// Actual selected GCS provider semantics; this is not Account/Store admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsObjectBinding, admitGcsObjectMetadata,
  prepareOwnedGcsMetadataPatch} from '../site/gcs-owned-object-request.mjs';

const cid = char => `sha256:${char.repeat(64)}`;
const metadata = {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16};
const binding = () => prepareGcsObjectBinding(moon, {kind: 'patch_metadata',
  bucket: 'bucket', prefix: 'in/', catalogCid: cid('a'), installationCid: cid('b'),
  contractCid: cid('c'), permissions: ['storage.objects.update'], metadata,
  maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384});
const original = () => admitGcsObjectMetadata(moon, {bytes: Buffer.from(
  '{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"2","size":"7","metadata":{"drop":"old","keep":"kept","actql-request":"old"}}'),
  bucket: 'bucket', prefix: 'in/', name: 'in/é%2F.csv', limits: metadata});

test('GCS Effect JSON wire preserves the original physical PATCH bytes and identity', () => {
  const request = prepareOwnedGcsMetadataPatch({moon, binding: binding(), original: original(),
    value: {content_type: 'text/csv', metadata: {$json: {keep: 'kept', new: '=é\r\n'}}},
    marker: cid('d'), maxProjectionBytes: 8192});
  assert.equal(request.request_cid,
    'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.equal(request.body,
    '{"contentType":"text/csv","metadata":{"actql-request":"'+cid('d')+'","drop":null,"keep":"kept","new":"=é\\r\\n"}}');
  assert.deepEqual(request.value,
    {content_type: 'text/csv', metadata: {$json: {keep: 'kept', new: '=é\r\n'}}});
});
