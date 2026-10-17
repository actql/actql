// The actual portable original request owner, not an installed approval or
// permission supplier. No service read, dispatch or replacement preparation.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {admitGcsObjectMetadata, prepareGcsObjectBinding,
  prepareOwnedGcsEffectMetadataPatch, projectOwnedGcsMetadataPatchTarget}
  from '../site/gcs-owned-object-request.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16};
const prepare = metadata => {
  const binding = prepareGcsObjectBinding(moon, {kind: 'patch_metadata', bucket: 'bucket', prefix: 'in/',
    catalogCid: cid('a'), installationCid: cid('b'), contractCid: cid('c'),
    permissions: ['storage.objects.update'], metadata: limits,
    maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384});
  const original = admitGcsObjectMetadata(moon, {bucket: 'bucket', prefix: 'in/', name: 'in/a', limits,
    bytes: Buffer.from(JSON.stringify({bucket: 'bucket', name: 'in/a', generation: '1',
      metageneration: '2', size: '7', ...(metadata === undefined ? {} : {metadata})}))});
  return prepareOwnedGcsEffectMetadataPatch({moon, binding, original, value: {content_type: 'text/csv'},
    marker: cid('d'), maxProjectionBytes: 8192});
};

test('same original PATCH exposes effective NULL-to-empty map separately from authored changes', () => {
  const request = prepare(undefined);
  const row = projectOwnedGcsMetadataPatchTarget(request, 8192);
  assert.deepEqual(row.before, {content_type: null, metadata: null});
  assert.deepEqual(row.after, {content_type: 'text/csv', metadata: {$json: {}}});
  assert.deepEqual(row.value, {content_type: 'text/csv'});
  const body = `{"contentType":"text/csv","metadata":{"actql-request":"${cid('d')}"}}`;
  assert.equal(request.body, body);
  const originalIdentity = JSON.stringify({body, catalog_cid: cid('a'), contract_cid: cid('c'),
    installation_cid: cid('b'), method: 'PATCH',
    path: '/storage/v1/b/bucket/o/in%2Fa?ifGenerationMatch=1&ifMetagenerationMatch=2',
    permissions: ['storage.objects.update'], resource_origin: 'https://storage.googleapis.com',
    version: 'actql-gcs-object-mutation-request/0.1'});
  assert.equal(request.request_cid, `sha256:${createHash('sha256').update(originalIdentity).digest('hex')}`);
  assert.equal(row.requestCid, request.request_cid);
  assert.ok(Object.isFrozen(row.after.metadata.$json));
  assert.ok(!JSON.stringify(row).includes(cid('d')));
});

test('same original PATCH never substitutes NULL for an already present empty user map', () => {
  for (const metadata of [{}, {'actql-request': 'previous-marker'}]) {
    const request = prepare(metadata), row = projectOwnedGcsMetadataPatchTarget(request, 8192);
    assert.deepEqual(row.before, {content_type: null});
    assert.deepEqual(row.after, {content_type: 'text/csv'});
    assert.deepEqual(row.value, {content_type: 'text/csv'});
    assert.equal(row.requestCid, request.request_cid);
  }
});
