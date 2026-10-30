import assert from 'node:assert/strict';
import test from 'node:test';
import {startInstalledRowRun} from './installed-row-run.mjs';

const ok = value => ({$tag: 1, _0: value});

test('whole input consumes the same Run/reader/evidence originals without Query or output transfer', async () => {
  const acquisition = {}, originalRead = {}, ledger = {}, provider = {}, capacity = {};
  const run = {}, attempt = {}, borrow = {}, capture = {}, source = {}, identity = {}, logical = {}, evidence = {};
  const checkedOwner = {}, dag = {}, calls = [];
  let settled, observeStop, stopped = false, retired = false;
  const moon = {
    clientProgramInstalledSourceReadCheckLedger(read, actual) {
      assert.equal(read, originalRead); assert.equal(actual, ledger); return ok();
    },
    clientProgramInstalledWholeSourceReadStartRows(read, actual, nonce, verify, transfer, scratch) {
      assert.equal(read, originalRead); assert.equal(actual, acquisition); assert.equal(nonce, 'original');
      assert.equal(transfer, 1024n); assert.equal(scratch, 512n); settled = verify;
      assert.equal(verify(attempt), false); calls.push('start'); return ok(run);
    },
    clientProgramWholeSourceBorrowResponses(actual, selected) {
      assert.equal(actual, run); assert.equal(selected, acquisition); calls.push('borrow'); return ok(borrow);
    },
    clientProgramRowSourceBindResponseCleanup(actual, observe) {
      assert.equal(actual, borrow); observeStop = observe; return ok();
    },
    clientProgramRowSourceFinish(actual) {assert.equal(actual, run); assert.equal(settled(attempt), false); return ok();},
    clientProgramRowSourceAttempt: () => attempt,
    clientProgramRowSourceCaptureBegin() {assert.equal(settled(attempt), true); return ok();},
    clientProgramRowSourceCaptureAdvance: () => ok({_0: true, _1: 1n}),
    clientProgramRowSourceCapture: () => ok(capture),
    clientProgramRowSourceCaptureSource(actual) {assert.equal(actual, capture); return ok(source);},
    clientProgramCapturedTaskSourceMatches(prepared, actual, task) {
      assert.equal(prepared, checkedOwner); assert.equal(actual, source); assert.equal(task, 0); return true;
    },
    clientProgramIdentifyCapturedSourceRelation: () => ok(identity),
    clientProgramIssueWholeSourceInputLogical(prepared, actual, measured, selected) {
      assert.equal(prepared, checkedOwner); assert.equal(actual, source);
      assert.equal(measured, identity); assert.equal(selected, capacity); calls.push('logical'); return ok(logical);
    },
    clientProgramWholeSourceCheckComputeBinding(actual, owner, task) {
      assert.equal(actual, capture); assert.equal(owner, dag); assert.equal(task, 0); calls.push('binding'); return ok();
    },
    clientProgramWholeSourceIssueSourceEvidenceOriginal(selected, actual, measured, input, scope, policy) {
      assert.equal(selected, acquisition); assert.equal(actual, capture); assert.equal(measured, identity);
      assert.equal(input, logical); assert.equal(scope, 'scope'); assert.equal(policy, 'policy');
      calls.push('evidence'); return ok(evidence);
    },
    clientProgramRowSourceCloseAccounted() {
      if (!observeStop()) return {$tag: 0, _0: 'physical-stop-pending'};
      calls.push('close'); return ok();
    },
    clientProgramRowSourceCaptureCleanup: () => ok(true),
    clientProgramRowSourceCaptureCleanupAdvance: () => ok(true),
    clientProgramInstalledSourceReadRetire(read) {assert.equal(read, originalRead); retired = true; return ok();},
  };
  const reader = {
    async read() {assert.equal(this, reader); calls.push('read');},
    requestStop() {assert.equal(this, reader); calls.push('stop');},
    retry() {assert.equal(this, reader); calls.push('retry');},
    observe() {assert.equal(this, reader); return {cleanupConfirmed: stopped};},
  };
  const receiver = {prepare(options) {assert.equal(this, receiver); assert.equal(options, input); return reader;}};
  const currentRead = async () => {calls.push('current');};
  const input = {verifyRead: currentRead};
  const session = startInstalledRowRun({moon, acquisition, originalRead, ledger, wholeInput: true,
    nonce: 'original', capacity: {provider, transferBytes: 1024n, executionBytes: 512n}});
  await session.readProvider({receiver, prepare: receiver.prepare, options: input});
  const result = await session.complete({owner: {checkedOwner, wholeInput: true,
    providerCaptureCapacity: capacity, occurrence: {stage: 0, input: 0, task: 0}},
  prepared: {checkedSource: {}}, currentRead});
  assert.equal(result.logicalInput, logical);
  assert.equal(Object.hasOwn(result, 'requirement'), false);
  assert.equal(result.capture.originalWholeInput(), capture);
  const copied = {...result.capture};
  assert.throws(() => copied.originalWholeInput(), {code: 'ForeignInstalledSourceCapture'});
  result.capture.retainTask(dag, 0);
  await result.prepareSourceEvidenceOriginal({authorityScopeCid: 'scope', effectiveDataPolicyCid: 'policy'});
  assert.equal(result.capture.takeSourceEvidenceOriginal(), evidence);
  assert.throws(() => session.close(), error => error.cause === 'physical-stop-pending');
  assert.equal(retired, false);
  stopped = true;
  assert.equal(await session.cleanup(), true);
  assert.equal(retired, true);
  assert.throws(() => result.capture.originalWholeInput(), {code: 'ForeignInstalledSourceCapture'});
  assert.equal(calls.filter(value => value === 'start').length, 1);
  assert.equal(calls.filter(value => value === 'read').length, 1);
  assert.equal(calls.filter(value => value === 'logical').length, 1);
  assert.equal(calls.filter(value => value === 'evidence').length, 1);
});

test('whole input cannot select a bare, keyed or listing RowRun', () => {
  const base = {moon: {}, acquisition: {}, nonce: 'original', wholeInput: true, ledger: {},
    originalRead: {}, capacity: {provider: {}, transferBytes: 1n, executionBytes: 1n}};
  for (const patch of [{originalRead: undefined}, {ledger: undefined}, {keyed: true},
    {capacity: {provider: {}, listingReport: {}}}]) {
    assert.throws(() => startInstalledRowRun({...base, ...patch}), {code: 'InstalledWholeSourceReadUnavailable'});
  }
});
