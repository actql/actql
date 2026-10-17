// Actual compiled GCS provider with explicit physical contract-control ports.
// This does not issue Core approval, funding or a service cleanup receipt.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsObjectBinding, readGcsObjectTarget, admitGcsObjectTargetObservation,
  projectGcsObjectMetadata, prepareOwnedGcsMetadataPatch} from '../site/gcs-owned-object-request.mjs';

const cid = c => `sha256:${c.repeat(64)}`;
const name = 'in/e\u0301%2F.csv';
const metadata = {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16};
const binding = extra => prepareGcsObjectBinding(moon, {kind: 'patch_metadata',
  bucket: 'bucket', prefix: 'in/', catalogCid: cid('a'), installationCid: cid('b'),
  contractCid: cid('c'), permissions: ['storage.objects.update'], metadata,
  maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384, ...extra});
const body = () => Buffer.from(JSON.stringify({bucket: 'bucket', name,
  generation: '9007199254740993', metageneration: '2', size: '7',
  metadata: {drop: 'old', keep: 'kept', 'actql-request': 'old'}}));
const auth = extra => ({grant: {}, useId: 'original-read', scope: {
  resourceOrigin: 'https://storage.googleapis.com', operation: 'gcs:file:read', ...extra}});
const read = (original, port, extra) => readGcsObjectTarget({moon, binding: original,
  name, authorization: auth(), credential: {}, maxRequestBytes: 4096,
  callResource: port, ...extra});

test('mutation target GET retains one original response before checked metadata and conditional request', async () => {
  const original = binding(), bytes = body();
  const headers = [['x-goog-generation', '9007199254740993'], ['x-goog-metageneration', '2']];
  let calls = 0;
  const response = await read(original, async invocation => {
    calls++;
    assert.equal(invocation.returnRejectedResponse, true);
    assert.equal(invocation.maxResponseBytes, 8192);
    assert.deepEqual([...invocation.operations.keys()], ['gcs:file:read']);
    const request = invocation.operations.get('gcs:file:read');
    assert.equal(request.method, 'GET');
    assert.equal(request.path, '/storage/v1/b/bucket/o/in%2Fe%CC%81%252F.csv');
    assert.equal(request.body, undefined);
    assert.deepEqual(request.headers, [['accept', 'application/json'], ['accept-encoding', 'identity']]);
    return {accepted: true, useCid: cid('e'), statusCode: 200, body: bytes, headers};
  });
  assert.equal(calls, 1);
  assert.equal(response.observation.body, bytes);
  assert.equal(response.headers, headers);
  assert.equal(response.before, undefined);
  const before = admitGcsObjectTargetObservation(moon, original, name, response);
  assert.deepEqual(projectGcsObjectMetadata(moon, before, metadata).metadata, {drop: 'old', keep: 'kept'});
  const request = prepareOwnedGcsMetadataPatch({moon, binding: original, original: before,
    value: {content_type: 'text/csv', metadata: {keep: 'kept', new: '=e\u0301\r\n'}},
    marker: cid('d'), maxProjectionBytes: 8192});
  assert.equal(request.request_cid, 'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.ok(request.path.endsWith('ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2'));
});

test('mutation target path scope clamp abort and missing ABI refuse before physical I/O', async () => {
  const original = binding();let calls = 0;
  const port = async () => {calls++;assert.fail('no acquisition');};
  for (const name of ['', 'outside/a', 'in/a\nb']) {
    await assert.rejects(read(original, port, {name}), {code: 'GcsInvalidObjectTargetName'});
  }
  await assert.rejects(read(original, port, {authorization: auth({operation: 'gcs:object:metadata:update'})}),
    {code: 'ForeignGcsObjectTargetReadAuthorization'});
  await assert.rejects(read(original, port, {maxRequestBytes: 0}), {code: 'GcsInvalidObjectTargetRead'});
  await assert.rejects(read(original, port, {moon: {}}), {code: 'GcsObjectTargetReadUnavailable'});
  await assert.rejects(read(binding({maxPathBytes: 30}), port), {code: 'GcsObjectTargetCapacityExceeded'});
  const controller = new AbortController();controller.abort();
  await assert.rejects(read(original, port, {signal: controller.signal}), {name: 'AbortError'});
  assert.equal(calls, 0);
});

test('mutation target lost read keeps the exact original cleanup failure with no retry', async () => {
  const failure = Object.freeze(Object.assign(new Error('lost reply'), {cleanupPending: true, cleanupHandle: {}}));
  let calls = 0;
  await assert.rejects(read(binding(), async () => {calls++;throw failure;}), error => error === failure);
  assert.equal(calls, 1);
  assert.equal(failure.cleanupPending, true);
});

test('mutation target missing partial contradictory and invalid byte responses never produce before', async () => {
  const original = binding();
  for (const [statusCode, accepted, bytes, headers] of [
    [404, false, Buffer.from('{}'), []], [404, true, Buffer.from('{}'), []],
    [206, true, body(), []], [200, true, Buffer.from([255]), []],
    [200, true, body(), [['x-goog-metageneration', '3']]],
    [200, true, body(), [['content-encoding', 'gzip']]],
  ]) {
    const response = await read(original, async () => ({statusCode, accepted, body: bytes, headers, useCid: cid('e')}));
    assert.equal(response.observation.body, bytes);
    assert.throws(() => admitGcsObjectTargetObservation(moon, original, name, response));
  }
});

test('mutation target malformed DATA rejects before invoking the typed provider', () => {
  let calls = 0;
  const provider = {gcsObjectTargetObservation() {calls++;assert.fail('invalid DATA');}};
  const valid = {observation: {accepted: true, statusCode: 200, useCid: cid('e'), body: body()}, headers: []};
  for (const observation of [{...valid.observation, accepted: false},
    {...valid.observation, useCid: 'copied'}, {...valid.observation, statusCode: 200.5},
    {...valid.observation, body: new Uint8Array(new SharedArrayBuffer(1))}]) {
    assert.throws(() => admitGcsObjectTargetObservation(provider, {}, name, {...valid, observation}),
      {code: 'GcsInvalidObjectTargetReadObservation'});
  }
  assert.equal(calls, 0);
});
