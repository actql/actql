// Actual compiled portable owner + existing byte/credential invocation. The
// explicit physical port is a counter, not Core approval or live GCS.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {captureClaimedEffectResponse} from '../../../host-node/effect-physical-dispatch.mjs';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {prepareGcsCollectionTarget, prepareGcsCollectionUploadBinding} from '../host/gcs-collection-target.mjs';
import {admitGcsUploadObservation, prepareOwnedGcsMultipartUpload, ownedGcsUploadBody,
  recheckOwnedGcsUpload, ownedGcsUploadResponseMatches, sendOwnedGcsUpload,
  readGcsUploadTarget, projectOwnedGcsUploadResponse} from '../site/gcs-owned-upload-request.mjs';
import {admitGcsUploadTargetObservation} from '../site/gcs-owned-upload-request.mjs';
import {admitGcsObjectMetadata} from '../site/gcs-owned-object-request.mjs';

const token = digit => `sha256:${digit.repeat(64)}`;
const metadata = Object.freeze({maxBytes: 8192, maxNodes: 100, maxDepth: 8, maxEntries: 4});
const limits = Object.freeze({metadata, maxContentBytes: 32, maxBodyBytes: 2048,
  maxPathBytes: 4096, maxIdentityBytes: 4096});
const name = 'in/e\u0301%2F.bin';
const content = () => Buffer.from([0, 255, 13, 10]);
const contentCid = 'sha256:e9489f37fb3051e9efa1dc916004d7274e7b63975e3209708947267f2393a9be';
function binding(extra = {}) {
  const collection = prepareGcsCollectionTarget(moon, {project: 'project', bucket: 'bucket',
    prefix: 'in/', targetRef: 'connector://exports/objects', resourceKind: 'file_collection',
    catalogCid: token('a'), installationCid: token('b'), maxBytes: 8192, maxNodes: 100, maxDepth: 8});
  return {collection, binding: prepareGcsCollectionUploadBinding(collection,
    {commandCid: token('c'), permissions: ['storage.objects.create', 'storage.objects.delete',
      'storage.objects.get'], ...limits, ...extra})};
}
const absent = original => admitGcsUploadObservation(moon, original,
  {name, statusCode: 404, body: Buffer.from('{"error":{"code":404}}')});
const existingBody = changes => Buffer.from(JSON.stringify({bucket: 'bucket', name,
  generation: '9007199254740993', metageneration: '2', size: '7', ...changes}));
const existing = (original, changes = {}) => admitGcsUploadObservation(moon, original,
  {name, statusCode: 200, body: existingBody(changes)});
const targetResponse = (body, changes = {}) => ({headers: [], observation: {
  accepted: true, useCid: token('e'), statusCode: 200, body, ...changes}});
const prepare = (original, before, extra = {}) => prepareOwnedGcsMultipartUpload({moon,
  binding: original, before, contentBytes: content(), contentRefCid: token('f'), contentCid,
  mediaType: 'application/octet-stream', marker: token('d'), maxProjectionBytes: 8192, ...extra});
const authorization = changes => ({grant: {}, useId: 'explicit-test-counter', scope: {
  resourceOrigin: 'https://storage.googleapis.com', operation: 'gcs:object:upload', ...changes}});
const send = (request, callResource, extra = {}) => sendOwnedGcsUpload({request, callResource,
  authorization: authorization(), credential: {explicitPhysicalCounterOnly: true},
  maxRequestBytes: 2048, maxResponseBytes: 8192, ...extra});

test('original target metadata uses the same exact bytes and Int64 header agreement', () => {
  const {binding: original} = binding();
  const body = existingBody();
  const response = {...targetResponse(body), headers: [['content-encoding', 'identity'],
    ['x-goog-generation', '9007199254740993'], ['x-goog-metageneration', '2']]};
  const before = admitGcsUploadTargetObservation(moon, original, name, response);
  const request = prepare(original, before, {overwrite: true});
  assert.equal(request.request_cid, prepare(original, existing(original), {overwrite: true}).request_cid);
  assert.equal(request.generation, '9007199254740993');
  assert.equal(response.observation.body, body);
  for (const headers of [[['x-goog-generation', '9007199254740994']],
    [['x-goog-metageneration', '3']], [['x-goog-generation', '09007199254740993']]]) {
    assert.throws(() => admitGcsUploadTargetObservation(moon, original, name,
      {...response, headers}), {code: 'GcsStaleUploadObservation'});
  }
});

test('an unaccepted or unrecorded target reply cannot become an observed absent object', () => {
  const {binding: original} = binding();
  let calls = 0;
  const observed = {...moon, gcsUploadTargetObservation(...args) {
    calls++;
    return moon.gcsUploadTargetObservation(...args);
  }};
  const body = Buffer.from('{"error":{"code":404}}');
  for (const changes of [{accepted: false}, {accepted: undefined}, {useCid: undefined},
    {useCid: 'not-a-use-observation'}, {statusCode: 0}]) {
    assert.throws(() => admitGcsUploadTargetObservation(observed, original, name,
      targetResponse(body, {statusCode: 404, ...changes})),
    {code: 'GcsInvalidUploadTargetReadObservation'});
  }
  assert.equal(calls, 0);
  const before = admitGcsUploadTargetObservation(observed, original, name,
    targetResponse(body, {statusCode: 404}));
  assert.equal(prepare(original, before).request_cid,
    'sha256:6c286b44b63592dd69d7ab707b710fdf6b5bd0199594589d70fe9e27a535a4de');
  assert.equal(calls, 1);
});

test('missing target-observation ABI refuses instead of falling back to body-only admission', () => {
  const {binding: original} = binding();
  const response = targetResponse(Buffer.from('{"error":{"code":404}}'), {statusCode: 404});
  assert.throws(() => admitGcsUploadTargetObservation(
    {...moon, gcsUploadTargetObservation: undefined}, original, name, response),
  {code: 'GcsUploadTargetObservationUnavailable'});
  assert.equal(response.observation.accepted, true);
  assert.equal(response.observation.statusCode, 404);
});

test('transformed duplicate or contradictory target headers cannot establish absence', () => {
  const {binding: original} = binding();
  const response = targetResponse(Buffer.from('{}'), {statusCode: 404});
  for (const headers of [[['content-encoding', 'gzip']], [['content-encoding', '']],
    [['content-encoding', 'identity'], ['content-encoding', 'identity']],
    [['x-goog-generation', '1']], [['x-goog-metageneration', '2']],
    [['Content-Encoding', 'identity']], [['content-range', 'bytes 0-0/1']]]) {
    assert.throws(() => admitGcsUploadTargetObservation(moon, original, name,
      {...response, headers}), {code: 'GcsInvalidUploadInput'});
  }
  assert.throws(() => admitGcsUploadTargetObservation(moon, original, name,
    {...response, headers: Array.from({length: 4}, () => ['content-encoding', 'identity'])}),
  {code: 'GcsUploadCapacityExceeded'});
  assert.throws(() => admitGcsUploadTargetObservation(moon, original, name,
    {...response, headers: [['content-encoding', 'x'.repeat(metadata.maxBytes + 1)]]}),
  {code: 'GcsUploadCapacityExceeded'});
});

test('target response refusal retains the same physical observation rather than retrying or clearing it', async () => {
  const {binding: original} = binding();
  const body = existingBody();
  const responseHeaders = [['x-goog-metageneration', '3']];
  let calls = 0;
  const response = await readGcsUploadTarget({moon, binding: original, name,
    authorization: authorization({operation: 'gcs:file:read'}), credential: {}, maxRequestBytes: 4096,
    callResource: async () => { calls++;return {accepted: true, useCid: token('e'),
      statusCode: 200, body, headers: responseHeaders}; }});
  assert.throws(() => admitGcsUploadTargetObservation(moon, original, name, response),
    {code: 'GcsStaleUploadObservation'});
  assert.equal(calls, 1);
  assert.equal(response.observation.body, body);
  assert.equal(response.headers, responseHeaders);
});

test('real multipart owner preserves independent binary bytes and request CID without exposing marker Preview', () => {
  const {binding: original} = binding();
  const bytes = content();
  const request = prepare(original, absent(original), {contentBytes: bytes});
  assert.equal(request.request_cid, 'sha256:6c286b44b63592dd69d7ab707b710fdf6b5bd0199594589d70fe9e27a535a4de');
  assert.equal(request.body_byte_length, 511);
  assert.equal(request.size_bytes, 4);
  assert.equal(request.crc32c, 'crxyRA==');
  assert.equal(request.name, name);
  assert.equal(request.generation, '0');
  assert.equal(request.metageneration, null);
  assert.equal(request.protocol_behavior, 'assign_original_request_marker:actql-request');
  assert.equal(JSON.stringify(request).includes(token('d')), false);
  const body = ownedGcsUploadBody(request);
  assert.equal(createHash('sha256').update(body).digest('hex'),
    'd0bbda939f3adf67d2f13e4ab4138769a075ab50c459a0ddde5d56b3583e719c');
  assert.ok(Buffer.from(body).includes(content()));
  bytes.fill(42); body.fill(43);
  assert.equal(createHash('sha256').update(ownedGcsUploadBody(request)).digest('hex'),
    'd0bbda939f3adf67d2f13e4ab4138769a075ab50c459a0ddde5d56b3583e719c');
});

test('real upload refuses copied frames and same DATA under another original binding', () => {
  const first = binding(), second = binding();
  const request = prepare(first.binding, absent(first.binding));
  assert.throws(() => ownedGcsUploadBody({...request}), {code: 'ForeignGcsUploadRequest'});
  assert.throws(() => ownedGcsUploadBody(request, second.binding), {code: 'GcsForeignUploadBinding'});
  assert.throws(() => prepare(second.binding, absent(first.binding)), {code: 'GcsForeignUploadBinding'});
  assert.throws(() => prepareGcsCollectionUploadBinding({...first.collection},
    {commandCid: token('c'), permissions: ['storage.objects.create'], ...limits}),
  {code: 'ForeignGcsCollectionTarget'});
  const foreign = binding({permissions: ['different.permission']});
  const changed = prepare(foreign.binding, absent(foreign.binding));
  assert.deepEqual(ownedGcsUploadBody(changed), ownedGcsUploadBody(request));
  assert.notEqual(changed.request_cid, request.request_cid);
});

test('optional overwrite and exact Int64 replacement observations survive the typed ABI', () => {
  const {binding: original} = binding();
  const before = existing(original);
  for (const overwrite of [undefined, false]) {
    assert.throws(() => prepare(original, before, {overwrite}), {code: 'GcsUploadTargetExists'});
  }
  const request = prepare(original, before, {overwrite: true});
  assert.equal(request.generation, '9007199254740993');
  assert.equal(request.metageneration, '2');
  assert.equal(request.path, '/upload/storage/v1/b/bucket/o?uploadType=multipart&ifGenerationMatch=9007199254740993&ifMetagenerationMatch=2');
  recheckOwnedGcsUpload(request, existing(original));
  for (const change of [{generation: '9007199254740994'}, {metageneration: '3'}]) {
    assert.throws(() => recheckOwnedGcsUpload(request, existing(original, change)),
      {code: 'GcsStaleUploadObservation'});
  }
  assert.throws(() => recheckOwnedGcsUpload(request, absent(original)), {code: 'GcsStaleUploadObservation'});
  assert.notEqual(prepare(original, absent(original)).request_cid,
    prepare(original, absent(original), {overwrite: false}).request_cid);
});

test('JSON upload names preserve exact legal controls and prefix while rejecting CR LF and foreign scope', () => {
  const {binding: original} = binding();
  for (const name of ['in/a\tb', 'in/\x7f', 'in/#[]*?', 'in/../literal', 'in/e\u0301']) {
    const before = admitGcsUploadObservation(moon, original,
      {name, statusCode: 404, body: Buffer.from('{}')});
    const request = prepare(original, before);
    assert.equal(request.name, name);
    const first = Buffer.from(ownedGcsUploadBody(request)).toString('utf8');
    assert.ok(first.includes(`"name":${JSON.stringify(name)}`));
  }
  for (const name of ['in/a\rb', 'in/a\nb', 'outside/a', 'in', '']) {
    assert.throws(() => admitGcsUploadObservation(moon, original,
      {name, statusCode: 404, body: Buffer.from('{}')}), {code: 'GcsInvalidUploadInput'});
  }
});

test('binary transport invokes one original scoped operation and returns the same rejected response backing', async () => {
  const {binding: original} = binding();
  const request = prepare(original, absent(original));
  const responseBody = Buffer.from('original precondition refusal');
  const headers = [['x-goog-generation', '9007199254740994']];
  let calls = 0;
  const response = await send(request, async invocation => {
    calls++;
    assert.equal(invocation.returnRejectedResponse, true);
    assert.deepEqual([...invocation.operations.keys()], ['gcs:object:upload']);
    const selected = invocation.operations.get('gcs:object:upload');
    assert.equal(selected.method, 'POST');
    assert.equal(selected.path, request.path);
    assert.equal(selected.body, undefined, 'binary never becomes a UTF-8 String body');
    assert.equal(selected.bodyMediaType, request.body_media_type);
    assert.deepEqual(selected.bodyBytes, Buffer.from(ownedGcsUploadBody(request)));
    assert.equal(selected.maxBodyBytes, 2048);
    return {accepted: false, useCid: 'same-original-response', statusCode: 412,
      body: responseBody, headers};
  });
  assert.equal(calls, 1);
  assert.equal(response.observation.body, responseBody);
  assert.equal(response.headers, headers);
  assert.equal(response.observation.accepted, false);
  assert.equal(response.observation.statusCode, 412);
  assert.equal(response.outcome, undefined);
});

test('upload response loss preserves the exact original cleanup failure without a resend', async () => {
  const {binding: original} = binding();
  const request = prepare(original, absent(original));
  const failure = Object.freeze(Object.assign(new Error('original lost reply'), {cleanupPending: true}));
  let calls = 0;
  await assert.rejects(send(request, async () => { calls++; throw failure; }), error => error === failure);
  assert.equal(calls, 1);
});

test('upload ABI and acquisition clamps reject without calling a physical port', async () => {
  const {binding: original} = binding();
  const before = absent(original);
  for (const overwrite of [null, 0, 'false']) {
    assert.throws(() => prepare(original, before, {overwrite}), {code: 'GcsInvalidUploadAbiInput'});
  }
  assert.throws(() => prepare(original, before,
    {contentBytes: new Uint8Array(new SharedArrayBuffer(4))}), {code: 'GcsInvalidUploadAbiBytes'});
  const request = prepare(original, before);
  let calls = 0;
  const never = () => { calls++; assert.fail('no physical acquisition'); };
  for (const maxRequestBytes of [0, -1, 0.5, 2 ** 32 + 2048, 510]) {
    await assert.rejects(send(request, never, {maxRequestBytes}), {code: 'GcsInvalidUploadTransportLimits'});
  }
  await assert.rejects(send(request, never, {authorization: authorization({operation: 'different'})}),
    {code: 'ForeignGcsUploadAuthorization'});
  const controller = new AbortController(); controller.abort();
  await assert.rejects(send(request, never, {signal: controller.signal}), {name: 'AbortError'});
  assert.equal(calls, 0);
});

test('matching payload or a foreign marker cannot become an upload apply receipt', () => {
  const {binding: original} = binding();
  const request = prepare(original, existing(original), {overwrite: true});
  const response = changes => admitGcsObjectMetadata(moon, {bucket: 'bucket', prefix: 'in/',
    name, limits: metadata, bytes: existingBody({generation: '9007199254740994',
      metageneration: '1', size: '4', contentType: 'application/octet-stream',
      crc32c: 'crxyRA==', metadata: {'actql-request': token('d')}, ...changes})});
  assert.equal(ownedGcsUploadResponseMatches(request, response({})), true, 'DATA consistency only');
  for (const change of [{metadata: {}}, {metadata: {'actql-request': 'old-or-copied'}},
    {generation: '9007199254740993'}, {metageneration: '2'}, {crc32c: 'AAAAAA=='}]) {
    assert.equal(ownedGcsUploadResponseMatches(request, response(change)), false);
  }
  assert.equal(request.applied, undefined);
});

test('target metadata read uses the original scoped path and response clamp without interpreting apply or 404', async () => {
  const {binding: original} = binding();
  const responseBody = Buffer.from('{"error":{"code":404}}');
  const headers = [['x-goog-generation', 'old-original']];
  let calls = 0;
  const result = await readGcsUploadTarget({moon, binding: original, name,
    authorization: authorization({operation: 'gcs:file:read'}), credential: {},
    maxRequestBytes: 4096,
    callResource: async invocation => {
      calls++;
      assert.equal(invocation.returnRejectedResponse, true);
      const selected = invocation.operations.get('gcs:file:read');
      assert.equal(selected.method, 'GET');
      assert.equal(selected.path, '/storage/v1/b/bucket/o/in%2Fe%CC%81%252F.bin');
      assert.equal(selected.body, undefined);
      assert.equal(selected.bodyBytes, undefined);
      assert.equal(selected.maxResponseBytes, undefined);
      assert.equal(invocation.maxResponseBytes, metadata.maxBytes);
      assert.deepEqual(selected.headers,
        [['accept', 'application/json'], ['accept-encoding', 'identity']]);
      return {accepted: false, statusCode: 404, useCid: 'original-404', body: responseBody, headers};
    }});
  assert.equal(calls, 1);
  assert.equal(result.observation.body, responseBody);
  assert.equal(result.headers, headers);
  assert.equal(result.before, undefined, 'the original response is retained before admission');
  assert.equal(result.applied, undefined);
  assert.doesNotThrow(() => prepare(original, admitGcsUploadObservation(moon, original,
    {name, ...result.observation})));
});

test('target metadata read refuses foreign scope before I/O and preserves the exact lost-response failure', async () => {
  const {binding: original} = binding();
  let calls = 0;
  const failure = Object.freeze(Object.assign(new Error('metadata read lost'), {cleanupPending: true}));
  const options = {moon, binding: original, name, maxRequestBytes: 4096,
    authorization: authorization({operation: 'gcs:file:read'}), credential: {},
    callResource: async () => { calls++; throw failure; }};
  for (const name of ['outside/a', 'in/a\nb']) {
    await assert.rejects(readGcsUploadTarget({...options, name}), {code: 'GcsInvalidUploadInput'});
  }
  await assert.rejects(readGcsUploadTarget({...options, authorization: authorization()}),
    {code: 'ForeignGcsUploadTargetReadAuthorization'});
  const controller = new AbortController();controller.abort();
  await assert.rejects(readGcsUploadTarget({...options, signal: controller.signal}), {name: 'AbortError'});
  assert.equal(calls, 0);
  await assert.rejects(readGcsUploadTarget(options), error => error === failure);
  assert.equal(calls, 1, 'read failure does not authorize retry or upload');
});

const uploadResponseBody = changes => existingBody({generation: '9007199254740994',
  metageneration: '1', size: '4', contentType: 'application/octet-stream',
  crc32c: 'crxyRA==', metadata: {'actql-request': token('d')}, ...changes});

test('direct upload projection reuses the existing capture boundary after exact raw response custody', async () => {
  const {binding: original} = binding();
  const request = prepare(original, existing(original), {overwrite: true});
  const body = uploadResponseBody(), events = [];
  // Explicit contract-control port: actual capture bridge/order, not genuine
  // Core claim admission, service I/O or a new numerical profile.
  let claimed = false;
  const ledger = {
    claimDispatch() { events.push('claim');if(claimed)return {claimed:false,action:'reconcile'};
      claimed=true;return {claimed:true,dispatching:{}}; },
    beginPhysicalFlight() {events.push('begin');return()=>events.push('end');},
    recordResponse(record) {
      events.push('store');assert.equal(record.canonicalRequestCid,request.request_cid);
      assert.equal(record.responseBytes,body);assert.equal(record.statusCode,200);
      return {response:Object.freeze({statusCode:record.statusCode,body:record.responseBytes})};
    },
  };
  const claim = {scope:{},locator:{},key:{},basis:{},intentFingerprintCid:token('a'),canonicalRequestCid:request.request_cid};
  const captured = await captureClaimedEffectResponse({ledger,claim,requestCid:request.request_cid,
    execute:()=>{events.push('execute');return send(request,async()=>({accepted:true,statusCode:200,
      useCid:token('e'),body,headers:[]}));}});
  events.push('project');
  assert.deepEqual(projectOwnedGcsUploadResponse(request, captured.physical.observation, 1024),
    {kind: 'typed-success-response', outcome: {state: 'applied', result: {}}});
  assert.deepEqual(projectOwnedGcsUploadResponse(request, captured.response, 1024),
    {kind:'typed-success-response',outcome:{state:'applied',result:{}}},
  'the same Ledger-verified saved response needs no hot-only nominal token');
  assert.deepEqual(events,['claim','begin','execute','end','store','project']);
  const again = await captureClaimedEffectResponse({ledger,claim,requestCid:request.request_cid,
    execute:()=>assert.fail('the existing owner refuses a second send')});
  assert.equal(again.claimed,false);
  assert.throws(()=>projectOwnedGcsUploadResponse({...request},captured.response,1024),
    {code:'ForeignGcsUploadRequest'});
});

test('direct conditional response projects conflict while a later metadata read remains only read DATA', async () => {
  const {binding: original} = binding();
  const request = prepare(original, absent(original));
  const port = async () => ({accepted: false, statusCode: 412, body: Buffer.from('{}'), headers: []});
  const answer = await send(request, port);
  assert.deepEqual(projectOwnedGcsUploadResponse(request, answer.observation, 1024),
    {kind: 'typed-failure-response', outcome: {state: 'failed', error: {
      code: 'conflict', message: 'The original GCS upload precondition failed'}}});
  const read = await readGcsUploadTarget({moon, binding: original, name,
    authorization: authorization({operation: 'gcs:file:read'}), credential: {},
    maxRequestBytes: 4096, callResource: port});
  assert.equal(read.outcome,undefined);
  assert.equal(read.observation.statusCode,412);
  // The existing reconciliation owner uses original metadata matching, not
  // the direct-dispatch classifier, for this independent later read.
});

test('missing marker mismatched bytes malformed response and ambiguous status do not settle an upload', async () => {
  for (const [statusCode, body] of [[503, uploadResponseBody()], [200, Buffer.from('{}')],
    [200, Buffer.from([255])], [200, uploadResponseBody({metadata: {}})],
    [200, uploadResponseBody({metadata: {'actql-request': 'copied-foreign'}})],
    [200, uploadResponseBody({crc32c: 'AAAAAA=='})], [200, uploadResponseBody({metageneration: '2'})]]) {
    const {binding: original} = binding();
    const request = prepare(original, absent(original));
    const answer = await send(request, async () => ({accepted: statusCode === 200,
      statusCode, body, headers: []}));
    assert.deepEqual(projectOwnedGcsUploadResponse(request, answer.observation, 1024), {kind: 'provider-response'});
    assert.equal(answer.observation.body, body);
  }
  const {binding: original} = binding();
  const request = prepare(original, absent(original));
  const invalid = await send(request, async () => ({accepted: false, statusCode: 4294967708,
    body: Buffer.from('{}'), headers: []}));
  assert.throws(() => projectOwnedGcsUploadResponse(request, invalid.observation, 1024), {code: 'GcsInvalidUploadResponse'});
  const other = binding();
  const nextRequest = prepare(other.binding, absent(other.binding));
  const answer = await send(nextRequest, async () => ({accepted: true, statusCode: 200,
    body: uploadResponseBody(), headers: []}));
  assert.throws(() => projectOwnedGcsUploadResponse(nextRequest, answer.observation, 1), {code: 'GcsUploadCapacityExceeded'});
});
