// Process-local installed Store wiring. Neither Core nor a receiving connector
// obtains filenames, file descriptors or a producer-specific runtime here.
// This is access to provisional bytes, not completion or identity authority.
const representations = new WeakMap();

export function registerRetainedInput(material, readable, body, configuration) {
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

function admitted(material, input) {
  const held = representations.get(material);
  if (!held || input == null || !held.readable(input)) {
    throw Object.assign(new Error('RetainedInputUnavailable'), {code: 'RetainedInputUnavailable'});
  }
  return held;
}

export function retainedInputContract(material, input) {
  return admitted(material, input).contract;
}

// Capability discovery is not permission to use a path. The exact input grant
// is checked again on both sides of the awaited native read below.
export function retainedInputSupportsFile(material, input) {
  return typeof admitted(material, input).body.withVerifiedFile === 'function';
}

export async function withRetainedInputFile(material, input, use, signal) {
  signal?.throwIfAborted();
  const held = admitted(material, input);
  if (typeof held.body.withVerifiedFile !== 'function' || typeof use !== 'function') {
    throw new TypeError('UnsupportedRetainedFileAccess');
  }
  const value = await held.body.withVerifiedFile(async file => {
    signal?.throwIfAborted();
    admitted(material, input);
    return use(file);
  }, signal);
  signal?.throwIfAborted();
  admitted(material, input);
  return value;
}

// Installed Store custody wiring only. The caller must obtain material from
// genuine completion evidence; this lookup itself is not a consumer grant.
// Concrete paths/session tokens remain behind the Store's opaque body handle.
export function retainedStorageBody(material) {
  const held = representations.get(material);
  if (!held) throw new TypeError('ForeignRetainedStorage');
  return held.body;
}

// Same installed transfer/custody boundary as retainedStorageBody. No consumer
// permission is implied; the transfer must validate its exact owned storage.
export function retainedStorageContract(material) {
  const held = representations.get(material);
  if (!held) throw new TypeError('ForeignRetainedStorage');
  return held.contract;
}

// The consumer's own decoder and identity verification must finish before it
// publishes anything. Even a consumer that catches a read failure lacks success.
export async function consumeRetainedInput(material, input, accept, signal) {
  signal?.throwIfAborted();
  const held = admitted(material, input);
  await held.body.consume(accept, signal);
  signal?.throwIfAborted();
  admitted(material, input);
}
