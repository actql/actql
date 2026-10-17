// Actual compiled GCS Owner; explicit credential/transport counters, not Core
// authorization, an installed Effect, a numerical profile or a GCS service.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsCollectionTarget, prepareGcsCollectionUploadBinding} from '../host/gcs-collection-target.mjs';
import {admitGcsUploadObservation} from '../site/gcs-owned-upload-request.mjs';
import {admitGcsObjectMetadata} from '../site/gcs-owned-object-request.mjs';
import {prepareGcsComposeBinding, prepareOwnedGcsComposition, ownedGcsCompositionBody,
  recheckOwnedGcsComposition, ownedGcsCompositionResponseMatches, sendOwnedGcsComposition,
  projectOwnedGcsCompositionResponse} from '../site/gcs-owned-compose-request.mjs';

const vectors = JSON.parse(readFileSync(new URL('./fixtures/compose-independent.json', import.meta.url))).vectors;
const token = digit => `sha256:${digit.repeat(64)}`;
const name = 'in/e\u0301%2F.bin', generation = '9007199254740993';
const metadata = Object.freeze({maxBytes: 8192, maxNodes: 100, maxDepth: 8, maxEntries: 4});
const limits = Object.freeze({metadata, maxContentBytes: 32, maxBodyBytes: 2048,
  maxPathBytes: 4096, maxIdentityBytes: 4096});
function binding(extra = {}, runtime = moon) {
  const collection = prepareGcsCollectionTarget(runtime, {project: 'project', bucket: 'bucket',
    prefix: 'in/', targetRef: 'connector://exports/objects', resourceKind: 'file_collection',
    catalogCid: token('a'), installationCid: token('b'), maxBytes: 8192, maxNodes: 100, maxDepth: 8});
  const target = prepareGcsCollectionUploadBinding(collection, {commandCid: token('c'),
    permissions: ['storage.objects.create', 'storage.objects.delete', 'storage.objects.get'],
    ...limits, ...extra});
  return {target, binding: prepareGcsComposeBinding(runtime, target,
    {maxSources: 32, maxResultBytes: 1000000n})};
}
function source(changes = {}) {
  return admitGcsObjectMetadata(moon, {bucket: 'bucket', prefix: 'in/', limits: metadata,
    bytes: Buffer.from(JSON.stringify({bucket: 'bucket', name, generation, metageneration: '2',
      size: '4', crc32c: 'crxyRA==', storageClass: 'STANDARD',
      contentType: 'application/octet-stream', ...changes}))});
}
const sources = () => [source(), source({name: 'in/part2', size: '2', crc32c: 'QtGpAA=='}), source()];
const absent = target => admitGcsUploadObservation(moon, target,
  {name, statusCode: 404, body: Buffer.from('{"error":{"code":404}}')});
const existing = (target, changes = {}) => admitGcsUploadObservation(moon, target,
  {name, statusCode: 200, body: Buffer.from(JSON.stringify({bucket: 'bucket', name,
    generation, metageneration: '2', size: '7', contentType: 'text/csv',
    metadata: {'e\u0301': '=exact\r\n', '': '', 'actql-request': 'old-marker'}, ...changes}))});
const prepare = (owner, extra = {}) => prepareOwnedGcsComposition({moon, binding: owner.binding,
  before: absent(owner.target), sources: sources(), marker: token('d'), maxProjectionBytes: 8192, ...extra});
const authorization = changes => ({grant: {}, useId: 'explicit-original-claim-counter', scope: {
  resourceOrigin: 'https://storage.googleapis.com', operation: 'gcs:object:compose', ...changes}});
const send = (request, callResource, changes = {}) => sendOwnedGcsComposition({request, callResource,
  authorization: authorization(), credential: {explicitPhysicalCounterOnly: true},
  maxRequestBytes: 2048, maxResponseBytes: 8192, ...changes});
const responseBody = changes => Buffer.from(JSON.stringify({bucket: 'bucket', name,
  generation: '9007199254740994', metageneration: '1', size: '10', crc32c: 'ml8N0A==',
  storageClass: 'STANDARD', contentType: 'application/octet-stream',
  metadata: {'actql-request': token('d')}, ...changes}));

test('compose matches independent original absent/existing preimages and hides only private marker values', () => {
  const owner = binding();
  for (const expected of vectors) {
    const request = prepare(owner, {before: expected.name === 'absent'
      ? absent(owner.target) : existing(owner.target)});
    assert.equal(request.request_cid, expected.request_cid);
    assert.equal('sha256:' + createHash('sha256').update(expected.request_preimage).digest('hex'), expected.request_cid);
    assert.equal(request.path, expected.path);
    assert.equal(ownedGcsCompositionBody(request), expected.body);
    assert.equal(request.body_byte_length, expected.body_bytes);
    assert.equal(request.after.crc32c, 'ml8N0A==');
    assert.equal(request.after.size_bytes, '10');
    assert.equal(JSON.stringify(request).includes(token('d')), false);
    assert.equal(JSON.stringify(request).includes('old-marker'), false);
    assert.equal(request.protocol_behavior, 'assign_original_request_marker:actql-request');
    assert.ok(Object.isFrozen(request.after.metadata));
    if (expected.name === 'existing') {
      assert.deepEqual(request.before.metadata, {'e\u0301': '=exact\r\n', '': ''});
      assert.deepEqual(request.after.metadata, request.before.metadata);
      assert.equal(request.after.content_type, 'text/csv');
      assert.equal(request.property_selection, 'captured_destination');
    } else {
      assert.deepEqual(request.after.metadata, {});
      assert.equal(request.after.content_type, 'application/octet-stream');
      assert.equal(request.property_selection, 'first_source_type_empty_user_metadata');
    }
  }
});

test('compose rejects copied originals same DATA foreign binding and different permission identity', () => {
  const owner = binding(), other = binding(), request = prepare(owner);
  assert.throws(() => ownedGcsCompositionBody({...request}), {code: 'ForeignGcsComposeRequest'});
  assert.throws(() => ownedGcsCompositionBody(request, other.binding), {code: 'ForeignGcsComposeRequest'});
  assert.throws(() => prepare(other, {before: absent(owner.target)}), {code: 'GcsForeignComposeBinding'});
  const distinct = binding({permissions: ['different.permission']});
  const different = prepare(distinct);
  assert.equal(ownedGcsCompositionBody(different), ownedGcsCompositionBody(request));
  assert.notEqual(different.request_cid, request.request_cid);
});

test('compose preserves order repetitions and both original destination guards across current recheck', () => {
  const owner = binding(), input = sources();
  const request = prepare(owner, {sources: input, before: existing(owner.target)});
  input[0] = source({name: 'in/replaced'});
  assert.deepEqual(request.sources.map(value => value.name), [name, 'in/part2', name]);
  assert.equal(request.sources[0].generation, generation);
  recheckOwnedGcsComposition(request, existing(owner.target), sources());
  assert.throws(() => recheckOwnedGcsComposition(request,
    existing(owner.target, {metageneration: '3'}), sources()), {code: 'GcsStaleComposeObservation'});
  assert.throws(() => recheckOwnedGcsComposition(request, existing(owner.target), input),
    {code: 'GcsStaleComposeObservation'});
  assert.throws(() => recheckOwnedGcsComposition(request, absent(owner.target), sources()),
    {code: 'GcsStaleComposeObservation'});
});

test('compose requires explicit typed limits and available compiler ABI without numeric coercion', () => {
  const owner = binding();
  for (const maxResultBytes of [0, 1, undefined, -1n, 5497558138881n]) {
    assert.throws(() => prepareGcsComposeBinding(moon, owner.target,
      {maxSources: 32, maxResultBytes}), {code: 'GcsInvalidComposeLimits'});
  }
  for (const maxSources of [0, 33, 1.5, 2 ** 32 + 1]) {
    assert.throws(() => prepareGcsComposeBinding(moon, owner.target,
      {maxSources, maxResultBytes: 10n}), {code: 'GcsInvalidComposeLimits'});
  }
  assert.throws(() => prepare(owner, {moon: {...moon, gcsComposePrepare: undefined}}),
    {code: 'GcsComposeRuntimeUnavailable'});
  assert.throws(() => prepare(owner, {sources: []}), {code: 'GcsInvalidComposeInput'});
  assert.throws(() => prepare(owner, {sources: Array(33).fill(source())}), {code: 'GcsInvalidComposeInput'});
  assert.throws(() => prepare(owner, {maxProjectionBytes: 1}), {code: 'GcsComposeCapacityExceeded'});
});

test('compose sends one exact original scoped request and returns the same rejected response backing', async () => {
  const request = prepare(binding());
  const body = Buffer.from('original precondition failure'), headers = [['x-goog-generation', generation]];
  let calls = 0;
  const response = await send(request, async invocation => {
    calls++;
    assert.equal(invocation.returnRejectedResponse, true);
    assert.deepEqual([...invocation.operations.keys()], ['gcs:object:compose']);
    const physical = invocation.operations.get('gcs:object:compose');
    assert.equal(physical.method, 'POST');
    assert.equal(physical.path, vectors[0].path);
    assert.equal(physical.body, vectors[0].body);
    assert.equal(JSON.parse(physical.body).deleteSourceObjects, false);
    assert.equal(invocation.maxResponseBytes, 8192);
    return {accepted: false, useCid: 'original-rejected-response', statusCode: 412, body, headers};
  });
  assert.equal(calls, 1);
  assert.equal(response.observation.body, body);
  assert.equal(response.headers, headers);
  assert.equal(response.observation.accepted, false);
  assert.equal(response.outcome, undefined);
});

test('compose response loss keeps exact frozen cleanup failure and never resends', async () => {
  const request = prepare(binding());
  const handle = Object.freeze({pending: true});
  const failure = Object.freeze(Object.assign(new Error('original lost response'),
    {cleanupPending: true, cleanupHandle: handle}));
  let calls = 0;
  await assert.rejects(send(request, async () => { calls++; throw failure; }), error => error === failure);
  assert.equal(calls, 1);
  assert.equal(failure.cleanupHandle, handle);
});

test('compose scope clamp and cancelled input refuse before any physical operation', async () => {
  const request = prepare(binding());
  let calls = 0;
  const never = () => { calls++; assert.fail('no physical operation'); };
  for (const maxRequestBytes of [0, -1, 0.5, 2 ** 32 + 2048, 610]) {
    await assert.rejects(send(request, never, {maxRequestBytes}), {code: 'GcsInvalidComposeTransportLimits'});
  }
  await assert.rejects(send(request, never, {authorization: authorization({operation: 'foreign'})}),
    {code: 'ForeignGcsComposeAuthorization'});
  await assert.rejects(send(request, never, {authorization: authorization({resourceOrigin: 'https://foreign.example'})}),
    {code: 'ForeignGcsComposeAuthorization'});
  const controller = new AbortController(); controller.abort();
  await assert.rejects(send(request, never, {signal: controller.signal}), {name: 'AbortError'});
  assert.equal(calls, 0);
});

test('compose direct response projection keeps uncorrelated or malformed responses unknown', () => {
  const owner = binding(), request = prepare(owner);
  const observed = body => ({statusCode: 200, body});
  const valid = responseBody();
  const response = admitGcsObjectMetadata(moon, {bucket: 'bucket', prefix: 'in/', limits: metadata, bytes: valid});
  assert.equal(ownedGcsCompositionResponseMatches(request, response), true);
  assert.equal(projectOwnedGcsCompositionResponse(request, observed(valid), 8192).outcome.state, 'applied');
  for (const body of [Buffer.from('{}'), Buffer.from([0xff]), responseBody({metadata: {}}),
    responseBody({metadata: {'actql-request': token('e')}}), responseBody({crc32c: 'AAAAAA=='})]) {
    assert.deepEqual(projectOwnedGcsCompositionResponse(request, observed(body), 8192), {kind: 'provider-response'});
  }
  const conflict = projectOwnedGcsCompositionResponse(request, {statusCode: 412, body: Buffer.from('{}')}, 8192);
  assert.equal(conflict.outcome.state, 'failed');
  assert.equal(conflict.outcome.error.code, 'conflict');
  assert.deepEqual(projectOwnedGcsCompositionResponse(request, {statusCode: 503, body: Buffer.from('{}')}, 8192),
    {kind: 'provider-response'});
  assert.throws(() => projectOwnedGcsCompositionResponse(request,
    observed(new Uint8Array(new SharedArrayBuffer(1))), 8192), {code: 'GcsInvalidComposeResponse'});
  assert.throws(() => projectOwnedGcsCompositionResponse(request, observed(Buffer.alloc(8193)), 8192),
    {code: 'GcsComposeCapacityExceeded'});
  assert.equal(valid.equals(responseBody()), true, 'projection does not mutate the retained original bytes');
});
