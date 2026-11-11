import assert from 'node:assert/strict';
import test from 'node:test';
import {salesforceInitializationConstructionCapacity,
  salesforceExecutionMappingConstructionCapacity} from
  '../adapters/connectors/salesforce/host/salesforce-initialization-construction.mjs';

const generation = () => ({connector_id: 'crm', resources: ['Account', 'Gone'], evidence: {
  names: ['Account', 'Gone'], describeBodyBase64: ['e30=', null], outcomes: [1, 8],
  describeUseCids: ['sha256:' + '1'.repeat(64), null],
  describeResponseSha256: ['2'.repeat(64), null], observationJson: '{}',
  describeLimits: {maxBytes: 100, maxNodes: 100, maxDepth: 16,
    maxFields: 1000, maxNameUnits: 1000}, maxObservationBytes: 1000,
}});
// These tests check geometry and no-decode behavior, not native capacity
// sufficiency or issuer acceptance; those use the actual compiled-entry gate.
const spy = exportName => {
  const calls = [];
  const result = Object.freeze({});
  return {calls, result, common: {[exportName](...args) { calls.push(args); return result; }}};
};
const initializationName = 'clientProgramSalesforceInitializationConstructionCapacity';

test('Salesforce geometry quotes exact original bytes and current Site strings without decode', () => {
  const runtime = spy(initializationName);
  const original = generation();
  const result = salesforceInitializationConstructionCapacity(runtime.common, {
    generation: original, siteBinding: {namespaceId: 'ns', principal: 'p', generation: 1},
  });
  assert.equal(result, runtime.result);
  assert.deepEqual(runtime.calls, [[[2, 0], 4, 2, [7, 4], 5, 3, 14,
    100, 100, 16, 1000, 1000, 1000, 4_000_000, 400_000, 64]]);
  assert.equal(original.evidence.describeBodyBase64[0], 'e30=');
});

test('Salesforce malformed base64 and active properties refuse before native quote', () => {
  for (const encoded of ['Zh==', 'Zm9=', 'Zg', 'Zg==\n', '====']) {
    const runtime = spy(initializationName);
    const original = generation();
    original.evidence.describeBodyBase64[0] = encoded;
    assert.throws(() => salesforceInitializationConstructionCapacity(runtime.common, {
      generation: original, siteBinding: {},
    }), {code: 'InvalidSalesforceConstructionOriginal'});
    assert.equal(runtime.calls.length, 0);
  }
  const runtime = spy(initializationName);
  const original = generation();
  let invoked = false;
  Object.defineProperty(original.evidence, 'observationJson', {get() { invoked = true; return '{}'; }});
  assert.throws(() => salesforceInitializationConstructionCapacity(runtime.common, {
    generation: original, siteBinding: {},
  }), {code: 'InvalidSalesforceConstructionOriginal'});
  assert.equal(invoked, false);
  assert.equal(runtime.calls.length, 0);
  const proxy = new Proxy(generation(), {getOwnPropertyDescriptor() { invoked = true; return undefined; }});
  assert.throws(() => salesforceInitializationConstructionCapacity(runtime.common, {
    generation: proxy, siteBinding: {},
  }), {code: 'InvalidSalesforceConstructionOriginal'});
  assert.equal(invoked, false);
});

test('Salesforce actual write names and selected Describe bound supply mapping geometry', () => {
  const runtime = spy('clientProgramSalesforceExecutionMappingConstructionCapacity');
  const result = salesforceExecutionMappingConstructionCapacity(runtime.common, {
    generation: generation(), write: {resource: 'Account', kind: 'createFromResult',
      sources: [{target: 'Name', field: 'result', nullBehavior: 'omit'}]},
  });
  assert.equal(result, runtime.result);
  assert.deepEqual(runtime.calls, [[0, 0, 1, 14, 0, 7, 3, 14, 2, 1000, 400_000, 40_000, 64]]);
});

test('Salesforce native None and mismatched evidence do not become admission authority', () => {
  assert.throws(() => salesforceInitializationConstructionCapacity({[initializationName]() {}}, {
    generation: generation(), siteBinding: {},
  }), {code: 'InvalidSalesforceConstructionOriginal'});
  const runtime = spy(initializationName);
  const original = generation();
  original.evidence.outcomes.pop();
  assert.throws(() => salesforceInitializationConstructionCapacity(runtime.common, {
    generation: original, siteBinding: {},
  }), {code: 'InvalidSalesforceConstructionOriginal'});
  assert.equal(runtime.calls.length, 0);
});
