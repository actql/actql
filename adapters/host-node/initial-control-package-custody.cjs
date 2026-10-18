'use strict';

// Private installed-image custody, not an operational issuer. Only the actual
// selected startup may adopt these Sources, namespace and loader originals;
// their complete runtime/intake envelope and bootstrap provenance remain its
// independent responsibility. No caller packet can obtain a scope here.
const NodeModule = require('node:module');
const {createRequire} = NodeModule;
const {dirname, join, isAbsolute} = require('node:path');
const {existsSync, realpathSync} = require('node:fs');
const {captureInitialControlImageSource} = require('./initial-control-image-source.cjs');
const {installInitialControlImageLoader, installOrdinaryInitialControlImageLoader} = require('./initial-control-image-loader.cjs');
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor, hasOwn = Object.hasOwn;
const apply = Reflect.apply, array = Array.isArray, integer = Number.isSafeInteger;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const parse = JSON.parse, NativeMap = Map, NativeSet = Set, NativeError = Error;
const mapGet = Map.prototype.get, mapSet = Map.prototype.set, mapHas = Map.prototype.has;
const setHas = Set.prototype.has, setAdd = Set.prototype.add;
const fail = code => { const cause = new NativeError(code); cause.code = code; throw cause; };
const own = (value, name) => {
  if (value === null || typeof value !== 'object') fail('InvalidInitialControlPackageImage');
  const property = descriptor(value, name);
  if (property === undefined || !hasOwn(property, 'value')) fail('InvalidInitialControlPackageImage');
  return property.value;
};
const optionalField = (value, name) => {
  const property = descriptor(value, name);
  if (property === undefined) return undefined;
  if (!hasOwn(property, 'value')) fail('InvalidInitialControlPackageImage');
  return property.value;
};
const concrete = value => typeof value === 'string' && value.length !== 0 &&
  !isAbsolute(value) && !value.includes('\\') &&
  !value.split('/').some(part => part === '' || part === '.' || part === '..');

function captureInitialControlPackageCustody(inventory, localRoot, consumerEntry, publicPreloadEntry) {
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
function captureOrdinaryInitialControlPackageCustody(inventory, localRoot, consumerEntry, publicDeliveryEntry) {
  if (typeof preloading !== 'function' || apply(preloading, module, []) !== false) {
    fail('InitialControlPackageCustodyUnavailable');
  }
  return capturePackageCustody(inventory, localRoot, consumerEntry, publicDeliveryEntry, true);
}

function capturePackageCustody(inventory, localRoot, consumerEntry, publicPreloadEntry, ordinary) {
  const root = realpathSync(localRoot), images = own(inventory, 'images');
  const packages = own(inventory, 'packages'), dependencies = own(inventory, 'dependencies');
  const hostModule = own(inventory, 'hostModule'), hostValidator = own(inventory, 'hostValidator');
  const localPublicModule = own(inventory, 'localPublicModule');
  const publicNode = own(inventory, 'publicNode'), publicNodeCoverage = own(inventory, 'publicNodeCoverage');
  if (!array(images) || !array(packages) || !array(dependencies) ||
      hostModule !== 'adapters/host-node/embedded-local.mjs' ||
      localPublicModule !== 'index.mjs' ||
      hostValidator !== 'assertInitialControlHostPreparation') fail('InvalidInitialControlPackageImage');
  const groups = [], actualPackages = [], roots = new NativeMap(), mainSources = new NativeMap();
  function captureGroup(directory, facts, expectedName, expectedVersion, expectedReleaseVersion, expectedRepresentation) {
    if (!array(facts) || facts.length === 0) fail('InvalidInitialControlPackageImage');
    const selected = [], names = new NativeSet();
    let manifest, representation;
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
    groups[groups.length] = freeze({root: directory, images: freeze(selected)});
    return {manifest, representation};
  }
  const local = captureGroup(root, images, '@actql/local-node', optionalField(inventory, 'localVersion'),
    optionalField(inventory, 'localReleaseVersion'));
  function resolvePackage(name, from) {
    const originalRequire = createRequire(join(from, 'package.json'));
    let entry;
    try { entry = originalRequire.resolve(name); }
    catch (cause) {
      if (cause.code !== 'MODULE_NOT_FOUND' && cause.code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') throw cause;
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
  function captureDependency(binding, from) {
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
  if (optionalCoverage === 'prepared') {
    if (typeof consumerEntry !== 'string' || !isAbsolute(consumerEntry)) {
      fail('InvalidInitialControlPackageImage');
    }
    // The actual startup resolves its optional SDK from that SAME consumer
    // entry, not from Local's potentially different nested dependency slot.
    captureDependency({name: '@actql/provider-ai-sdk', package: optional}, dirname(consumerEntry));
  } else if (optional !== null || optionalCoverage !== 'absent' && optionalCoverage !== 'unprepared') {
    fail('InvalidInitialControlPackageImage');
  }
  let nodeRoot;
  const unselectedPublicPackages = new NativeSet();
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
    function publicDependency(binding, from) {
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
    function markUnselected(binding) {
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
  const loader = ordinary ? installOrdinaryInitialControlImageLoader(groups) : installInitialControlImageLoader(groups);
  const originalRequire = createRequire(join(root, 'package.json'));
  let namespace, publicNamespaces, initialized = false;
  function initializeHostNamespace() {
    if (apply(preloading, module, []) !== !ordinary) fail('InitialControlPackageCustodyUnavailable');
    loader.assertCurrent();
    if (initialized) return namespace;
    // Actual Source delivery precedes this compilation. Do not capture a
    // mutable pathname later or initialize a replacement caller namespace.
    const loaded = originalRequire(join(root, hostModule));
    if (typeof descriptor(loaded, hostValidator)?.value !== 'function') {
      fail('InitialControlPackageImageChanged');
    }
    // Compile both actual public ESM namespaces before the Module handoff.
    // Later entry imports must reuse these same originals, not pathname bytes
    // that can change after the Host namespace was initialized.
    // Ordinary public facades are already being linked by Node when their
    // private prefix runs. Do not synchronously re-require that same in-flight
    // ESM graph. Their fixed prefix belongs to its separate ordinary bootstrap
    // responsibility; covered Host/dependencies are delivered by this loader.
    const localNamespace = ordinary ? undefined : originalRequire(join(root, localPublicModule));
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
  function readAsset(path) {
    assertCurrent();
    if (typeof path !== 'string') fail('InitialControlPackageCustodyUnavailable');
    return apply(mapGet, mainSources, [path])?.source;
  }
  // Held Sources, module/namespace records, loader hooks and caches remain the
  // original process/module lifetime, including escaped Strings. This table
  // issues no scope and has no synthetic close/GC/capacity acknowledgement.
  return freeze({initializeHostNamespace, assertCurrent, readAsset});
}

module.exports = {captureInitialControlPackageCustody, captureOrdinaryInitialControlPackageCustody};
freeze(module.exports);
