import startup from './infer-trusted-node-preload.cjs';

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

// The actual startup must supply its nominal receiver, retaining the original
// same Host/installation/generation/source/backend/recipe and complete finite
// envelope before any covered work. No consumer-side fallback is permitted.
//
// The receiver contract is:
//   begin(originals) -> original scope, or Promise of that SAME nominal scope
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
export function beginInitialControlInstallation(originals) {
  if (begin === undefined) {
    const error = new NativeError('NodeInitialControlAdmissionUnavailable');
    error.code = 'NodeInitialControlAdmissionUnavailable';
    throw error;
  }
  return apply(begin, startup, [originals]);
}

// Membership is checked in the SAME private preload instance. In particular,
// calling a caller-supplied scope.assertCurrent() cannot authenticate a scope.
export function assertInitialControlInstallationCurrent(scope, sameOriginals) {
  if (current === undefined) {
    const error = new NativeError('NodeInitialControlAdmissionUnavailable');
    error.code = 'NodeInitialControlAdmissionUnavailable';
    throw error;
  }
  return apply(current, startup, [scope, sameOriginals]);
}
