import assert from 'node:assert/strict';
import test from 'node:test';
import {openNodeInferOperation} from './infer-operation.mjs';

const ok = value => ({$tag: 1, _0: value});

function fixture({count = 1, onSlot} = {}) {
  const active = {};
  const set = {};
  const inputReceipt = {};
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
    clientProgramStartRestoredPreparedInferExecution(...args) {
      calls.restoredStarts = (calls.restoredStarts ?? 0) + 1;
      calls.restoredInput = args[6];
      calls.enterOriginal = args.at(-1);
      return ok(active);
    },
    clientProgramInferApprovalInputExportBegin(owner, maxBatchBytes) {
      assert.equal(owner, active);
      calls.exports = (calls.exports ?? 0) + 1;
      return ok({maxBatchBytes});
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
    clientProgramInferPreparedCallBinding: value => value === set ?
      {_0: 'models/fixture', _1: 'task-cid', _2: 'request-cid'} : undefined,
    clientProgramInferPreparedInputWire: value => value === set ? 'input' : undefined,
    clientProgramInferPreparedInputReceipt: value => value === set ?
      inputReceipt : undefined,
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
    clientProgramResumeImmediateInferExecution(owner, admission, current) {
      assert.equal(owner, active);
      assert.equal(admission, 'admission');
      assert.equal(current(), true);
      calls.resumes++;
      waiting = false;
      return ok(undefined);
    },
    clientProgramModelInvocationGrantHandle(request, checkpoint, verified,
      at, immediate) {
      calls.grants ??= [];
      calls.grants.push({request, checkpoint, verified, at, immediate});
      return request === 'originals' && checkpoint === 'checkpoint' &&
        verified === 'verified' ? ok('grant') : {$tag: 0, _0: 'foreign'};
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
  return {moon, calls, inputReceipt};
}

test('deferred Model operation waits once and resumes the same owner', async () => {
  const {moon, calls, inputReceipt} = fixture();
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, deferDispatch: true,
    enterCall: () => { calls.entries++; return true; }});
  const waiting = await operation.run();
  assert.equal(waiting.kind, 'waiting');
  assert.equal(waiting.callSet.inputWire, 'input');
  assert.equal(waiting.callSet.inputReceipt, inputReceipt);
  assert.equal(waiting.callSet.count, 1);
  assert.deepEqual(waiting.callSet.binding, {providerId: 'models/fixture',
    taskCid: 'task-cid', fixedRequestCid: 'request-cid'});
  assert.equal(waiting.callSet.slotWire(0), 'slot');
  assert.equal(operation.preparedCallSet(), waiting.callSet);
  assert.deepEqual(await operation.materializeCallSet({quantum: 1}), {
    inputWire: 'input', binding: {providerId: 'models/fixture',
      taskCid: 'task-cid', fixedRequestCid: 'request-cid'}, slotWires: ['slot'],
  });
  assert.equal(await operation.run(), waiting);
  assert.deepEqual({starts: calls.starts, advances: calls.advances,
    resumes: calls.resumes, entries: calls.entries},
  {starts: 1, advances: 1, resumes: 0, entries: 0});
  const dispatchAdmission = {};
  const compiled = {};
  const runDefinition = {};
  const observation = {account: {}, principalId: 'owner'};
  assert.equal(operation.issueDispatch({
    issueCheckedClientInferDispatch(actualCompiled, actualDefinition,
      actualObservation) {
      assert.equal(actualCompiled, compiled);
      assert.equal(actualDefinition, runDefinition);
      assert.equal(actualObservation.account, observation.account);
      return dispatchAdmission;
    },
  }, {compiled, runDefinition, ...observation}), dispatchAdmission);
  assert.equal(operation.bindDispatch({
    bindCheckedClientInferDispatch(actualCompiled, active, actualDefinition,
      actualObservation) {
      assert.equal(actualCompiled, compiled);
      assert.equal(actualDefinition, runDefinition);
      assert.equal(actualObservation.account, observation.account);
      assert.equal(actualObservation.principalId, observation.principalId);
      return undefined;
    },
  }, {compiled, runDefinition, ...observation}), undefined);
  assert.equal(await operation.resumeApproved({grant: 'grant',
    admission: 'admission', now: () => 'now', current: () => true}), 'output');
  assert.equal(calls.starts, 1);
  assert.equal(calls.resumes, 1);
  assert.equal(operation.preparedCallSet(), undefined);
  await operation.close();
  assert.equal(calls.cleaned, 1);
});

test('journal readback is admitted before the waiting owner resumes', async () => {
  const {moon, calls} = fixture();
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, deferDispatch: true,
    enterCall: () => true});
  assert.equal((await operation.run()).kind, 'waiting');
  await assert.rejects(operation.resumeApprovedFromReadback({
    requestWire: 'foreign', checkpointWire: 'checkpoint',
    verifiedWire: 'verified', admission: 'admission',
    now: () => 'trusted-now', current: () => true,
  }));
  assert.equal(calls.resumes, 0);
  assert.equal((await operation.run()).kind, 'waiting');
  assert.equal(await operation.resumeApprovedFromReadback({
    requestWire: 'originals', checkpointWire: 'checkpoint',
    verifiedWire: 'verified', admission: 'admission',
    now: () => 'trusted-now', current: () => true,
  }), 'output');
  assert.deepEqual(calls.grants, [
    {request: 'foreign', checkpoint: 'checkpoint',
      verified: 'verified', at: 'trusted-now', immediate: false},
    {request: 'originals', checkpoint: 'checkpoint',
      verified: 'verified', at: 'trusted-now', immediate: false},
  ]);
  assert.equal(calls.resumes, 1);
  await operation.close();
});

test('ordinary allow resumes the same prepared operation without a grant', async () => {
  const {moon, calls} = fixture();
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, deferDispatch: true,
    enterCall: () => { calls.entries++; return true; }});
  assert.equal((await operation.run()).kind, 'waiting');
  assert.equal(calls.entries, 0);
  assert.equal(await operation.resumeImmediate({admission: 'admission',
    current: () => true}), 'output');
  assert.equal(calls.starts, 1);
  assert.equal(calls.resumes, 1);
  assert.equal(calls.grants, undefined);
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

test('restored prepared input uses the existing restoration entry and retains export access only while waiting', async () => {
  const {moon, calls, inputReceipt} = fixture();
  const restoredInput = {};
  const operation = openNodeInferOperation({moon, preparedProgram: {}, step: 2,
    graph: {}, registry: 'registry', values: 'values', fragment: 'fragment',
    ordered: 'ordered', provider: {}, restoredInput, deferDispatch: true,
    enterCall: () => true});
  const waiting = await operation.run();
  assert.equal(calls.starts, 0);
  assert.equal(calls.restoredStarts, 1);
  assert.equal(calls.restoredInput, restoredInput);
  assert.equal(waiting.callSet.inputReceipt, inputReceipt);
  assert.deepEqual(waiting.callSet.beginInputExport(16384), {maxBatchBytes: 16384});
  assert.equal(calls.exports, 1);
  for (const limit of [0, -1, 1.5, Infinity, 2147483648]) {
    assert.throws(() => waiting.callSet.beginInputExport(limit),
      /InferPreparedCallSetUnavailable/);
  }
  assert.equal(calls.exports, 1);
  await operation.close();
  assert.throws(() => waiting.callSet.beginInputExport(16384),
    /InferPreparedCallSetUnavailable/);
  assert.equal(calls.entries, 0);
  assert.equal(calls.cleaned, 1);
});

test('restored input cannot select an ordinary or composed execution fallback', () => {
  const {moon, calls} = fixture();
  const base = {moon, preparedProgram: {}, step: 2, graph: {},
    registry: 'registry', values: 'values', provider: {}, restoredInput: {},
    enterCall: () => true, deferDispatch: true};
  for (const override of [{deferDispatch: false}, {enterCall: undefined},
    {acquiredInput: {}}, {composedInput: {}}]) {
    assert.throws(() => openNodeInferOperation({...base, ...override}), TypeError);
  }
  assert.equal(calls.starts, 0);
  assert.equal(calls.restoredStarts, undefined);
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
