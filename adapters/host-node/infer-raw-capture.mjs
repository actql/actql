import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {createHash} from 'node:crypto';

// Membership of a private physical port in the existing operation, not a new
// resource or grant Owner. A matching function/CID/copy is not this original.
const originalTransportPorts = new WeakMap();

// Preserve the same mutable primary error for existing consumers. An
// immutable Store/decoder failure cannot receive custody annotations; retain
// it as the cause of the existing raw-custody carrier instead of losing it to
// an assignment TypeError. The carrier is not a receipt or cleanup authority.
const retainedRawFailure = (error, facts) => {
  if (error !== null && typeof error === 'object' && Object.isExtensible(error)) {
    try { return Object.assign(error, facts); }
    catch { /* A read-only field cannot replace the original failure/custody. */ }
  }
  return Object.assign(new Error('ModelRawCustodyPending', {cause: error}), facts);
};

export function originalModelRawTransportPersistenceMatches(port, operation, registration) {
  const original = originalTransportPorts.get(port);
  return original !== undefined && original.operation.deref() === operation &&
    original.registration === registration;
}

const tuple = (value, length) => {
  const fields = Array.isArray(value) ? value
    : Array.from({length}, (_, index) => value?.[`_${index}`]);
  if (fields.length !== length || fields.some(field => field === undefined)) {
    throw Object.assign(new Error('InvalidModelRawCaptureProjection'),
      {code: 'InvalidModelRawCaptureProjection'});
  }
  return fields;
};

// Trusted installed adapter only, not an SDK registration or public read port.
// The view originates in the existing Model Owner. Reuse its original physical
// holding retry responsibility; no callback can issue a receipt from CID alone.
export function createModelRawCaptureStorePort(store, moon, view, bytes) {
  const current = () => checked(moon.clientProgramInferRawCaptureSaveCurrent(view));
  current();
  const [semanticCid, holdingCid, wire, contentCid, byteCount] = tuple(
    moon.clientProgramInferRawCaptureSaveBinding(view), 5,
  );
  const originals = moon.clientProgramInferRawCaptureSaveOriginals(view)
    .map(value => {
      const [kind, cid, wire] = tuple(value, 3);
      return Object.freeze({kind, cid, wire});
    });
  const binding = Object.freeze({semanticCid, holdingCid, wire, contentCid, byteCount});
  let storeReadCleanup;
  let storeReadFlight;
  // Only a failure from this trusted original Store read may supply this
  // handle. A caller's reported CID/error never supplies cleanup custody.
  const observeStoreRead = async read => {
    if (storeReadFlight !== undefined ||
        storeReadCleanup?.status().pending === true) {
      throw new TypeError('ModelRawReaderCleanupPending');
    }
    try { return await read(); }
    catch (error) {
      const handle = error?.cleanupHandle;
      if (typeof handle?.status === 'function' &&
          typeof handle?.retry === 'function' && handle.status().pending === true) {
        storeReadCleanup = handle;
      }
      throw error;
    }
  };
  const confirmRaw = actual => observeStoreRead(() => store.confirmModelRawEvidence(actual));
  // A narrow port, not another copy of the Store registry. Holding's own
  // reconciliation reads must retain the same failed reader handle too.
  const holding = preparePrivatePublicationHolding({
    confirmModelRawEvidence: confirmRaw,
    prepareModelRawEvidence: store.prepareModelRawEvidence,
    commitPhysicalHolding: store.commitPhysicalHolding,
  },
    {...binding, name: 'model_raw_response'}, bytes);
  const persist = async () => {
      let confirmed = false;
      try {
        current();
        await observeStoreRead(() => store.confirmModelRawCaptureOriginals(
          originals, store.storeAuthorityCid));
        current();
        await holding.commit();
        // Commit acknowledgement alone cannot supply the nominal receipt.
        // Reconfirm exact descriptor/body bytes and directory durability first.
        const saved = await confirmRaw(binding);
        if (saved === undefined) throw Object.assign(
          new Error('ModelRawCapturePersistenceUnknown'),
          {code: 'ModelRawCapturePersistenceUnknown'});
        confirmed = true;
        current();
        const receipt = checked(moon.clientProgramAcknowledgeSavedInferRawCapture(view));
        return Object.freeze({receipt, bytes: saved.bytes});
      } catch (error) {
        // Revocation after saving is not a proof of non-persistence. The
        // caller retains this original view and existing retry/cleanup handle;
        // neither reconciliation nor this failure authorizes another send.
        const facts = {
          rawPersistenceConfirmed: confirmed,
          rawCustodyRetained: true,
          cleanupHandle: holding,
        };
        if (!holding.status().committed || holding.status().preparedPending) {
          facts.cleanupPending = true;
        }
        throw retainedRawFailure(error, facts);
      }
  };
  return Object.freeze({
    holding,
    persist,
    cleanupStoreReads(notify) {
      if (storeReadFlight !== undefined) return false;
      if (storeReadCleanup === undefined) return true;
      if (storeReadCleanup.status().pending !== true) {
        storeReadCleanup = undefined;
        return true;
      }
      const original = storeReadCleanup;
      storeReadFlight = Promise.resolve().then(() => original.retry())
        .catch(() => { /* The same original reader stays pending. */ })
        .finally(() => {
          storeReadFlight = undefined;
          notify();
        });
      return false;
    },
    async persistChat(metadata) {
      const saved = await persist();
      try {
        // Preserve an observed BOM as U+FEFF, along with Unicode and newlines.
        // The descriptor and bytes have already been compared by the Store.
        const body = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true})
          .decode(saved.bytes);
        const response = checked(moon.clientProgramInferSavedRawChatResponse(
          saved.receipt, body, metadata,
        ));
        return Object.freeze({receipt: saved.receipt, response});
      } catch (error) {
        // Invalid UTF-8 is not a successful response, and cannot erase the
        // original raw receipt or turn saved custody into an unsent attempt.
        throw retainedRawFailure(error, {
          rawPersistenceConfirmed: true,
          rawCustodyRetained: true,
          rawReceipt: saved.receipt,
          cleanupHandle: holding,
        });
      }
    },
  });
}

// Trusted installed physical caller only. The parent retains this SAME Store
// holding before persistence, including callback/save failures. Core admits
// the descriptor from the original call and registration, not hand-built JSON.
export function createModelRawTransportPersistence({store, moon, registration,
  retainHolding, notify, operation}) {
  if (typeof retainHolding !== 'function' || typeof notify !== 'function') {
    throw new TypeError('MissingRawHoldingCustody');
  }
  // One original physical call per installed port. This is a retained adapter
  // view, not another Slot owner. A retry reuses its exact Save/holding handles.
  let originalCall;
  let originalRaw;
  let port;
  let custodyRetained = false;
  let retired = false;
  const wake = () => {
    try { notify(); } catch { /* Cleanup wake is not a terminal Run fact. */ }
  };
  const persist = async (call, raw) => {
    if (retired) throw new TypeError('OriginalRawPersistenceRetired');
    if (originalCall !== undefined &&
        (originalCall !== call || originalRaw !== raw)) {
      throw new TypeError('ForeignOriginalRawPersistence');
    }
    if (!(raw?.body instanceof Uint8Array) ||
        typeof raw.transportComplete !== 'boolean' ||
        typeof raw.observedAt !== 'string') {
      throw new TypeError('MissingOriginalRawTransportFacts');
    }
    originalCall = call;
    originalRaw = raw;
    if (port === undefined) {
      const contentCid = `sha256:${createHash('sha256').update(raw.body).digest('hex')}`;
      const view = checked(moon.clientProgramObserveInferRawCapture(call,
        registration, contentCid, raw.body.byteLength, raw.status,
        raw.transportComplete, raw.observedAt));
      port = createModelRawCaptureStorePort(store, moon, view, raw.body);
    }
    try {
      // Outside Entry/commit boundaries. This transfers cleanup responsibility,
      // not permission to enter, persist, disclose or publish an answer.
      if (!custodyRetained) {
        retainHolding(port);
        custodyRetained = true;
      }
      // No extra provider metadata was observed by this physical profile.
      // Unknown response fields remain in the authenticated raw Artifact.
      return await port.persistChat(undefined);
    } catch (error) {
      throw retainedRawFailure(error, {
        rawCustodyRetained: true,
        cleanupHandle: error?.cleanupHandle ?? port.holding,
      });
    }
  };
  // Called by this original Model physical cleanup port. It observes existing
  // Store cleanup, not capture success, raw disclosure, whole Run release or
  // authority to send. Never adopt a caller's substituted error/cleanup handle.
  persist.cleanup = call => {
    if (originalCall !== undefined && originalCall !== call) return false;
    if (retired) return true;
    const retireView = () => {
      // Drop this port's transport-backing alias only. Escaped parent holding,
      // Save/receipt and raw views retain their independent original custody.
      originalRaw = undefined;
      port = undefined;
      originalTransportPorts.delete(persist);
      retired = true;
      return true;
    };
    if (port === undefined) return retireView(); // No holding was constructed.
    // A committed raw cell does not prove its failed confirmation reader is
    // retired. Keep this same port/transport view until Store cleanup succeeds.
    if (!port.cleanupStoreReads(wake)) return false;
    const status = port.holding.status();
    if (status.operationPending || status.preparedPending) {
      if (!status.operationPending) {
        void port.holding.abort().then(wake, wake);
      }
      return false;
    }
    if (status.abandoned) return retireView();
    // Durable raw custody stays with the parent. This releases no Store data
    // and does not claim that escaped Save/receipt/parent aliases have retired.
    if (status.committed) return custodyRetained ? retireView() : false;
    void port.holding.abort().then(wake, wake);
    return false;
  };
  if (operation !== undefined) {
    originalTransportPorts.set(persist, {operation: new WeakRef(operation), registration});
  }
  return Object.freeze(persist);
}
