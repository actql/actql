import assert from 'node:assert/strict';
import test from 'node:test';
import {closeSync, fstatSync, mkdtempSync, openSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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
