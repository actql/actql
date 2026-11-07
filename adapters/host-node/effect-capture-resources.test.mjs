import assert from 'node:assert/strict';
import test from 'node:test';
import resources from './ordinary-node-resource-runtime.cjs';
import {prepareEffectCaptureResources} from './effect-capture-resources.mjs';

// Existing actual Node Resource supplier and original child callbacks. Core
// phase results are explicit ports, not a matching Common or quota proof.
const ok = value => ({$tag:1, _0:value});
function fixture({live = false, beginFailure, reserveFailure, retireFailure,
  retirementCurrent = false, complete} = {}) {
  const events = [], request = {}, definition = {}, parent = {}, policy = {}, value = {};
  let view, admission, originalInput, retired = 0, failRetire = retireFailure, stopped = false;
  const stop = () => {
    assert.equal(admission.ports.report(0,0,0,0n,0n,0n,0n,0n,0n,0n,0,0,0), 0);
    assert.equal(admission.ports.status(2), 0);
    stopped = true;
  };
  const moon = {
    clientLocalResourcePolicyOriginal() {assert.equal(this, moon); return policy;},
    clientProgramRequestPreparationControl(actual) {assert.equal(actual, policy); return [1024n,0n];},
    clientLocalPreparationResourceLimits(actual) {
      assert.equal(actual, policy); return [100n,100n,100n,100000n,1000000n,1000000n];
    },
    clientProgramPrepareLocalPreparationAdmission(original, input) {
      assert.equal(view.status().pending, true); originalInput = input;
      admission = {original, ports:resources.prepareOriginalLocalPreparationPorts(original, input)};
      events.push('initial'); return ok(admission);
    },
    clientProgramBeginRequestPreparation(actual, input, selected) {
      assert.equal(actual, admission); assert.equal(input, originalInput); assert.equal(selected, policy);
      events.push('parent'); if (beginFailure !== undefined) throw beginFailure;
      assert.equal(admission.ports.status(0), 0); return ok(parent);
    },
    clientProgramAbortRequestPreparation(actual) {
      assert.equal(actual, parent); events.push('abort');
      if (!stopped) {
        // Actual Core finish_preparation_retirement enters reservation_check,
        // which calls check_imported_child_ledger's SINGLE original current.
        // A consumed-return retry sees the already closed original instead.
        if (retirementCurrent) {
          const before = events.filter(value => value === 'current').length;
          assert.equal(admission.ports.status(1), 0);
          assert.equal(events.filter(value => value === 'current').length, before + 1);
        }
        stop();
      }
      if (failRetire !== undefined) {const error = failRetire; failRetire = undefined; throw error;}
      return ok(undefined);
    },
    clientProgramCleanupLocalPreparationAdmission(actual) {
      assert.equal(actual, admission); events.push('cancel-initial');
      assert.equal(admission.ports.cancelUnpublished(), 0); return ok(undefined);
    },
    clientProgramPrepareInstalledEffectCaptureRecovery(run, prepared, identity, originalDefinition, wire, nodes, depth) {
      assert.equal(this, moon); assert.equal(view.status().pending, true);
      assert.equal(run, managed.value); assert.equal(prepared, managed.prepared);
      assert.equal(identity, request); assert.equal(originalDefinition, managed.definitionOriginal.definition);
      assert.deepEqual([wire,nodes,depth], [limits.maxWireBytes,limits.maxNodes,limits.maxDepth]);
      events.push('live-fixed');
      if (beginFailure !== undefined) throw beginFailure;
      return ok(value);
    },
    clientProgramReserveInstalledEffectCaptureRecovery(actual, bytes) {
      assert.equal(actual, value); events.push(['live-grow', bytes]);
      if (reserveFailure !== undefined) throw reserveFailure;
      return ok(undefined);
    },
    clientProgramReserveInstalledEffectCaptureDecoded(actual, wire) {
      assert.equal(actual, value); assert.equal(typeof wire, 'string');
      events.push(['live-decoded', wire]);
      if (reserveFailure !== undefined) throw reserveFailure;
      return ok(undefined);
    },
    clientProgramCompleteInstalledEffectCaptureRecovery(actual) {
      assert.equal(this, moon);assert.equal(actual, value);
      assert.equal(view.status().busy, true);events.push('live-complete');
      complete?.();
      return ok(undefined);
    },
    clientProgramRetireInstalledEffectCaptureRecovery(actual) {
      assert.equal(actual, value); events.push('live-retire');
      if (failRetire !== undefined) {const error = failRetire; failRetire = undefined; throw error;}
      return ok(undefined);
    },
  };
  const limits = Object.freeze({maxWireBytes:10000, maxNodes:1000, maxDepth:64});
  const managed = live ? {value:{}, prepared:{}, request, definitionOriginal:{definition:{}}} : undefined;
  const control = {
    reserveEffectCaptureRecovery(owner, input, identity, runDefinition, bytes, selected) {
      assert.equal(this, control); assert.equal(owner, parent); assert.equal(input, originalInput);
      assert.equal(input.request, request); assert.equal(input.runDefinition, definition);
      assert.equal(identity, request); assert.equal(runDefinition, definition);
      assert.deepEqual(selected, limits); events.push(['cold-grow', bytes]);
      if (reserveFailure !== undefined) throw reserveFailure;
    },
  };
  return {events, request, definition, control, moon,
    open(options = {}) {
      return prepareEffectCaptureResources({moon, control, request, runDefinition:definition,
        contractLimits:limits, managed, assertCurrent() {events.push('current');},
        retain(original) {assert.equal(view, undefined); view = original; events.push('retain');},
        retired(original) {assert.equal(original, view); retired++; events.push('retired');}, ...options});
    }, get view() {return view;}, get retired() {return retired;}};
}

test('cold saved Request retains before opening and grows SAME parent before the original read', async () => {
  const f = fixture(), view = f.open();
  assert.deepEqual(f.events.filter(value => value !== 'current'),
    ['retain','initial','parent',['cold-grow',0]]);
  assert.equal(f.events[0], 'retain');
  view.begin(); view.reserve(777); view.finish(false);
  assert.equal(await view.close(), true); assert.equal(await view.close(), true);
  assert.equal(f.events.filter(value => value === 'abort').length, 1);
  assert.equal(f.retired, 1);
  assert.throws(() => view.reserve(777), {code:'EffectCaptureResourceUnavailable'});
});

test('live capture uses SAME adopted Run and never opens a second Request Resource', async () => {
  const f = fixture({live:true}), view = f.open();
  view.begin(); view.reserve(123); view.reserveDecoded('{"original":true}'); view.finish(false);
  assert.equal(await view.close(), true);
  assert.equal(f.events.includes('initial'), false); assert.equal(f.events.includes('parent'), false);
  assert.equal(f.events.includes('abort'), false);
  assert.deepEqual(f.events.filter(Array.isArray), [['live-grow',123], ['live-decoded','{"original":true}']]);
  assert.equal(f.events.filter(value => value === 'live-complete').length, 1);
  assert.equal(f.events.filter(value => value === 'live-retire').length, 1);
});

test('failed parent construction retains the original initial cleanup instead of inventing a Run', async () => {
  const cause = new Error('original begin failure'), f = fixture({beginFailure:cause});
  assert.throws(() => f.open(), error => error === cause);
  assert.equal(await f.view.close(), true); assert.equal(f.retired, 1);
  assert.equal(f.events.includes('cancel-initial'), true); assert.equal(f.events.includes('abort'), false);
});

test('original pending physical child keeps capture reservation until its SAME retry stops', async () => {
  const f = fixture({live:true}), view = f.open(); let pending = true, retries = 0;
  const child = {status: () => ({pending}), retry() {retries++; return {pending};}};
  const cause = Object.assign(new Error('original schema child'), {cleanupPending:true, cleanupHandle:child});
  view.begin(); view.reserve(128); view.finish(true, cause);
  assert.equal(f.events.includes('live-complete'), false);
  assert.equal(await view.close(), false); assert.equal(retries, 1);
  assert.equal(f.events.includes('live-retire'), false); assert.equal(f.retired, 0);
  pending = false;
  assert.equal(await view.close(), true); assert.equal(retries, 1); assert.equal(f.retired, 1);
});

test('consumed original parent return failure retries SAME duty without another reservation', async () => {
  const cause = new Error('settlement after consumption'), f = fixture({retireFailure:cause});
  const view = f.open(); view.begin(); view.reserve(64); view.finish(false);
  await assert.rejects(view.close(), error => error === cause);
  assert.equal(f.retired, 0); assert.equal(view.status().pending, true);
  assert.equal(await view.close(), true); assert.equal(f.retired, 1);
  assert.deepEqual(f.events.filter(Array.isArray), [['cold-grow',0],['cold-grow',64]]);
  assert.equal(f.events.filter(value => value === 'parent').length, 1);
});

test('close during original current check refuses BEFORE any recovery resource constructor', async () => {
  const f = fixture(); let closing;
  assert.throws(() => f.open({assertCurrent() {closing = f.view.close();}}),
    {code:'EffectCaptureResourceUnavailable'});
  assert.equal(await closing, true); assert.equal(f.events.includes('initial'), false);
});

test('a busy original decode and unavailable cleanup carrier cannot become retirement ACK', async () => {
  const f = fixture({live:true}), view = f.open(); view.begin();
  assert.equal(await view.close(), false); assert.equal(f.events.includes('live-retire'), false);
  const original = new Proxy({}, {getOwnPropertyDescriptor() {throw new Error('unavailable');}});
  assert.doesNotThrow(() => view.finish(true, original));
  assert.equal(await view.close(), false); assert.equal(f.retired, 0);
});

test('live selected extent refuses non-Int inputs before the typed reservation port', async () => {
  const f = fixture({live:true}), view = f.open();
  for (const bytes of [-1, 0.5, NaN, Infinity, 2147483648, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => view.reserve(bytes), {code:'EffectCaptureResourceExtentInvalid'});
  }
  assert.deepEqual(f.events.filter(Array.isArray), []);
  assert.equal(await view.close(), true);
});

test('returned decoded owner stays backed through its original failed schema cleanup', async () => {
  const f = fixture({live:true}), view = f.open(), cause = new Error('original schema cleanup');
  let pending = true, cleanupCalls = 0;
  view.begin(); view.reserve(256);
  view.retainCleanup(async () => {
    cleanupCalls++; f.events.push('decoded-cleanup');
    if (pending) throw cause;
  });
  view.finish(false);
  assert.equal(f.events.filter(value => value === 'live-complete').length, 1);
  await assert.rejects(view.close(), error => error === cause);
  assert.equal(f.events.includes('live-retire'), false); assert.equal(f.retired, 0);
  pending = false; assert.equal(await view.close(), true);
  assert.equal(cleanupCalls, 2); assert.equal(f.retired, 1);
  assert.ok(f.events.indexOf('live-retire') > f.events.lastIndexOf('decoded-cleanup'));
});

test('schema returned during pending close is retained before the SAME reservation can settle', async () => {
  const f = fixture({live:true}), view = f.open(); let cleaned = 0;
  view.begin(); view.reserve(64);
  assert.equal(await view.close(), false);
  view.retainCleanup(() => {cleaned++;});
  assert.throws(() => view.finish(false), {code:'EffectCaptureResourceUnavailable'});
  assert.equal(f.events.includes('live-complete'), false);
  assert.equal(await view.close(), true);
  assert.equal(cleaned, 1); assert.equal(f.retired, 1);
  assert.throws(() => view.retainCleanup(() => {}), {code:'EffectCaptureResourceUnavailable'});
});

for (const primary of [new Error('original current refinement refusal'), undefined]) {
  test(`successful Store return keeps SAME duty on ${primary === undefined ? 'undefined' : 'current'} refinement failure`, async () => {
    const f = fixture({live:true, complete() {throw primary;}}), view = f.open();
    view.begin();view.reserve(128);
    assert.throws(() => view.finish(false), cause => cause === primary);
    assert.equal(view.status().busy, false);assert.equal(view.status().pending, true);
    assert.equal(f.retired, 0);
    assert.deepEqual(f.events.filter(Array.isArray), [['live-grow',128]]);
    assert.equal(await view.close(), true);assert.equal(f.retired, 1);
    assert.equal(f.events.filter(value => value === 'live-complete').length, 1);
    assert.equal(f.events.filter(value => value === 'live-retire').length, 1);
  });
}

test('cold capture retirement retains original current until SAME Request settlement and consumed return retry', async () => {
  const cause = new Error('same original consumed settlement return');
  const f = fixture({retirementCurrent:true, retireFailure:cause}), view = f.open();
  view.begin(); view.reserve(128); view.finish(false);
  const before = f.events.filter(value => value === 'current').length;
  await assert.rejects(view.close(), error => error === cause);
  assert.equal(f.events.filter(value => value === 'current').length, before + 1);
  assert.equal(view.status().pending, true); assert.equal(f.retired, 0);
  assert.equal(await view.close(), true);
  assert.equal(f.events.filter(value => value === 'current').length, before + 1,
    'consumed original does not repeat its already spent current/settlement');
  assert.equal(f.events.filter(value => value === 'parent').length, 1);
  assert.equal(f.events.filter(value => value === 'abort').length, 2);
  assert.deepEqual(f.events.filter(Array.isArray), [['cold-grow',0],['cold-grow',128]]);
  assert.equal(f.retired, 1);
});
