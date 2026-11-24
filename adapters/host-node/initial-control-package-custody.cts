'use strict';

type ImageSource = ReturnType<typeof import('./initial-control-image-source.cjs').captureInitialControlImageSource>;
type ImageGroup = Readonly<{
  root: string;
  images: readonly Readonly<{path: string; captured: ImageSource}>[];
  version: unknown;
}>;
type ImageFact = Readonly<{path: unknown; cid: unknown}>;
type SdkImageRegistration = Readonly<{
  adapter: ImageFact;
  lock: ImageFact;
  sdk: ImageFact & Readonly<{packageName: unknown; version: unknown}>;
}>;
type SdkImage = Readonly<{namespace: unknown; cid: unknown; packageName: unknown; version: unknown}>;
type ImageCustody = ReturnType<typeof capturePackageCustody>;
type SelectedSdkInstallation = Readonly<{
  verifiedSdkInstallations: ReadonlyMap<string, SdkImageRegistration>;
  sdkImageCustody: ImageCustody;
}>;
type NativeLoader = typeof import('./host-journal-native-image.cjs').loadOrdinaryLocalFilesNative;
type NativeOriginal = Readonly<{
  root: string;
  images: unknown;
  load: NativeLoader;
  limits: Readonly<{maxImageBytes: number; temporaryDirectory: string}>;
}>;

// Private installed-image custody, not an operational issuer. Only the actual
// selected startup may adopt these Sources, namespace and loader originals;
// their complete runtime/intake envelope and bootstrap provenance remain its
// independent responsibility. No caller packet can obtain a scope here.
const NodeModule = require('node:module') as typeof import('node:module');
const {createRequire} = NodeModule;
const {dirname, join, isAbsolute} = require('node:path') as typeof import('node:path');
const {existsSync, realpathSync} = require('node:fs') as typeof import('node:fs');
const {captureInitialControlImageSource} = require('./initial-control-image-source.cjs') as typeof import('./initial-control-image-source.cjs');
const {installInitialControlImageLoader, installOrdinaryInitialControlImageLoader} = require('./initial-control-image-loader.cjs') as typeof import('./initial-control-image-loader.cjs');
const {getHeapStatistics} = require('node:v8') as typeof import('node:v8');
const {tmpdir} = require('node:os') as typeof import('node:os');
const {types: nodeTypes} = require('node:util') as typeof import('node:util');
const {declareOrdinaryInitialControlPhaseEnvelope, inspectOrdinaryInitialControlPhaseEnvelope}
  = require('./initial-control-phase-envelope.cjs') as typeof import('./initial-control-phase-envelope.cjs');
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor, hasOwn = Object.hasOwn;
const apply = Reflect.apply, array = Array.isArray as (value: unknown) => value is unknown[],
  integer = Number.isSafeInteger as (value: unknown) => value is number;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const parse = JSON.parse, NativeMap = Map, NativeSet = Set, NativeError = Error;
const mapGet = Map.prototype.get, mapSet = Map.prototype.set, mapHas = Map.prototype.has;
const setHas = Set.prototype.has, setAdd = Set.prototype.add;
const sdkImages = new WeakMap<ImageCustody,
  (packageName: unknown, path: unknown, cid: unknown, kind: unknown) => SdkImage>();
const sdkImageGet = WeakMap.prototype.get, sdkImageSet = WeakMap.prototype.set;
const invalidSdkRegistration = 'InvalidInstalledModelSdkInstallation';
const fail: (code: string) => never = code => { const cause = new NativeError(code) as NodeJS.ErrnoException; cause.code = code; throw cause; };
const own = (value: unknown, name: PropertyKey): unknown => {
  if (value === null || typeof value !== 'object') fail('InvalidInitialControlPackageImage');
  const property = descriptor(value, name);
  if (property === undefined || !hasOwn(property, 'value')) fail('InvalidInitialControlPackageImage');
  return property.value;
};
const optionalField = (value: unknown, name: PropertyKey): unknown => {
  const property = descriptor(value, name);
  if (property === undefined) return undefined;
  if (!hasOwn(property, 'value')) fail('InvalidInitialControlPackageImage');
  return property.value;
};
const concrete = (value: unknown): value is string => typeof value === 'string' && value.length !== 0 &&
  !isAbsolute(value) && !value.includes('\\') &&
  !value.split('/').some(part => part === '' || part === '.' || part === '..');

function captureInitialControlPackageCustody(inventory: unknown, localRoot: string, consumerEntry?: unknown,
  publicPreloadEntry?: unknown) {
  // A late caller must not trigger resolution, path reads or descriptor walks.
  // This helper still cannot prove a preload's original source or funding.
  if (typeof preloading !== 'function' || apply(preloading, module, []) !== true) {
    fail('InitialControlPackageCustodyUnavailable');
  }
  return capturePackageCustody(inventory, localRoot, consumerEntry, publicPreloadEntry, false);
}

// Separate ordinary byte/namespace custody, never a late operational issuer.
// It can only be adopted by the real installed public-prefix instance, whose
// runtime and finite phase must precede this first path/image acquisition.
function captureOrdinaryInitialControlPackageCustody(inventory: unknown, localRoot: string, consumerEntry?: unknown,
  publicDeliveryEntry?: unknown, initialSdkRegistrations?: Iterable<SdkImageRegistration>) {
  if (typeof preloading !== 'function' || apply(preloading, module, []) !== false) {
    fail('InitialControlPackageCustodyUnavailable');
  }
  return capturePackageCustody(inventory, localRoot, consumerEntry, publicDeliveryEntry, true, initialSdkRegistrations);
}

function capturePackageCustody(inventory: unknown, localRoot: string, consumerEntry: unknown,
  publicPreloadEntry: unknown, ordinary: boolean, initialSdkRegistrations?: Iterable<SdkImageRegistration>) {
  const root = realpathSync(localRoot), images = own(inventory, 'images');
  // The inventory array checks below also establish the package array used by the inner functions.
  const packages = own(inventory, 'packages') as readonly unknown[], dependencies = own(inventory, 'dependencies');
  const hostModule = own(inventory, 'hostModule'), hostValidator = own(inventory, 'hostValidator');
  const localPublicModule = own(inventory, 'localPublicModule');
  const publicNode = own(inventory, 'publicNode'), publicNodeCoverage = own(inventory, 'publicNodeCoverage');
  if (!array(images) || !array(packages) || !array(dependencies) ||
      hostModule !== 'adapters/host-node/embedded-local.mjs' ||
      localPublicModule !== 'index.mjs' ||
      hostValidator !== 'assertInitialControlHostPreparation') fail('InvalidInitialControlPackageImage');
  const groups: ImageGroup[] = [], actualPackages: string[] = [], roots = new NativeMap<string, number>(),
    mainSources = new NativeMap<string, ImageSource>();
  function captureGroup(directory: string, facts: unknown, expectedName: string, expectedVersion: unknown,
    expectedReleaseVersion: unknown, expectedRepresentation?: ImageSource['representation']) {
    if (!array(facts) || facts.length === 0) fail('InvalidInitialControlPackageImage');
    const selected: ImageGroup['images'][number][] = [], names = new NativeSet<string>();
    let manifest: unknown, representation: ImageSource['representation'];
    for (let index = 0; index < facts.length; index++) {
      const fact = facts[index], path = own(fact, 'path');
      if (!concrete(path) || apply(setHas, names, [path])) fail('InvalidInitialControlPackageImage');
      apply(setAdd, names, [path]);
      const release = optionalField(fact, 'npmRelease');
      if (release !== undefined && (path !== 'package.json' ||
          expectedReleaseVersion === undefined || own(release, 'version') !== expectedReleaseVersion)) {
        fail('InvalidInitialControlPackageImage');
      }
      const captured = captureInitialControlImageSource(join(directory, path), fact);
      selected[selected.length] = freeze({path, captured});
      if (directory === root) apply(mapSet, mainSources, [path, captured]);
      if (path === 'package.json') {
        manifest = parse(captured.source);
        representation = captured.representation ?? 'source';
      }
    }
    const version = representation === 'release' ? expectedReleaseVersion : expectedVersion;
    if (manifest === undefined || own(manifest, 'name') !== expectedName ||
        version !== undefined && own(manifest, 'version') !== version ||
        expectedReleaseVersion !== undefined && expectedRepresentation !== undefined &&
          representation !== expectedRepresentation) {
      fail('InitialControlPackageImageChanged');
    }
    groups[groups.length] = freeze({root: directory, images: freeze(selected), version: optionalField(manifest, 'version')});
    return {manifest, representation};
  }
  const local = captureGroup(root, images, '@actql/local-node', optionalField(inventory, 'localVersion'),
    optionalField(inventory, 'localReleaseVersion'));
  function resolvePackage(name: string, from: string) {
    const originalRequire = createRequire(join(from, 'package.json'));
    let entry;
    try { entry = originalRequire.resolve(name); }
    catch (cause) {
      if ((cause as NodeJS.ErrnoException).code !== 'MODULE_NOT_FOUND' &&
          (cause as NodeJS.ErrnoException).code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') throw cause;
      // Type-only selected dependencies can have no executable entry. Resolve
      // only through Node's same actual package search, never a supplied root.
      const paths = originalRequire.resolve.paths(name);
      if (!array(paths)) throw cause;
      for (let index = 0; index < paths.length; index++) {
        const candidate = join(paths[index], name);
        if (existsSync(join(candidate, 'package.json'))) return realpathSync(candidate);
      }
      throw cause;
    }
    let directory = dirname(realpathSync(entry));
    for (;;) {
      if (existsSync(join(directory, 'package.json'))) return directory;
      const parent = dirname(directory);
      if (parent === directory) fail('InitialControlPackageImageChanged');
      directory = parent;
    }
  }
  function captureDependency(binding: unknown, from: string) {
    const name = own(binding, 'name'), index = own(binding, 'package');
    if (typeof name !== 'string' || !integer(index) || index < 0 || index >= packages.length) {
      fail('InvalidInitialControlPackageImage');
    }
    const selected = packages[index];
    if (own(selected, 'name') !== name) fail('InvalidInitialControlPackageImage');
    const directory = resolvePackage(name, from);
    const previous = actualPackages[index];
    if (previous !== undefined) {
      if (previous !== directory) fail('InitialControlPackageImageChanged');
      return;
    }
    if (apply(mapHas, roots, [directory])) fail('InitialControlPackageImageChanged');
    actualPackages[index] = directory;
    apply(mapSet, roots, [directory, index]);
    captureGroup(directory, own(selected, 'images'), name, own(selected, 'version'),
      optionalField(selected, 'releaseVersion'), local.representation);
    const next = own(selected, 'dependencies');
    if (!array(next)) fail('InvalidInitialControlPackageImage');
    for (let item = 0; item < next.length; item++) captureDependency(next[item], directory);
  }
  for (let index = 0; index < dependencies.length; index++) captureDependency(dependencies[index], root);
  const optional = own(inventory, 'optionalSdk'), optionalCoverage = own(inventory, 'optionalSdkCoverage');
  const sdkPackages = new NativeMap<string, string>();
  if (optionalCoverage === 'prepared') {
    if (typeof consumerEntry !== 'string' || !isAbsolute(consumerEntry)) {
      fail('InvalidInitialControlPackageImage');
    }
    // The actual startup resolves its optional SDK from that SAME consumer
    // entry, not from Local's potentially different nested dependency slot.
    captureDependency({name: '@actql/provider-ai-sdk', package: optional}, dirname(consumerEntry));
    apply(mapSet, sdkPackages, ['@actql/provider-ai-sdk', actualPackages[optional as number]]);
    // captureDependency has admitted this index and recursively checked its dependency array.
    for (const dependency of own(packages[optional as number], 'dependencies') as readonly unknown[]) {
      apply(mapSet, sdkPackages, [own(dependency, 'name'), actualPackages[own(dependency, 'package') as number]]);
    }
  } else if (optional !== null || optionalCoverage !== 'absent' && optionalCoverage !== 'unprepared') {
    fail('InvalidInitialControlPackageImage');
  }
  let nodeRoot: string | undefined;
  const unselectedPublicPackages = new NativeSet<number>();
  if (publicNodeCoverage === 'prepared') {
    if (own(publicNode, 'name') !== '@actql/node') fail('InvalidInitialControlPackageImage');
    const next = own(publicNode, 'dependencies');
    if (!array(next)) fail('InvalidInitialControlPackageImage');
    if (publicPreloadEntry !== undefined) {
      if (typeof publicPreloadEntry !== 'string' || !isAbsolute(publicPreloadEntry)) {
        fail('InvalidInitialControlPackageImage');
      }
      const entry = realpathSync(publicPreloadEntry);
      nodeRoot = dirname(entry);
      if (entry !== join(nodeRoot, ordinary ? 'initial-control-public-dispatch.cjs' : 'selected-infer-startup.cjs') || nodeRoot === root) {
        fail('InitialControlPackageImageChanged');
      }
      captureGroup(nodeRoot, own(publicNode, 'images'), '@actql/node', own(publicNode, 'version'),
        optionalField(publicNode, 'releaseVersion'), local.representation);
    }
    let localBound = false;
    function publicDependency(binding: unknown, from: string) {
      const name = own(binding, 'name');
      if (name === '@actql/local-node') {
        if (from !== nodeRoot || own(binding, 'local') !== true || resolvePackage(name, from) !== root) {
          fail('InitialControlPackageImageChanged');
        }
        localBound = true;
        return;
      }
      captureDependency(binding, from);
    }
    // For Local-only delivery the optional parent facade is not acquired.
    // Its graph may contain additional Source facts, never usable coverage of
    // an unloaded Node facade. Validate their reachability without loading it.
    function markUnselected(binding: unknown) {
      const name = own(binding, 'name');
      if (name === '@actql/local-node') {
        if (own(binding, 'local') !== true) fail('InvalidInitialControlPackageImage');
        localBound = true; return;
      }
      const index = own(binding, 'package');
      if (!integer(index) || index < 0 || index >= packages.length ||
          own(packages[index], 'name') !== name) fail('InvalidInitialControlPackageImage');
      if (apply(setHas, unselectedPublicPackages, [index])) return;
      apply(setAdd, unselectedPublicPackages, [index]);
      const children = own(packages[index], 'dependencies');
      if (!array(children)) fail('InvalidInitialControlPackageImage');
      for (let item = 0; item < children.length; item++) markUnselected(children[item]);
    }
    for (let index = 0; index < next.length; index++) {
      if (nodeRoot === undefined) markUnselected(next[index]);
      else publicDependency(next[index], nodeRoot);
    }
    if (!localBound) fail('InvalidInitialControlPackageImage');
  } else if (publicNode !== null || publicNodeCoverage !== 'absent' && publicNodeCoverage !== 'unprepared') {
    fail('InvalidInitialControlPackageImage');
  }
  if (publicPreloadEntry !== undefined && nodeRoot === undefined) fail('InitialControlPublicNodeUnavailable');
  for (let index = 0; index < packages.length; index++) {
    if (actualPackages[index] === undefined && !apply(setHas, unselectedPublicPackages, [index])) {
      fail('InvalidInitialControlPackageImage');
    }
  }
  if (!apply(mapHas, mainSources, [hostModule]) || !apply(mapHas, mainSources, [localPublicModule])) {
    fail('InvalidInitialControlPackageImage');
  }
  function selectSdkImage(packageName: unknown, path: unknown, cid: unknown, kind: unknown, refusal?: string) {
    if (typeof packageName !== 'string' || !concrete(path) ||
        typeof cid !== 'string' || !/^sha256:[a-f0-9]{64}$/u.test(cid) ||
        kind !== 'module' && kind !== 'lock' || kind === 'lock' && packageName !== '@actql/provider-ai-sdk') {
      fail(refusal ?? 'InitialControlSdkImageUnavailable');
    }
    const directory = apply(mapGet, sdkPackages, [packageName]) as string | undefined;
    if (directory === undefined) fail(refusal ?? 'InitialControlSdkImageUnavailable');
    const group = groups.find(value => value.root === directory)!;
    const image = group.images.find(value => value.path === path);
    if (image === undefined || 'sha256:' + image.captured.sha256 !== cid ||
        kind === 'lock' && path !== 'npm-shrinkwrap.json') fail(refusal ?? 'InitialControlPackageImageChanged');
    return {directory, group, image};
  }
  let requiredModules: string[] | undefined;
  if (initialSdkRegistrations !== undefined) {
    requiredModules = [];
    for (const {adapter, lock, sdk} of initialSdkRegistrations) {
      const select = (name: unknown, original: ImageFact, kind: 'module' | 'lock') =>
        selectSdkImage(name, original.path, original.cid, kind, invalidSdkRegistration);
      select(sdkPackage, lock, 'lock');
      const sdkImage = select(sdk.packageName, sdk, 'module');
      if (sdkImage.group.version !== sdk.version) fail(invalidSdkRegistration);
      const adapterImage = select(sdkPackage, adapter, 'module');
      requiredModules.push(join(sdkImage.directory, sdk.path as string), join(adapterImage.directory, adapter.path as string));
    }
  }
  const loader = ordinary ? installOrdinaryInitialControlImageLoader(groups, requiredModules) :
    installInitialControlImageLoader(groups);
  const originalRequire = createRequire(join(root, 'package.json'));
  let namespace: unknown, publicNamespaces: Readonly<{local: unknown; node: unknown}> | undefined,
    initialized = false, selectedSdk = false;
  function initializeHostNamespace() {
    if (apply(preloading!, module, []) !== !ordinary) fail('InitialControlPackageCustodyUnavailable');
    loader.assertCurrent();
    if (initialized) return namespace;
    if (selectedSdk && ordinary) {
      // Compile the fixed optional package entrance with the same selected
      // modules. Its CommonJS dependencies must land before the cache seal.
      const directory = apply(mapGet, sdkPackages, ['@actql/provider-ai-sdk']) as string;
      const group = groups.find(value => value.root === directory)!;
      const entry = group.images.find(value => value.path === 'index.mjs');
      if (entry === undefined) fail('InitialControlSdkImageUnavailable');
      loader.loadSelectedModule(join(directory, entry.path), entry.captured.sha256);
    }
    if (requiredModules !== undefined) {
      // The pinned Undici HTTP/1 transport loads these two parser variants
      // lazily. Give both their original verified Source before closing the
      // CommonJS cache, without establishing a socket or invoking an SDK.
      const directory = apply(mapGet, sdkPackages, ['undici']) as string | undefined;
      const transport = groups.find(value => value.root === directory);
      for (const path of ['lib/llhttp/llhttp-wasm.js', 'lib/llhttp/llhttp_simd-wasm.js']) {
        const parser = transport?.images.find(value => value.path === path);
        if (parser === undefined) fail('InitialControlSdkImageUnavailable');
        loader.loadSelectedModule(join(directory!, path), parser.captured.sha256, 'wasm-parser');
      }
    }
    // Actual Source delivery precedes this compilation. Do not capture a
    // mutable pathname later or initialize a replacement caller namespace.
    const loaded = originalRequire(join(root, hostModule as string));
    if (typeof descriptor(loaded, hostValidator as string)?.value !== 'function') {
      fail('InitialControlPackageImageChanged');
    }
    // Compile both actual public ESM namespaces before the Module handoff.
    // Later entry imports must reuse these same originals, not pathname bytes
    // that can change after the Host namespace was initialized.
    // Ordinary public facades are already being linked by Node when their
    // private prefix runs. Do not synchronously re-require that same in-flight
    // ESM graph. Their fixed prefix belongs to its separate ordinary bootstrap
    // responsibility; covered Host/dependencies are delivered by this loader.
    const localNamespace = ordinary ? undefined : originalRequire(join(root, localPublicModule as string));
    const nodeNamespace = ordinary || nodeRoot === undefined ? undefined : originalRequire(join(nodeRoot, 'index.mjs'));
    publicNamespaces = freeze({local: localNamespace, node: nodeNamespace});
    loader.captureLoadedModules();
    namespace = loaded;
    initialized = true;
    return namespace;
  }
  function assertCurrent() {
    loader.assertCurrent();
    if (!initialized || publicNamespaces === undefined) fail('InitialControlPackageCustodyUnavailable');
  }
  function readAsset(path: unknown) {
    assertCurrent();
    if (typeof path !== 'string') fail('InitialControlPackageCustodyUnavailable');
    return (apply(mapGet, mainSources, [path]) as ImageSource | undefined)?.source;
  }
  function readSdkImage(packageName: unknown, path: unknown, cid: unknown, kind: unknown): SdkImage {
    loader.assertCurrent();
    const {directory, group, image} = selectSdkImage(packageName, path, cid, kind);
    const namespace = kind === 'module' ? loader.loadSelectedModule(join(directory, path as string), image.captured.sha256) : undefined;
    if (!initialized && namespace !== undefined) selectedSdk = true;
    loader.assertCurrent();
    return freeze({namespace, cid, packageName, version: group.version});
  }
  // Held Sources, module/namespace records, loader hooks and caches remain the
  // original process/module lifetime, including escaped Strings. This table
  // issues no scope and has no synthetic close/GC/capacity acknowledgement.
  const custody = freeze({initializeHostNamespace, assertCurrent, readAsset});
  apply(sdkImageSet, sdkImages, [custody, readSdkImage]);
  return custody;
}

function readVerifiedSdkImage(custody: unknown, packageName: unknown, path: unknown, cid: unknown, kind: unknown) {
  const read = apply(sdkImageGet, sdkImages, [custody]) as
    ((name: unknown, source: unknown, digest: unknown, kind: unknown) => SdkImage) | undefined;
  if (read === undefined) fail('InitialControlSdkImageUnavailable');
  return read(packageName, path, cid, kind);
}

const sdkPackage = '@actql/provider-ai-sdk';
const ordinarySdkPreparations = new WeakMap<object, SelectedSdkInstallation>();
let ordinarySdkImages: ImageCustody | undefined, ordinaryNativeOriginal: NativeOriginal | undefined,
  sdkImageFailure: Readonly<{cause: unknown; blocksOrdinary: boolean}> | undefined, sdkImageStarting = false;

function prepareOrdinaryModelSdkInstallation(source: unknown) {
  if (source === undefined) return undefined;
  if (!Array.isArray(source) || nodeTypes.isProxy(source) || !Object.isFrozen(source) || source.length === 0 || source.length > 64) {
    fail(invalidSdkRegistration);
  }
  const data: (value: unknown, keys: readonly PropertyKey[], optional?: readonly PropertyKey[]) =>
      asserts value is Readonly<Record<PropertyKey, unknown>> = (value, keys, optional = []) => {
    if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value) ||
        Object.getPrototypeOf(value) !== Object.prototype || !Object.isFrozen(value) ||
        Reflect.ownKeys(value).some(key => !keys.includes(key) && !optional.includes(key)) ||
        [...keys, ...optional.filter(key => Object.hasOwn(value, key))].some(key => {
          const field = Object.getOwnPropertyDescriptor(value, key);
          return !field?.enumerable || !Object.hasOwn(field, 'value');
        })) fail(invalidSdkRegistration);
  };
  const previous = ordinarySdkPreparations.get(source);
  if (previous !== undefined) {
    previous.sdkImageCustody.assertCurrent();
    return;
  }
  const registrations = new Map<string, SdkImageRegistration>();
  for (let index = 0; index < source.length; index++) {
    const field = Object.getOwnPropertyDescriptor(source, index);
    if (field === undefined || !Object.hasOwn(field, 'value')) fail(invalidSdkRegistration);
    const original: unknown = field.value;
    data(original, ['adapter', 'sdk', 'lock', 'route', 'providerOptions'], ['credential']);
    if (Object.hasOwn(original, 'credential')) data(original.credential, ['reference', 'header']);
    data(original.adapter, ['path', 'cid']);
    data(original.sdk, ['path', 'cid', 'packageName', 'version', 'exportName']);
    data(original.lock, ['path', 'cid']);
    data(original.route, ['providerId', 'selector', 'modelId', 'apiMode', 'endpoint']);
    const id = original.route.providerId;
    if (typeof id !== 'string' || id.length === 0 || id.length > 256 || registrations.has(id)) {
      fail(invalidSdkRegistration);
    }
    registrations.set(id, original as unknown as SdkImageRegistration);
  }
  if (sdkImageFailure !== undefined) throw sdkImageFailure.cause;
  if (sdkImageStarting) fail('InitialControlSdkImageStarting');
  const initialize = ordinarySdkImages === undefined;
  let nativeOriginal: NativeOriginal | undefined, capturing = false;
  try {
    if (initialize) {
      sdkImageStarting = true;
      // Adopt the existing installed-image envelope before borrowing any bytes
      // or compiling the selected module. The original package owns this
      // cache for the process lifetime, including after Host close.
      const envelope = declareOrdinaryInitialControlPhaseEnvelope(getHeapStatistics().heap_size_limit);
      const {imageInventory} = require('./initial-control-package-original.cjs') as
        {imageInventory?: Readonly<{optionalSdkCoverage?: unknown}>};
      if (imageInventory?.optionalSdkCoverage !== 'prepared') fail('InitialControlSdkImageUnavailable');
      const runtime = Object.freeze({node: process.versions.node, v8: process.versions.v8,
        openssl: process.versions.openssl, platform: process.platform, arch: process.arch,
        eager: false, libraries: Object.freeze({...process.versions})});
      inspectOrdinaryInitialControlPhaseEnvelope(imageInventory, envelope, runtime);
      const root = join(__dirname, '../..');
      const {declareHostJournalServiceRecipe} = require('./host-journal-service-recipe.cjs') as typeof import('./host-journal-service-recipe.cjs');
      const {loadOrdinaryLocalFilesNative} = require('./host-journal-native-image.cjs') as typeof import('./host-journal-native-image.cjs');
      const {directoryLimits} = declareHostJournalServiceRecipe(envelope);
      nativeOriginal = freeze({root, images: own(imageInventory, 'nativeImages'),
        load: loadOrdinaryLocalFilesNative,
        limits: freeze({maxImageBytes: directoryLimits.maxImageBytes, temporaryDirectory: tmpdir()})});
      capturing = true;
      ordinarySdkImages = captureOrdinaryInitialControlPackageCustody(imageInventory, root, process.argv[1],
        undefined, registrations.values());
    }
    const read = (packageName: unknown, selected: ImageFact, kind: 'module' | 'lock') =>
      readVerifiedSdkImage(ordinarySdkImages, packageName, selected.path, selected.cid, kind);
    for (const original of registrations.values()) {
      read(sdkPackage, original.lock, 'lock');
      const sdk = read(original.sdk.packageName, original.sdk, 'module');
      if (sdk.version !== original.sdk.version) fail(invalidSdkRegistration);
      read(sdkPackage, original.adapter, 'module');
    }
    // This closes first selections. Subsequent Hosts may borrow these same
    // namespaces, and a newly requested module fails before registration.
    if (initialize) ordinarySdkImages!.initializeHostNamespace();
    ordinarySdkImages!.assertCurrent();
    if (initialize) ordinaryNativeOriginal = nativeOriginal;
    ordinarySdkPreparations.set(source, freeze({verifiedSdkInstallations: registrations, sdkImageCustody: ordinarySdkImages!}));
  } catch (cause) {
    // Descriptor preflight runs before any hooks or namespace acquisition.
    // An installed-image failure after entering capture remains fail-closed
    // on the default filesystem route, including partial loader activation.
    if (initialize && (ordinarySdkImages !== undefined || (cause as NodeJS.ErrnoException | undefined)?.code !== invalidSdkRegistration)) {
      sdkImageFailure = freeze({cause, blocksOrdinary: capturing});
    }
    throw cause;
  } finally {
    if (initialize) sdkImageStarting = false;
  }
}

function ordinaryModelSdkInstallation(source: unknown) {
  if (sdkImageFailure?.blocksOrdinary) throw sdkImageFailure.cause;
  if (source === undefined) return undefined;
  const selected = ordinarySdkPreparations.get(source as object);
  if (selected === undefined) fail('InitialControlSdkImageUnavailable');
  selected.sdkImageCustody.assertCurrent();
  return selected;
}

function ordinaryLocalFilesNative() {
  if (sdkImageFailure?.blocksOrdinary) throw sdkImageFailure.cause;
  if (ordinaryNativeOriginal === undefined) return undefined;
  const {root, images, limits, load} = ordinaryNativeOriginal;
  // The Store's ordinary acquisition borrows the native owner's exact module.
  // A binary never enters the JavaScript Source resolver or its cache seal.
  return load(root, images, limits, ordinarySdkImages!.assertCurrent).operations;
}

const exported = module.exports = {captureInitialControlPackageCustody, captureOrdinaryInitialControlPackageCustody,
  readVerifiedSdkImage, prepareOrdinaryModelSdkInstallation, ordinaryModelSdkInstallation,
  ordinaryLocalFilesNative};
freeze(module.exports);
export = exported;
