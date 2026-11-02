'use strict';

// Private loader custody, not an operational admission. Only the original
// selected preload can adopt its independently captured, complete image graph.
// Calling this helper from another preload cannot add an initial-control scope
// to that Owner, supply a missing domain or issue capacity/permission.
const NodeModule = require('node:module');
const {join} = require('node:path');
const {realpathSync} = require('node:fs');
const {pathToFileURL, fileURLToPath, URL: OriginalURL} = require('node:url');
const nativeApply = Reflect.apply;
const descriptor = Object.getOwnPropertyDescriptor, hasOwn = Object.hasOwn;
const ownKeys = Reflect.ownKeys;
const freeze = Object.freeze, defineProperty = Object.defineProperty;
const prototype = Object.getPrototypeOf, sameValue = Object.is;
const objectPrototype = Object.prototype, arrayPrototype = Array.prototype;
const NativeError = Error, NativeMap = Map, NativeWeakSet = WeakSet, parse = JSON.parse;
const weakHas = WeakSet.prototype.has, weakAdd = WeakSet.prototype.add;
const nativeMapGet = Map.prototype.get, nativeMapSet = Map.prototype.set, nativeMapHas = Map.prototype.has;
const nativeMapEach = Map.prototype.forEach;
const isArray = Array.isArray, safeInteger = Number.isSafeInteger;
const nativeStartsWith = String.prototype.startsWith, nativeEndsWith = String.prototype.endsWith;
const nativeCharCodeAt = String.prototype.charCodeAt, nativeSlice = String.prototype.slice;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const registerHooks = NodeModule.registerHooks, register = NodeModule.register;
const stockLoad = NodeModule._load, stockCache = NodeModule._cache;
const syncBuiltinESMExports = NodeModule.syncBuiltinESMExports;
const fail = (code, image) => {
  const error = new NativeError(code); error.code = code;
  // Only an already-held package-relative image key, never an absolute path
  // or caller data. This diagnostic neither changes refusal nor admits a
  // cache shape. Its retained String alias follows the original error duty.
  if (image !== undefined) error.image = image;
  throw error;
};
const own = (value, name) => {
  if (value === null || typeof value !== 'object') fail('InvalidInitialControlLoaderImage');
  const property = descriptor(value, name);
  if (property === undefined || !hasOwn(property, 'value')) fail('InvalidInitialControlLoaderImage');
  return property.value;
};
const starts = (value, prefix) => nativeApply(nativeStartsWith, value, [prefix]);
const ends = (value, suffix) => nativeApply(nativeEndsWith, value, [suffix]);
const concrete = value => typeof value === 'string' && value.length !== 0 &&
  !starts(value, '/') && !value.split('/').some(part => part === '' || part === '.' || part === '..') &&
  !value.includes('\\');

function installInitialControlImageLoader(groups) {
  // Observe Node's captured real preload getter, not a caller field or argv
  // label. The complete operational supplier still has its independent source,
  // public-wrapper, backend, envelope and original Host checks to perform.
  if (typeof preloading !== 'function' || nativeApply(preloading, module, []) !== true ||
      typeof registerHooks !== 'function' || typeof register !== 'function') {
    fail('InitialControlImageLoaderUnavailable');
  }
  return installImageLoader(groups, false);
}

// Byte/module custody only. This separate ordinary implementation never
// authenticates a startup or issues an installation scope. Its actual package
// prefix must already hold the ordinary runtime/compiler/lifetime original.
function installOrdinaryInitialControlImageLoader(groups) {
  if (typeof preloading !== 'function' || nativeApply(preloading, module, []) !== false ||
      typeof registerHooks !== 'function' || typeof register !== 'function') {
    fail('InitialControlImageLoaderUnavailable');
  }
  return installImageLoader(groups, true);
}

function installImageLoader(groups, ordinary) {
  if (!isArray(groups) || groups.length === 0) fail('InvalidInitialControlLoaderImage');
  const images = new NativeMap(), prefixes = [];
  const initialCache = new NativeMap(), delivered = new NativeMap();
  const loadedModules = [];
  let invalidated = false, loadedCaptured = false;
  for (let index = 0; index < groups.length; index++) {
    const group = groups[index], root = realpathSync(own(group, 'root'));
    const originals = own(group, 'images');
    if (!isArray(originals) || originals.length === 0) fail('InvalidInitialControlLoaderImage');
    const prefix = pathToFileURL(root + '/').href;
    prefixes[prefixes.length] = prefix;
    const manifests = new NativeMap(), records = [];
    for (let item = 0; item < originals.length; item++) {
      const original = originals[item], path = own(original, 'path'), captured = own(original, 'captured');
      const source = own(captured, 'source'), bytes = own(captured, 'bytes'), sha256 = own(captured, 'sha256');
      if (!concrete(path) || typeof source !== 'string' || !safeInteger(bytes) || bytes < 0 ||
          typeof sha256 !== 'string' || sha256.length !== 64) fail('InvalidInitialControlLoaderImage');
      const url = pathToFileURL(join(root, path)).href;
      if (!starts(url, prefix) || nativeApply(nativeMapHas, images, [url])) fail('InvalidInitialControlLoaderImage');
      const value = {url, source, bytes, sha256, path, format: undefined};
      records[records.length] = value;
      // Manifests here are the same captured immutable Sources as code. The
      // format decision cannot change by replacing a pathname after capture.
      if (path === 'package.json' || ends(path, '/package.json')) {
        const manifest = parse(source);
        if (manifest === null || typeof manifest !== 'object' || isArray(manifest)) fail('InvalidInitialControlLoaderImage');
        nativeApply(nativeMapSet, manifests, [path.slice(0, -'package.json'.length), manifest.type]);
      }
      nativeApply(nativeMapSet, images, [url, value]);
    }
    if (!nativeApply(nativeMapHas, manifests, [''])) fail('InvalidInitialControlLoaderImage');
    for (let item = 0; item < records.length; item++) {
      const record = records[item], path = record.path;
      if (ends(path, '.mjs')) record.format = 'module';
      else if (ends(path, '.cjs')) record.format = 'commonjs';
      else if (ends(path, '.json')) record.format = 'json';
      else if (ends(path, '.js')) {
        let at = path.slice(0, path.lastIndexOf('/') + 1);
        while (!nativeApply(nativeMapHas, manifests, [at])) {
          const previous = at.slice(0, -1).lastIndexOf('/');
          at = previous < 0 ? '' : at.slice(0, previous + 1);
        }
        record.format = nativeApply(nativeMapGet, manifests, [at]) === 'module' ? 'module' : 'commonjs';
      }
      freeze(record);
      if (record.format === 'commonjs' || record.format === 'json') {
        const property = descriptor(stockCache, fileURLToPath(record.url));
        if (property !== undefined) {
          if (!hasOwn(property, 'value')) fail('InitialControlImageLoaderChanged');
          nativeApply(nativeMapSet, initialCache, [record.url, property.value]);
        }
      }
    }
  }
  function assertCurrent() {
    if (registration === undefined || invalidated ||
        descriptor(NodeModule, '_load')?.value !== stockLoad ||
        descriptor(NodeModule, '_cache')?.value !== stockCache ||
        descriptor(NodeModule, 'registerHooks')?.value !== registerHooksFence ||
        descriptor(NodeModule, 'register')?.value !== registerFence) fail('InitialControlImageLoaderChanged');
    for (let index = 0; index < loadedModules.length; index++) {
      const held = loadedModules[index], property = descriptor(stockCache, held.filename);
      const exportsProperty = held.module === undefined ? undefined : descriptor(held.module, 'exports');
      let same = held.module === undefined ? property === undefined :
        property !== undefined && hasOwn(property, 'value') && property.value === held.module &&
        exportsProperty !== undefined && hasOwn(exportsProperty, 'value') &&
        exportsProperty.value === held.exports &&
        (held.jsonInterop ? jsonInteropRecord(held.module) :
          descriptor(held.module, 'filename')?.value === held.filename &&
          (descriptor(held.module, 'loaded')?.value === true ||
            held.loading && (ordinary || nativeApply(preloading, module, []) === true)));
      if (same && held.properties !== undefined) {
        const names = ownKeys(held.exports);
        same = names.length === held.properties.length;
        for (let item = 0; same && item < names.length; item++) {
          const original = held.properties[item], current = descriptor(held.exports, names[item]);
          same = names[item] === original.name && current !== undefined &&
            current.enumerable === original.enumerable && current.configurable === original.configurable &&
            hasOwn(current, 'value') === original.data &&
            (original.data ? current.value === original.value && current.writable === original.writable :
              current.get === original.get && current.set === original.set);
        }
      }
      if (!same) { invalidated = true; fail('InitialControlImageLoaderChanged'); }
    }
  }
  function jsonInteropRecord(value) {
    // Node's synchronous ESM JSON translator publishes a completed two-field
    // cache record, not a filename-bearing CommonJS Module. This exact header
    // is accepted ONLY for delivered JSON below, with a same-Source tree check;
    // it cannot authenticate an arbitrary cache preseed or CommonJS record.
    if (value === null || typeof value !== 'object' || prototype(value) !== objectPrototype) return false;
    const names = ownKeys(value);
    if (names.length !== 2 || names[0] !== 'exports' || names[1] !== 'loaded') return false;
    for (let index = 0; index < names.length; index++) {
      const property = descriptor(value, names[index]);
      if (property === undefined || !hasOwn(property, 'value') || property.writable !== true ||
          property.enumerable !== true || property.configurable !== true ||
          names[index] === 'loaded' && property.value !== true) return false;
    }
    return true;
  }
  function sealJsonOriginal(original, exported) {
    // Only selected JSON compiler metadata, not arbitrary CJS exports, library
    // caches or application input. Compare the actual parsed tree with the
    // SAME captured Source before sealing any node. Preserve stock Node's JSON
    // BOM handling without changing the held Source bytes or their identity.
    const source = original.source;
    const expected = parse(nativeApply(nativeCharCodeAt, source, [0]) === 0xfeff
      ? nativeApply(nativeSlice, source, [1]) : source);
    const checks = [{actual: exported, expected}], objects = [], seen = new NativeWeakSet();
    for (let index = 0; index < checks.length; index++) {
      const pair = checks[index], actual = pair.actual, expected = pair.expected;
      if (expected === null || typeof expected !== 'object') {
        if (!sameValue(actual, expected)) fail('InitialControlImageLoaderChanged');
        continue;
      }
      if (actual === null || typeof actual !== 'object' ||
          isArray(actual) !== isArray(expected) ||
          prototype(actual) !== (isArray(expected) ? arrayPrototype : objectPrototype) ||
          nativeApply(weakHas, seen, [actual])) fail('InitialControlImageLoaderChanged');
      nativeApply(weakAdd, seen, [actual]);
      const names = ownKeys(actual), expectedNames = ownKeys(expected);
      if (names.length !== expectedNames.length) fail('InitialControlImageLoaderChanged');
      for (let item = 0; item < names.length; item++) {
        const name = names[item], value = descriptor(actual, name);
        if (name !== expectedNames[item] || value === undefined || !hasOwn(value, 'value')) {
          fail('InitialControlImageLoaderChanged');
        }
        checks[checks.length] = {actual: value.value, expected: descriptor(expected, name).value};
      }
      objects[objects.length] = actual;
    }
    // Native JSON trees have only these original records/arrays and primitive
    // leaves. Never freeze Object/Array prototypes, CJS function graphs or a
    // caller's unrelated objects. The expected parse, pair/keys/descriptor walk,
    // WeakSet and node array overlap the original Module/tree/Source; none is
    // free workspace or an operational admission. Escaped nodes keep lifetime.
    for (let index = 0; index < objects.length; index++) freeze(objects[index]);
  }
  function captureLoadedModules() {
    // Only the original preload can finish this handoff, immediately after its
    // synchronous original namespace initialization and BEFORE entry. A late
    // snapshot cannot authenticate exports that entry may already have changed.
    if (nativeApply(preloading, module, []) !== !ordinary) fail('InitialControlImageLoaderUnavailable');
    assertCurrent();
    if (loadedCaptured) return;
    nativeApply(nativeMapEach, images, [original => {
      if (original.format !== 'commonjs' && original.format !== 'json') return;
      const filename = fileURLToPath(original.url), property = descriptor(stockCache, filename);
      if (property === undefined) {
        loadedModules[loadedModules.length] = {filename, module: undefined};
        return;
      }
      if (!hasOwn(property, 'value') || !nativeApply(nativeMapHas, delivered, [original.url]) &&
          (!nativeApply(nativeMapHas, initialCache, [original.url]) ||
            nativeApply(nativeMapGet, initialCache, [original.url]) !== property.value)) {
        invalidated = true; fail('InitialControlImageLoaderChanged');
      }
      const current = property.value, filenameProperty = descriptor(current, 'filename');
      const exportsProperty = descriptor(current, 'exports'), loadedProperty = descriptor(current, 'loaded');
      const jsonInterop = original.format === 'json' && filenameProperty === undefined &&
        nativeApply(nativeMapHas, delivered, [original.url]) && jsonInteropRecord(current);
      if ((!jsonInterop && filenameProperty?.value !== filename) || exportsProperty === undefined ||
          !hasOwn(exportsProperty, 'value') || typeof loadedProperty?.value !== 'boolean') {
        invalidated = true; fail('InitialControlImageLoaderChanged', original.path);
      }
      const exported = exportsProperty.value;
      if (original.format === 'json') {
        try { sealJsonOriginal(original, exported); }
        catch (cause) { invalidated = true; throw cause; }
      }
      let properties;
      if (exported !== null && (typeof exported === 'object' || typeof exported === 'function')) {
        const names = ownKeys(exported); properties = [];
        for (let index = 0; index < names.length; index++) {
          const name = names[index], value = descriptor(exported, name);
          if (value === undefined) { invalidated = true; fail('InitialControlImageLoaderChanged'); }
          // Copy descriptors without invoking exported getters. Nested exported
          // referents still need their selected library/consumer correspondence;
          // this shallow original is not a universal export-graph certificate.
          properties[properties.length] = {name, data: hasOwn(value, 'value'),
            value: value.value, writable: value.writable, get: value.get, set: value.set,
            enumerable: value.enumerable, configurable: value.configurable};
        }
      }
      // Preexisting bootstrap records have their separate original Source duty.
      // Capturing their identity here never proves their already-executed body.
      loadedModules[loadedModules.length] = {filename, module: current, exports: exported,
        loading: loadedProperty.value === false, jsonInterop, properties};
    }]);
    loadedCaptured = true;
    assertCurrent();
  }
  function covered(url) {
    if (typeof url !== 'string') return false;
    for (let index = 0; index < prefixes.length; index++) if (starts(url, prefixes[index])) return true;
    return false;
  }
  function resolve(specifier, context, nextResolve) {
    if (covered(context.parentURL)) assertCurrent();
    let captured;
    if (typeof specifier === 'string' && (starts(specifier, 'file:') ||
        starts(specifier, './') || starts(specifier, '../') || starts(specifier, '/'))) {
      let url;
      try {url = new OriginalURL(specifier, context.parentURL).href;}
      catch { /* The original Node resolver retains malformed-specifier errors. */ }
      const original = nativeApply(nativeMapGet, images, [url]);
      // Resolve only an exact already-captured file. Native package resolution
      // and all unselected URLs stay with Node. A true synchronous resolution
      // keeps its CJS translator on this original format/Source instead of
      // reclassifying the pathname through a replaced package.json.
      if (original !== undefined) captured = {url, format: original.format, shortCircuit: true};
    }
    const result = captured ?? nextResolve(specifier, context);
    if (covered(result.url)) {
      assertCurrent();
      const original = nativeApply(nativeMapGet, images, [result.url]);
      if (original === undefined) fail('UncapturedInitialControlImage');
      if (loadedCaptured && (original.format === 'commonjs' || original.format === 'json')) {
        const filename = fileURLToPath(original.url);
        let initialized = false;
        for (let index = 0; index < loadedModules.length; index++) {
          const held = loadedModules[index];
          if (held.filename === filename && held.module !== undefined) initialized = true;
        }
        // Node can hand Source to its ESM CJS translator before publishing the
        // new Module cache entry. Refuse here, before that compilation, rather
        // than treating a later current check as pre-entry provenance.
        if (!initialized) { invalidated = true; fail('InitialControlImageLoaderChanged'); }
      }
      if ((original.format === 'commonjs' || original.format === 'json') &&
          !nativeApply(nativeMapHas, delivered, [result.url])) {
        const property = descriptor(stockCache, fileURLToPath(result.url));
        if (property !== undefined && (!hasOwn(property, 'value') ||
            !nativeApply(nativeMapHas, initialCache, [result.url]) ||
            nativeApply(nativeMapGet, initialCache, [result.url]) !== property.value)) {
          invalidated = true;
          fail('InitialControlImageLoaderChanged');
        }
      }
    } else if (covered(context.parentURL) && !starts(result.url, 'node:')) {
      fail('UncapturedInitialControlDependency');
    }
    return result;
  }
  function load(url, context, nextLoad) {
    const original = nativeApply(nativeMapGet, images, [url]);
    if (original === undefined) {
      if (covered(url)) fail('UncapturedInitialControlImage');
      return nextLoad(url, context);
    }
    assertCurrent();
    if (original.format === undefined) fail('UncapturedInitialControlImageDomain');
    // This is only a Source-handoff marker, not module/exports authentication
    // or an operational admission. Full post-load cache and resolver custody
    // must still be joined by the selected preload before adopting this helper.
    nativeApply(nativeMapSet, delivered, [url, true]);
    // These strings are immutable copies of the same-FD Source. Never delegate
    // this body to a mutable pathname, synthesize a FileHandle, or issue an ACK.
    return {format: original.format, source: original.source, shortCircuit: true};
  }
  function registerHooksFence(...args) {
    // Calls through this published fence permanently invalidate this helper,
    // even after deregistration. This does not observe calls through a native
    // registration function retained before installation. The selected startup
    // must independently close that ownership/non-escape boundary; property
    // identity and assertCurrent alone cannot certify all registration history.
    invalidated = true;
    return nativeApply(registerHooks, NodeModule, args);
  }
  function registerFence(...args) {
    invalidated = true;
    return nativeApply(register, NodeModule, args);
  }
  for (const name of ['registerHooks', 'register']) {
    const property = descriptor(NodeModule, name);
    if (property?.value !== (name === 'registerHooks' ? registerHooks : register) ||
        property.writable !== true || property.configurable !== true) fail('InitialControlImageLoaderUnavailable');
  }
  const registration = nativeApply(registerHooks, NodeModule, [{resolve, load}]);
  defineProperty(NodeModule, 'registerHooks', {value: registerHooksFence, writable: false, configurable: false});
  defineProperty(NodeModule, 'register', {value: registerFence, writable: false, configurable: false});
  nativeApply(syncBuiltinESMExports, NodeModule, []);
  // Actual loader registration, held Sources and native module registry remain
  // process/module-lifetime duties. A Host close cannot deregister them, infer
  // source/backing collection or acknowledge a different physical allocation.
  return freeze({assertCurrent, captureLoadedModules});
}

module.exports = {installInitialControlImageLoader, installOrdinaryInitialControlImageLoader};
freeze(module.exports);
