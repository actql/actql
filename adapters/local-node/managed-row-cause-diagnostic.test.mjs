import test from 'node:test';
import assert from 'node:assert/strict';
import {checkedLocalManagedAdvance} from './managed-advance-diagnostic.mjs';
import {dispatchFailureSnapshot, publicBudgetFailureMessage, retainedBudgetFailureMessage}
  from '../host-node/client-dispatch-diagnostic.mjs';

test('original typed row cause reaches the same failure without reading private data or replacing cleanup', () => {
  const result = {}, owner = {}, secret = 'PRIVATE_QUERY_AND_PROVIDER_VALUE';
  const original = Object.assign(new Error(secret), {code: 'MoonBitHostFailure', cleanupOwner: owner});
  let checks = 0, causes = 0, steps = 0;
  const moon = {
    strategyModule_local_ManagedAdvanceCause(value) {
      assert.strictEqual(this, moon); assert.strictEqual(value, result); causes++; return 'evaluation.arithmetic_failure';
    },
    strategyModule_local_ManagedAdvanceRowStep(value) {
      assert.strictEqual(this, moon); assert.strictEqual(value, result); steps++; return 41;
    },
  };
  assert.throws(() => checkedLocalManagedAdvance(moon, result, value => {
    checks++; assert.strictEqual(value, result); throw original;
  }, 7), error => error === original);
  assert.deepEqual([checks, causes, steps], [1, 1, 1]);
  assert.strictEqual(original.cleanupOwner, owner);
  assert.equal(original.message, secret);
  assert.deepEqual(dispatchFailureSnapshot(original).primaryDiagnostic, {
    code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'row_failure',
    task: 7, step: 41, cause: 'evaluation.arithmetic_failure',
  });
  assert.equal(publicBudgetFailureMessage(original), 'Execution failed: phase=local_managed_advance; task=7; step=41; cause=evaluation.arithmetic_failure. Original execution failure; resource quantities were not retained.');
});

test('unavailable or malformed row diagnosis never replaces the original error or infers a memory quota', () => {
  for (const [cause, step] of [[undefined, 1], ['private query text', 1], ['x'.repeat(97), 1],
    ['rows.row_limit', -1], ['rows.row_limit', 1.5], ['rows.row_limit', 2147483648]]) {
    const original = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
    assert.throws(() => checkedLocalManagedAdvance({
      strategyModule_local_ManagedAdvanceCause: () => cause,
      strategyModule_local_ManagedAdvanceRowStep: () => step,
    }, {}, () => {throw original;}, 7), error => error === original);
    assert.equal(original.primaryDiagnostic, undefined);
  }
  const fields = {code: 'MoonBitHostFailure', phase: 'local_managed_advance',
    kind: 'row_failure', task: 0, step: 42, cause: 'rows.row_limit'};
  assert(publicBudgetFailureMessage({primaryDiagnostic: fields}).includes('cause=rows.row_limit.'));
  assert(!publicBudgetFailureMessage({primaryDiagnostic: fields}).includes('dimension='));
  for (const bad of [{...fields, budget: {}}, {...fields, dimension: 'execution_bytes'},
    {...fields, unit: 1}, {...fields, step: -1}, {...fields, cause: 'provider secret'},
    Object.defineProperty({...fields}, 'cause', {get() {assert.fail('no getter');}})]) {
    assert.equal(dispatchFailureSnapshot({primaryDiagnostic: bad}).primaryDiagnostic, undefined);
  }
  const original = Object.assign(new Error('original'), {code: 'MoonBitHostFailure'});
  assert.throws(() => checkedLocalManagedAdvance({
    strategyModule_local_ManagedAdvanceCause() {throw new Error('optional inspection');},
    strategyModule_local_ManagedAdvanceRowStep() {assert.fail('no call after throw');},
  }, {}, () => {throw original;}, 7), error => error === original);
});

test('only the same failed cold Run control frame retains its bounded original row cause', () => {
  const message = publicBudgetFailureMessage({primaryDiagnostic: {code: 'MoonBitHostFailure',
    phase: 'local_managed_advance', kind: 'row_failure', task: 7, step: 41,
    cause: 'evaluation.arithmetic_failure'}});
  const control = {revision: 4, physical_stop: 'confirmed', cancellation_requested: false};
  const state = {run_id: 'original-run', status: 'failed', result_available: false,
    next_action: {kind: 'none'}, terminal_error: {code: 'ACTQL_E_UNPUBLISHED_RUN', message}, control};
  const key = JSON.stringify(state);
  assert.equal(retainedBudgetFailureMessage(key, state, 'original-run', control), message);
  assert.equal(retainedBudgetFailureMessage(key, state, 'foreign-run', control), undefined);
  for (const status of ['running', 'needs_reconciliation', 'succeeded', 'cancelled']) {
    assert.equal(retainedBudgetFailureMessage(key, {...state, status}, 'original-run', control), undefined);
  }
  for (const changed of [{...control, physical_stop: 'unknown'}, {...control, revision: 5}]) {
    assert.equal(retainedBudgetFailureMessage(key, state, 'original-run', changed), undefined);
  }
  for (const bad of [message + ' private', message.replace('task=7', 'task=2147483648'),
    message.replace('cause=evaluation.arithmetic_failure.', 'cause=private query.'),
    message.replace('failure. Original', 'failure! Original')]) {
    assert.equal(retainedBudgetFailureMessage(JSON.stringify({...state, terminal_error: {...state.terminal_error, message: bad}}), state, 'original-run', control), undefined);
  }
});
