// Private view issued inside the existing trusted Host construction only.
// It binds the selected native/module responsibility; it is not a byte grant,
// proof of RSS, current authority, physical ACK or permission to send.
// The actual Host must cover this view/control allocation before issuance.
import startup from './infer-trusted-node-preload.cjs';
const fields = Object.freeze(['host', 'supplier', 'installation', 'generation',
  'runtime', 'moduleLifetime', 'transport', 'target']);
const constructorKey = Symbol('InferTrustedRuntimeViewConstructor');
const fail = code => {
  throw Object.assign(new TypeError(code), {code});
};
const nominal = value => value !== null &&
  (typeof value === 'object' || typeof value === 'function');

// Inspect and retain the same descriptor values, without invoking getters or
// deep-copying original handles. Reflection does not isolate hostile code.
function checkOriginalShape(value) {
  if (!nominal(value) || Array.isArray(value)) {
    fail('InferTrustedRuntimeOriginalUnavailable');
  }
  const names = Reflect.ownKeys(value);
  if (names.length !== fields.length) {
    fail('InferTrustedRuntimeOriginalUnavailable');
  }
  for (let index = 0; index < names.length; index++) {
    const name = names[index];
    if (typeof name !== 'string' || !fields.includes(name)) {
      fail('InferTrustedRuntimeOriginalUnavailable');
    }
  }
}

// Issue and recheck use this SAME one-read validation. No getter or second
// property read can replace the independently supplied original descriptor.
function originalValue(value, name) {
  const descriptor = Object.getOwnPropertyDescriptor(value, name);
  if (descriptor === undefined || descriptor.enumerable !== true ||
      !Object.hasOwn(descriptor, 'value')) {
    fail('InferTrustedRuntimeOriginalUnavailable');
  }
  const original = descriptor.value;
  if (name === 'target' ? typeof original !== 'string' || original.length === 0
    : !nominal(original)) {
    fail('InferTrustedRuntimeOriginalUnavailable');
  }
  return original;
}

function originals(value) {
  checkOriginalShape(value);
  const retained = {};
  for (const name of fields) retained[name] = originalValue(value, name);
  return Object.freeze(retained);
}

// Recheck does not retain another eight-field snapshot or callback/context.
// Still validate ALL descriptors before reporting Changed, preserving the
// original malformed-input priority and each value's one-read observation.
function checkOriginals(value, retained) {
  checkOriginalShape(value);
  let changed = false;
  for (let index = 0; index < fields.length; index++) {
    const name = fields[index];
    const original = originalValue(value, name);
    if (!changed && retained[name] !== original) changed = true;
  }
  if (changed) fail('InferTrustedRuntimeOriginalChanged');
}

class TrustedRuntimeView {
  #originals;

  constructor(key, bindings) {
    if (key !== constructorKey) fail('InferTrustedRuntimeViewUnavailable');
    this.#originals = bindings;
    Object.freeze(this);
  }

  static #binding(view) {
    if (!nominal(view) || !(#originals in view)) {
      fail('InferTrustedRuntimeViewUnavailable');
    }
    if (view.#originals === undefined) fail('InferTrustedRuntimeViewRetired');
    return view.#originals;
  }

  static check(view, actual) {
    const retained = TrustedRuntimeView.#binding(view);
    checkOriginals(actual, retained);
  }

  static forget(view, host, generation) {
    const retained = TrustedRuntimeView.#binding(view);
    if (retained.host !== host || retained.generation !== generation) {
      fail('InferTrustedRuntimeOriginalChanged');
    }
    // Drop back-references only. Native/module/process responsibility remains
    // with the actual Host supplier, even after the last Call/Host closes.
    view.#originals = undefined;
  }
}

// The owning installer supplies these independently from its actual originals,
// not from packet fields, matching CIDs, a caller flag or this view's contents.
// This module stays private: no SDK factory/plugin/wire issues runtime coverage.
export function issueInferTrustedRuntimeView(actualOriginals) {
  return new TrustedRuntimeView(constructorKey, originals(actualOriginals));
}

// Call only after the existing Host/Model owner checks current lifecycle, and
// again at its actual operation boundary after awaits. This predicate cannot
// substitute for those checks, original Ledger funding or the final send gate.
export function checkInferTrustedRuntimeView(view, actualOriginals) {
  TrustedRuntimeView.check(view, actualOriginals);
}

// Existing Host cleanup calls this only after its actual duties settle. There
// is deliberately no success Bool/callback, lease release, reopen or reset API.
// A failed/pending cleanup retains the same view and its original references.
export function forgetInferTrustedRuntimeView(view, actualHost, actualGeneration) {
  TrustedRuntimeView.forget(view, actualHost, actualGeneration);
}

// Associate the actual early startup original with this existing eight-ref
// view. A late embedded import returns None, never reconstructed coverage.
export function associateInferTrustedStartupView(view, actualOriginals) {
  TrustedRuntimeView.check(view, actualOriginals);
  return startup.associateHost(view, actualOriginals);
}

export function requireInferTrustedStartupView(view, actualOriginals) {
  TrustedRuntimeView.check(view, actualOriginals);
  startup.check(view, actualOriginals);
}

// Caller has checked the SAME actual Common scope before this association.
// No callback, caller Bool, CID or another startup can supply that original.
export function borrowInferTrustedStartupView(hostView, scopeView, hostOriginals, scopeOriginals) {
  requireInferTrustedStartupView(hostView, hostOriginals);
  TrustedRuntimeView.check(scopeView, scopeOriginals);
  if (hostOriginals.host !== scopeOriginals.host ||
      hostOriginals.generation !== scopeOriginals.generation ||
      hostOriginals.supplier !== scopeOriginals.supplier ||
      hostOriginals.runtime !== scopeOriginals.runtime) {
    fail('InferTrustedStartupChanged');
  }
  startup.borrowScope(hostView, scopeView, hostOriginals.host, hostOriginals.generation);
}

// Existing Host/Scope cleanup is the prerequisite. This cuts only this
// association, not the startup's actual process/native/module responsibility.
export function forgetInferTrustedStartupView(view, host, generation) {
  startup.retire(view, host, generation);
}
