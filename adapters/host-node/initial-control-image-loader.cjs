'use strict';

// Private loader custody, not an operational admission. Only the original
// selected preload can adopt its independently captured, complete image graph.
// Calling this helper from another preload cannot add an initial-control scope
// to that Owner, supply a missing domain or issue capacity/permission.
const NodeModule = require('node:module');
const {join} = require('node:path');
const {realpathSync} = require('node:fs');
const {pathToFileURL, fileURLToPath} = require('node:url');
const nativeApply = Reflect.apply;
const descriptor = Object.getOwnPropertyDescriptor, hasOwn = Object.hasOwn;
const freeze = Object.freeze, defineProperty = Object.defineProperty;
const NativeError = Error, NativeMap = Map, parse = JSON.parse;
const nativeMapGet = Map.prototype.get, nativeMapSet = Map.prototype.set, nativeMapHas = Map.prototype.has;
const isArray = Array.isArray, safeInteger = Number.isSafeInteger;
const nativeStartsWith = String.prototype.startsWith, nativeEndsWith = String.prototype.endsWith;
const preloading = descriptor(NodeModule.prototype, 'isPreloading')?.get;
const registerHooks = NodeModule.registerHooks, register = NodeModule.register;
const stockLoad = NodeModule._load, stockCache = NodeModule._cache;
const syncBuiltinESMExports = NodeModule.syncBuiltinESMExports;
const fail = code => { const error = new NativeError(code); error.code = code; throw error; };
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
  if (!isArray(groups) || groups.length === 0) fail('InvalidInitialControlLoaderImage');
  const images = new NativeMap(), prefixes = [];
  const initialCache = new NativeMap(), delivered = new NativeMap();
  let invalidated = false;
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
  }
  function covered(url) {
    if (typeof url !== 'string') return false;
    for (let index = 0; index < prefixes.length; index++) if (starts(url, prefixes[index])) return true;
    return false;
  }
  function resolve(specifier, context, nextResolve) {
    if (covered(context.parentURL)) assertCurrent();
    const result = nextResolve(specifier, context);
    if (covered(result.url)) {
      assertCurrent();
      const original = nativeApply(nativeMapGet, images, [result.url]);
      if (original === undefined) fail('UncapturedInitialControlImage');
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
    // Preserve Node's API result but make this selected loader permanently
    // unavailable BEFORE another hook can intercept a covered import. Even if
    // that hook is later deregistered, it cannot restore this original history.
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
  return freeze({assertCurrent});
}

module.exports = {installInitialControlImageLoader};
freeze(module.exports);
