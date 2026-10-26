// Bound installed Source configuration and identity metadata before buffering.
// This does not make separate identity and installation reads one snapshot.
import {open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {types} from 'node:util';

const profileByteLimit = 8 * 1024 * 1024;
const chunkBytes = 64 * 1024;
const applyOriginal = Reflect.apply;

// Select original read methods only; this owns no I/O, authority or cleanup.
export function captureConfigurationReaders(reader, readJson, unavailable) {
  const refuse = () => {
    unavailable();
    throw new TypeError('InstalledConfigurationReaderUnavailable');
  };
  if (readJson !== undefined && typeof readJson !== 'function') refuse();
  if (reader === undefined) return Object.freeze({
    readJson: readJson ?? readSourceProfileJson, readText: readBoundedConfigurationText,
  });
  if (reader === null || typeof reader !== 'object' || Array.isArray(reader) || types.isProxy(reader)) refuse();
  const json = Object.getOwnPropertyDescriptor(reader, 'readJson');
  const text = Object.getOwnPropertyDescriptor(reader, 'readText');
  if (!json || !Object.hasOwn(json, 'value') || typeof json.value !== 'function' ||
      !text || !Object.hasOwn(text, 'value') || typeof text.value !== 'function') refuse();
  // Retain both original methods and their receiver before the first read awaits.
  return Object.freeze({
    readJson: readJson ?? ((...args) => Reflect.apply(json.value, reader, args)),
    readText: (...args) => Reflect.apply(text.value, reader, args),
  });
}

export async function readSourceProfileJson(path,
  {maxBytes = profileByteLimit, openFile = open} = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0 ||
      maxBytes > profileByteLimit) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  return readConfiguration(path, maxBytes, openFile,
    bytes => JSON.parse(bytes.toString('utf8')));
}

// Publications may have a different declared ceiling and hash their original
// UTF-8 text. Do not parse/reserialize them or impose the JSON profile ceiling.
export async function readBoundedConfigurationText(path, {maxBytes, openFile = open} = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  return readConfiguration(path, maxBytes, openFile, bytes => bytes.toString('utf8'));
}

// Project originals must not replace malformed bytes with U+FFFD before the
// Common reader sees them. Keep a genuine BOM as text as well: its admission
// belongs to that reader, not to an implicit TextDecoder normalization.
export async function readBoundedConfigurationUtf8(path, {maxBytes, openFile = open} = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  return readConfiguration(path, maxBytes, openFile, bytes =>
    new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes));
}

async function readConfiguration(path, maxBytes, openFile, project) {
  return withOriginalFile(path, openFile, async original => {
    const chunks = [];
    let bytes = 0;
    let used = 0;
    let buffer = Buffer.allocUnsafe(Math.min(chunkBytes, maxBytes + 1));
    for (;;) {
      // One lookahead byte distinguishes exact-limit EOF from an oversized
      // file, including one that grows after it is opened. Never readFile.
      const {bytesRead} = await original.read(buffer, used,
        buffer.length - used, null);
      if (bytesRead === 0) {
        chunks.push(buffer.subarray(0, used));
        return project(Buffer.concat(chunks, bytes));
      }
      bytes += bytesRead;
      used += bytesRead;
      if (bytes > maxBytes) {
        throw new TypeError('InvalidInstalledSourceProfile');
      }
      if (used === buffer.length) {
        chunks.push(buffer);
        buffer = Buffer.allocUnsafe(Math.min(chunkBytes, maxBytes - bytes + 1));
        used = 0;
      }
    }
  });
}

// Re-read the selected runtime for each installation. Keep the exact byte
// preimage, without materializing a full runtime Buffer or caching a path,
// module namespace, timestamp, credential or installation decision. This
// workspace bound is not a file-size/work limit or a physical funding claim.
export async function installedRuntimeBundleCid(path, {openFile = open} = {}) {
  return withOriginalFile(path, openFile, async original => {
    const digest = createHash('sha256');
    const buffer = Buffer.allocUnsafe(chunkBytes);
    for (;;) {
      const {bytesRead} = await original.read(buffer, 0, buffer.length, null);
      if (bytesRead === 0) return `sha256:${digest.digest('hex')}`;
      digest.update(buffer.subarray(0, bytesRead));
    }
  });
}

// Shared physical custody of the original configuration/runtime read. A
// close failure retains this same handle and retry, never a second read.
export async function withOriginalFile(path, openFile, consume) {
  let original = await openFile(path, 'r');
  let originalClose;
  const captureClose = () => {
    const observed = original.close;
    if (typeof observed !== 'function') {
      throw new TypeError('InstalledSourceProfileCloseUnavailable');
    }
    originalClose = observed;
  };
  let failure;
  let readFailed = false;
  try {
    // Retain successful observation before any consumer await. Retry may
    // observe a method only when setup never obtained one; it cannot replace
    // an already captured close or use a different receiver to retire this FD.
    captureClose();
    return await consume(original);
  } catch (cause) {
    readFailed = true;
    failure = cause;
    throw cause;
  } finally {
    try {
      // A failed setup observation already owns this FD. Preserve that cause
      // and leave observation to its close-only retry, without starting intake
      // or silently retrying a getter inside the same failed setup.
      if (originalClose === undefined) throw failure;
      if (await applyOriginal(originalClose, original, []) === false) {
        throw new TypeError('InstalledSourceProfileCleanupPending');
      }
      original = undefined;
      originalClose = undefined;
    }
    catch (cause) {
      const first = cause;
      let latest = cause, flight;
      const status = () => Object.freeze({pending: original !== undefined,
        errors: Object.freeze(first === latest ? [first] : [first, latest])});
      const retry = () => {
        if (flight !== undefined) return flight;
        flight = (async () => {
          if (original !== undefined) {
            try {
              if (originalClose === undefined) captureClose();
              if (await applyOriginal(originalClose, original, []) === false) {
                throw new TypeError('InstalledSourceProfileCleanupPending');
              }
              original = undefined;
              originalClose = undefined;
            } catch (error) { latest = error; throw error; }
          }
          return status();
        })().finally(() => { flight = undefined; });
        return flight;
      };
      const cleanupHandle = Object.freeze({status, retry,
        primaryFailure: readFailed ? failure : cause});
      let primary = cause;
      if (readFailed) {
        // Diagnostic presentation must not hide the original FD. Thrown values
        // need not be Errors, and reading/coercing their message can itself fail.
        let message;
        try {
          const observed = failure?.message;
          if (typeof observed === 'string') message = observed;
        } catch { /* Keep both original failures without a diagnostic message. */ }
        primary = new AggregateError([failure, cause], message, {cause: failure});
      }
      const descriptors = {
        cleanupHandle: {value: cleanupHandle, configurable: true},
        cleanupPending: {get: () => status().pending, configurable: true},
      };
      let exported = primary;
      try {
        // Never overwrite another resource's cleanup responsibility. Frozen or
        // readonly primaries stay intact beneath the same-handle carrier.
        if (primary.cleanupHandle !== undefined || primary.cleanupPending === true ||
            Object.getOwnPropertyDescriptor(primary, 'cleanupHandle') !== undefined) throw primary;
        if (Object.getOwnPropertyDescriptor(primary, 'cleanupPending')?.configurable === false) throw primary;
        Object.defineProperties(primary, descriptors);
      } catch {
        exported = new Error('InstalledSourceProfileCleanupPending', {cause: primary});
        Object.defineProperties(exported, descriptors);
      }
      throw exported;
    }
  }
}
