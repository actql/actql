'use strict';

// Private selected startup, not an application-time trust factory. Node runs
// this exact module in its real --require preload phase BEFORE entry imports.
// Ordinary embedded processes importing it later retain no startup original.
const {Buffer} = require('node:buffer');
const {Readable} = require('node:stream');
const {createRequire} = require('node:module');
const {dirname, join} = require('node:path');
const originalProcess = require('node:process');
// Selected runtime implementation duty: ONLY the V8 internal backing of these
// two identity indices stays with this actual startup/module and escaped-handle
// lifetime. It is not fixed SDK storage or a numerical lease. Entry records,
// keys/value references, borrow controls, closures and check workspace remain
// managed Host/bootstrap/Run obligations. Weak/delete/GC is not a close ACK or
// evidence of table shrink; no other growing cache inherits this scope.
const associations = new WeakMap();
const generations = new WeakSet();
const sdkFields = Object.freeze(['openai', 'providerUtils', 'createOpenAI']);
let originalSupplier;

const unavailable = () => {
  throw Object.assign(new TypeError('InferTrustedStartupUnavailable'),
    {code: 'InferTrustedStartupUnavailable'});
};
const changed = () => {
  throw Object.assign(new TypeError('InferTrustedStartupChanged'),
    {code: 'InferTrustedStartupChanged'});
};

// Distinct exact early recipes, not flags inspected later by a caller. The
// original two-argument recipe keeps its original static-module meaning.
// Only this preload's actual early eager recipe may extend that duty to fixed
// input-independent bytecode/constant/source-position storage generated here.
const eagerSdkStartup = module.isPreloading === true &&
  originalProcess.execArgv.length === 3 &&
  originalProcess.execArgv[0] === '--no-lazy' &&
  originalProcess.execArgv[1] === '--require' &&
  originalProcess.execArgv[2] === __filename;
// Loader provenance, not current poolSize/version alone. Reject other prior
// preload/import/loader selections, including merely equivalent flag orders.
const selected = module.isPreloading === true &&
  (eagerSdkStartup || originalProcess.execArgv.length === 2 &&
  originalProcess.execArgv[0] === '--require' &&
  originalProcess.execArgv[1] === __filename) &&
  originalProcess.env.NODE_OPTIONS === undefined &&
  originalProcess.version === 'v22.22.0' &&
  originalProcess.platform === 'darwin' && originalProcess.arch === 'arm64' &&
  originalProcess.versions.openssl === '3.5.4';

let startup;
if (selected) {
  // Stock subclass initialization must precede the base-method fence. In the
  // selected Node source, net installs Socket.prototype.read by assignment;
  // freezing the inherited Readable method first prevents Node's own setup.
  // These are fixed builtin imports only, not user preload/code or network IO.
  const {Socket} = require('node:net');
  require('node:http');
  require('node:https');
  const tls = require('node:tls');
  const {TextDecoder} = require('node:util');
  const promise = globalThis.Promise;
  // Resolve Node's lazy global before inspecting its data descriptor. Both
  // module-cached Core decoders and per-read metadata decoders must use this
  // same original constructor, not a later application replacement.
  if (globalThis.TextDecoder !== TextDecoder) unavailable();
  // This opt-in physical startup keeps the selected allocator/pool premise
  // invariant, rather than trying to infer historical slabs at Host.open().
  // It is not a language restriction or a default for existing processes.
  const originals = [
    [Buffer, 'poolSize'], [Buffer, 'alloc'], [Buffer, 'allocUnsafe'], [Buffer, 'allocUnsafeSlow'],
    [Buffer, 'from'], [Buffer, 'concat'],
    [Readable.prototype, 'read'], [Readable.prototype, 'push'],
    [Readable.prototype, 'unshift'], [Socket.prototype, 'read'],
    [globalThis, 'TextDecoder'], [TextDecoder.prototype, 'decode'],
    [Buffer.prototype, 'subarray'],
    // Preserve the native chain whose concrete Promise/await allocations the
    // selected supplier inventories. Freezing these originals is not a byte
    // grant, a hook/debug bound or an exemption for application callbacks.
    [globalThis, 'Promise'], [promise, 'resolve'], [promise, 'reject'],
    [promise.prototype, 'then'], [promise.prototype, 'catch'],
    [promise.prototype, 'finally'], [promise.prototype, 'constructor'],
    // The selected TLS implementation owns its own peer-certificate graph,
    // hostname-verification scratch and original TLS error referents. Keep
    // the actual adapter functions, not a later application replacement.
    // HTTP header/body clamps do not cover these pre-HTTP allocations.
    [tls, 'connect'], [tls, 'checkServerIdentity'],
    [tls.TLSSocket.prototype, 'getPeerCertificate'],
  ].map(([owner, name]) => {
    const descriptor = Object.getOwnPropertyDescriptor(owner, name);
    if (descriptor === undefined || !Object.hasOwn(descriptor, 'value')) unavailable();
    if (name === 'poolSize' ? descriptor.value !== 8192 : typeof descriptor.value !== 'function') {
      unavailable();
    }
    return {owner, name, value: descriptor.value};
  });
  for (const {owner, name, value} of originals) {
    Object.defineProperty(owner, name, {value, writable: false, configurable: false});
  }
  // Species is an accessor, not another data-valued method. Keep the SAME
  // getter without invoking it or replacing it with a function-valued field.
  const species = Object.getOwnPropertyDescriptor(promise, Symbol.species);
  if (species === undefined || typeof species.get !== 'function' ||
      species.set !== undefined || Object.hasOwn(species, 'value')) unavailable();
  const promiseSpecies = Object.freeze({owner: promise, get: species.get});
  Object.defineProperty(promise, Symbol.species, {
    get: species.get, set: undefined, configurable: false,
  });
  let sdkStaticModules;
  // Resolve the OPTIONAL selected package from this actual consumer entry,
  // including normal external installations, never a monorepo source path.
  // No installed SDK means no SDK coverage, not a dependency for Pure Hosts.
  const consumerRequire = createRequire(originalProcess.argv[1]);
  let sdkEntry;
  try { sdkEntry = consumerRequire.resolve('@actql/provider-ai-sdk'); }
  catch (error) { if (error.code !== 'MODULE_NOT_FOUND') unavailable(); }
  if (sdkEntry !== undefined) {
    // A before/after absence check alone misses entry code that sets a value,
    // dynamically imports the SDK and restores absence. Synchronous require
    // of this selected ESM graph completes BEFORE entry code can run. Its
    // default createOpenAI therefore sees this independently checked absence.
    // Do not read/log the value or mutate the operator's environment. Explicit
    // per-call assembler bounds cannot cover an earlier module-default read.
    if (Object.hasOwn(originalProcess.env, 'OPENAI_BASE_URL')) unavailable();
    try {
      consumerRequire(sdkEntry);
      sdkStaticModules = sdkOriginals(consumerRequire(
        join(dirname(sdkEntry), '_internal', 'openai-chat.mjs')).openAIChatStaticOriginals);
    } catch { unavailable(); }
  }
  // The actual process/module/native responsibility stays with this startup.
  // These originals and the existing Host overlap still need funded coverage.
  // In particular the three added descriptor records/array entries/references
  // are managed startup controls, not part of the TLS adapter trust exemption.
  // ActQL aliases, Promises, closures, copied diagnostics and exported peer or
  // error data also remain on the original Ledger. Native trust is neither a
  // zero-byte claim nor a lease. The same socket operation and last borrower
  // retain their original responsibility until actual cleanup, not destroy(),
  // rejection, Promise settlement or retirement of this association.
  startup = {process: originalProcess, module, entry: originalProcess.argv[1], originals,
    promiseSpecies, sdkStaticModules, eagerSdkStartup, invalidated: false};
}

function currentStartup() {
  if (startup === undefined) unavailable();
  if (startup.invalidated) changed();
  if (startup.process !== originalProcess || startup.entry !== originalProcess.argv[1] ||
      globalThis.Buffer !== Buffer) {
    startup.invalidated = true;
    changed();
  }
  for (const {owner, name, value} of startup.originals) {
    const descriptor = Object.getOwnPropertyDescriptor(owner, name);
    if (descriptor === undefined || descriptor.value !== value ||
        descriptor.writable !== false || descriptor.configurable !== false) {
      startup.invalidated = true;
      changed();
    }
  }
  const species = Object.getOwnPropertyDescriptor(startup.promiseSpecies.owner, Symbol.species);
  if (species === undefined || species.get !== startup.promiseSpecies.get ||
      species.set !== undefined || species.configurable !== false ||
      Object.hasOwn(species, 'value')) {
    startup.invalidated = true;
    changed();
  }
}

function current(view, host, generation) {
  currentStartup();
  const held = associations.get(view);
  if (held === undefined || held.retired || held.host !== host ||
      held.generation !== generation || held.original.retired) unavailable();
}

function sdkUnavailable() {
  throw Object.assign(new TypeError('InferTrustedSdkStaticUnavailable'),
    {code: 'InferTrustedSdkStaticUnavailable'});
}
function sdkValue(value, field) {
  const descriptor = Object.getOwnPropertyDescriptor(value, field);
  if (descriptor === undefined || descriptor.enumerable !== true ||
      !Object.hasOwn(descriptor, 'value') || descriptor.writable !== false ||
      descriptor.configurable !== false) sdkUnavailable();
  return descriptor.value;
}
function moduleNamespace(value) {
  if (value === null || typeof value !== 'object' ||
      Object.getPrototypeOf(value) !== null || Object.isExtensible(value)) sdkUnavailable();
  const tag = Object.getOwnPropertyDescriptor(value, Symbol.toStringTag);
  if (tag === undefined || !Object.hasOwn(tag, 'value') || tag.value !== 'Module' ||
      tag.writable !== false || tag.configurable !== false) sdkUnavailable();
}
function sdkOriginals(value, retained) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      !Object.isFrozen(value)) sdkUnavailable();
  const keys = Reflect.ownKeys(value);
  if (keys.length !== sdkFields.length || keys.some(key => !sdkFields.includes(key))) {
    sdkUnavailable();
  }
  const openai = sdkValue(value, 'openai'), providerUtils = sdkValue(value, 'providerUtils');
  const createOpenAI = sdkValue(value, 'createOpenAI');
  moduleNamespace(openai);
  moduleNamespace(providerUtils);
  const factory = Object.getOwnPropertyDescriptor(openai, 'createOpenAI');
  if (typeof createOpenAI !== 'function' || factory === undefined ||
      !Object.hasOwn(factory, 'value') || factory.value !== createOpenAI) sdkUnavailable();
  if (retained !== undefined) {
    if (retained.openai !== openai || retained.providerUtils !== providerUtils ||
        retained.createOpenAI !== createOpenAI) {
      throw Object.assign(new TypeError('InferTrustedSdkStaticChanged'),
        {code: 'InferTrustedSdkStaticChanged'});
    }
    return retained;
  }
  return Object.freeze({openai, providerUtils, createOpenAI});
}

function checkSdkModules(view, originals, modules) {
  current(view, originals.host, originals.generation);
  const retained = associations.get(view).original.sdkStaticModules;
  if (retained === undefined || retained !== startup.sdkStaticModules) sdkUnavailable();
  sdkOriginals(modules, retained);
}

module.exports = Object.freeze({
  associateHost(view, originals) {
    // Missing early startup is None, not native/module coverage or success.
    if (startup === undefined) return undefined;
    currentStartup();
    if (originals.runtime !== originalProcess || associations.has(view)) changed();
    if (originalSupplier !== undefined && originalSupplier !== originals.supplier) changed();
    if (generations.has(originals.generation)) unavailable();
    originalSupplier ??= originals.supplier;
    const original = {host: originals.host, generation: originals.generation,
      supplier: originals.supplier, installation: originals.installation,
      sdkStaticModules: undefined, retired: false};
    generations.add(originals.generation);
    associations.set(view, {host: originals.host, generation: originals.generation,
      original, root: true, retired: false});
    return view;
  },
  borrowScope(originalView, scopeView, host, generation) {
    current(originalView, host, generation);
    if (associations.has(scopeView)) changed();
    const held = associations.get(originalView);
    if (held.root !== true) unavailable();
    associations.set(scopeView, {host, generation, original: held.original, retired: false});
  },
  check(view, originals) {
    current(view, originals.host, originals.generation);
    if (associations.get(view).original.supplier !== originals.supplier ||
        originals.runtime !== originalProcess) changed();
  },
  bindSdkStaticModules(view, originals, modules) {
    current(view, originals.host, originals.generation);
    const held = associations.get(view);
    if (held.root !== true || startup.sdkStaticModules === undefined) sdkUnavailable();
    // The trusted installed builder supplies actual namespaces and its SAME
    // factory. Selected package/lock identities remain that supplier's duty;
    // module shape or matching hashes alone cannot authenticate a dependency.
    const retained = sdkOriginals(modules, startup.sdkStaticModules);
    held.original.sdkStaticModules = retained;
  },
  checkSdkStaticModules(view, originals, modules) {
    checkSdkModules(view, originals, modules);
  },
  checkSdkEagerModules(view, originals, modules) {
    // First validate the SAME bound modules/current Host or borrowed Scope.
    // No copied flag/hash or later execArgv observation supplies this history.
    checkSdkModules(view, originals, modules);
    if (!startup.eagerSdkStartup) {
      throw Object.assign(new TypeError('InferTrustedSdkEagerUnavailable'),
        {code: 'InferTrustedSdkEagerUnavailable'});
    }
    // This predicate issues no byte grant and says nothing about per-call
    // closures/frames/feedback/cache, dynamic eval, tiering or hooks. Retiring
    // a Host association also does not retire the actual ESM/bytecode graph.
  },
  retire(view, host, generation) {
    const held = associations.get(view);
    if (held === undefined || held.host !== host || held.generation !== generation) unavailable();
    held.retired = true;
    associations.delete(view);
    if (held.root === true) {
      held.original.retired = true;
      held.original.host = undefined;
      held.original.generation = undefined;
      held.original.supplier = undefined;
      held.original.installation = undefined;
      held.original.sdkStaticModules = undefined;
    }
    // Only Host borrow retirement; the selected runtime still owns these two
    // indices' internal backing, including weak membership of escaped retired
    // generations. startup.sdkStaticModules keeps its separate fixed graph.
    // Last Host/Run close does not retire either process/module responsibility.
    // No native/process/physical-stop ACK or numerical baseline is issued.
  },
});
