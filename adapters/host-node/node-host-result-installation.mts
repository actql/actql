import {createRequire} from 'node:module';
import {prepareOrdinaryHostResult} from './ordinary-host-result.mjs';
import {readHostResultPublicationPreparation, readHostResultPublicationRunRequirements, readHostEffectResultPublicationRunRequirements} from './embedded-local.mjs';

import type {HostJournalOriginals} from './ordinary-host-journal.mjs';

type OrdinaryResult = ReturnType<typeof prepareOrdinaryHostResult>;
type StartupStatus = Readonly<{pending: boolean}>;
type StoreOptions = Parameters<OrdinaryResult['openStore']>[0];
type Store = Awaited<ReturnType<OrdinaryResult['openStore']>>;
type ResultOriginals = HostJournalOriginals & Readonly<{supplier: unknown; moduleLifetime: unknown}>;
type StartupState = {
  original: unknown; originals: ResultOriginals | undefined;
  closing: boolean; closed: boolean; flight: Promise<StartupStatus> | undefined;
};
type StartupCallbacks = readonly [
  (originals: ResultOriginals) => object | undefined,
  (original: unknown, originals: ResultOriginals | undefined) => undefined,
  (original: unknown, originals: ResultOriginals | undefined) => Promise<StartupStatus>,
  (original: unknown, originals: ResultOriginals | undefined, options: StoreOptions, control: object) => Promise<Store>,
  (original: unknown, originals: ResultOriginals | undefined, operation: string) => undefined,
  (original: unknown, originals: ResultOriginals | undefined, prepared: object) => undefined,
];
type StartupCallbackIndex = 0 | 1 | 2 | 3 | 4 | 5;

// Capture only the actual selected startup's fixed Result purpose. Neither
// this forwarding view nor an object's current method can issue that purpose.
const require = createRequire(import.meta.url);
const explicitStartup = process.execArgv.some(value =>
  value === '@actql/node/selected-infer-startup' || value === '@actql/local-node/selected-infer-startup');
const owner: object = explicitStartup ? require('./infer-trusted-node-preload.cjs') : Object.freeze({});
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const own = Object.hasOwn, freeze = Object.freeze, NativePromise = Promise;
const names = ['prepareHostResultPublicationInstallation', 'assertHostResultPublicationInstallationCurrent',
  'closeHostResultPublicationInstallation', 'openHostResultPublicationStore',
  'beforeHostResultPublicationOperation', 'admitHostResultPublicationRun'];
const callbacks = names.map((name): ((...args: never[]) => unknown) | undefined => {
  const property = descriptor(owner, name);
  return property !== undefined && own(property, 'value') && typeof property.value === 'function'
    ? property.value : undefined;
});
const unavailable: () => never = () => {throw Object.assign(new Error('HostResultPublicationUnavailable'),
  {code: 'HostResultPublicationUnavailable'});};
function invoke<Index extends StartupCallbackIndex>(index: Index,
  args: Parameters<StartupCallbacks[Index]>): ReturnType<StartupCallbacks[Index]> {
  if (callbacks[index] === undefined) unavailable();
  return apply(callbacks[index] as (...values: Parameters<StartupCallbacks[Index]>) =>
    ReturnType<StartupCallbacks[Index]>, owner, args);
}
function current(state: StartupState) {
  if (state.closing || state.closed || invoke(1, [state.original, state.originals]) !== undefined) unavailable();
}
function close(state: StartupState) {
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
export async function prepareHostResultPublicationInstallation(originals: ResultOriginals) {
  if (!explicitStartup) {
    const original = prepareOrdinaryHostResult(originals,
      readHostResultPublicationPreparation(originals), readHostResultPublicationRunRequirements,
      readHostEffectResultPublicationRunRequirements);
    await original.initialize();
    return original;
  }
  const original = await invoke(0, [originals]);
  if (original === undefined) unavailable();
  const state: StartupState = {original, originals, closing: false, closed: false, flight: undefined};
  try {current(state);}
  catch (cause) {
    const carrier: Error & {code: string; cleanupHandle?: {status(): StartupStatus; retry(): Promise<StartupStatus>}} =
      Object.assign(new Error('HostResultPublicationCleanupPending', {cause}),
      {code: 'HostResultPublicationCleanupPending'});
    carrier.cleanupHandle = freeze({status: () => freeze({pending: !state.closed}), retry: () => close(state)});
    throw carrier;
  }
  return freeze({assertCurrent() {current(state);}, close() {return close(state);},
    openStore(options: StoreOptions, control: object) {current(state); return invoke(3, [state.original, state.originals, options, control]);},
    beforeOperation(operation: string) {current(state); return invoke(4, [state.original, state.originals, operation]);},
    admitRun(prepared: object) {current(state); return invoke(5, [state.original, state.originals, prepared]);}});
}
