// Actual compiled DATA recovery. The surrounding capture/Store must separately
// authenticate retained material and bind the current installed originals.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {runtimePair} from '../../../host-common/compiler-binding.generated.mjs';
import {gcsOwnedResult, prepareGcsObjectBinding, admitGcsObjectMetadata,
  prepareOwnedGcsEffectMetadataPatch, prepareOwnedGcsObjectDelete,
  projectOwnedGcsObjectRequest, ownedGcsObjectRequestCid,
  borrowOwnedGcsMetadataPatchTarget, borrowOwnedGcsObjectDeleteTarget,
  restoreOwnedGcsObjectMutationRequest} from '../site/gcs-owned-object-request.mjs';

const artifact = new URL('../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js', import.meta.url);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
assert(lstatSync(artifact).isFile());
const originalArtifactHash = hash(readFileSync(artifact));
const cid = character => `sha256:${character.repeat(64)}`;
const metadata = {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16};
const raw = Buffer.from('{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"2","size":"7","metadata":{"drop":"old","keep":"kept","actql-request":"old"}}');
const changes = Buffer.from('{"content_type":"text/csv","metadata":{"$json":{"keep":"kept","new":"=é\\r\\n"}}}');
const binding = kind => prepareGcsObjectBinding(moon, {
  kind, bucket: 'bucket', prefix: 'in/', catalogCid: cid('a'),
  installationCid: cid('b'), contractCid: cid('c'), permissions: ['storage.objects.update'],
  metadata, maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384});
function original(kind = 'patch_metadata') {
  const owner = binding(kind);
  const before = admitGcsObjectMetadata(moon, {bytes: raw, bucket: 'bucket', prefix: 'in/',
    name: 'in/é%2F.csv', limits: metadata});
  const request = kind === 'delete' ? prepareOwnedGcsObjectDelete({moon, binding: owner,
    original: before, maxProjectionBytes: 8192}) : prepareOwnedGcsEffectMetadataPatch({moon,
    binding: owner, original: before, value: JSON.parse(changes), marker: cid('d'), maxProjectionBytes: 8192});
  return {owner, request};
}
function restore(owner, request, overrides = {}) {
  const input = {name: 'in/é%2F.csv', status: 200, headers: [], response: raw,
    responseHash: hash(raw), changes: Buffer.from(JSON.stringify(request.value)),
    body: request.body, requestCid: request.request_cid, ...overrides};
  const handle = gcsOwnedResult(moon, moon.gcsObjectRestoreMutationValue(owner,
    input.name, input.status, input.headers.map(([name, value]) => runtimePair(name, value)),
    input.response, input.responseHash, input.changes, input.body, input.requestCid));
  return projectOwnedGcsObjectRequest(moon, owner, handle, 8192);
}
test.after(() => assert.equal(hash(readFileSync(artifact)), originalArtifactHash,
  'the actual imported runtime must remain unchanged'));

test('actual GCS recovery preserves independent request bytes and fresh local binding membership', () => {
  const {owner, request} = original();
  const local = binding('patch_metadata');
  const restored = restore(local, request);
  assert.equal(restored.request_cid, 'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.equal(restored.body, request.body);
  assert.equal(restored.path, request.path);
  assert.deepEqual(restored.value, request.value);
  assert.equal(ownedGcsObjectRequestCid(restored, local), request.request_cid);
  assert.throws(() => ownedGcsObjectRequestCid(request, local), {code: 'GcsForeignObjectBinding'});
  assert.throws(() => ownedGcsObjectRequestCid(restored, owner), {code: 'GcsForeignObjectBinding'});
  // A re-admitted DATA request does not issue the live child's current closure.
  assert.throws(() => borrowOwnedGcsMetadataPatchTarget(restored, 8192, local),
    {code: 'GcsOriginalMutationPreparationUnavailable'});
});

test('actual GCS recovery refuses equal-field raw replacement and changed exact intent', () => {
  const {owner, request} = original();
  assert.throws(() => restore(owner, request, {response: Buffer.concat([Buffer.from(' '), raw])}),
    {code: 'GcsStaleObjectObservation'});
  assert.throws(() => restore(owner, request, {body: ' ' + request.body}),
    {code: 'GcsInvalidObjectChanges'});
  assert.throws(() => restore(owner, request, {changes: Buffer.from(' ' + changes)}),
    {code: 'GcsInvalidObjectChanges'});
  assert.throws(() => restore(owner, request, {body: request.body.replace(cid('d'), cid('e'))}),
    {code: 'GcsInvalidObjectChanges'});
});

test('actual GCS recovery rechecks original target status encoding and version headers', () => {
  const {owner, request} = original();
  for (const overrides of [{status: 404}, {headers: [['content-encoding', 'gzip']]},
    {headers: [['x-goog-generation', '1']]}, {headers: [['x-goog-metageneration', '3']]}]) {
    assert.throws(() => restore(owner, request, overrides), {code: 'GcsInvalidObjectChanges'});
  }
  assert.throws(() => restore(owner, request, {name: 'in/other'}), {code: 'GcsForeignObjectBinding'});
});

test('actual GCS DELETE recovery has no invented after response or nonempty changes', () => {
  const {owner, request} = original('delete');
  const restored = restore(owner, request);
  assert.equal(restored.method, 'DELETE');
  assert.equal(restored.body, '');
  assert.equal(restored.after, null);
  assert.deepEqual(restored.value, {});
  assert.throws(() => restore(owner, request, {changes: Buffer.from(' {}')}),
    {code: 'GcsInvalidObjectChanges'});
});

function restoreCaller(owner, request, overrides = {}, runtime = moon) {
  return restoreOwnedGcsObjectMutationRequest({moon: runtime, binding: owner,
    name: 'in/é%2F.csv', responseStatus: 200, responseHeaders: [],
    responseBytes: raw, responseSha256: hash(raw),
    changesBytes: Buffer.from(JSON.stringify(request.value)), body: request.body,
    requestCid: request.request_cid, maxProjectionBytes: 8192, ...overrides});
}

for (const kind of ['patch_metadata', 'delete']) {
  test(`private ${kind} restore caller keeps exact bytes and only new local membership`, () => {
    const {owner, request} = original(kind), local = binding(kind);
    const restored = restoreCaller(local, request);
    assert.deepEqual(restored, request);
    assert.equal(ownedGcsObjectRequestCid(restored, local), request.request_cid);
    assert.throws(() => ownedGcsObjectRequestCid(restored, owner),
      {code: 'GcsForeignObjectBinding'});
    assert.throws(() => ownedGcsObjectRequestCid({...restored}, local),
      {code: 'ForeignGcsObjectRequest'});
    const borrow = kind === 'delete'
      ? borrowOwnedGcsObjectDeleteTarget : borrowOwnedGcsMetadataPatchTarget;
    assert.throws(() => borrow(restored, 8192, local),
      {code: 'GcsOriginalMutationPreparationUnavailable'});
  });

  test(`private ${kind} restore refuses replaced raw or conditional request material`, () => {
    const {owner, request} = original(kind);
    for (const overrides of [
      {responseBytes: Buffer.concat([Buffer.from(' '), raw])},
      {responseSha256: '0'.repeat(64)},
    ]) assert.throws(() => restoreCaller(owner, request, overrides),
      {code: 'GcsStaleObjectObservation'});
    for (const overrides of [
      {body: ' ' + request.body},
      {changesBytes: Buffer.from(' ' + JSON.stringify(request.value))},
      {requestCid: cid('e')},
      {responseStatus: 404},
      {responseHeaders: [['content-encoding', 'gzip']]},
      {responseHeaders: [['x-goog-generation', '1']]},
    ]) assert.throws(() => restoreCaller(owner, request, overrides),
      {code: 'GcsInvalidObjectChanges'});
  });
}

test('private restore rejects shared backing and incomplete material before Core', () => {
  const {owner, request} = original();
  let calls = 0;
  const runtime = {...moon, gcsObjectRestoreMutationValue() {
    calls++; assert.fail('Invalid byte/header/extent input must refuse before Core');
  }};
  for (const overrides of [
    {responseBytes: new Uint8Array(new SharedArrayBuffer(raw.length))},
    {changesBytes: new Uint8Array(new SharedArrayBuffer(2))},
    {responseBytes: undefined}, {changesBytes: null},
    {responseHeaders: undefined}, {responseHeaders: [['x-goog-generation', 1]]},
    {responseHeaders: Array.from({length: 4}, () => ['x-goog-generation', '1'])},
    {responseStatus: undefined}, {body: undefined}, {maxProjectionBytes: 0},
  ]) assert.throws(() => restoreCaller(owner, request, overrides, runtime),
    {code: 'InvalidGcsObjectRecovery'});
  assert.equal(calls, 0);
  assert.throws(() => restoreCaller(owner, request, {},
    {...moon, gcsObjectRestoreMutationValue: undefined}),
  {code: 'GcsOriginalMutationRecoveryUnavailable'});
  assert.equal(ownedGcsObjectRequestCid(request, owner), request.request_cid,
    'refusal must not replace or retire the still-owned original request');
});
