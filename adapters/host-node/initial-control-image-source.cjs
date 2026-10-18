'use strict';

// Internal byte custody only, not an installation admission or a trust factory.
// The selected preload must independently own the recipe, actual module graph,
// backend and complete envelope before it can adopt any captured Source here.
const {openSync, readSync, fstatSync, closeSync, constants} = require('node:fs');
const {createHash, Hash} = require('node:crypto');
const {Buffer} = require('node:buffer');
const {TextDecoder} = require('node:util');
const freeze = Object.freeze, descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, safeInteger = Number.isSafeInteger;
const NativeError = Error, nativeBigInt = BigInt, min = Math.min;
const nativeApply = Reflect.apply, hashUpdate = Hash.prototype.update, hashDigest = Hash.prototype.digest;
const allocate = Buffer.allocUnsafe, subarray = Buffer.prototype.subarray;
const hashPattern = /^[0-9a-f]{64}$/u, patternTest = RegExp.prototype.test;
const fileTypeMask = BigInt(constants.S_IFMT), regularFileType = BigInt(constants.S_IFREG);
const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const decode = TextDecoder.prototype.decode;
const fail = code => { const cause = new NativeError(code); cause.code = code; throw cause; };
const field = (value, name) => {
  if (value === null || typeof value !== 'object') fail('InvalidInitialControlImageFact');
  const property = descriptor(value, name);
  if (property === undefined || !hasOwn(property, 'value')) fail('InvalidInitialControlImageFact');
  return property.value;
};
const unchanged = (first, last) => first.dev === last.dev && first.ino === last.ino &&
  first.size === last.size && first.mtimeNs === last.mtimeNs && first.ctimeNs === last.ctimeNs;

function captureInitialControlImageSource(path, expected) {
  // Copy expected DATA before opening. Matching bytes are not original Host,
  // generation, capacity, current authorization or an operational issuer.
  const bytes = field(expected, 'bytes'), sha256 = field(expected, 'sha256');
  if (!safeInteger(bytes) || bytes < 0 || typeof sha256 !== 'string' ||
      !nativeApply(patternTest, hashPattern, [sha256])) fail('InvalidInitialControlImageFact');
  // A substituted pipe/device must not block the preload before its regular
  // file observation. NONBLOCK does not change regular-file read semantics.
  let fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  let primary, failed = false;
  try {
    const first = fstatSync(fd, {bigint: true});
    if ((first.mode & fileTypeMask) !== regularFileType || first.size !== nativeBigInt(bytes)) {
      fail('InitialControlImageChanged');
    }
    // The complete original Source backing and immutable decoded String overlap
    // during decoding. The recipe supplies the finite file extent, not a lease.
    const backing = nativeApply(allocate, Buffer, [bytes]), lookahead = nativeApply(allocate, Buffer, [1]);
    const hash = createHash('sha256');
    let offset = 0;
    while (offset < bytes) {
      const length = min(64 * 1024, bytes - offset);
      const count = readSync(fd, backing, offset, length, null);
      if (!safeInteger(count) || count <= 0 || count > length) fail('InitialControlImageChanged');
      nativeApply(hashUpdate, hash, [nativeApply(subarray, backing, [offset, offset + count])]);
      offset += count;
    }
    if (readSync(fd, lookahead, 0, 1, null) !== 0 ||
        !unchanged(first, fstatSync(fd, {bigint: true})) ||
        nativeApply(hashDigest, hash, ['hex']) !== sha256) {
      fail('InitialControlImageChanged');
    }
    const source = nativeApply(decode, decoder, [backing]);
    return freeze({source, bytes, sha256});
  } catch (cause) { failed = true; primary = cause; throw cause; }
  finally {
    try {
      if (closeSync(fd) !== undefined) fail('InitialControlImageCleanupPending');
      fd = undefined;
    }
    catch (cause) {
      const first = cause;
      let latest = cause;
      const status = () => freeze({pending: fd !== undefined,
        errors: freeze(first === latest ? [first] : [first, latest])});
      const retry = () => {
        if (fd !== undefined) {
          try {
            if (closeSync(fd) !== undefined) fail('InitialControlImageCleanupPending');
            fd = undefined;
          }
          catch (error) { latest = error; throw error; }
        }
        return status();
      };
      // Always keep the same close function and numeric FD. Never reopen or
      // reread a failed image, overwrite another duty, or mutate a frozen cause.
      const cleanupHandle = freeze({status, retry, primaryFailure: failed ? primary : cause});
      const carrier = new NativeError('InitialControlImageCleanupPending', {cause: failed ? primary : cause});
      carrier.code = 'InitialControlImageCleanupPending';
      carrier.cleanupHandle = cleanupHandle;
      carrier.closeFailure = cause;
      throw carrier;
    }
  }
}

module.exports = freeze({captureInitialControlImageSource});
