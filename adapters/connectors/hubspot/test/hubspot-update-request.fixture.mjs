// Native request-only controls, shared by the matching compiled test and an
// explicitly qualified immutable-runtime compatibility diagnostic. No grant,
// Credential, Ledger, provider operation, business state or cleanup ACK.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {createHubSpotUpdateRequestAdapter} from '../host/hubspot-update-request.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

const canonical = value => value !== null && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
  : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const tag = 'sha256:' + 'b'.repeat(64);
const rowId = '9007199254740993';
const value = Object.freeze({amount: '9007199254740993.0100000000', tags: ['a', 'b']});
const metadata = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false, modificationMetadata: {readOnlyValue: false}},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', calculated: false,
    modificationMetadata: {readOnlyValue: false}, options: [{value: 'a'}, {value: 'b'}]},
  {name: 'actql_request_id', type: 'string', fieldType: 'text', calculated: false, modificationMetadata: {readOnlyValue: false}},
]};
function fixture(moon, {body = metadata, fields = ['amount', 'tags'], markerProperty = 'actql_request_id'} = {}) {
  const catalog = checked(moon.hubspotProjectProperties(Buffer.from(JSON.stringify(body)), 'companies', 30000, 3000, 24, 100, 256));
  const mapping = checked(moon.hubspotPrepareExecutionMapping(catalog, 'hubspot', 'sha256:' + 'a'.repeat(64),
    'companies', 1, 'id', fields, [], 100, 16, 256, 20000, 2000, 24));
  const installed = Object.freeze({catalog, mapping, resource: 'companies', markerProperty,
    mappingCid: moon.hubspotExecutionMappingCid(mapping), mappingRef: moon.hubspotExecutionMappingRef(mapping)});
  const limits = {maxProperties: 100,
    body: {maxInputBytes: 8192, maxNodes: 2000, maxDepth: 24, maxFields: 16, maxNameBytes: 256,
      maxValueNodes: 2000, maxValueTextBytes: 8192, maxComparisonWork: 20000,
      maxOutputBytes: 8192, maxOutputNodes: 2000, maxOutputDepth: 24},
    request: {maxRows: 100, maxProperties: 100, maxTraceBytes: 128,
      maxBodyBytes: 20000, maxBodyNodes: 3000, maxBodyDepth: 24}, maxRecoveryBytes: 65536};
  const member = Object.freeze({kind: 'update', resource: 'companies', mapping: {
    mappingRef: installed.mappingRef, mappingCid: installed.mappingCid}});
  const adapter = createHubSpotUpdateRequestAdapter({moon, connectorId: 'hubspot', portalId: '7',
    origin: 'https://hubspot.invalid', installedFor: () => installed, limits});
  return {catalog, mapping, installed, limits, member, adapter};
}
export {fixture as hubspotUpdateRequestFixture};

export function registerHubSpotUpdateRequestTests(moon) {
  test('HubSpot original update request binds full logical value then actual dispatch marker without rounding', () => {
    const f = fixture(moon), logical = f.adapter.prepare({member: f.member, value, selector: rowId});
    const expectedLogical = {version: 'actql-installed-hubspot-update-request/0.1',
      connectorId: 'hubspot', origin: 'https://hubspot.invalid', portalId: '7', resource: 'companies',
      mappingRef: f.installed.mappingRef, mappingCid: f.installed.mappingCid,
      markerProperty: 'actql_request_id', valueWire: canonical(value), selectorWire: JSON.stringify(rowId)};
    assert.equal(logical.requestCid, cid(expectedLogical));
    assert.throws(() => f.adapter.assertFinalized(logical.request, tag), {code: 'HubSpotUpdateRequestNotFinalized'});
    assert.throws(() => f.adapter.savedWire(logical.request), {code: 'HubSpotUpdateRequestNotFinalized'});
    const physical = f.adapter.finalize({request: logical.request, requestTag: tag});
    f.adapter.assertFinalized(physical.request, tag);
    assert.equal(f.adapter.capabilityRequestCid(physical.request), logical.requestCid);
    assert.notEqual(physical.requestCid, logical.requestCid);
    assert.deepEqual(f.adapter.requestFacts(physical.request), {value, target: rowId});
    const expectedBody = canonical({inputs: [{id: rowId, objectWriteTraceId: logical.requestCid,
      properties: {actql_request_id: tag, amount: value.amount, tags: 'a;b'}}]});
    assert.equal(moon.hubspotRecordBatchBody(f.adapter.nativeRequest(physical.request)), expectedBody);
    assert.equal(physical.requestCid, cid({logical: expectedLogical, logicalCid: logical.requestCid, requestTag: tag, body: expectedBody}));
    assert.equal(f.adapter.objectType(physical.request), 'companies');
    assert.throws(() => f.adapter.assertFinalized(physical.request, 'sha256:' + 'c'.repeat(64)), {code: 'HubSpotUpdateRequestNotFinalized'});
  });

  test('HubSpot cold update request reconstructs through fresh native originals and exact full wire', () => {
    const first = fixture(moon), logical = first.adapter.prepare({member: first.member, value, selector: rowId});
    const physical = first.adapter.finalize({request: logical.request, requestTag: tag});
    const wire = first.adapter.savedWire(physical.request), second = fixture(moon);
    assert.notStrictEqual(first.catalog, second.catalog); assert.notStrictEqual(first.mapping, second.mapping);
    assert.throws(() => second.adapter.requestCid(physical.request), {code: 'ForeignHubSpotUpdateRequest'});
    const restored = second.adapter.restore({member: second.member, wire, requestTag: tag});
    assert.equal(restored.requestCid, physical.requestCid);
    assert.equal(second.adapter.savedWire(restored.request), wire);
    assert.notStrictEqual(second.adapter.nativeRequest(restored.request), first.adapter.nativeRequest(physical.request));
    assert.deepEqual(second.adapter.requestFacts(restored.request), {value, target: rowId});
  });

  test('HubSpot update recovery refuses changed binding marker request or target rather than reprojecting a different request', () => {
    const f = fixture(moon), prepared = f.adapter.prepare({member: f.member, value, selector: rowId});
    const physical = f.adapter.finalize({request: prepared.request, requestTag: tag}), wire = f.adapter.savedWire(physical.request);
    for (const mutate of [
      saved => {saved.logical.origin = 'https://foreign.invalid';},
      saved => {saved.logical.portalId = '8';},
      saved => {saved.logical.markerProperty = 'another_marker';},
      saved => {saved.logical.selectorWire = JSON.stringify('another-record');},
      saved => {saved.body = '{}';},
      saved => {saved.requestCid = 'sha256:' + 'c'.repeat(64);},
    ]) {
      const saved = JSON.parse(wire); mutate(saved);
      assert.throws(() => f.adapter.restore({member: f.member, wire: canonical(saved), requestTag: tag}),
        {code: 'HubSpotUpdateRecoveryMismatch'});
    }
    assert.throws(() => f.adapter.restore({member: f.member, wire, requestTag: 'sha256:' + 'c'.repeat(64)}),
      {code: 'HubSpotUpdateRecoveryMismatch'});
  });

  test('HubSpot update marker requires existing writable string property and never substitutes a business value', () => {
    for (const changed of ['missing', 'readonly']) {
      const body = structuredClone(metadata);
      if (changed === 'missing') body.results.pop(); else body.results.at(-1).modificationMetadata.readOnlyValue = true;
      const f = fixture(moon, {body}), original = f.adapter.prepare({member: f.member, value, selector: rowId});
      assert.throws(() => f.adapter.finalize({request: original.request, requestTag: tag}), {code: 'MoonBitHostFailure'});
    }
    const f = fixture(moon, {fields: ['actql_request_id']});
    const original = f.adapter.prepare({member: f.member, value: {actql_request_id: 'business'}, selector: rowId});
    assert.throws(() => f.adapter.finalize({request: original.request, requestTag: tag}), {code: 'MoonBitHostFailure'});
  });

  test('HubSpot update request refuses foreign mapping carrier malformed marker and original input bound', () => {
    const f = fixture(moon);
    assert.throws(() => f.adapter.prepare({member: {...f.member, mapping: {...f.member.mapping, mappingCid: 'foreign'}}, value, selector: rowId}),
      {code: 'ForeignHubSpotUpdateMapping'});
    const original = f.adapter.prepare({member: f.member, value, selector: rowId});
    assert.throws(() => f.adapter.finalize({request: original.request, requestTag: 'new-request'}), {code: 'InvalidHubSpotUpdateRequestTag'});
    assert.throws(() => f.adapter.requestCid({...original.request}), {code: 'ForeignHubSpotUpdateRequest'});
    assert.throws(() => f.adapter.prepare({member: f.member, value: {amount: 'x'.repeat(8193), tags: []}, selector: rowId}),
      {code: 'HubSpotUpdateRequestInputLimit'});
    // The adapter captured these original bounds before later caller mutation.
    f.limits.body.maxInputBytes = 999999;
    assert.throws(() => f.adapter.prepare({member: f.member, value: {amount: 'x'.repeat(8193), tags: []}, selector: rowId}),
      {code: 'HubSpotUpdateRequestInputLimit'});
  });
}
