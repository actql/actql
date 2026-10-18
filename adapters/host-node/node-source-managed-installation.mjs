import {createRequire} from 'node:module';
import {types} from 'node:util';

// The preload may synchronously initialize this ESM namespace. Its already
// published CJS receiver avoids a static CJS/ESM initialization cycle.
const originalOwner = createRequire(import.meta.url)('./infer-trusted-node-preload.cjs');

// Fixed private startup receiver only. A shape, callback supplied by a Client,
// scalar quota or initial-control scope cannot create a Source installation.
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, freeze = Object.freeze, isPromise = types.isPromise;
const NativeError = Error, NativeWeakMap = WeakMap;
const get = WeakMap.prototype.get, set = WeakMap.prototype.set;
const installations = new NativeWeakMap();
const names = freeze(['prepareSourceManagedInstallation', 'assertSourceManagedInstallationCurrent',
  'beforeSourceSnapshot', 'bindSourceSnapshot', 'bindSourceRequest',
  'finishSourceProducer', 'closeSourceManagedInstallation']);
const callbacks = names.map(name => {
  const d = descriptor(originalOwner, name);
  return d !== undefined && hasOwn(d, 'value') && typeof d.value === 'function' ? d.value : undefined;
});
const unavailable = () => {throw Object.assign(new NativeError('SourceManagedPreparationUnavailable'),
  {code: 'SourceManagedPreparationUnavailable'});};
function invoke(index, args) {
  const callback = callbacks[index];
  if (callback === undefined) unavailable();
  return apply(callback, originalOwner, args);
}
function original(view, originals) {
  const state = apply(get, installations, [view]);
  if (state === undefined || state.closed || state.originals !== originals) unavailable();
  return state;
}
function current(state) {
  if (state.closed) unavailable();
  if (state.failure !== undefined) throw state.failure;
  // Fixed actual Owner checks nominal installation, shared runtime/domain,
  // Host/generation and currentness; the view's own fields are not evidence.
  if (invoke(1, [state.installation, state.originals]) !== undefined) unavailable();
}
async function close(state) {
  if (state.closed) return freeze({pending: false});
  if (state.flight !== undefined) return state.flight;
  const flight = (async () => {
    const observation = await invoke(6, [state.installation, state.originals]);
    const d = observation !== null && typeof observation === 'object'
      ? descriptor(observation, 'pending') : undefined;
    if (d !== undefined && hasOwn(d, 'value') && d.value === false) {
      state.closed = true; state.installation = undefined; state.originals = undefined;
    }
    return observation;
  })();
  state.flight = flight;
  try { return await flight; }
  finally { if (state.flight === flight) state.flight = undefined; }
}
function syncVoid(state, index, args) {
  current(state);
  const result = invoke(index, [state.installation, state.originals, ...args]);
  if (result !== undefined) {
    // Retain the unexpected observation, including a live Promise, rather than
    // awaiting it and moving the original synchronous snapshot boundary.
    state.failure = Object.assign(new NativeError('SourceManagedSynchronousProtocolChanged', {cause: result}),
      {code: 'SourceManagedSynchronousProtocolChanged'});
    throw state.failure;
  }
}

export async function prepareSourceManagedInstallation(originals) {
  // This connect-time initialization may await. None of the four submission
  // operations below may await before the SDK's original snapshot/clone.
  const installation = await invoke(0, [originals]);
  if (installation === undefined) unavailable();
  const state = {installation, originals, closed: false, failure: undefined, flight: undefined};
  try { current(state); }
  catch (cause) {
    // Initialization acquired an original before its final current fence.
    // Forward the SAME original close, retaining partial custody on refusal;
    // neither rejection nor a failed current check acknowledges that child.
    const carrier = new NativeError('SourceManagedInstallationCleanupPending', {cause});
    carrier.code = 'SourceManagedInstallationCleanupPending';
    carrier.cleanupHandle = freeze({status: () => freeze({pending: !state.closed}),
      retry: () => close(state)});
    throw carrier;
  }
  const view = freeze({
    beforeSourceSnapshot(kind, input, options) {
      current(state);
      const receipt = invoke(2, [state.installation, state.originals, kind, input, options]);
      if (receipt === null || (typeof receipt !== 'object' && typeof receipt !== 'function') || isPromise(receipt)) {
        state.failure = Object.assign(new NativeError('SourceManagedSynchronousProtocolChanged', {cause: receipt}),
          {code: 'SourceManagedSynchronousProtocolChanged'});
        throw state.failure;
      }
      // This wrapper does not admit a receipt by shape. Each later operation
      // rechecks that exact receipt in the original private Root's inventory.
      return receipt;
    },
    bindSourceSnapshot(receipt, body) {syncVoid(state, 3, [receipt, body]);},
    bindSourceRequest(receipt, body, request) {syncVoid(state, 4, [receipt, body, request]);},
    finishSourceProducer(receipt, terminal) {
      // Producer retirement may follow lost currentness. Only the original
      // Owner can cut this producer's aliases; this is no child/physical ACK.
      const result = invoke(5, [state.installation, state.originals, receipt, terminal]);
      if (result !== undefined) unavailable();
    },
    assertCurrent() {current(state);},
    // A single original close flight. Cutting these aliases cannot return
    // shared VM byte credit; failure observations retain their real lifetime.
    close() {return close(state);},
  });
  apply(set, installations, [view, state]);
  return view;
}

export function assertSourceManagedInstallationCurrent(view, sameOriginals) {
  current(original(view, sameOriginals));
}
