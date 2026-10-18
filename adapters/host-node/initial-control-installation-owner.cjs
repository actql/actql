'use strict';

// Internal state machine, not an operational issuer. Only the actual preload's
// private instance may accept its scopes. Importing this helper and constructing
// another instance cannot add a member to that instance or supply its envelope.
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor, create = Object.create;
const hasOwn = Object.hasOwn, keys = Reflect.ownKeys, apply = Reflect.apply;
const NativeError = Error, NativeWeakMap = WeakMap, NativeWeakSet = WeakSet, NativeMap = Map;
const NativePromise = Promise, promiseResolve = Promise.resolve, promiseThen = Promise.prototype.then;
const weakGet = WeakMap.prototype.get, weakSet = WeakMap.prototype.set;
const generationHas = WeakSet.prototype.has, generationAdd = WeakSet.prototype.add;
const mapGet = Map.prototype.get, mapSet = Map.prototype.set;
const mapEach = Map.prototype.forEach, mapClear = Map.prototype.clear;
const names = freeze(['host', 'installation', 'generation', 'supplier', 'moduleLifetime']);
const reference = value => value !== null &&
  (typeof value === 'object' || typeof value === 'function');
const fail = code => { const error = new NativeError(code); error.code = code; throw error; };
const unavailable = () => fail('NodeInitialControlAdmissionUnavailable');
const foreign = () => fail('NodeInitialControlOriginalChanged');
const own = (value, name) => {
  const property = descriptor(value, name);
  if (property === undefined || !hasOwn(property, 'value')) foreign();
  return property.value;
};
const snapshot = value => {
  if (!reference(value) || keys(value).length !== names.length) foreign();
  const result = create(null);
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    const item = own(value, name);
    if (!reference(item)) foreign();
    result[name] = item;
  }
  return freeze(result);
};
const matches = (left, right) => {
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    if (left[name] !== right[name]) return false;
  }
  return true;
};
const completed = value => reference(value) &&
  descriptor(value, 'pending')?.value === false;

// operational is held only by the selected preload, never obtained from a
// caller packet. Its captured functions retain the selected source,
// backend, recipe and original envelope, including escaped preparation aliases.
// No per-object lease, reserve, allocation or business-Run permission is issued
// here. An absent complete operational original refuses before caller reads.
function createInitialControlInstallationOwner(operational) {
  const assertOperational = operational === undefined ? undefined : own(operational, 'assertCurrent');
  const closeOperational = operational === undefined ? undefined : own(operational, 'close');
  const prepareProperty = operational === undefined ? undefined : descriptor(operational, 'prepare');
  const prepareOperational = prepareProperty === undefined ? undefined : own(operational, 'prepare');
  if (operational !== undefined &&
      (typeof assertOperational !== 'function' || typeof closeOperational !== 'function' ||
       prepareProperty !== undefined && typeof prepareOperational !== 'function')) unavailable();
  const scopes = new NativeWeakMap();
  const generations = new NativeWeakSet();

  function remember(state, cause) {
    const record = freeze({cause});
    state.firstError ??= record;
    state.lastError = record;
  }
  function observeChild(state, child) {
    if (child.cleanup === undefined || child.acknowledged) return;
    try {
      if (completed(apply(child.cleanup.status, child.cleanup.receiver, []))) {
        child.acknowledged = true;
        child.cleanup = undefined;
      }
    } catch (cause) { remember(state, cause); }
  }
  function observation(state) {
    let pendingPreparations = 0;
    apply(mapEach, state.children, [child => {
      observeChild(state, child);
      if (!child.released || !child.acknowledged) pendingPreparations++;
    }]);
    return freeze({pending: !state.closed, closing: state.closing,
      pendingPreparations, errors: freeze(state.firstError === undefined ? [] :
        state.firstError === state.lastError ? [state.firstError] : [state.firstError, state.lastError])});
  }
  function stateFor(scope) {
    const state = apply(weakGet, scopes, [scope]);
    if (state === undefined) foreign();
    return state;
  }
  function assertCurrent(scope, originals) {
    if (assertOperational === undefined) unavailable();
    const state = stateFor(scope);
    if (state.closing || state.closed || !matches(state.originals, snapshot(originals))) foreign();
    apply(assertOperational, operational, [state.originals]);
    // The original supplier callback may reentrantly close this same scope.
    if (state.closing || state.closed) foreign();
  }
  function cleanupOriginal(handle) {
    if (!reference(handle)) foreign();
    const status = own(handle, 'status'), retry = own(handle, 'retry');
    if (typeof status !== 'function' || typeof retry !== 'function') foreign();
    return {receiver: handle, status, retry};
  }
  function retainPreparation(scope, record, handle) {
    const state = stateFor(scope);
    assertCurrent(scope, state.originals);
    if (!reference(record)) foreign();
    let child = apply(mapGet, state.children, [record]);
    if (child !== undefined) {
      if (child.released) foreign();
      if (handle !== undefined) {
        if (child.handle !== undefined && child.handle !== handle) foreign();
        if (child.handle === undefined) {
          // A read can fail only after its managed preparation was retained.
          // Attach its original physical duty once, never replace a pending one.
          child.handle = handle;
          child.acknowledged = false;
          try { child.cleanup = cleanupOriginal(handle); }
          catch (cause) { remember(state, cause); throw cause; }
        }
      }
      return child.duty;
    }
    child = {record, handle, cleanup: undefined, acknowledged: handle === undefined,
      released: false, duty: undefined};
    child.duty = freeze({releaseReferences(originalRecord) {
      if (child.record !== originalRecord || state.closed) foreign();
      child.released = true;
      // This is only the caller's managed alias-cut notice. It does not
      // acknowledge FD/body/native cleanup, escaped aliases, GC or capacity.
    }});
    // Retain the record before any fallible cleanup descriptor observation.
    apply(mapSet, state.children, [record, child]);
    if (handle !== undefined) {
      try { child.cleanup = cleanupOriginal(handle); }
      catch (cause) { remember(state, cause); throw cause; }
    }
    return child.duty;
  }
  function close(scope) {
    const state = stateFor(scope);
    if (state.flight !== undefined) return state.flight;
    state.closing = true;
    if (state.closed) return Promise.resolve(observation(state));
    // Install one flight before invoking any original callback. A reentrant or
    // concurrent close observes that SAME Promise and cannot double-retry.
    const flight = Promise.resolve().then(async () => {
      // Snapshot original child references with the captured native Map walk;
      // a later application replacement cannot skip another child's duty.
      const children = [];
      apply(mapEach, state.children, [child => { children[children.length] = child; }]);
      for (let index = 0; index < children.length; index++) {
        const child = children[index];
        observeChild(state, child);
        if (child.cleanup !== undefined && !child.acknowledged) {
          try { await apply(child.cleanup.retry, child.cleanup.receiver, []); }
          catch (cause) { remember(state, cause); }
          // Retry's return value or settlement is not an ACK. Only the original
          // captured status observation may acknowledge this physical duty.
          observeChild(state, child);
        }
      }
      const before = observation(state);
      if (before.pendingPreparations !== 0) return before;
      try {
        const value = await apply(closeOperational, operational, [state.originals]);
        if (!completed(value)) return observation(state);
      } catch (cause) {
        remember(state, cause);
        return observation(state);
      }
      state.closed = true;
      apply(mapEach, state.children, [child => {
        child.record = undefined;
        child.handle = undefined;
        child.cleanup = undefined;
      }]);
      apply(mapClear, state.children, []);
      state.originals = undefined;
      return observation(state);
    }).finally(() => { if (state.flight === flight) state.flight = undefined; });
    state.flight = flight;
    return flight;
  }
  function issue(held) {
    apply(assertOperational, operational, [held]);
    const state = {originals: held, children: new NativeMap(), closing: false, closed: false,
      flight: undefined, firstError: undefined, lastError: undefined};
    const scope = freeze({assertCurrent(sameOriginals) { assertCurrent(scope, sameOriginals); },
      retainPreparation(record, cleanupHandle) { return retainPreparation(scope, record, cleanupHandle); },
      status() { return observation(state); }, close() { return close(scope); }});
    apply(weakSet, scopes, [scope, state]);
    return scope;
  }
  function begin(originals) {
    if (assertOperational === undefined) unavailable();
    const held = snapshot(originals);
    if (apply(generationHas, generations, [held.generation])) foreign();
    // Snapshot and consume before module initialization or any original current
    // callback can await or reenter. Caller packet mutation cannot replace one
    // of the five originals while the actual supplier's flight is pending.
    apply(generationAdd, generations, [held.generation]);
    if (prepareOperational === undefined) return issue(held);
    // Only the preload's captured operational original can initialize its
    // selected Host namespace. That original owns the single initialization
    // flight and any partial/Unknown cleanup duty; no provisional scope, copied
    // authority or second cleanup Owner is issued here. Preserve its rejection
    // and original cleanupHandle without wrapping, retrying or treating Promise
    // settlement as physical cleanup. Current is checked after initialization.
    const prepared = apply(prepareOperational, operational, [held]);
    return apply(promiseThen, apply(promiseResolve, NativePromise, [prepared]),
      [() => issue(held)]);
  }
  return freeze({begin, assertCurrent});
}

module.exports = {createInitialControlInstallationOwner};
freeze(module.exports);
