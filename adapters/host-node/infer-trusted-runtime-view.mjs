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

// Private DATA from the actual opened Store, not a caller's size declaration.
// Preserve the issuer's one immutable record rather than copying its Strings
// or repeatedly allocating a new projection at every current/Scope check.
function originalStoreDimensions(store) {
  const method = Object.getOwnPropertyDescriptor(store, 'originalModelStorageDimensions');
  // Legacy/private Store associations remain usable without these observations.
  // Their absent dimensions are Unavailable, never zero or inferred from caps.
  if (method === undefined) return undefined;
  if (!Object.hasOwn(method, 'value') || typeof method.value !== 'function') {
    fail('InferTrustedStoreDimensionsUnavailable');
  }
  const value = Reflect.apply(method.value, store, []);
  const fields = ['directoryCodeUnits', 'directoryUtf8Bytes',
    'privateNamespaceCodeUnits', 'privateNamespaceUtf8Bytes', 'privateKeyBytes'];
  if (!nominal(value) || Array.isArray(value) || !Object.isFrozen(value)) {
    fail('InferTrustedStoreDimensionsUnavailable');
  }
  const names = Reflect.ownKeys(value);
  if (names.length !== fields.length || names.some(name => !fields.includes(name))) {
    fail('InferTrustedStoreDimensionsUnavailable');
  }
  for (const name of fields) {
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    if (descriptor === undefined || descriptor.enumerable !== true ||
        !Object.hasOwn(descriptor, 'value') ||
        !Number.isSafeInteger(descriptor.value) || descriptor.value <= 0) {
      fail('InferTrustedStoreDimensionsUnavailable');
    }
  }
  return value;
}

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
  // Present only on the original Host view, not another Store/cleanup Owner.
  // The field itself also exists on Scope views and needs managed coverage.
  #store;

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

  static bindStore(view, actual, store, moduleLifetime) {
    TrustedRuntimeView.check(view, actual);
    if (!nominal(store) || !nominal(moduleLifetime)) {
      fail('InferTrustedStoreUnavailable');
    }
    if (view.#store !== undefined) fail('InferTrustedStoreAlreadyBound');
    view.#store = Object.freeze({store, moduleLifetime});
  }

  static checkStore(view, actual, store, moduleLifetime) {
    TrustedRuntimeView.check(view, actual);
    if (view.#store === undefined) fail('InferTrustedStoreUnavailable');
    if (view.#store.store !== store || view.#store.moduleLifetime !== moduleLifetime) {
      fail('InferTrustedStoreChanged');
    }
  }

  static storeDimensions(view, actual, store, moduleLifetime) {
    TrustedRuntimeView.checkStore(view, actual, store, moduleLifetime);
    if (Object.hasOwn(view.#store, 'dimensions')) return view.#store.dimensions;
    // Acquire only for this new observation role. Ordinary Store association
    // does not require a Model private key or create a projected size record.
    const value = originalStoreDimensions(store);
    if (value === undefined) fail('InferTrustedStoreDimensionsUnavailable');
    // A physical method must not replace/retire this Host during observation.
    TrustedRuntimeView.checkStore(view, actual, store, moduleLifetime);
    view.#store = Object.freeze({store, moduleLifetime, dimensions: value});
    return value;
  }

  static forget(view, host, generation) {
    const retained = TrustedRuntimeView.#binding(view);
    if (retained.host !== host || retained.generation !== generation) {
      fail('InferTrustedRuntimeOriginalChanged');
    }
    // Drop back-references only. Native/module/process responsibility remains
    // with the actual Host supplier, even after the last Call/Host closes.
    view.#store = undefined;
    view.#originals = undefined;
  }
}

// The owning installer supplies these independently from its actual originals,
// not from packet fields, matching CIDs, a caller flag or this view's contents.
// This module stays private: no SDK factory/plugin/wire issues runtime coverage.
// The selected startup's TLS responsibility includes the adapter's own peer
// graph, hostname-verification scratch and original TLS error referents, bound
// to these SAME actual Host/supplier/installation/generation/runtime originals.
// This is not HTTP-clamp coverage or an exemption for ActQL/SDK allocations.
// Operation currentness, concurrency, physical close and the last actual
// borrower remain the existing caller/cleanup Owner's obligations; this view
// does not observe or acknowledge them, including when its links are retired.
export function issueInferTrustedRuntimeView(actualOriginals) {
  return new TrustedRuntimeView(constructorKey, originals(actualOriginals));
}

// Call only after the existing Host/Model owner checks current lifecycle, and
// again at its actual operation boundary after awaits. This predicate cannot
// substitute for those checks, original Ledger funding or the final send gate.
export function checkInferTrustedRuntimeView(view, actualOriginals) {
  TrustedRuntimeView.check(view, actualOriginals);
}

// The existing installed Host supplies the actual opened Store and its static
// module namespace. Neither a packet nor this reference check authenticates a
// Store, funds managed allocations, issues a numeric profile or confirms close.
// AES-GCM and FD/Dir native lifetime remains the selected Host responsibility.
export function bindInferTrustedStore(view, actualOriginals, store, moduleLifetime) {
  TrustedRuntimeView.bindStore(view, actualOriginals, store, moduleLifetime);
}

// Existing Model currentness checks use this exact Store association. A failed
// Store close retains the same association; only final Host cleanup forgets it.
export function checkInferTrustedStore(view, actualOriginals, store, moduleLifetime) {
  TrustedRuntimeView.checkStore(view, actualOriginals, store, moduleLifetime);
}

// The same Host selection borrows these immutable size observations. Neither
// the record nor a matching copy authenticates a Store, observes availability,
// funds paths/encodings/managed controls or grants read/restore/send. The owning
// caller still performs its actual Store/Scope current checks at every use.
export function selectedInferTrustedStoreDimensions(view, actualOriginals, store, moduleLifetime) {
  return TrustedRuntimeView.storeDimensions(view, actualOriginals, store, moduleLifetime);
}

// Existing Host cleanup calls this only after its actual duties settle. There
// is deliberately no success Bool/callback, lease release, reopen or reset API.
// A failed/pending cleanup retains the same view and its original references.
export function forgetInferTrustedRuntimeView(view, actualHost, actualGeneration) {
  TrustedRuntimeView.forget(view, actualHost, actualGeneration);
}

// Associate the actual early startup original with this existing eight-ref
// view. A late embedded import returns None, never reconstructed coverage.
// Its exact runtime duty includes only V8 internal backing of that startup's
// associations/generations indices, through module/escaped-handle lifetime.
// ActQL records/references/controls and workspace still need managed funding;
// this is neither fixed SDK classification nor numerical/physical-close ACK.
export function associateInferTrustedStartupView(view, actualOriginals) {
  TrustedRuntimeView.check(view, actualOriginals);
  return startup.associateHost(view, actualOriginals);
}

export function requireInferTrustedStartupView(view, actualOriginals) {
  TrustedRuntimeView.check(view, actualOriginals);
  startup.check(view, actualOriginals);
}

// Separate, explicitly selected SDK static-module duty, NOT a native/TLS kind.
// Only the same installed Host builder's immutable actual module originals may
// be attached. The existing startup owns their process/module lifetime; Scope
// views borrow the existing original record without another private field.
// Per-M factories, lazy/cache state, inputs, Promises and copies are excluded.
// All added binding/borrow controls still need their original managed budget.
export function bindInferTrustedSdkStaticModules(view, actualOriginals, modules) {
  requireInferTrustedStartupView(view, actualOriginals);
  startup.bindSdkStaticModules(view, actualOriginals, modules);
}

export function checkInferTrustedSdkStaticModules(view, actualOriginals, modules) {
  requireInferTrustedStartupView(view, actualOriginals);
  startup.checkSdkStaticModules(view, actualOriginals, modules);
}

// Additional private responsibility of the distinct exact early eager recipe.
// Requires the existing same-module binding, not a caller flag or new Owner.
// Covers only fixed input-independent compilation storage actually produced at
// that startup; lazy/per-call/feedback/cache/optimizer/hook state stays managed
// or unavailable. The selector field and checks also need bootstrap coverage.
export function checkInferTrustedSdkEagerModules(view, actualOriginals, modules) {
  requireInferTrustedStartupView(view, actualOriginals);
  startup.checkSdkEagerModules(view, actualOriginals, modules);
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
