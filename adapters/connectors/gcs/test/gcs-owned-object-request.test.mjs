// Real compiled Connector Owner and actual scoped-invocation boundary. The
// physical counter port is explicit: this is not Core approval or GCS service.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {admitGcsObjectMetadata, projectGcsObjectMetadata, prepareGcsObjectBinding,
  prepareOwnedGcsMetadataPatch, prepareOwnedGcsObjectDelete, ownedGcsObjectRequestCid,
  recheckOwnedGcsObjectRequest, sendOwnedGcsObjectRequest} from '../site/gcs-owned-object-request.mjs';

const metadata = Object.freeze({maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16});
const marker = `sha256:${'d'.repeat(64)}`;
const scope = Object.freeze({resourceOrigin: 'https://storage.googleapis.com',
  operation: 'gcs:object:metadata:update'});
const auth = overrides => ({grant: {}, useId: 'original-claim-use', scope: {...scope, ...overrides}});
const config = overrides => ({kind: 'patch_metadata', bucket: 'bucket', prefix: 'in/',
  catalogCid: `sha256:${'a'.repeat(64)}`, installationCid: `sha256:${'b'.repeat(64)}`,
  contractCid: `sha256:${'c'.repeat(64)}`, permissions: ['storage.objects.update'],
  metadata, maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384, ...overrides});
const read = (overrides = {}) => admitGcsObjectMetadata(moon, {bucket: 'bucket', prefix: 'in/',
  limits: metadata, bytes: Buffer.from(JSON.stringify({bucket: 'bucket', name: 'in/e\u0301%2F.csv',
    generation: '9007199254740993', metageneration: '2', size: '7',
    metadata: {drop: 'old', keep: 'kept', 'actql-request': 'old'}, ...overrides}))});
const value = () => ({content_type: 'text/csv', metadata: {keep: 'kept', new: '=e\u0301\r\n'}});
function request(overrides = {}) {
  const binding = prepareGcsObjectBinding(moon, config());
  return {binding, request: prepareOwnedGcsMetadataPatch({moon, binding, original: read(),
    value: value(), marker, maxProjectionBytes: 8192, ...overrides})};
}
const send = (request, callResource, extra = {}) => sendOwnedGcsObjectRequest({request,
  authorization: auth(), credential: {journal: {physicalCounterOnly: true}}, callResource,
  maxRequestBytes: 16384, maxResponseBytes: 8192, ...extra});

test('real GCS owner exports exact metadata/Preview and independently pinned request bytes', () => {
  const {request: r} = request();
  assert.equal(r.before.generation, '9007199254740993');
  assert.deepEqual(r.before.metadata, {drop: 'old', keep: 'kept'});
  assert.deepEqual(r.after.metadata, value().metadata);
  assert.deepEqual(r.value, value());
  assert.equal(r.protocol_behavior, 'assign_original_request_marker:actql-request');
  assert.equal(r.body, `{"contentType":"text/csv","metadata":{"actql-request":"${marker}","drop":null,"keep":"kept","new":"=é\\r\\n"}}`);
  assert.equal(ownedGcsObjectRequestCid(r),
    'sha256:c59b859de44ff44255e356a9e72ef80d640b1a28590984e629d474a91f895179');
  assert.ok(Object.isFrozen(r.after.metadata));
  assert.equal(projectGcsObjectMetadata(moon, read(), metadata).generation, '9007199254740993');
  assert.equal(r.outcome, undefined);
});

test('authored marker collisions including the identical marker refuse before physical I/O', () => {
  for (const token of ['foreign', marker]) {
    assert.throws(() => request({value: {metadata: {'actql-request': token}}}),
      {code: 'GcsReservedRequestMetadata'});
  }
  for (const change of [{metadata: null}, {metadata: {key: null}}, {content_type: null}]) {
    assert.throws(() => request({value: change}), {code: 'GcsInvalidObjectChanges'});
  }
});

test('case prefixes and distinct NFC/NFD user keys survive the real compiled boundary', () => {
  const keys = {'Actql-request': 'case', 'actql-request-extra': 'prefix',
    'e\u0301': 'NFD', 'é': 'NFC'};
  const {request: r} = request({value: {metadata: keys}});
  assert.deepEqual(r.value.metadata, keys);
  assert.deepEqual(r.after.metadata, keys);
  assert.ok(r.body.includes('"drop":null'));
  assert.ok(r.body.includes('"keep":null'));
});

test('copies and another same-data binding cannot borrow an original request', () => {
  const {request: r} = request();
  assert.throws(() => ownedGcsObjectRequestCid({...r}), {code: 'ForeignGcsObjectRequest'});
  assert.throws(() => ownedGcsObjectRequestCid(r,
    prepareGcsObjectBinding(moon, config())), {code: 'GcsForeignObjectBinding'});
  assert.throws(() => ownedGcsObjectRequestCid(r,
    prepareGcsObjectBinding(moon, config({permissions: ['different.permission']}))),
  {code: 'GcsForeignObjectBinding'});
});

test('same original generation/metageneration are rechecked without adopting another head', () => {
  const {request: r, binding} = request();
  recheckOwnedGcsObjectRequest(r, read(), binding);
  assert.throws(() => recheckOwnedGcsObjectRequest(r, read({metageneration: '3'}), binding),
    {code: 'GcsStaleObjectObservation'});
  assert.throws(() => recheckOwnedGcsObjectRequest(r, read({generation: '9007199254740994'}), binding),
    {code: 'GcsStaleObjectObservation'});
});

test('one scoped invocation retains original response backing without interpreting apply', async () => {
  const {request: r} = request();
  const body = Buffer.from('retained original response');
  const headers = [['x-goog-metageneration', '3']];
  let calls = 0;
  const result = await send(r, async invocation => {
    calls++;
    assert.equal(invocation.returnRejectedResponse, true);
    assert.equal(invocation.scope.operation, r.operation);
    assert.equal(invocation.maxResponseBytes, 8192);
    assert.deepEqual([...invocation.operations.keys()], [r.operation]);
    const physical = invocation.operations.get(r.operation);
    assert.equal(physical.method, 'PATCH');
    assert.equal(physical.path, r.path);
    assert.equal(physical.body, r.body);
    assert.ok(physical.path.endsWith('ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2'));
    return {accepted: true, useCid: 'physical-original', statusCode: 200, body, headers};
  });
  assert.equal(calls, 1);
  assert.equal(result.observation.body, body);
  assert.equal(result.headers, headers);
  assert.equal(result.observation.outcome, undefined);
});

test('lost response preserves the exact original failure with no local resend', async () => {
  const {request: r} = request();
  const primary = Object.defineProperty(new Error('lost original reply'), 'cleanupPending', {value: true});
  let calls = 0;
  await assert.rejects(send(r, async () => { calls++; throw primary; }), error => error === primary);
  assert.equal(calls, 1);
  assert.equal(primary.cleanupPending, true);
});

test('foreign scope and invalid physical clamps refuse before invoking a port', async () => {
  const {request: r} = request();
  let calls = 0;
  const port = async () => { calls++; assert.fail('must refuse before physical acquisition'); };
  await assert.rejects(send(r, port, {authorization: auth({operation: 'different'})}),
    {code: 'ForeignGcsObjectAuthorization'});
  await assert.rejects(send(r, port, {authorization: auth({resourceOrigin: 'https://foreign.example'})}),
    {code: 'ForeignGcsObjectAuthorization'});
  for (const maxResponseBytes of [0, -1, 1.5, 4294967296]) {
    await assert.rejects(send(r, port, {maxResponseBytes}), {code: 'InvalidGcsObjectTransportLimits'});
  }
  assert.equal(calls, 0);
});

test('bodyless delete preserves a rejected original response without creating a receipt', async () => {
  const binding = prepareGcsObjectBinding(moon, config({kind: 'delete'}));
  const r = prepareOwnedGcsObjectDelete({moon, binding, original: read(), maxProjectionBytes: 8192});
  const body = Buffer.from('precondition failed');
  const result = await send(r, async invocation => {
    assert.equal(invocation.operations.get(r.operation).body, undefined);
    return {accepted: false, statusCode: 412, body, useCid: 'original-rejection', headers: []};
  }, {authorization: auth({operation: 'gcs:object:delete'})});
  assert.equal(result.observation.body, body);
  assert.equal(result.observation.statusCode, 412);
  assert.equal(result.observation.accepted, false);
  assert.equal(result.outcome, undefined);
});
