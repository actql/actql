// Real selected GCS parser/projection with an explicit controlled physical
// port. The Resource callback below is a contract control, not Core authority.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {readGcsObjects} from '../site/gcs-object-listing.mjs';
import {GCS_FILE_LIST_OPERATION} from '../site/gcs-file-listing.mjs';

const scope = Object.freeze({operation: GCS_FILE_LIST_OPERATION,
  resourceOrigin: 'https://storage.googleapis.com', siteGeneration: 1,
  issuerAuthority: 'fixture', principal: 'fixture', namespaceId: 'fixture',
  environment: 'fixture', siteKey: 'fixture', runtimeBundleCid: 'fixture',
  connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1',
  runInvocationCid: 'fixture', taskAttempt: 'fixture', dispatchRequestCid: 'fixture'});
const item = Object.freeze({bucket: 'bucket', name: 'in/e\u0301%2F.csv',
  generation: '9007199254740993', metageneration: '2', size: '9223372036854775807',
  contentType: 'text/csv', storageClass: 'COLDLINE', updated: '2026-10-17T00:00:00Z',
  md5Hash: 'AAAAAA==', crc32c: 'crxyRA==',
  metadata: {'actql-request': 'private', '$json': 'user', 'e\u0301': 'e\u0301\r\n%2F'}});
function fixture(pages = [{kind: 'storage#objects', nextPageToken: 'empty'},
  {kind: 'storage#objects', items: [item]}]) {
  const state = {calls: [], charges: [], rows: [], resources: [], events: []};
  const options = {moon, target: {bucket: 'bucket', prefix: 'in/'}, requestWire: '{}',
    limits: {maxPageBytes: 8192, maxPageItems: 3, maxRequestBytes: 4096,
      maxTimeMs: 1000, maxPages: 4, maxRows: 3}, credential: {journal: {fixture: true}},
    verifyRead: async () => {state.events.push('current');},
    authorizationFor: async index => ({grant: {}, useId: `objects-${index}`, scope}),
    resourceFor: value => {
      state.resources.push(value); return {$fixtureResource: value};
    },
    chargePage: body => {
      const charge = Object.freeze({body});
      state.charges.push(charge); state.events.push('charge'); return charge;
    },
    consumePage: async (rows, {charge}) => {
      assert.equal(charge, state.charges.at(-1));
      state.rows.push(rows); state.events.push('consume');
    },
    callResource: async call => {
      state.calls.push(call); state.events.push('send');
      const body = pages[state.calls.length - 1];
      return {accepted: true, statusCode: 200, headers: [],
        body: Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body))};
    }};
  return {options, state};
}

test('actual GCS object parser preserves exact Int64 Decimal text, all fields and raw JSON metadata', async () => {
  const {options, state} = fixture();
  await readGcsObjects(options);
  assert.equal(state.calls.length, 2);
  assert.deepEqual(state.rows, [[], [{resource: {$fixtureResource: {bucket: 'bucket',
    objectName: 'in/e\u0301%2F.csv'}}, version: '9007199254740993', name: 'in/e\u0301%2F.csv',
    size: '9223372036854775807', generation: '9007199254740993', metageneration: '2',
    content_type: 'text/csv', storage_class: 'COLDLINE', updated: '2026-10-17T00:00:00.000Z',
    md5: 'AAAAAA==', crc32c: 'crxyRA==', metadata: {'$json': 'user', 'e\u0301': 'e\u0301\r\n%2F'}}]]);
  assert.deepEqual(state.events, ['current', 'send', 'charge', 'consume',
    'current', 'send', 'charge', 'consume']);
  assert.equal(JSON.parse(state.charges[1].body).items[0].metadata['actql-request'], 'private',
    'the logical private-key projection never changes original physical evidence');
  assert.deepEqual(state.calls.map(call => call.operations.get(GCS_FILE_LIST_OPERATION).path), [
    '/storage/v1/b/bucket/o?prefix=in%2F&maxResults=3&projection=noAcl',
    '/storage/v1/b/bucket/o?prefix=in%2F&maxResults=3&projection=noAcl&pageToken=empty']);
});

test('missing provider metadata and empty object remain distinct Source DATA', async () => {
  const absent = {...item}; delete absent.metadata;
  const {options, state} = fixture([{kind: 'storage#objects', items: [absent, {...item, metadata: {}}]}]);
  await readGcsObjects(options);
  assert.equal(state.rows[0][0].metadata, null);
  assert.deepEqual(state.rows[0][1].metadata, {});
});

test('GCS timestamp Source DATA uses the same UTC instant while retaining the exact physical report', async () => {
  const reported = '2026-10-17T01:30:00.123000000+01:30';
  const {options, state} = fixture([{kind: 'storage#objects', items: [{...item, updated: reported}]}]);
  await readGcsObjects(options);
  assert.equal(state.rows[0][0].updated, '2026-10-17T00:00:00.123Z');
  assert.equal(JSON.parse(state.charges[0].body).items[0].updated, reported);
});

test('unrepresentable GCS sub-millisecond timestamps refuse without rounding or issuing a Resource', async () => {
  const reported = '2026-10-17T00:00:00.123001Z';
  const {options, state} = fixture([{kind: 'storage#objects', items: [{...item, updated: reported}]}]);
  await assert.rejects(readGcsObjects(options), {code: 'InvalidMetadata'});
  assert.equal(state.calls.length, 1);
  assert.equal(state.charges.length, 1);
  assert.equal(JSON.parse(state.charges[0].body).items[0].updated, reported);
  assert.equal(state.resources.length, 0);
  assert.equal(state.rows.length, 0);
});

test('actual checked prefix narrows scope without Unicode or percent normalization', async () => {
  const {options, state} = fixture([{kind: 'storage#objects', items: [item]}]);
  options.requestWire = '{"prefix":"in/e\u0301%2F"}';
  await readGcsObjects(options);
  assert.equal(state.calls[0].operations.get(GCS_FILE_LIST_OPERATION).path,
    '/storage/v1/b/bucket/o?prefix=in%2Fe%CC%81%252F&maxResults=3&projection=noAcl');
  for (const requestWire of ['{"prefix":"out/"}', '{"glob":"*"}',
    '{"prefix":"in/","prefix":"out/"}', '{"prefix":1}', '[]']) {
    const denied = fixture(); denied.options.requestWire = requestWire;
    await assert.rejects(readGcsObjects(denied.options));
    assert.equal(denied.state.calls.length, 0);
  }
});

for (const [name, body] of [
  ['overflow Int64', {kind: 'storage#objects', items: [{...item, size: '9223372036854775808'}]}],
  ['rounded generation number', {kind: 'storage#objects', items: [{...item, generation: 9007199254740992}]}],
  ['foreign object', {kind: 'storage#objects', items: [item, {...item, name: 'outside/file'}]}],
  ['null metadata', {kind: 'storage#objects', items: [{...item, metadata: null}]}],
  ['unexpected prefix page', {kind: 'storage#objects', items: [item], prefixes: ['in/folder/']}],
  ['duplicate provider keys', Buffer.from('{"kind":"storage#objects","items":[],"items":[]}')],
  ['invalid UTF8', Buffer.from([0xff])],
]) {
  test(`actual GCS ${name} preserves original charge and admits no partial page`, async () => {
    const {options, state} = fixture([body]);
    await assert.rejects(readGcsObjects(options));
    assert.equal(state.calls.length, 1); assert.equal(state.charges.length, 1);
    assert.equal(state.rows.length, 0); assert.equal(state.resources.length, 0);
  });
}

test('empty continuations, repeated tokens and exact page/row ceilings never become completion', async () => {
  const cycle = fixture([{kind: 'storage#objects', nextPageToken: 'cycle'},
    {kind: 'storage#objects', nextPageToken: 'cycle'}]);
  await assert.rejects(readGcsObjects(cycle.options), {code: 'GcsObjectListingRepeatedToken'});
  assert.equal(cycle.state.calls.length, 2);
  const pageLimit = fixture(); pageLimit.options.limits.maxPages = 1;
  await assert.rejects(readGcsObjects(pageLimit.options), {code: 'GcsObjectListingLimit'});
  assert.equal(pageLimit.state.calls.length, 1);
  const rowLimit = fixture([{kind: 'storage#objects', items: [item], nextPageToken: 'more'}]);
  rowLimit.options.limits.maxRows = 1;
  await assert.rejects(readGcsObjects(rowLimit.options), {code: 'GcsObjectListingLimit'});
  assert.equal(rowLimit.state.calls.length, 1);
});

test('original cancellation and physical failure preserve identity without a retry', async () => {
  const cancelled = fixture(), abort = new AbortController();
  const reason = Object.freeze(new Error('original cancellation'));
  abort.abort(reason); cancelled.options.signal = abort.signal;
  await assert.rejects(readGcsObjects(cancelled.options), error => error === reason);
  assert.equal(cancelled.state.calls.length, 0);
  const lost = fixture();
  const cleanupHandle = Object.freeze({release: async () => false});
  const primary = Object.freeze(Object.assign(new Error('original physical failure'),
    {cleanupPending: true, cleanupHandle}));
  let attempts = 0;
  lost.options.callResource = async () => {attempts++; throw primary;};
  await assert.rejects(readGcsObjects(lost.options), error => error === primary);
  assert.equal(attempts, 1); assert.equal(lost.state.rows.length, 0);
  assert.equal(primary.cleanupHandle, cleanupHandle);
});

test('original error response is charged before interpretation and foreign subsequent scope is refused', async () => {
  const rejected = fixture();
  rejected.options.callResource = async call => {
    rejected.state.calls.push(call);
    return {accepted: false, statusCode: 403, headers: [], body: Buffer.from('denied')};
  };
  await assert.rejects(readGcsObjects(rejected.options), {code: 'GcsObjectListingRejected'});
  assert.equal(rejected.state.charges.length, 1); assert.equal(rejected.state.rows.length, 0);
  const foreign = fixture();
  foreign.options.authorizationFor = async index => ({grant: {}, useId: `original-${index}`,
    scope: {...scope, siteGeneration: index + 1}});
  await assert.rejects(readGcsObjects(foreign.options), {code: 'InvalidGcsObjectListingAuthorization'});
  assert.equal(foreign.state.calls.length, 1);
});
