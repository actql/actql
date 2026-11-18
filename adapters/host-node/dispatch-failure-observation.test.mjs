import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';
import {dispatchFailureSnapshot, publicBudgetFailureMessage} from './client-dispatch-diagnostic.mjs';

// Explicit typed-runtime DATA ports. The companion real Core test passes its
// actual compiled original tuple through this same imported decoder.
const row = (position, rejection) => runtimeTupleFromFields({0: position, 1: rejection});
const view = (count = 1) => runtimeTupleFromFields({
  0: 'adaptive_dispatch', 1: 'no_strategy', 2: 3, 3: count, 4: true,
  5: count > 8, 6: Array.from({length: Math.min(count, 8)}, (_, i) => row(i, 'execution_limit')),
  7: 'unavailable',
});
const core = cause => runtimeCore({
  strategyRemoteManagedOutputEvidenceKind: () => 'unused-constructor',
  strategyHostNext: () => ({$tag: 0, _0: cause}),
});

test('actual imported next retains its original Err and caches only bounded Common facts', () => {
  const cause = Object.freeze({tag: 'original-NoStrategy'}), setup = {};
  let calls = 0, original;
  assert.throws(() => core(cause).next(setup, actual => {
    assert.equal(actual, setup); calls++; return view(19);
  }), error => {original = error; return error.code === 'MoonBitHostFailure' && error.cause === cause;});
  const first = dispatchFailureSnapshot(original), second = dispatchFailureSnapshot(original);
  assert.equal(calls, 1);
  assert.equal(first.code, 'MoonBitHostFailure');
  assert.equal(first.primaryDiagnostic, second.primaryDiagnostic);
  assert.deepEqual(first.primaryDiagnostic, {
    code: 'MoonBitHostFailure', phase: 'adaptive_dispatch', kind: 'no_strategy',
    task: 3, assessmentCount: 19, complete: true, truncated: true,
    decision: 'unavailable', candidateCount: 'unavailable',
    assessments: Array.from({length: 8}, (_, position) => ({position, rejection: 'execution_limit'})),
  });
  assert.equal(Object.isFrozen(first.primaryDiagnostic.assessments), true);
  assert.equal(first.primaryDiagnostic.assessments.every(Object.isFrozen), true);
  assert.equal(publicBudgetFailureMessage(original), undefined);
  const wrapper = Object.assign(new Error('same-wrapper'), {code: 'CapturedRunExecutionFailed',
    primaryFailure: original, cleanupDiagnostic: {owner: 'local_managed',
      phase: 'close_additional', continuation: 'blocked'}});
  const projected = dispatchFailureSnapshot(wrapper);
  assert.equal(projected.code, wrapper.code);
  assert.equal(projected.primaryDiagnostic, first.primaryDiagnostic);
  assert.deepEqual(projected.cleanupDiagnostic, wrapper.cleanupDiagnostic);
});

test('absent refused and malformed observation never masks primary or authorizes a copied diagnostic', () => {
  const cause = {}, selected = core(cause);
  for (const observe of [undefined, () => undefined, () => {throw new Error('original current refused');},
    () => view(9)._6, () => ({...view(), _3: 2147483648}),
    () => ({...view(), _1: 'resources'}),
    () => ({...view(0), _1: 'resources', _4: true}),
    () => ({...view(0), _1: 'not a typed kind', _4: false}),
    () => ({...view(), _6: [row(0, 'unknown.bad')]}),
    () => ({...view(), _6: Array(9).fill(row(0, 'execution_limit'))})]) {
    let error;
    assert.throws(() => selected.next({}, observe), value => {
      error = value; return value.code === 'MoonBitHostFailure' && value.cause === cause;
    });
    assert.equal(dispatchFailureSnapshot(error).primaryDiagnostic, undefined);
  }
  const copied = Object.assign(new Error('copied'), {primaryDiagnostic: {
    code: 'MoonBitHostFailure', phase: 'adaptive_dispatch', kind: 'no_strategy', task: 3,
  }});
  assert.equal(dispatchFailureSnapshot(copied).primaryDiagnostic, undefined);
  let getters = 0;
  Object.defineProperty(copied, 'primaryFailure', {get() {getters++; throw Error('foreign accessor');}});
  assert.equal(dispatchFailureSnapshot(copied).primaryDiagnostic, undefined);
  assert.equal(getters, 0);
});
