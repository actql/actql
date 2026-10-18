'use strict';

// Internal state machine, not an operational issuer. Only the actual preload's
// private instance may accept its scopes. Importing this helper and constructing
// another instance cannot add a member to that instance or supply its envelope.
const names = Object.freeze(['host', 'installation', 'generation', 'supplier', 'moduleLifetime']);
const reference = value => value !== null &&
  (typeof value === 'object' || typeof value === 'function');
const fail = code => { throw Object.assign(new Error(code), {code}); };
const unavailable = () => fail('NodeInitialControlAdmissionUnavailable');
const foreign = () => fail('NodeInitialControlOriginalChanged');
const own = (value, name) => {
  const descriptor = Object.getOwnPropertyDescriptor(value, name);
  if (descriptor === undefined || !Object.hasOwn(descriptor, 'value')) foreign();
  return descriptor.value;
};
const snapshot = value => {
  if (!reference(value) || Reflect.ownKeys(value).length !== names.length) foreign();
  const result = {};
  for (const name of names) {
    const item = own(value, name);
    if (!reference(item)) foreign();
    result[name] = item;
  }
  return Object.freeze(result);
};
const matches = (left, right) => names.every(name => left[name] === right[name]);
const completed = value => reference(value) &&
  Object.getOwnPropertyDescriptor(value, 'pending')?.value === false;

// operational is held only by the selected preload, never obtained from a
// caller packet. Its two captured functions retain the selected source,
// backend, recipe and original envelope, including escaped preparation aliases.
// No per-object lease, reserve, allocation or business-Run permission is issued
// here. An absent complete operational original refuses before caller reads.
function createInitialControlInstallationOwner(operational) {
  const assertOperational = operational === undefined ? undefined : own(operational, 'assertCurrent');
  const closeOperational = operational === undefined ? undefined : own(operational, 'close');
  if (operational !== undefined &&
      (typeof assertOperational !== 'function' || typeof closeOperational !== 'function')) unavailable();
  const scopes = new WeakMap();
  const generations = new WeakSet();

  function remember(state, cause) {
    const record = Object.freeze({cause});
    state.firstError ??= record;
    state.lastError = record;
  }
  function observeChild(state, child) {
    if (child.cleanup === undefined || child.acknowledged) return;
    try {
      if (completed(Reflect.apply(child.cleanup.status, child.cleanup.receiver, []))) {
        child.acknowledged = true;
        child.cleanup = undefined;
      }
    } catch (cause) { remember(state, cause); }
  }
  function observation(state) {
    let pendingPreparations = 0;
    for (const child of state.children.values()) {
      observeChild(state, child);
      if (!child.released || !child.acknowledged) pendingPreparations++;
    }
    return Object.freeze({pending: !state.closed, closing: state.closing,
      pendingPreparations, errors: Object.freeze(state.firstError === undefined ? [] :
        state.firstError === state.lastError ? [state.firstError] : [state.firstError, state.lastError])});
  }
  function stateFor(scope) {
    const state = scopes.get(scope);
    if (state === undefined) foreign();
    return state;
  }
  function assertCurrent(scope, originals) {
    if (assertOperational === undefined) unavailable();
    const state = stateFor(scope);
    if (state.closing || state.closed || !matches(state.originals, snapshot(originals))) foreign();
    Reflect.apply(assertOperational, operational, [state.originals]);
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
    let child = state.children.get(record);
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
    child.duty = Object.freeze({releaseReferences(originalRecord) {
      if (child.record !== originalRecord || state.closed) foreign();
      child.released = true;
      // This is only the caller's managed alias-cut notice. It does not
      // acknowledge FD/body/native cleanup, escaped aliases, GC or capacity.
    }});
    // Retain the record before any fallible cleanup descriptor observation.
    state.children.set(record, child);
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
      for (const child of state.children.values()) {
        observeChild(state, child);
        if (child.cleanup !== undefined && !child.acknowledged) {
          try { await Reflect.apply(child.cleanup.retry, child.cleanup.receiver, []); }
          catch (cause) { remember(state, cause); }
          // Retry's return value or settlement is not an ACK. Only the original
          // captured status observation may acknowledge this physical duty.
          observeChild(state, child);
        }
      }
      const before = observation(state);
      if (before.pendingPreparations !== 0) return before;
      try {
        const value = await Reflect.apply(closeOperational, operational, [state.originals]);
        if (!completed(value)) return observation(state);
      } catch (cause) {
        remember(state, cause);
        return observation(state);
      }
      state.closed = true;
      for (const child of state.children.values()) {
        child.record = undefined;
        child.handle = undefined;
        child.cleanup = undefined;
      }
      state.children.clear();
      state.originals = undefined;
      return observation(state);
    }).finally(() => { if (state.flight === flight) state.flight = undefined; });
    state.flight = flight;
    return flight;
  }
  function begin(originals) {
    if (assertOperational === undefined) unavailable();
    const held = snapshot(originals);
    if (generations.has(held.generation)) foreign();
    // Consume before the original current callback: it may reenter this Owner.
    // A refused attempt cannot recycle this generation into a second issue.
    generations.add(held.generation);
    Reflect.apply(assertOperational, operational, [held]);
    const state = {originals: held, children: new Map(), closing: false, closed: false,
      flight: undefined, firstError: undefined, lastError: undefined};
    const scope = Object.freeze({assertCurrent(sameOriginals) { assertCurrent(scope, sameOriginals); },
      retainPreparation(record, cleanupHandle) { return retainPreparation(scope, record, cleanupHandle); },
      status() { return observation(state); }, close() { return close(scope); }});
    scopes.set(scope, state);
    return scope;
  }
  return Object.freeze({begin, assertCurrent});
}

module.exports = Object.freeze({createInitialControlInstallationOwner});
