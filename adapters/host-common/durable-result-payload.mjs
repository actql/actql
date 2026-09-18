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

function validResultControl(control) {
  return validControl(control) && typeof control.beginResult === 'function';
}

function validIdentity(value) {
  return value !== null && typeof value === 'object' &&
    /^sha256:[0-9a-f]{64}$/u.test(value.orderedRowsCid) &&
    /^sha256:[0-9a-f]{64}$/u.test(value.logicalRelationCid) &&
    /^sha256:[0-9a-f]{64}$/u.test(value.resultSchemaCid) &&
    ['bytes', 'nodes', 'rows'].every(name =>
      Number.isSafeInteger(value[name]) && value[name] >= 0) &&
    ['schemaBytes', 'schemaNodes', 'schemaFields'].every(name =>
      Number.isSafeInteger(value[name]) && value[name] >= 0);
}

function payloadFailure(reason, cleanupErrors, writer) {
  const failure = reason instanceof Error
    ? reason
    : new DurableResultPayloadError('DurableResultPayloadFailed', reason);
  if (cleanupErrors.length !== 0) {
    failure.cleanupErrors = Object.freeze([...cleanupErrors]);
  }
  if (writer?.status().reservationHeld === true) {
    const status = () => Object.freeze({
      pending: writer.status().reservationHeld === true,
      errors: Object.freeze([...cleanupErrors]),
    });
    failure.cleanupPending = true;
    failure.cleanupHandle = Object.freeze({
      status,
      async retry() {
        if (writer.status().reservationHeld === true) {
          try { await writer.cancel(); }
          catch (error) { cleanupErrors.push(error); }
        }
        failure.cleanupPending = status().pending;
        failure.cleanupErrors = status().errors;
        return status();
      },
    });
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
  return storeCompletedPayload(
    store, control, () => control.begin(output, limits), limits, signal,
  );
}

/// Stream one exact checked Named Result from the common Host graph. The
/// adapter receives an index only; projection, ordering, and identity remain
/// bound to the opaque occurrence retained by the MoonBit runtime.
export async function storeCompletedResultPayload(
  store, control, host, result, limits, signal,
) {
  if (!validStore(store) || !validResultControl(control) ||
      !Number.isSafeInteger(result) || result < 0) {
    fail('InvalidDurableResultPayloadAdapter');
  }
  return storeCompletedPayload(
    store,
    control,
    () => control.beginResult(host, result, limits),
    limits,
    signal,
  );
}

/// Store and issue evidence for one exact Named Result export. Evidence is
/// issued before the physical object is sealed, so a failed issuance cannot
/// strand an otherwise unreferenced durable payload.
export async function storeCompletedResultPublicationPayload(
  store,
  control,
  host,
  result,
  limits,
  publication,
  signal,
) {
  if (!validStore(store) || !validResultControl(control) ||
      typeof control.issueResultEvidence !== 'function' ||
      publication === null || typeof publication !== 'object' ||
      typeof publication.control?.issueResultArtifact !== 'function' ||
      !Number.isSafeInteger(result) || result < 0) {
    fail('InvalidDurableResultPayloadAdapter');
  }
  return storeCompletedPayload(
    store,
    control,
    () => control.beginResult(host, result, limits),
    limits,
    signal,
    handle => {
      const evidence = control.issueResultEvidence(
        handle, publication.evidenceContext, publication.limits,
      );
      const artifact = publication.control.issueResultArtifact(
        handle,
        publication.invocation,
        publication.retention,
        publication.limits,
      );
      return Object.freeze({...evidence, artifact});
    },
  );
}

async function storeCompletedPayload(
  store, control, beginExport, limits, signal, issueEvidence,
) {
  signal?.throwIfAborted();
  let exportHandle;
  let writer;
  let sealed = false;
  let exportReleased = false;
  try {
    exportHandle = beginExport();
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
    const publication = issueEvidence?.(exportHandle);
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
      ...(publication === undefined ? {} : {publication}),
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
    throw payloadFailure(reason, cleanupErrors, writer);
  }
}
