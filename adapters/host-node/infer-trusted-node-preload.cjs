'use strict';

// Private selected startup, not an application-time trust factory. Node runs
// this exact module in its real --require preload phase BEFORE entry imports.
// Ordinary embedded processes importing it later retain no startup original.
const {Buffer} = require('node:buffer');
const {Readable} = require('node:stream');
const {createRequire} = require('node:module');
const {dirname, join} = require('node:path');
const {getHeapStatistics} = require('node:v8');
const {isProxy} = require('node:util').types;
const originalProcess = require('node:process');
const applyOriginal = Reflect.apply;
const {createInitialControlInstallationOwner} = require('./initial-control-installation-owner.cjs');
const {declareInitialControlPhaseEnvelope, inspectInitialControlPhaseEnvelope}
  = require('./initial-control-phase-envelope.cjs');
const {declareSourceManagedPhaseEnvelope} = require('./source-managed-phase-envelope.cjs');
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
// Public delivery must be the actual fixed package wrapper chain loaded by
// Node's preload loader. A matching argv label, application import, other
// installation or intermediary application wrapper supplies no startup.
function publicPreloadOriginals() {
  if (module.isPreloading !== true) return undefined;
  const args = originalProcess.execArgv;
  const offset = args.length === 3 && args[0] === '--no-lazy' ? 1 : 0;
  if (args.length !== offset + 2 || args[offset] !== '--require') return undefined;
  const name = args[offset + 1];
  if (name !== '@actql/node/selected-infer-startup' &&
      name !== '@actql/local-node/selected-infer-startup') return undefined;
  const local = module.parent;
  if (local?.filename !== join(__dirname, '..', '..', 'selected-infer-startup.cjs') ||
      require.cache[local.filename] !== local) return undefined;
  const entry = name === '@actql/node/selected-infer-startup' ? local.parent : local;
  const loader = entry?.parent;
  if (loader?.id !== 'internal/preload') return undefined;
  try {
    const consumerRequire = createRequire(originalProcess.argv[1]);
    if (consumerRequire.resolve(name) !== entry.filename ||
        require.cache[entry.filename] !== entry ||
        entry !== local && createRequire(entry.filename).resolve('@actql/local-node/selected-infer-startup') !==
          local.filename) return undefined;
  } catch { return undefined; }
  // Original module records/paths and these controls remain managed startup
  // holdings. They are not fixed SDK storage, a byte lease or physical ACK.
  return Object.freeze({local, entry, loader, localFilename: local.filename,
    entryFilename: entry.filename});
}
const publicPreload = publicPreloadOriginals();
const eagerSdkStartup = module.isPreloading === true &&
  originalProcess.execArgv.length === 3 &&
  originalProcess.execArgv[0] === '--no-lazy' &&
  originalProcess.execArgv[1] === '--require' &&
  (originalProcess.execArgv[2] === __filename || publicPreload !== undefined);
// Loader provenance, not current poolSize/version alone. Reject other prior
// preload/import/loader selections, including merely equivalent flag orders.
const selected = module.isPreloading === true &&
  (eagerSdkStartup || originalProcess.execArgv.length === 2 &&
  originalProcess.execArgv[0] === '--require' &&
  originalProcess.execArgv[1] === __filename || publicPreload !== undefined) &&
  originalProcess.env.NODE_OPTIONS === undefined &&
  originalProcess.version === 'v22.22.0' &&
  originalProcess.platform === 'darwin' && originalProcess.arch === 'arm64' &&
  originalProcess.versions.openssl === '3.5.4';

// Source-only and incomplete distributions have no prepared image original.
// Requiring the actual generated Source here precedes entry imports; loading a
// similarly shaped caller object later cannot replace this module original.
// The fixed bootstrap prefix itself belongs to the selected trusted-runtime
// disposition. Declare its full managed/native/source/preparation ceiling
// before the generated inventory or any captured image is initialized.
const initialControlDeclaration = selected && eagerSdkStartup && publicPreload !== undefined
  ? declareInitialControlPhaseEnvelope(applyOriginal(getHeapStatistics, undefined, []).heap_size_limit)
  : undefined;
// Declare the additional Source scope against the SAME original VM before
// inventory capture, namespace initialization or SDK input acquisition. This
// is not Source admission: missing external suppliers/nominal child bindings
// still refuse. No second heap/native allowance or initial-control credit is
// created, and Source retirement cannot replenish process-lived holdings.
const sourceManagedEnvelope = initialControlDeclaration === undefined ? undefined :
  declareSourceManagedPhaseEnvelope(initialControlDeclaration);
// Native runtime/library identities stay with this SAME actual process/module
// lifetime. Their finite selected disposition is not retired by Host cleanup.
const initialControlRuntimeOriginal = initialControlDeclaration === undefined ? undefined :
  Object.freeze({node: originalProcess.versions.node, v8: originalProcess.versions.v8,
    openssl: originalProcess.versions.openssl, platform: originalProcess.platform,
    arch: originalProcess.arch, eager: true,
    libraries: Object.freeze({...originalProcess.versions})});
const initialControlPackageOriginal = initialControlDeclaration !== undefined
  ? require('./initial-control-package-original.cjs').imageInventory : undefined;

let startup, startupFailure;
// The selected runtime/control disposition is an explicit finite trust premise,
// not a universal V8/RSS lease or a resource profile. Instantiate it in this
// actual early preload, before image capture/compilation and caller acquisition.
// Source-only, non-eager and ordinary imports retain operational absence.
const initialControlEnvelope = initialControlPackageOriginal === undefined ? undefined :
  inspectInitialControlPhaseEnvelope(initialControlPackageOriginal, initialControlDeclaration,
    initialControlRuntimeOriginal);
let preparationOriginals, preparationInput, preparationIntake, preparationClosed = false;
const initialControlInputLimits = Object.freeze({maxProperties:40,maxNodes:40,maxDepth:4,
  maxStringCodeUnits:4096,maxTotalStringCodeUnits:8192,maxArrayItems:0,maxOpaqueAliases:0,maxWork:65536});
const samePreparation = held => preparationOriginals !== undefined &&
  held.host === preparationOriginals.host && held.installation === preparationOriginals.installation &&
  held.generation === preparationOriginals.generation && held.supplier === preparationOriginals.supplier &&
  held.moduleLifetime === preparationOriginals.moduleLifetime;
const inputUnavailable = () => {
  throw Object.assign(new TypeError('NodeInitialControlInputUnavailable'),
    {code: 'NodeInitialControlInputUnavailable'});
};
const operational = initialControlEnvelope === undefined ? undefined : Object.freeze({
  prepare(held, rawInput) {
    currentStartup();
    if (preparationOriginals !== undefined) inputUnavailable();
    applyOriginal(startup.initialControlHostValidator, startup.initialControlHostNamespace, [held]);
    if (rawInput !== undefined && (preparationIntake === undefined ||
        preparationIntake.raw !== rawInput || preparationIntake.consumed)) inputUnavailable();
    // One generation for this process recipe, including refused/closing work.
    // Never replenish it on close, WeakMap deletion, settlement or GC.
    preparationOriginals = held;
    if (rawInput === undefined) preparationInput = Object.freeze(Object.create(null));
    else {
      preparationIntake.consumed = true;
      preparationInput = preparationIntake.snapshot.packet;
      // The original identity was checked synchronously. Retain the immutable
      // admitted snapshot, not an unnecessary mutable caller graph through
      // namespace awaits or cleanup. This alias cut is not a physical ACK.
      preparationIntake.raw = undefined;
    }
  },
  assertCurrent(held) {
    if (!samePreparation(held) || preparationClosed) inputUnavailable();
    currentStartup();
    applyOriginal(startup.initialControlHostValidator, startup.initialControlHostNamespace, [held]);
  },
  readInput(held) {
    if (!samePreparation(held) || preparationClosed) inputUnavailable();
    return preparationInput;
  },
  readAsset(held, path) {
    if (!samePreparation(held) || preparationClosed) inputUnavailable();
    return startup.initialControlImages.readAsset(path);
  },
  close(held) {
    if (!samePreparation(held)) inputUnavailable();
    // The installation Owner invokes this only after its retained children
    // acknowledge and preparation aliases have been cut. This closes the
    // managed preparation, not the process/module/native or escaped lifetime.
    preparationInput = undefined;
    preparationIntake = undefined;
    preparationClosed = true;
    return Object.freeze({pending: false});
  },
});
const initialControl = createInitialControlInstallationOwner(operational);

// Publish the same immutable callback table before synchronous namespace
// initialization can reenter this Module. Capturing it is not an operational
// admission; currentStartup still refuses before that original handoff exists.
module.exports = {
  connectInitialControlHostPreparation(kind, rawInput) {
    // An immutable image or exported callback is not an intake issuer. Keep
    // absence before raw reads, current callbacks or candidate construction.
    initialControl.requireOperational();
    currentStartup();
    if (kind === 'open') {
      if (preparationOriginals !== undefined || preparationIntake !== undefined) inputUnavailable();
      if (rawInput !== undefined) inputUnavailable();
    } else if (kind === 'connect') {
      // Only classify an own DATA local-mode selector here. Other existing
      // routes retain their original public validation/coverage. Never probe a
      // Proxy or evaluate a mode getter merely to choose this private route.
      if (rawInput === null || typeof rawInput !== 'object' || isProxy(rawInput)) return undefined;
      const mode = Object.getOwnPropertyDescriptor(rawInput,'mode');
      if (mode === undefined || !Object.hasOwn(mode,'value') || mode.value !== 'local') return undefined;
      const endpoint=Object.getOwnPropertyDescriptor(rawInput,'endpoint');
      if (endpoint !== undefined && Object.hasOwn(endpoint,'value') && endpoint.value !== undefined) return undefined;
      if (preparationOriginals !== undefined || preparationIntake !== undefined) inputUnavailable();
      const reader = startup.initialControlHostInputReader;
      if (reader === undefined) inputUnavailable();
      // This SAME selected finite control envelope precedes first ownKeys,
      // descriptor traversal and snapshot. Its captured reader is DATA only;
      // no callback/opaque backing is accepted by the zero-alias recipe.
      const snapshot = applyOriginal(reader, startup.initialControlHostNamespace,
        [rawInput, initialControlInputLimits]);
      if (snapshot.originalReferences.length !== 0) inputUnavailable();
      const packet = snapshot.packet, keys = Reflect.ownKeys(packet);
      // First supported public packet is the literal README Mock entrance.
      // Do not silently drop an unknown field or substitute configured live
      // providers when a valid but unsupported packet is supplied.
      if (keys.length !== 3 || !keys.includes('mode') || !keys.includes('installation') ||
          !keys.includes('profile') || packet.mode !== 'local' || packet.profile !== 'mock' ||
          packet.installation === null || typeof packet.installation !== 'object') inputUnavailable();
      const installationKeys = Reflect.ownKeys(packet.installation);
      if (installationKeys.length !== 1 || installationKeys[0] !== 'directory' ||
          typeof packet.installation.directory !== 'string' || packet.installation.directory.length === 0) inputUnavailable();
      preparationIntake = {raw:rawInput,snapshot,consumed:false};
    } else inputUnavailable();
    const consumer = startup.initialControlHostConsumer;
    if (consumer === undefined || kind !== 'open' && kind !== 'connect') {
      throw Object.assign(new TypeError('NodeInitialControlAdmissionUnavailable'),
        {code: 'NodeInitialControlAdmissionUnavailable'});
    }
    // Only the captured actual Host operation/receiver receives the same raw
    // input synchronously. It retains the same candidate and begins original
    // acquisition before copying; only its existing Client Promise may escape.
    return applyOriginal(consumer, startup.initialControlHostNamespace, [kind, rawInput]);
  },
  beginInitialControlInstallation(originals, rawInput) {
    return initialControl.begin(originals, rawInput);
  },
  assertInitialControlInstallationCurrent(scope, sameOriginals) {
    return initialControl.assertCurrent(scope, sameOriginals);
  },
  readInitialControlInstallationAsset(scope, sameOriginals, path) {
    return initialControl.readAsset(scope, sameOriginals, path);
  },
  readInitialControlInstallationInput(scope, sameOriginals) {
    return initialControl.readInput(scope, sameOriginals);
  },
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
};
// Node's synchronous ESM consumer can read these published originals while
// this startup captures its namespace. A null prototype avoids Node installing
// its circular-require warning prototype on the immutable forwarder table.
// No marker field or caller-supplied table authenticates an operational Root.
Object.setPrototypeOf(module.exports, null);
Object.freeze(module.exports);

if (selected) try {
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
  const string = globalThis.String;
  // Same-realm native prototype, without starting a generator, Promise or
  // physical stream. Actual Node Readable iteration uses this shared next.
  // The temporary function/prototype lookup remains startup workspace, not a
  // per-Call capacity grant or proof that a completed iterator was reclaimed.
  const asyncGeneratorPrototype = Object.getPrototypeOf(async function* () {}).prototype;
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
    [Readable.prototype, Symbol.asyncIterator], [asyncGeneratorPrototype, 'next'],
    [globalThis, 'TextDecoder'], [TextDecoder.prototype, 'decode'],
    [Buffer.prototype, 'subarray'],
    // The emitted Common UTF16/UTF8 and JSON scanners read primitive String
    // code units through this exact method. Preserve that selected native
    // implementation, not an application replacement with different storage
    // or scan behavior. This does not freeze all String methods or bound their
    // heap/flatten/GC behavior. The extra descriptor/array slot stays managed.
    [string.prototype, 'charCodeAt'],
    // Common's emitted String builder calls the global constructor's same
    // fromCodePoint. Keep both originals for the selected implementation;
    // this is not a no-allocation claim for arbitrary Unicode/builders.
    // Two added pairs/descriptor records and reflection remain managed.
    [globalThis, 'String'], [string, 'fromCodePoint'],
    // The prepared Host trims its original environment Source before the
    // existing normalizer runs. Keep that exact native operation; immutable
    // Source/module identity alone cannot bound a replacement application
    // callback. The pair, descriptor and returned String overlap remain in
    // the original control envelope, not a byte grant or an all-String fence.
    [string.prototype, 'trimEnd'],
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
  // Consume the actual normal package inventory before optional SDK or Host
  // namespace compilation. Source-only absence remains absence. This captures
  // original image bytes and module identity, not the missing operational
  // intake/runtime envelope, prior-registration proof or business capacity.
  const initialControlImages = initialControlPackageOriginal === undefined ? undefined :
    require('./initial-control-package-custody.cjs').captureInitialControlPackageCustody(
      initialControlPackageOriginal, join(__dirname, '..', '..'), originalProcess.argv[1],
      publicPreload.entry === publicPreload.local ? undefined : publicPreload.entryFilename);
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
  const initialControlHostNamespace = initialControlImages?.initializeHostNamespace();
  const consumerProperty = initialControlHostNamespace === undefined ? undefined :
    Object.getOwnPropertyDescriptor(initialControlHostNamespace, 'connectInitialControlHostPreparation');
  const initialControlHostConsumer = consumerProperty !== undefined &&
    Object.hasOwn(consumerProperty, 'value') && typeof consumerProperty.value === 'function'
    ? consumerProperty.value : undefined;
  const validatorProperty = initialControlHostNamespace === undefined ? undefined :
    Object.getOwnPropertyDescriptor(initialControlHostNamespace, 'assertInitialControlHostPreparation');
  const initialControlHostValidator = validatorProperty !== undefined &&
    Object.hasOwn(validatorProperty, 'value') && typeof validatorProperty.value === 'function'
    ? validatorProperty.value : undefined;
  const inputReaderProperty = initialControlHostNamespace === undefined ? undefined :
    Object.getOwnPropertyDescriptor(initialControlHostNamespace, 'readInitialControlHostInput');
  const initialControlHostInputReader = inputReaderProperty !== undefined &&
    Object.hasOwn(inputReaderProperty,'value') && typeof inputReaderProperty.value === 'function'
    ? inputReaderProperty.value : undefined;
  if (operational !== undefined && initialControlHostValidator === undefined) unavailable();
  // The actual process/module/native responsibility stays with this startup.
  // These originals and the existing Host overlap still need funded coverage.
  // In particular the three added descriptor records/array entries/references
  // are managed startup controls, not part of the TLS adapter trust exemption.
  // ActQL aliases, Promises, closures, copied diagnostics and exported peer or
  // error data also remain on the original Ledger. Native trust is neither a
  // zero-byte claim nor a lease. The same socket operation and last borrower
  // retain their original responsibility until actual cleanup, not destroy(),
  // rejection, Promise settlement or retirement of this association.
  startup = {process: originalProcess, module, entry: originalProcess.argv[1], originals, publicPreload,
    promiseSpecies, sdkStaticModules, eagerSdkStartup, initialControlImages,
    initialControlHostNamespace, initialControlHostConsumer, initialControlHostValidator, initialControlHostInputReader,
    initialControlEnvelope, sourceManagedEnvelope, invalidated: false};
} catch (cause) {
  // Retain the exact original startup/physical cleanup cause. A failed image
  // never becomes a namespace and is not reread after a close-only retry.
  // Publishing the original Client-only refusal keeps any original pending
  // handle reachable instead of mistaking process exit for its cleanup ACK.
  startupFailure = Object.freeze({cause});
}

function currentStartup() {
  if (startupFailure !== undefined) throw startupFailure.cause;
  if (startup === undefined) unavailable();
  if (startup.invalidated) changed();
  startup.initialControlImages?.assertCurrent();
  if (startup.process !== originalProcess || startup.entry !== originalProcess.argv[1] ||
      globalThis.Buffer !== Buffer) {
    startup.invalidated = true;
    changed();
  }
  const loaded = startup.publicPreload;
  if (loaded !== undefined && (module.parent !== loaded.local ||
      loaded.local.filename !== loaded.localFilename ||
      loaded.entry.filename !== loaded.entryFilename ||
      loaded.entry.parent !== loaded.loader ||
      loaded.local !== loaded.entry && loaded.local.parent !== loaded.entry ||
      require.cache[loaded.localFilename] !== loaded.local ||
      require.cache[loaded.entryFilename] !== loaded.entry)) {
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
