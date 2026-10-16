import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeIsBoxedSome, runtimeIsBoxedNone, runtimeField, runtimeUnboxedReferenceOption}
  from '../../../host-common/compiler-binding.generated.mjs';
import {recordWriteFixture} from './hubspot-record-write.fixture.mjs';

const metadata = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false,
    modificationMetadata: {readOnlyValue: false}},
  {name: 'actql_request_id', type: 'string', fieldType: 'text', hasUniqueValue: false,
    calculated: false, modificationMetadata: {readOnlyValue: false}},
  {name: 'external_key', type: 'string', fieldType: 'text', hasUniqueValue: true,
    calculated: false, modificationMetadata: {readOnlyValue: false}},
]};
const bounds = [4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20];
const value = '{"amount":"9007199254740993.0100000000"}';
const requestId = 'original-captured-request';
// These are qualified against the actual compiled exports. The optional
// marker Array is boxed; the two optional String projections are unboxed.
function markerFields(request) {
  const value = moon.hubspotRecordBatchMarkerFields(request);
  assert.ok(runtimeIsBoxedSome(value));
  return runtimeField(value, 0);
}
const originalValue = (request, index) => runtimeUnboxedReferenceOption(
  moon.hubspotRecordBatchInputValueJson(request, index));
const originalTarget = (request, index) => runtimeUnboxedReferenceOption(
  moon.hubspotRecordBatchInputTargetJson(request, index));
async function fixture(t, kind = 'update') {
  return await recordWriteFixture(t, kind, ['effect', 'read'], {metadataOverride: metadata,
    requestFactory({catalog, body, input}) {
      assert.equal(moon.hubspotWriteBodyValueJson(body), value);
      const unmarked = checked(moon.hubspotPrepareRecordBatch(catalog,
        {create: 0, update: 1, upsert: 2}[kind], {create: '', update: 'id', upsert: 'external_key'}[kind],
        [input], 100, 100, 100, 4096, 1000, 20));
      assert.ok(runtimeIsBoxedNone(moon.hubspotRecordBatchMarkerFields(unmarked)));
      const marker = checked(moon.hubspotPrepareRecordRequestMarker(catalog,
        'actql_request_id', requestId, ...bounds));
      return checked(moon.hubspotPrepareMarkedRecordBatch(catalog,
        {create: 0, update: 1, upsert: 2}[kind], {create: '', update: 'id', upsert: 'external_key'}[kind],
        [input], marker, 100, 100, 100, 4096, 1000, 20));
    }});
}

test('original request marker reaches real Credential SQLite TLS without changing business value or correlation', async t => {
  for (const kind of ['create', 'update', 'upsert']) {
    const f = await fixture(t, kind);
    const request = f.request;
    assert.deepEqual(markerFields(request), ['actql_request_id', requestId]);
    assert.equal(originalValue(request, 0), value);
    assert.equal(originalValue(request, 1), undefined);
    assert.equal(originalTarget(request, 0),
      kind === 'create' ? undefined : kind === 'update' ? '"9007199254740993"' : '"original-key"');
    const raw = await f.send();
    const body = moon.hubspotRecordBatchBody(request);
    assert.deepEqual(f.writeState.writes, [body]);
    assert.equal(JSON.parse(body).inputs[0].objectWriteTraceId, 'original-write');
    assert.deepEqual(JSON.parse(body).inputs[0].properties,
      {actql_request_id: requestId, amount: '9007199254740993.0100000000'});
    assert.equal(f.state.requests.length, 3); assert.equal(f.state.charges, 3);
    assert.equal(f.project(raw.observation).kind, 'typed-success-response');
    assert.equal(originalValue(request, 0), value);
    f.row.assertNoCapture();
  }
});

test('lost marked POST preserves original marker and nominal Unknown without resend or application inference', async t => {
  const f = await fixture(t);
  const originalBody = moon.hubspotRecordBatchBody(f.request);
  f.writeState.responseHook = async (request, response) => {
    if (!request.url.endsWith('/batch/update')) return false;
    const chunks = []; for await (const chunk of request) chunks.push(chunk);
    f.writeState.writes.push(Buffer.concat(chunks).toString());
    response.destroy(); return true;
  };
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'ECONNRESET');
    assert.equal(error.observations.length, 2); return true;
  });
  assert.deepEqual(f.writeState.writes, [originalBody]);
  assert.equal(f.state.requests.length, 3);
  assert.equal(f.journal.recover().filter(row => row.outcome === 'unknown').length, 1);
  assert.deepEqual(markerFields(f.request), ['actql_request_id', requestId]);
  assert.equal(originalValue(f.request, 0), value);
  // A persisted marker is request DATA. No history read, Effect claim,
  // application/release ACK, reissue or provider retry is created here.
  f.row.assertNoCapture();
});


test('current marker-property revocation refuses before POST and keeps original observations', async t => {
  const f = await fixture(t);
  const changed = structuredClone(metadata);
  changed.results[1].modificationMetadata.readOnlyValue = true;
  f.writeState.properties = JSON.stringify(changed);
  await assert.rejects(f.send(), error => {
    assert.equal(error.code, 'MoonBitHostFailure');
    assert.equal(error.observations.length, 2); return true;
  });
  assert.equal(f.writeState.writes.length, 0);
  assert.equal(f.state.requests.length, 2);
  assert.deepEqual(markerFields(f.request), ['actql_request_id', requestId]);
  assert.equal(originalValue(f.request, 0), value);
});
