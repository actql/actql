import assert from 'node:assert/strict';
import test from 'node:test';
import {recoverNamedSalesforceObservation, NAMED_EVIDENCE_VERSION}
  from '../site/salesforce-named-describe.mjs';

const cid = 'sha256:' + '1'.repeat(64);
function fixture(count = 1) {
  const body = Buffer.from('{"name":"Account","fields":[]}');
  const evidence = {version: NAMED_EVIDENCE_VERSION,
    names: Array(count).fill('Account'), outcomes: Array(count).fill(1),
    describeBodyBase64: Array(count).fill(body.toString('base64')),
    describeUseCids: Array(count).fill(cid), describeResponseSha256: Array(count).fill(cid),
    observationJson: JSON.stringify({binding: {namespace_id: 'namespace'}}),
    describeLimits: {maxBytes: 1024, maxNodes: 128, maxDepth: 16, maxFields: 4, maxNameUnits: 64},
    maxObservationBytes: 1024};
  return {evidence, body};
}

test('named recovery grows with the same decoded body before its complete original validator', () => {
  const {evidence, body} = fixture(), observation = {}, events = [];
  let originalBody;
  const moon = {salesforceRecoverNamedCatalogObservation(wire, names, bodies, outcomes, ...rest) {
    events.push('validate');assert.strictEqual(wire, evidence.observationJson);
    assert.deepEqual(names, evidence.names);assert.deepEqual(outcomes, evidence.outcomes);
    assert.strictEqual(bodies[0], originalBody);assert.deepEqual(bodies[0], body);
    assert.deepEqual(rest.slice(-6), [1024, 128, 16, 4, 64, 1024]);
    return {$tag: 1, _0: observation};
  }, salesforceCatalogObservationCid(value) {assert.strictEqual(value, observation);return cid;}};
  assert.strictEqual(recoverNamedSalesforceObservation({moon, evidence, expectedObservationCid: cid,
    beforeRecover(actual, bodies) {
      events.push('grow');assert.strictEqual(actual, evidence);originalBody = bodies[0];
    }}), observation);
  assert.deepEqual(events, ['grow', 'validate']);
});

test('named recovery preserves a refused growth before native admission', () => {
  const {evidence} = fixture(), original = new Error('original quota refused');
  let native = 0;
  assert.throws(() => recoverNamedSalesforceObservation({evidence, expectedObservationCid: cid,
    moon: {salesforceRecoverNamedCatalogObservation() {native++;}},
    beforeRecover() {throw original;}}), error => error === original);
  assert.equal(native, 0);
});

test('wider named inventory retains its complete fallback before binary decoding', () => {
  const {evidence} = fixture(2), original = new Error('complete fallback refused');
  evidence.describeBodyBase64[0] = {toString() {assert.fail('No binary decoding before fallback');}};
  assert.throws(() => recoverNamedSalesforceObservation({evidence, expectedObservationCid: cid,
    moon: {salesforceRecoverNamedCatalogObservation() {assert.fail('No native admission');}},
    beforeRecover(actual, bodies) {
      assert.strictEqual(actual, evidence);assert.equal(bodies, undefined);throw original;
    }}), error => error === original);
});
