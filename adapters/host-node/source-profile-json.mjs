// Bound installed Source configuration and identity metadata before buffering.
// This does not make separate identity and installation reads one snapshot.
import {open} from 'node:fs/promises';

const profileByteLimit = 8 * 1024 * 1024;
const chunkBytes = 64 * 1024;

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

async function readConfiguration(path, maxBytes, openFile, project) {
  let original = await openFile(path, 'r');
  let failure;
  let readFailed = false;
  try {
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
  } catch (cause) {
    readFailed = true;
    failure = cause;
    throw cause;
  } finally {
    try {
      if (await original.close() === false) {
        throw new TypeError('InstalledSourceProfileCleanupPending');
      }
      original = undefined;
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
              if (await original.close() === false) {
                throw new TypeError('InstalledSourceProfileCleanupPending');
              }
              original = undefined;
            } catch (error) { latest = error; throw error; }
          }
          return status();
        })().finally(() => { flight = undefined; });
        return flight;
      };
      const cleanupHandle = Object.freeze({status, retry,
        primaryFailure: readFailed ? failure : cause});
      const primary = !readFailed ? cause : new AggregateError(
        [failure, cause], failure.message, {cause: failure});
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
