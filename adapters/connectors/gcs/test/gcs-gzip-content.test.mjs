// Exact stored gzip bytes through the real transport and explicit controlled
// credential/capture ports. No decompression, service call or grant is issued.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readGcsVersionedContent} from '../site/gcs-versioned-content.mjs';

// Fixed gzip member for ASCII 123456789; the product never imports a gzip
// codec. SHA/MD5 and the bitwise Castagnoli reference were evaluated separately
// from the transport's table implementation, before these expectations.
const gzip = Buffer.from('1f8b080000000000001333343236313533b7b004002639f4cb09000000', 'hex');
const sha = 'sha256:50362a01a8d29d0eaceb7640872bab3f6d7f980e33804a57e21c79a18fe25cb8';
const generation = '9007199254740993';
const metageneration = '9007199254740995';
const scope = Object.freeze({operation: 'gcs:file:read',
  resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1,
  issuerAuthority: 'fixture', principal: 'fixture', namespaceId: 'fixture',
  environment: 'fixture', siteKey: 'fixture', runtimeBundleCid: 'fixture',
  connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
  runInvocationCid: 'fixture', taskAttempt: 1, dispatchRequestCid: 'fixture'});

function fixture({media = gzip, mediaHeaders = [['content-encoding', 'gzip']],
  maxBytes = 29, metadata = {}, mediaStatus = 200} = {}) {
  const state = {calls: [], requests: [], charges: [], verified: [], received: [], events: []};
  const options = {target: {bucket: 'bucket', prefix: 'in/', objectName: 'in/e\u0301%2F.json', generation},
    limits: {maxMetadataBytes: 4096, maxContentBytes: maxBytes, maxRequestBytes: 4096,
      maxAttempts: 2, maxTimeMs: 1000}, credential: {journal: {fixture: true}},
    initialAuthorization: {grant: {}, scope, useId: 'metadata'},
    authorizationForRequest: async request => {
      state.requests.push(request);
      return {grant: {}, scope, useId: 'media'};
    },
    recheckAuthorization: async () => ({grant: {}, scope, useId: 'handoff'}),
    chargeBody: async (body, observation) => {
      const ticket = Object.freeze({body, observation});
      state.charges.push(ticket); state.events.push(`charged:${observation.phase}`); return ticket;
    },
    chargeVerification: async bytes => { state.verified.push(bytes); },
    receiveContent: async (bytes, observation) => {
      state.received.push({bytes, observation}); state.events.push('capture');
      return Object.freeze({fixture: 'original capture receipt'});
    },
    callResource: async call => {
      state.calls.push(call); state.events.push(`send:${state.calls.length}`);
      const mediaRead = state.calls.length === 2;
      return {accepted: true, statusCode: mediaRead ? mediaStatus : 200,
        headers: mediaRead ? mediaHeaders : [],
        body: mediaRead ? media : Buffer.from(JSON.stringify({bucket: 'bucket',
          name: 'in/e\u0301%2F.json', generation, metageneration, size: '29',
          contentType: 'application/json', contentEncoding: 'gzip',
          crc32c: 'zCyQIQ==', md5Hash: 'FWXt8dDJrcb0EgQJ/cAkGQ==', ...metadata}))};
    }};
  return {state, options};
}

test('stored gzip bytes retain exact version CRC byte CID and capture loan without decompression', async () => {
  const {state, options} = fixture();
  const result = await readGcsVersionedContent(options);
  assert.equal(state.calls.length, 2);
  const requests = state.calls.map(call => call.operations.get(scope.operation));
  assert.deepEqual(requests.map(request => request.headers),
    [[['accept-encoding', 'identity']], [['accept-encoding', 'gzip'], ['range', 'bytes=0-28']]]);
  assert.equal(requests[1].path,
    '/storage/v1/b/bucket/o/in%2Fe%CC%81%252F.json?generation=9007199254740993&ifGenerationMatch=9007199254740993&alt=media&ifMetagenerationMatch=9007199254740995');
  const observedRequest = JSON.parse(state.requests[0].requestWire);
  assert.equal(observedRequest.target, requests[1].path);
  assert.deepEqual(observedRequest.headers, requests[1].headers);
  assert.equal(state.calls[1].maxResponseBytes, 29);
  assert.equal(result.digests.contentCid, sha);
  assert.equal(result.metadata.sizeBytes, 29n);
  assert.equal(result.metadata.mediaType, 'application/json');
  assert.equal(result.metadata.contentEncoding, 'gzip');
  assert.equal(state.received.length, 1);
  assert.equal(state.received[0].bytes, gzip, 'borrow the same verified raw body, not decoded bytes or a fresh loan');
  assert.equal(state.received[0].observation.metadataCharge, state.charges[0]);
  assert.equal(state.received[0].observation.contentCharge, state.charges[1]);
  assert.deepEqual(state.verified, [29]);
  assert.deepEqual(state.events, ['send:1', 'charged:metadata', 'send:2', 'charged:media', 'capture']);
});

test('stored gzip complete Range response proves the same bounded object bytes, never a partial ContentRef', async () => {
  const {state, options} = fixture({mediaStatus: 206,
    mediaHeaders: [['content-encoding', 'gzip'], ['content-range', 'bytes 0-28/29']]});
  const result = await readGcsVersionedContent(options);
  assert.equal(result.digests.contentCid, sha);
  assert.equal(state.received[0].bytes, gzip);
  assert.equal(state.received[0].observation.contentCharge, state.charges[1]);
  assert.equal(state.calls.length, 2);
  assert.deepEqual(state.calls[1].operations.get(scope.operation).headers,
    [['accept-encoding', 'gzip'], ['range', 'bytes=0-28']]);
});

for (const [name, change, code, calls] of [
  ['missing stored representation header', {mediaHeaders: []}, 'GcsContentRepresentationUnsupported', 2],
  ['identity transformed response', {mediaHeaders: [['content-encoding', 'identity']]}, 'GcsContentRepresentationUnsupported', 2],
  ['foreign representation', {mediaHeaders: [['content-encoding', 'br']]}, 'GcsContentRepresentationUnsupported', 2],
  ['decoded response with a false gzip header', {media: Buffer.from('123456789')}, 'GcsContentSizeMismatch', 2],
  ['corrupted compressed bytes', {media: Buffer.from(gzip).fill(0, 10, 11)}, 'GcsContentDigestMismatch', 2],
  ['one-short acquisition capacity', {maxBytes: 28}, 'GcsContentMetadataMismatch', 1],
  ['unsupported metadata encoding', {metadata: {contentEncoding: 'br'}}, 'GcsContentRepresentationUnsupported', 1],
  ['partial Range response', {mediaHeaders: [['content-encoding', 'gzip'], ['content-range', 'bytes 0-28/30']]}, 'GcsContentRepresentationUnsupported', 2],
  ['partial 206 bytes', {mediaStatus: 206, mediaHeaders: [['content-encoding', 'gzip'], ['content-range', 'bytes 0-27/29']]}, 'GcsContentRepresentationUnsupported', 2],
  ['unknown 206 extent', {mediaStatus: 206, mediaHeaders: [['content-encoding', 'gzip'], ['content-range', 'bytes 0-28/*']]}, 'GcsContentRepresentationUnsupported', 2],
  ['missing 206 range', {mediaStatus: 206}, 'GcsContentRepresentationUnsupported', 2],
]) {
  test(`stored gzip ${name} retains original charge and refuses handoff`, async () => {
    const {state, options} = fixture(change);
    await assert.rejects(readGcsVersionedContent(options), {code});
    assert.equal(state.calls.length, calls);
    assert.equal(state.charges.length, calls);
    assert.equal(state.received.length, 0);
  });
}

test('stored gzip capture failure keeps both original tickets without another read', async () => {
  const {state, options} = fixture();
  const failure = Object.freeze(new Error('FixtureGzipCapturePending'));
  let pending;
  options.receiveContent = async (bytes, observation) => {
    pending = {bytes, observation}; throw failure;
  };
  await assert.rejects(readGcsVersionedContent(options), error => error === failure);
  assert.equal(state.calls.length, 2);
  assert.equal(pending.bytes, gzip);
  assert.equal(pending.observation.metadataCharge, state.charges[0]);
  assert.equal(pending.observation.contentCharge, state.charges[1]);
});
