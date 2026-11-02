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
  const releaseProperty = descriptor(expected, 'npmRelease');
  let release;
  if (releaseProperty !== undefined) {
    if (!hasOwn(releaseProperty, 'value')) fail('InvalidInitialControlImageFact');
    const value = releaseProperty.value, length = field(value, 'bytes'), digest = field(value, 'sha256');
    const version = field(value, 'version');
    if (!safeInteger(length) || length < 0 || typeof digest !== 'string' ||
        !nativeApply(patternTest, hashPattern, [digest]) ||
        typeof version !== 'string' || version.length === 0 || version.length > 256) {
      fail('InvalidInitialControlImageFact');
    }
    release = {bytes: length, sha256: digest};
  }
  // A substituted pipe/device must not block the preload before its regular
  // file observation. NONBLOCK does not change regular-file read semantics.
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  let primary, failed = false, closeState = 'not_attempted';
  try {
    const first = fstatSync(fd, {bigint: true});
    if ((first.mode & fileTypeMask) !== regularFileType ||
        (first.size !== nativeBigInt(bytes) &&
         (release === undefined || first.size !== nativeBigInt(release.bytes)))) {
      fail('InitialControlImageChanged');
    }
    const actualBytes = first.size === nativeBigInt(bytes) ? bytes : release.bytes;
    // The complete original Source backing and immutable decoded String overlap
    // during decoding. The recipe supplies the finite file extent, not a lease.
    const backing = nativeApply(allocate, Buffer, [actualBytes]), lookahead = nativeApply(allocate, Buffer, [1]);
    const hash = createHash('sha256');
    let offset = 0;
    while (offset < actualBytes) {
      const length = min(64 * 1024, actualBytes - offset);
      const count = readSync(fd, backing, offset, length, null);
      if (!safeInteger(count) || count <= 0 || count > length) fail('InitialControlImageChanged');
      nativeApply(hashUpdate, hash, [nativeApply(subarray, backing, [offset, offset + count])]);
      offset += count;
    }
    const actualSha256 = nativeApply(hashDigest, hash, ['hex']);
    const originalMatch = actualBytes === bytes && actualSha256 === sha256;
    const releaseMatch = release !== undefined && actualBytes === release.bytes && actualSha256 === release.sha256;
    if (readSync(fd, lookahead, 0, 1, null) !== 0 ||
        !unchanged(first, fstatSync(fd, {bigint: true})) || (!originalMatch && !releaseMatch)) {
      fail('InitialControlImageChanged');
    }
    const source = nativeApply(decode, decoder, [backing]);
    return freeze({source, bytes: actualBytes, sha256: actualSha256,
      ...(release === undefined ? {} : {representation: originalMatch ? 'source' : 'release'})});
  } catch (cause) { failed = true; primary = cause; throw cause; }
  finally {
    try {
      // Mark the attempt before entering native close: an exception does not
      // establish whether the integer has already been released and reused.
      closeState = 'pending';
      if (closeSync(fd) !== undefined) fail('InitialControlImageCleanupPending');
      closeState = 'closed';
    }
    catch (cause) {
      const errors = freeze([cause]);
      const status = () => freeze({pending: closeState !== 'closed', errors});
      // Only observe this original unresolved duty. Never issue another close
      // for its numeric FD, inspect a replacement path/FD as an ACK, or reread.
      const retry = () => status();
      const cleanupHandle = freeze({status, retry, primaryFailure: failed ? primary : cause});
      const carrier = new NativeError('InitialControlImageCleanupPending', {cause: failed ? primary : cause});
      carrier.code = 'InitialControlImageCleanupPending';
      carrier.cleanupHandle = cleanupHandle;
      carrier.closeFailure = cause;
      throw carrier;
    }
  }
}

module.exports = {captureInitialControlImageSource};
freeze(module.exports);
