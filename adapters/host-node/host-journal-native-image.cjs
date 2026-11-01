'use strict';

// Private selected image custody, not operational admission. The real prefix
// must supply its complete native/loader/FS/managed phase BEFORE this call.
// The normal package fact identifies bytes; it cannot issue that supplier.
const fs = require('node:fs'), processOriginal = require('node:process');
const {join, isAbsolute} = require('node:path');
const crypto = require('node:crypto'), {Buffer} = require('node:buffer');
const {types} = require('node:util');
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, freeze = Object.freeze, integer = Number.isSafeInteger;
const NativeError = Error, big = BigInt, isProxy = types.isProxy;
const allocate = Buffer.allocUnsafe, slice = Buffer.prototype.subarray;
const update = crypto.Hash.prototype.update, digest = crypto.Hash.prototype.digest;
const createHash = crypto.createHash, dlopen = descriptor(processOriginal, 'dlopen').value;
const fsNames = ['openSync', 'readSync', 'writeSync', 'fstatSync', 'lstatSync',
  'closeSync', 'fsyncSync', 'fchmodSync', 'mkdtempSync', 'unlinkSync', 'rmdirSync'];
const operations = freeze(Object.fromEntries(fsNames.map(name => [name, descriptor(fs, name).value])));
const constants = freeze({read: fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK,
  create: fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_RDWR | fs.constants.O_NOFOLLOW,
  mask: big(fs.constants.S_IFMT), regular: big(fs.constants.S_IFREG)});
let selected, invalidated = false;
const fail = code => { const error = new NativeError(code); error.code = code; throw error; };
const own = (value, name) => {
  if (value === null || typeof value !== 'object' || isProxy(value)) fail('HostJournalNativeImageUnavailable');
  const field = descriptor(value, name);
  if (field === undefined || !hasOwn(field, 'value')) fail('HostJournalNativeImageUnavailable');
  return field.value;
};
function currentBindings() {
  if (invalidated) fail('HostJournalNativeImageChanged');
  if (descriptor(processOriginal, 'dlopen')?.value !== dlopen ||
      fsNames.some(name => descriptor(fs, name)?.value !== operations[name])) {
    invalidated = true; fail('HostJournalNativeImageChanged');
  }
}
const call = (name, args) => apply(operations[name], fs, args);
const same = (a, b) => a.dev === b.dev && a.ino === b.ino && a.size === b.size &&
  a.mtimeNs === b.mtimeNs && a.ctimeNs === b.ctimeNs;

function loadHostJournalDirectoryNative(packageRoot, expected, limits, assertRuntimeCurrent) {
  const path = own(expected, 'path'), bytes = own(expected, 'bytes'), sha256 = own(expected, 'sha256');
  const maxImageBytes = own(limits, 'maxImageBytes');
  const temporaryDirectory = own(limits, 'temporaryDirectory');
  if (processOriginal.platform !== 'darwin' || processOriginal.arch !== 'arm64' ||
      processOriginal.versions.node !== '22.22.0' ||
      typeof packageRoot !== 'string' || !isAbsolute(packageRoot) || packageRoot.length > 4096 ||
      packageRoot.includes('\0') ||
      path !== '_build/native/directory-darwin-arm64.node' || !integer(bytes) || bytes < 1 ||
      !integer(maxImageBytes) || maxImageBytes < bytes || typeof sha256 !== 'string' ||
      typeof temporaryDirectory !== 'string' || temporaryDirectory.length > 4096 ||
      !isAbsolute(temporaryDirectory) || temporaryDirectory.includes('\0') ||
      !/^[0-9a-f]{64}$/u.test(sha256) || typeof assertRuntimeCurrent !== 'function') {
    fail('HostJournalNativeImageUnavailable');
  }
  currentBindings();
  if (selected !== undefined) {
    if (selected.root !== packageRoot || selected.sha256 !== sha256 || selected.bytes !== bytes ||
        selected.temporaryDirectory !== temporaryDirectory ||
        selected.runtimeCurrent !== assertRuntimeCurrent) fail('HostJournalNativeImageForeign');
    if (selected.failed) throw selected.failure;
    if (selected.view === undefined) fail('HostJournalNativeImagePending');
    apply(assertRuntimeCurrent, undefined, []);
    return selected.view;
  }
  const entry = selected = {root: packageRoot, sha256, bytes, runtimeCurrent: assertRuntimeCurrent,
    temporaryDirectory,
    source: undefined, writer: undefined, reader: undefined, directory: undefined, path: undefined,
    identity: undefined, module: undefined, loadAttempted: false, failed: false, failure: undefined, view: undefined};
  const fence = () => { currentBindings(); apply(assertRuntimeCurrent, undefined, []); };
  const acquired = fd => ({fd, consumed: false, unknown: undefined});
  const close = name => {
    const duty = entry[name];
    if (duty === undefined || duty.consumed) return;
    duty.consumed = true;
    try {
      if (call('closeSync', [duty.fd]) !== undefined) fail('HostJournalNativeImageCloseUnknown');
      entry[name] = undefined;
    } catch (cause) { duty.unknown = cause; }
  };
  const cleanup = () => {
    close('source');
    if (entry.identity === undefined && entry.writer !== undefined && !entry.writer.consumed) {
      entry.identity = call('fstatSync', [entry.writer.fd, {bigint: true}]);
    }
    close('writer');
    if (entry.path !== undefined) {
      // Only remove this exact private inode, never a successor at its name.
      let actual;
      try { actual = call('lstatSync', [entry.path, {bigint: true}]); }
      catch (cause) { if (cause.code !== 'ENOENT') throw cause; }
      if (actual !== undefined) {
        if (entry.identity === undefined || actual.dev !== entry.identity.dev || actual.ino !== entry.identity.ino) {
          fail('HostJournalNativeImageCleanupPending');
        }
        if (call('unlinkSync', [entry.path]) !== undefined) fail('HostJournalNativeImageCleanupPending');
      }
      entry.path = undefined;
    }
    close('reader');
    if (entry.directory !== undefined) {
      if (call('rmdirSync', [entry.directory]) !== undefined) fail('HostJournalNativeImageCleanupPending');
      entry.directory = undefined;
    }
  };
  let cleanupError;
  const status = () => freeze({pending: entry.source !== undefined || entry.writer !== undefined ||
    entry.reader !== undefined || entry.path !== undefined || entry.directory !== undefined,
    loadAttempted: entry.loadAttempted,
    errors: freeze([entry.source?.unknown, entry.writer?.unknown, entry.reader?.unknown, cleanupError]
      .filter(value => value !== undefined))});
  const observeCleanup = () => {
    // No source acquisition, loading or consumed close is repeated here.
    try { cleanup(); } catch (cause) { cleanupError = cause; }
    return status();
  };
  const hashCopy = () => {
    const working = apply(allocate, Buffer, [Math.min(65536, bytes)]);
    const lookahead = apply(allocate, Buffer, [1]);
    const hash = apply(createHash, crypto, ['sha256']);
    let offset = 0;
    while (offset < bytes) {
      const length = Math.min(working.length, bytes - offset);
      const count = call('readSync', [entry.reader.fd, working, 0, length, offset]);
      if (!integer(count) || count < 1 || count > length) fail('HostJournalNativeImageChanged');
      apply(update, hash, [apply(slice, working, [0, count])]); offset += count;
    }
    if (call('readSync', [entry.reader.fd, lookahead, 0, 1, bytes]) !== 0 ||
        apply(digest, hash, ['hex']) !== sha256) fail('HostJournalNativeImageChanged');
  };
  try {
    fence();
    entry.source = acquired(call('openSync', [join(packageRoot, path), constants.read]));
    const first = call('fstatSync', [entry.source.fd, {bigint: true}]);
    if ((first.mode & constants.mask) !== constants.regular || first.size !== big(bytes)) {
      fail('HostJournalNativeImageChanged');
    }
    const backing = apply(allocate, Buffer, [bytes]), lookahead = apply(allocate, Buffer, [1]);
    const hash = apply(createHash, crypto, ['sha256']);
    let offset = 0;
    while (offset < bytes) {
      const length = Math.min(65536, bytes - offset);
      const count = call('readSync', [entry.source.fd, backing, offset, length, null]);
      if (!integer(count) || count < 1 || count > length) fail('HostJournalNativeImageChanged');
      apply(update, hash, [apply(slice, backing, [offset, offset + count])]); offset += count;
    }
    if (call('readSync', [entry.source.fd, lookahead, 0, 1, null]) !== 0 ||
        apply(digest, hash, ['hex']) !== sha256 || !same(first, call('fstatSync', [entry.source.fd, {bigint: true}]))) {
      fail('HostJournalNativeImageChanged');
    }
    close('source');
    if (entry.source !== undefined) fail('HostJournalNativeImageCleanupPending');
    fence();
    // The actual disposition selects its filesystem original; do not acquire
    // an unbounded ambient environment String here as a substitute supplier.
    entry.directory = call('mkdtempSync', [join(temporaryDirectory, 'actql-node-directory-image-')]);
    entry.path = join(entry.directory, 'directory.node');
    entry.writer = acquired(call('openSync', [entry.path, constants.create, 0o600]));
    entry.identity = call('fstatSync', [entry.writer.fd, {bigint: true}]);
    offset = 0;
    while (offset < bytes) {
      const count = call('writeSync', [entry.writer.fd, backing, offset, bytes - offset, null]);
      if (!integer(count) || count < 1 || count > bytes - offset) fail('HostJournalNativeImageChanged');
      offset += count;
    }
    call('fsyncSync', [entry.writer.fd]); call('fchmodSync', [entry.writer.fd, 0o400]);
    entry.reader = acquired(call('openSync', [entry.path, constants.read]));
    const copy = call('fstatSync', [entry.reader.fd, {bigint: true}]);
    if (copy.dev !== entry.identity.dev || copy.ino !== entry.identity.ino || copy.size !== big(bytes) || copy.nlink !== 1n) {
      fail('HostJournalNativeImageChanged');
    }
    entry.identity = copy;
    close('writer');
    if (entry.writer !== undefined) fail('HostJournalNativeImageCleanupPending');
    hashCopy();
    // No path, writable FD, callback or await escapes this private image's
    // acquisition/load/unlink sequence. Darwin rejects the unlinked-before-
    // dlopen route; use its ordinary named-image API with no policy changes.
    entry.module = {exports: {}};
    entry.loadAttempted = true;
    apply(dlopen, processOriginal, [entry.module, entry.path]);
    hashCopy();
    if (!same(copy, call('fstatSync', [entry.reader.fd, {bigint: true}]))) fail('HostJournalNativeImageChanged');
    cleanup();
    if (status().pending) fail('HostJournalNativeImageCleanupPending');
    const native = own(entry.module, 'exports');
    const captured = {};
    for (const name of ['open', 'next', 'current', 'close']) {
      const operation = own(native, name);
      if (typeof operation !== 'function') fail('HostJournalNativeImageUnavailable');
      captured[name] = operation;
    }
    // The optional Store lease borrows this SAME selected image. Older images
    // still support directory inspection but supply no recovery capability.
    for (const name of ['openFileRoot','fileRootCurrent','fileRootClose',
      'openStoreOwnerLease','storeOwnerLeaseReceipt']) {
      const operation = descriptor(native, name)?.value;
      if (typeof operation === 'function') captured[name] = operation;
    }
    fence();
    entry.view = freeze({operations: native, assertCurrent() {
      fence();
      if (own(entry.module, 'exports') !== native || Object.entries(captured)
        .some(([name, operation]) => own(native, name) !== operation)) fail('HostJournalNativeImageChanged');
    }});
    return entry.view;
  } catch (cause) {
    entry.failed = true;
    observeCleanup();
    if (status().pending) {
      const carrier = new NativeError('HostJournalNativeImageCleanupPending', {cause});
      carrier.code = 'HostJournalNativeImageCleanupPending'; carrier.cleanupPending = true;
      carrier.cleanupHandle = freeze({status, retry: observeCleanup});
      entry.failure = carrier;
    } else entry.failure = cause;
    throw entry.failure;
  }
}
module.exports = {loadHostJournalDirectoryNative};
freeze(module.exports);
