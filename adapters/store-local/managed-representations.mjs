// Installed managed Store wiring. No old row-CID/row-JSON contract is inferred.
// The registry binds an actual opaque Core material, not a path or digest.
import {randomUUID} from 'node:crypto';
import {localStoreOwnsBody, localRetainedStoreAvailable} from './files.mjs';
import {withVerifiedDelegatedFile} from './direct-file.mjs';
import {snapshotPhysicalManifest} from './managed-manifest.mjs';
const representations = new WeakMap();
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/.test(value);
const issue = code => Object.assign(new Error(code), {code});
const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};
const cleanupState = handle => {
  if (!handle || typeof member(handle, 'status') !== 'function') {
    return Object.freeze({pending: true, errors: Object.freeze([])});
  }
  try {
    const state = handle.status();
    if (!state || typeof state.pending !== 'boolean') {
      return Object.freeze({pending: true, errors: Object.freeze([])});
    }
    return Object.freeze({
      pending: state.pending,
      errors: Object.freeze(Array.isArray(state.errors) ? [...state.errors] : []),
    });
  } catch (error) {
    return Object.freeze({pending: true, errors: Object.freeze([error])});
  }
};

// Transfer input pins only when an inner operation explicitly reports
// unconfirmed native cleanup. Ordinary failures have already stopped using the
// file and release synchronously. The returned failure is Host-owned and never
// requires the original throwable to be mutable or even be an Error.
function retainBorrowsUntilStopped(reason, borrows) {
  const native = member(reason, 'cleanupHandle');
  if (member(reason, 'cleanupPending') !== true) return undefined;
  let released = false;
  const release = () => {
    if (released) return false;
    released = true;
    for (const borrow of borrows) borrow?.confirmStopped();
    return true;
  };
  const initial = cleanupState(native);
  if (!initial.pending) {
    release();
    return undefined;
  }
  const status = () => {
    const state = cleanupState(native);
    return Object.freeze({
      pending: !released,
      errors: state.errors,
    });
  };
  const failure = issue(typeof member(reason, 'code') === 'string'
    ? member(reason, 'code') : 'ManagedInputUseFailed');
  failure.cause = reason;
  failure.primaryFailure = reason;
  failure.cleanupPending = true;
  failure.cleanupErrors = initial.errors;
  failure.cleanupHandle = Object.freeze({
    status,
    async retry() {
      if (released) return status();
      if (typeof member(native, 'retry') !== 'function') return status();
      try { await native.retry(); }
      catch (error) {
        failure.cleanupErrors = Object.freeze([
          ...failure.cleanupErrors, error,
        ]);
      }
      if (!cleanupState(native).pending) release();
      failure.cleanupPending = !released;
      return status();
    },
  });
  return failure;
}

export function registerManagedInput(
  material, readable, store, body, codecContractCid, physicalManifest,
) {
  if (!material || typeof material !== 'object' || representations.has(material) ||
      typeof readable !== 'function' || !localStoreOwnsBody(store, body) || !cid(codecContractCid)) {
    throw issue('InvalidManagedInputRegistration');
  }
  let admitted;
  try {
    admitted = snapshotPhysicalManifest(physicalManifest, {
      maxChunks: 1,
      maxManifestBytes: 1024 * 1024,
      maxReferencedBytes: body.bytes,
    });
  } catch {
    throw issue('InvalidManagedInputRegistration');
  }
  const chunks = admitted.manifest.chunks;
  if (admitted.manifest.codec_contract_cid !== codecContractCid ||
      chunks.length !== 1 || chunks[0].cid !== body.cid ||
      chunks[0].byte_length !== body.bytes ||
      chunks[0].row_count !== admitted.manifest.row_count) {
    throw issue('InvalidManagedInputRegistration');
  }
  representations.set(material, Object.freeze({
    readable,
    store,
    body,
    codecContractCid,
    physicalManifest: admitted,
  }));
  return admitted;
}

// Installed dispatcher lookup for the exact opaque material. This does not
// expose a path, grant a read, or let a callback relabel a representation.
export function managedInputCodecContractCid(material) {
  return representations.get(material)?.codecContractCid;
}

export function managedInputPhysicalManifestCid(material) {
  return representations.get(material)?.physicalManifest.cid;
}

// authorize and beforeRead belong to installed Host use/resource admission,
// never Program options. Availability is not permission or a budget waiver.
// use must await all local/native accesses before settling, even on failure.
export async function withManagedInputFile(material, input, codecContractCid, authorize, use, signal, beforeRead) {
  if (typeof authorize !== 'function' || typeof use !== 'function' ||
      (beforeRead !== undefined && typeof beforeRead !== 'function')) {
    throw issue('InvalidManagedInputUse');
  }
  const admit = () => {
    signal?.throwIfAborted();
    const held = representations.get(material);
    if (!held || input == null || !localRetainedStoreAvailable(held.store) ||
        !held.body.available() || !held.readable(input)) throw issue('ManagedInputUnavailable');
    if (!cid(codecContractCid) || held.codecContractCid !== codecContractCid) throw issue('UnsupportedManagedCodec');
    const chunk = held.physicalManifest.manifest.chunks[0];
    if (chunk.cid !== held.body.cid || chunk.byte_length !== held.body.bytes) {
      throw issue('ManagedInputUnavailable');
    }
    if (authorize(input) !== true) throw issue('ManagedInputUnauthorized');
    if (!held.readable(input)) throw issue('ManagedInputUnavailable');
    return held;
  };
  const held = admit();
  // The Store pins the exact generation before exposing its path, and confirms
  // integrity and release before this function makes a successful return.
  const borrow = held.body.delegateRead(`managed-local-${randomUUID()}`);
  try {
    const result = await withVerifiedDelegatedFile(borrow.descriptor, async file => {
      admit();
      return use(file);
    }, signal, beforeRead === undefined ? undefined : bytes => {
      admit();
      return beforeRead(bytes);
    });
    borrow.verify(result.report);
    admit();
    borrow.confirmStopped();
    return result.value;
  } catch (error) {
    if (['RetainedBodyChanged', 'RetainedBodyTruncated', 'ForeignStoreFile', 'ENOENT'].includes(error?.code)) held.body.close();
    const retained = retainBorrowsUntilStopped(error, [borrow]);
    if (!retained) borrow.confirmStopped();
    throw retained ?? error;
  }
}

// Logical input occurrences retain their independent authorization and view
// checks. Exact duplicate physical bodies share one Store borrow and one
// integrity pass while the callback receives one file occurrence per port.
export async function withManagedInputFiles(
  occurrences, authorize, use, signal, beforeRead,
) {
  if (!Array.isArray(occurrences) || occurrences.length === 0 ||
      typeof authorize !== 'function' || typeof use !== 'function' ||
      (beforeRead !== undefined && typeof beforeRead !== 'function')) {
    throw issue('InvalidManagedInputUse');
  }
  const admit = index => {
    signal?.throwIfAborted();
    const occurrence = occurrences[index];
    if (!occurrence || typeof occurrence !== 'object') {
      throw issue('InvalidManagedInputUse');
    }
    const {material, input, codecContractCid} = occurrence;
    const held = representations.get(material);
    if (!held || input == null || !localRetainedStoreAvailable(held.store) ||
        !held.body.available() || !held.readable(input)) {
      throw issue('ManagedInputUnavailable');
    }
    if (!cid(codecContractCid) || held.codecContractCid !== codecContractCid) {
      throw issue('UnsupportedManagedCodec');
    }
    const chunk = held.physicalManifest.manifest.chunks[0];
    if (chunk.cid !== held.body.cid || chunk.byte_length !== held.body.bytes) {
      throw issue('ManagedInputUnavailable');
    }
    if (authorize(input, index) !== true) {
      throw issue('ManagedInputUnauthorized');
    }
    if (!held.readable(input)) throw issue('ManagedInputUnavailable');
    return held;
  };
  const held = occurrences.map((_, index) => admit(index));
  const unique = [];
  const byBody = new Map();
  for (let index = 0; index < held.length; index++) {
    let entry = byBody.get(held[index].body);
    if (!entry) {
      entry = {held: held[index], indices: [], borrow: undefined, file: undefined};
      byBody.set(held[index].body, entry);
      unique.push(entry);
    } else if (entry.held.store !== held[index].store) {
      throw issue('ManagedInputUnavailable');
    }
    entry.indices.push(index);
  }
  const live = () => {
    for (const entry of unique) {
      if (!localRetainedStoreAvailable(entry.held.store) ||
          !entry.held.body.available()) throw issue('ManagedInputUnavailable');
    }
    for (let index = 0; index < occurrences.length; index++) admit(index);
  };
  async function verify(index) {
    if (index === unique.length) {
      live();
      return use(held.map(value => byBody.get(value.body).file));
    }
    const entry = unique[index];
    let result;
    try {
      result = await withVerifiedDelegatedFile(
        entry.borrow.descriptor,
        async file => {
          live();
          entry.file = file;
          try { return await verify(index + 1); }
          finally { entry.file = undefined; }
        },
        signal,
        beforeRead === undefined
          ? undefined
          : bytes => {
              live();
              return beforeRead(Object.freeze(entry.indices.slice()), bytes);
            },
      );
    } catch (error) {
      if (['RetainedBodyChanged', 'RetainedBodyTruncated',
        'ForeignStoreFile', 'ENOENT'].includes(error?.code)) {
        entry.held.body.close();
      }
      throw error;
    }
    entry.borrow.verify(result.report);
    live();
    return result.value;
  }
  try {
    for (const entry of unique) {
      entry.borrow = entry.held.body.delegateRead(
        `managed-local-${randomUUID()}`,
      );
    }
    const value = await verify(0);
    for (const entry of unique) entry.borrow?.confirmStopped();
    return value;
  } catch (error) {
    const retained = retainBorrowsUntilStopped(
      error, unique.map(entry => entry.borrow),
    );
    if (!retained) {
      for (const entry of unique) entry.borrow?.confirmStopped();
    }
    throw retained ?? error;
  }
}
