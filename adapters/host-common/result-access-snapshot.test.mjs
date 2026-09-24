import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {inspectAuthorizedDeliveryAttempt,
  installResultAccessAuthority, installResultAccessService} from
  './result-access.mjs';

const receipt = JSON.parse(readFileSync(new URL(
  '../../packages/client-wire/fixtures/delivery-attempt.found.json',
  import.meta.url), 'utf8'));
const cid = char => `sha256:${char.repeat(64)}`;
const request = () => ({
  indexKey: {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
    runDefinitionCid: receipt.attempt.run_definition_cid},
  principalId: 'principal-a', purpose: 'download', resultName: 'answer',
  attemptId: 'read-a',
});

function service({authorize, lookup}) {
  const store = {
    confirmCommittedIndex() {}, readPublicationContract() {},
    observeTrustedClock() {}, readCommittedResultRetentionExtension() {},
    lookupDeliveryAttempt: lookup,
  };
  const methods = [
    'issueResultReadGrant', 'resultReadRetentionPolicyCid',
    'resultReadAvailability', 'resultReadExtendedAvailability',
    'resultReadDefinitionCid', 'resultRetentionClockContractCid',
    'resultReadGrantValidAt', 'beginResultAccessProgress',
    'resultAccessProgressAction',
    'recordResultAccessRequestAuthorization',
    'recordResultAccessResolution',
    'recordResultAccessInitialAvailability',
    'recordResultAccessReadAdmission', 'recordResultAccessGrant',
  ];
  const control = Object.fromEntries(methods.map(name => [name, () => {}]));
  const authority = installResultAccessAuthority({
    authorizeResultReadRequest() {}, admitResultRead() {},
    authorizeResultRead() {}, authorizeDeliveryAttemptLookup: authorize,
  });
  return installResultAccessService({
    store, control, authority, now: () => '2026-09-24T00:00:00.000Z',
    createDigest() {},
    limits: {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20},
    frameLimits: {maxRowBytes: 1000, maxDepth: 20,
      maxFrameBytes: 10000},
  });
}

test('attempt lookup keeps the authorized scalar and nested Run snapshot',
  async () => {
    let release;
    let started;
    const authorized = new Promise(resolve => { started = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    let authorizedRequest;
    let lookupRequest;
    const installed = service({
      async authorize(facts) {
        authorizedRequest = facts;
        started();
        await gate;
        return true;
      },
      async lookup(facts) {
        lookupRequest = facts;
        return receipt;
      },
    });
    const submitted = request();
    const pending = inspectAuthorizedDeliveryAttempt(installed, submitted);
    await authorized;
    submitted.resultName = 'foreign';
    submitted.attemptId = 'other';
    submitted.indexKey.tenantId = 'tenant-b';
    submitted.indexKey.runDefinitionCid = cid('9');
    release();
    assert.deepEqual(await pending, receipt);
    assert.strictEqual(lookupRequest, authorizedRequest);
    assert.equal(Object.isFrozen(authorizedRequest.indexKey), true);
    assert.deepEqual(lookupRequest, request());
  });

test('attempt lookup rejects a foreign Store answer after authorization',
  async () => {
    const installed = service({
      authorize: async () => true,
      lookup: async () => ({...receipt,
        attempt: {...receipt.attempt, attempt_id: 'other'}}),
    });
    await assert.rejects(inspectAuthorizedDeliveryAttempt(
      installed, request()), {code: 'InvalidDeliveryAttemptLookup'});
  });

test('attempt lookup denies before Store I/O on false or thrown authority',
  async () => {
    for (const authorize of [async () => false,
      async () => { throw new Error('authority unavailable'); }]) {
      let lookups = 0;
      const installed = service({authorize, lookup: async () => {
        lookups++;
        return receipt;
      }});
      await assert.rejects(inspectAuthorizedDeliveryAttempt(
        installed, request()), {code: 'ResultAccessDenied'});
      assert.equal(lookups, 0);
    }
  });

test('attempt lookup distinguishes absent evidence from a Store failure',
  async () => {
    const absent = service({authorize: async () => true,
      lookup: async () => undefined});
    assert.deepEqual(await inspectAuthorizedDeliveryAttempt(
      absent, request()), {kind: 'not_found'});
    const failure = new Error('store unavailable');
    const unavailable = service({authorize: async () => true,
      lookup: async () => { throw failure; }});
    await assert.rejects(inspectAuthorizedDeliveryAttempt(
      unavailable, request()), error => error === failure);
  });
