import assert from 'node:assert/strict';
import test from 'node:test';
import * as api from '../../adapters/host-common/result-access.mjs';
import {createResultDeliveryFixture} from '../../scripts/fixtures/result-delivery-acceptance.mjs';
import {openResultDeliveryControl} from './index.mjs';

const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const fixed = digit => 'sha256:' + digit.repeat(64);
function originalFixture() {
  const control = openResultDeliveryControl();
  const fixture = createResultDeliveryFixture(api, control);
  const grant = control.issueResultReadGrant(fixture.index, fixture.manifest, {
    resultNames: ['answer'], formats: ['json'], principalId: 'principal', purpose: 'download',
    dataCeilingCid: fixed('a'), maxBytes: 1024, maxUses: 1,
    expiresAt: '2026-10-02T00:00:00.000Z', authorizationContextCid: fixed('2'),
    egressAdmissionCid: fixed('3'),
  }, limits);
  let reads = 0;
  const request = {get resultName() { reads++; return 'answer'; },
    get format() { reads++; return 'json'; },
    get attemptId() { reads++; return 'original-attempt'; },
    get requestedAt() { reads++; return '2026-10-01T00:00:01.000Z'; }};
  const attempt = control.issueDeliveryAttempt(fixture.index, fixture.manifest, grant, request, limits);
  assert.equal(reads, 4);
  return {...fixture, control, grant, attempt};
}

test('issued delivery capture retains exact immutable facts without JSON parsing', () => {
  const f = originalFixture();
  const parse = JSON.parse;
  let parses = 0;
  JSON.parse = (...args) => { parses++; return Reflect.apply(parse, JSON, args); };
  let original, facts;
  try {
    original = f.control.captureIssuedDeliveryAttempt(f.attempt, f.index, f.manifest, f.grant, limits);
    facts = f.control.readIssuedDeliveryAttempt(original);
    assert.equal(f.control.captureIssuedDeliveryAttempt(f.attempt, f.index, f.manifest, f.grant, limits), original);
  } finally { JSON.parse = parse; }
  assert.equal(parses, 0);
  assert.equal(facts.attempt, f.attempt);
  assert.equal(facts.grant, f.grant);
  assert.equal(facts.index, f.index);
  assert.equal(facts.manifest, f.manifest);
  assert(Object.isFrozen(facts) && Object.isFrozen(facts.request) && Object.isFrozen(facts.limits));
  assert.deepEqual(facts.request, {resultName: 'answer', format: 'json',
    attemptId: 'original-attempt', requestedAt: '2026-10-01T00:00:01.000Z'});
});

test('issued delivery capture refuses copies and foreign receivers, and keeps raw admission compatible', () => {
  const f = originalFixture();
  const original = f.control.captureIssuedDeliveryAttempt(f.attempt, f.index, f.manifest, f.grant, limits);
  let fieldReads = 0;
  const proxy = new Proxy(f.attempt, {get() { fieldReads++; throw new Error('CopiedViewRead'); }});
  for (const attempt of [{...f.attempt}, proxy]) {
    assert.throws(() => f.control.captureIssuedDeliveryAttempt(attempt, f.index, f.manifest, f.grant, limits),
      {message: 'ForeignRunHostDelivery'});
  }
  assert.equal(fieldReads, 0);
  for (const value of [undefined, {}, {...original}, new Proxy(original, {})]) {
    assert.throws(() => f.control.readIssuedDeliveryAttempt(value), {message: 'ForeignRunHostDeliveryOriginal'});
  }
  assert.throws(() => openResultDeliveryControl().readIssuedDeliveryAttempt(original),
    {message: 'ForeignRunHostDeliveryOriginal'});
  const equalGrant = f.control.admit('result_read_grant', f.grant.wire, limits);
  assert.throws(() => f.control.captureIssuedDeliveryAttempt(f.attempt, f.index, f.manifest, equalGrant, limits),
    {message: 'RunHostDeliveryOriginalMismatch'});
  const admitted = f.control.admit('delivery_attempt', f.attempt.wire, limits);
  assert.equal(f.control.captureIssuedDeliveryAttempt(admitted, f.index, f.manifest, f.grant, limits), undefined);
  assert.equal(f.control.captureIssuedDeliveryAttempt(f.attempt, f.index, f.manifest, f.grant,
    {...limits, maxNodes: limits.maxNodes + 1}), undefined);
});

test('normal Result access preserves the issued attempt through Store selection', async () => {
  const base = openResultDeliveryControl();
  let issues = 0, attemptAdmissions = 0, grantAdmissions = 0;
  const control = {...base,
    issueDeliveryAttempt(...args) { issues++; return base.issueDeliveryAttempt(...args); },
    admit(name, ...args) {
      if (name === 'delivery_attempt') attemptAdmissions++;
      if (name === 'result_read_grant') grantAdmissions++;
      return base.admit(name, ...args);
    },
  };
  const f = createResultDeliveryFixture(api, control, {originals: true});
  const result = await f.deliver();
  assert.equal(result.idempotent, false);
  assert.equal(f.state.chunks.join(''), '[{"value":7}]');
  assert(issues > 0 && issues <= 1);
  assert.equal(attemptAdmissions, 0);
  assert.equal(grantAdmissions, 0);
  assert.equal(f.state.grantUses, 1);
  assert.equal(f.state.finishes, 1);
  // Each public read still obtains current authorization. The pure capture
  // cannot disclose an old receipt after a new Deny.
  f.state.allowed = false;
  await assert.rejects(f.deliver(), {code: 'ResultDeliveryDenied'});
  assert.equal(f.state.readers, 1);
});


test('copied Store selection echoes cannot expose Result rows', async () => {
  const control = openResultDeliveryControl();
  const f = createResultDeliveryFixture(api, control, {originals: true});
  const select = f.store.createDeliveryAttempt;
  f.store.createDeliveryAttempt = async (...args) => {
    const reply = await select(...args);
    return {...reply, original: {...reply.original}};
  };
  await assert.rejects(f.deliver(), {code: 'InvalidResultDeliveryAttemptState'});
  assert.equal(f.state.readers, 0);
  assert.equal(f.state.records.length, 0);
  assert.equal(f.state.chunks.length, 0);
  assert.equal(f.state.grantUses, 1);
});
