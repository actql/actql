import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeInferOperation} from './infer-operation.mjs';

const ok = value => ({$tag: 1, _0: value});

function fixture({count = 1, onSlot} = {}) {
  const active = {};
  const set = {};
  const calls = {starts: 0, advances: 0, resumes: 0, entries: 0,
    cancelled: 0, cleaned: 0};
  let waiting = true;
  let stopped = false;
  const moon = {
    clientProgramStartScopedEnteredInferExecution(...args) {
      calls.starts++;
      assert.equal(args.at(-1), true);
      calls.enterOriginal = args.at(-2);
      return ok(active);
    },
    clientProgramInferCallEntryOriginals: () => ({_0: 0, _1: 'call',
      _2: 'attempt', _3: 'authority'}),
    clientProgramAdvanceInferExecution(owner) {
      assert.equal(owner, active);
      calls.advances++;
      if (stopped) return ok({kind: 'stopped'});
      if (waiting) return ok({kind: 'waiting'});
      stopped = true;
      return ok({kind: 'complete'});
    },
    clientProgramInferExecutionPollKind: poll => poll.kind,
    clientProgramInferPreparedCallSet: owner => owner === active ? set : undefined,
    clientProgramInferPreparedCallCount: value => value === set ? count : undefined,
    clientProgramInferPreparedInputWire: value => value === set ? 'input' : undefined,
    clientProgramInferPreparedSlotWire: (value, index) => {
      onSlot?.(index);
      return value === set && index >= 0 && index < count
        ? count === 1 ? 'slot' : `slot-${index}` : undefined;
    },
    clientProgramResumeApprovedInferExecution(owner, grant, admission) {
      assert.equal(owner, active);
      assert.equal(grant, 'grant');
      assert.equal(admission, 'admission');
      calls.resumes++;
      waiting = false;
      return ok(undefined);
    },
    clientProgramInferExecutionOutput: () => 'output',
    clientProgramInferExecutionStopped: () => stopped,
    clientProgramCancelInferExecution() {
      calls.cancelled++;
      stopped = true;
      return true;
    },
    clientProgramCleanupInferExecution() {
      calls.cleaned++;
      return ok(true);
    },
  };
  return {moon, calls};
}

test('deferred Model operation waits once and resumes the same owner', async () => {
  const {moon, calls} = fixture();
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, deferDispatch: true,
    enterCall: () => { calls.entries++; return true; }});
  const waiting = await operation.run();
  assert.equal(waiting.kind, 'waiting');
  assert.equal(waiting.callSet.inputWire, 'input');
  assert.equal(waiting.callSet.count, 1);
  assert.equal(waiting.callSet.slotWire(0), 'slot');
  assert.equal(operation.preparedCallSet(), waiting.callSet);
  assert.deepEqual(await operation.materializeCallSet({quantum: 1}), {
    inputWire: 'input', slotWires: ['slot'],
  });
  assert.equal(await operation.run(), waiting);
  assert.deepEqual({starts: calls.starts, advances: calls.advances,
    resumes: calls.resumes, entries: calls.entries},
  {starts: 1, advances: 1, resumes: 0, entries: 0});
  assert.equal(await operation.resumeApproved({grant: 'grant',
    admission: 'admission', now: () => 'now', current: () => true}), 'output');
  assert.equal(calls.starts, 1);
  assert.equal(calls.resumes, 1);
  assert.equal(operation.preparedCallSet(), undefined);
  await operation.close();
  assert.equal(calls.cleaned, 1);
});

test('deferred Model operation stops and cleans up without approval', async () => {
  const {moon, calls} = fixture();
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, deferDispatch: true,
    enterCall: () => { calls.entries++; return true; }});
  assert.equal((await operation.run()).kind, 'waiting');
  await operation.close();
  assert.equal(calls.starts, 1);
  assert.equal(calls.entries, 0);
  assert.equal(calls.cleaned, 1);
  assert.equal(operation.preparedCallSet(), undefined);
});

test('call inventory materialization observes cancellation between slots', async () => {
  const abort = new AbortController();
  const seen = [];
  const {moon, calls} = fixture({count: 8, onSlot(index) {
    seen.push(index);
    if (index === 2) abort.abort();
  }});
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, deferDispatch: true,
    enterCall: () => { calls.entries++; return true; }, signal: abort.signal});
  assert.equal((await operation.run()).kind, 'waiting');
  await assert.rejects(operation.materializeCallSet({quantum: 1}),
    error => error?.name === 'AbortError');
  assert.deepEqual(seen, [0, 1, 2]);
  await operation.close();
  assert.equal(calls.entries, 0);
  assert.equal(calls.cleaned, 1);
});

test('asynchronous entry is refused without releasing its in-flight custody', async () => {
  const {moon, calls} = fixture();
  let settle;
  const pending = new Promise(resolve => { settle = resolve; });
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, deferDispatch: true,
    enterCall: () => pending});
  assert.equal(calls.enterOriginal({}), false);
  assert.equal(operation.entryFailure()?.message, 'AsyncInferAttemptEntry');
  assert.equal(operation.physicalStopped(), false);
  let closed = false;
  const closing = operation.close().then(() => { closed = true; });
  await Promise.resolve();
  assert.equal(closed, false);
  settle(true);
  await closing;
  assert.equal(calls.cleaned, 1);
});
