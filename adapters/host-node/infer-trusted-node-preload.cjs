'use strict';

// Private selected startup, not an application-time trust factory. Node runs
// this exact module in its real --require preload phase BEFORE entry imports.
// Ordinary embedded processes importing it later retain no startup original.
const {Buffer} = require('node:buffer');
const {Readable} = require('node:stream');
const originalProcess = require('node:process');
const associations = new WeakMap();
const generations = new WeakSet();
let originalSupplier;

const unavailable = () => {
  throw Object.assign(new TypeError('InferTrustedStartupUnavailable'),
    {code: 'InferTrustedStartupUnavailable'});
};
const changed = () => {
  throw Object.assign(new TypeError('InferTrustedStartupChanged'),
    {code: 'InferTrustedStartupChanged'});
};

// Loader provenance plus a single selected startup recipe, not current
// poolSize/version alone. Reject other prior preload/import/loader selections.
const selected = module.isPreloading === true &&
  originalProcess.execArgv.length === 2 &&
  originalProcess.execArgv[0] === '--require' &&
  originalProcess.execArgv[1] === __filename &&
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
  require('node:tls');
  // This opt-in physical startup keeps the selected allocator/pool premise
  // invariant, rather than trying to infer historical slabs at Host.open().
  // It is not a language restriction or a default for existing processes.
  const originals = [
    [Buffer, 'poolSize'], [Buffer, 'alloc'], [Buffer, 'allocUnsafe'], [Buffer, 'allocUnsafeSlow'],
    [Buffer, 'from'], [Buffer, 'concat'],
    [Readable.prototype, 'read'], [Readable.prototype, 'push'],
    [Readable.prototype, 'unshift'], [Socket.prototype, 'read'],
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
  // The actual process/module/native responsibility stays with this startup.
  // These originals and the existing Host overlap still need funded coverage.
  startup = {process: originalProcess, module, entry: originalProcess.argv[1], originals,
    invalidated: false};
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
}

function current(view, host, generation) {
  currentStartup();
  const held = associations.get(view);
  if (held === undefined || held.retired || held.host !== host ||
      held.generation !== generation || held.original.retired) unavailable();
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
      retired: false};
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
    }
    // Only back-reference retirement; no native/process/physical-stop ACK.
  },
});
