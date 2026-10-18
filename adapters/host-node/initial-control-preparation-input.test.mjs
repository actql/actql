import assert from 'node:assert/strict';
import test from 'node:test';
import ownerModule from './initial-control-installation-owner.cjs';

const {createInitialControlInstallationOwner: createOwner} = ownerModule;
const originals = () => ({host: {}, installation: {}, generation: {}, supplier() {}, moduleLifetime: {}});
const changed = {code: 'NodeInitialControlOriginalChanged'};
const inputUnavailable = {code: 'NodeInitialControlInputUnavailable'};

// Explicit original controls test this private state machine only. They are
// not the actual selected startup, a raw acquisition envelope, callback-backing
// admission, public Host positive or business/numerical funding.
function fixture() {
  const original = originals(), raw = {}, snapshot = Object.freeze({raw});
  let result = snapshot, current = true, onRead, reads = 0, prepares = 0;
  const refused = Object.freeze(new Error('OriginalInputCurrentRefused'));
  const root = {prepare(held, input) {
    assert.equal(this, root); assert.equal(held.host, original.host);
    assert.equal(input, raw); prepares++;
  }, assertCurrent(held) {
    assert.equal(this, root); assert.equal(held.host, original.host);
    if (!current) throw refused;
  }, readInput(held) {
    assert.equal(this, root); assert.equal(held.host, original.host);
    reads++; onRead?.(); return result;
  }, close() { assert.equal(this, root); return {pending: false}; }};
  const owner = createOwner(root);
  return {root, owner, original, raw, snapshot, refused,
    begin() { return owner.begin(original, raw); },
    setResult(value) { result = value; }, setCurrent(value) { current = value; },
    setOnRead(value) { onRead = value; }, get reads() { return reads; }, get prepares() { return prepares; }};
}

test('missing operational or intake originals refuse before raw input acquisition', () => {
  let observations = 0;
  const raw = new Proxy({}, {ownKeys() { observations++; throw new Error('RawOwnKeys'); },
    get() { observations++; throw new Error('RawGet'); },
    getOwnPropertyDescriptor() { observations++; throw new Error('RawDescriptor'); }});
  assert.throws(() => createOwner(undefined).begin({}, raw),
    {code: 'NodeInitialControlAdmissionUnavailable'});
  const root = {assertCurrent() {}, close() { return {pending: false}; }};
  assert.throws(() => createOwner(root).begin(originals(), raw), inputUnavailable);
  assert.equal(observations, 0);
});

test('private operational presence check issues no scope and invokes no original callback', () => {
  assert.throws(() => createOwner(undefined).requireOperational(),
    {code: 'NodeInitialControlAdmissionUnavailable'});
  let callbacks = 0;
  const root = {assertCurrent() { callbacks++; }, close() { callbacks++; }};
  const owner = createOwner(root);
  assert.equal(owner.requireOperational(), undefined);
  assert.equal(callbacks, 0);
  assert.throws(() => owner.assertCurrent({}, originals()), changed);
});

test('captured prepare receives the same raw input synchronously before its first await', async () => {
  let covered = false, observations = 0, finish, calls = 0, heldByPrepare;
  const raw = new Proxy({}, {ownKeys() { observations++; assert.equal(covered, true); return []; }});
  const wait = new Promise(resolve => { finish = resolve; });
  const snapshot = Object.freeze({raw}), original = originals();
  const root = {prepare(held, input) {
    assert.equal(this, root); assert.equal(input, raw); heldByPrepare = held; calls++;
    // Only this explicit original fixture grants its acquisition condition.
    // The Owner has not enumerated or inspected raw before this callback.
    assert.equal(observations, 0); covered = true; Reflect.ownKeys(input);
    return wait;
  }, assertCurrent(held) { assert.equal(held, heldByPrepare); },
  readInput(held) { assert.equal(this, root); assert.equal(held, heldByPrepare); return snapshot; },
  close() { return {pending: false}; }};
  const owner = createOwner(root);
  root.prepare = () => { throw new Error('ReplacementPrepare'); };
  const pending = owner.begin(original, raw);
  assert.equal(calls, 1); assert.equal(observations, 1);
  finish({resolvedDataIsNotAnAdmission: true});
  const scope = await pending;
  assert.equal(owner.readInput(scope, original), snapshot);
  assert.throws(() => owner.begin(original, raw), changed);
  assert.equal((await scope.close()).pending, false);
});

test('raw acquisition failure preserves the original cause and pending duty without rereading', () => {
  let calls = 0;
  const cleanupHandle = Object.freeze({status() { return {pending: true}; }, retry() {}});
  const cause = Object.freeze(Object.assign(new Error('OriginalInputUnknown'), {cleanupHandle}));
  const raw = new Proxy({}, {ownKeys() { throw new Error('UnexpectedOwnerRead'); }});
  const root = {prepare(held, input) { calls++; assert.equal(input, raw); throw cause; },
    assertCurrent() { throw new Error('ScopeNotPrepared'); }, close() { throw new Error('NoScope'); }};
  const owner = createOwner(root), original = originals();
  assert.throws(() => owner.begin(original, raw), error => error === cause && error.cleanupHandle === cleanupHandle);
  assert.throws(() => owner.begin(original, raw), changed);
  assert.equal(calls, 1); assert.equal(cleanupHandle.status().pending, true);
});

test('input projection binds its nominal Scope, five originals and original receiver', async () => {
  const f = fixture(), other = fixture(), scope = await f.begin(), foreign = await other.begin();
  f.root.readInput = () => { throw new Error('ReplacementInputReader'); };
  for (const value of [{}, {...scope}, foreign, undefined]) {
    assert.throws(() => f.owner.readInput(value, f.original), changed);
  }
  for (const name of Object.keys(f.original)) {
    assert.throws(() => f.owner.readInput(scope, {...f.original, [name]: {}}), changed);
  }
  assert.equal(f.reads, 0);
  assert.equal(f.owner.readInput(scope, f.original), f.snapshot);
  assert.equal(f.owner.readInput(scope, f.original), f.snapshot);
  f.setResult({...f.snapshot});
  assert.throws(() => f.owner.readInput(scope, f.original), changed);
  assert.equal((await scope.close()).pending, false);
  assert.equal((await foreign.close()).pending, false);
});

test('after-input callback current and reentrant close retain the same pending preparation', async () => {
  const f = fixture(), scope = await f.begin(), record = {snapshot: f.snapshot};
  const duty = scope.retainPreparation(record);
  let closing;
  f.setOnRead(() => { closing = scope.close(); });
  assert.throws(() => f.owner.readInput(scope, f.original), changed);
  assert.equal((await closing).pending, true);
  assert.equal(record.snapshot, f.snapshot);
  record.snapshot = undefined; duty.releaseReferences(record);
  assert.equal((await scope.close()).pending, false);
  // Escaped original DATA is not collected or physically acknowledged by close.
  assert.equal(f.snapshot.raw, f.raw);
  const other = fixture(), otherScope = await other.begin();
  other.setOnRead(() => other.setCurrent(false));
  assert.throws(() => other.owner.readInput(otherScope, other.original), error => error === other.refused);
  assert.equal((await otherScope.close()).pending, false);
});

test('snapshot handoff refuses malformed or asynchronous results without observing them', async () => {
  let reads = 0;
  const proxy = new Proxy({}, {get() { reads++; throw new Error('ProxyGet'); },
    getPrototypeOf() { reads++; throw new Error('ProxyPrototype'); }});
  for (const value of [undefined, null, true, 'snapshot', () => {}, Promise.resolve({}), proxy]) {
    const f = fixture(), scope = await f.begin(); f.setResult(value);
    assert.throws(() => f.owner.readInput(scope, f.original), inputUnavailable);
    assert.equal((await scope.close()).pending, false);
  }
  assert.equal(reads, 0);
});

test('input callback descriptor capture does not run a getter or supply a legacy reader', async () => {
  let reads = 0;
  const base = {assertCurrent() {}, close() { return {pending: false}; }};
  const getter = Object.defineProperty({...base}, 'readInput', {get() { reads++; }});
  assert.throws(() => createOwner(getter), changed);
  assert.equal(reads, 0);
  assert.throws(() => createOwner({...base, readInput: false}),
    {code: 'NodeInitialControlAdmissionUnavailable'});
  const owner = createOwner(base), original = originals(), scope = owner.begin(original);
  assert.throws(() => owner.readInput(scope, original), inputUnavailable);
  assert.equal((await scope.close()).pending, false);
});
