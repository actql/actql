import assert from 'node:assert/strict';
import test from 'node:test';
import {salesforceInitializationConstructionCapacity} from '../host/salesforce-initialization-construction.mjs';

const generation = bodies => ({connector_id: 'salesforce', evidence: {
  names: bodies.map((_, index) => `Object${index}`),
  describeBodyBase64: bodies, outcomes: bodies.map(() => 'available'),
  describeUseCids: bodies.map(() => null), describeResponseSha256: bodies.map(() => null),
  describeLimits: {maxBytes: 4_000_000, maxNodes: 400_000, maxDepth: 32,
    maxFields: 1000, maxNameUnits: 200_000},
  observationJson: '{}', maxObservationBytes: 8_000_000,
}});

test('Salesforce initialization forwards exact original Base64 to the Common structural issuer', () => {
  const body = Buffer.from('{"description":"' + 'a'.repeat(250_000) + '"}').toString('base64');
  const original = generation([body, null]);
  const capacity = Object.freeze({opaque: true});
  let calls = 0;
  const common = {clientProgramSalesforceOriginalInitializationConstructionCapacity(...args) {
    calls++;
    assert.deepEqual(args, [[body, undefined], 2, [7, 7], 5, 10, 14,
      4_000_000, 400_000, 32, 1000, 200_000, 8_000_000, 4_000_000, 400_000, 64]);
    return capacity;
  }, clientProgramSalesforceInitializationConstructionCapacity() {
    assert.fail('the body-length-only fallback does not measure this original');
  }};
  assert.equal(salesforceInitializationConstructionCapacity(common,
    {generation: original, siteBinding: {principal: 'own'}}), capacity);
  assert.equal(calls, 1);
  assert.equal(original.evidence.describeBodyBase64[0], body);
  assert.equal(original.evidence.describeBodyBase64[1], null);
});

test('Salesforce initialization preserves descriptor and canonical Base64 refusal before the issuer', () => {
  let calls = 0;
  const common = {clientProgramSalesforceOriginalInitializationConstructionCapacity() {calls++;}};
  for (const body of ['AB==', 'AAB=', 'AA=A', 'éAAA']) {
    assert.throws(() => salesforceInitializationConstructionCapacity(common,
      {generation: generation([body]), siteBinding: {}}), {code: 'InvalidSalesforceConstructionOriginal'});
  }
  const original = generation(['e30=']);
  Object.defineProperty(original.evidence.describeBodyBase64, '0', {
    get() {assert.fail('an original body getter must never execute');},
  });
  assert.throws(() => salesforceInitializationConstructionCapacity(common,
    {generation: original, siteBinding: {}}), {code: 'InvalidSalesforceConstructionOriginal'});
  assert.equal(calls, 0);
});
