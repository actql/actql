// Selected portable GCS Owner only; no normal permission or physical I/O.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsObjectBinding, admitGcsObjectMetadata,
  prepareOwnedGcsEffectMetadataPatch, prepareOwnedGcsMetadataPatch, prepareOwnedGcsObjectDelete,
  projectOwnedGcsMetadataPatchTarget, createGcsMutationRequestChild,
  recheckOwnedGcsObjectRequest} from '../site/gcs-owned-object-request.mjs';
const cid = char => `sha256:${char.repeat(64)}`;
const name = 'in/é%2F.csv';
const metadata = {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16};
const config = extra => ({kind: 'patch_metadata', bucket: 'bucket', prefix: 'in/',
  catalogCid: cid('a'), installationCid: cid('b'), contractCid: cid('c'),
  permissions: ['storage.objects.update'], metadata, maxPathBytes: 4096,
  maxBodyBytes: 8192, maxIdentityBytes: 16384, ...extra});
const body = extra => Buffer.from(JSON.stringify({bucket: 'bucket', name,
  generation: '9007199254740993', metageneration: '2', size: '7',
  metadata: {drop: 'old', keep: 'kept', 'actql-request': 'old'}, ...extra}));
const read = bytes => admitGcsObjectMetadata(moon, {bytes, bucket: 'bucket', prefix: 'in/', name, limits: metadata});
const value = () => ({content_type: 'text/csv', metadata: {$json: {keep: 'kept', new: '=é\r\n'}}});
function prepared({bytes = body(), changes = value(), selected = moon} = {}) {
  const binding = prepareGcsObjectBinding(selected, config());
  const request = prepareOwnedGcsEffectMetadataPatch({moon: selected, binding, original: read(bytes),
    value: changes, marker: cid('d'), maxProjectionBytes: 8192});
  return {binding, request};
}

test('GCS initial target projection preserves the same original response CID and checked Value facts', () => {
  const {request, binding} = prepared();
  const row = projectOwnedGcsMetadataPatchTarget(request, 8192, binding);
  assert.deepEqual(row, {identity: name,
    versionCid: 'sha256:a255da12181025e4a6ce594ad9ab3fb7a672ba774bf81b8277cba04294e94fed',
    before: {content_type: null, metadata: {$json: {drop: 'old', keep: 'kept'}}},
    after: value(), value: value(), requestCid: 'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179',
    protocol_behavior: 'assign_original_request_marker:actql-request'});
  assert.ok(Object.isFrozen(row.before.metadata.$json));
  assert.ok(!JSON.stringify(row).includes(cid('d')));
  const bytes = Buffer.byteLength(JSON.stringify(row));
  assert.deepEqual(projectOwnedGcsMetadataPatchTarget(request, bytes), row);
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(request, bytes - 1), {code: 'GcsObjectRequestCapacityExceeded'});
});

test('GCS initial target projection distinguishes missing empty and omitted fields without default metadata', () => {
  const project = (bytes, changes) => projectOwnedGcsMetadataPatchTarget(prepared({bytes, changes}).request, 8192);
  assert.deepEqual(project(body({metadata: undefined}), {metadata: {$json: {}}}).before, {metadata: null});
  assert.deepEqual(project(body({metadata: {}}), {metadata: {$json: {}}}).before, {metadata: {$json: {}}});
  assert.deepEqual(project(body(), {}).before, {});
  assert.deepEqual(project(body({contentType: 'application/old'}), {content_type: 'text/new'}).before,
    {content_type: 'application/old'});
});

test('GCS target projection never substitutes copies foreign permission binding raw values or delete purpose', () => {
  const {request, binding} = prepared();
  assert.throws(() => projectOwnedGcsMetadataPatchTarget({...request}, 8192), {code: 'ForeignGcsObjectRequest'});
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(request, 8192, prepareGcsObjectBinding(moon, config())),
    {code: 'GcsForeignObjectBinding'});
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(request, 8192,
    prepareGcsObjectBinding(moon, config({permissions: ['different.permission']}))), {code: 'GcsForeignObjectBinding'});
  const raw = prepareOwnedGcsMetadataPatch({moon, binding, original: read(body()),
    value: {metadata: {key: 'raw-map'}}, marker: cid('d'), maxProjectionBytes: 8192});
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(raw, 8192), {code: 'GcsInvalidObjectChanges'});
  const deleting = prepareGcsObjectBinding(moon, config({kind: 'delete', permissions: ['storage.objects.delete']}));
  const deleted = prepareOwnedGcsObjectDelete({moon, binding: deleting, original: read(body()), maxProjectionBytes: 8192});
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(deleted, 8192), {code: 'GcsInvalidObjectBinding'});
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(request, 0), {code: 'InvalidGcsObjectAbiLimits'});
  const missing = prepared({selected: {...moon, gcsObjectPatchEffectTarget: undefined}}).request;
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(missing, 8192), {code: 'GcsOriginalMutationPreparationUnavailable'});
});

test('GCS response guard includes metadata-only change and does not replace the conditional apply fence', () => {
  const {request, binding} = prepared();
  const first = projectOwnedGcsMetadataPatchTarget(request, 8192);
  const changedBody = body({metageneration: '3'});
  const changed = projectOwnedGcsMetadataPatchTarget(prepared({bytes: changedBody}).request, 8192);
  assert.equal(changed.versionCid, `sha256:${createHash('sha256').update(changedBody).digest('hex')}`);
  assert.notEqual(changed.versionCid, first.versionCid);
  assert.throws(() => recheckOwnedGcsObjectRequest(request, read(changedBody), binding), {code: 'GcsStaleObjectObservation'});
  assert.equal(projectOwnedGcsMetadataPatchTarget(request, 8192).versionCid, first.versionCid);
  assert.ok(request.path.endsWith('ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2'));
});

test('GCS capture target projects the child original GET without replacement read and refuses after retirement', async () => {
  const scope = {issuerAuthority: 'fixture', principal: 'operator', namespaceId: 'fixture', environment: 'test',
    siteKey: 'site', siteGeneration: 1, runtimeBundleCid: cid('a'), connectorRegistration: 'gcs',
    connectorRevision: 'gcs/0.1', resourceOrigin: 'https://storage.googleapis.com', operation: 'gcs:file:read',
    runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: BigInt(Date.now() + 60000), maxUses: 1};
  let calls = 0, approvals = 0;
  const child = createGcsMutationRequestChild({moon, binding: prepareGcsObjectBinding(moon, config()),
    kind: 'patch_metadata', name, value: value(), valueEncoding: 'effect_value', marker: cid('d'),
    maxProjectionBytes: 8192, maxRequestBytes: 4096, maxSecretBytes: 128,
    credential: {control: {identity: () => cid('a')}, journal: {claim() {}, authorize() {}, finish() {}},
      resolveSecret: async () => 'fixture-only'}, assertCurrent() {},
    authorizationForRow: async () => {approvals++;return {scope, grant: {}, useId: 'original-read'};},
    callResource: async () => {calls++;return {accepted: true, statusCode: 200, useCid: cid('e'), body: body(), headers: []};}});
  const {request} = await child.prepare();
  const row = projectOwnedGcsMetadataPatchTarget(request, 8192);
  assert.deepEqual(projectOwnedGcsMetadataPatchTarget(request, 8192), row);
  assert.equal(calls, 1);assert.equal(approvals, 1);
  assert.equal(await child.release(), true);
  assert.throws(() => projectOwnedGcsMetadataPatchTarget(request, 8192), {code: 'ForeignGcsObjectRequest'});
  assert.equal(calls, 1);
});
