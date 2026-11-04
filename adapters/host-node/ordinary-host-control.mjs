import {openSync, fstatSync, readSync, closeSync} from 'node:fs';
import {resolve, relative, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {snapshotHostCapacityPolicy, snapshotHostLookupExecutionPolicy}
  from './installed-host-policy.mjs';

// Ordinary in-process initialization trusts the supported platform and caller.
// This registry retains Host-owned configuration and explicit cleanup, not a
// sandbox, a startup provenance issuer, a numerical pool or business authority.
const scopes = new WeakMap();
const packageRoot = fileURLToPath(new URL('../../', import.meta.url));
const fail = code => {throw Object.assign(new Error(code), {code});};
const names = ['host', 'installation', 'generation', 'supplier', 'moduleLifetime'];

function copyOwnValues(value) {
  // Retain copied own configuration, not a live caller prototype. In
  // particular, a field absent at the synchronous snapshot cannot appear
  // through an inherited getter during initialization's await.
  const result = Object.create(null);
  for (const name of Reflect.ownKeys(value)) {
    const property = Object.getOwnPropertyDescriptor(value, name);
    // Documented trusted getters are evaluated once, before any await. Keep
    // unknown fields for the existing semantic validator; do not drop them.
    const supplied = value[name];
    const field = name === 'hostCapacityPolicy' ? snapshotHostCapacityPolicy(supplied)
      : name === 'hostLookupExecutionPolicy' ? snapshotHostLookupExecutionPolicy(supplied) : supplied;
    Object.defineProperty(result, name, {value: ['consentRefs', 'runners', 'sourceProfilePaths', 'effectProfilePaths'].includes(name) &&
      Array.isArray(field) ? Object.freeze([...field]) : field, enumerable: property.enumerable,
      writable: false, configurable: false});
  }
  return result;
}

function snapshot(input) {
  if (input === undefined) return Object.freeze({});
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    fail('InvalidConnectionOptions');
  }
  const value = copyOwnValues(input);
  const installation = Object.getOwnPropertyDescriptor(value, 'installation');
  if (installation?.value !== undefined && installation.value !== null &&
      typeof installation.value === 'object' && !Array.isArray(installation.value)) {
    const selected = copyOwnValues(installation.value);
    const replacements = {
      hostCapacityPolicy: snapshotHostCapacityPolicy(selected.hostCapacityPolicy),
      hostLookupExecutionPolicy: snapshotHostLookupExecutionPolicy(selected.hostLookupExecutionPolicy),
    };
    const copied = Object.create(null);
    for (const name of Reflect.ownKeys(selected)) {
      Object.defineProperty(copied, name, {value: Object.hasOwn(replacements, name)
        ? replacements[name] : selected[name], enumerable: Object.getOwnPropertyDescriptor(selected, name).enumerable});
    }
    const packet = Object.create(null);
    for (const name of Reflect.ownKeys(value)) {
      Object.defineProperty(packet, name, {value: name === 'installation' ? Object.freeze(copied) : value[name],
        enumerable: Object.getOwnPropertyDescriptor(value, name).enumerable});
    }
    return Object.freeze(packet);
  }
  return Object.freeze(value);
}

function stateFor(scope, originals, allowClosing = false) {
  const state = scopes.get(scope);
  if (state === undefined || state.closed || !allowClosing && state.closing ||
      names.some(name => originals?.[name] !== state.originals[name])) fail('InstalledHostPreparationChanged');
  return state;
}

function observation(state) {
  return Object.freeze({pending: !state.closed,
    retainedPreparations: state.children.size, pendingFileClose: state.fileCloseUnknown});
}

async function close(state) {
  if (state.closed) return observation(state);
  if (state.flight !== undefined) return state.flight;
  state.closing = true;
  const flight = Promise.resolve().then(async () => {
    if (state.fileCloseUnknown) return observation(state);
    for (const child of state.children.values()) {
      if (child.handle !== undefined && !child.acknowledged) {
        // Retry only the same explicit object cleanup, never a consumed
        // numeric close. Currentness is not required for original cleanup.
        try {await Reflect.apply(child.retry, child.handle, []);} catch {}
        const result = Reflect.apply(child.status, child.handle, []);
        const pending = result !== null && typeof result === 'object'
          ? Object.getOwnPropertyDescriptor(result, 'pending') : undefined;
        child.acknowledged = pending !== undefined && Object.hasOwn(pending, 'value') && pending.value === false;
      }
      if (!child.released || !child.acknowledged) return observation(state);
    }
    state.children.clear(); state.assets.clear(); state.input = undefined;
    state.closed = true; state.originals = undefined;
    return observation(state);
  });
  state.flight = flight;
  try {return await flight;} finally {if (state.flight === flight) state.flight = undefined;}
}

export function beginOrdinaryHostControl(originals, input) {
  if (originals === null || typeof originals !== 'object' || names.some(name => originals[name] === undefined)) {
    fail('InstalledHostPreparationChanged');
  }
  const held = Object.freeze(Object.fromEntries(names.map(name => [name, originals[name]])));
  const state = {originals: held, input: snapshot(input), children: new Map(), assets: new Map(),
    assetCodeUnits: 0, closing: false, closed: false, flight: undefined, fileCloseUnknown: false};
  const scope = Object.freeze({
    retainPreparation(record, cleanupHandle) {
      stateFor(scope, held);
      if (record === null || typeof record !== 'object' && typeof record !== 'function') {
        fail('InstalledHostPreparationChanged');
      }
      let child = state.children.get(record);
      if (child === undefined) {
        if (state.children.size === 64) fail('InstalledHostPreparationLimit');
        child = {record, handle: undefined, acknowledged: true, released: false};
        state.children.set(record, child);
      }
      if (child.released) fail('InstalledHostPreparationChanged');
      if (cleanupHandle !== undefined && child.handle !== cleanupHandle) {
        if (child.handle !== undefined) fail('InstalledHostPreparationChanged');
        child.handle = cleanupHandle; child.acknowledged = false;
        child.status = cleanupHandle.status; child.retry = cleanupHandle.retry;
        if (typeof child.status !== 'function' || typeof child.retry !== 'function') {
          fail('InstalledHostPreparationCleanupPending');
        }
      }
      return child.duty ??= Object.freeze({releaseReferences(original) {
        if (original !== record || state.closed) fail('InstalledHostPreparationChanged');
        child.released = true;
      }});
    },
    status: () => observation(state), close: () => close(state),
  });
  scopes.set(scope, state);
  return scope;
}

export function isOrdinaryHostControl(scope) {return scopes.has(scope);}
export function assertOrdinaryHostControlCurrent(scope, originals) {stateFor(scope, originals);}
export function ordinaryHostControlInput(scope, originals) {return stateFor(scope, originals).input;}

export function readOrdinaryHostAsset(scope, originals, path) {
  const state = stateFor(scope, originals);
  if (typeof path !== 'string' || !path.startsWith('spec/') || path.includes('\0') ||
      isAbsolute(path) || relative(packageRoot, resolve(packageRoot, path)).startsWith('..')) {
    fail('InstalledHostAssetUnavailable');
  }
  if (state.assets.has(path)) return state.assets.get(path);
  if (state.assets.size === 64) fail('InstalledHostAssetLimit');
  const limit = 8 * 1024 * 1024;
  const fd = openSync(resolve(packageRoot, path), 'r');
  let primary, failed = false, output;
  try {
    const info = fstatSync(fd);
    if (!info.isFile() || info.size > limit) fail('InstalledHostAssetUnavailable');
    const chunks = []; let bytes = 0;
    for (;;) {
      const buffer = Buffer.allocUnsafe(Math.min(65536, limit - bytes + 1));
      const count = readSync(fd, buffer, 0, buffer.length, null);
      if (count === 0) break;
      bytes += count;
      if (bytes > limit) fail('InstalledHostAssetUnavailable');
      chunks.push(buffer.subarray(0, count));
    }
    output = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(Buffer.concat(chunks, bytes));
  } catch (cause) {primary = cause; failed = true;}
  // A numeric close is attempted once. Unknown may retain the Host duty,
  // but no retry can close an integer subsequently reused by the process.
  try {closeSync(fd);} catch (cause) {
    state.fileCloseUnknown = true;
    const error = Object.assign(new Error('InstalledHostAssetCleanupPending', {cause: failed ? primary : cause}),
      {code: 'InstalledHostAssetCleanupPending'});
    error.cleanupHandle = Object.freeze({status: () => observation(state), retry: () => close(state)});
    throw error;
  }
  if (failed) throw primary;
  if (output.length > 32 * 1024 * 1024 - state.assetCodeUnits) fail('InstalledHostAssetLimit');
  state.assetCodeUnits += output.length;
  stateFor(scope, originals); state.assets.set(path, output);
  return output;
}
