// Bound installed Source configuration and identity metadata before buffering.
// This does not make separate identity and installation reads one snapshot.
import {open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {types} from 'node:util';

export const installedConfigurationByteLimit = 8 * 1024 * 1024;
export const installedConfigurationChunkBytes = 64 * 1024;
const profileByteLimit = installedConfigurationByteLimit;
const chunkBytes = installedConfigurationChunkBytes;
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
  const originalText = Object.getOwnPropertyDescriptor(reader, 'readOriginalText');
  const originalBytes = Object.getOwnPropertyDescriptor(reader, 'readOriginalBytes');
  const parseText = Object.getOwnPropertyDescriptor(reader, 'parseJsonText');
  if (!json || !Object.hasOwn(json, 'value') || typeof json.value !== 'function' ||
      !text || !Object.hasOwn(text, 'value') || typeof text.value !== 'function' ||
      originalText !== undefined && (!Object.hasOwn(originalText, 'value') ||
        typeof originalText.value !== 'function') ||
      originalBytes !== undefined && (!Object.hasOwn(originalBytes, 'value') ||
        typeof originalBytes.value !== 'function') ||
      parseText !== undefined && (!Object.hasOwn(parseText, 'value') ||
        typeof parseText.value !== 'function')) refuse();
  // Capture the initializer's optional actual-FD text method before any read awaits.
  // Its absence cannot substitute a bounded reader or manufacture a byte ceiling.
  return Object.freeze({
    readJson: readJson ?? ((...args) => Reflect.apply(json.value, reader, args)),
    readText: (...args) => Reflect.apply(text.value, reader, args),
    ...(parseText === undefined ? {} : {
      parseJsonText: (...args) => Reflect.apply(parseText.value, reader, args),
    }),
    ...(originalText === undefined ? {} : {
      readOriginalText: (...args) => Reflect.apply(originalText.value, reader, args),
    }),
    ...(originalBytes === undefined ? {} : {
      readOriginalBytes: (...args) => Reflect.apply(originalBytes.value, reader, args),
    }),
  });
}

export async function readSourceProfileJson(path,
  {maxBytes = profileByteLimit, openFile = open, beforeDecode, beforeParse, io} = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0 ||
      maxBytes > profileByteLimit) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  if (beforeParse !== undefined && typeof beforeParse !== 'function') {
    throw new TypeError('InvalidInstalledConfigurationConstruction');
  }
  return readConfiguration(path, maxBytes, openFile,
    bytes => {
      const wire = bytes.toString('utf8');
      // The SAME decoded original supplies construction geometry before the
      // native parser allocates a value tree. This callback is no validator.
      if (beforeParse !== undefined && beforeParse(wire) !== undefined) {
        throw new TypeError('InvalidInstalledConfigurationConstruction');
      }
      return JSON.parse(wire);
    }, beforeDecode, io);
}

// Publications may have a different declared ceiling and hash their original
// UTF-8 text. Do not parse/reserialize them or impose the JSON profile ceiling.
export async function readBoundedConfigurationText(path, {maxBytes, openFile = open, beforeDecode, io} = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  return readConfiguration(path, maxBytes, openFile, bytes => bytes.toString('utf8'), beforeDecode, io);
}

// Project originals must not replace malformed bytes with U+FFFD before the
// Common reader sees them. Keep a genuine BOM as text as well: its admission
// belongs to that reader, not to an implicit TextDecoder normalization.
export async function readBoundedConfigurationUtf8(path, {maxBytes, openFile = open, beforeDecode, io} = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  return readConfiguration(path, maxBytes, openFile, bytes =>
    new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes), beforeDecode, io);
}

async function readConfiguration(path, maxBytes, openFile, project, beforeDecode, io) {
  if (beforeDecode !== undefined && typeof beforeDecode !== 'function') {
    throw new TypeError('InvalidInstalledConfigurationConstruction');
  }
  return withOriginalFile(path, openFile, original =>
    readConfigurationBody(original, maxBytes, project, beforeDecode), io);
}

// An installed issuer key has no JSON-profile/CA/secret ceiling. The normal
// initializer funds the size observed on THIS opened FD before buffering; a
// growing original refuses rather than reading beyond that actual envelope.
// The existing same-handle close/retry owner remains the only I/O owner.
export async function readOriginalConfigurationText(path, options) {
  return readOriginalConfiguration(path, options, bytes => bytes.toString('utf8'));
}

// Preserve the exact original CA bytes. Its observed FD extent belongs to the
// same initializer as text/key input, rather than a borrowed secret ceiling.
export async function readOriginalConfigurationBytes(path, options) {
  return readOriginalConfiguration(path, options, bytes => bytes);
}

async function readOriginalConfiguration(path,
  {openFile = open, beforeRead, beforeDecode, io} = {}, project) {
  if (typeof beforeRead !== 'function' || typeof beforeDecode !== 'function') {
    throw new TypeError('InvalidInstalledConfigurationConstruction');
  }
  return withOriginalFile(path, openFile, async original => {
    const observed = await original.stat();
    if (!Number.isSafeInteger(observed.size) || observed.size < 0) {
      throw new TypeError('InvalidInstalledSourceProfileByteLimit');
    }
    if (beforeRead(observed.size) !== undefined) throw new TypeError('InvalidInstalledConfigurationConstruction');
    return readConfigurationBody(original, observed.size, project, beforeDecode);
  }, io);
}

async function readConfigurationBody(original, maxBytes, project, beforeDecode) {
    const chunks = [];
    let bytes = 0;
    let used = 0;
    let buffer = Buffer.allocUnsafe(Math.min(chunkBytes, maxBytes + 1));
    let joined;
    try {
      for (;;) {
        // One lookahead byte distinguishes exact-limit EOF from an oversized
        // file, including one that grows after it is opened. Never readFile.
        const {bytesRead} = await original.read(buffer, used,
          buffer.length - used, null);
        if (bytesRead === 0) {
          chunks.push(buffer.subarray(0, used));
          // The fixed initializer funds the received buffer/text overlap here;
          // JSON construction separately observes that SAME decoded String.
          // An absent port keeps the exact buffering/parsing semantics.
          if (beforeDecode !== undefined && beforeDecode(bytes) !== undefined) {
            throw new TypeError('InvalidInstalledConfigurationConstruction');
          }
          joined = Buffer.concat(chunks, bytes);
          return project(joined);
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
    } finally {
      // Cut these logical transient aliases before original FD cleanup/current
      // callbacks. Only its actual close ACK permits the caller's E/R fold.
      joined = buffer = undefined;
      chunks.length = 0;
    }
}

// Re-read the selected runtime for each installation. Keep the exact byte
// preimage, without materializing a full runtime Buffer or caching a path,
// module namespace, timestamp, credential or installation decision. This
// workspace bound is not a file-size/work limit or a physical funding claim.
export async function installedRuntimeBundleCid(path, {openFile = open, io} = {}) {
  return withOriginalFile(path, openFile, async original => {
    const digest = createHash('sha256');
    const buffer = Buffer.allocUnsafe(chunkBytes);
    for (;;) {
      const {bytesRead} = await original.read(buffer, 0, buffer.length, null);
      if (bytesRead === 0) return `sha256:${digest.digest('hex')}`;
      digest.update(buffer.subarray(0, bytesRead));
    }
  }, io);
}

// Shared physical custody of the original configuration/runtime read. A
// close failure retains this same handle and retry, never a second read.
function capturePhysicalIo(io) {
  if (io === undefined) return undefined;
  if (io === null || typeof io !== 'object' || Array.isArray(io) || types.isProxy(io)) {
    throw new TypeError('InvalidInstalledSourcePhysicalIo');
  }
  const fields = Object.getOwnPropertyDescriptors(io), methods = {};
  const names = ['begin', 'charge', 'uncertain', 'finish'];
  if (Reflect.ownKeys(fields).length !== names.length) throw new TypeError('InvalidInstalledSourcePhysicalIo');
  for (const name of names) {
    const field = fields[name];
    if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function' ||
        types.isAsyncFunction(field.value) || types.isGeneratorFunction(field.value)) {
      throw new TypeError('InvalidInstalledSourcePhysicalIo');
    }
    methods[name] = field.value;
  }
  return {receiver: io, methods};
}

export async function withOriginalFile(path, openFile, consume, physicalIo) {
  const io = capturePhysicalIo(physicalIo), pending = new Set(), computations = new Set();
  let original, originalClose, physicallyClosed = false;
  const invalidIo = () => new TypeError('InvalidInstalledSourcePhysicalIo');
  const validOperation = value => value !== null && typeof value === 'object' && !types.isProxy(value);
  function invokeIo(name, args, record) {
    const value = applyOriginal(io.methods[name], io.receiver, args);
    if (types.isPromise(value)) {
      // Join an unexpected computation to THIS original file cleanup owner.
      // Its settlement alone is no accounting or retirement acknowledgement.
      const task = {name, record, settled: false};computations.add(task);
      task.completion = Promise.resolve(value).then(result => {task.value = result;task.settled = true;},
        cause => {task.cause = cause;task.settled = true;});
      if (name === 'charge') record.ambiguous = true;
      throw invalidIo();
    }
    if (name === 'begin' ? !validOperation(value) : value !== undefined) {
      if (name === 'charge') record.ambiguous = true;
      throw invalidIo();
    }
    return value;
  }
  function begin(transfer) {
    if (io === undefined) return undefined;
    const operation = invokeIo('begin', [BigInt(transfer)]);
    const record = {operation, accounted: transfer === 0};pending.add(record);return record;
  }
  function finish(record) {
    if (!record.accounted) {
      if (record.ambiguous) throw invalidIo();
      if (record.extent === undefined) invokeIo('uncertain', [record.operation], record);
      else invokeIo('charge', [record.operation, BigInt(record.extent)], record);
      record.accounted = true;
    }
    invokeIo('finish', [record.operation], record);pending.delete(record);
  }
  function captureMethod(name) {
    const method = original[name];
    if (typeof method !== 'function') throw new TypeError('InstalledSourceProfileReadUnavailable');
    return method;
  }
  const captureClose = () => {
    const observed = original.close;
    if (typeof observed !== 'function') throw new TypeError('InstalledSourceProfileCloseUnavailable');
    originalClose = observed;
  };
  async function cleanup() {
    if (original !== undefined && !physicallyClosed) {
      if (originalClose === undefined) captureClose();
      if (await applyOriginal(originalClose, original, []) === false) {
        throw new TypeError('InstalledSourceProfileCleanupPending');
      }
      physicallyClosed = true;
    }
    for (const task of computations) {
      if (!task.settled) throw invalidIo();
      if (task.name === 'begin') {
        if (!validOperation(task.value)) throw task.cause ?? invalidIo();
        pending.add({operation: task.value, accounted: true});
      }
      // A charge with an unexpected result may already have debited bytes.
      // Never issue a second debit on the strength of Promise settlement.
      if (task.name === 'charge') throw task.cause ?? invalidIo();
      computations.delete(task);
    }
    for (const record of pending) finish(record);
    original = originalClose = undefined;
  }
  let failure, readFailed = false;
  try {
    // This operation retains the opened FD lease until its original close.
    // Separate reads/stat use their own actual attempt and transfer windows.
    begin(0);
    original = await openFile(path, 'r');
    captureClose();
    const selected = io === undefined ? original : Object.freeze({
      async read(buffer, offset, length, position) {
        const method = captureMethod('read'), record = begin(length);
        const result = await applyOriginal(method, original, [buffer, offset, length, position]);
        const received = result.bytesRead;
        if (!Number.isSafeInteger(received) || received < 0 || received > length) {
          throw new TypeError('InvalidInstalledSourceProfileRead');
        }
        record.extent = received;
        finish(record);
        // Snapshot the original native extent before any later callback can
        // replace its result fields. No body or payload is copied here.
        return Object.freeze({bytesRead: received});
      },
      async stat() {
        const method = captureMethod('stat'), record = begin(0);
        const result = await applyOriginal(method, original, []);finish(record);return result;
      },
    });
    return await consume(selected);
  } catch (cause) {
    readFailed = true;failure = cause;throw cause;
  } finally {
    try {
      // Preserve the legacy no-handle open failure unchanged. A failed method
      // observation never retries that getter inside the same intake attempt.
      if (original !== undefined && originalClose === undefined) throw failure;
      await cleanup();
    } catch (cause) {
      const first = cause;
      let latest = cause, flight;
      const status = () => Object.freeze({pending: original !== undefined || pending.size !== 0 || computations.size !== 0,
        errors: Object.freeze(first === latest ? [first] : [first, latest])});
      const retry = () => {
        if (flight !== undefined) return flight;
        flight = (async () => {
          try {
            for (const task of computations) if (!task.settled) await task.completion;
            await cleanup();
          } catch (error) {latest = error;throw error;}
          return status();
        })().finally(() => {flight = undefined;});
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
