import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectResultProgress} from './effect-result-work.mjs';
import {runtimePair} from '../host-common/compiler-binding.generated.mjs';

const ok = value => ({$tag: 1, _0: value});
function fixture({prepare, advance} = {}) {
  const parent = {}, prepared = {}, request = {}, plan = {}, source = {}, transformation = {};
  const calls = {prepare: 0, advance: 0};
  const runtime = {
    clientProgramInstalledEffectResultWorkPrepare(...args) {
      calls.prepare++;
      assert.deepEqual(args, [parent, prepared, request, plan, source]);
      assert.equal(run.selecting, true);
      return prepare?.(run) ?? ok(undefined);
    },
    clientProgramInstalledEffectResultAdvance(...args) {
      calls.advance++;
      assert.deepEqual(args, [parent, prepared, request, plan, source, transformation, 7]);
      assert.equal(run.selecting, true);
      return advance?.(run, calls.advance) ?? ok(runtimePair(calls.advance === 2, 7));
    },
  };
  const run = {runtime, value: parent, prepared, request, operationPlan: plan,
    readPlan() {}, closed: false, selecting: false};
  return {run, source, transformation, calls};
}

test('Result progress keeps one original preparation across multiple bounded polls', () => {
  const f = fixture();
  const progress = prepareInstalledEffectResultProgress(f.run, f.source);
  assert.equal(progress(f.transformation, 7), false);
  assert.equal(progress(f.transformation, 7), true);
  assert.deepEqual(f.calls, {prepare: 1, advance: 2});
  assert.equal(f.run.selecting, false);
});

test('actual work refusal preserves its cause and never retries or replaces the receipt', () => {
  const primary = {};
  const f = fixture({advance: () => ({$tag: 0, _0: primary})});
  const progress = prepareInstalledEffectResultProgress(f.run, f.source);
  let failure;
  assert.throws(() => progress(f.transformation, 7), error => {
    failure = error; return error.cause === primary;
  });
  assert.throws(() => progress(f.transformation, 7), error => error === failure);
  assert.deepEqual(f.calls, {prepare: 1, advance: 1});
  assert.equal(f.run.selecting, false);
});

for (const field of ['runtime', 'value', 'prepared', 'request', 'operationPlan', 'readPlan']) {
  test(`Result progress refuses replacement of ${field} before native work`, () => {
    const f = fixture();
    const progress = prepareInstalledEffectResultProgress(f.run, f.source);
    f.run[field] = {};
    assert.throws(() => progress(f.transformation, 7), {code: 'ForeignInstalledEffectManagedRun'});
    assert.equal(f.calls.advance, 0);
    assert.equal(f.run.selecting, false);
  });
}

test('a tuple changed during native progress is refused after actual consumed work', () => {
  const f = fixture({advance: run => {run.request = {}; return ok(runtimePair(true, 7));}});
  const progress = prepareInstalledEffectResultProgress(f.run, f.source);
  assert.throws(() => progress(f.transformation, 7), {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(f.calls.advance, 1);
  assert.equal(f.run.selecting, false);
});

test('reentry is refused while the same physical Run retirement latch is held', () => {
  let progress;
  const f = fixture({advance: () => {
    assert.throws(() => progress(f.transformation, 7), {code: 'InstalledEffectResultWorkPending'});
    return ok(runtimePair(true, 7));
  }});
  progress = prepareInstalledEffectResultProgress(f.run, f.source);
  assert.equal(progress(f.transformation, 7), true);
  assert.equal(f.calls.advance, 1);
  assert.equal(f.run.selecting, false);
});

test('malformed progress cannot fall back to generic work or obtain another preparation', () => {
  const f = fixture({advance: () => ok(runtimePair(true, 8))});
  const progress = prepareInstalledEffectResultProgress(f.run, f.source);
  assert.throws(() => progress(f.transformation, 7), {code: 'InvalidInstalledEffectResultProgress'});
  assert.throws(() => progress(f.transformation, 7), {code: 'InvalidInstalledEffectResultProgress'});
  assert.deepEqual(f.calls, {prepare: 1, advance: 1});
});

test('an Array cannot replace the pinned compiler scalar tuple ABI', () => {
  const f = fixture({advance: () => ok([true, 7])});
  const progress = prepareInstalledEffectResultProgress(f.run, f.source);
  assert.throws(() => progress(f.transformation, 7), {code: 'InvalidInstalledEffectResultProgress'});
  assert.equal(f.run.selecting, false);
});

test('closed owner and invalid quanta refuse before native progress', () => {
  const f = fixture();
  const progress = prepareInstalledEffectResultProgress(f.run, f.source);
  for (const quantum of [0, -1, 257, NaN]) {
    assert.throws(() => progress(f.transformation, quantum), {code: 'InvalidInstalledEffectResultQuantum'});
  }
  f.run.closed = true;
  assert.throws(() => progress(f.transformation, 7), {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(f.calls.advance, 0);
});
