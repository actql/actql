import {createRequire} from 'node:module';
import {beginOrdinaryHostControl, isOrdinaryHostControl, assertOrdinaryHostControlCurrent,
  ordinaryHostControlInput, readOrdinaryHostAsset} from './ordinary-host-control.mjs';

// The actual CJS startup may synchronously capture this ESM namespace before
// entry. Read its already-published original forwarders through that SAME CJS
// receiver; a static CJS import instead creates a forbidden require/ESM cycle.
// This is only the private consumer path, not a late operational issuer.
const require = createRequire(import.meta.url);
// Ordinary public delivery initializes its separate installed-prefix instance
// before the Host graph. The old preload path keeps its exact original table;
// this routing does not reinterpret a label or callback as an admission.
// The historical explicit startup remains a private diagnostic entrance.
// Ordinary initialization is legitimate after arbitrary trusted app imports,
// with normal options, multiple Hosts and later reopen in the same process.
const explicitStartup = process.execArgv.some(value =>
  value === '@actql/node/selected-infer-startup' || value === '@actql/local-node/selected-infer-startup');
const startup = explicitStartup ? require('./infer-trusted-node-preload.cjs') : Object.freeze({});

const ownDescriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, apply = Reflect.apply;
const NativeError = Error;

// Private consumer of the actual selected preload's operational issuer. This
// module is not an issuer: an eight-reference view, bounds, Ledger or caller
// packet cannot replace an absent startup capability. In particular, importing
// it after entry does not manufacture coverage of earlier imports/discovery.
const descriptor = ownDescriptor(startup,
  'beginInitialControlInstallation');
const begin = descriptor !== undefined && hasOwn(descriptor, 'value') &&
  typeof descriptor.value === 'function' ? descriptor.value : undefined;
const currentDescriptor = ownDescriptor(startup,
  'assertInitialControlInstallationCurrent');
const current = currentDescriptor !== undefined && hasOwn(currentDescriptor, 'value') &&
  typeof currentDescriptor.value === 'function' ? currentDescriptor.value : undefined;
const assetDescriptor = ownDescriptor(startup, 'readInitialControlInstallationAsset');
const readAsset = assetDescriptor !== undefined && hasOwn(assetDescriptor, 'value') &&
  typeof assetDescriptor.value === 'function' ? assetDescriptor.value : undefined;
const inputDescriptor = ownDescriptor(startup, 'readInitialControlInstallationInput');
const readInput = inputDescriptor !== undefined && hasOwn(inputDescriptor, 'value') &&
  typeof inputDescriptor.value === 'function' ? inputDescriptor.value : undefined;

// The actual startup must supply its nominal receiver, retaining the original
// same Host/installation/generation/source/backend/recipe and complete finite
// envelope before any covered work. No consumer-side fallback is permitted.
//
// The receiver contract is:
//   begin(originals, rawInput?) -> original scope, or Promise of that SAME nominal scope
//   assertCurrent(sameOriginals) -> void/throw
//   retainPreparation(originalRecord, originalCleanupHandle?) -> original duty
//   status() -> original pending observation
//   close() -> original pending observation, or its original Promise
// Retain before fallible work and retain the same duty through partial failure.
// The existing Host invokes close only after its real child cleanup; this port
// does not interpret close/settlement/reference retirement as physical ACK.
// There is no conversion to metadata HTTP, Source, Result, business Run, Model,
// Content/driver or VM capacity. An unavailable envelope stays unavailable.
// An asynchronous namespace initialization snapshots originals before awaiting;
// callers await begin and check fixed nominal current before covered work. Its
// original initialization failure/cleanupHandle is not replaced by this port.
export function beginInitialControlInstallation(originals, rawInput) {
  if (!explicitStartup) return beginOrdinaryHostControl(originals, rawInput);
  if (begin === undefined) {
    const error = new NativeError('NodeInitialControlAdmissionUnavailable');
    error.code = 'NodeInitialControlAdmissionUnavailable';
    throw error;
  }
  return apply(begin, startup, [originals, rawInput]);
}

// Membership is checked in the SAME private preload instance. In particular,
// calling a caller-supplied scope.assertCurrent() cannot authenticate a scope.
export function assertInitialControlInstallationCurrent(scope, sameOriginals) {
  if (isOrdinaryHostControl(scope)) return assertOrdinaryHostControlCurrent(scope, sameOriginals);
  if (current === undefined) {
    const error = new NativeError('NodeInitialControlAdmissionUnavailable');
    error.code = 'NodeInitialControlAdmissionUnavailable';
    throw error;
  }
  return apply(current, startup, [scope, sameOriginals]);
}

// The package-relative key selects only a fixed image already held by the
// actual preload. No caller file/data/receiver is admitted or reread here.
// Escaped original Strings retain their own original envelope/lifetime.
export function readInitialControlInstallationAsset(scope, sameOriginals, path) {
  if (isOrdinaryHostControl(scope)) return readOrdinaryHostAsset(scope, sameOriginals, path);
  if (readAsset === undefined) {
    const error = new NativeError('NodeInitialControlAdmissionUnavailable');
    error.code = 'NodeInitialControlAdmissionUnavailable';
    throw error;
  }
  return apply(readAsset, startup, [scope, sameOriginals, path]);
}

// Original finite snapshot projection only, after synchronous original intake
// and nominal begin. No enumeration, copy, caller callback or replacement
// producer occurs here. Coverage must precede the raw packet's first ownKeys;
// this port and a returned object cannot retroactively supply it.
export function readInitialControlInstallationInput(scope, sameOriginals) {
  if (isOrdinaryHostControl(scope)) return ordinaryHostControlInput(scope, sameOriginals);
  if (readInput === undefined) {
    const error = new NativeError('NodeInitialControlAdmissionUnavailable');
    error.code = 'NodeInitialControlAdmissionUnavailable';
    throw error;
  }
  return apply(readInput, startup, [scope, sameOriginals]);
}
