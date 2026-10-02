// Physical custody of one encrypted private publication body. The semantic
// binding must already have been issued by the MoonBit publication owner.
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

export function preparePrivatePublicationHolding(store, binding) {
  if (!store || typeof store.confirmPrivateEvidence !== 'function' ||
      typeof store.preparePrivateEvidence !== 'function' ||
      typeof store.commitPhysicalHolding !== 'function' ||
      !binding || !['effect_preview', 'effect_capture', 'model_capture_bundle',
        'model_slot_capture', 'model_call_attempt', 'model_attempt_accounting',
        'model_attempt_outcome', 'model_dispatch_authority', 'observation_set',
        'run_invocation']
        .includes(binding.name) ||
      typeof binding.semanticCid !== 'string' ||
      typeof binding.holdingCid !== 'string' ||
      typeof binding.wire !== 'string') {
    fail('InvalidPrivatePublicationHolding');
  }
  const owned = Object.freeze({...binding});
  let prepared;
  let record;
  let committed = false;
  let abandoned = false;
  let abandoning = false;
  let flight;
  let abortFlight;
  const releaseUnused = async () => {
    if (prepared?.status().pending === true) await prepared.release();
  };
  const confirm = () => store.confirmPrivateEvidence(owned);
  const status = () => Object.freeze({
    committed, abandoned, abandoning,
    operationPending: flight !== undefined || abortFlight !== undefined,
    preparedPending: prepared?.status().pending === true,
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
          return existing;
        }
        if (prepared === undefined) {
          const encrypted = await store.preparePrivateEvidence(
            owned.name, owned.wire, owned.semanticCid,
          );
          prepared = encrypted.prepared;
          record = Object.freeze({
            version: 'actql-local-physical-holding/0.1',
            namespace: 'publication-private',
            holding_cid: owned.holdingCid,
            manifest_cid: owned.semanticCid,
            objects: Object.freeze([Object.freeze({
              cid: encrypted.physicalCid, byte_count: encrypted.bytes,
            })]),
          });
        }
        try {
          await store.commitPhysicalHolding(record, [prepared]);
        } catch (error) {
          let reconciled;
          try { reconciled = await confirm(); }
          catch (failure) { error.reconciliationFailure = failure; }
          if (reconciled === undefined) throw error;
        }
        const verified = await confirm();
        if (verified === undefined) fail('PrivatePublicationHoldingUnknown');
        await releaseUnused();
        record = verified;
        committed = true;
        return verified;
      })().catch(error => {
        if (prepared?.status().pending === true) {
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
          record = existing;
          committed = true;
          return false;
        }
        await releaseUnused();
        abandoned = true;
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
