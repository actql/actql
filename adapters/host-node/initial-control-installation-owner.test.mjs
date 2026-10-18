import assert from 'node:assert/strict';
import test from 'node:test';
import {closeSync, fstatSync, mkdtempSync, openSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createContext, runInContext} from 'node:vm';
import ownerModule from './initial-control-installation-owner.cjs';

const {createInitialControlInstallationOwner: createOwner} = ownerModule;
const changed = {code: 'NodeInitialControlOriginalChanged'};
const originals = () => ({host: {}, installation: {}, generation: {}, supplier() {}, moduleLifetime: {}});

// Explicit operational controls exercise only the private state machine. They
// are not the actual preload's image/envelope issuer, a normal Host positive,
// physical-capacity acquisition or permission to perform any covered work.
function fixture() {
  let current = true, closes = 0, closeValue = {pending: false};
  const root = {assertCurrent(value) {
    assert.equal(this, root);
    assert.ok(Object.isFrozen(value));
    if (!current) throw new Error('OriginalOperationalCurrentRefused');
  }, close() { assert.equal(this, root); closes++; return closeValue; }};
  const owner = createOwner(root), original = originals(), scope = owner.begin(original);
  return {owner, original, scope, setCurrent(value) { current = value; },
    setClose(value) { closeValue = value; }, get closes() { return closes; }};
}

test('unavailable actual original refuses before reading caller descriptors', () => {
  const owner = createOwner(undefined);
  const packet = new Proxy({}, {ownKeys() { throw new Error('UnexpectedCallerRead'); }});
  assert.throws(() => owner.begin(packet), {code: 'NodeInitialControlAdmissionUnavailable'});
  assert.throws(() => owner.assertCurrent({}, packet), {code: 'NodeInitialControlAdmissionUnavailable'});
});

test('asynchronous begin snapshots five originals before initialization and checks current after it', async () => {
  let finish, prepares = 0, currents = 0, heldByPrepare;
  const wait = new Promise(resolve => { finish = resolve; });
  const original = originals(), same = {...original};
  const root = {prepare(held) {
    assert.equal(this, root); prepares++; heldByPrepare = held;
    assert.ok(Object.isFrozen(held));
    assert.deepEqual({...held}, same);
    return wait;
  }, assertCurrent(held) {
    assert.equal(this, root); currents++;
    assert.equal(held, heldByPrepare);
    assert.deepEqual({...held}, same);
  }, close(held) { assert.equal(held, heldByPrepare); return {pending: false}; }};
  const owner = createOwner(root), pending = owner.begin(original);
  assert.ok(pending instanceof Promise);
  assert.equal(prepares, 1);
  assert.equal(currents, 0);
  for (const name of Object.keys(original)) original[name] = {};
  assert.throws(() => owner.begin(same), changed);
  finish({aResolvedObjectIsNotAnAdmission: true});
  const scope = await pending;
  assert.equal(currents, 1);
  owner.assertCurrent(scope, same);
  assert.throws(() => owner.assertCurrent(scope, original), changed);
  assert.equal((await scope.close()).pending, false);
});

test('asynchronous initialization retains the captured original callback and receiver', async () => {
  let finish, calls = 0;
  const wait = new Promise(resolve => { finish = resolve; });
  const root = {prepare() { assert.equal(this, root); calls++; return wait; },
    assertCurrent() { assert.equal(this, root); }, close() { return {pending: false}; }};
  const owner = createOwner(root);
  root.prepare = () => { throw new Error('ReplacementMustNotInitialize'); };
  const pending = owner.begin(originals());
  assert.equal(calls, 1);
  finish();
  const scope = await pending;
  assert.equal((await scope.close()).pending, false);
});

test('one original namespace flight can serve different generations without sharing their scopes', async () => {
  let finish, imports = 0, flight;
  const root = {prepare() {
    flight ??= new Promise(resolve => { imports++; finish = resolve; });
    return flight;
  }, assertCurrent() {}, close() { return {pending: false}; }};
  const owner = createOwner(root), first = originals(), second = originals();
  const firstPending = owner.begin(first), secondPending = owner.begin(second);
  assert.equal(imports, 1);
  assert.notEqual(firstPending, secondPending);
  finish();
  const [firstScope, secondScope] = await Promise.all([firstPending, secondPending]);
  assert.notEqual(firstScope, secondScope);
  assert.throws(() => owner.assertCurrent(firstScope, second), changed);
  assert.equal((await firstScope.close()).pending, false);
  owner.assertCurrent(secondScope, second);
  assert.equal((await secondScope.close()).pending, false);
});

test('failed asynchronous initialization preserves its exact cause and original pending cleanup', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-initial-control-init-duty-'));
  const fd = openSync(join(directory, 'original'), 'wx');
  let closed = false, retries = 0, currents = 0;
  t.after(() => { if (!closed) closeSync(fd); rmSync(directory, {recursive: true}); });
  const cleanupHandle = Object.freeze({status() { return {pending: !closed}; },
    retry() { retries++; closeSync(fd); closed = true; }});
  const cause = Object.freeze(Object.assign(new Error('OriginalInitializationUnknown'), {cleanupHandle}));
  const root = {prepare() { return Promise.reject(cause); },
    assertCurrent() { currents++; }, close() { throw new Error('ScopeWasNotIssued'); }};
  const owner = createOwner(root), original = originals();
  await assert.rejects(owner.begin(original), error => error === cause && error.cleanupHandle === cleanupHandle);
  assert.equal(currents, 0);
  assert.equal(retries, 0);
  assert.ok(fstatSync(fd).isFile());
  assert.equal(cleanupHandle.status().pending, true);
  assert.throws(() => owner.begin(original), changed);
  // Only the original initialization duty can acknowledge this actual FD.
  cleanupHandle.retry();
  assert.equal(cleanupHandle.status().pending, false);
  assert.equal(retries, 1);
});

test('current refusal after initialization cannot issue or recycle the consumed generation', async () => {
  let finish, current = true, checks = 0;
  const wait = new Promise(resolve => { finish = resolve; });
  const cause = Object.freeze(new Error('OriginalCandidateRetiredDuringInitialization'));
  const root = {prepare() { return wait; }, assertCurrent() { checks++; if (!current) throw cause; },
    close() { throw new Error('NoScopeToClose'); }};
  const owner = createOwner(root), original = originals(), pending = owner.begin(original);
  current = false;
  finish();
  await assert.rejects(pending, error => error === cause);
  assert.equal(checks, 1);
  assert.throws(() => owner.begin(original), changed);
});

test('synchronous prepare failures and malformed captured preparation descriptors do not become scopes', () => {
  const cause = Object.freeze(new Error('OriginalSynchronousInitializationFailure'));
  const root = {prepare() { throw cause; }, assertCurrent() { throw new Error('NotInitialized'); },
    close() { return {pending: false}; }};
  const owner = createOwner(root), original = originals();
  assert.throws(() => owner.begin(original), error => error === cause);
  assert.throws(() => owner.begin(original), changed);
  let reads = 0;
  const getter = Object.defineProperty({...root}, 'prepare', {get() { reads++; return root.prepare; }});
  assert.throws(() => createOwner(getter), changed);
  assert.equal(reads, 0);
  assert.throws(() => createOwner({...root, prepare: true}), {code: 'NodeInitialControlAdmissionUnavailable'});
});

test('nominal current rejects fake copied and other-instance scopes without calling their methods', () => {
  const f = fixture(), foreign = fixture();
  let calls = 0;
  for (const value of [{assertCurrent() { calls++; }}, {...f.scope}, foreign.scope, undefined]) {
    assert.throws(() => f.owner.assertCurrent(value, f.original), changed);
  }
  f.owner.assertCurrent(f.scope, {...f.original});
  assert.equal(calls, 0);
});

test('current binds all five physical originals and rejects accessor or inherited packets', () => {
  const f = fixture();
  for (const name of Object.keys(f.original)) {
    assert.throws(() => f.owner.assertCurrent(f.scope, {...f.original, [name]: {}}), changed);
  }
  let calls = 0;
  const getter = Object.defineProperty({...f.original}, 'host', {get() { calls++; }});
  assert.throws(() => f.owner.assertCurrent(f.scope, getter), changed);
  assert.throws(() => f.owner.assertCurrent(f.scope, Object.create(f.original)), changed);
  assert.equal(calls, 0);
  assert.throws(() => f.owner.begin({...f.original}), changed);
});

test('same managed record returns one duty and a foreign release does not discharge it', async () => {
  const f = fixture(), record = {};
  const duty = f.scope.retainPreparation(record);
  assert.equal(f.scope.retainPreparation(record), duty);
  assert.throws(() => duty.releaseReferences({...record}), changed);
  assert.equal((await f.scope.close()).pending, true);
  assert.equal(f.closes, 0);
  duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(f.closes, 1);
  assert.throws(() => f.owner.assertCurrent(f.scope, f.original), changed);
});

test('a failure can attach its original cleanup once after retaining the same preparation', async () => {
  const f = fixture(), record = {};
  let pending = true, retries = 0;
  const handle = {status() { assert.equal(this, handle); return {pending}; },
    retry() { assert.equal(this, handle); retries++; pending = false; }};
  const duty = f.scope.retainPreparation(record);
  assert.equal(f.scope.retainPreparation(record, handle), duty);
  assert.equal(f.scope.retainPreparation(record, handle), duty);
  assert.throws(() => f.scope.retainPreparation(record, {...handle}), changed);
  duty.releaseReferences(record);
  assert.throws(() => f.scope.retainPreparation(record, handle), changed);
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(retries, 1);
});

test('retry settlement booleans and inherited or getter pending fields are not physical ACKs', async () => {
  for (const result of [undefined, {}, true, 0, {pending: true}, Object.create({pending: false}),
    Object.defineProperty({}, 'pending', {get() { throw new Error('NotAnOriginalDataObservation'); }})]) {
    const f = fixture(), record = {};
    const handle = {status() { return result; }, async retry() { return {pending: false}; }};
    f.scope.retainPreparation(record, handle).releaseReferences(record);
    const status = await f.scope.close();
    assert.equal(status.pending, true);
    assert.equal(status.pendingPreparations, 1);
    assert.equal(f.closes, 0);
  }
});

test('original status and retry receiver survive replacement and frozen thrown causes', async () => {
  const f = fixture(), record = {}, cause = Object.freeze(new Error('OriginalFrozenFailure'));
  let pending = true, retries = 0;
  const handle = {status() { assert.equal(this, handle); return {pending}; },
    retry() { assert.equal(this, handle); retries++; throw cause; }};
  f.scope.retainPreparation(record, handle).releaseReferences(record);
  handle.status = () => ({pending: false});
  handle.retry = () => { throw new Error('ReplacementMustNotRun'); };
  const first = await f.scope.close();
  assert.equal(first.pending, true);
  assert.equal(first.errors[0].cause, cause);
  assert.equal(retries, 1);
  pending = false;
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(retries, 1);
});

test('concurrent and reentrant closes share one flight through original asynchronous cleanup', async () => {
  const f = fixture(), record = {};
  let complete, pending = true, retries = 0, reentrant;
  const wait = new Promise(resolve => { complete = resolve; });
  const handle = {status() { return {pending}; }, async retry() {
    assert.equal(this, handle); retries++;
    reentrant = f.scope.close();
    await wait;
    pending = false;
  }};
  f.scope.retainPreparation(record, handle).releaseReferences(record);
  const flight = f.scope.close();
  assert.equal(f.scope.close(), flight);
  await Promise.resolve();
  assert.equal(reentrant, flight);
  assert.equal(f.scope.status().pending, true);
  complete();
  assert.equal((await flight).pending, false);
  assert.equal(retries, 1);
});

test('one child ACK never retires a pending sibling or reruns the completed child', async () => {
  const f = fixture(), first = {}, second = {};
  let firstPending = true, secondPending = true, firstRetries = 0, secondRetries = 0;
  f.scope.retainPreparation(first, {status() { return {pending: firstPending}; },
    retry() { firstRetries++; firstPending = false; }}).releaseReferences(first);
  f.scope.retainPreparation(second, {status() { return {pending: secondPending}; },
    retry() { secondRetries++; }}).releaseReferences(second);
  assert.equal((await f.scope.close()).pendingPreparations, 1);
  assert.equal(firstRetries, 1);
  assert.equal(secondRetries, 1);
  assert.equal(f.closes, 0);
  secondPending = false;
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(firstRetries, 1);
  assert.equal(secondRetries, 1);
});

test('operational close is child-first and its original pending false is separately required', async () => {
  const f = fixture(), record = {};
  const duty = f.scope.retainPreparation(record);
  f.setClose(undefined);
  assert.equal((await f.scope.close()).pending, true);
  assert.equal(f.closes, 0);
  duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, true);
  assert.equal(f.closes, 1);
  f.setClose({pending: false});
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(f.closes, 2);
  await f.scope.close();
  assert.equal(f.closes, 2);
});

test('managed alias release is not an escaped-alias or selected-domain retirement ACK', async () => {
  const f = fixture(), record = {};
  f.scope.retainPreparation(record).releaseReferences(record);
  f.setClose({pending: true});
  assert.equal((await f.scope.close()).pending, true);
  assert.equal(f.scope.status().pendingPreparations, 0);
  assert.throws(() => f.owner.assertCurrent(f.scope, f.original), changed);
  f.setClose({pending: false});
  assert.equal((await f.scope.close()).pending, false);
});

test('current refusal does not prevent cleanup of original retained duties', async () => {
  const f = fixture(), record = {};
  const duty = f.scope.retainPreparation(record);
  f.setCurrent(false);
  assert.throws(() => f.owner.assertCurrent(f.scope, f.original), /OriginalOperationalCurrentRefused/);
  duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, false);
});

test('cleanup descriptor failure retains the record and never manufactures physical success', async () => {
  const f = fixture(), record = {};
  const handle = {status() { return {pending: false}; }};
  assert.throws(() => f.scope.retainPreparation(record, handle), changed);
  f.scope.retainPreparation(record).releaseReferences(record);
  assert.equal((await f.scope.close()).pending, true);
  assert.equal(f.closes, 0);
});

test('failure history retains first and latest only, including null and undefined causes', async () => {
  const f = fixture(), record = {};
  let cause;
  const handle = {status() { throw cause; }, retry() { throw cause; }};
  f.scope.retainPreparation(record, handle).releaseReferences(record);
  const first = await f.scope.close();
  assert.equal(first.errors.length, 2);
  assert.equal(first.errors[0].cause, undefined);
  cause = null;
  const last = await f.scope.close();
  assert.equal(last.errors.length, 2);
  assert.equal(last.errors[0].cause, undefined);
  assert.equal(last.errors[1].cause, null);
  assert.ok(Object.isFrozen(last.errors));
});

test('original real file descriptors remain child-owned across pending and sibling cleanup', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-initial-control-file-duty-'));
  const firstFd = openSync(join(directory, 'first'), 'wx');
  const secondFd = openSync(join(directory, 'second'), 'wx');
  let firstClosed = false, secondClosed = false, allowSecond = false;
  t.after(() => {
    if (!firstClosed) closeSync(firstFd);
    if (!secondClosed) closeSync(secondFd);
    rmSync(directory, {recursive: true});
  });
  const f = fixture(), firstRecord = {}, secondRecord = {};
  const first = {status() { return {pending: !firstClosed}; }, retry() {
    assert.equal(this, first); closeSync(firstFd); firstClosed = true;
  }};
  const second = {status() { return {pending: !secondClosed}; }, retry() {
    assert.equal(this, second);
    if (allowSecond) { closeSync(secondFd); secondClosed = true; }
    return {pending: false};
  }};
  f.scope.retainPreparation(firstRecord, first).releaseReferences(firstRecord);
  f.scope.retainPreparation(secondRecord, second).releaseReferences(secondRecord);
  assert.equal((await f.scope.close()).pending, true);
  assert.throws(() => fstatSync(firstFd), {code: 'EBADF'});
  assert.ok(fstatSync(secondFd).isFile());
  assert.equal(f.closes, 0);
  allowSecond = true;
  assert.equal((await f.scope.close()).pending, false);
  assert.throws(() => fstatSync(secondFd), {code: 'EBADF'});
  assert.equal(f.closes, 1);
});

test('operational current callback cannot reentrantly close then authorize a scope', async () => {
  let closeDuringCurrent = false, scope, closing;
  const root = {assertCurrent() { if (closeDuringCurrent) closing = scope.close(); },
    close() { return {pending: false}; }};
  const owner = createOwner(root), original = originals();
  scope = owner.begin(original);
  closeDuringCurrent = true;
  assert.throws(() => owner.assertCurrent(scope, original), changed);
  assert.equal((await closing).pending, false);
});

test('failed late cleanup attachment keeps its original debt rather than restoring a managed-only duty', async () => {
  const f = fixture(), record = {};
  const duty = f.scope.retainPreparation(record);
  const original = {status() { return {pending: false}; }};
  assert.throws(() => f.scope.retainPreparation(record, original), changed);
  assert.throws(() => f.scope.retainPreparation(record, {status() { return {pending: false}; }, retry() {}}), changed);
  assert.equal(f.scope.retainPreparation(record), duty);
  duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, true);
  assert.equal(f.closes, 0);
});

test('a generation cannot be reissued by reentry from its original current callback', async () => {
  const original = originals();
  let owner, nested = 0;
  const root = {assertCurrent() {
    if (nested++ === 0) assert.throws(() => owner.begin(original), changed);
  }, close() { return {pending: false}; }};
  owner = createOwner(root);
  const scope = owner.begin(original);
  assert.equal(nested, 1);
  assert.equal((await scope.close()).pending, false);
  assert.throws(() => owner.begin(original), changed);
});

test('later Reflect Object and collection replacements cannot authenticate or discharge a scope', async () => {
  // Mutate a fresh test-only realm, never the test runner's native intrinsics.
  // This is an internal-state counter, not an actual preload envelope issuer.
  const context = createContext({module: {exports: {}}, firstPending: true, secondPending: true});
  runInContext(readFileSync(new URL('./initial-control-installation-owner.cjs', import.meta.url), 'utf8'), context);
  runInContext(`
    const owner = module.exports.createInitialControlInstallationOwner({
      assertCurrent() {}, close() { return {pending: false}; }
    });
    const originals = {host: {}, installation: {}, generation: {}, supplier() {}, moduleLifetime: {}};
    const scope = owner.begin(originals);
    const firstRecord = {}, secondRecord = {};
    scope.retainPreparation(firstRecord, {status() { return {pending: firstPending}; }, retry() { firstPending = false; }})
      .releaseReferences(firstRecord);
    scope.retainPreparation(secondRecord, {status() { return {pending: secondPending}; }, retry() {}})
      .releaseReferences(secondRecord);
    let replacementCalls = 0;
    const replacement = () => { replacementCalls++; throw new Error('ReplacementMustNotRun'); };
    Reflect.apply = replacement;
    Reflect.ownKeys = replacement;
    Object.getOwnPropertyDescriptor = replacement;
    Object.hasOwn = replacement;
    Object.freeze = replacement;
    Object.create = replacement;
    Object.assign = replacement;
    Array.prototype[Symbol.iterator] = replacement;
    WeakMap.prototype.get = replacement;
    WeakMap.prototype.set = replacement;
    WeakSet.prototype.has = replacement;
    WeakSet.prototype.add = replacement;
    Map.prototype.get = replacement;
    Map.prototype.set = replacement;
    Map.prototype.values = replacement;
    Map.prototype.forEach = replacement;
    Map.prototype.clear = replacement;
    let rejected = false;
    try { owner.assertCurrent({...scope}, originals); }
    catch (error) { rejected = error.code === 'NodeInitialControlOriginalChanged'; }
    if (!rejected) throw new Error('ForeignScopeAccepted');
    owner.assertCurrent(scope, originals);
    globalThis.firstClose = scope.close();
    globalThis.finish = async () => {
      const first = await firstClose;
      if (!first.pending || first.pendingPreparations !== 1) throw new Error('SiblingWasRetired');
      secondPending = false;
      const last = await scope.close();
      if (last.pending || replacementCalls !== 0) throw new Error('NativeOriginalWasNotRetained');
    };
  `, context);
  await context.finish();
});
