import assert from 'node:assert/strict';
import test from 'node:test';
import module from './source-response-backing.cjs';

// Explicit original-Resource port controls only. The Buffer backing is real;
// these are not actual startup/Source admission or a normal funding positive.
function fixture() {
  const scope = Object.freeze({}), original = Object.freeze({});
  const state = {current: true, returns: 0, acknowledged: true, windows: []};
  const ports = {
    assertSourceCurrent(value) { assert.equal(this, ports); assert.equal(value, scope);
      state.currentChecks = (state.currentChecks ?? 0) + 1;
      if (!state.current || state.currentChecks === state.failOnCheck) {
        if (state.currentFailurePresent) throw state.currentFailure;
        throw new Error('OriginalSourceClosing');
      } },
    reserveResponseStorage(value, bytes) { assert.equal(this, ports); assert.equal(value, scope);
      assert.equal(bytes, 16); return original; },
    borrowResponseStorage(value, parent, read, offset, bytes) { assert.equal(this, ports);
      assert.equal(value, scope); assert.equal(parent, original); state.windows.push([offset, bytes]);
      state.afterBorrow?.();
      if (state.borrowReplyPresent) return state.borrowReply;
      return Object.freeze({read}); },
    returnResponseBorrow(value, parent, read, borrowed) { assert.equal(this, ports);
      assert.equal(value, scope); assert.equal(parent, original); assert.equal(borrowed.read, read);
      state.returns++; return state.acknowledged; },
  };
  const owner = module.createSourceResponseBackingOwner(ports);
  const pool = owner.allocate(scope, 16, 4);
  return {scope, state, ports, owner, pool};
}

test('original byte backing uses distinct non-reusable allocations without chunk copies or concat', () => {
  const f = fixture(), first = {}, second = {};
  const a = f.owner.acquire(f.pool, f.scope, first, 8), b = f.owner.acquire(f.pool, f.scope, second, 8);
  const writeA = f.owner.start(a, f.scope, first), writeB = f.owner.start(b, f.scope, second);
  writeA.write(Buffer.from('abc')); writeB.write(Buffer.from('xyz'));
  const bodyA = writeA.finish(), bodyB = writeB.finish();
  assert.equal(bodyA.toString(), 'abc'); assert.equal(bodyB.toString(), 'xyz');
  assert.notEqual(bodyA.buffer, bodyB.buffer);
  assert.equal(bodyA.buffer.byteLength, 8); assert.equal(bodyB.buffer.byteLength, 8);
  assert.deepEqual(f.state.windows, [[0, 8], [8, 8]]);
  writeA.stop(); f.owner.releaseAliases(a, f.scope, first);
  assert.equal(f.owner.settle(a).pending, false);
  assert.equal(f.owner.status(b).pending, true);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).allocated, 16);
  assert.throws(() => f.owner.acquire(f.pool, f.scope, {}, 1), {code: 'SourceResponseBackingUnavailable'});
});

test('overflow admits no partial handoff and retains the same loan until writer and aliases stop', () => {
  const f = fixture(), read = {}, loan = f.owner.acquire(f.pool, f.scope, read, 3);
  const writer = f.owner.start(loan, f.scope, read);
  writer.write(Buffer.from('ab'));
  assert.throws(() => writer.write(Buffer.from('cd')), {code: 'SourceResponseBodyLimit'});
  assert.throws(() => writer.finish(), {code: 'SourceResponseBodyUnavailable'});
  assert.equal(f.owner.settle(loan).pending, true); assert.equal(f.state.returns, 0);
  writer.stop(); assert.equal(f.owner.settle(loan).pending, true);
  f.owner.releaseAliases(loan, f.scope, read); assert.equal(f.owner.settle(loan).pending, false);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).backingRetained, true);
});

test('copied, foreign and repeated loans cannot replace the original read', () => {
  const f = fixture(), g = fixture(), read = {}, loan = f.owner.acquire(f.pool, f.scope, read, 4);
  assert.throws(() => f.owner.start({...loan}, f.scope, read), {code: 'ForeignSourceResponseBacking'});
  assert.throws(() => g.owner.start(loan, g.scope, read), {code: 'ForeignSourceResponseBacking'});
  assert.throws(() => f.owner.start(loan, f.scope, {...read}), {code: 'ForeignSourceResponseBacking'});
  f.owner.start(loan, f.scope, read);
  assert.throws(() => f.owner.start(loan, f.scope, read), {code: 'ForeignSourceResponseBacking'});
});

test('return failure keeps debt and original callback receiver even after its public method changes', () => {
  const f = fixture(), read = {}, loan = f.owner.acquire(f.pool, f.scope, read, 4);
  const writer = f.owner.start(loan, f.scope, read); writer.write(Buffer.from('a')); writer.finish();
  writer.stop(); f.owner.releaseAliases(loan, f.scope, read); f.state.acknowledged = false;
  f.ports.returnResponseBorrow = () => {throw new Error('ReplacementMustNotRun');};
  assert.equal(f.owner.settle(loan).pending, true); assert.equal(f.state.returns, 1);
  f.state.acknowledged = true; assert.equal(f.owner.settle(loan).pending, false);
  assert.equal(f.state.returns, 2); assert.equal(f.owner.settle(loan).pending, false);
  assert.equal(f.state.returns, 2); assert.equal(f.owner.poolStatus(f.pool, f.scope).parentBytesReleased, false);
});

test('closing a Source forbids new loans while same original cleanup remains possible', () => {
  const f = fixture(), read = {}, loan = f.owner.acquire(f.pool, f.scope, read, 4);
  const writer = f.owner.start(loan, f.scope, read); writer.write(Buffer.from('a'));
  f.owner.close(f.pool, f.scope); f.state.current = false;
  assert.throws(() => writer.write(Buffer.from('b')), /OriginalSourceClosing/);
  writer.stop(); f.owner.releaseAliases(loan, f.scope, read);
  assert.equal(f.owner.settle(loan).pending, false);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).backingRetained, true);
});

test('Source close and child return never replenish the process-lifetime allocation', () => {
  const f = fixture(), read = {}, loan = f.owner.acquire(f.pool, f.scope, read, 4);
  const writer = f.owner.start(loan, f.scope, read); writer.stop();
  f.owner.releaseAliases(loan, f.scope, read); f.owner.settle(loan);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).allocated, 4);
  assert.throws(() => f.owner.allocate(f.scope, 16, 4), {code: 'SourceResponseBackingUnavailable'});
});

test('local closing refuses new output even before an external current callback changes', () => {
  const f = fixture(), read = {}, loan = f.owner.acquire(f.pool, f.scope, read, 4);
  const writer = f.owner.start(loan, f.scope, read);
  f.owner.close(f.pool, f.scope);
  assert.throws(() => writer.write(Buffer.from('a')), {code: 'SourceResponseBodyLimit'});
  assert.throws(() => writer.finish(), {code: 'SourceResponseBodyUnavailable'});
  writer.stop(); f.owner.releaseAliases(loan, f.scope, read);
  assert.equal(f.owner.settle(loan).pending, false);
});

test('Promise or undefined return observations are pending, never a cleanup acknowledgement', () => {
  const f = fixture(), read = {}, loan = f.owner.acquire(f.pool, f.scope, read, 4);
  const writer = f.owner.start(loan, f.scope, read);
  writer.stop(); f.owner.releaseAliases(loan, f.scope, read);
  for (const result of [undefined, Promise.resolve(true), {}, 1]) {
    f.state.acknowledged = result;
    assert.equal(f.owner.settle(loan).pending, true);
  }
  f.state.acknowledged = true;
  assert.equal(f.owner.settle(loan).pending, false);
});

test('response backing never exposes a sibling through the returned Buffer ArrayBuffer', () => {
  const f = fixture(), a = {}, b = {};
  const loanA = f.owner.acquire(f.pool, f.scope, a, 8), loanB = f.owner.acquire(f.pool, f.scope, b, 8);
  const writerA = f.owner.start(loanA, f.scope, a), writerB = f.owner.start(loanB, f.scope, b);
  writerA.write(Buffer.from('a')); writerB.write(Buffer.from('b'));
  const bodyA = writerA.finish(), bodyB = writerB.finish();
  assert.notEqual(bodyA.buffer, bodyB.buffer);
  new Uint8Array(bodyA.buffer).fill(120);
  assert.equal(bodyB.toString(), 'b');
});

test('partial current refusal retains the acquired original borrow in the same cleanup carrier', () => {
  const f = fixture(), read = {};
  f.state.afterBorrow = () => {f.state.current = false;};
  let failure;
  try { f.owner.acquire(f.pool, f.scope, read, 4); assert.fail('acquire must refuse'); }
  catch (cause) { failure = cause; }
  assert.ok(failure.cleanupHandle);
  assert.match(failure.cause.message, /OriginalSourceClosing/);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(f.state.returns, 0);
  // The original return callback/receiver, not its later public replacement,
  // settles exactly this borrow. No writer or body was ever handed off.
  f.ports.returnResponseBorrow = () => {throw new Error('ReplacementMustNotRun');};
  f.state.acknowledged = false;
  assert.equal(failure.cleanupHandle.retry().pending, true);
  assert.equal(f.state.returns, 1);
  f.state.acknowledged = true;
  assert.equal(failure.cleanupHandle.retry().pending, false);
  assert.equal(f.state.returns, 2);
  assert.equal(failure.cleanupHandle.retry().pending, false);
  assert.equal(f.state.returns, 2);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).allocated, 4);
});

test('partial refusal after actual allocation keeps its backing and immutable original cause', () => {
  const f = fixture(), original = Object.freeze(new Error('OriginalAfterAllocation'));
  f.state.failOnCheck = f.state.currentChecks + 3;
  f.state.currentFailurePresent = true; f.state.currentFailure = original;
  let failure;
  try { f.owner.acquire(f.pool, f.scope, {}, 4); assert.fail('acquire must refuse'); }
  catch (cause) { failure = cause; }
  assert.equal(failure.cause, original);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).backingRetained, true);
  assert.equal(failure.cleanupHandle.retry().pending, false);
  assert.equal(f.state.returns, 1);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).backingRetained, true);
  assert.equal(f.owner.poolStatus(f.pool, f.scope).parentBytesReleased, false);
});

test('missing or asynchronous borrow replies retain Unknown without inventing a return token', () => {
  for (const result of [undefined, null, 1, true, Promise.resolve({})]) {
    const f = fixture(); f.state.borrowReplyPresent = true; f.state.borrowReply = result;
    let failure;
    try { f.owner.acquire(f.pool, f.scope, {}, 4); assert.fail('acquire must refuse'); }
    catch (cause) { failure = cause; }
    assert.equal(failure.code, 'SourceResponseBackingCleanupPending');
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(failure.cleanupHandle.retry().pending, true);
    assert.equal(f.state.returns, 0);
    assert.equal(f.owner.poolStatus(f.pool, f.scope).allocated, 4);
    assert.equal(f.owner.poolStatus(f.pool, f.scope).backingRetained, false);
  }
});

test('an undefined thrown cause remains the exact failed original while its known borrow cleans up', () => {
  const f = fixture(); f.state.currentFailurePresent = true; f.state.currentFailure = undefined;
  f.state.afterBorrow = () => {f.state.current = false;};
  let failure;
  try { f.owner.acquire(f.pool, f.scope, {}, 4); assert.fail('acquire must refuse'); }
  catch (cause) { failure = cause; }
  assert.equal(Object.hasOwn(failure, 'cause'), true); assert.equal(failure.cause, undefined);
  assert.equal(failure.cleanupHandle.retry().pending, false);
  assert.equal(f.state.returns, 1);
});
