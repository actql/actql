// Bound installed Source configuration and identity metadata before buffering.
// This does not make separate identity and installation reads one snapshot.
import {open} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {types} from 'node:util';

// Static views of existing native methods and cleanup DATA. They do not
// authorize I/O, certify currentness or acknowledge physical retirement.
type Method = (...args: unknown[]) => unknown;
interface ReadFileOriginal {
  read(buffer: Buffer, offset: number, length: number, position: null): Promise<{bytesRead: number}>;
  stat(): Promise<{size: number}>;
  close: Method;
}
type ReadFileSelection = Pick<ReadFileOriginal, 'read' | 'stat'>;
interface ReadOptions {
  maxBytes?: number; openFile?: unknown; beforeRead?: unknown;
  beforeDecode?: unknown; beforeParse?: unknown; io?: unknown;
}
type PhysicalName = 'begin' | 'charge' | 'uncertain' | 'finish';
interface PendingIo {operation: unknown; accounted: boolean; ambiguous?: boolean; extent?: number}
interface Computation {name: PhysicalName; record?: PendingIo; settled: boolean;
  completion?: Promise<void>; value?: unknown; cause?: unknown}
interface CleanupCarrier {message?: unknown; cleanupHandle?: unknown; cleanupPending?: unknown}

export const installedConfigurationByteLimit = 8 * 1024 * 1024;
export const installedConfigurationChunkBytes = 64 * 1024;
const profileByteLimit = installedConfigurationByteLimit;
const chunkBytes = installedConfigurationChunkBytes;
const applyOriginal = Reflect.apply;

// Select original read methods only; this owns no I/O, authority or cleanup.
export function captureConfigurationReaders(reader: unknown, readJson: unknown, unavailable: () => unknown) {
  const refuse: () => never = () => {
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
  const prepareProfile = Object.getOwnPropertyDescriptor(reader, 'prepareProfile');
  const readProfile = Object.getOwnPropertyDescriptor(reader, 'readProfile');
  if (!json || !Object.hasOwn(json, 'value') || typeof json.value !== 'function' ||
      !text || !Object.hasOwn(text, 'value') || typeof text.value !== 'function' ||
      originalText !== undefined && (!Object.hasOwn(originalText, 'value') ||
        typeof originalText.value !== 'function') ||
      originalBytes !== undefined && (!Object.hasOwn(originalBytes, 'value') ||
        typeof originalBytes.value !== 'function') ||
      parseText !== undefined && (!Object.hasOwn(parseText, 'value') ||
        typeof parseText.value !== 'function') ||
      prepareProfile !== undefined && (!Object.hasOwn(prepareProfile, 'value') ||
        typeof prepareProfile.value !== 'function') ||
      readProfile !== undefined && (!Object.hasOwn(readProfile, 'value') ||
        typeof readProfile.value !== 'function')) refuse();
  // Capture the initializer's optional actual-FD text method before any read awaits.
  // Its absence cannot substitute a bounded reader or manufacture a byte ceiling.
  return Object.freeze({
    readJson: readJson ?? ((...args: unknown[]) => Reflect.apply(json!.value as Method, reader, args)),
    readText: (...args: unknown[]) => Reflect.apply(text!.value as Method, reader, args),
    ...(prepareProfile === undefined ? {} : {prepareProfile: (...args: unknown[]) => Reflect.apply(prepareProfile.value as Method, reader, args)}),
    ...(readProfile === undefined ? {} : {readProfile: (...args: unknown[]) => Reflect.apply(readProfile.value as Method, reader, args)}),
    ...(parseText === undefined ? {} : {
      parseJsonText: (...args: unknown[]) => Reflect.apply(parseText.value as Method, reader, args),
    }),
    ...(originalText === undefined ? {} : {
      readOriginalText: (...args: unknown[]) => Reflect.apply(originalText.value as Method, reader, args),
    }),
    ...(originalBytes === undefined ? {} : {
      readOriginalBytes: (...args: unknown[]) => Reflect.apply(originalBytes.value as Method, reader, args),
    }),
  });
}

export async function readSourceProfileJson(path: unknown,
  {maxBytes = profileByteLimit, openFile = open, beforeDecode, beforeParse, io}: ReadOptions = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes! < 0 ||
      maxBytes > profileByteLimit) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  if (beforeParse !== undefined && typeof beforeParse !== 'function') {
    throw new TypeError('InvalidInstalledConfigurationConstruction');
  }
  return readConfiguration(path, maxBytes!, openFile,
    bytes => {
      const wire = bytes.toString('utf8');
      // The SAME decoded original supplies construction geometry before the
      // native parser allocates a value tree. This callback is no validator.
      if (beforeParse !== undefined && beforeParse(wire) !== undefined) {
        throw new TypeError('InvalidInstalledConfigurationConstruction');
      }
      return JSON.parse(wire) as unknown;
    }, beforeDecode, io);
}

// Publications may have a different declared ceiling and hash their original
// UTF-8 text. Do not parse/reserialize them or impose the JSON profile ceiling.
export async function readBoundedConfigurationText(path: unknown, {maxBytes, openFile = open, beforeDecode, io}: ReadOptions = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes! < 0) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  return readConfiguration(path, maxBytes!, openFile, bytes => bytes.toString('utf8'), beforeDecode, io);
}

// Project originals must not replace malformed bytes with U+FFFD before the
// Common reader sees them. Keep a genuine BOM as text as well: its admission
// belongs to that reader, not to an implicit TextDecoder normalization.
export async function readBoundedConfigurationUtf8(path: unknown, {maxBytes, openFile = open, beforeDecode, io}: ReadOptions = {}) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes! < 0) {
    throw new TypeError('InvalidInstalledSourceProfileByteLimit');
  }
  return readConfiguration(path, maxBytes!, openFile, bytes =>
    new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(bytes), beforeDecode, io);
}

async function readConfiguration<T>(path: unknown, maxBytes: number, openFile: unknown, project: (bytes: Buffer) => T, beforeDecode: unknown, io: unknown) {
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
export async function readOriginalConfigurationText(path: unknown, options?: ReadOptions) {
  return readOriginalConfiguration(path, options, bytes => bytes.toString('utf8'));
}

// Preserve the exact original CA bytes. Its observed FD extent belongs to the
// same initializer as text/key input, rather than a borrowed secret ceiling.
export async function readOriginalConfigurationBytes(path: unknown, options?: ReadOptions) {
  return readOriginalConfiguration(path, options, bytes => bytes);
}

async function readOriginalConfiguration<T>(path: unknown,
  {openFile = open, beforeRead, beforeDecode, io}: ReadOptions = {}, project: (bytes: Buffer) => T) {
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

async function readConfigurationBody<T>(original: ReadFileSelection, maxBytes: number, project: (bytes: Buffer) => T, beforeDecode: unknown) {
    const chunks: Buffer[] = [];
    let bytes = 0;
    let used = 0;
    let buffer: Buffer | undefined = Buffer.allocUnsafe(Math.min(chunkBytes, maxBytes + 1));
    let joined: Buffer | undefined;
    try {
      for (;;) {
        // One lookahead byte distinguishes exact-limit EOF from an oversized
        // file, including one that grows after it is opened. Never readFile.
        const {bytesRead} = await original.read(buffer!, used,
          buffer!.length - used, null);
        if (bytesRead === 0) {
          chunks.push(buffer!.subarray(0, used));
          // The fixed initializer funds the received buffer/text overlap here;
          // JSON construction separately observes that SAME decoded String.
          // An absent port keeps the exact buffering/parsing semantics.
          if (beforeDecode !== undefined && (beforeDecode as (bytes: number) => unknown)(bytes) !== undefined) {
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
        if (used === buffer!.length) {
          chunks.push(buffer!);
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
export async function installedRuntimeBundleCid(path: unknown, {openFile = open, io}: ReadOptions = {}) {
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
function capturePhysicalIo(io: unknown) {
  if (io === undefined) return undefined;
  if (io === null || typeof io !== 'object' || Array.isArray(io) || types.isProxy(io)) {
    throw new TypeError('InvalidInstalledSourcePhysicalIo');
  }
  const fields = Object.getOwnPropertyDescriptors(io), methods = {} as Record<PhysicalName, Method>;
  const names = ['begin', 'charge', 'uncertain', 'finish'] as const;
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

export async function withOriginalFile<T>(path: unknown, openFile: unknown, consume: (selected: ReadFileSelection) => T | Promise<T>, physicalIo?: unknown) {
  const io = capturePhysicalIo(physicalIo), pending = new Set<PendingIo>(), computations = new Set<Computation>();
  let original: ReadFileOriginal | undefined, originalClose: Method | undefined, physicallyClosed = false;
  const invalidIo = () => new TypeError('InvalidInstalledSourcePhysicalIo');
  const validOperation = (value: unknown) => value !== null && typeof value === 'object' && !types.isProxy(value);
  function invokeIo(name: PhysicalName, args: unknown[], record?: PendingIo) {
    const value = applyOriginal(io!.methods[name], io!.receiver, args) as unknown;
    if (types.isPromise(value)) {
      // Join an unexpected computation to THIS original file cleanup owner.
      // Its settlement alone is no accounting or retirement acknowledgement.
      const task: Computation = {name, record, settled: false};computations.add(task);
      task.completion = Promise.resolve(value).then(result => {task.value = result;task.settled = true;},
        cause => {task.cause = cause;task.settled = true;});
      if (name === 'charge') record!.ambiguous = true;
      throw invalidIo();
    }
    if (name === 'begin' ? !validOperation(value) : value !== undefined) {
      if (name === 'charge') record!.ambiguous = true;
      throw invalidIo();
    }
    return value;
  }
  function begin(transfer: number) {
    if (io === undefined) return undefined;
    const operation = invokeIo('begin', [BigInt(transfer)]);
    const record: PendingIo = {operation, accounted: transfer === 0};pending.add(record);return record;
  }
  function finish(record: PendingIo) {
    if (!record.accounted) {
      if (record.ambiguous) throw invalidIo();
      if (record.extent === undefined) invokeIo('uncertain', [record.operation], record);
      else invokeIo('charge', [record.operation, BigInt(record.extent)], record);
      record.accounted = true;
    }
    invokeIo('finish', [record.operation], record);pending.delete(record);
  }
  function captureMethod(name: 'read' | 'stat') {
    const method = original![name];
    if (typeof method !== 'function') throw new TypeError('InstalledSourceProfileReadUnavailable');
    return method as unknown as Method;
  }
  const captureClose = () => {
    const observed = original!.close;
    if (typeof observed !== 'function') throw new TypeError('InstalledSourceProfileCloseUnavailable');
    originalClose = observed;
  };
  async function cleanup() {
    if (original !== undefined && !physicallyClosed) {
      if (originalClose === undefined) captureClose();
      if (await applyOriginal(originalClose!, original, []) === false) {
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
    for (const record of pending) finish(record!);
    original = originalClose = undefined;
  }
  let failure: unknown, readFailed = false;
  try {
    // This operation retains the opened FD lease until its original close.
    // Separate reads/stat use their own actual attempt and transfer windows.
    begin(0);
    original = await (openFile as (path: unknown, flags: string) => Promise<ReadFileOriginal>)(path, 'r');
    captureClose();
    const selected = io === undefined ? original : Object.freeze({
      async read(buffer: Buffer, offset: number, length: number, position: null) {
        const method = captureMethod('read'), record = begin(length);
        const result = await applyOriginal(method, original, [buffer, offset, length, position]) as {bytesRead: number};
        const received = result.bytesRead;
        if (!Number.isSafeInteger(received) || received < 0 || received > length) {
          throw new TypeError('InvalidInstalledSourceProfileRead');
        }
        record!.extent = received;
        finish(record!);
        // Snapshot the original native extent before any later callback can
        // replace its result fields. No body or payload is copied here.
        return Object.freeze({bytesRead: received});
      },
      async stat() {
        const method = captureMethod('stat'), record = begin(0);
        const result = await applyOriginal(method, original, []);finish(record!);return result as {size: number};
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
      let latest: unknown = cause, flight: Promise<Readonly<{pending: boolean; errors: readonly unknown[]}>> | undefined;
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
          const observed = (failure as CleanupCarrier | null | undefined)?.message;
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
        if ((primary as CleanupCarrier).cleanupHandle !== undefined || (primary as CleanupCarrier).cleanupPending === true ||
            Object.getOwnPropertyDescriptor(primary as object, 'cleanupHandle') !== undefined) throw primary;
        if (Object.getOwnPropertyDescriptor(primary as object, 'cleanupPending')?.configurable === false) throw primary;
        Object.defineProperties(primary as object, descriptors);
      } catch {
        exported = new Error('InstalledSourceProfileCleanupPending', {cause: primary});
        Object.defineProperties(exported, descriptors);
      }
      throw exported;
    }
  }
}
