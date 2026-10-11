import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';
import {checked} from '../host-common/runtime-result.mjs';

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
  const holding = preparePrivatePublicationHolding(store,
    {...binding, name: 'model_raw_response'}, bytes);
  return Object.freeze({
    holding,
    async persist() {
      let confirmed = false;
      try {
        current();
        await store.confirmModelRawCaptureOriginals(originals, store.storeAuthorityCid);
        current();
        await holding.commit();
        // Commit acknowledgement alone cannot supply the nominal receipt.
        // Reconfirm exact descriptor/body bytes and directory durability first.
        const saved = await store.confirmModelRawEvidence(binding);
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
        error.rawPersistenceConfirmed = confirmed;
        error.rawCustodyRetained = true;
        error.cleanupHandle = holding;
        if (!holding.status().committed || holding.status().preparedPending) {
          error.cleanupPending = true;
        }
        throw error;
      }
    },
  });
}
