import type {CheckOutcome, Client, ClientError, CheckRequirementFrontier} from './index.d.ts';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createCheckSupplementationSession, getCheckRequirementFrontier,
  equalCheckRequirementFrontiers} from './index.mjs';

test('supplementation requires an explicit finite positive attempt cap', () => {
  for (const maxAttempts of [undefined, 0, -1, 1.5, Infinity, NaN, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => createCheckSupplementationSession({check() {}} as unknown as Pick<Client, 'check'>, {maxAttempts} as {maxAttempts: number}),
      {code: 'InvalidCheckSupplementationSession'});
  }
  assert.throws(() => createCheckSupplementationSession({} as Pick<Client, 'check'>, {maxAttempts: 1}),
    {code: 'InvalidCheckSupplementationSession'});
});

test('transport failures consume the attempt cap without manufacturing an outcome', async () => {
  let calls = 0;
  const failure = new Error('fixture transport failure');
  const session = createCheckSupplementationSession({async check() {calls++; throw failure;}},
    {maxAttempts: 2});
  for (const attempt of [1, 2]) {
    await assert.rejects(session.check('SELECT 1', {kind: 'text', scope: 'bound_input', format: 'sql'}), error => error === failure);
    assert.equal(calls, attempt);
  }
  await assert.rejects(session.check('SELECT 1', {kind: 'text', scope: 'bound_input', format: 'sql'}), error =>
    (error as ClientError).code === 'CheckSupplementationStopped' && (error as {attempts: number}).attempts === 2 &&
    (error as {maxAttempts: number}).maxAttempts === 2 && (error as {decision: {reason: string}}).decision.reason === 'attempt_budget');
  assert.equal(calls, 2);
});

test('overlapping supplementation calls refuse before consuming another attempt', async () => {
  let release!: (value: unknown) => void, calls = 0;
  const response = {outcome: 'completed'};
  const session = createCheckSupplementationSession({check() {
    calls++; return new Promise<CheckOutcome>(resolve => {release = resolve as (value: unknown) => void;});
  }}, {maxAttempts: 3});
  const pending = session.check('SELECT 1', {kind: 'text', scope: 'bound_input', format: 'sql'});
  await assert.rejects(session.check('SELECT 2', {kind: 'text', scope: 'bound_input', format: 'sql'}),
    {code: 'CheckSupplementationBusy'});
  assert.equal(calls, 1);
  release(response);
  const result = await pending;
  assert.equal(result.outcome, response);
  assert.equal(result.attempts, 1);
  assert.deepEqual(result.decision, {kind: 'stop', reason: 'frontier_unavailable'});
  assert.equal(Object.isFrozen(result), true);
  assert.equal(Object.isFrozen(result.decision), true);
  await assert.rejects(session.check('SELECT 3', {kind: 'text', scope: 'bound_input', format: 'sql'}),
    {code: 'CheckSupplementationStopped'});
  assert.equal(calls, 1);
});

test('unassociated and copied reports do not create comparable Requirement frontiers', () => {
  const report = {outcome: 'completed', report: {verdict: 'verified'}};
  assert.equal(getCheckRequirementFrontier(report as CheckOutcome), undefined);
  assert.equal(equalCheckRequirementFrontiers(report as unknown as CheckOutcome, structuredClone(report) as unknown as CheckOutcome), undefined);
});
