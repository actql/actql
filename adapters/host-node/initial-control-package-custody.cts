'use strict';

type ImageSource = ReturnType<typeof import('./initial-control-image-source.cjs').captureInitialControlImageSource>;
type ImageDependency = Readonly<{name: string; root: string}>;
type ImageGroup = Readonly<{
  root: string;
  name: string;
  images: readonly Readonly<{path: string; captured: ImageSource}>[];
  version: unknown;
  dependencies: readonly ImageDependency[];
}>;
type ImageFact = Readonly<{packageName: unknown; version: unknown; path: unknown; cid: unknown}>;
type ExternalPackage = Readonly<{
  name: string; version: string;
  images: readonly Readonly<{path: string; bytes: number; sha256: string}>[];
  dependencies: readonly Readonly<{name: string; package: number}>[];
}>;
type SdkImageRegistration = Readonly<{
  adapter: ImageFact;
  lock: ImageFact;
  sdk: ImageFact;
  packageImages?: readonly ExternalPackage[];
}>;
type SdkCapabilitySupport = 'supported' | 'experimental' | 'unsupported' | 'unavailable';
type SdkRoute = Readonly<{
  selector: string; modelId: string; apiMode: string; endpoint: string;
  structuredCapability: Readonly<{operation: 'structured_generate'; adapter: SdkCapabilitySupport; model: SdkCapabilitySupport}>;
  providerOptions: unknown;
  credential?: Readonly<{reference: unknown; header: unknown}>;
}>;
type SdkRegistration = SdkImageRegistration & Readonly<{
  providerId: string; defaultSelector: string; routes: readonly SdkRoute[];
}>;
type VerifiedSdkImages = Readonly<{adapter: unknown; sdk: unknown}>;
type ImageCustody = ReturnType<typeof capturePackageCustody>;
type SelectedSdkInstallation = Readonly<{
  verifiedSdkInstallations: ReadonlyMap<string, SdkRegistration>;
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
  (registration: SdkImageRegistration) => VerifiedSdkImages>();
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
  const groups: ImageGroup[] = [], actualPackages: string[] = [], groupDependencies = new NativeMap<string, ImageDependency[]>(),
    mainSources = new NativeMap<string, ImageSource>(), capturedGroups = new NativeMap<string, ImageGroup>(),
    manifests = new NativeMap<string, unknown>();
  function captureGroup(directory: string, facts: unknown, expectedName: string, expectedVersion: unknown,
    expectedReleaseVersion: unknown, expectedRepresentation?: ImageSource['representation'], external = false) {
    if (apply(mapHas, groupDependencies, [directory])) fail('InitialControlPackageImageChanged');
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
      const filename = join(directory, path);
      if (external && (path.split('/').includes('node_modules') || realpathSync(filename) !== filename)) {
        fail('InitialControlPackageImageChanged');
      }
      const captured = captureInitialControlImageSource(filename, fact);
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
    const dependencies: ImageDependency[] = [];
    apply(mapSet, groupDependencies, [directory, dependencies]);
    const group = freeze({root: directory, name: expectedName, images: freeze(selected),
      version: optionalField(manifest, 'version'), dependencies});
    groups[groups.length] = group;
    apply(mapSet, capturedGroups, [directory, group]);
    apply(mapSet, manifests, [directory, manifest]);
    return {manifest, representation};
  }
  const local = captureGroup(root, images, '@actql/local-node', optionalField(inventory, 'localVersion'),
    optionalField(inventory, 'localReleaseVersion'));
  function resolvePackage(name: string, from: string, missing?: true): string | undefined {
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
      if (missing) return undefined;
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
  function bindEdge(importer: string, name: string, root: string, append: boolean) {
    const edges = apply(mapGet, groupDependencies, [importer]) as ImageDependency[];
    const previous = edges.find(edge => edge.name === name);
    if (previous === undefined && append) edges[edges.length] = freeze({name, root});
    else if (previous?.root !== root) fail('InitialControlPackageImageChanged');
  }
  function sharesCapturedImages(held: ImageGroup, facts: readonly unknown[]) {
    if (held.images.length !== facts.length) return false;
    const directories = new NativeMap<string, ImageSource>();
    for (const image of held.images) apply(mapSet, directories, [image.path, image.captured]);
    return facts.every(fact => {
      const captured = apply(mapGet, directories, [own(fact, 'path')]) as ImageSource | undefined;
      return captured !== undefined && captured.bytes === own(fact, 'bytes') && captured.sha256 === own(fact, 'sha256');
    });
  }
  function captureDependency(binding: unknown, from: string, importer: string | undefined,
    graph = packages, actual = actualPackages, external = false, append = true): string {
    const name = own(binding, 'name'), index = own(binding, 'package');
    if (typeof name !== 'string' || !integer(index) || index < 0 || index >= graph.length) {
      fail('InvalidInitialControlPackageImage');
    }
    const selected = graph[index];
    if (own(selected, 'name') !== name) fail('InvalidInitialControlPackageImage');
    const directory = resolvePackage(name, from);
    if (directory === undefined) fail('InitialControlPackageImageChanged');
    if (importer !== undefined) bindEdge(importer, name, directory, append);
    const previous = actual[index];
    if (previous !== undefined) {
      if (previous !== directory) fail('InitialControlPackageImageChanged');
      return directory;
    }
    actual[index] = directory;
    const facts = own(selected, 'images'), next = own(selected, 'dependencies');
    if (!array(next) || !array(facts)) fail('InvalidInitialControlPackageImage');
    const held = apply(mapGet, capturedGroups, [directory]) as ImageGroup | undefined;
    if (held === undefined) {
      captureGroup(directory, facts, name, own(selected, 'version'),
        optionalField(selected, 'releaseVersion'), local.representation, external);
    } else if (!external || held.name !== name || held.version !== own(selected, 'version') ||
        held.dependencies.length !== next.length || !sharesCapturedImages(held, facts)) {
      fail('InitialControlPackageImageChanged');
    }
    for (let item = 0; item < next.length; item++) captureDependency(next[item], directory, directory, graph, actual, external, held === undefined);
    return directory;
  }
  for (let index = 0; index < dependencies.length; index++) captureDependency(dependencies[index], root, root);
  const optional = own(inventory, 'optionalSdk'), optionalCoverage = own(inventory, 'optionalSdkCoverage');
  const sdkAdapterRoots = new NativeMap<string, string>();
  const sdkRegistrations = initialSdkRegistrations === undefined ? undefined : [...initialSdkRegistrations];
  const requiresBundled = sdkRegistrations === undefined ||
    sdkRegistrations.some(registration => registration.adapter.packageName === sdkPackage);
  const selectedConsumer = () => {
    if (typeof consumerEntry !== 'string' || !isAbsolute(consumerEntry)) fail('InvalidInitialControlPackageImage');
    return dirname(consumerEntry);
  };
  let bundled = false;
  if (optionalCoverage === 'prepared') {
    const consumer = selectedConsumer();
    // The existing public registration port also owns the stock transport
    // and its parsers. Keep that exact closure when present, even when the
    // application selects an independently installed adapter.
    bundled = requiresBundled || resolvePackage(sdkPackage, consumer, true) !== undefined;
    if (bundled) {
      const directory = captureDependency({name: sdkPackage, package: optional}, consumer, undefined);
      apply(mapSet, sdkAdapterRoots, [sdkPackage, directory]);
    }
  } else if (optional !== null || optionalCoverage !== 'absent' && optionalCoverage !== 'unprepared') {
    fail('InvalidInitialControlPackageImage');
  }
  let nodeRoot: string | undefined;
  const unselectedPackages = new NativeSet<number>();
  function markUnselected(binding: unknown) {
    const name = own(binding, 'name');
    const index = own(binding, 'package');
    if (!integer(index) || index < 0 || index >= packages.length ||
        own(packages[index], 'name') !== name) fail('InvalidInitialControlPackageImage');
    if (apply(setHas, unselectedPackages, [index])) return;
    apply(setAdd, unselectedPackages, [index]);
    const children = own(packages[index], 'dependencies');
    if (!array(children)) fail('InvalidInitialControlPackageImage');
    for (let item = 0; item < children.length; item++) markUnselected(children[item]);
  }
  if (!bundled && optionalCoverage === 'prepared') markUnselected({name: sdkPackage, package: optional});
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
        const edges = apply(mapGet, groupDependencies, [from]) as ImageDependency[];
        edges[edges.length] = freeze({name, root});
        localBound = true;
        return;
      }
      captureDependency(binding, from, from);
    }
    // For Local-only delivery the optional parent facade is not acquired.
    // Its graph may contain additional Source facts, never usable coverage of
    // an unloaded Node facade. Validate their reachability without loading it.
    function markPublicDependency(binding: unknown) {
      if (own(binding, 'name') === '@actql/local-node') {
        if (own(binding, 'local') !== true) fail('InvalidInitialControlPackageImage');
        localBound = true;
      } else markUnselected(binding);
    }
    for (let index = 0; index < next.length; index++) {
      if (nodeRoot === undefined) markPublicDependency(next[index]);
      else publicDependency(next[index], nodeRoot);
    }
    if (!localBound) fail('InvalidInitialControlPackageImage');
  } else if (publicNode !== null || publicNodeCoverage !== 'absent' && publicNodeCoverage !== 'unprepared') {
    fail('InvalidInitialControlPackageImage');
  }
  if (publicPreloadEntry !== undefined && nodeRoot === undefined) fail('InitialControlPublicNodeUnavailable');
  for (let index = 0; index < packages.length; index++) {
    if (actualPackages[index] === undefined && !apply(setHas, unselectedPackages, [index])) {
      fail('InvalidInitialControlPackageImage');
    }
  }
  if (!apply(mapHas, mainSources, [hostModule]) || !apply(mapHas, mainSources, [localPublicModule])) {
    fail('InvalidInitialControlPackageImage');
  }
  const externalGraphs = new NativeMap<string, readonly ExternalPackage[]>();
  for (const registration of sdkRegistrations ?? []) {
    const {packageImages, adapter} = registration;
    if (packageImages === undefined) continue;
    const first = packageImages[0];
    if (first === undefined || first.name !== adapter.packageName || first.version !== adapter.version || first.name === sdkPackage) {
      fail(invalidSdkRegistration);
    }
    const previous = apply(mapGet, externalGraphs, [first.name]);
    if (previous !== undefined) {
      if (previous !== packageImages) fail(invalidSdkRegistration);
      continue;
    }
    const actual: string[] = [];
    const directory = captureDependency({name: first.name, package: 0}, selectedConsumer(), undefined, packageImages, actual, true);
    if (packageImages.some((_, index) => actual[index] === undefined)) fail(invalidSdkRegistration);
    validateExternalLock(registration, packageImages, actual);
    apply(mapSet, externalGraphs, [first.name, packageImages]);
    apply(mapSet, sdkAdapterRoots, [first.name, directory]);
  }
  function validateExternalLock(registration: SdkImageRegistration, graph: readonly ExternalPackage[], actual: readonly string[]) {
    const {lock} = registration;
    const adapterGroup = apply(mapGet, capturedGroups, [actual[0]]) as ImageGroup;
    const original = adapterGroup.images.find(image => image.path === 'npm-shrinkwrap.json');
    if (lock.packageName !== graph[0].name || lock.version !== graph[0].version ||
        original === undefined || lock.path !== original.path || lock.cid !== 'sha256:' + original.captured.sha256) fail(invalidSdkRegistration);
    const body: unknown = parse(original.captured.source), records = own(body, 'packages');
    const declared = own(records, '');
    if (own(body, 'lockfileVersion') !== 3 || own(declared, 'name') !== graph[0].name ||
        own(declared, 'version') !== graph[0].version) fail(invalidSdkRegistration);
    const checked = new NativeMap<string, number>();
    function verify(index: number, slot: string) {
      const previous = apply(mapGet, checked, [slot]);
      if (previous !== undefined) {
        if (previous !== index) fail(invalidSdkRegistration);
        return;
      }
      if (checked.size >= graph.length) fail(invalidSdkRegistration);
      apply(mapSet, checked, [slot, index]);
      const selected = graph[index];
      const manifest = apply(mapGet, manifests, [actual[index]]);
      const required = {...optionalField(manifest, 'dependencies') as object,
        ...optionalField(manifest, 'peerDependencies') as object};
      const optional = (optionalField(manifest, 'optionalDependencies') ?? {}) as object;
      const optionalPeer = optionalField(manifest, 'peerDependenciesMeta') as Record<string, {optional?: boolean}> | undefined;
      const record = own(records, slot), name = optionalField(record, 'name');
      if (name !== undefined && name !== selected.name || own(record, 'version') !== selected.version ||
          Object.keys(required).some(name => !hasOwn(optional, name) && optionalPeer?.[name]?.optional !== true &&
            !selected.dependencies.some(edge => edge.name === name))) fail(invalidSdkRegistration);
      const names = new NativeSet<string>();
      for (const edge of selected.dependencies) {
        if ((!hasOwn(required, edge.name) && !hasOwn(optional, edge.name)) || apply(setHas, names, [edge.name])) fail(invalidSdkRegistration);
        apply(setAdd, names, [edge.name]);
        let parent = slot;
        for (;;) {
          const target = parent ? parent + '/node_modules/' + edge.name : 'node_modules/' + edge.name;
          if (hasOwn(records as object, target)) {
            verify(edge.package, target);
            break;
          }
          if (parent === '') fail(invalidSdkRegistration);
          const cut = parent.lastIndexOf('/node_modules/');
          parent = cut < 0 ? '' : parent.slice(0, cut);
        }
      }
    }
    verify(0, '');
  }
  function selectSdkImages(registration: SdkImageRegistration, refusal?: string) {
    const {adapter, sdk, lock} = registration;
    const adapterRoot = apply(mapGet, sdkAdapterRoots, [adapter.packageName]) as string | undefined;
    if (adapterRoot === undefined || apply(mapGet, externalGraphs, [adapter.packageName]) !== registration.packageImages ||
        lock.packageName !== adapter.packageName ||
        lock.version !== adapter.version || lock.path !== 'npm-shrinkwrap.json') {
      fail(refusal ?? 'InitialControlSdkImageUnavailable');
    }
    const adapterGroup = groups.find(value => value.root === adapterRoot)!;
    const sdkEdge = adapterGroup.dependencies.find(edge => edge.name === sdk.packageName);
    if (sdkEdge === undefined) fail(refusal ?? 'InitialControlSdkImageUnavailable');
    const sdkGroup = groups.find(value => value.root === sdkEdge.root)!;
    function select(group: ImageGroup, fact: ImageFact) {
      if (!concrete(fact.path) || typeof fact.cid !== 'string' || !/^sha256:[a-f0-9]{64}$/u.test(fact.cid) ||
          fact.version !== group.version) fail(refusal ?? 'InitialControlPackageImageChanged');
      const image = group.images.find(value => value.path === fact.path);
      if (image === undefined || 'sha256:' + image.captured.sha256 !== fact.cid) {
        fail(refusal ?? 'InitialControlPackageImageChanged');
      }
      return {filename: join(group.root, image.path), sha256: image.captured.sha256};
    }
    select(adapterGroup, lock);
    return {adapter: select(adapterGroup, adapter), sdk: select(sdkGroup, sdk)};
  }
  let requiredModules: string[] | undefined;
  if (sdkRegistrations !== undefined) {
    requiredModules = [];
    for (const registration of sdkRegistrations) {
      const {adapter, sdk} = selectSdkImages(registration, invalidSdkRegistration);
      requiredModules.push(sdk.filename, adapter.filename);
    }
  }
  manifests.clear();
  const loader = ordinary ? installOrdinaryInitialControlImageLoader(groups, requiredModules) :
    installInitialControlImageLoader(groups);
  const originalRequire = createRequire(join(root, 'package.json'));
  let namespace: unknown, publicNamespaces: Readonly<{local: unknown; node: unknown}> | undefined,
    initialized = false, selectedSdk = false;
  function initializeHostNamespace() {
    if (apply(preloading!, module, []) !== !ordinary) fail('InitialControlPackageCustodyUnavailable');
    loader.assertCurrent();
    if (initialized) return namespace;
    if ((selectedSdk || requiredModules !== undefined && bundled) && ordinary) {
      // Compile the fixed optional package entrance with the same selected
      // modules. Its CommonJS dependencies must land before the cache seal.
      const directory = apply(mapGet, sdkAdapterRoots, ['@actql/provider-ai-sdk']) as string;
      const group = groups.find(value => value.root === directory)!;
      const entry = group.images.find(value => value.path === 'index.mjs');
      if (entry === undefined) fail('InitialControlSdkImageUnavailable');
      loader.loadSelectedModule(join(directory, entry.path), entry.captured.sha256);
    }
    if (requiredModules !== undefined && bundled) {
      // The pinned Undici HTTP/1 transport loads these two parser variants
      // lazily. Give both their original verified Source before closing the
      // CommonJS cache, without establishing a socket or invoking an SDK.
      const adapterRoot = apply(mapGet, sdkAdapterRoots, ['@actql/provider-ai-sdk']) as string | undefined;
      const adapterGroup = groups.find(value => value.root === adapterRoot);
      const directory = adapterGroup?.dependencies.find(edge => edge.name === 'undici')?.root;
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
    const nodeNamespace = ordinary || nodeRoot === undefined ? undefined :
      createRequire(join(nodeRoot, 'package.json'))(join(nodeRoot, 'index.mjs'));
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
  function readSdkImages(registration: SdkImageRegistration): VerifiedSdkImages {
    loader.assertCurrent();
    const {adapter, sdk} = selectSdkImages(registration);
    const namespaces = freeze({sdk: loader.loadSelectedModule(sdk.filename, sdk.sha256),
      adapter: loader.loadSelectedModule(adapter.filename, adapter.sha256)});
    if (!initialized && registration.adapter.packageName === sdkPackage) selectedSdk = true;
    loader.assertCurrent();
    return namespaces;
  }
  // Held Sources, module/namespace records, loader hooks and caches remain the
  // original process/module lifetime, including escaped Strings. This table
  // issues no scope and has no synthetic close/GC/capacity acknowledgement.
  const custody = freeze({initializeHostNamespace, assertCurrent, readAsset});
  apply(sdkImageSet, sdkImages, [custody, readSdkImages]);
  return custody;
}

function readVerifiedSdkImages(custody: unknown, registration: SdkImageRegistration) {
  const read = apply(sdkImageGet, sdkImages, [custody]) as
    ((original: SdkImageRegistration) => VerifiedSdkImages) | undefined;
  if (read === undefined) fail('InitialControlSdkImageUnavailable');
  return read(registration);
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
  function frozenList(value: unknown, maximum: number): readonly unknown[] {
    if (!array(value) || nodeTypes.isProxy(value) || !Object.isFrozen(value) ||
        Object.getPrototypeOf(value) !== Array.prototype || value.length > maximum ||
        Reflect.ownKeys(value).length !== value.length + 1) fail(invalidSdkRegistration);
    for (let index = 0; index < value.length; index++) {
      const member = descriptor(value, index);
      if (!member?.enumerable || !hasOwn(member, 'value')) fail(invalidSdkRegistration);
    }
    return value;
  }
  const closures = new Map<unknown, unknown>();
  const externalPackages: ExternalPackage[] = [];
  const previous = ordinarySdkPreparations.get(source);
  if (previous !== undefined) {
    previous.sdkImageCustody.assertCurrent();
    return;
  }
  // The same recipe funds caller DATA and combined installed Sources.
  const envelope = declareOrdinaryInitialControlPhaseEnvelope(getHeapStatistics().heap_size_limit);
  const {limits} = envelope;
  let remainingImages = limits.imageFiles, remainingEdges = limits.dependencyEdges;
  const registrations = new Map<string, SdkRegistration>();
  const knownSupport = ['supported', 'experimental', 'unsupported', 'unavailable'];
  let remainingRoutes = 64;
  for (let index = 0; index < source.length; index++) {
    const field = Object.getOwnPropertyDescriptor(source, index);
    if (field === undefined || !Object.hasOwn(field, 'value')) fail(invalidSdkRegistration);
    const original: unknown = field.value;
    data(original, ['providerId', 'adapter', 'sdk', 'lock', 'defaultSelector', 'routes'], ['packageImages']);
    data(original.adapter, ['path', 'cid', 'packageName', 'version']);
    data(original.sdk, ['path', 'cid', 'packageName', 'version', 'exportName']);
    data(original.lock, ['path', 'cid', 'packageName', 'version']);
    const id = original.providerId;
    if (typeof id !== 'string' || id.length === 0 || id.length > 256 || registrations.has(id)) {
      fail(invalidSdkRegistration);
    }
    const selectors = new Set<string>();
    const routes = frozenList(original.routes, remainingRoutes);
    for (const route of routes) {
      data(route, ['selector', 'modelId', 'apiMode', 'endpoint', 'structuredCapability', 'providerOptions'], ['credential']);
      if (Object.hasOwn(route, 'credential')) data(route.credential, ['reference', 'header']);
      if (typeof route.selector !== 'string' || route.selector.length === 0 || route.selector.length > 256 ||
          selectors.has(route.selector)) fail(invalidSdkRegistration);
      selectors.add(route.selector);
      const capability = route.structuredCapability;
      data(capability, ['operation', 'adapter', 'model']);
      if (capability.operation !== 'structured_generate' ||
          typeof capability.adapter !== 'string' || !knownSupport.includes(capability.adapter) ||
          typeof capability.model !== 'string' || !knownSupport.includes(capability.model)) fail(invalidSdkRegistration);
    }
    if (typeof original.defaultSelector !== 'string' || !selectors.has(original.defaultSelector)) fail(invalidSdkRegistration);
    remainingRoutes -= routes.length;
    if (Object.hasOwn(original, 'packageImages')) {
      const adapterName = original.adapter.packageName, graph = original.packageImages;
      const admitted = closures.get(adapterName);
      if (admitted === undefined) {
        const selected = frozenList(graph, limits.packages - externalPackages.length);
        if (selected.length === 0 || adapterName === sdkPackage) fail(invalidSdkRegistration);
        for (const item of selected) {
          data(item, ['name', 'version', 'images', 'dependencies']);
          if (typeof item.name !== 'string' || !/^(?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*$/u.test(item.name) ||
              item.name.length > 214 || typeof item.version !== 'string' || item.version.length === 0 ||
              item.version.length > 256) fail(invalidSdkRegistration);
          const paths = new Set();
          for (const image of frozenList(item.images, remainingImages)) {
            data(image, ['path', 'bytes', 'sha256']);
            if (!concrete(image.path) || image.path.length > limits.pathCodeUnits || paths.has(image.path) ||
                !integer(image.bytes) || image.bytes < 0 || typeof image.sha256 !== 'string' ||
                !/^[a-f0-9]{64}$/u.test(image.sha256)) fail(invalidSdkRegistration);
            paths.add(image.path);
            remainingImages--;
          }
          const names = new Set();
          for (const edge of frozenList(item.dependencies, remainingEdges)) {
            data(edge, ['name', 'package']);
            if (typeof edge.name !== 'string' || names.has(edge.name) || !integer(edge.package) ||
                edge.package < 0 || edge.package >= selected.length) fail(invalidSdkRegistration);
            names.add(edge.name);
            remainingEdges--;
          }
          externalPackages.push(item as ExternalPackage);
        }
        closures.set(adapterName, graph);
      } else if (admitted !== graph) fail(invalidSdkRegistration);
    } else if (original.adapter.packageName !== sdkPackage) fail(invalidSdkRegistration);
    registrations.set(id, original as unknown as SdkRegistration);
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
      const {imageInventory} = require('./initial-control-package-original.cjs') as
        {imageInventory?: Readonly<{optionalSdkCoverage?: unknown}>};
      if (imageInventory === undefined || [...registrations.values()].some(original =>
          original.adapter.packageName === sdkPackage) && imageInventory.optionalSdkCoverage !== 'prepared') {
        fail('InitialControlSdkImageUnavailable');
      }
      const runtime = Object.freeze({node: process.versions.node, v8: process.versions.v8,
        openssl: process.versions.openssl, platform: process.platform, arch: process.arch,
        eager: false, libraries: Object.freeze({...process.versions})});
      inspectOrdinaryInitialControlPhaseEnvelope(imageInventory, envelope, runtime, externalPackages);
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
    for (const original of registrations.values()) {
      readVerifiedSdkImages(ordinarySdkImages, original);
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
  readVerifiedSdkImages, prepareOrdinaryModelSdkInstallation, ordinaryModelSdkInstallation,
  ordinaryLocalFilesNative};
freeze(module.exports);
export = exported;
