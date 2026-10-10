import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {admitDispatchJson, effectCheckpointReports as reports, prepareDispatch}
  from '@actql/coordinator-core';

// Independently authored protocol vectors, not runtime-generated expectations.
const fixture = JSON.parse(readFileSync(process.env.ACTQL_TEST_EFFECT_CHECKPOINT_VECTORS ??
  new URL('../../spec/fixtures/remote-effect-checkpoint-vectors.json', import.meta.url), 'utf8'));
const vector = name => fixture.vectors.find(value => value.name === name);
const limits = {maxWireBytes: 262144, maxNodes: 4096, maxDepth: 32};
const request = () => admitDispatchJson(vector('dispatch').canonical, vector('dispatch').cid);
const report = () => reports.admit(vector('report').canonical, request(), limits);
const rejected = {code: 'CoordinatorOwnerRejected'};

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
