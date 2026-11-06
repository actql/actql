// One native child of the existing exclusive Store owner. Unsupported normal
// native delivery supplies no proof, never a substitute pathname/PID lease.
import {randomUUID} from 'node:crypto';
import {localProjectFilesystem} from '../host-node/local-files-native.mjs';
import {hostJournalDirectoryNative} from '../host-node/host-journal-directory.mjs';
const fail = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const operations = ['openFileRoot', 'fileRootCurrent', 'fileRootClose',
  'openStoreOwnerLease', 'storeOwnerLeaseReceipt', 'publishStoreOwnerDirectory',
  'openFileDirectory', 'replaceStoreOwnerMetadata'];
export function openPublicationOwnerLease(path, inspector, deferred = false) {
  let native, assertCurrent = () => {};
  try {
    if (inspector === undefined) native = localProjectFilesystem();
    else ({native, assertCurrent} = hostJournalDirectoryNative(inspector));
  }
  catch (cause) {
    if (['LocalFilesNativeUnavailable','ERR_DLOPEN_FAILED','MODULE_NOT_FOUND'].includes(cause?.code)) return undefined;
    throw cause;
  }
  const methods = Object.fromEntries(operations.map(name => [name,
    Object.getOwnPropertyDescriptor(native, name)?.value]));
  if (operations.some(name => typeof methods[name] !== 'function')) return undefined;
  const call = (name, ...args) => {
    if (name !== 'fileRootClose') assertCurrent();
    return Reflect.apply(methods[name], native, args);
  };
  let root, lease, rootClose, leaseClose, anchor, closing = false;
  const closeOne = (original, previous) => {
    if (previous !== undefined) return previous;
    // Native close consumes its descriptor before the syscall. An unknown
    // acknowledgement is retained, never retried through a recycled integer.
    return call('fileRootClose', original);
  };
  let metadataDirectory, metadataDirectoryClose;
  const closeMetadata = () => {
    if (metadataDirectory === undefined) return;
    metadataDirectoryClose = closeOne(metadataDirectory, metadataDirectoryClose);
    if (metadataDirectoryClose?.outcome !== 'closed') fail('PublicationStoreLeaseCleanupPending');
    metadataDirectory = undefined; metadataDirectoryClose = undefined;
  };
  const close = () => {
    closing = true;
    closeMetadata();
    if (lease !== undefined) {
      leaseClose = closeOne(lease, leaseClose);
      if (leaseClose?.outcome !== 'closed') fail('PublicationStoreLeaseCleanupPending');
      lease = undefined;
    }
    if (root !== undefined) {
      rootClose = closeOne(root, rootClose);
      if (rootClose?.outcome !== 'closed') fail('PublicationStoreLeaseCleanupPending');
      root = undefined;
    }
    return true;
  };
  const current = () => {
    if (closing || root === undefined) fail('PublicationStoreLeaseChanged');
    call('fileRootCurrent', root);
    if (lease === undefined) return;
    const value = call('storeOwnerLeaseReceipt', lease);
    if (value?.identity !== anchor.identity || String(value.device) !== anchor.device ||
        String(value.inode) !== anchor.inode) fail('PublicationStoreLeaseChanged');
  };
  try {
    root = call('openFileRoot', path); call('fileRootCurrent', root);
    const qualify = () => {
      if (anchor !== undefined) {current(); return true;}
      try {
        current();
        lease = call('openStoreOwnerLease', root, randomUUID());
        const value = call('storeOwnerLeaseReceipt', lease);
        if (typeof value?.identity !== 'string' || typeof value.device !== 'bigint' ||
            typeof value.inode !== 'bigint') fail('PublicationStoreLeaseUnavailable');
        anchor = Object.freeze({identity: value.identity, device: String(value.device), inode: String(value.inode)});
        current();
        return true;
      } catch (cause) {
        if (!['PublicationStoreLeaseUnavailable', 'ForeignPublicationOwnerRoot',
          'LocalFileOriginalChanged'].includes(cause?.code)) throw cause;
        // The same old unsupported-qualification fallback is allowed only
        // after the original lease/root acknowledge close. Busy never falls back.
        close();
        return false;
      }
    };
    if (!deferred && !qualify()) return undefined;
    return Object.freeze({current, close, qualify, drainMetadata: closeMetadata,
      get anchor() {return anchor;},
      publishDirectory(name, original) {
        current(); call('publishStoreOwnerDirectory', root, name, original.dev, original.ino);
      },
      replaceMetadata(name, before, staged, committed) {
        current();
        metadataDirectory = call('openFileDirectory', root, 'owner', 2);
        try {
          call('fileRootCurrent', metadataDirectory); current();
          call('replaceStoreOwnerMetadata', metadataDirectory, name,
            before.dev, before.ino, before.size, before.mtimeNs, before.ctimeNs, staged.dev, staged.ino);
          committed();
        } catch (cause) {
          try {closeMetadata();} catch (cleanupError) {
            throw Object.assign(new Error('PublicationStoreLeaseCleanupPending', {cause}),
              {code: 'PublicationStoreLeaseCleanupPending', primaryFailure: cause, cleanupError});
          }
          throw cause;
        }
        closeMetadata();
      },
      matches(value) {current(); return anchor !== undefined && value?.identity === anchor.identity &&
        value?.device === anchor.device && value?.inode === anchor.inode;}});
  } catch (cause) {
    try {close();} catch (cleanupError) {
      throw Object.assign(new Error('PublicationStoreLeaseCleanupPending', {cause}),
        {code: 'PublicationStoreLeaseCleanupPending', cleanupPending: true, cleanupError,
          cleanupHandle: Object.freeze({status: () => ({pending: root !== undefined || lease !== undefined}),
            retry() {close(); return {pending: false};}})});
    }
    // Qualification failure is not a new Store-open restriction. Only after
    // both actual native originals acknowledge close may this opening retain
    // ordinary behavior without an execution-stop proof. Busy never downgrades.
    if (['PublicationStoreLeaseUnavailable', 'ForeignPublicationOwnerRoot',
      'LocalFileOriginalChanged'].includes(cause?.code)) return undefined;
    throw cause;
  }
}
