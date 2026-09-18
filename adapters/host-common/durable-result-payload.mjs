// Physical adapter for one MoonBit-owned canonical CompletedOutput export.
// It streams batches directly to an installed durable Store. Logical Result
// identity, Artifact admission, publication commit, and retention remain
// separate common-core decisions.

export class DurableResultPayloadError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
  }
}

const fail = (code, cause) => {
  throw new DurableResultPayloadError(code, cause);
};

function validStore(store) {
  return store !== null && typeof store === 'object' &&
    typeof store.createObjectWriter === 'function';
}

function validControl(control) {
  return control !== null && typeof control === 'object' &&
    ['begin', 'next', 'finish', 'identity', 'cancel']
      .every(name => typeof control[name] === 'function');
}

function validIdentity(value) {
  return value !== null && typeof value === 'object' &&
    /^sha256:[0-9a-f]{64}$/u.test(value.orderedRowsCid) &&
    /^sha256:[0-9a-f]{64}$/u.test(value.logicalRelationCid) &&
    ['bytes', 'nodes', 'rows'].every(name =>
      Number.isSafeInteger(value[name]) && value[name] >= 0);
}

function payloadFailure(reason, cleanupErrors) {
  const failure = reason instanceof Error
    ? reason
    : new DurableResultPayloadError('DurableResultPayloadFailed', reason);
  if (cleanupErrors.length !== 0) {
    failure.cleanupErrors = Object.freeze([...cleanupErrors]);
  }
  return failure;
}

/// Stream an exact completed output without materializing a whole row array in
/// JavaScript. The ordered-row receipt and physical object identity are kept as
/// distinct typed fields even when this codec makes their SHA-256 values equal.
export async function storeCompletedOutputPayload(
  store, control, output, limits, signal,
) {
  if (!validStore(store) || !validControl(control)) {
    fail('InvalidDurableResultPayloadAdapter');
  }
  signal?.throwIfAborted();
  let exportHandle;
  let writer;
  let sealed = false;
  let exportReleased = false;
  try {
    exportHandle = control.begin(output, limits);
    writer = store.createObjectWriter(limits.maxWireBytes);
    for (;;) {
      signal?.throwIfAborted();
      const part = control.next(exportHandle);
      if (part === undefined) break;
      if (typeof part !== 'string') fail('InvalidDurableResultPayloadBatch');
      if (part.length !== 0) await writer.append(part);
    }
    signal?.throwIfAborted();
    const tail = control.finish(exportHandle);
    if (typeof tail !== 'string') fail('InvalidDurableResultPayloadBatch');
    if (tail.length !== 0) await writer.append(tail);
    signal?.throwIfAborted();
    const orderedRows = control.identity(exportHandle);
    if (!validIdentity(orderedRows)) {
      fail('InvalidDurableResultPayloadIdentity');
    }
    const physical = await writer.seal(orderedRows.orderedRowsCid);
    sealed = true;
    if (physical.bytes !== orderedRows.bytes ||
        physical.cid !== orderedRows.orderedRowsCid) {
      fail('DurableResultPayloadIdentityMismatch');
    }
    control.cancel(exportHandle);
    exportReleased = true;
    return Object.freeze({
      physical: Object.freeze({...physical}),
      orderedRows: Object.freeze({...orderedRows}),
    });
  } catch (reason) {
    const cleanupErrors = [];
    if (writer !== undefined && !sealed) {
      try { await writer.cancel(); }
      catch (error) { cleanupErrors.push(error); }
    }
    if (exportHandle !== undefined && !exportReleased) {
      try { control.cancel(exportHandle); }
      catch (error) { cleanupErrors.push(error); }
    }
    throw payloadFailure(reason, cleanupErrors);
  }
}
