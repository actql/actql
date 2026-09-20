import assert from 'node:assert/strict';
import {checked} from '../runtime-result.mjs';

// Binding/lifecycle probe only: the callback is a test issuer, not evidence of
// actual SQL conversion. Real import correspondence is tested separately.
export function exerciseNativeFilePlan(moon, setup, wire) {
  const opened = [];
  const open = () => {
    const run = checked(moon.computeHostOpen(setup, () => false));
    opened.push(run);
    return run;
  };
  const planFor = run => {
    const plan = checked(moon.computeHostInputFilePlan(run, 0, wire, 4096, 10000));
    assert.ok(plan);
    return plan;
  };
  let calls = 0;
  const verified = () => { calls++; return true; };
  try {
    const run = open(), foreign = open(), plan = planFor(run);
    assert.equal(moon.computeHostInputFilePlanReuse(plan, foreign, 0, verified), false);
    assert.equal(moon.computeHostInputFilePlanReuse(plan, run, 1, verified), false);
    assert.equal(calls, 0, 'foreign bindings must not invoke the issuer');
    checked(moon.computeHostInputStreamBegin(run, 0, wire, 4096));
    assert.equal(moon.computeHostInputFilePlanReuse(plan, run, 0, verified), true);
    assert.ok(calls > 0);
    const admittedCalls = calls; // Evidence construction and attachment may both check liveness.
    assert.equal(moon.computeHostInputFilePlanReuse(plan, run, 0, verified), false);
    assert.equal(calls, admittedCalls, 'a consumed plan cannot issue twice');

    const refusedRun = open(), refused = planFor(refusedRun);
    assert.equal(moon.computeHostInputFilePlanReuse(refused, refusedRun, 0, () => false), false);
    assert.equal(moon.computeHostInputFilePlanReuse(refused, refusedRun, 0, verified), false);
    assert.equal(calls, admittedCalls, 'failed verification consumes issuance');

    const closedRun = open(), closed = planFor(closedRun);
    moon.computeHostClose(closedRun);
    assert.equal(moon.computeHostInputFilePlanReuse(closed, closedRun, 0, verified), false);
    assert.equal(checked(moon.computeHostInputFilePlan(closedRun, 0, wire, 4096, 10000)), undefined);
    assert.equal(calls, admittedCalls);

    const reentrantRun = open(), reentrant = planFor(reentrantRun);
    assert.equal(moon.computeHostInputFilePlanReuse(reentrant, reentrantRun, 0, () => {
      moon.computeHostClose(reentrantRun);
      return true;
    }), false, 'revocation during verification must not install evidence');
  } finally {
    for (const run of opened) moon.computeHostClose(run);
  }
}
