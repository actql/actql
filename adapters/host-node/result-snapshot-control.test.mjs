import assert from 'node:assert/strict';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const limits = Object.freeze({maxWireBytes: 1000, maxNodes: 100, maxDepth: 10});
const ok = value => ({$tag: 1, _0: value});

function fixture(advance) {
  const exported = {}, preparation = {}, snapshot = {};
  const calls = {begin: 0, advance: 0, finish: 0, cancel: 0};
  const control = runtimeCore({
    strategyRemoteManagedOutputEvidenceKind: () => 'unused-in-this-test',
    strategyHostOutputSnapshotBegin(actual, bytes, nodes, depth) {
      assert.equal(actual, exported);
      assert.deepEqual([bytes, nodes, depth], [1000, 100, 10]);
      calls.begin++;
      return ok(preparation);
    },
    strategyHostOutputSnapshotAdvance(actual, quantum) {
      assert.equal(actual, preparation);
      assert.equal(quantum, 256);
      calls.advance++;
      return advance?.(calls.advance) ?? ok(calls.advance === 2);
    },
    strategyHostOutputSnapshotFinish(actual) {
      assert.equal(actual, preparation);
      calls.finish++;
      return ok(snapshot);
    },
    strategyHostOutputSnapshotCancel(actual) {
      assert.equal(actual, preparation);
      calls.cancel++;
    },
    strategyHostOutputExportAdmitCapturedResultSnapshot() {
      assert.fail('no synchronous snapshot fallback');
    },
  }).publicationControl;
  return {control, exported, calls};
}

test('snapshot adapter polls before transferring its opaque completed token', async () => {
  const f = fixture();
  assert.deepEqual(await f.control.admitCompletedResultSnapshot(f.exported, limits),
    {kind: 'captured-result-snapshot'});
  assert.deepEqual(f.calls, {begin: 1, advance: 2, finish: 1, cancel: 0});
});

test('snapshot cancellation yields and returns only private preparation custody', async () => {
  const abort = new AbortController();
  const reason = new Error('SnapshotPreparationCancelled');
  const f = fixture(() => {
    setTimeout(() => abort.abort(reason), 0);
    return ok(false);
  });
  await assert.rejects(f.control.admitCompletedResultSnapshot(
    f.exported, limits, abort.signal), error => error === reason);
  assert.deepEqual(f.calls, {begin: 1, advance: 1, finish: 0, cancel: 1});
});

test('pre-cancelled snapshot admission does not start a child preparation', async () => {
  const f = fixture();
  await assert.rejects(f.control.admitCompletedResultSnapshot(
    f.exported, limits, AbortSignal.abort()), {name: 'AbortError'});
  assert.deepEqual(f.calls, {begin: 0, advance: 0, finish: 0, cancel: 0});
});

test('snapshot typed refusal does not retry or fall back to synchronous admission', async () => {
  const cause = {kind: 'foreign-receipt'};
  const f = fixture(() => ({$tag: 0, _0: cause}));
  await assert.rejects(f.control.admitCompletedResultSnapshot(f.exported, limits),
    error => error.code === 'MoonBitHostFailure' && error.cause === cause);
  assert.deepEqual(f.calls, {begin: 1, advance: 1, finish: 0, cancel: 1});
});
