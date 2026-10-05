import test from 'node:test';
import assert from 'node:assert/strict';
import {createCheckSupplementationSession, getCheckRequirementFrontier,
  equalCheckRequirementFrontiers} from './index.mjs';

test('supplementation requires an explicit finite positive attempt cap', () => {
  for (const maxAttempts of [undefined, 0, -1, 1.5, Infinity, NaN, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => createCheckSupplementationSession({check() {}}, {maxAttempts}),
      {code: 'InvalidCheckSupplementationSession'});
  }
  assert.throws(() => createCheckSupplementationSession({}, {maxAttempts: 1}),
    {code: 'InvalidCheckSupplementationSession'});
});

test('transport failures consume the attempt cap without manufacturing an outcome', async () => {
  let calls = 0;
  const failure = new Error('fixture transport failure');
  const session = createCheckSupplementationSession({async check() {calls++; throw failure;}},
    {maxAttempts: 2});
  for (const attempt of [1, 2]) {
    await assert.rejects(session.check('SELECT 1', {format: 'sql'}), error => error === failure);
    assert.equal(calls, attempt);
  }
  await assert.rejects(session.check('SELECT 1', {format: 'sql'}), error =>
    error.code === 'CheckSupplementationStopped' && error.attempts === 2 &&
    error.maxAttempts === 2 && error.decision.reason === 'attempt_budget');
  assert.equal(calls, 2);
});

test('overlapping supplementation calls refuse before consuming another attempt', async () => {
  let release, calls = 0;
  const response = {outcome: 'completed'};
  const session = createCheckSupplementationSession({check() {
    calls++; return new Promise(resolve => {release = resolve;});
  }}, {maxAttempts: 3});
  const pending = session.check('SELECT 1', {format: 'sql'});
  await assert.rejects(session.check('SELECT 2', {format: 'sql'}),
    {code: 'CheckSupplementationBusy'});
  assert.equal(calls, 1);
  release(response);
  const result = await pending;
  assert.equal(result.outcome, response);
  assert.equal(result.attempts, 1);
  assert.deepEqual(result.decision, {kind: 'stop', reason: 'frontier_unavailable'});
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.decision), true);
  await assert.rejects(session.check('SELECT 3', {format: 'sql'}),
    {code: 'CheckSupplementationStopped'});
  assert.equal(calls, 1);
});

test('unassociated and copied reports do not create comparable Requirement frontiers', () => {
  const report = {outcome: 'completed', report: {verdict: 'verified'}};
  assert.equal(getCheckRequirementFrontier(report), undefined);
  assert.equal(equalCheckRequirementFrontiers(report, structuredClone(report)), undefined);
});
