// Private physical reading only. This does not admit a Model response, issue
// evidence, decide remote success/stop, or enable an installed async profile.
// Fund the fixed backing buffer, one borrowed stream chunk, header originals,
// reader, pending read/abort wait and cancellation in the shared retention sum
// before use. Returning an incomplete view does not release those obligations.
const positive = value => Number.isSafeInteger(value) && value > 0;
const fail = code => { throw Object.assign(new TypeError(code), {code}); };

// Fixed once before the final Core send gate, never rebuilt from Run values.
export function fixedInferResponseLimits({
  maxBytes, maxChunkBytes, maxChunks, observedHeaders = [], maxHeaderBytes,
}) {
  if (!positive(maxBytes) || maxBytes > 2_147_483_647 ||
      !positive(maxChunkBytes) || maxChunkBytes > maxBytes ||
      !positive(maxChunks) || maxChunks > 2_147_483_647 ||
      !positive(maxHeaderBytes) || maxHeaderBytes > 65_536 ||
      !Array.isArray(observedHeaders) || observedHeaders.length > 16 ||
      new Set(observedHeaders).size !== observedHeaders.length ||
      observedHeaders.some(name => typeof name !== 'string' ||
        name.length > 64 || !/^[a-z0-9][a-z0-9-]*$/u.test(name))) {
    fail('InvalidInferResponseReader');
  }
  return Object.freeze({maxBytes, maxChunkBytes, maxChunks, maxHeaderBytes,
    observedHeaders: Object.freeze([...observedHeaders])});
}

export async function readBoundedInferResponse(response, inputLimits, signal) {
  const {maxBytes, maxChunkBytes, maxChunks, observedHeaders, maxHeaderBytes} =
    fixedInferResponseLimits(inputLimits);
  if ((signal !== undefined && !(signal instanceof AbortSignal)) ||
      !Number.isInteger(response?.status) || response.status < 200 ||
      response.status > 599 || typeof response.headers?.get !== 'function' ||
      (response.body !== null && typeof response.body?.getReader !== 'function')) {
    fail('InvalidInferResponseReader');
  }
  const status = response.status;
  const headers = [];
  let headerBytes = 0;
  for (const name of observedHeaders) {
    const value = response.headers.get(name);
    if (value === null) continue;
    if (typeof value !== 'string' || value.length > maxHeaderBytes) {
      fail('InferResponseHeaderLimit');
    }
    const bytes = Buffer.byteLength(value);
    if (bytes > maxHeaderBytes - headerBytes) fail('InferResponseHeaderLimit');
    headerBytes += bytes;
    headers.push(Object.freeze([name, value]));
  }
  if (response.body === null) {
    // An actually empty HTTP body is not a NULL answer or an adopted success.
    return Object.freeze({status, headers: Object.freeze(headers),
      body: new Uint8Array(0), observedBytes: 0, transportComplete: true,
      issue: undefined, readerRetirement: Promise.resolve(true),
      retryReaderRetirement: () => Promise.resolve(true)});
  }
  // Content-Length is never used as the decoded-body bound. Do not call
  // text/json/arrayBuffer, clone or tee before the finite byte check.
  const backing = new Uint8Array(maxBytes);
  const reader = response.body.getReader();
  let heldReader = reader;
  let retiring;
  let pendingRead;
  let wakeRead;
  const retryReaderRetirement = () => {
    if (heldReader === undefined) return Promise.resolve(true);
    if (retiring !== undefined) return retiring;
    let cancellation;
    try { cancellation = heldReader.cancel(); }
    catch { cancellation = Promise.reject(new Error('InferReaderCancelFailed')); }
    // An abort-ignoring read remains an original physical obligation even
    // when cancel resolves. Never report reader retirement from cancel alone.
    retiring = Promise.resolve(cancellation).then(() => pendingRead).then(() => {
      try {
        heldReader.releaseLock();
        heldReader = undefined;
        pendingRead = undefined;
        return true;
      } catch { return false; }
    }, () => false).finally(() => { retiring = undefined; });
    return retiring;
  };
  let aborted = signal?.aborted ?? false;
  const abort = () => {
    aborted = true;
    wakeRead?.({cancelled: true});
    void retryReaderRetirement();
  };
  signal?.addEventListener('abort', abort, {once: true});
  let length = 0;
  let observedBytes = 0;
  let chunks = 0;
  let issue;
  for (;;) {
    if (aborted) { issue = 'InferResponseReadCancelled'; break; }
    let observed;
    try {
      // Preserve the same physical read, including its late rejection/value.
      // Cancellation can expose an incomplete prefix without waiting for a
      // read that ignores abort; cleanup still owns that pending operation.
      pendingRead = Promise.resolve(reader.read()).then(next => ({next}),
        () => ({failed: true}));
      if (aborted) { issue = 'InferResponseReadCancelled'; break; }
      observed = signal === undefined ? await pendingRead
        : await new Promise(resolve => {
          wakeRead = resolve;
          pendingRead.then(resolve);
        });
      wakeRead = undefined;
    } catch { issue = 'InferResponseReadFailed'; break; }
    if (aborted) { issue = 'InferResponseReadCancelled'; break; }
    pendingRead = undefined;
    if (observed.failed) { issue = 'InferResponseReadFailed'; break; }
    const next = observed.next;
    if (next.done) {
      signal?.removeEventListener('abort', abort);
      try { reader.releaseLock(); heldReader = undefined; }
      catch { /* Retain the same physical reader for cleanup retry. */ }
      return Object.freeze({status,
        headers: Object.freeze(headers), body: backing.subarray(0, length),
        observedBytes, transportComplete: true, issue: undefined,
        readerRetirement: Promise.resolve(heldReader === undefined),
        retryReaderRetirement});
    }
    const chunk = next.value;
    if (!(chunk instanceof Uint8Array)) {
      issue = 'InferResponseChunkInvalid';
      break;
    }
    observedBytes = observedBytes !== undefined &&
      chunk.byteLength <= Number.MAX_SAFE_INTEGER - observedBytes
      ? observedBytes + chunk.byteLength : undefined;
    if (chunks === maxChunks) { issue = 'InferResponseChunkCountLimit'; break; }
    chunks++;
    if (chunk.byteLength > maxChunkBytes || chunk.byteLength > maxBytes - length) {
      issue = chunk.byteLength > maxChunkBytes
        ? 'InferResponseChunkLimit' : 'InferResponseByteLimit';
      break;
    }
    backing.set(chunk, length);
    length += chunk.byteLength;
  }
  signal?.removeEventListener('abort', abort);
  // Retain the exact accepted prefix on failure. It is explicitly incomplete,
  // not an adopted answer or evidence that the original call was unexecuted.
  // Cancellation may still be pending after this observation. Its promise is
  // not physical-stop or Core-cleanup proof; a failed retirement stays false.
  const readerRetirement = retryReaderRetirement();
  return Object.freeze({status,
    headers: Object.freeze(headers), body: backing.subarray(0, length),
    observedBytes, transportComplete: false, issue, readerRetirement,
    retryReaderRetirement});
}
