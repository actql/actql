import assert from 'node:assert/strict';
import test from 'node:test';
import {startInstalledRowRun} from './installed-row-run.mjs';

const ok = value => ({$tag: 1, _0: value});
const error = value => ({$tag: 0, _0: value});
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
};

// These are caller/order doubles, not evidence of physical retirement or a
// normal capacity profile. Actual Core reservation tests remain independent.
function fixture({read = () => 'rows', stop = () => {}, observe,
  verifyRead = async () => {}} = {}) {
  const acquisition = {}, run = {}, ledger = {}, capacity = {};
  const began = deferred();
  const borrow = {}, calls = [], options = Object.freeze({original: acquisition, verifyRead});
  let cleanup, retired = false, closes = 0, settles = 0;
  const reader = {
    read() {assert.equal(this, reader); calls.push('read'); began.resolve(); return read();},
    requestStop() {assert.equal(this, reader); calls.push('stop'); return stop();},
    observe() {
      assert.equal(this, reader); calls.push('observe');
      return observe ? observe() : {cleanupConfirmed: retired};
    },
  };
  const supplier = {prepare(actual) {
    assert.equal(this, supplier); assert.equal(actual, options);
    assert.equal(typeof cleanup, 'function');
    calls.push('prepare'); return reader;
  }};
  const moon = {
    clientProgramRowSourceStartProviderAccounted(...args) {
      assert.equal(args[0], acquisition); assert.equal(args[1], capacity);
      assert.equal(args[2], 'original-nonce'); assert.equal(args[3]({}), false);
      assert.deepEqual(args.slice(4), [ledger, 17n, 23n]);
      calls.push('start'); return ok(run);
    },
    clientProgramRowSourceBorrowResponses(actualRun, actualAcquisition) {
      assert.equal(actualRun, run); assert.equal(actualAcquisition, acquisition);
      calls.push('borrow'); return ok(borrow);
    },
    clientProgramRowSourceBindResponseCleanup(actualBorrow, observer) {
      assert.equal(actualBorrow, borrow); cleanup = observer;
      assert.equal(cleanup(), false); calls.push('bind'); return ok(undefined);
    },
    clientProgramRowSourceRetireResponseWorkspace(actualBorrow) {
      assert.equal(actualBorrow, borrow);
      return cleanup() ? ok(undefined) : error('original reader pending');
    },
    clientProgramRowSourceCloseAccounted(actualRun) {
      assert.equal(actualRun, run); closes++;
      calls.push('close');
      if (cleanup !== undefined && !cleanup()) return error('original reader pending');
      settles++; return ok(undefined);
    },
    clientProgramRowSourceCaptureCleanup: () => ok(true),
    clientProgramRowSourceCaptureCleanupAdvance: () => ok(true),
  };
  const start = overrides => startInstalledRowRun({moon, acquisition,
    nonce: 'original-nonce', ledger, capacity: {provider: capacity,
      transferBytes: 17n, executionBytes: 23n}, ...overrides});
  return {moon, start, calls, reader, supplier, options, capacity, acquisition, run, ledger, borrow,
    readBegan: began.promise,
    read: session => session.readProvider({prepare: supplier.prepare,
      receiver: supplier, options}),
    retire: () => {retired = true;},
    counts: () => ({closes, settles}),
    cleanup: () => cleanup()};
}

test('provider reader is bound to the original acquisition before factory and read', async () => {
  const f = fixture(), session = f.start();
  assert.equal(await f.read(session), 'rows');
  assert.deepEqual(f.calls, ['start', 'borrow', 'bind', 'prepare', 'read']);
  await assert.rejects(f.read(session), {code: 'InstalledSourceReaderAlreadyPrepared'});
  assert.equal(f.calls.filter(name => name === 'start').length, 1);
});

test('provider declaration requires the same Ledger and cannot select keyed or listing starts', () => {
  const f = fixture();
  assert.throws(() => f.start({ledger: undefined}), {code: 'InstalledProviderSourceLedgerRequired'});
  assert.throws(() => f.start({keyed: true}), {code: 'InstalledProviderSourceProgramMismatch'});
  assert.throws(() => f.start({capacity: {provider: f.capacity, listingReport: {}}}),
    {code: 'InstalledProviderSourceProgramMismatch'});
  delete f.moon.clientProgramRowSourceBindResponseCleanup;
  assert.throws(() => f.start(), {code: 'InstalledProviderSourceUnavailable'});
  assert.deepEqual(f.calls, []);
});

test('provider Core reservation refusal never falls back to an unaccounted start', () => {
  const f = fixture();
  f.moon.clientProgramRowSourceStartProviderAccounted = () => error('insufficient original capacity');
  assert.throws(() => f.start(), {code: 'MoonBitHostFailure'});
  assert.deepEqual(f.calls, []);
});

test('reader methods and receiver are captured once and cannot be replaced after read starts', async () => {
  const pending = deferred(), f = fixture({read: () => pending.promise});
  const original = {...f.reader}, gets = {read: 0, requestStop: 0, observe: 0};
  for (const name of Object.keys(gets)) {
    Object.defineProperty(f.reader, name, {configurable: true,
      get() {gets[name]++; return original[name];}});
  }
  const session = f.start(), reading = f.read(session);
  for (const name of Object.keys(gets)) {
    Object.defineProperty(f.reader, name, {value() {assert.fail('replacement method used');}});
  }
  pending.resolve('same original response');
  assert.equal(await reading, 'same original response');
  assert.throws(() => session.close(), {code: 'MoonBitHostFailure'});
  assert.deepEqual(gets, {read: 1, requestStop: 1, observe: 1});
  assert.equal(f.calls.filter(name => name === 'stop').length, 1);
  assert.equal(f.counts().settles, 0);
});

test('read settlement and cancel acceptance do not retire raw or escaped observation custody', async () => {
  const f = fixture(), session = f.start();
  await f.read(session);
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(state.closeFailed, true);
  assert.equal(state.recovery.cleanupPending(), true);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.counts().settles, 0);
  assert.equal(f.calls.filter(name => name === 'stop').length, 1);
  f.retire();
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(state.recovery.cleanupPending(), false);
  assert.equal(f.counts().settles, 1);
  session.close();
  assert.equal(f.counts().settles, 1);
});

test('a pending original read keeps its Promise custody even if the reader reports stopped', async () => {
  const pending = deferred(), f = fixture({read: () => pending.promise});
  const session = f.start(), reading = f.read(session);
  await f.readBegan;
  f.retire();
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.counts().settles, 0);
  pending.resolve('incomplete original prefix');
  await reading;
  assert.equal(await state.recovery.cleanup(), true);
});

test('current refusal after factory keeps the same reader for cleanup and sends nothing', async () => {
  const denied = new Error('original authority changed');
  const f = fixture({verifyRead: async () => {throw denied;}}), session = f.start();
  await assert.rejects(f.read(session), error => error === denied);
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.calls.filter(name => name === 'prepare').length, 1);
  assert.equal(f.calls.filter(name => name === 'read').length, 0);
  assert.equal(f.calls.filter(name => name === 'stop').length, 1);
  assert.equal(f.counts().settles, 0);
});

test('close during current read wait prevents the original reader from starting after await', async () => {
  const checking = deferred(), f = fixture({verifyRead: () => checking.promise});
  const session = f.start(), reading = f.read(session), state = {};
  session.closeAfterFailure(state);
  checking.resolve();
  await assert.rejects(reading, {code: 'InstalledSourceClosed'});
  assert.equal(f.calls.filter(name => name === 'read').length, 0);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.counts().settles, 0);
});

test('same stop Promise remains handled and pending without another cancel or read', async () => {
  const stopping = deferred(), f = fixture({stop: () => stopping.promise});
  const session = f.start();
  await f.read(session); f.retire();
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.counts().settles, 0);
  stopping.resolve(); await Promise.resolve();
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(f.calls.filter(name => name === 'stop').length, 1);
  assert.equal(f.calls.filter(name => name === 'read').length, 1);
});

test('reader failure keeps its original error/raw while same observer remains pending', async () => {
  const original = Object.freeze(Object.assign(new Error('original read failed'),
    {observations: Object.freeze([Buffer.from('original raw')])}));
  const f = fixture({read: () => {throw original;}}), session = f.start();
  await assert.rejects(f.read(session), error => error === original);
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(original.observations[0].toString(), 'original raw');
  assert.equal(f.counts().settles, 0);
});

test('throwing factory or method getter retains the installed original borrow without retry', async () => {
  for (const kind of ['factory', 'getter']) {
    const original = Object.freeze(new Error(kind)), f = fixture(), session = f.start();
    if (kind === 'factory') f.supplier.prepare = () => {throw original;};
    else Object.defineProperty(f.reader, 'read', {get() {throw original;}});
    await assert.rejects(f.read(session), error => error === original);
    const state = {};
    session.closeAfterFailure(state);
    assert.equal(await state.recovery.cleanup(), false);
    await assert.rejects(f.read(session), {code: 'InstalledSourceReaderAlreadyPrepared'});
    assert.equal(f.counts().settles, 0);
    assert.equal(f.calls.filter(name => name === 'borrow').length, 1);
  }
});

test('truthy, missing or throwing reader cleanup observations never acknowledge retirement', async () => {
  for (const observe of [() => ({cleanupConfirmed: 1}), () => ({}),
    () => {throw new Error('original observation unavailable');}]) {
    const f = fixture({observe}), session = f.start();
    await f.read(session);
    const state = {};
    session.closeAfterFailure(state);
    assert.equal(state.recovery.cleanupPending(), true);
    try {assert.equal(await state.recovery.cleanup(), false);}
    catch (error) {assert.match(error.message, /original observation unavailable/u);}
    assert.equal(f.counts().settles, 0);
  }
});


function installCompletedProviderCapture(f) {
  const capture = {}, source = {}, checkedOwner = {}, requirement = {};
  Object.assign(f.moon, {
    clientProgramRowSourceFinish: actual => {assert.equal(actual,f.run);return ok(undefined);},
    clientProgramRowSourceAttempt: actual => {assert.equal(actual,f.run);return {};},
    clientProgramRowSourceCaptureBegin: () => ok(undefined),
    clientProgramRowSourceCaptureAdvance: () => ok({_0:true,_1:1n}),
    clientProgramRowSourceCapture: () => ok(capture),
    clientProgramRowSourceCaptureSource: actual => {assert.equal(actual,capture);return ok(source);},
    clientProgramEffectCapturedSourceMatches: () => true,
    clientProgramIdentifyCapturedEffectSourceRelation: () => ok({}),
    clientProgramEffectIssueCapturedSourceLogical: () => ok({}),
    clientProgramRowSourceRetireResponseWorkspace(actualBorrow) {
      assert.equal(actualBorrow,f.borrow);
      if (!f.cleanup()) return error('original reader pending');
      f.calls.push('retire-workspace'); return ok(undefined);
    },
  });
  return {capture,source,options:{owner:{checkedOwner,effectful:true,
    requirement,occurrence:{task:0}},prepared:{checkedSource:{}},
    registry:'registry',values:'values',currentRead:async()=>{}}};
}

test('completed provider capture retires SAME reader workspace before returning live Source', async () => {
  let f;
  f=fixture({stop(){f.retire();}});
  const selected=installCompletedProviderCapture(f),session=f.start();
  await f.read(session);
  const result=await session.complete(selected.options);
  assert.deepEqual(f.calls.filter(name=>['stop','retire-workspace','close'].includes(name)),
    ['stop','retire-workspace']);
  assert.equal(result.capture.source(),selected.source);
  assert.equal(f.counts().closes,0);
  assert.equal(f.calls.filter(name=>name==='observe').length,1);
  result.close();
  assert.equal(f.counts().settles,1);
});

test('provider workspace completion refuses pending original stop and keeps SAME cleanup', async () => {
  const f=fixture(),selected=installCompletedProviderCapture(f),session=f.start();
  await f.read(session);
  await assert.rejects(session.complete(selected.options),{code:'MoonBitHostFailure'});
  assert.equal(f.calls.includes('retire-workspace'),false);
  assert.equal(f.counts().settles,0);
  assert.equal(await session.cleanup(),false);
  f.retire();
  assert.equal(await session.cleanup(),true);
  assert.equal(f.calls.filter(name=>name==='read').length,1);
  assert.equal(f.counts().settles,1);
});

test('provider workspace Core refusal preserves original observer for final cleanup', async () => {
  let f;f=fixture({stop(){f.retire();}});
  const selected=installCompletedProviderCapture(f),session=f.start();
  f.moon.clientProgramRowSourceRetireResponseWorkspace=actual=>{
    assert.equal(actual,f.borrow);return error('same original current refused');
  };
  await f.read(session);
  await assert.rejects(session.complete(selected.options),{code:'MoonBitHostFailure'});
  assert.equal(f.counts().settles,0);
  assert.equal(await session.cleanup(),true);
  assert.equal(f.counts().settles,1);
});

test('provider workspace completion cannot interpret an unresolved stop Promise as retirement', async () => {
  const pending=deferred();let f;f=fixture({stop(){f.retire();return pending.promise;}});
  const selected=installCompletedProviderCapture(f),session=f.start();
  await f.read(session);
  await assert.rejects(session.complete(selected.options),{code:'MoonBitHostFailure'});
  assert.equal(f.calls.includes('retire-workspace'),false);
  pending.resolve();await Promise.resolve();
  assert.equal(await session.cleanup(),true);
  assert.equal(f.calls.filter(name=>name==='stop').length,1);
  assert.equal(f.calls.filter(name=>name==='read').length,1);
});
