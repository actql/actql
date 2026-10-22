import {createRequire} from 'node:module';
import {prepareOrdinaryHostResult} from './ordinary-host-result.mjs';
import {readHostResultPublicationPreparation, readHostResultPublicationRunRequirements,
  readHostEffectResultPublicationRunRequirements}
  from './embedded-local.mjs';

// Capture only the actual selected startup's fixed Result purpose. Neither
// this forwarding view nor an object's current method can issue that purpose.
const require = createRequire(import.meta.url);
const explicitStartup = process.execArgv.some(value =>
  value === '@actql/node/selected-infer-startup' || value === '@actql/local-node/selected-infer-startup');
const owner = explicitStartup ? require('./infer-trusted-node-preload.cjs') : Object.freeze({});
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const own = Object.hasOwn, freeze = Object.freeze, NativePromise = Promise;
const names = ['prepareHostResultPublicationInstallation', 'assertHostResultPublicationInstallationCurrent',
  'closeHostResultPublicationInstallation', 'openHostResultPublicationStore',
  'beforeHostResultPublicationOperation', 'admitHostResultPublicationRun'];
const callbacks = names.map(name => {
  const property = descriptor(owner, name);
  return property !== undefined && own(property, 'value') && typeof property.value === 'function'
    ? property.value : undefined;
});
const unavailable = () => {throw Object.assign(new Error('HostResultPublicationUnavailable'),
  {code: 'HostResultPublicationUnavailable'});};
function invoke(index, args) {
  if (callbacks[index] === undefined) unavailable();
  return apply(callbacks[index], owner, args);
}
function current(state) {
  if (state.closing || state.closed || invoke(1, [state.original, state.originals]) !== undefined) unavailable();
}
function close(state) {
  if (state.closed) return NativePromise.resolve(freeze({pending: false}));
  if (state.flight !== undefined) return state.flight;
  state.closing = true;
  const flight = NativePromise.resolve().then(async () => {
    const observation = await invoke(2, [state.original, state.originals]);
    const pending = observation !== null && typeof observation === 'object' ? descriptor(observation, 'pending') : undefined;
    if (pending !== undefined && own(pending, 'value') && pending.value === false) {
      state.closed = true;
      state.original = state.originals = undefined;
    }
    return observation;
  });
  state.flight = flight;
  const settled = () => {if (state.flight === flight) state.flight = undefined;};
  flight.then(settled, settled);
  return flight;
}
export async function prepareHostResultPublicationInstallation(originals) {
  if (!explicitStartup) {
    const original = prepareOrdinaryHostResult(originals,
      readHostResultPublicationPreparation(originals), readHostResultPublicationRunRequirements,
      readHostEffectResultPublicationRunRequirements);
    await original.initialize();
    return original;
  }
  const original = await invoke(0, [originals]);
  if (original === undefined) unavailable();
  const state = {original, originals, closing: false, closed: false, flight: undefined};
  try {current(state);}
  catch (cause) {
    const carrier = Object.assign(new Error('HostResultPublicationCleanupPending', {cause}),
      {code: 'HostResultPublicationCleanupPending'});
    carrier.cleanupHandle = freeze({status: () => freeze({pending: !state.closed}), retry: () => close(state)});
    throw carrier;
  }
  return freeze({assertCurrent() {current(state);}, close() {return close(state);},
    openStore(options, control) {current(state); return invoke(3, [state.original, state.originals, options, control]);},
    beforeOperation(operation) {current(state); return invoke(4, [state.original, state.originals, operation]);},
    admitRun(prepared) {current(state); return invoke(5, [state.original, state.originals, prepared]);}});
}
