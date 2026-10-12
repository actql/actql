import assert from 'node:assert/strict';
import test from 'node:test';
import {readGcsKeyedContent} from '../site/gcs-keyed-content.mjs';

const generation = '9007199254740993';
const metadata = {bucket: 'actql-fixture', name: 'test/e\u0301%2F.csv',
  generation, metageneration: '9007199254740995', size: '9',
  contentType: 'text/csv', crc32c: '4waSgw=='};
const payload = Buffer.from('123456789');
const resource = Object.freeze({$fixtureResource: 'original-resource'});
const content = Object.freeze({$fixtureContent: 'actually-verified-bytes'});
const scope = {operation: 'gcs:file:read', resourceOrigin: 'https://storage.googleapis.com',
  siteGeneration: 1, connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1'};

function fixture() {
  const state = {requests: [], calls: [], charges: [], pages: [], verification: [],
    captures: [], currentChecks: 0, pending: undefined};
  const options = {requestWire: JSON.stringify({resource, version: generation}),
    credential: {journal: {fixture: true}},
    limits: {maxMetadataBytes: 4096, maxContentBytes: 9, maxRequestBytes: 4096,
      maxAttempts: 2, maxTimeMs: 1000},
    resolveResource: async observed => {
      assert.deepEqual(observed, resource);
      return {bucket: metadata.bucket, objectName: metadata.name, prefix: 'test/'};
    },
    beginRequest: async body => {
      assert.equal(state.pending, undefined, 'one charge must settle before another send');
      state.requests.push(JSON.parse(body));
      return {grant: {}, useId: `request-${state.requests.length}`, scope};
    },
    chargePage: body => {
      assert.equal(state.pending, undefined);
      const ticket = {body: Buffer.from(body)};
      state.charges.push(ticket); state.pending = ticket; return ticket;
    },
    consumePage: async (rows, {charge}) => {
      assert.equal(charge, state.pending, 'consume the exact actual-body ticket once');
      state.pages.push(rows); state.pending = undefined;
    },
    chargeVerification: async bytes => { state.verification.push(bytes); },
    verifyRead: async () => { state.currentChecks++; },
    captureContent: async observed => {
      assert.deepEqual(observed.bytes, payload);
      assert.equal(observed.mediaType, 'text/csv');
      assert.equal(observed.contentCid,
        'sha256:15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225');
      state.captures.push(observed); return content;
    },
    callResource: async invocation => {
      state.calls.push(invocation);
      return {accepted: true, statusCode: 200, headers: [],
        body: state.calls.length === 1 ? Buffer.from(JSON.stringify(metadata)) : payload};
    }};
  return {options, state};
}

test('keyed GCS capture sequences actual request observations and consumes metadata/media tickets once', async () => {
  const {options, state} = fixture();
  await readGcsKeyedContent(options);
  assert.equal(state.requests.length, 2); assert.equal(state.calls.length, 2);
  assert.deepEqual(state.pages, [[], [{resource, version: generation, content}]]);
  assert.equal(state.charges.length, 2); assert.equal(state.pending, undefined);
  assert.equal(state.captures.length, 1); assert.equal(state.currentChecks, 1);
  assert.deepEqual(state.verification, [9]);
  for (const [index, call] of state.calls.entries()) {
    const actual = call.operations.get(scope.operation);
    assert.equal(state.requests[index].method, actual.method);
    assert.equal(state.requests[index].target, actual.path);
    assert.deepEqual(state.requests[index].headers, actual.headers);
    assert.equal(call.useId, `request-${index + 1}`);
  }
  assert.equal(state.requests[0].target,
    '/storage/v1/b/actql-fixture/o/test%2Fe%CC%81%252F.csv?generation=9007199254740993&ifGenerationMatch=9007199254740993');
  assert.equal(state.requests[1].target,
    '/storage/v1/b/actql-fixture/o/test%2Fe%CC%81%252F.csv?generation=9007199254740993&ifGenerationMatch=9007199254740993&alt=media&ifMetagenerationMatch=9007199254740995');
});

test('wrong media bytes leave the original physical ticket pending and produce no ContentRef row', async () => {
  const {options, state} = fixture(); const call = options.callResource;
  options.callResource = async invocation => {
    const response = await call(invocation);
    return state.calls.length === 2 ? {...response, body: Buffer.from('wrongbyte')} : response;
  };
  await assert.rejects(readGcsKeyedContent(options), {code: 'GcsContentDigestMismatch'});
  assert.deepEqual(state.pages, [[]]); assert.equal(state.captures.length, 0);
  assert.equal(state.pending, state.charges[1]); assert.equal(state.calls.length, 2);
});

test('current authorization refusal after positive read work stops before Store transfer', async () => {
  const {options, state} = fixture();
  options.verifyRead = async () => { throw Object.assign(new Error('FixtureRevoked'), {code: 'FixtureRevoked'}); };
  await assert.rejects(readGcsKeyedContent(options), {code: 'FixtureRevoked'});
  assert.equal(state.calls.length, 2); assert.equal(state.captures.length, 0);
  assert.deepEqual(state.pages, [[]]); assert.equal(state.pending, state.charges[1]);
});

test('cancellation after capture keeps the original media ticket and publishes no keyed row', async () => {
  const {options, state} = fixture();
  const controller = new AbortController();
  const reason = new Error('FixtureCancelledAfterCapture');
  const capture = options.captureContent;
  options.signal = controller.signal;
  options.captureContent = async observed => {
    const captured = await capture(observed);
    controller.abort(reason);
    return captured;
  };
  await assert.rejects(readGcsKeyedContent(options), error => error === reason);
  // Actual verified bytes remain with their capture owner. Cancellation is
  // neither cleanup proof nor permission to consume/replace its media ticket.
  assert.equal(state.captures.length, 1);
  assert.deepEqual(state.captures[0].bytes, payload);
  assert.deepEqual(state.pages, [[]]);
  assert.equal(state.pending, state.charges[1]);
  assert.equal(state.charges.length, 2);
  assert.equal(state.requests.length, 2);
  assert.equal(state.calls.length, 2, 'no replacement read after cancellation');
});

test('keyed row consumer failure keeps captured bytes and the exact media charge for its owner', async () => {
  const {options, state} = fixture();
  const failure = new Error('FixtureRowConsumerFailed');
  const consume = options.consumePage;
  const attempted = [];
  options.consumePage = async (rows, observation) => {
    if (rows.length === 0) return consume(rows, observation);
    attempted.push({rows, charge: observation.charge});
    throw failure;
  };
  await assert.rejects(readGcsKeyedContent(options), error => error === failure);
  assert.deepEqual(attempted, [{rows: [{resource, version: generation, content}],
    charge: state.charges[1]}]);
  assert.equal(attempted[0].charge, state.pending);
  assert.equal(state.captures.length, 1);
  assert.deepEqual(state.pages, [[]]);
  assert.equal(state.charges.length, 2);
  assert.equal(state.requests.length, 2);
  assert.equal(state.calls.length, 2, 'consumer failure cannot resend a read');
});

test('foreign Resource resolution refuses before any request or credential use', async () => {
  const {options, state} = fixture();
  options.resolveResource = async () => undefined;
  await assert.rejects(readGcsKeyedContent(options), {code: 'GcsKeyedResourceUnavailable'});
  assert.equal(state.requests.length, 0); assert.equal(state.calls.length, 0);
});

test('unknown media exchange is never retried and never invokes the capture owner', async () => {
  const {options, state} = fixture(); const call = options.callResource;
  options.callResource = async invocation => {
    const response = await call(invocation);
    if (state.calls.length === 2) throw new Error('FixtureExchangeUnknown');
    return response;
  };
  await assert.rejects(readGcsKeyedContent(options), /FixtureExchangeUnknown/u);
  assert.equal(state.calls.length, 2); assert.equal(state.charges.length, 1);
  assert.deepEqual(state.pages, [[]]); assert.equal(state.captures.length, 0);
});

for (const phase of ['resolveResource', 'beginRequest']) {
  test(`keyed limits cannot widen while awaiting ${phase}`, async () => {
    const {options, state} = fixture();
    options.limits.maxContentBytes = 8;
    const original = options[phase];
    options[phase] = async (...args) => {
      await Promise.resolve();
      options.limits.maxContentBytes = 9;
      options.limits.maxMetadataBytes = 8192;
      return original(...args);
    };
    await assert.rejects(readGcsKeyedContent(options), {code: 'GcsContentMetadataMismatch'});
    assert.equal(state.requests.length, 1);
    assert.equal(state.calls.length, 1);
    assert.equal(state.calls[0].maxResponseBytes, 4096);
    assert.deepEqual(state.pages, [[]]);
    assert.equal(state.pending, undefined);
    assert.equal(state.captures.length, 0);
  });
}

for (const [name, change] of [
  ['outside prefix', {objectName: 'other/secret.csv'}],
  ['invalid object text', {objectName: 'test/\uD800'}],
  ['invalid bucket', {bucket: ''}],
  ['invalid prefix', {prefix: 1}],
]) {
  test(`resolved keyed locator ${name} refuses before attempt observation or credential use`, async () => {
    const {options, state} = fixture();
    options.resolveResource = async () => ({bucket: metadata.bucket,
      objectName: metadata.name, prefix: 'test/', ...change});
    await assert.rejects(readGcsKeyedContent(options), {code: 'InvalidGcsContentRead'});
    assert.equal(state.requests.length, 0);
    assert.equal(state.calls.length, 0);
    assert.equal(state.charges.length, 0);
    assert.equal(state.captures.length, 0);
  });
}
