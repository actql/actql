import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {inspectAuthorizedDeliveryAttempt,
  installResultAccessAuthority, installResultAccessService} from
  './result-access.mjs';
import type {WireDeliveryAttemptLookup} from '../../packages/client-wire/index.js';

type LookupRequest = Parameters<typeof inspectAuthorizedDeliveryAttempt>[1];
type AuthorityConfiguration = Parameters<typeof installResultAccessAuthority>[0];
type ServiceConfiguration = Parameters<typeof installResultAccessService>[0];
type Fixture = {
  authorize: NonNullable<AuthorityConfiguration['authorizeDeliveryAttemptLookup']>;
  lookup(facts: LookupRequest): Promise<unknown>;
};

const receipt = JSON.parse(readFileSync(new URL(
  '../../packages/client-wire/fixtures/delivery-attempt.found.json',
  import.meta.url), 'utf8')) as Extract<WireDeliveryAttemptLookup, {kind: 'found'}>;
const cid = (char: string) => `sha256:${char.repeat(64)}`;
const request = () => ({
  indexKey: {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
    runDefinitionCid: receipt.attempt.run_definition_cid},
  principalId: 'principal-a', purpose: 'download', resultName: 'answer',
  attemptId: 'read-a',
});

function service({authorize, lookup}: Fixture) {
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
  // The other installer ports are unused in the lookup-only fixture.
  const authority = installResultAccessAuthority({
    authorizeResultReadRequest() {}, admitResultRead() {},
    authorizeResultRead() {}, authorizeDeliveryAttemptLookup: authorize,
  } as unknown as AuthorityConfiguration);
  return installResultAccessService({
    store, control, authority, now: () => '2026-09-24T00:00:00.000Z',
    createDigest() {},
    limits: {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20},
    frameLimits: {maxRowBytes: 1000, maxDepth: 20,
      maxFrameBytes: 10000},
  } as unknown as ServiceConfiguration);
}

test('attempt lookup keeps the authorized scalar and nested Run snapshot',
  async () => {
    let release!: () => void;
    let started!: () => void;
    const authorized = new Promise<void>(resolve => { started = resolve; });
    const gate = new Promise<void>(resolve => { release = resolve; });
    let authorizedRequest!: LookupRequest;
    let lookupRequest!: LookupRequest;
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
    submitted.indexKey.namespaceId = 'namespace-b';
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

for (const answer of ['found', 'absent']) {
  for (const revocation of ['deny', 'unavailable']) {
    test(`attempt lookup withholds ${answer} when its mutable authority becomes ${revocation}`,
      async () => {
        let release!: () => void, started!: () => void, allowed = true;
        const entered = new Promise<void>(resolve => { started = resolve; });
        const gate = new Promise<void>(resolve => { release = resolve; });
        const authorized: LookupRequest[] = [];
        let lookedUp!: LookupRequest, lookups = 0;
        const installed = service({
          async authorize(facts) {
            authorized.push(facts);
            if (!allowed && revocation === 'unavailable') {
              throw new Error('private authority detail');
            }
            return allowed;
          },
          async lookup(facts) {
            lookups++;
            lookedUp = facts;
            started();
            await gate;
            return answer === 'found' ? receipt : undefined;
          },
        });
        const submitted = request();
        const pending = inspectAuthorizedDeliveryAttempt(installed, submitted);
        await entered;
        submitted.indexKey.namespaceId = 'foreign';
        submitted.attemptId = 'other';
        allowed = false;
        release();
        await assert.rejects(pending, {code: 'ResultAccessDenied'});
        assert.equal(authorized.length, 2,
          'consume the same Owner after its authority changed, not a new validation frame');
        assert.strictEqual(authorized[0], lookedUp);
        assert.strictEqual(authorized[1], lookedUp);
        assert.equal(lookups, 1);
        assert.deepEqual(lookedUp, request());
        await assert.rejects(inspectAuthorizedDeliveryAttempt(installed, request()),
          {code: 'ResultAccessDenied'});
        assert.equal(authorized.length, 3);
        assert.notStrictEqual(authorized[2], lookedUp,
          'a new public operation has its own current observation');
        assert.equal(lookups, 1, 'the separately denied operation performs no Store lookup');
      });
  }
}
