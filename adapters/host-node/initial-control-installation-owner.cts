'use strict';

// Internal state machine, not an operational issuer. Only the actual preload's
// private instance may accept its scopes. Importing this helper and constructing
// another instance cannot add a member to that instance or supply its envelope.
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor, create = Object.create;
const hasOwn = Object.hasOwn, keys = Reflect.ownKeys, apply = Reflect.apply;
const NativeError = Error, NativeWeakMap = WeakMap, NativeWeakSet = WeakSet, NativeMap = Map;
const {isPromise, isProxy} = (require('node:util') as typeof import('node:util')).types;
const NativePromise = Promise, promiseResolve = Promise.resolve, promiseThen = Promise.prototype.then;
const weakGet = WeakMap.prototype.get, weakSet = WeakMap.prototype.set;
const generationHas = WeakSet.prototype.has, generationAdd = WeakSet.prototype.add;
const mapGet = Map.prototype.get, mapSet = Map.prototype.set;
const mapEach = Map.prototype.forEach, mapClear = Map.prototype.clear;
const names = freeze(['host', 'installation', 'generation', 'supplier', 'moduleLifetime'] as const);
const reference = (value:unknown):value is object => value !== null &&
  (typeof value === 'object' || typeof value === 'function');
const fail: (code:string)=>never = code => { const error = new NativeError(code) as NodeJS.ErrnoException; error.code = code; throw error; };
const unavailable: ()=>never = () => fail('NodeInitialControlAdmissionUnavailable');
const foreign: ()=>never = () => fail('NodeInitialControlOriginalChanged');
const own = (value:object, name:PropertyKey):unknown => {
  const property = descriptor(value, name);
  if (property === undefined || !hasOwn(property, 'value')) foreign();
  return property.value;
};
type Snapshot = Readonly<Record<typeof names[number],object>>;
type CapturedMethod = (...args:never[])=>unknown;
type Cleanup = {receiver:object;status:CapturedMethod;retry:CapturedMethod};
type Duty = Readonly<{releaseReferences(originalRecord:unknown):void}>;
type Child = {record:object|undefined;handle:unknown;cleanup:Cleanup|undefined;
  acknowledged:boolean;released:boolean;duty:Duty|undefined};
type ErrorRecord = Readonly<{cause:unknown}>;
type Observation = Readonly<{pending:boolean;closing:boolean;pendingPreparations:number;
  errors:readonly ErrorRecord[]}>;
type Scope = Readonly<{
  assertCurrent(sameOriginals:unknown):void;
  retainPreparation(record:unknown,cleanupHandle?:unknown):Duty;
  status():Observation;
  close():Promise<Observation>;
}>;
type State = {
  originals:Snapshot|undefined;input:object|undefined;children:Map<object,Child>;
  closing:boolean;closed:boolean;flight:Promise<Observation>|undefined;
  firstError:ErrorRecord|undefined;lastError:ErrorRecord|undefined;
};
type Owner<Begin> = Readonly<{
  begin(originals:unknown,rawInput?:unknown):Begin;
  assertCurrent(scope:unknown,originals:unknown):void;
  readAsset(scope:unknown,originals:unknown,path:unknown):string;
  readInput(scope:unknown,originals:unknown):object;
  requireOperational():void;
}>;
type Operational = Readonly<{assertCurrent:CapturedMethod;close:CapturedMethod}>;

const snapshot = (value:unknown):Snapshot => {
  if (!reference(value) || keys(value).length !== names.length) foreign();
  const result = create(null) as Record<typeof names[number],object>;
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    const item = own(value, name);
    if (!reference(item)) foreign();
    result[name] = item;
  }
  return freeze(result);
};
const matches = (left:Snapshot, right:Snapshot) => {
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    if (left[name] !== right[name]) return false;
  }
  return true;
};
const completed = (value:unknown) => reference(value) &&
  descriptor(value, 'pending')?.value === false;

// operational is held only by the selected preload, never obtained from a
// caller packet. Its captured functions retain the selected source,
// backend, recipe and original envelope, including escaped preparation aliases.
// No per-object lease, reserve, allocation or business-Run permission is issued
// here. An absent complete operational original refuses before caller reads.
function createInitialControlInstallationOwner(operational:Operational & {prepare:CapturedMethod}):Owner<Promise<Scope>>;
function createInitialControlInstallationOwner(operational:object|undefined):Owner<Scope|Promise<Scope>>;
function createInitialControlInstallationOwner(operational:object|undefined):Owner<Scope|Promise<Scope>> {
  const assertOperational = operational === undefined ? undefined : own(operational, 'assertCurrent') as CapturedMethod|undefined;
  const closeOperational = operational === undefined ? undefined : own(operational, 'close') as CapturedMethod|undefined;
  const prepareProperty = operational === undefined ? undefined : descriptor(operational, 'prepare');
  const prepareOperational = prepareProperty === undefined ? undefined : own(operational!, 'prepare') as CapturedMethod|undefined;
  const assetProperty = operational === undefined ? undefined : descriptor(operational, 'readAsset');
  const readOperationalAsset = assetProperty === undefined ? undefined : own(operational!, 'readAsset') as CapturedMethod|undefined;
  const inputProperty = operational === undefined ? undefined : descriptor(operational, 'readInput');
  const readOperationalInput = inputProperty === undefined ? undefined : own(operational!, 'readInput') as CapturedMethod|undefined;
  if (operational !== undefined &&
      (typeof assertOperational !== 'function' || typeof closeOperational !== 'function' ||
       prepareProperty !== undefined && typeof prepareOperational !== 'function' ||
       assetProperty !== undefined && typeof readOperationalAsset !== 'function' ||
       inputProperty !== undefined && typeof readOperationalInput !== 'function')) unavailable();
  const scopes = new NativeWeakMap<object,State>();
  const generations = new NativeWeakSet<object>();

  function requireOperational() {
    // Private pre-dispatch absence fence only, before a Host candidate exists.
    // It issues no scope, observes no caller and invokes no original callback.
    // Same-Host/current/raw-acquisition checks still belong to actual begin.
    if (assertOperational === undefined) unavailable();
  }

  function remember(state:State, cause:unknown) {
    const record = freeze({cause});
    state.firstError ??= record;
    state.lastError = record;
  }
  function observeChild(state:State, child:Child) {
    if (child.cleanup === undefined || child.acknowledged) return;
    try {
      if (completed(apply(child.cleanup.status, child.cleanup.receiver, []))) {
        child.acknowledged = true;
        child.cleanup = undefined;
      }
    } catch (cause) { remember(state, cause); }
  }
  function observation(state:State):Observation {
    let pendingPreparations = 0;
    apply(mapEach, state.children, [(child:Child) => {
      observeChild(state, child);
      if (!child.released || !child.acknowledged) pendingPreparations++;
    }]);
    return freeze({pending: !state.closed, closing: state.closing,
      pendingPreparations, errors: freeze(state.firstError === undefined ? [] :
        state.firstError === state.lastError ? [state.firstError] : [state.firstError, state.lastError!])});
  }
  function stateFor(scope:unknown) {
    const state = apply(weakGet, scopes, [scope]) as State|undefined;
    if (state === undefined) foreign();
    return state;
  }
  function assertCurrent(scope:unknown, originals:unknown) {
    if (assertOperational === undefined) unavailable();
    const state = stateFor(scope);
    if (state.closing || state.closed || !matches(state.originals!, snapshot(originals))) foreign();
    apply(assertOperational, operational, [state.originals]);
    // The original supplier callback may reentrantly close this same scope.
    if (state.closing || state.closed) foreign();
  }
  function readAsset(scope:unknown, originals:unknown, path:unknown) {
    // This is an immutable original Source borrow, not another file read or a
    // decoder, authority factory, current-path proof or capacity conversion.
    // Only the SAME nominal scope and five originals can reach the actual
    // preload's captured asset projection. Never call caller scope methods.
    assertCurrent(scope, originals);
    if (readOperationalAsset === undefined || typeof path !== 'string') {
      fail('NodeInitialControlAssetUnavailable');
    }
    const state = stateFor(scope);
    const source = apply(readOperationalAsset, operational, [state.originals, path]);
    // The original callback may retire this same Host/scope reentrantly.
    // Do not let the returned String bypass that current/closing fence.
    assertCurrent(scope, originals);
    if (typeof source !== 'string') fail('NodeInitialControlAssetUnavailable');
    return source;
  }
  function readInput(scope:unknown, originals:unknown) {
    // Only the original supplier may acquire and retain the raw packet before
    // its first enumeration/copy. This projection cannot admit that input,
    // infer its backing from shape/alias count or reconstruct a snapshot.
    assertCurrent(scope, originals);
    if (readOperationalInput === undefined) fail('NodeInitialControlInputUnavailable');
    const state = stateFor(scope);
    const input:unknown = apply(readOperationalInput, operational, [state.originals]);
    // Native brand tests observe neither a then getter nor Proxy traps. The
    // actual supplier still owns finite provenance, bounds and original DATA;
    // these representation checks are not that operational proof.
    if (input === null || typeof input !== 'object' || isPromise(input) || isProxy(input)) {
      fail('NodeInitialControlInputUnavailable');
    }
    if (state.input !== undefined && state.input !== input) foreign();
    state.input = input;
    // Retain before the fallible current check. Reentrant close may deny this
    // handoff but cannot discard its same pending supplier/preparation duty.
    assertCurrent(scope, originals);
    return input;
  }
  function cleanupOriginal(handle:unknown):Cleanup {
    if (!reference(handle)) foreign();
    const status = own(handle, 'status'), retry = own(handle, 'retry');
    if (typeof status !== 'function' || typeof retry !== 'function') foreign();
    return {receiver: handle, status:status as CapturedMethod, retry:retry as CapturedMethod};
  }
  function retainPreparation(scope:unknown, record:unknown, handle:unknown):Duty {
    const state = stateFor(scope);
    assertCurrent(scope, state.originals);
    if (!reference(record)) foreign();
    let child = apply(mapGet, state.children, [record]) as Child|undefined;
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
      return child.duty!;
    }
    child = {record, handle, cleanup: undefined, acknowledged: handle === undefined,
      released: false, duty: undefined};
    child.duty = freeze({releaseReferences(originalRecord:unknown) {
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
    return child.duty!;
  }
  function close(scope:unknown):Promise<Observation> {
    const state = stateFor(scope);
    if (state.flight !== undefined) return state.flight;
    state.closing = true;
    if (state.closed) return Promise.resolve(observation(state));
    // Install one flight before invoking any original callback. A reentrant or
    // concurrent close observes that SAME Promise and cannot double-retry.
    const flight = Promise.resolve().then(async () => {
      // Snapshot original child references with the captured native Map walk;
      // a later application replacement cannot skip another child's duty.
      const children:Child[] = [];
      apply(mapEach, state.children, [(child:Child) => { children[children.length] = child; }]);
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
        const value = await apply(closeOperational!, operational, [state.originals]);
        if (!completed(value)) return observation(state);
      } catch (cause) {
        remember(state, cause);
        return observation(state);
      }
      state.closed = true;
      apply(mapEach, state.children, [(child:Child) => {
        child.record = undefined;
        child.handle = undefined;
        child.cleanup = undefined;
      }]);
      apply(mapClear, state.children, []);
      state.input = undefined;
      state.originals = undefined;
      return observation(state);
    }).finally(() => { if (state.flight === flight) state.flight = undefined; });
    state.flight = flight;
    return flight;
  }
  function issue(held:Snapshot):Scope {
    apply(assertOperational!, operational, [held]);
    const state:State = {originals: held, input: undefined, children: new NativeMap(), closing: false, closed: false,
      flight: undefined, firstError: undefined, lastError: undefined};
    const scope:Scope = freeze({assertCurrent(sameOriginals:unknown) { assertCurrent(scope, sameOriginals); },
      retainPreparation(record:unknown, cleanupHandle?:unknown) { return retainPreparation(scope, record, cleanupHandle); },
      status() { return observation(state); }, close() { return close(scope); }});
    apply(weakSet, scopes, [scope, state]);
    return scope;
  }
  function begin(originals:unknown, rawInput?:unknown):Scope|Promise<Scope> {
    if (assertOperational === undefined) unavailable();
    if (rawInput !== undefined && prepareOperational === undefined) {
      fail('NodeInitialControlInputUnavailable');
    }
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
    // This callback starts synchronously in the caller's original stack,
    // before any await. Do not enumerate, clone or inspect rawInput here. The
    // selected operational supplier must first cover raw acquisition/ownKeys,
    // preserve callback/opaque backing custody, then call its captured reader
    // and retain the same snapshot/partial cleanup before async initialization.
    const prepared = apply(prepareOperational, operational, [held, rawInput]);
    return apply(promiseThen, apply(promiseResolve, NativePromise, [prepared]),
      [() => issue(held)]) as Promise<Scope>;
  }
  return freeze({begin, assertCurrent, readAsset, readInput, requireOperational});
}

// Keep Node's named-export detection on the original CommonJS assignment.
const exported = module.exports = {createInitialControlInstallationOwner};
freeze(module.exports);
export = exported as Readonly<typeof exported>;
