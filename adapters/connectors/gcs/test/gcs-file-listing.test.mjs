import assert from 'node:assert/strict';
import test from 'node:test';
import {readGcsFileListing, GCS_FILE_LIST_OPERATION} from '../site/gcs-file-listing.mjs';

const scope = Object.freeze({operation: GCS_FILE_LIST_OPERATION,
  resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1,
  issuerAuthority: 'fixture', principal: 'fixture', namespaceId: 'fixture',
  environment: 'fixture', siteKey: 'fixture', runtimeBundleCid: 'fixture',
  connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
  runInvocationCid: 'fixture', taskAttempt: 'fixture', dispatchRequestCid: 'fixture'});
const metadata = {bucket: 'actql-fixture', name: 'test/e\u0301%2F.csv',
  generation: '9007199254740993', size: '7', contentType: 'text/csv'};

function fixture(pages = [
  {kind: 'storage#objects', nextPageToken: 'empty'},
  {kind: 'storage#objects', items: [metadata], nextPageToken: 'terminal'},
  {kind: 'storage#objects'},
]) {
  const state = {calls: [], charges: [], envelopes: [], tokens: [], events: []};
  const options = {target: {bucket: 'actql-fixture', prefix: 'test/'},
    limits: {maxPageBytes: 4096, maxPageItems: 3, maxRequestBytes: 4096, maxTimeMs: 1000},
    credential: {journal: {fixture: true}},
    listing: {
      beginRequest: async token => { state.tokens.push(token); state.events.push('begin'); },
      consumePage: async (body, {charge}) => {
        state.events.push('consume');
        assert.equal(charge, state.charges.at(-1));
        state.envelopes.push(JSON.parse(body));
      },
    },
    authorizationFor: async index => ({grant: {}, useId: `list-${index}`, scope}),
    resourceFor: target => ({$fixtureResource: target}),
    chargePage: bytes => {
      const ticket = {bytes: Buffer.from(bytes)};
      state.charges.push(ticket); state.events.push('charge'); return ticket;
    },
    callResource: async call => {
      state.events.push('send'); state.calls.push(call);
      return {accepted: true, statusCode: 200, headers: [],
        body: Buffer.from(JSON.stringify(pages[state.calls.length - 1]))};
    }};
  return {options, state};
}

test('GCS listing retains empty continuation pages, exact keys and string generations', async () => {
  const {options, state} = fixture();
  await readGcsFileListing(options);
  assert.deepEqual(state.tokens, [undefined, 'empty', 'terminal']);
  assert.equal(state.calls.length, 3);
  assert.deepEqual(state.envelopes.map(value => value.items.length), [0, 1, 0]);
  assert.deepEqual(state.envelopes[1].items, [{
    resource: {$fixtureResource: {bucket: 'actql-fixture', objectName: 'test/e\u0301%2F.csv'}},
    name: 'test/e\u0301%2F.csv', path: 'test/e\u0301%2F.csv',
    version: '9007199254740993', size_bytes: 7, media_type: 'text/csv', modified_at: null,
  }]);
  assert.deepEqual(state.events, Array.from({length: 3}, () =>
    ['begin', 'send', 'charge', 'consume']).flat());
  for (const [index, call] of state.calls.entries()) {
    const request = call.operations.get(GCS_FILE_LIST_OPERATION);
    assert.equal(request.method, 'GET');
    assert.equal(request.path, '/storage/v1/b/actql-fixture/o?prefix=test%2F&maxResults=3&projection=noAcl' +
      (index === 0 ? '' : `&pageToken=${['empty', 'terminal'][index - 1]}`));
    assert.equal(request.body, undefined);
    assert.equal(call.returnRejectedResponse, true);
  }
});

test('flat GCS listing refuses unexpected prefix pages without partial admission', async () => {
  const {options, state} = fixture([{kind: 'storage#objects',
    items: [metadata], prefixes: ['test/folder/'], nextPageToken: 'unfinished'}]);
  const resources = [];
  options.resourceFor = target => {
    resources.push(target);
    return {$fixtureResource: target};
  };
  await assert.rejects(readGcsFileListing(options), {code: 'InvalidGcsFileListingPage'});
  assert.equal(state.calls.length, 1);
  assert.equal(state.charges.length, 1);
  assert.equal(state.envelopes.length, 0);
  assert.deepEqual(resources, []);
  assert.deepEqual(state.tokens, [undefined]);
  assert.deepEqual(state.events, ['begin', 'send', 'charge']);
  assert.deepEqual(JSON.parse(state.charges[0].bytes), {
    kind: 'storage#objects', items: [metadata], prefixes: ['test/folder/'],
    nextPageToken: 'unfinished',
  });
  assert.equal(state.calls[0].operations.get(GCS_FILE_LIST_OPERATION).path,
    '/storage/v1/b/actql-fixture/o?prefix=test%2F&maxResults=3&projection=noAcl');
});

test('flat GCS listing accepts empty prefixes but follows an empty continuation page', async () => {
  const {options, state} = fixture([
    {kind: 'storage#objects', items: [], prefixes: [], nextPageToken: 'empty'},
    {kind: 'storage#objects', items: [], prefixes: []},
  ]);
  await readGcsFileListing(options);
  assert.equal(state.calls.length, 2);
  assert.equal(state.charges.length, 2);
  assert.deepEqual(state.tokens, [undefined, 'empty']);
  assert.deepEqual(state.envelopes, [
    {items: [], request_token: null, next_token: 'empty'},
    {items: [], request_token: 'empty', next_token: null},
  ]);
  assert.deepEqual(state.calls.map(call =>
    call.operations.get(GCS_FILE_LIST_OPERATION).path), [
    '/storage/v1/b/actql-fixture/o?prefix=test%2F&maxResults=3&projection=noAcl',
    '/storage/v1/b/actql-fixture/o?prefix=test%2F&maxResults=3&projection=noAcl&pageToken=empty',
  ]);
});

for (const [name, changed] of [
  ['foreign bucket', {bucket: 'other'}],
  ['foreign prefix', {name: 'elsewhere/file'}],
  ['unpaired surrogate', {name: 'test/\ud800'}],
  ['numeric generation', {generation: 9007199254740992}],
  ['unsafe numeric size', {size: '9007199254740993'}],
]) {
  test(`GCS ${name} retains charge and rejects before common admission`, async () => {
    const {options, state} = fixture([{kind: 'storage#objects', items: [{...metadata, ...changed}]}]);
    await assert.rejects(readGcsFileListing(options), {code: 'GcsFileListingMetadataMismatch'});
    assert.equal(state.calls.length, 1); assert.equal(state.charges.length, 1);
    assert.equal(state.envelopes.length, 0);
  });
}

test('a common request refusal prevents the next physical send without local cursor reinterpretation', async () => {
  const {options, state} = fixture([{kind: 'storage#objects', nextPageToken: 'repeat'}]);
  options.listing.beginRequest = async token => {
    if (token !== undefined) throw Object.assign(new Error('CommonListingLimit'), {code: 'CommonListingLimit'});
  };
  await assert.rejects(readGcsFileListing(options), {code: 'CommonListingLimit'});
  assert.equal(state.calls.length, 1); assert.equal(state.envelopes.length, 1);
});

test('rejected provider body is charged before status interpretation', async () => {
  const {options, state} = fixture();
  options.callResource = async call => {
    state.calls.push(call);
    return {accepted: false, statusCode: 403, headers: [], body: Buffer.from('denied')};
  };
  await assert.rejects(readGcsFileListing(options), {code: 'GcsFileListingRejected'});
  assert.equal(state.charges[0].bytes.toString(), 'denied');
  assert.equal(state.envelopes.length, 0);
});

test('authorization binding changes stop before a second credential invocation', async () => {
  const {options, state} = fixture();
  options.authorizationFor = async index => ({grant: {}, useId: `use-${index}`,
    scope: index === 0 ? scope : {...scope, taskAttempt: 'different'}});
  await assert.rejects(readGcsFileListing(options), {code: 'InvalidGcsFileListingAuthorization'});
  assert.equal(state.calls.length, 1); assert.equal(state.envelopes.length, 1);
});

test('caller mutation across await cannot redirect installed bucket, prefix or limits', async () => {
  const {options, state} = fixture();
  const original = options.callResource;
  options.callResource = async call => {
    const response = await original(call);
    options.target.bucket = 'foreign'; options.target.prefix = 'foreign/';
    options.limits.maxPageItems = 1; options.limits.maxPageBytes = 1;
    options.credential.journal = {foreign: true};
    return response;
  };
  await readGcsFileListing(options);
  assert.equal(state.calls.length, 3);
  assert.ok(state.calls.every(call => call.journal.fixture === true));
});

test('positive physical work followed by cancellation retains charge without admission', async () => {
  const {options, state} = fixture();
  const controller = new AbortController(); options.signal = controller.signal;
  const charge = options.chargePage;
  options.chargePage = bytes => {
    const ticket = charge(bytes); controller.abort(new Error('FixtureCancelled')); return ticket;
  };
  await assert.rejects(readGcsFileListing(options), /FixtureCancelled/u);
  assert.equal(state.calls.length, 1); assert.equal(state.charges.length, 1);
  assert.equal(state.envelopes.length, 0);
});
