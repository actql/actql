'use strict';

// Physical byte storage only. This helper does not authenticate a startup,
// create Source capacity, admit managed decode or authorize HTTP. The actual
// private installation retains ONE instance and its original Resource ports;
// another instance or a scope-looking object cannot replace that membership.
const {Buffer} = require('node:buffer');
const {isPromise} = require('node:util').types;
const alloc = Buffer.alloc, isBuffer = Buffer.isBuffer;
const copy = Buffer.prototype.copy, subarray = Buffer.prototype.subarray;
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const freeze = Object.freeze, integer = Number.isSafeInteger;
const NativeWeakMap = WeakMap;
const get = WeakMap.prototype.get, set = WeakMap.prototype.set;
const NativeError = Error;

function fail(code) { throw Object.assign(new NativeError(code), {code}); }
function callback(receiver, name) {
  const d = descriptor(receiver, name);
  if (d === undefined || !Object.hasOwn(d, 'value') || typeof d.value !== 'function') {
    fail('InvalidSourceResponseBackingPorts');
  }
  return d.value;
}

function createSourceResponseBackingOwner(ports) {
  const current = callback(ports, 'assertSourceCurrent');
  const reserve = callback(ports, 'reserveResponseStorage');
  const borrow = callback(ports, 'borrowResponseStorage');
  const returned = callback(ports, 'returnResponseBorrow');
  const pools = new NativeWeakMap(), loans = new NativeWeakMap();
  // Strong original records deliberately survive alias-cut and child return.
  // The process/module domain, not GC or a Source close, owns this allocation.
  // Each supported installation has one finite pool; no released window is
  // reused and no successful sibling replenishes another child's allowance.
  const originals = [];
  let attempted = false;
  const requireCurrent = scope => apply(current, ports, [scope]);
  function poolFor(pool, scope) {
    const state = apply(get, pools, [pool]);
    if (state === undefined || state.scope !== scope) fail('ForeignSourceResponseBacking');
    return state;
  }
  function loanFor(loan) {
    const state = apply(get, loans, [loan]);
    if (state === undefined) fail('ForeignSourceResponseBacking');
    return state;
  }
  function remember(state, cause) {
    const record = freeze({cause});
    state.firstError ??= record;
    state.lastError = record;
  }
  function allocate(scope, bytes, maxLoans) {
    requireCurrent(scope);
    if (attempted || !integer(bytes) || bytes < 1 || bytes > 2147483647 ||
        !integer(maxLoans) || maxLoans < 1 || maxLoans > 128) {
      fail('SourceResponseBackingUnavailable');
    }
    attempted = true;
    const pool = freeze(Object.create(null));
    const state = {scope, bytes, maxLoans, allocated: 0, children: [],
      original: undefined, buffer: undefined, closing: false,
      firstError: undefined, lastError: undefined};
    apply(set, pools, [pool, state]);
    originals[originals.length] = state;
    try {
      // Reserve through the original Resource before allocation. Returning
      // DATA here is not itself a capacity proof: only the actual private
      // installation may supply these fixed original ports and use its pool.
      state.original = apply(reserve, ports, [scope, bytes]);
      if (state.original === undefined || isPromise(state.original)) {
        fail('SourceResponseBackingUnavailable');
      }
      requireCurrent(scope);
      state.buffer = apply(alloc, Buffer, [bytes]);
      requireCurrent(scope);
      return pool;
    } catch (cause) {
      state.closing = true;
      remember(state, cause);
      // An allocation/reservation failure retains its original record and
      // cause. Never retry alloc, fabricate zero use or return parent credit.
      throw cause;
    }
  }
  function acquire(pool, scope, readOriginal, maxBytes) {
    const parent = poolFor(pool, scope);
    requireCurrent(scope);
    if (parent.closing || parent.buffer === undefined || !integer(maxBytes) ||
        maxBytes < 1 || maxBytes > parent.bytes - parent.allocated ||
        parent.children.length >= parent.maxLoans ||
        readOriginal === null || (typeof readOriginal !== 'object' && typeof readOriginal !== 'function')) {
      fail('SourceResponseBackingUnavailable');
    }
    const loan = freeze(Object.create(null));
    const state = {parent, scope, readOriginal, offset: parent.allocated, maxBytes,
      written: 0, borrowed: undefined, entered: false, finished: false, failed: false,
      writerStopped: false, aliasesReleased: false, returned: false,
      body: undefined, firstError: undefined, lastError: undefined};
    // Commit the non-reusable window and partial original BEFORE the original
    // borrow callback can fail or reenter. Other children remain independent.
    parent.allocated += maxBytes;
    parent.children[parent.children.length] = state;
    apply(set, loans, [loan, state]);
    try {
      state.borrowed = apply(borrow, ports,
        [scope, parent.original, readOriginal, state.offset, maxBytes]);
      if (state.borrowed === undefined || isPromise(state.borrowed)) {
        fail('SourceResponseBackingUnavailable');
      }
      requireCurrent(scope);
      return loan;
    } catch (cause) { remember(state, cause); throw cause; }
  }
  function start(loan, scope, readOriginal) {
    const state = loanFor(loan);
    requireCurrent(scope);
    if (state.scope !== scope || state.readOriginal !== readOriginal || state.entered ||
        state.parent.closing || state.borrowed === undefined || state.writerStopped) {
      fail('ForeignSourceResponseBacking');
    }
    state.entered = true;
    return freeze({
      write(chunk) {
        try {
          requireCurrent(state.scope);
          if (state.parent.closing || state.writerStopped || state.finished ||
              state.failed || !isBuffer(chunk) || chunk.length > state.maxBytes - state.written) {
            fail('SourceResponseBodyLimit');
          }
          apply(copy, chunk, [state.parent.buffer, state.offset + state.written]);
          state.written += chunk.length;
          requireCurrent(state.scope);
        } catch (cause) {
          state.failed = true;
          remember(state, cause);
          throw cause;
        }
      },
      finish() {
        requireCurrent(state.scope);
        if (state.parent.closing || state.writerStopped || state.finished || state.failed) {
          fail('SourceResponseBodyUnavailable');
        }
        state.finished = true;
        state.body = apply(subarray, state.parent.buffer,
          [state.offset, state.offset + state.written]);
        requireCurrent(state.scope);
        return state.body;
      },
      // The original receive owner calls this after cutting its write path.
      // It is not a socket/FD/native ACK and releases no physical byte credit.
      stop() { state.writerStopped = true; },
    });
  }
  function releaseAliases(loan, scope, readOriginal) {
    const state = loanFor(loan);
    if (state.scope !== scope || state.readOriginal !== readOriginal) {
      fail('ForeignSourceResponseBacking');
    }
    state.aliasesReleased = true;
    state.body = undefined;
  }
  function settle(loan) {
    const state = loanFor(loan);
    if (state.returned || !state.writerStopped || !state.aliasesReleased) return status(loan);
    try {
      // Only the original Resource return may acknowledge the child borrow.
      // Promise/undefined/truthiness or writer.stop alone never does so.
      if (apply(returned, ports, [state.scope, state.parent.original,
          state.readOriginal, state.borrowed]) === true) state.returned = true;
    } catch (cause) { remember(state, cause); }
    return status(loan);
  }
  function status(loan) {
    const state = loanFor(loan);
    return freeze({pending: !state.returned, writerStopped: state.writerStopped,
      aliasesReleased: state.aliasesReleased, borrowReturned: state.returned,
      parentBytesReleased: false});
  }
  function close(pool, scope) { poolFor(pool, scope).closing = true; }
  function poolStatus(pool, scope) {
    const state = poolFor(pool, scope);
    return freeze({bytes: state.bytes, allocated: state.allocated,
      children: state.children.length, closing: state.closing,
      backingRetained: state.buffer !== undefined, parentBytesReleased: false});
  }
  return freeze({allocate, acquire, start, releaseAliases, settle, status, close, poolStatus});
}
module.exports = freeze({createSourceResponseBackingOwner});
