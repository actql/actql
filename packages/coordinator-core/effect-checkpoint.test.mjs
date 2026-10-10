import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitDispatchJson, effectCheckpointReports as reports, effectResumeDeliveries, prepareDispatch}
  from '@actql/coordinator-core';

// Independently authored protocol vectors, not runtime-generated expectations.
const fixture = JSON.parse(readFileSync(process.env.ACTQL_TEST_EFFECT_CHECKPOINT_VECTORS ??
  new URL('../../spec/fixtures/remote-effect-checkpoint-vectors.json', import.meta.url), 'utf8'));
const vector = name => fixture.vectors.find(value => value.name === name);
const limits = {maxWireBytes: 262144, maxNodes: 4096, maxDepth: 32};
const request = () => admitDispatchJson(vector('dispatch').canonical, vector('dispatch').cid);
const report = () => reports.admit(vector('report').canonical, request(), limits);
const rejected = {code: 'CoordinatorOwnerRejected'};
const resume = JSON.parse(readFileSync(process.env.ACTQL_TEST_EFFECT_RESUME_VECTORS ??
  new URL('../../spec/fixtures/remote-effect-resume-vectors.json', import.meta.url), 'utf8'));
const resumeDelivery = (original = report(), changes = {}) => effectResumeDeliveries.prepareJson(
  original, changes.wire ?? resume.delivery.body.resolution_wire,
  changes.authentication ?? resume.authentication,
  changes.reviewers ?? [{key_id: resume.authentication.key_id, reviewer_id: resume.authentication.reviewer_id}],
  changes.claim ?? {claimant: 'original-coordinator', generation: 1n},
  changes.limits ?? limits);

test('portable Checkpoint report and exact ACK agree with independent canonical vectors', () => {
  const admitted = report();
  const facts = reports.facts(admitted);
  assert.deepEqual(facts, {reportCid: vector('report').cid,
    dispatchCid: vector('dispatch').cid,
    checkpointCid: vector('checkpoint').body.checkpoint_cid,
    checkpointWire: vector('checkpoint').canonical});
  assert.equal(reports.acceptedJson(admitted), vector('reply').canonical);
  assert.deepEqual(reports.admitReplyJson(admitted, vector('reply').canonical), {kind: 'accepted'});
  assert.equal(reports.acceptedJson(admitted), vector('reply').canonical);
  assert.equal(Object.isFrozen(admitted), true);
  assert.equal(Object.isFrozen(facts), true);
});

test('another consumer attempt or generation cannot admit the original report', () => {
  const body = vector('dispatch').body;
  const fields = {coordinatorAuthority: body.coordinator_authority,
    runDefinitionCid: body.run_definition_cid, taskKey: body.task_key,
    taskAttempt: body.task_attempt, dispatchId: body.dispatch_id,
    siteKey: body.site_key, siteGeneration: body.site_generation,
    runtimeBundleCid: body.runtime_bundle_cid,
    connectorRegistration: body.connector_registration, connectorRevision: body.connector_revision,
    strategyRevision: body.strategy_revision, inputBindingCid: body.input_binding_cid,
    obligationsCid: body.obligations_cid, budgetCid: body.budget_cid,
    evidenceIssuerCapabilityCid: body.evidence_issuer_capability_cid, grantCid: body.grant_cid};
  for (const change of [{taskAttempt: 2}, {dispatchId: 'foreign-consumer'}, {siteGeneration: 2}]) {
    assert.throws(() => reports.admit(vector('report').canonical,
      prepareDispatch({...fields, ...change}), limits), rejected);
  }
});

test('noncanonical, corrupt Checkpoint and oversized observations are refused', () => {
  for (const body of [vector('report').canonical + ' ',
    vector('report').canonical.replace('review-1', 'review-2'),
    JSON.stringify({...vector('report').body, unexpected: true})]) {
    assert.throws(() => reports.admit(body, request(), limits), rejected);
  }
  assert.throws(() => reports.admit(vector('report').canonical, request(),
    {...limits, maxWireBytes: 32}), rejected);
  for (const maxWireBytes of [0, -1, 262145, Infinity, 1.5, '262144']) {
    assert.throws(() => reports.admit(vector('report').canonical, request(),
      {...limits, maxWireBytes}), {message: 'InvalidEffectCheckpointReportInput'});
  }
});

test('forged report handles and foreign ACKs cannot confirm the original observation', () => {
  const admitted = report();
  for (const fake of [{}, {...admitted}, request(), null]) {
    assert.throws(() => reports.facts(fake), {message: 'InvalidEffectCheckpointReport'});
    assert.throws(() => reports.acceptedJson(fake), {message: 'InvalidEffectCheckpointReport'});
  }
  for (const key of ['report_cid', 'checkpoint_cid', 'dispatch_request_cid']) {
    assert.throws(() => reports.admitReplyJson(admitted,
      JSON.stringify({...vector('reply').body, [key]: 'sha256:' + 'f'.repeat(64)})), rejected);
  }
  assert.throws(() => reports.admitReplyJson(admitted, vector('reply').canonical + ' '), rejected);
});

test('definitive refusal uses only closed codes and remains bound to the original report', () => {
  const admitted = report();
  for (const reason of ['authorization_denied', 'scope_mismatch', 'report_conflict']) {
    const expected = JSON.stringify({...vector('reply').body, outcome: 'refused', reason});
    assert.equal(reports.refusedJson(admitted, reason), expected);
    assert.deepEqual(reports.admitReplyJson(admitted, expected), {kind: 'refused', reason});
  }
  assert.throws(() => reports.refusedJson(admitted, 'private_cause'), rejected);
  assert.throws(() => reports.admitReplyJson(admitted, JSON.stringify({
    ...vector('reply').body, outcome: 'accepted', reason: 'report_conflict'})), rejected);
});

test('portable resume delivery uses the original common Owner and fixed independent body', () => {
  const original = report();
  const before = reports.facts(original);
  assert.equal(resumeDelivery(original), resume.delivery.canonical);
  // Common Resolution admission owns JSON framing; no value normalizer is added.
  assert.equal(resumeDelivery(original, {wire: resume.delivery.body.resolution_wire + ' '}),
    resume.delivery.canonical);
  assert.deepEqual(reports.facts(original), before);
  assert.equal(reports.acceptedJson(original), vector('reply').canonical);
  // Generation is delivery fencing metadata, never a new Run or attempt.
  assert.equal(resumeDelivery(original, {claim: {claimant: 'original-coordinator', generation: 2n}}),
    JSON.stringify({...resume.delivery.body, generation: '2'}));
});

test('portable resume delivery rejects forged original and foreign approval metadata', () => {
  const original = report();
  for (const fake of [{}, {...original}, request(), null]) {
    assert.throws(() => resumeDelivery(fake), {message: 'InvalidEffectCheckpointReport'});
  }
  assert.throws(() => resumeDelivery(original, {wire: '{'}), rejected);
  assert.throws(() => resumeDelivery(original, {reviewers: []}), rejected);
  for (const authentication of [{...resume.authentication, reviewer_id: 'other'},
    {...resume.authentication, key_id: 'other'},
    {...resume.authentication, expected_authority_scope_cid: 'sha256:' + 'f'.repeat(64)}]) {
    assert.throws(() => resumeDelivery(original, {authentication}), rejected);
  }
});

test('portable resume delivery refuses invalid and unbounded caller inputs before serialization', () => {
  const original = report();
  const invalid = {message: 'InvalidEffectResumeDeliveryInput'};
  for (const claim of [{claimant: '', generation: 1n}, {claimant: 'x'.repeat(257), generation: 1n},
    {claimant: 'é'.repeat(129), generation: 1n}, {claimant: 'a', generation: 0n},
    {claimant: 'a', generation: -1n}, {claimant: 'a', generation: 9223372036854775808n},
    {claimant: 'a', generation: 1}, {claimant: 'a', generation: 1n, current: true}]) {
    assert.throws(() => resumeDelivery(original, {claim}), invalid);
  }
  assert.throws(() => resumeDelivery(original, {authentication: {...resume.authentication, authorized: true}}), invalid);
  assert.throws(() => resumeDelivery(original, {reviewers: new Array(1)}), invalid);
  assert.throws(() => resumeDelivery(original, {wire: 'x'.repeat(limits.maxWireBytes + 1)}), invalid);
  for (const maximum of [0, -1, Infinity, 262145, '262144']) {
    assert.throws(() => resumeDelivery(original, {limits: {...limits, maxWireBytes: maximum}}), invalid);
  }
});

test('resume input limits apply before UTF-8 allocation, including the remaining aggregate budget', () => {
  const original = report();
  const NativeEncoder = globalThis.TextEncoder;
  const encoded = [];
  globalThis.TextEncoder = class extends NativeEncoder {
    encode(value) {
      encoded.push(value.length);
      assert.ok(value.length <= limits.maxWireBytes, 'oversized text reached the encoder');
      return super.encode(value);
    }
  };
  try {
    const invalid = {message: 'InvalidEffectResumeDeliveryInput'};
    const huge = 'x'.repeat(limits.maxWireBytes + 1);
    for (const changes of [{wire: huge},
      {authentication: {...resume.authentication, proof_preimage: huge}},
      {reviewers: [{key_id: huge, reviewer_id: resume.authentication.reviewer_id}]},
      {claim: {claimant: huge, generation: 1n}}]) {
      assert.throws(() => resumeDelivery(original, changes), invalid);
    }
    encoded.length = 0;
    assert.throws(() => resumeDelivery(original, {
      wire: 'x'.repeat(64), limits: {...limits, maxWireBytes: 65},
    }), invalid);
    assert.deepEqual(encoded, ['original-coordinator'.length, 64]);
  } finally {
    globalThis.TextEncoder = NativeEncoder;
  }
});

test('resume admission snapshots typed caller facts once without implicit string coercion', () => {
  const original = report();
  let reads = 0;
  const authentication = {...resume.authentication};
  Object.defineProperty(authentication, 'key_id', {enumerable: true, get() {
    reads++;
    return reads === 1 ? resume.authentication.key_id : {toString() {
      throw new Error('CallerValueCoerced');
    }};
  }});
  assert.equal(resumeDelivery(original, {authentication}), resume.delivery.canonical);
  assert.equal(reads, 1);
  authentication.key_id;
  assert.throws(() => resumeDelivery(original, {authentication}),
    {message: 'InvalidEffectResumeDeliveryInput'});
});
