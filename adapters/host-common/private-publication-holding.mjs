// Physical custody of one encrypted private publication body. The semantic
// binding must already have been issued by the MoonBit publication owner.
const fail = code => {
  throw Object.assign(new Error(code), {code});
};
const pendingCleanup = owner => Object.assign(
  new Error('PrivatePublicationHoldingCleanupPending'),
  {code: 'PrivatePublicationHoldingCleanupPending',
    cleanupPending: true, cleanupHandle: owner},
);

// Check all diagnostic slots before attaching any of them. Extensibility does
// not make existing own/inherited read-only properties or accessors writable.
// Keep that original failure as the cause without invoking diagnostic setters
// or replacing/recreating its custody owner.
const writableFailure = error => {
  if (error !== null && typeof error === 'object' && Object.isExtensible(error)) {
    let writable = true;
    for (const field of ['cleanupPending', 'cleanupHandle', 'reconciliationFailure']) {
      let receiver = error;
      while (receiver !== null) {
        const descriptor = Object.getOwnPropertyDescriptor(receiver, field);
        if (descriptor !== undefined) {
          if (descriptor.writable !== true) writable = false;
          break;
        }
        receiver = Object.getPrototypeOf(receiver);
      }
      if (!writable) break;
    }
    if (writable) return error;
  }
  const failure = new Error(error?.message, {cause: error});
  if (typeof error?.code === 'string') failure.code = error.code;
  return failure;
};

export function preparePrivatePublicationHolding(store, binding, rawBytes) {
  const lookupRaw = binding?.name === 'lookup_raw_response';
  const raw = lookupRaw || binding?.name === 'model_raw_response';
  const prepareRaw = lookupRaw ? 'prepareLookupRawEvidence' : 'prepareModelRawEvidence';
  const confirmRaw = lookupRaw ? 'confirmLookupRawEvidence' : 'confirmModelRawEvidence';
  if (!store || typeof (raw ? store[confirmRaw] :
      store.confirmPrivateEvidence) !== 'function' ||
      typeof (raw ? store[prepareRaw] :
        store.preparePrivateEvidence) !== 'function' ||
      typeof store.commitPhysicalHolding !== 'function' ||
      !binding || !['effect_preview', 'effect_capture', 'effect_catalog', 'credential_raw_observation', 'model_capture_bundle',
        'model_slot_capture', 'model_invocation_evidence', 'model_call_attempt', 'model_attempt_accounting',
        'model_attempt_outcome', 'model_dispatch_authority', 'model_attachment_admission', 'observation_set',
        'run_invocation', 'source_evidence', 'model_raw_response', 'lookup_raw_response', 'content_input_artifact',
        'content_evidence', 'content_generation', 'installation_publication']
        .includes(binding.name) ||
      typeof binding.semanticCid !== 'string' ||
      typeof binding.holdingCid !== 'string' ||
      typeof binding.wire !== 'string' ||
      (raw && !(rawBytes instanceof Uint8Array)) ||
      (!raw && rawBytes !== undefined)) {
    fail('InvalidPrivatePublicationHolding');
  }
  const owned = Object.freeze({...binding});
  // This is the original transport backing, not a reconstructed String.
  // Its retention is part of the Model caller's funded phase until retirement.
  let originalBytes = rawBytes;
  let prepared;
  let constructionCleanup;
  let record;
  let committed = false;
  let abandoned = false;
  let abandoning = false;
  let flight;
  let abortFlight;
  const releaseUnused = async () => {
    if (constructionCleanup !== undefined) {
      await constructionCleanup.release();
      // False can mean an already retired handle OR a still-owned visible
      // holding after an unknown commit. Only this same handle's status can
      // distinguish them; pending custody must survive for exact retry.
      if (constructionCleanup.status().pending !== false) throw pendingCleanup(owner);
      constructionCleanup = undefined;
    }
    for (const handle of prepared ?? []) {
      if (handle.status().pending === true) await handle.release();
      if (handle.status().pending !== false) throw pendingCleanup(owner);
    }
  };
  const rawBinding = raw ? Object.freeze({semanticCid: owned.semanticCid,
    holdingCid: owned.holdingCid, wire: owned.wire, contentCid: owned.contentCid,
    byteCount: owned.byteCount}) : undefined;
  const confirm = async () => raw
    ? (await store[confirmRaw](rawBinding))?.record
    : store.confirmPrivateEvidence(owned);
  const status = () => Object.freeze({
    committed, abandoned, abandoning,
    operationPending: flight !== undefined || abortFlight !== undefined,
    preparedPending: constructionCleanup !== undefined ||
      prepared?.some(handle => handle.status().pending === true) === true,
  });
  const owner = {
    binding: owned,
    status,
    retry() { return owner.commit(); },
    commit() {
      if (abandoned || abandoning) return Promise.reject(Object.assign(
        new Error('PrivatePublicationHoldingAbandoned'),
        {code: 'PrivatePublicationHoldingAbandoned'},
      ));
      if (flight !== undefined) return flight;
      if (committed) return Promise.resolve(record);
      let operation;
      operation = (async () => {
        const existing = await confirm();
        if (existing !== undefined) {
          await releaseUnused();
          record = existing;
          committed = true;
          // The same Store confirmation and prepared cleanup both succeeded.
          // Retire only this owner's aliases, not escaped handles or backing.
          prepared = undefined;
          originalBytes = undefined;
          return existing;
        }
        if (prepared === undefined) {
          if (constructionCleanup !== undefined) {
            await releaseUnused();
          }
          let encrypted;
          try {
            encrypted = raw ? await store[prepareRaw](
              rawBinding, originalBytes,
            ) : [await store.preparePrivateEvidence(
              owned.name, owned.wire, owned.semanticCid,
            )];
          } catch (error) {
            if (error?.cleanupPending === true && error.cleanupHandle !== undefined) {
              constructionCleanup = error.cleanupHandle;
            }
            throw error;
          }
          prepared = encrypted.map(object => object.prepared);
          record = Object.freeze({
            version: 'actql-local-physical-holding/0.1',
            namespace: 'publication-private',
            holding_cid: owned.holdingCid,
            manifest_cid: owned.semanticCid,
            objects: Object.freeze(encrypted.map(object => Object.freeze({
              cid: object.physicalCid, byte_count: object.bytes,
            }))),
          });
        }
        try {
          await store.commitPhysicalHolding(record, prepared);
        } catch (error) {
          let reconciled;
          try { reconciled = await confirm(); }
          catch (failure) {
            error = writableFailure(error);
            error.reconciliationFailure = failure;
          }
          if (reconciled === undefined) throw error;
        }
        const verified = await confirm();
        if (verified === undefined) fail('PrivatePublicationHoldingUnknown');
        await releaseUnused();
        record = verified;
        committed = true;
        prepared = undefined;
        originalBytes = undefined;
        return verified;
      })().catch(error => {
        if ((record !== undefined && !committed) || constructionCleanup !== undefined ||
            prepared?.some(handle => handle.status().pending === true)) {
          error = writableFailure(error);
          error.cleanupPending = true;
          error.cleanupHandle = owner;
        }
        throw error;
      }).finally(() => {
        if (flight === operation) flight = undefined;
      });
      flight = operation;
      return operation;
    },
    abort() {
      if (abortFlight !== undefined) return abortFlight;
      abandoning = true;
      let operation;
      operation = (async () => {
        if (flight !== undefined) {
          try { await flight; }
          catch { /* Reconcile against the Store below. */ }
        }
        const existing = await confirm();
        if (existing !== undefined) {
          await releaseUnused();
          record = existing;
          committed = true;
          prepared = undefined;
          originalBytes = undefined;
          return false;
        }
        await releaseUnused();
        abandoned = true;
        prepared = undefined;
        originalBytes = undefined;
        return true;
      })().finally(() => {
        if (abortFlight === operation) abortFlight = undefined;
        abandoning = false;
      });
      abortFlight = operation;
      return operation;
    },
  };
  return Object.freeze(owner);
}
