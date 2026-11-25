// Process-local installed Store wiring. Neither Core nor a receiving connector
// obtains filenames, file descriptors or a producer-specific runtime here.
// This is access to provisional bytes, not completion or identity authority.
import type {DelegatedReadLease} from './files.mjs';

type FileAccess = Readonly<Pick<DelegatedReadLease, 'path'> & Partial<Pick<DelegatedReadLease, 'bytes'>>>;
type ByteConsumer = (chunk: Uint8Array) => unknown;
type FileAccounting = (bytes: number) => unknown;
type StoredBody = Readonly<{
  consume(accept: ByteConsumer, signal?: AbortSignal): unknown;
  nativeFilePath?(): string | undefined;
  withVerifiedFile?<Value>(use: (file: FileAccess) => Value, signal?: AbortSignal,
    beforeRead?: FileAccounting): Value | PromiseLike<Value | undefined>;
}>;
type Contract = Readonly<{wire: Readonly<Record<string, unknown>>; maxFrameBytes: number}>;
type Representation = Readonly<{readable: (input: unknown) => boolean; body: StoredBody; contract: Contract}>;
const representations = new WeakMap<object, Representation>();

export function registerRetainedInput(material: object, readable: Representation['readable'], body: StoredBody,
  configuration: Contract) {
  if (material === null || typeof material !== 'object' || representations.has(material) ||
      typeof readable !== 'function' || typeof body?.consume !== 'function') {
    throw new TypeError('InvalidRetainedInputRegistration');
  }
  const contract = Object.freeze({
    wire: Object.freeze({...configuration.wire}),
    maxFrameBytes: configuration.maxFrameBytes,
  });
  representations.set(material, Object.freeze({readable, body, contract}));
}

function admitted(material: object, input: unknown) {
  const held = representations.get(material);
  if (!held || input == null || !held.readable(input)) {
    throw Object.assign(new Error('RetainedInputUnavailable'), {code: 'RetainedInputUnavailable'});
  }
  return held;
}

export function retainedInputContract(material: object, input: unknown) {
  return admitted(material, input).contract;
}

// Capability discovery is not permission to use a path. The exact input grant
// is checked again on both sides of the awaited native read below.
export function retainedInputSupportsFile(material: object, input: unknown) {
  const body = admitted(material, input).body;
  return typeof body.withVerifiedFile === 'function' && typeof body.nativeFilePath === 'function';
}

// Installed transport allowlist only; content remains provisional until the
// borrowed read verifies it. Neither path nor this lookup grants completion.
export function retainedInputFilePath(material: object, input: unknown) {
  const body = admitted(material, input).body;
  if (typeof body.nativeFilePath !== 'function') throw new TypeError('UnsupportedRetainedFileAccess');
  return body.nativeFilePath();
}

export async function withRetainedInputFile<Value>(material: object, input: unknown, use: (file: FileAccess) => Value,
  signal?: AbortSignal, beforeRead?: FileAccounting) {
  signal?.throwIfAborted();
  const held = admitted(material, input);
  if (typeof held.body.withVerifiedFile !== 'function' || typeof use !== 'function') {
    throw new TypeError('UnsupportedRetainedFileAccess');
  }
  const value = await held.body.withVerifiedFile(async file => {
    signal?.throwIfAborted();
    admitted(material, input);
    return use(file);
  }, signal, beforeRead === undefined ? undefined : bytes => {
    signal?.throwIfAborted();
    admitted(material, input);
    return beforeRead(bytes);
  });
  signal?.throwIfAborted();
  admitted(material, input);
  return value;
}

// Installed Store custody wiring only. The caller must obtain material from
// genuine completion evidence; this lookup itself is not a consumer grant.
// Concrete paths/session tokens remain behind the Store's opaque body handle.
export function retainedStorageBody(material: object) {
  const held = representations.get(material);
  if (!held) throw new TypeError('ForeignRetainedStorage');
  return held.body;
}

// Same installed transfer/custody boundary as retainedStorageBody. No consumer
// permission is implied; the transfer must validate its exact owned storage.
export function retainedStorageContract(material: object) {
  const held = representations.get(material);
  if (!held) throw new TypeError('ForeignRetainedStorage');
  return held.contract;
}

// The consumer's own decoder and identity verification must finish before it
// publishes anything. Even a consumer that catches a read failure lacks success.
export async function consumeRetainedInput(material: object, input: unknown, accept: ByteConsumer, signal?: AbortSignal) {
  signal?.throwIfAborted();
  const held = admitted(material, input);
  await held.body.consume(accept, signal);
  signal?.throwIfAborted();
  admitted(material, input);
}
