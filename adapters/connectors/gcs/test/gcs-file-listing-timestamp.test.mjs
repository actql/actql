import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {readGcsFileListing, GCS_FILE_LIST_OPERATION} from '../site/gcs-file-listing.mjs';

// Actual portable GCS projection and transport; HTTP, Account, issuer and
// listing ports are explicit fixtures, not physical funding or live GCS.
function fixture(updated, provider = moon) {
  const metadata = {bucket: 'fixture-bucket', name: 'in/a.csv', size: '7',
    generation: '9007199254740993', updated};
  const raw = Buffer.from(JSON.stringify({kind: 'storage#objects', items: [metadata]}));
  const state = {sends: 0, charges: [], resources: [], pages: [], tickets: []};
  const options = {moon: provider, target: {bucket: metadata.bucket, prefix: 'in/'},
    limits: {maxPageBytes: 8192, maxPageItems: 3, maxRequestBytes: 4096, maxTimeMs: 1000},
    credential: {journal: {fixture: true}},
    authorizationFor: async () => ({grant: {}, useId: 'original-list', scope: {
      operation: GCS_FILE_LIST_OPERATION, resourceOrigin: 'https://storage.googleapis.com',
      siteGeneration: 1, connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1'}}),
    callResource: async () => {state.sends++; return {accepted: true, statusCode: 200,
      headers: [], body: raw};},
    chargePage: body => {
      assert.strictEqual(body, raw);
      const ticket = Object.freeze({raw}); state.charges.push(body); state.tickets.push(ticket); return ticket;
    },
    resourceFor: selected => {state.resources.push(selected); return {$fixtureResource: 'original'};},
    listing: {beginRequest: async () => {}, consumePage: async (body, {charge}) => {
      assert.strictEqual(charge, state.tickets.at(-1)); state.pages.push(JSON.parse(body));
    }},
  };
  return {options, state, raw, metadata};
}

for (const [reported, expected] of [
  ['2026-10-17T00:00:00Z', '2026-10-17T00:00:00.000Z'],
  ['2026-10-17T00:00:00.1Z', '2026-10-17T00:00:00.100Z'],
  ['2026-10-17T00:00:00.12Z', '2026-10-17T00:00:00.120Z'],
  ['2026-10-17T00:00:00.123Z', '2026-10-17T00:00:00.123Z'],
  ['2026-10-17T00:00:00.123000000Z', '2026-10-17T00:00:00.123Z'],
  ['2026-10-17T00:00:00.123001Z', '2026-10-17T00:00:00.123001Z'],
  ['2026-10-17T00:00:00.000000001Z', '2026-10-17T00:00:00.000000001Z'],
  ['2026-10-17T00:00:00.123456780Z', '2026-10-17T00:00:00.12345678Z'],
  ['1969-12-31T23:59:59.999999999Z', '1969-12-31T23:59:59.999999999Z'],
]) {
  test(`ordinary GCS listing canonicalizes ${reported} without changing its original observation`, async () => {
    const f = fixture(reported);
    assert.equal(moon.gcsObjectTimestamp(reported), expected);
    await readGcsFileListing(f.options);
    assert.equal(f.state.sends, 1); assert.equal(f.state.charges.length, 1);
    assert.equal(JSON.parse(f.state.charges[0]).items[0].updated, reported);
    assert.deepEqual(f.state.resources, [{bucket: 'fixture-bucket', objectName: 'in/a.csv'}]);
    assert.equal(f.state.pages[0].items[0].modified_at, expected);
    assert.equal(f.state.pages[0].items[0].version, f.metadata.generation);
    assert.deepEqual(f.state.pages[0].items[0].resource, {$fixtureResource: 'original'});
    assert.equal(f.state.pages[0].request_token, null);
    assert.equal(f.state.pages[0].next_token, null);
    assert.equal(f.metadata.updated, reported);
  });
}

for (const reported of ['2026-02-29T00:00:00Z', '2026-10-17T00:00:60Z',
  '2026-10-17T00:00:00.0000000001Z']) {
  test(`invalid GCS listing time ${reported} retains its charge and admits no Resource`, async () => {
    const f = fixture(reported);
    assert.equal(moon.gcsObjectTimestamp(reported), undefined);
    await assert.rejects(readGcsFileListing(f.options), {code: 'GcsFileListingMetadataMismatch'});
    assert.equal(f.state.sends, 1); assert.equal(f.state.charges.length, 1);
    assert.strictEqual(f.state.charges[0], f.raw);
    assert.deepEqual(f.state.resources, []); assert.deepEqual(f.state.pages, []);
  });
}

test('missing selected GCS timestamp supplier refuses before an HTTP operation', async () => {
  const f = fixture('2026-10-17T00:00:00.1Z', Object.freeze({}));
  await assert.rejects(readGcsFileListing(f.options), {code: 'InvalidGcsFileListing'});
  assert.equal(f.state.sends, 0); assert.equal(f.state.charges.length, 0);
});

test('explicit historical source-only listing retains its original physical spelling', async () => {
  const f = fixture('2026-10-17T00:00:00.1Z');
  f.options.moon = undefined;
  await readGcsFileListing(f.options);
  assert.equal(f.state.pages[0].items[0].modified_at, '2026-10-17T00:00:00.1Z');
  assert.equal(f.state.sends, 1); assert.equal(f.state.charges.length, 1);
});
