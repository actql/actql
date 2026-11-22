import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {createHash} from 'node:crypto';

type HoldingStore = Parameters<typeof preparePrivatePublicationHolding>[0];
type ConfirmRaw = NonNullable<HoldingStore['confirmModelRawEvidence']>;
type RawBinding = Parameters<ConfirmRaw>[0];
type SavedRaw = NonNullable<Awaited<ReturnType<ConfirmRaw>>> &
  Readonly<{bytes: NonNullable<Parameters<TextDecoder['decode']>[0]>}>;
type Awaitable<T> = T | PromiseLike<T>;
type WireOriginal = Readonly<{kind: unknown; cid: unknown; wire: unknown}>;
type Store = Omit<HoldingStore, 'confirmModelRawEvidence'> & Readonly<{
  storeAuthorityCid: string | undefined;
  confirmModelRawEvidence(binding: RawBinding): Awaitable<SavedRaw | undefined>;
  confirmModelRawCaptureOriginals(originals: readonly WireOriginal[], authorityCid: string | undefined): Awaitable<unknown>;
}>;
type Runtime = Readonly<{
  clientProgramInferRawCaptureSaveCurrent(view: unknown): unknown;
  clientProgramInferRawCaptureSaveBinding(view: unknown): unknown;
  clientProgramInferRawCaptureSaveOriginals(view: unknown): readonly unknown[];
  clientProgramAcknowledgeSavedInferRawCapture(view: unknown): unknown;
  clientProgramInferSavedRawChatResponse(receipt: unknown, body: string, metadata: unknown): unknown;
  clientProgramObserveInferRawCapture(call: unknown, registration: unknown, contentCid: string, bytes: number,
    status: number, transportComplete: boolean, observedAt: string): unknown;
}>;
type StorePort = ReturnType<typeof createModelRawCaptureStorePort>;
type RawFacts = Readonly<{body: Uint8Array; status: number; transportComplete: boolean; observedAt: string}>;
type TransportPersistence = ((call: unknown, raw: RawFacts, bytesOnly?: boolean) =>
  Promise<Awaited<ReturnType<StorePort['persist']>> | Awaited<ReturnType<StorePort['persistChat']>>>) &
  Readonly<{cleanup(call: unknown): boolean}>;
type TransportOptions = Readonly<{
  store: Store; moon: Runtime; registration: unknown; retainHolding(port: StorePort): void;
  notify(): void; operation?: object;
}>;
type RetirableOptions = {[Name in keyof TransportOptions]: TransportOptions[Name] | undefined};
type OriginalPort = Readonly<{operation: WeakRef<object>; registration: unknown; prepare?(): TransportPersistence}>;
type Binder<Result> = (next: () => object | undefined) => Result;
type CleanupHandle = Readonly<{status(): Readonly<{pending: boolean}>; retry(): Awaitable<unknown>}>;
type CleanupFailure = Readonly<{cleanupHandle?: CleanupHandle}>;
type BindingTuple = [semanticCid: string, holdingCid: string, wire: string, contentCid: string, byteCount: number];

// Membership of a private physical port in the existing operation, not a new
// resource or grant Owner. A matching function/CID/copy is not this original.
const originalTransportPorts = new WeakMap<object, OriginalPort>();

// Preserve the same mutable primary error for existing consumers. An
// immutable Store/decoder failure cannot receive custody annotations; retain
// it as the cause of the existing raw-custody carrier instead of losing it to
// an assignment TypeError. The carrier is not a receipt or cleanup authority.
const retainedRawFailure = <Facts extends object>(error: unknown, facts: Facts) => {
  if (error !== null && typeof error === 'object' && Object.isExtensible(error)) {
    try { return Object.assign(error, facts); }
    catch { /* A read-only field cannot replace the original failure/custody. */ }
  }
  return Object.assign(new Error('ModelRawCustodyPending', {cause: error}), facts);
};

export function originalModelRawTransportPersistenceMatches(port: unknown, operation: unknown, registration: unknown) {
  const original = originalTransportPorts.get(port as object);
  return original !== undefined && original.operation.deref() === operation &&
    original.registration === registration;
}

// One synchronous installation binding may project a distinct existing
// single-Call port for every prepared request. The empty descriptor is private
// nominal membership, not a callable Store port, grant, or new cleanup owner.
export function createModelRawTransportPersistenceFactory({store, moon, registration,
  retainHolding, notify, operation}: TransportOptions & Readonly<{operation: object}>) {
  if (typeof retainHolding !== 'function' || typeof notify !== 'function') {
    throw new TypeError('MissingRawHoldingCustody');
  }
  const factory = Object.freeze({});
  originalTransportPorts.set(factory, {operation: new WeakRef(operation), registration,
    prepare: () => createModelRawTransportPersistence({store, moon, registration,
      retainHolding, notify, operation})});
  return factory;
}

// Consume only this original operation's factory. A single legacy port keeps
// its existing one-Call semantics. Neither a failed binder nor an escaped next
// callback can prepare replacement ports after the synchronous binding ends.
export function bindOriginalModelRawTransportPersistence<Result>(persistence: object | undefined,
  operation: object | undefined, registration: unknown, bind: Binder<Result>): Result;
export function bindOriginalModelRawTransportPersistence<Result>(persistence: object | undefined,
  operation: object | undefined, registration: unknown, bind: Binder<Result> | undefined) {
  let original = originalTransportPorts.get(persistence as object);
  if (persistence !== undefined &&
      !originalModelRawTransportPersistenceMatches(persistence, operation, registration)) {
    throw new TypeError('ForeignInferRawCapturePersistence');
  }
  if (original?.prepare !== undefined) originalTransportPorts.delete(persistence!);
  let open = true;
  try {
    return bind!(() => {
      if (!open) throw new TypeError('InferRawCaptureBindingUnavailable');
      return original?.prepare === undefined ? persistence : original.prepare();
    });
  } finally {
    open = false;
    original = undefined;
    persistence = undefined;
    operation = undefined;
    registration = undefined;
    bind = undefined;
  }
}

const tuple = (value: unknown, length: number): readonly unknown[] => {
  const fields = Array.isArray(value) ? value
    : Array.from({length}, (_, index) => runtimeOptionalField(value, index));
  if (fields.length !== length || fields.some(field => field === undefined)) {
    throw Object.assign(new Error('InvalidModelRawCaptureProjection'),
      {code: 'InvalidModelRawCaptureProjection'});
  }
  return fields;
};

// Trusted installed adapter only, not an SDK registration or public read port.
// The view originates in the existing Model Owner. Reuse its original physical
// holding retry responsibility; no callback can issue a receipt from CID alone.
export function createModelRawCaptureStorePort(store: Store, moon: Runtime, view: unknown, bytes: Uint8Array) {
  const current = () => checked(moon.clientProgramInferRawCaptureSaveCurrent(view));
  current();
  const [semanticCid, holdingCid, wire, contentCid, byteCount] = tuple(
    moon.clientProgramInferRawCaptureSaveBinding(view), 5,
  ) as BindingTuple;
  const originals = moon.clientProgramInferRawCaptureSaveOriginals(view)
    .map(value => {
      const [kind, cid, wire] = tuple(value, 3);
      return Object.freeze({kind, cid, wire});
    });
  const binding = Object.freeze({semanticCid, holdingCid, wire, contentCid, byteCount});
  let storeReadCleanup: CleanupHandle | undefined;
  let storeReadFlight: Promise<unknown> | undefined;
  // Only a failure from this trusted original Store read may supply this
  // handle. A caller's reported CID/error never supplies cleanup custody.
  const observeStoreRead = async <Result,>(read: () => Awaitable<Result>) => {
    if (storeReadFlight !== undefined ||
        storeReadCleanup?.status().pending === true) {
      throw new TypeError('ModelRawReaderCleanupPending');
    }
    try { return await read(); }
    catch (error) {
      const handle = (error as CleanupFailure | undefined)?.cleanupHandle;
      if (typeof handle?.status === 'function' &&
          typeof handle?.retry === 'function' && handle.status().pending === true) {
        storeReadCleanup = handle;
      }
      throw error;
    }
  };
  const confirmRaw = (actual: RawBinding) => observeStoreRead(() => store.confirmModelRawEvidence(actual));
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
        const facts: {rawPersistenceConfirmed: boolean; rawCustodyRetained: boolean;
          cleanupHandle: ReturnType<typeof preparePrivatePublicationHolding>; cleanupPending?: boolean} = {
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
    cleanupStoreReads(notify: () => void) {
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
    async persistChat(metadata: unknown) {
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
export function createModelRawTransportPersistence(options: TransportOptions): TransportPersistence;
export function createModelRawTransportPersistence({store, moon, registration,
  retainHolding, notify, operation}: RetirableOptions): TransportPersistence {
  if (typeof retainHolding !== 'function' || typeof notify !== 'function') {
    throw new TypeError('MissingRawHoldingCustody');
  }
  // One original physical call per installed port. This is a retained adapter
  // view, not another Slot owner. A retry reuses its exact Save/holding handles.
  let originalCall: unknown;
  let retiredCall: unknown;
  let originalRaw: RawFacts | undefined;
  let port: StorePort | undefined;
  let custodyRetained = false;
  let retired = false;
  const wake = () => {
    try { notify!(); } catch { /* Cleanup wake is not a terminal Run fact. */ }
  };
  const persist = async (call: unknown, raw: RawFacts, bytesOnly = false) => {
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
      const view = checked(moon!.clientProgramObserveInferRawCapture(call,
        registration, contentCid, raw.body.byteLength, raw.status,
        raw.transportComplete, raw.observedAt));
      port = createModelRawCaptureStorePort(store!, moon!, view, raw.body);
    }
    try {
      // Outside Entry/commit boundaries. This transfers cleanup responsibility,
      // not permission to enter, persist, disclose or publish an answer.
      if (!custodyRetained) {
        retainHolding!(port);
        custodyRetained = true;
      }
      // The selected SDK decodes the Store's verified byte loan. Existing
      // Chat and native callers keep their original Common envelope view.
      return await (bytesOnly === true ? port.persist() : port.persistChat(undefined));
    } catch (error) {
      throw retainedRawFailure(error, {
        rawCustodyRetained: true,
        cleanupHandle: (error as CleanupFailure | undefined)?.cleanupHandle ?? port.holding,
      });
    }
  };
  // Called by this original Model physical cleanup port. It observes existing
  // Store cleanup, not capture success, raw disclosure, whole Run release or
  // authority to send. Never adopt a caller's substituted error/cleanup handle.
  persist.cleanup = (call: unknown) => {
    if (retired) {
      // Keep exact-call retry/refusal without an escaped retired port keeping
      // the entire Call/Entry/Plan graph alive. A cleared weak reference cannot
      // match a foreign live Call. Scalar refused inputs need no weak backing.
      if (retiredCall instanceof WeakRef) {
        const original = retiredCall.deref();
        return original !== undefined && original === call;
      }
      return retiredCall === undefined || retiredCall === call;
    }
    if (originalCall !== undefined && originalCall !== call) return false;
    const retireView = () => {
      // Drop this retired caller's transport and factory aliases only.
      // Escaped parent holding, Save/receipt and raw views retain their
      // independent original custody; this is not physical GC or capacity ACK.
      retiredCall = originalCall !== null &&
          (typeof originalCall === 'object' || typeof originalCall === 'function')
        ? new WeakRef(originalCall) : originalCall;
      originalCall = undefined;
      originalRaw = undefined;
      port = undefined;
      originalTransportPorts.delete(persist);
      store = undefined;
      moon = undefined;
      registration = undefined;
      retainHolding = undefined;
      notify = undefined;
      operation = undefined;
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
