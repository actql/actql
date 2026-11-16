import {constructEffectfulPublication} from '../host-common/run-publication.mjs';
import assert from 'node:assert/strict';
import test from 'node:test';
import resources from './ordinary-node-resource-runtime.cjs';
import {prepareEffectCaptureResources} from './effect-capture-resources.mjs';

// Existing actual Node Resource supplier and original child callbacks. Core
// phase results are explicit ports, not a matching Common or quota proof.
const ok = value => ({$tag:1, _0:value});
function fixture({live = false, beginFailure, reserveFailure, retireFailure,
  retirementCurrent = false, complete, begin, decodedFailure, admitFailure,
  preparedAvailable = true, validation, validationFailure} = {}) {
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
    clientProgramBeginInstalledEffectCaptureRecovery(actual) {
      assert.equal(this, moon); assert.equal(actual, value);
      assert.equal(view.status().busy, true); events.push('live-begin');
      begin?.(); return ok(undefined);
    },
    clientProgramBeginInstalledEffectCaptureValidation(actual) {
      assert.equal(this, moon); assert.equal(actual, value);
      assert.equal(view.status().busy, true); events.push('live-validation');
      validation?.();
      if (validationFailure !== undefined) throw validationFailure;
      return ok(undefined);
    },
    clientProgramInstalledEffectCapturePreparedAvailable(actual) {
      assert.equal(actual, value); return preparedAvailable;
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
  const captured = Object.freeze({name:'captured_run', wire:'original captured'});
  const control = {
    admit(name, wire, selected) {
      assert.equal(this, control); assert.equal(name, 'captured_run');
      assert.equal(wire, captured.wire); assert.deepEqual(selected, limits);
      events.push('ordinary-admit');
      if (admitFailure !== undefined) throw admitFailure;
      return captured;
    },
    admitLiveEffectCapturedRun(actual, wire) {
      assert.equal(actual, value); assert.equal(wire, captured.wire);
      events.push('live-admit'); return captured;
    },
    reserveEffectCaptureEncrypted(...args) {return Reflect.apply(control.reserveEffectCaptureRecovery, control, args);},
    reserveEffectCaptureEnvelope(owner,input,identity,runDefinition,wire) {
      assert.equal(this,control);assert.equal(owner,parent);assert.equal(input,originalInput);
      assert.equal(identity,request);assert.equal(runDefinition,definition);events.push(['cold-envelope',wire]);
    },
    reserveEffectCaptureDecoded(owner, input, identity, runDefinition, wire, selected) {
      assert.equal(this, control); assert.equal(owner, parent); assert.equal(input, originalInput);
      assert.equal(identity, request); assert.equal(runDefinition, definition); assert.equal(selected.maxDepth,64);
      events.push(['cold-decoded', wire]); if (decodedFailure !== undefined) throw decodedFailure;
    },
    admitRecoveredEffectCapturedRun(owner, input, identity, runDefinition, wire) {
      assert.equal(this, control); assert.equal(owner, parent); assert.equal(input, originalInput);
      assert.equal(identity, request); assert.equal(runDefinition, definition); assert.equal(wire,captured.wire);
      events.push('cold-admit'); if (admitFailure !== undefined) throw admitFailure; return captured;
    },
    retireRecoveredEffectCapturedRun(actual) {
      assert.equal(this, control); assert.equal(actual,captured); events.push('cold-retire-data');
    },
    reserveEffectCaptureRecovery(owner, input, identity, runDefinition, bytes, selected) {
      assert.equal(this, control); assert.equal(owner, parent); assert.equal(input, originalInput);
      assert.equal(input.request, request); assert.equal(input.runDefinition, definition);
      assert.equal(identity, request); assert.equal(runDefinition, definition);
      assert.deepEqual(selected, limits); events.push(['cold-grow', bytes]);
      if (reserveFailure !== undefined) throw reserveFailure;
    },
  };
  return {events, request, definition, control, moon, captured,
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

test('adopted recovery selects the encrypted envelope and prepared admission ports on the SAME Read', async () => {
  const f = fixture({live:true}), encrypted = f.moon.clientProgramReserveInstalledEffectCaptureRecovery;
  let readOwner;
  f.moon.clientProgramReserveInstalledEffectCaptureEncrypted = function (owner, bytes) {
    assert.equal(this, f.moon); readOwner = owner; f.events.push('encrypted-port');
    return Reflect.apply(encrypted, this, [owner, bytes]);
  };
  f.moon.clientProgramReserveInstalledEffectCaptureRecovery = () => assert.fail('legacy reserve selected');
  f.moon.clientProgramReserveInstalledEffectCaptureEnvelope = function (owner, wire) {
    assert.equal(this, f.moon); assert.equal(wire, 'authenticated envelope');
    assert.strictEqual(owner, readOwner); f.events.push('envelope-port');
    return ok(undefined);
  };
  const view = f.open();
  view.begin(); view.reserve(10001); view.reserveEnvelope('authenticated envelope');
  view.reserveDecoded('{"captured_run":"original captured"}');
  assert.strictEqual(view.admitCapturedRun(f.captured.wire), f.captured);
  assert.equal(f.events.filter(value => value === 'encrypted-port').length, 1);
  assert.equal(f.events.filter(value => value === 'envelope-port').length, 1);
  assert.equal(f.events.filter(value => value === 'live-admit').length, 1);
  assert.equal(f.events.includes('ordinary-admit'), false);
  assert.equal(f.events.includes('initial'), false);
  view.finish(false);
  assert.equal(await view.close(), true);
  assert.equal(f.events.filter(value => value === 'cold-retire-data').length, 1);
  assert.equal(f.events.filter(value => value === 'live-retire').length, 1);
});

test('captured inverse re-enters the SAME Read before validation and cuts only after return', async () => {
  const f = fixture({live:true}), view = f.open();
  view.begin(); view.reserve(123); view.reserveDecoded('{"original":true}');
  assert.strictEqual(view.admitCapturedRun(f.captured.wire), f.captured);
  view.finish(false);
  const receiver = {}, argument = {}, result = {};
  const before = f.events.length;
  assert.strictEqual(view.constructCaptured(f.captured, receiver, function (value) {
    assert.strictEqual(this, receiver); assert.strictEqual(value, argument);
    assert.equal(view.status().busy, true);
    assert.equal(f.events.at(-1), 'live-begin');
    assert.throws(() => view.constructCaptured(f.captured, receiver, () => {}, argument),
      {code:'EffectCaptureResourceUnavailable'});
    return result;
  }, argument), result);
  assert.deepEqual(f.events.slice(before), ['live-begin','live-complete']);
  assert.equal(view.status().busy, false);
  const events = f.events.length;
  assert.throws(() => view.constructCaptured({...f.captured}, receiver, () => {}, argument),
    {code:'EffectCaptureResourceUnavailable'});
  assert.equal(f.events.length, events);
  assert.equal(await view.close(), true);
  assert.throws(() => view.constructCaptured(f.captured, receiver, () => {}, argument),
    {code:'EffectCaptureResourceUnavailable'});
});

test('ordinary cold capture admission binds its exact returned original to the SAME Read', async () => {
  const f = fixture({live:true, preparedAvailable:false}), view = f.open();
  view.begin(); view.reserve(123); view.reserveDecoded('{"original":true}');
  const captured = view.admitCapturedRun(f.captured.wire);
  assert.strictEqual(captured, f.captured);
  assert.equal(f.events.filter(value => value === 'ordinary-admit').length, 1);
  assert.equal(f.events.includes('live-admit'), false);
  view.finish(false);
  const result = {};
  assert.strictEqual(view.constructCaptured(captured, undefined, () => {
    assert.equal(view.status().busy, true); return result;
  }, {}), result);
  assert.equal(f.events.filter(value => value === 'ordinary-admit').length, 1);
  assert.throws(() => view.constructCaptured({...captured}, undefined, () => {}, {}),
    {code:'EffectCaptureResourceUnavailable'});
  assert.equal(await view.close(), true);
  assert.equal(f.events.includes('cold-retire-data'), false);
  assert.equal(f.events.filter(value => value === 'live-retire').length, 1);
  assert.equal(await view.close(), true);
});

function returnedLiveCapture(f) {
  const view = f.open(); view.begin(); view.reserve(123);
  view.reserveDecoded('{"original":true}');
  view.admitCapturedRun(f.captured.wire); view.finish(false);
  return view;
}

test('retained capture validation selects its own entry and preserves exact original, receiver and finish fences', async () => {
  const f = fixture({live: true}), view = returnedLiveCapture(f), receiver = {}, argument = {}, result = {};
  const before = f.events.length;
  assert.strictEqual(view.constructCapturedValidation(f.captured, receiver, function (value) {
    assert.strictEqual(this, receiver); assert.strictEqual(value, argument);
    assert.equal(view.status().busy, true); assert.equal(f.events.at(-1), 'live-validation');
    assert.throws(() => view.constructCapturedValidation(f.captured, receiver, () => {}, argument),
      {code: 'EffectCaptureResourceUnavailable'});
    assert.throws(() => view.constructCaptured(f.captured, receiver, () => {}, argument),
      {code: 'EffectCaptureResourceUnavailable'});
    return result;
  }, argument), result);
  assert.deepEqual(f.events.slice(before), ['live-validation', 'live-complete']);
  const calls = f.events.length;
  assert.throws(() => view.constructCapturedValidation({...f.captured}, receiver, () => {}, argument),
    {code: 'EffectCaptureResourceUnavailable'});
  assert.equal(f.events.length, calls);
  view.constructCaptured(f.captured, receiver, () => result, argument);
  assert.deepEqual(f.events.slice(-2), ['live-begin', 'live-complete'], 'generic/generated construction keeps the full entrance');
  assert.equal(await view.close(), true);
  assert.throws(() => view.constructCapturedValidation(f.captured, receiver, () => {}, argument),
    {code: 'EffectCaptureResourceUnavailable'});
});

test('retained validation funding and callback failures keep the original primary and unfinished cleanup', async () => {
  const refusal = new Error('same validation reservation refused');
  const f = fixture({live: true, validationFailure: refusal}), view = returnedLiveCapture(f);
  let entered = false; const completed = f.events.filter(value => value === 'live-complete').length;
  assert.throws(() => view.constructCapturedValidation(f.captured, undefined, () => {entered = true;}),
    error => error === refusal);
  assert.equal(entered, false); assert.equal(view.status().busy, false);
  assert.equal(f.events.filter(value => value === 'live-complete').length, completed);
  assert.equal(await view.close(), true);

  const g = fixture({live: true}), retained = returnedLiveCapture(g);
  let pending = true;
  const child = {status: () => ({pending}), async retry() {}};
  const primary = Object.assign(new Error('same validation child failed'), {cleanupPending: true, cleanupHandle: child});
  assert.throws(() => retained.constructCapturedValidation(g.captured, undefined, () => {throw primary;}),
    error => error === primary);
  assert.equal(g.events.filter(value => value === 'live-complete').length, 1);
  assert.equal(await retained.close(), false); assert.equal(g.events.includes('live-retire'), false);
  pending = false; assert.equal(await retained.close(), true);
});

test('retained validation current callback closing the same Read cannot enter validation or issue a finish', async () => {
  let closing;
  const f = fixture({live: true, validation() {closing = f.view.close();}}), view = returnedLiveCapture(f);
  let entered = false;
  assert.throws(() => view.constructCapturedValidation(f.captured, undefined, () => {entered = true;}),
    {code: 'EffectCaptureResourceUnavailable'});
  assert.equal(entered, false); assert.equal(f.events.filter(value => value === 'live-complete').length, 1);
  assert.equal(await closing, true); assert.equal(view.status().pending, false);
});

test('ordinary cold admission failure keeps its original primary and does not retire a nonexistent prepared token', async () => {
  const primary = new Error('original ordinary admission failure');
  const f = fixture({live:true, preparedAvailable:false, admitFailure:primary}), view = f.open();
  view.begin(); view.reserve(123); view.reserveDecoded('{"original":true}');
  assert.throws(() => view.admitCapturedRun(f.captured.wire), error => error === primary);
  view.finish(true, primary);
  assert.equal(await view.close(), true);
  assert.equal(f.events.filter(value => value === 'ordinary-admit').length, 1);
  assert.equal(f.events.includes('cold-retire-data'), false);
  assert.equal(f.events.filter(value => value === 'live-retire').length, 1);
});

test('captured inverse failure preserves its original child and does not cut a failed constructor', async () => {
  const f = fixture({live:true}), view = f.open();
  view.begin(); view.reserve(123); view.reserveDecoded('{"original":true}');
  view.admitCapturedRun(f.captured.wire); view.finish(false);
  let pending = true;
  const child = {status:() => ({pending}), async retry() {}};
  const primary = Object.assign(new Error('original inverse failure'),
    {cleanupPending:true, cleanupHandle:child});
  const completed = f.events.filter(value => value === 'live-complete').length;
  assert.throws(() => view.constructCaptured(f.captured, {}, () => {throw primary;}, {}),
    error => error === primary);
  assert.equal(view.status().busy, false);
  assert.equal(f.events.filter(value => value === 'live-complete').length, completed);
  assert.equal(await view.close(), false);
  assert.equal(f.events.includes('live-retire'), false);
  pending = false;
  assert.equal(await view.close(), true);
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


test('live re-admission funds SAME Definition before consuming and preserves original growth refusal', async () => {
  let refusal;
  const f = fixture({live:true, begin() {if (refusal !== undefined) throw refusal;}}), view = f.open();
  view.begin();view.reserve(32);view.finish(false);
  refusal = new Error('original fixed Definition growth refused');
  assert.throws(() => view.begin(), error => error === refusal);
  assert.equal(view.status().busy, false); assert.equal(view.status().pending, true);
  assert.equal(f.events.filter(value => value === 'live-begin').length, 2);
  assert.equal(f.events.filter(value => value === 'live-complete').length, 1);
  assert.deepEqual(f.events.filter(Array.isArray), [['live-grow',32]]);
  assert.equal(await view.close(), true);
});

test('live begin reentry and pending close cannot enter Definition admission or claim completion', async () => {
  const f = fixture({live:true, begin() {
    assert.throws(() => f.view.begin(), {code:'EffectCaptureResourceUnavailable'});
    void f.view.close();
  }}), view = f.open();
  assert.throws(() => view.begin(), {code:'EffectCaptureResourceUnavailable'});
  assert.equal(view.status().busy, false);
  assert.equal(f.events.includes('live-complete'), false);
  assert.deepEqual(f.events.filter(Array.isArray), []);
  assert.equal(await view.close(), true);
});


test('cold decoded funding precedes parsing and retains the same typed refusal through first close', async () => {
  const primary = new Error('same Read decoded capacity refused');
  const f = fixture({decodedFailure:primary}), view = f.open();
  view.begin(); view.reserve(128);
  let parsed = false;
  try {
    view.reserveDecoded('{'); parsed = true; JSON.parse('{');
    assert.fail('refused prefix reached parser');
  } catch (error) {assert.equal(error,primary); view.finish(true,error);}
  assert.equal(parsed,false); assert.equal(f.events.includes('cold-admit'),false);
  assert.equal(await view.close(),true); assert.equal(f.retired,1);
});

test('cold prepared DATA stays with the original Read through failed schema cleanup and is cut before parent settlement', async () => {
  const f=fixture(), view=f.open(); let pending=true, cleanupCalls=0;
  const primary=new Error('same returned schema cleanup');
  view.begin(); view.reserve(256); view.reserveDecoded('{"captured_run":"original captured"}');
  const captured=view.admitCapturedRun('original captured');
  assert.equal(view.admitCapturedRun('original captured'),captured);
  view.retainCleanup(()=>{cleanupCalls++; if(pending)throw primary;}); view.finish(false);
  await assert.rejects(view.close(),e=>e===primary);
  assert.equal(f.events.includes('cold-retire-data'),false); assert.equal(f.events.includes('abort'),false);
  pending=false; assert.equal(await view.close(),true); assert.equal(cleanupCalls,2);
  assert.ok(f.events.indexOf('cold-retire-data')<f.events.indexOf('abort'));
  assert.throws(()=>view.admitCapturedRun('original captured'),{code:'EffectCaptureResourceUnavailable'});
});

test('cold admission failure preserves primary and unknown physical cleanup never becomes ACK', async () => {
  const primary=Object.assign(new Error('cold semantic refusal'),{cleanupPending:true});
  const f=fixture({admitFailure:primary}),view=f.open();
  view.begin();view.reserve(256);view.reserveDecoded('{"captured_run":"original captured"}');
  assert.throws(()=>view.admitCapturedRun('original captured'),e=>e===primary);view.finish(true,primary);
  assert.equal(await view.close(),false);assert.equal(f.events.includes('abort'),false);
  assert.equal(f.events.includes('cold-retire-data'),false);assert.equal(f.retired,0);
});


test('final publication validator uses the same captured Read, exact receiver and original argument inventory', async () => {
  const f = fixture({live:true}), view = f.open();
  view.begin(); view.reserve(123); view.reserveDecoded('{"original":true}');
  assert.strictEqual(view.admitCapturedRun(f.captured.wire), f.captured);
  view.finish(false);
  const receiver = {}, args = [{}, {}, {}, {}, {}, {}, {}], result = {};
  const before = f.events.length;
  assert.strictEqual(constructEffectfulPublication(view, f.captured, receiver, function (...actual) {
    assert.strictEqual(this, receiver); assert.deepEqual(actual, args);
    actual.forEach((value, index) => assert.strictEqual(value, args[index]));
    assert.equal(view.status().busy, true);
    return result;
  }, args), result);
  assert.deepEqual(f.events.slice(before), ['live-validation', 'live-complete']);
  assert.throws(() => constructEffectfulPublication(view, {...f.captured}, receiver,
    () => assert.fail('Foreign capture cannot validate'), args), {code:'EffectCaptureResourceUnavailable'});
  assert.equal(await view.close(), true);
  assert.throws(() => constructEffectfulPublication(view, f.captured, receiver,
    () => assert.fail('Retired Read cannot validate'), args), {code:'EffectCaptureResourceUnavailable'});
});
test('final publication funding refusal keeps the original primary before validator work', async () => {
  const primary = Object.freeze(new Error('current lost')); let armed = false;
  const f = fixture({live:true, validation() {if (armed) throw primary;}}), view = f.open();
  view.begin(); view.reserve(123); view.reserveDecoded('{"original":true}');
  assert.strictEqual(view.admitCapturedRun(f.captured.wire), f.captured);
  view.finish(false); armed = true;
  assert.throws(() => constructEffectfulPublication(view, f.captured, {},
    () => assert.fail('No validation before funding'), []), error => error === primary);
  assert.equal(view.status().busy, false);
  assert.equal(await view.close(), true);
});

test('publication construction preserves full Read funding for nonlive and older Core resources', async () => {
  for (const live of [false, true]) {
    const f = fixture({live});
    if (live) delete f.moon.clientProgramBeginInstalledEffectCaptureValidation;
    const view = returnedLiveCapture(f), result = {}, before = f.events.length;
    assert.strictEqual(constructEffectfulPublication(view, f.captured, undefined, () => result, []), result);
    assert.equal(f.events.slice(before).includes('live-validation'), false);
    if (live) assert.deepEqual(f.events.slice(before), ['live-begin', 'live-complete']);
    assert.throws(() => view.constructCapturedValidation(f.captured, undefined, () => {}),
      {code: 'EffectCaptureResourceUnavailable'});
    assert.equal(await view.close(), true);
  }
  const captured = {}, result = {};
  const original = {constructCaptured(actual, receiver, method, args) {
    assert.strictEqual(this, original); assert.strictEqual(actual, captured);
    return Reflect.apply(method, receiver, [args]);
  }};
  assert.strictEqual(constructEffectfulPublication(original, captured, undefined, () => result, []), result);
});
