import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import {isEffectPreparationRefusal, refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';

function fixture(options = {}) {
  const {completeFailure} = options;
  const parent = {}, prepared = {}, request = {}, plan = {}, events = [];
  let active = false;
  const runtime = {
    clientProgramInstalledEffectOperationControlConstructionBegin(...args) {
      assert.deepEqual(args, [parent, prepared, request, plan]);
      assert.equal(active, false);
      active = true; events.push('begin');
      return {$tag: 1};
    },
    clientProgramInstalledEffectOperationControlConstructionComplete(...args) {
      assert.deepEqual(args, [parent, prepared, request, plan]);
      assert.equal(active, true); events.push('complete');
      if (Object.hasOwn(options, 'completeFailure')) throw completeFailure;
      active = false;
      return {$tag: 1};
    },
  };
  const run = {runtime, value: parent, prepared, request, operationPlan: plan,
    readPlan() {}, closed: false};
  const control = prepareInstalledEffectControlConstruction(run);
  run.controlConstruction = control;
  run.retireControlConstruction = control.retire;
  return {run, control, events, active: () => active};
}

test('observed semantic refusal completes its same synchronous frame before original Ledger observation', () => {
  const f = fixture();
  const original = refusedEffectPreparation(new Error('ObservedTargetRefusal'));
  assert.throws(() => f.control(undefined, () => {f.events.push('project'); throw original;}, []),
    error => error === original);
  assert.deepEqual(f.events, ['begin', 'project', 'complete']);
  assert.equal(f.active(), false);
  let reads = 0;
  assert.equal(f.control(undefined, () => {reads++; return 'original Ledger observation';}, []),
    'original Ledger observation');
  assert.equal(reads, 1);
  assert.equal(f.control.retire(), true);
});

for (const kind of ['transport', 'lookalike', 'resource']) {
  test(`unobserved ${kind} failure retains the failed frame and forbids a later callback`, () => {
    const f = fixture();
    const original = Object.assign(new Error(kind), {
      code: kind === 'lookalike' ? 'GitHubCommentForeignRepository' : kind === 'transport' ? 'EIO' : 'CapacityExceeded',
    });
    assert.throws(() => f.control(undefined, () => {throw original;}, []), error => error === original);
    assert.deepEqual(f.events, ['begin']);
    assert.equal(f.active(), true);
    assert.throws(() => f.control(undefined, () => assert.fail('No callback after failed prefix'), []),
      error => error === original);
  });
}

test('semantic refusal cannot complete a frame after its original current record changes', () => {
  const f = fixture();
  const original = refusedEffectPreparation(new Error('ObservedTargetRefusal'));
  let pending;
  assert.throws(() => f.control(undefined, () => {f.run.request = {}; throw original;}, []), error => {
    pending = error;
    assert(error instanceof AggregateError);
    assert.equal(error.cause, original);
    assert.equal(error.primaryFailure, original);
    assert.equal(error.code, 'InstalledEffectControlConstructionPending');
    assert.equal(error.errors[0], original);
    assert.equal(error.errors[1].code, 'ForeignInstalledEffectManagedRun');
    assert.equal(error.cleanupPending, true);
    assert.equal(isEffectPreparationRefusal(error), false);
    return true;
  });
  assert.deepEqual(f.events, ['begin']);
  assert.equal(f.active(), true);
  assert.throws(() => f.control(undefined, () => assert.fail('No callback after current loss'), []),
    error => error === pending);
});

for (const completionFailure of [new Error('OriginalCompletionUnknown'), undefined]) {
test(`semantic refusal retains both original and completion failure, including undefined=${completionFailure === undefined}`, () => {
  const f = fixture({completeFailure: completionFailure});
  const original = refusedEffectPreparation(new Error('ObservedTargetRefusal'));
  let pending;
  assert.throws(() => f.control(undefined, () => {throw original;}, []), error => {
    pending = error;
    assert(error instanceof AggregateError);
    assert.equal(error.cause, original);
    assert.equal(error.primaryFailure, original);
    assert.equal(error.code, 'InstalledEffectControlConstructionPending');
    assert.equal(error.errors.length, 2);
    assert.equal(error.errors[0], original);
    assert.equal(error.errors[1], completionFailure);
    assert.equal(error.cleanupPending, true);
    assert.equal(isEffectPreparationRefusal(error), false);
    return true;
  });
  assert.deepEqual(f.events, ['begin', 'complete']);
  assert.equal(f.active(), true);
  assert.throws(() => f.control(undefined, () => assert.fail('No callback after completion failure'), []),
    error => error === pending);
});
}

test('a marked then getter failure after the callback returned cannot impersonate its semantic result', () => {
  const f = fixture();
  const original = refusedEffectPreparation(new Error('ObservedTargetRefusal'));
  const invalid = {get then() {throw original;}};
  assert.throws(() => f.control(undefined, () => invalid, []), error => error === original);
  assert.deepEqual(f.events, ['begin']);
  assert.equal(f.active(), true);
  assert.throws(() => f.control(undefined, () => assert.fail('No callback after invalid task'), []),
    error => error === original);
});
