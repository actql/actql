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
const {installInitialControlImageLoader} = require('./initial-control-image-loader.cjs');
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
const concrete = value => typeof value === 'string' && value.length !== 0 &&
  !isAbsolute(value) && !value.includes('\\') &&
  !value.split('/').some(part => part === '' || part === '.' || part === '..');

function captureInitialControlPackageCustody(inventory, localRoot, consumerEntry) {
  // A late caller must not trigger resolution, path reads or descriptor walks.
  // This helper still cannot prove a preload's original source or funding.
  if (typeof preloading !== 'function' || apply(preloading, module, []) !== true) {
    fail('InitialControlPackageCustodyUnavailable');
  }
  const root = realpathSync(localRoot), images = own(inventory, 'images');
  const packages = own(inventory, 'packages'), dependencies = own(inventory, 'dependencies');
  const hostModule = own(inventory, 'hostModule'), hostValidator = own(inventory, 'hostValidator');
  if (!array(images) || !array(packages) || !array(dependencies) ||
      hostModule !== 'adapters/host-node/embedded-local.mjs' ||
      hostValidator !== 'assertInitialControlHostPreparation') fail('InvalidInitialControlPackageImage');
  const groups = [], actualPackages = [], roots = new NativeMap(), mainSources = new NativeMap();
  function captureGroup(directory, facts, expectedName, expectedVersion) {
    if (!array(facts) || facts.length === 0) fail('InvalidInitialControlPackageImage');
    const selected = [], names = new NativeSet();
    let manifest;
    for (let index = 0; index < facts.length; index++) {
      const fact = facts[index], path = own(fact, 'path');
      if (!concrete(path) || apply(setHas, names, [path])) fail('InvalidInitialControlPackageImage');
      apply(setAdd, names, [path]);
      const captured = captureInitialControlImageSource(join(directory, path), fact);
      selected[selected.length] = freeze({path, captured});
      if (directory === root) apply(mapSet, mainSources, [path, captured]);
      if (path === 'package.json') manifest = parse(captured.source);
    }
    if (manifest === undefined || own(manifest, 'name') !== expectedName ||
        expectedVersion !== undefined && own(manifest, 'version') !== expectedVersion) {
      fail('InitialControlPackageImageChanged');
    }
    groups[groups.length] = freeze({root: directory, images: freeze(selected)});
    return manifest;
  }
  captureGroup(root, images, '@actql/local-node');
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
    captureGroup(directory, own(selected, 'images'), name, own(selected, 'version'));
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
  for (let index = 0; index < packages.length; index++) {
    if (actualPackages[index] === undefined) fail('InvalidInitialControlPackageImage');
  }
  if (!apply(mapHas, mainSources, [hostModule])) fail('InvalidInitialControlPackageImage');
  const loader = installInitialControlImageLoader(groups);
  const originalRequire = createRequire(join(root, 'package.json'));
  let namespace, initialized = false;
  function initializeHostNamespace() {
    if (apply(preloading, module, []) !== true) fail('InitialControlPackageCustodyUnavailable');
    loader.assertCurrent();
    if (initialized) return namespace;
    // Actual Source delivery precedes this compilation. Do not capture a
    // mutable pathname later or initialize a replacement caller namespace.
    const loaded = originalRequire(join(root, hostModule));
    if (typeof descriptor(loaded, hostValidator)?.value !== 'function') {
      fail('InitialControlPackageImageChanged');
    }
    loader.captureLoadedModules();
    namespace = loaded;
    initialized = true;
    return namespace;
  }
  function assertCurrent() {
    loader.assertCurrent();
    if (!initialized) fail('InitialControlPackageCustodyUnavailable');
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

module.exports = {captureInitialControlPackageCustody};
freeze(module.exports);
