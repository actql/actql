// Installed managed Store wiring. No old row-CID/row-JSON contract is inferred.
// The registry binds an actual opaque Core material, not a path or digest.
import {randomUUID} from 'node:crypto';
import {localStoreOwnsBody, localRetainedStoreAvailable} from './files.mjs';
import {withVerifiedDelegatedFile} from './direct-file.mjs';
const representations = new WeakMap();
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/.test(value);
const issue = code => Object.assign(new Error(code), {code});

export function registerManagedInput(material, readable, store, body, codecContractCid) {
  if (!material || typeof material !== 'object' || representations.has(material) ||
      typeof readable !== 'function' || !localStoreOwnsBody(store, body) || !cid(codecContractCid)) {
    throw issue('InvalidManagedInputRegistration');
  }
  representations.set(material, Object.freeze({readable, store, body, codecContractCid}));
}

// Installed dispatcher lookup for the exact opaque material. This does not
// expose a path, grant a read, or let a callback relabel a representation.
export function managedInputCodecContractCid(material) {
  return representations.get(material)?.codecContractCid;
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
    return result.value;
  } catch (error) {
    if (['RetainedBodyChanged', 'RetainedBodyTruncated', 'ForeignStoreFile', 'ENOENT'].includes(error?.code)) held.body.close();
    throw error;
  } finally {
    // The awaited local use has stopped, including failure. Remote callbacks
    // must not use this local helper to pretend an unconfirmed worker stopped.
    borrow.confirmStopped();
  }
}
