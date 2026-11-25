import assert from 'node:assert/strict';
import test from 'node:test';
import type {outputExportControl} from '../host-common/output-export-control.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {localOutputLimits} from './local-publication-limits.mjs';

type FixtureOptions = Readonly<{advance?: (count: number) => unknown; finish?: () => unknown; unselected?: boolean}>;

const ok = (value: unknown) => ({$tag: 1, _0: value});
function fixture({advance, finish = () => ok(exported), unselected = false}: FixtureOptions = {}) {
  const input = {}, selection = {}, preparation = {};
  const calls = {begin: 0, advance: 0, finish: 0, cancel: 0};
  const control: ReturnType<typeof outputExportControl> = runtimeCore({
    strategyRemoteManagedOutputEvidenceKind: () => 'unused-in-this-test',
    strategyHostResultTransformationBegin(actual: unknown, result: number, ...args: unknown[]) {
      assert.equal(actual, input);
      assert.equal(result, 0);
      assert.equal(args.at(-1), unselected ? undefined : selection);
      assert.equal(args.at(-2), undefined);
      calls.begin++;
      return ok(preparation);
    },
    strategyHostManagedResultTransformationBegin(actual: unknown, chosen: unknown) {
      assert.equal(actual, input);
      assert.equal(chosen, unselected ? undefined : selection);
      calls.begin++;
      return ok(preparation);
    },
    strategyHostResultTransformationAdvance(actual: unknown, quantum: number) {
      assert.equal(actual, preparation);
      assert.equal(quantum, 256);
      calls.advance++;
      return advance?.(calls.advance) ?? ok(calls.advance === 2);
    },
    strategyHostResultTransformationFinish(actual: unknown) {
      assert.equal(actual, preparation);
      calls.finish++;
      return finish();
    },
    strategyHostResultTransformationCancel(actual: unknown) {
      assert.equal(actual, preparation);
      calls.cancel++;
    },
    strategyHostManagedResultImportFinish() {
      assert.fail('no fallback to synchronous/unselected export');
    },
  }).outputExportControl;
  return {control, input, selection, preparation, calls};
}
const exported = {};

for (const managed of [false, true]) {
  test(`owned ${managed ? 'managed' : 'cell-backed'} Result uses its original metered poll without fallback`, async () => {
    const f = fixture();
    let polls = 0;
    const progress = (actual: unknown, quantum: number) => {
      assert.equal(actual, f.preparation);
      assert.equal(quantum, 256);
      return ++polls === 2;
    };
    const result = managed
      ? await f.control.transformManagedResultImport(f.input, f.selection, undefined, progress)
      : await f.control.beginResult(f.input, 0, localOutputLimits, undefined,
        f.selection, undefined, progress);
    assert.equal(result, exported);
    assert.equal(polls, 2);
    assert.deepEqual(f.calls, {begin: 1, advance: 0, finish: 1, cancel: 0});
  });
}

test('owned work failure cancels the same transformation and preserves the original cause', async () => {
  const f = fixture();
  const cause = new Error('actual metered refusal');
  await assert.rejects(f.control.transformManagedResultImport(f.input, f.selection,
    undefined, () => {throw cause;}), error => error === cause);
  assert.deepEqual(f.calls, {begin: 1, advance: 0, finish: 0, cancel: 1});
});

test('cell-backed Result uses bounded selected transformation', async () => {
  const f = fixture();
  assert.equal(await f.control.beginResult(f.input, 0, localOutputLimits,
    undefined, f.selection), exported);
  assert.deepEqual(f.calls, {begin: 1, advance: 2, finish: 1, cancel: 0});
});

test('captured Result without a Client selection polls the common preparation', async () => {
  const f = fixture({unselected: true});
  assert.equal(await f.control.beginResult(f.input, 0, localOutputLimits), exported);
  assert.deepEqual(f.calls, {begin: 1, advance: 2, finish: 1, cancel: 0});
});

test('managed Result without a Client selection polls the common preparation', async () => {
  const f = fixture({unselected: true});
  assert.equal(await f.control.finishManagedResultImport(f.input), exported);
  assert.deepEqual(f.calls, {begin: 1, advance: 2, finish: 1, cancel: 0});
});

test('captured Result without a Client selection yields before cancellation', async () => {
  const abort = new AbortController();
  const cause = new Error('UnselectedResultPreparationCancelled');
  const f = fixture({unselected: true, advance: () => {
    setTimeout(() => abort.abort(cause), 0);
    return ok(false);
  }});
  await assert.rejects(f.control.beginResult(f.input, 0, localOutputLimits,
    undefined, undefined, abort.signal), error => error === cause);
  assert.deepEqual(f.calls, {begin: 1, advance: 1, finish: 0, cancel: 1});
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
      f.input, f.selection), error => (error as Error).cause === cause);
    assert.equal(f.calls.cancel, 1);
  });
}
