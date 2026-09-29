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
    ['begin', 'next', 'finish', 'identity', 'cancel',
      'payloadFailureAction', 'cleanupOwnerAction']
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
    typeof value.resultSchemaWire === 'string' &&
    Array.isArray(value.resultFields) && value.resultFields.length > 0 &&
    new Set(value.resultFields).size === value.resultFields.length &&
    value.resultFields.every(field =>
      typeof field === 'string' && field.length > 0) &&
    /^sha256:[0-9a-f]{64}$/u.test(value.codecContractCid) &&
    ['bytes', 'nodes', 'rows'].every(name =>
      Number.isSafeInteger(value[name]) && value[name] >= 0) &&
    ['schemaBytes', 'schemaNodes', 'schemaFields'].every(name =>
      Number.isSafeInteger(value[name]) && value[name] >= 0) &&
    new TextEncoder().encode(value.resultSchemaWire).byteLength ===
      value.schemaBytes;
}

function payloadFailure(reason, cleanupErrors, cleanupOwners, control) {
  // The caller's throwable can be a primitive or an immutable Error. Keep all
  // cleanup metadata on an envelope owned by this adapter.
  const failure = new DurableResultPayloadError(
    'DurableResultPayloadFailed', reason,
  );
  failure.primaryFailure = reason;
  const status = () => Object.freeze({
    pending: cleanupOwners.some(owner => owner.pending()),
    errors: Object.freeze([...cleanupErrors]),
  });
  const update = () => {
    const current = status();
    failure.cleanupPending = current.pending;
    failure.cleanupErrors = current.errors;
    return current;
  };
  if (status().pending) {
    failure.cleanupHandle = Object.freeze({
      status,
      async retry() {
        let currentOwner = 0;
        let statusChecked = false;
        let pending = false;
        let retryAvailable = false;
        let retryAttempted = false;
        while (true) {
          const action = control.cleanupOwnerAction(
            currentOwner,
            cleanupOwners.length,
            statusChecked,
            pending,
            retryAvailable,
            retryAttempted,
          );
          if (action === 'inspect') {
            pending = cleanupOwners[currentOwner].pending();
            retryAvailable = typeof cleanupOwners[currentOwner].retry ===
              'function';
            statusChecked = true;
            continue;
          }
          if (action === 'retry') {
            retryAttempted = true;
            try { await cleanupOwners[currentOwner].retry(); }
            catch (error) { cleanupErrors.push(error); }
            continue;
          }
          if (action === 'advance') {
            currentOwner++;
            statusChecked = false;
            pending = false;
            retryAvailable = false;
            retryAttempted = false;
            continue;
          }
          if (action === 'finished') break;
          fail('InvalidDurableResultPayloadCleanupProgress');
        }
        return update();
      },
    });
  }
  update();
  return failure;
}

function preparedResultOwners(physical, schema) {
  const owners = [physical, schema];
  const status = () => Object.freeze({
    pending: owners.some(owner => owner.status().pending === true),
    errors: Object.freeze(owners.flatMap(owner =>
      owner.status().errors ?? [])),
  });
  const release = async () => {
    let changed = false;
    for (const owner of owners) {
      if (owner.status().pending !== true) continue;
      await owner.release();
      changed = true;
    }
    return changed;
  };
  return Object.freeze({
    status,
    release,
    async retry() {
      await release();
      return status();
    },
  });
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
  beginResult,
) {
  if (!validStore(store) ||
      typeof store.createPreparedObjectWriter !== 'function' ||
      typeof store.putPreparedResultSchema !== 'function' ||
      !validResultControl(control) ||
      typeof control.issueResultEvidence !== 'function' ||
      publication === null || typeof publication !== 'object' ||
      typeof publication.control?.issueResultArtifact !== 'function' ||
      typeof publication.control?.issueDurableResultBinding !== 'function' ||
      typeof publication.control?.admitCompletedResultSnapshot !==
        'function' ||
      !/^sha256:[0-9a-f]{64}$/u.test(
        publication.runDefinition?.identity,
      ) ||
      !Number.isSafeInteger(result) || result < 0) {
    fail('InvalidDurableResultPayloadAdapter');
  }
  return storeCompletedPayload(
    store,
    control,
    () => typeof beginResult === 'function'
      ? beginResult(host, result, limits)
      : control.beginResult(host, result, limits),
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
      const snapshot = publication.control.admitCompletedResultSnapshot(
        handle,
        publication.limits,
      );
      return Object.freeze({...evidence, artifact, snapshot});
    },
    (physical, orderedRows, evidence) =>
      publication.control.issueDurableResultBinding({
        runDefinition: publication.runDefinition,
        definition: publication.definition,
        invocation: publication.invocation,
        artifact: evidence.artifact,
        ordering: evidence.ordering,
        retention: publication.retention,
      }, {
        codecContractCid: orderedRows.codecContractCid,
        resultFields: orderedRows.resultFields,
        resultSchemaWire: orderedRows.resultSchemaWire,
        materialGenerationCid: physical.cid,
        storeAuthorityCid: store.storeAuthorityCid,
        rowCount: orderedRows.rows,
        byteCount: physical.bytes,
        physicalSha256: physical.cid.slice('sha256:'.length),
      }, publication.limits),
    true,
    publication.runDefinition.identity,
  );
}

async function storeCompletedPayload(
  store,
  control,
  beginExport,
  limits,
  signal,
  issueEvidence,
  issuePhysicalEvidence,
  preparePhysical = false,
  schemaRunDefinitionCid,
) {
  signal?.throwIfAborted();
  let exportHandle;
  let writer;
  let prepared;
  let schema;
  let sealed = false;
  let exportReleased = false;
  try {
    exportHandle = await beginExport();
    writer = preparePhysical
      ? store.createPreparedObjectWriter(limits.maxWireBytes)
      : store.createObjectWriter(limits.maxWireBytes);
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
    if (publication !== undefined) {
      schema = await store.putPreparedResultSchema(
        orderedRows.resultSchemaWire,
        orderedRows.resultSchemaCid,
        schemaRunDefinitionCid,
      );
      prepared = schema.prepared;
    }
    const sealedPhysical = await writer.seal(orderedRows.orderedRowsCid);
    if (schema !== undefined) {
      prepared = preparedResultOwners(sealedPhysical.prepared, schema.prepared);
    } else {
      prepared = sealedPhysical.prepared;
    }
    const physical = Object.freeze({
      cid: sealedPhysical.cid,
      bytes: sealedPhysical.bytes,
      created: sealedPhysical.created,
    });
    sealed = true;
    if (physical.bytes !== orderedRows.bytes ||
        physical.cid !== orderedRows.orderedRowsCid) {
      fail('DurableResultPayloadIdentityMismatch');
    }
    const durableBinding = issuePhysicalEvidence?.(
      physical, orderedRows, publication,
    );
    control.cancel(exportHandle);
    exportReleased = true;
    return Object.freeze({
      physical: Object.freeze({...physical}),
      orderedRows: Object.freeze({...orderedRows}),
      ...(publication === undefined ? {} : {
        publication: Object.freeze({...publication, durableBinding}),
        schema: Object.freeze({
          semanticCid: schema.semanticCid,
          physical: schema.physical,
          created: schema.created,
        }),
        physicalPrepared: sealedPhysical.prepared,
        prepared,
      }),
    });
  } catch (reason) {
    const cleanupErrors = [];
    const cleanupOwners = [];
    if (reason?.cleanupPending === true &&
        reason.cleanupHandle !== undefined) {
      cleanupOwners.push(Object.freeze({
        pending: () => reason.cleanupHandle.status().pending === true,
        retry: () => reason.cleanupHandle.retry(),
      }));
    }
    let writerCancelAttempted = false;
    let preparedReleaseAttempted = false;
    let exportCancelAttempted = false;
    let preparedPending = false;
    if (prepared !== undefined) {
      try { preparedPending = prepared.status().pending === true; }
      catch (error) {
        cleanupErrors.push(error);
        preparedPending = true;
      }
    }
    while (true) {
      const action = control.payloadFailureAction(
        writer !== undefined,
        sealed,
        writerCancelAttempted,
        preparedPending,
        preparedReleaseAttempted,
        exportHandle !== undefined,
        exportReleased,
        exportCancelAttempted,
      );
      if (action === 'cancel_writer') {
        writerCancelAttempted = true;
        try { await writer.cancel(); }
        catch (error) {
          cleanupErrors.push(error);
          cleanupOwners.push(Object.freeze({
            pending: () => writer.status().reservationHeld === true ||
              writer.status().custodyPending === true,
            retry: () => writer.cancel(),
          }));
        }
        continue;
      }
      if (action === 'release_prepared') {
        preparedReleaseAttempted = true;
        try { await prepared.release(); }
        catch (error) {
          cleanupErrors.push(error);
          cleanupOwners.push(Object.freeze({
            pending: () => prepared.status().pending === true,
            retry: () => prepared.retry(),
          }));
        }
        continue;
      }
      if (action === 'cancel_export') {
        exportCancelAttempted = true;
        try {
          control.cancel(exportHandle);
          exportReleased = true;
        } catch (error) {
          cleanupErrors.push(error);
          cleanupOwners.push(Object.freeze({
            pending: () => !exportReleased,
            retry: async () => {
              control.cancel(exportHandle);
              exportReleased = true;
            },
          }));
        }
        continue;
      }
      if (action === 'finished') break;
      fail('InvalidDurableResultPayloadFailureProgress');
    }
    throw payloadFailure(reason, cleanupErrors, cleanupOwners, control);
  }
}
