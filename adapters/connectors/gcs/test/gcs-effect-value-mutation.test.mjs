// Actual selected GCS provider semantics; this is not Account/Store admission.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsObjectBinding, admitGcsObjectMetadata,
  prepareOwnedGcsEffectMetadataPatch, prepareOwnedGcsMetadataPatch,
  createGcsMutationRequestChild, ownedGcsObjectRequestCid} from '../site/gcs-owned-object-request.mjs';

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
  const request = prepareOwnedGcsEffectMetadataPatch({moon, binding: binding(), original: original(),
    value: {content_type: 'text/csv', metadata: {$json: {keep: 'kept', new: '=é\r\n'}}},
    marker: cid('d'), maxProjectionBytes: 8192});
  assert.equal(request.request_cid,
    'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.equal(request.body,
    '{"contentType":"text/csv","metadata":{"actql-request":"'+cid('d')+'","drop":null,"keep":"kept","new":"=é\\r\\n"}}');
  assert.deepEqual(request.value,
    {content_type: 'text/csv', metadata: {$json: {keep: 'kept', new: '=é\r\n'}}});
});

test('GCS Effect metadata wire keeps SQL NULL JSON null empty missing and user keys distinct', () => {
  const prepare = value => prepareOwnedGcsEffectMetadataPatch({moon, binding: binding(),
    original: original(), value, marker: cid('d'), maxProjectionBytes: 8192});
  for (const value of [{metadata: null}, {metadata: {$json: null}}, {metadata: {}},
    {metadata: {raw: 'map'}}, {metadata: {$json: {}, foreign: 'field'}},
    {metadata: {$json: {bad: 1}}}, {metadata: {$json: []}}]) {
    assert.throws(() => prepare(value), {code: 'GcsInvalidObjectChanges'});
  }
  assert.deepEqual(prepare({}).value, {});
  const empty = prepare({metadata: {$json: {}}});
  assert.deepEqual(empty.value, {metadata: {$json: {}}});
  assert.ok(empty.body.includes('"drop":null,"keep":null'));
  const opaque = prepare({metadata: {$json: {'$json': 'user-key', 'é': 'NFC', 'é': 'NFD\r\n'}}});
  assert.deepEqual(opaque.value.metadata.$json, {'$json': 'user-key', 'é': 'NFC', 'é': 'NFD\r\n'});
  assert.deepEqual(JSON.parse(opaque.body).metadata,
    {'actql-request': cid('d'), drop: null, keep: null, '$json': 'user-key', 'é': 'NFC', 'é': 'NFD\r\n'});
});

test('GCS explicit raw JSON and Effect Value entrypoints never guess each others encoding', () => {
  const options = {moon, binding: binding(), original: original(), marker: cid('d'), maxProjectionBytes: 8192};
  const raw = prepareOwnedGcsMetadataPatch({...options, value: {metadata: {'$json': 'user-key'}}});
  assert.deepEqual(raw.value, {metadata: {'$json': 'user-key'}});
  assert.throws(() => prepareOwnedGcsEffectMetadataPatch({...options, value: raw.value}),
    {code: 'GcsInvalidObjectChanges'});
  assert.throws(() => prepareOwnedGcsMetadataPatch({...options, value: {metadata: {$json: {key: 'value'}}}}),
    {code: 'GcsInvalidObjectChanges'});
});

const scope = Object.freeze({issuerAuthority: 'fixture', principal: 'operator', namespaceId: 'fixture',
  environment: 'test', siteKey: 'site', siteGeneration: 1, runtimeBundleCid: cid('a'),
  connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1', resourceOrigin: 'https://storage.googleapis.com',
  operation: 'gcs:file:read', runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
  expiresUnixMilliseconds: BigInt(Date.now() + 60000), maxUses: 1});
const childOptions = extra => ({moon, binding: binding(), kind: 'patch_metadata', name: 'in/é%2F.csv',
  value: {content_type: 'text/csv', metadata: {$json: {keep: 'kept', new: '=é\r\n'}}},
  valueEncoding: 'effect_value', marker: cid('d'), maxProjectionBytes: 8192, maxRequestBytes: 4096,
  maxSecretBytes: 128, credential: {control: {identity: () => cid('a')},
    journal: {claim() {}, authorize() {}, finish() {}}, resolveSecret: async () => 'fixture-only'},
  authorizationForRow: async () => ({scope, grant: {}, useId: 'original-target-read'}), assertCurrent() {},
  callResource: async () => ({accepted: true, statusCode: 200, useCid: cid('e'), headers: [],
    body: Buffer.from('{"bucket":"bucket","name":"in/é%2F.csv","generation":"9007199254740993","metageneration":"2","size":"7","metadata":{"drop":"old","keep":"kept","actql-request":"old"}}')}),
  ...extra});

test('GCS original Effect child preserves typed row facts and same request retirement', async () => {
  let reads = 0;
  const options = childOptions({});
  const child = createGcsMutationRequestChild({...options, callResource: async invocation => {
    reads++;return options.callResource(invocation);
  }});
  const {request, requestCid} = await child.prepare();
  assert.deepEqual(request.value, options.value);
  assert.equal(requestCid, 'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.equal(ownedGcsObjectRequestCid(request), requestCid);
  assert.equal(await child.release(), true);
  assert.throws(() => ownedGcsObjectRequestCid(request), {code: 'ForeignGcsObjectRequest'});
  assert.equal(reads, 1);
});

test('GCS authored collision and malformed Effect wire refuse before approval or GET', async () => {
  let approvals = 0, reads = 0;
  for (const extra of [
    {value: {metadata: {$json: {'actql-request': 'collision'}}}},
    {value: {metadata: {'actql-request': 'collision'}}, valueEncoding: 'source_json'},
    {value: {metadata: {$json: null}}}, {value: {metadata: {raw: 'map'}}},
    {valueEncoding: 'guess'}, {moon: {...moon, gcsObjectCheckPatchInput: undefined}},
    {moon: {...moon, gcsObjectPrepareEffectPatch: undefined}},
  ]) {
    const child = createGcsMutationRequestChild(childOptions({
      authorizationForRow: async () => {approvals++;assert.fail('Static refusal must precede original approval');},
      callResource: async () => {reads++;assert.fail('Static refusal must precede acquisition');}, ...extra}));
    await assert.rejects(child.prepare());
    assert.equal(await child.release(), true);
    assert.equal(child.status().pending, false);
  }
  assert.equal(approvals, 0);assert.equal(reads, 0);
});
