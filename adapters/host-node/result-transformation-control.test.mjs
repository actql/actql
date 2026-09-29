import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {localOutputLimits} from './local-values-plan.mjs';

const ok = value => ({$tag: 1, _0: value});
function fixture({advance, finish = () => ok(exported)} = {}) {
  const input = {}, selection = {}, preparation = {};
  const calls = {begin: 0, advance: 0, finish: 0, cancel: 0};
  const control = runtimeCore({
    strategyRemoteManagedOutputEvidenceKind: () => 'unused-in-this-test',
    strategyHostResultTransformationBegin(actual, result, ...args) {
      assert.equal(actual, input);
      assert.equal(result, 0);
      assert.equal(args.at(-1), selection);
      assert.equal(args.at(-2), undefined);
      calls.begin++;
      return ok(preparation);
    },
    strategyHostManagedResultTransformationBegin(actual, chosen) {
      assert.equal(actual, input);
      assert.equal(chosen, selection);
      calls.begin++;
      return ok(preparation);
    },
    strategyHostResultTransformationAdvance(actual, quantum) {
      assert.equal(actual, preparation);
      assert.equal(quantum, 256);
      calls.advance++;
      return advance?.(calls.advance) ?? ok(calls.advance === 2);
    },
    strategyHostResultTransformationFinish(actual) {
      assert.equal(actual, preparation);
      calls.finish++;
      return finish();
    },
    strategyHostResultTransformationCancel(actual) {
      assert.equal(actual, preparation);
      calls.cancel++;
    },
    strategyHostManagedResultImportFinish() {
      assert.fail('no fallback to synchronous/unselected export');
    },
  }).outputExportControl;
  return {control, input, selection, calls};
}
const exported = {};

test('cell-backed Result uses bounded selected transformation', async () => {
  const f = fixture();
  assert.equal(await f.control.beginResult(f.input, 0, localOutputLimits,
    undefined, f.selection), exported);
  assert.deepEqual(f.calls, {begin: 1, advance: 2, finish: 1, cancel: 0});
});

test('cell-backed Result cancellation retains the same cleanup path', async () => {
  const abort = new AbortController();
  const f = fixture({advance: () => {
    setTimeout(() => abort.abort(), 0);
    return ok(false);
  }});
  await assert.rejects(f.control.beginResult(f.input, 0, localOutputLimits,
    undefined, f.selection, abort.signal), {name: 'AbortError'});
  assert.deepEqual(f.calls, {begin: 1, advance: 1, finish: 0, cancel: 1});
});

test('bounded Result transformation transfers completion without cancellation', async () => {
  const f = fixture();
  assert.equal(await f.control.transformManagedResultImport(f.input, f.selection),
    exported);
  assert.deepEqual(f.calls, {begin: 1, advance: 2, finish: 1, cancel: 0});
});

test('Result transformation yields and releases preparation on caller cancellation', async () => {
  const abort = new AbortController();
  const f = fixture({advance: () => {
    setTimeout(() => abort.abort(), 0);
    return ok(false);
  }});
  await assert.rejects(f.control.transformManagedResultImport(
    f.input, f.selection, abort.signal), {name: 'AbortError'});
  assert.deepEqual(f.calls, {begin: 1, advance: 1, finish: 0, cancel: 1});
});

test('a cancelled Result export does not acquire preparation', async () => {
  const f = fixture();
  await assert.rejects(f.control.transformManagedResultImport(
    f.input, f.selection, AbortSignal.abort()), {name: 'AbortError'});
  assert.deepEqual(f.calls, {begin: 0, advance: 0, finish: 0, cancel: 0});
});

for (const stage of ['advance', 'finish']) {
  test(`Result ${stage} failure preserves cause and cancels without fallback`, async () => {
    const cause = {typedFailure: stage};
    const failure = () => ({$tag: 0, _0: cause});
    const f = fixture(stage === 'advance' ? {advance: failure}
      : {advance: () => ok(true), finish: failure});
    await assert.rejects(f.control.transformManagedResultImport(
      f.input, f.selection), error => error.cause === cause);
    assert.equal(f.calls.cancel, 1);
  });
}
