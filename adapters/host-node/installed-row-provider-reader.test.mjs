import assert from 'node:assert/strict';
import test from 'node:test';
import {startInstalledRowRun} from './installed-row-run.mjs';
import {createInstalledCredentialSourceReader} from './installed-credential-source-reader.mjs';

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

test('provider construction callback keeps the same original borrow before Query and whole-input reads', async () => {
  for (const wholeInput of [false, true]) {
    let reserve, grows = 0;
    const next = Object.freeze({});
    const f = fixture({read() {reserve(next); return 'same rows';}});
    const grow = function(actual, capacity) {
      assert.equal(this, f.moon); assert.equal(actual, f.borrow); assert.equal(capacity, next);
      grows++; return ok();
    };
    f.moon.clientProgramRowSourceGrowResponseConstructionCapacity = grow;
    f.moon.clientProgramRowSourceGrowResponseCapacity = () => assert.fail('charged response fallback');
    const read = {};
    if (wholeInput) {
      f.moon.clientProgramInstalledSourceReadCheckLedger = (original, ledger) => {
        assert.equal(original, read); assert.equal(ledger, f.ledger); return ok();
      };
      f.moon.clientProgramInstalledWholeSourceReadStartRows = (original, selected) => {
        assert.equal(original, read); assert.equal(selected, f.acquisition); return ok(f.run);
      };
      f.moon.clientProgramInstalledSourceReadRetire = original => {
        assert.equal(original, read); return ok();
      };
      f.moon.clientProgramWholeSourceBorrowResponses = f.moon.clientProgramRowSourceBorrowResponses;
    }
    const session = f.start(wholeInput ? {wholeInput, originalRead: read} : undefined);
    const supplier = {prepare(options, retain, responseCapacity) {
      assert.equal(this, supplier); assert.equal(options, f.options);
      assert.equal(typeof retain, 'function');
      assert.equal(typeof responseCapacity, 'function');
      reserve = capacity => responseCapacity(capacity, 'announced-body');
      assert.throws(() => reserve(next), {code: 'InstalledSourceClosed'});
      assert.equal(grows, 0);
      // The original method and receiver were captured before this mutation.
      f.moon.clientProgramRowSourceGrowResponseConstructionCapacity = () => {
        assert.fail('replacement constructor entry');
      };
      return f.reader;
    }};
    assert.equal(await session.readProvider({receiver: supplier, prepare: supplier.prepare,
      options: f.options}), 'same rows');
    assert.equal(grows, 1);
    assert.throws(() => reserve(next), {code: 'InstalledSourceClosed'});
    const state = {};
    session.closeAfterFailure(state);
    assert.equal(await state.recovery.cleanup(), false);
    assert.equal(f.counts().settles, 0);
    f.retire();
    assert.equal(await state.recovery.cleanup(), true);
    assert.equal(f.counts().settles, 1);
    assert.throws(() => reserve(next), {code: 'InstalledSourceClosed'});
    assert.equal(grows, 1);
  }
});

test('provider construction refusal and callback close never enter the native constructor or release pending originals', async () => {
  for (const kind of ['refused', 'closed']) {
    const primary = Object.freeze(new Error('same original capacity refusal'));
    let reserve, constructors = 0, calls = 0;
    const f = fixture({read() {reserve(f.capacity); constructors++;}});
    const session = f.start(), state = {};
    f.moon.clientProgramRowSourceGrowResponseCapacity = () => assert.fail('charged response fallback');
    f.moon.clientProgramRowSourceGrowResponseConstructionCapacity = function(borrow, capacity) {
      assert.equal(this, f.moon); assert.equal(borrow, f.borrow); assert.equal(capacity, f.capacity);
      calls++;
      if (kind === 'refused') return error(primary);
      session.closeAfterFailure(state);
      return ok();
    };
    const supplier = {prepare(options, _retain, response) {
      assert.equal(this, supplier); assert.equal(options, f.options); reserve = capacity => response(capacity, 'announced-body');
      return f.reader;
    }};
    await assert.rejects(session.readProvider({receiver: supplier, prepare: supplier.prepare,
      options: f.options}), actual => kind === 'refused' ? actual.cause === primary
      : actual.code === 'InstalledSourceClosed');
    assert.equal(constructors, 0);
    assert.equal(calls, 1);
    if (kind === 'refused') session.closeAfterFailure(state);
    assert.equal(await state.recovery.cleanup(), false);
    assert.equal(f.counts().settles, 0);
    f.retire();
    assert.equal(await state.recovery.cleanup(), true);
    assert.equal(f.counts().settles, 1);
    assert.throws(() => reserve(f.capacity), {code: 'InstalledSourceClosed'});
    assert.equal(calls, 1);
  }
});

test('missing provider construction port remains absent instead of falling back to the charged response entry', async () => {
  const f = fixture(), session = f.start();
  f.moon.clientProgramRowSourceGrowResponseCapacity = () => assert.fail('response fallback');
  const supplier = {prepare(options, _retain, response) {
    assert.equal(this, supplier); assert.equal(options, f.options);
    assert.equal(typeof response, 'function');
    return {...f.reader, read() {response(f.capacity, 'announced-body'); assert.fail('native constructor');}};
  }};
  await assert.rejects(session.readProvider({receiver: supplier, prepare: supplier.prepare,
    options: f.options}), {code: 'InstalledSourceResponseConstructionUnavailable'});
  assert.equal(f.calls.filter(name => name === 'read').length, 0);
  assert.equal(f.counts().settles, 0);
});

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

// Actual shared factory preparation, with explicit Core/Account/Site ports.
// No credential binding or physical read may occur in these failed constructors.
function originalPreparationFixture() {
  let reads = 0, bindings = 0;
  const site = Object.freeze({});
  const factory = createInstalledCredentialSourceReader({capacity: {},
    originalSite: Object.freeze({site, referenceCurrent() {return true;},
      authorizationPurpose() {assert.fail('No failed constructor can authorize a read');},
      bindRunAcquisition() {bindings++; assert.fail('No failed constructor can bind a child');},
      callResource() {reads++; assert.fail('No failed constructor can send');}}),
    assertCurrent() {}, operation: 'read', maxResponses: 1,
    maxResponseBytes: 128, maxSecretBytes: 128,
    preparePageReader() {return Object.freeze({
      fetchPage() {assert.fail('No page request before reader entry');},
      decodePage() {assert.fail('No response before reader entry');},
    });}});
  const options = Object.freeze({resource: 'rows', columns: Object.freeze(['id']),
    requestWire: 'same-original-request', verifyRead() {}, authorizationFor() {},
    chargePage() {assert.fail('No failed constructor can charge a body');},
    consumePage() {assert.fail('No failed constructor can consume a page');}});
  return {factory, options, counts: () => ({reads, bindings})};
}

test('same RowRun recovers the actual shared factory preparation after its original constructor refuses', async () => {
  const f = fixture(), session = f.start(), original = originalPreparationFixture();
  const options = Object.freeze({...original.options, authorizationFor: undefined});
  await assert.rejects(session.readProvider({receiver: original.factory,
    prepare: original.factory.prepare, options}), {code: 'InstalledSourceReaderMethodUnavailable'});
  // The original factory's preparation finally has run, but its early record
  // must still reach this SAME Core borrow before the failed attempt can close.
  session.close();
  assert.equal(f.counts().settles, 1);
  assert.equal(original.factory.retire(), true);
  assert.deepEqual(original.counts(), {reads: 0, bindings: 0});
  assert.equal(f.calls.filter(name => name === 'borrow').length, 1);
});

test('same RowRun keeps actual preparation custody when the returned reader method getter throws', async () => {
  const f = fixture(), session = f.start(), original = originalPreparationFixture();
  const cause = Object.freeze(new Error('original-returned-method-failure'));
  await assert.rejects(session.readProvider({receiver: original.factory,
    options: original.options,
    prepare(options, retain, grow) {
      assert.equal(this, original.factory); assert.equal(options, original.options);
      Reflect.apply(original.factory.prepare, original.factory, [options, retain, grow]);
      return Object.freeze({get read() {throw cause;}});
    }}), observed => observed === cause);
  session.close();
  assert.equal(f.counts().settles, 1);
  assert.equal(original.factory.retire(), true);
  assert.deepEqual(original.counts(), {reads: 0, bindings: 0});
  assert.equal(f.calls.filter(name => name === 'borrow').length, 1);
});

test('provider preparation keeps the same pending original and rejects truthy retirement', async () => {
  const f = fixture(), session = f.start(), cause = new Error('partial constructor failed');
  let retired = false, calls = 0;
  const preparation = Object.freeze({retire() {
    assert.equal(this, preparation); calls++; return retired ? true : 'pending';
  }});
  await assert.rejects(session.readProvider({options: f.options, prepare(_options, retain) {
    retain(preparation); throw cause;
  }}), observed => observed === cause);
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.counts().settles, 0);
  assert.equal(state.recovery.cleanupPending(), true);
  assert(calls > 0);
  retired = true;
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(f.counts().settles, 1);
  assert.equal(f.calls.filter(name => name === 'borrow').length, 1);
  assert.equal(f.calls.includes('read'), false);
});

test('provider preparation keeps one unexpected Promise flight and never treats its settlement as ACK', async () => {
  const f = fixture(), session = f.start(), pending = deferred();
  let calls = 0, acknowledged = false;
  const preparation = Object.freeze({retire() {
    assert.equal(this, preparation); calls++;
    return calls === 1 ? pending.promise : acknowledged;
  }});
  const cause = new Error('partial constructor failed');
  await assert.rejects(session.readProvider({options: f.options, prepare(_options, retain) {
    retain(preparation); throw cause;
  }}), observed => observed === cause);
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(calls, 1);
  assert.equal(f.counts().settles, 0);
  pending.resolve(true); await Promise.resolve();
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(f.counts().settles, 0);
  acknowledged = true;
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(f.counts().settles, 1);
});

test('provider preparation refuses a replacement and fences same-record cleanup reentry', async () => {
  const f = fixture(), session = f.start();
  let mayRetire = false, reentered = false, foreignCalls = 0;
  const original = Object.freeze({retire() {
    assert.equal(this, original);
    if (!reentered) {
      reentered = true;
      assert.throws(() => session.close(), {code: 'MoonBitHostFailure'});
    }
    return mayRetire;
  }});
  const foreign = Object.freeze({retire() {foreignCalls++; return true;}});
  await assert.rejects(session.readProvider({options: f.options, prepare(_options, retain) {
    retain(original); retain(foreign);
  }}), {code: 'InstalledSourcePreparationAlreadyRetained'});
  const state = {};
  session.closeAfterFailure(state);
  assert.equal(await state.recovery.cleanup(), false);
  assert.equal(reentered, true);
  assert.equal(f.counts().settles, 0);
  mayRetire = true;
  assert.equal(await state.recovery.cleanup(), true);
  assert.equal(f.counts().settles, 1);
  assert.equal(foreignCalls, 0);
});

test('provider preparation preserves original options and the existing third capacity-growth argument', async () => {
  const f = fixture(), session = f.start(), capacity = Object.freeze({});
  let grow, growths = 0;
  f.moon.clientProgramRowSourceGrowResponseCapacity = (borrow, selected) => {
    assert.equal(borrow, f.borrow); assert.equal(selected, capacity); growths++; return ok();
  };
  const read = f.reader.read;
  f.reader.read = function () {grow(capacity); return Reflect.apply(read, this, []);};
  await session.readProvider({receiver: f.supplier, options: f.options,
    prepare(options, retain, reserve) {
      assert.equal(this, f.supplier); assert.equal(options, f.options);
      assert.equal(typeof retain, 'function'); assert.equal(typeof reserve, 'function');
      assert.throws(() => reserve(capacity), {code: 'InstalledSourceClosed'});
      grow = reserve; return f.reader;
    }});
  assert.equal(growths, 1);
  f.retire(); session.close();
  assert.equal(f.counts().settles, 1);
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

test('WholeInput forwards announced and charged growth through its same original borrow without Query substitution', async () => {
  const f = fixture(), originalRead = {}, next = {};
  f.moon.clientProgramInstalledSourceReadCheckLedger = (read, ledger) => {
    assert.equal(read, originalRead); assert.equal(ledger, f.ledger); return ok();
  };
  f.moon.clientProgramInstalledWholeSourceReadStartRows = (read, selected) => {
    assert.equal(read, originalRead); assert.equal(selected, f.acquisition); return ok(f.run);
  };
  f.moon.clientProgramInstalledSourceReadRetire = read => {
    assert.equal(read, originalRead); return ok();
  };
  f.moon.clientProgramWholeSourceBorrowResponses = (run, selected) => {
    assert.equal(run, f.run); assert.equal(selected, f.acquisition); return ok(f.borrow);
  };
  const phases = [];
  f.moon.clientProgramRowSourceGrowResponseConstructionCapacity = (borrow, capacity) => {
    assert.equal(borrow, f.borrow); assert.equal(capacity, next); phases.push('announced'); return ok();
  };
  f.moon.clientProgramRowSourceGrowResponseCapacity = (borrow, capacity) => {
    assert.equal(borrow, f.borrow); assert.equal(capacity, next); phases.push('charged'); return ok();
  };
  let reserve;
  const supplier = {prepare(options, retain, grow, originalBorrow) {
    assert.equal(this, supplier); assert.equal(options, f.options);
    assert.equal(originalBorrow, f.borrow); reserve = grow;
    f.reader.read = function () {assert.equal(this, f.reader); reserve(next, 'announced-body'); reserve(next); return 'rows';};
    return f.reader;
  }};
  const session = f.start({wholeInput:true, originalRead});
  assert.equal(await session.readProvider({prepare:supplier.prepare,receiver:supplier,options:f.options}), 'rows');
  assert.deepEqual(phases, ['announced', 'charged']);
  f.retire(); assert.equal(await session.cleanup(), true);
});
