import assert from 'node:assert/strict';
import test from 'node:test';
import {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
function fixture({beginFailure} = {}) {
  const parent = {}, prepared = {}, request = {}, plan = {}, events = [];
  const begin = (kind, ...args) => {
    assert.deepEqual(args.slice(0, 4), [parent, prepared, request, plan]);
    events.push({kind, args});
    if (beginFailure) throw beginFailure;
    return Object.create({$tag: 1});
  };
  const runtime = {
    clientProgramInstalledEffectOperationControlConstructionBegin: (...args) => begin('begin', ...args),
    clientProgramInstalledEffectOperationNativeConstructionBegin: (...args) => begin('begin', ...args),
    clientProgramInstalledEffectOperationMemberReceiptConstructionBegin: (...args) => begin('receipt', ...args),
    clientProgramInstalledEffectOperationControlConstructionComplete(...args) {
      assert.deepEqual(args, [parent, prepared, request, plan]);
      events.push({kind: 'complete'}); return Object.create({$tag: 1});
    },
  };
  const run = {runtime, value: parent, prepared, request, operationPlan: plan, readPlan() {}, closed: false};
  const work = prepareInstalledEffectControlConstruction(run);
  run.controlConstruction = work; run.retireControlConstruction = work.retire;
  return {work, events};
}
test('same control forwards opaque native quote before Reflect and preserves the legacy no-quote call', () => {
  const f = fixture(), original = Object.freeze({});
  let calls = 0;
  f.work(undefined, () => {calls++; assert.equal(f.events.length, 1);}, [], original);
  assert.equal(f.events[0].args[4], original); assert.equal(f.events[0].args.length, 5);
  assert.deepEqual(f.events.map(x => x.kind), ['begin', 'complete']);
  f.work(undefined, () => {calls++;}, []);
  assert.equal(f.events[2].args.length, 4); assert.equal(calls, 2);
});
test('native funding refusal prevents caller work and a Proxy quote executes no traps', () => {
  const original = new Error('resource refusal'), f = fixture({beginFailure: original}); let calls = 0;
  assert.throws(() => f.work(undefined, () => {calls++;}, [], {}), error => error === original);
  assert.equal(calls, 0); assert.deepEqual(f.events.map(x => x.kind), ['begin']);
  const fresh = fixture(); let traps = 0;
  const proxy = new Proxy({}, {get() {traps++; throw new Error();}, getOwnPropertyDescriptor() {traps++; throw new Error();}});
  assert.throws(() => fresh.work(undefined, () => {calls++;}, [], proxy), {code: 'InvalidInstalledEffectControlConstruction'});
  assert.equal(traps, 0); assert.equal(calls, 0); assert.deepEqual(fresh.events, []);
});
test('failed native caller keeps its original failed prefix without completion or another callback', () => {
  const f = fixture(), original = new Error('native recheck refusal');
  assert.throws(() => f.work(undefined, () => {throw original;}, [], {}), error => error === original);
  assert.deepEqual(f.events.map(x => x.kind), ['begin']);
  assert.throws(() => f.work(undefined, () => assert.fail('No callback after failed prefix'), [], {}), error => error === original);
  // Explicit same-owner retirement drops the failed closure after this
  // synchronous caller has returned. It calls no Core completion/physical ACK.
  assert.equal(f.work.retire(), true);
  assert.deepEqual(f.events.map(x => x.kind), ['begin']);
});

test('member Receipt selects its same-parent Ledger-capable entrance with the original opaque quote', () => {
  const f = fixture(), original = Object.freeze({});
  let calls = 0;
  f.work(undefined, () => {calls++;}, [], original, true);
  assert.equal(calls, 1);
  assert.equal(f.events[0].args[4], original);
  assert.deepEqual(f.events.map(x => x.kind), ['receipt', 'complete']);
  f.work(undefined, () => {calls++;}, [], original);
  assert.deepEqual(f.events.map(x => x.kind), ['receipt', 'complete', 'begin', 'complete']);
});
test('member Receipt funding refusal preserves the primary error and invalid role has no callback', () => {
  const primary = Object.freeze(new Error('refused')), f = fixture({beginFailure: primary});
  assert.throws(() => f.work(undefined, () => assert.fail('No receipt after refusal'), [], {}, true), error => error === primary);
  assert.deepEqual(f.events.map(x => x.kind), ['receipt']);
  for (const args of [[undefined, true], [{}, 1]]) {
    const fresh = fixture();
    assert.throws(() => fresh.work(undefined, () => assert.fail('No invalid receipt callback'), [], ...args),
      {code: 'InvalidInstalledEffectControlConstruction'});
    assert.deepEqual(fresh.events, []);
  }
});
