import {createRequire} from 'node:module';
import {prepareOrdinaryHostJournal} from './ordinary-host-journal.mjs';

// Capture the same already-selected startup receiver while its namespace
// loads. A late import, preload label or caller constructor cannot issue the
// separate writable Host/Journal facility. No initial/Source credit is used.
const require = createRequire(import.meta.url);
const explicitStartup = process.execArgv.some(value =>
  value === '@actql/node/selected-infer-startup' || value === '@actql/local-node/selected-infer-startup');
const owner = explicitStartup ? require('./infer-trusted-node-preload.cjs') : Object.freeze({});
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const own = Object.hasOwn, freeze = Object.freeze, NativePromise = Promise;
const names = ['prepareHostJournalInstallation', 'assertHostJournalInstallationCurrent',
  'closeHostJournalInstallation', 'openHostJournalRequestJournal', 'originalHostPublicationOwnership',
  'admitHostJournalRootFormat'];
const callbacks = names.map(name => {
  const property = descriptor(owner, name);
  return property !== undefined && own(property, 'value') &&
    typeof property.value === 'function' ? property.value : undefined;
});
const unavailable = () => {
  throw Object.assign(new Error('HostJournalPreparationUnavailable'),
    {code: 'HostJournalPreparationUnavailable'});
};
function invoke(index, args) {
  if (callbacks[index] === undefined) unavailable();
  return apply(callbacks[index], owner, args);
}
function current(state) {
  if (state.closed || state.closing) unavailable();
  // Only the captured actual Owner can authenticate the nominal original and
  // same startup/runtime/Host/installation/generation/source recipe. No method
  // on a caller-provided object is used as that authentication.
  if (invoke(1, [state.original, state.originals]) !== undefined) unavailable();
}
function close(state) {
  if (state.closed) return NativePromise.resolve(freeze({pending: false}));
  if (state.flight !== undefined) return state.flight;
  state.closing = true;
  // Publish the original close flight before invoking the fixed receiver, so
  // synchronous reentry observes it rather than starting another mutation.
  const flight = NativePromise.resolve().then(async () => {
    const observation = await invoke(2, [state.original, state.originals]);
    const pending = observation !== null && typeof observation === 'object'
      ? descriptor(observation, 'pending') : undefined;
    if (pending !== undefined && own(pending, 'value') && pending.value === false) {
      state.closed = true;
      state.original = undefined;
      state.originals = undefined;
    }
    return observation;
  });
  state.flight = flight;
  const settled = () => { if (state.flight === flight) state.flight = undefined; };
  flight.then(settled, settled);
  return flight;
}

export async function prepareHostJournalInstallation(sameOriginals) {
  if (!explicitStartup) return prepareOrdinaryHostJournal(sameOriginals);
  // Root retains any partially acquired original and forwards its own error /
  // cleanupHandle if this await fails. Never retry by issuing a replacement.
  const original = await invoke(0, [sameOriginals]);
  if (original === undefined) unavailable();
  const state = {original, originals: sameOriginals,
    closed: false, closing: false, flight: undefined};
  try { current(state); }
  catch (cause) {
    // Preparation acquired an original before the final fixed current fence.
    // Keep that SAME original reachable to the existing Host failure owner.
    const carrier = Object.assign(new Error('HostJournalPreparationCleanupPending', {cause}),
      {code: 'HostJournalPreparationCleanupPending'});
    carrier.cleanupHandle = freeze({status: () => freeze({pending: !state.closed}),
      retry: () => close(state)});
    throw carrier;
  }
  return freeze({assertCurrent() { current(state); }, close() { return close(state); },
    admitRootFormat(root) {
      current(state);
      return invoke(5, [state.original, state.originals, root]);
    },
    publicationOwnership() {
      current(state);
      return invoke(4, [state.original, state.originals]);
    },
    openRequestJournal(directory, options) {
      current(state);
      // The captured Root constructs and retains its SAME physical Journal
      // before any post-constructor current check. Only it can select the
      // native facility/limits or carry a partially opened child on failure.
      // This adapter neither enumerates caller options nor issues admission.
      return invoke(3, [state.original, state.originals, directory, options]);
    }});
}
