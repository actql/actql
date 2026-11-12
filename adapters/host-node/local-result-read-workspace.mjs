import {openRequestPreparation, cleanupRequestInput}
  from '../local-node/request-preparation-adapter.mjs';
import {physicalContentReadWindowBytes} from '../store-local/publication-store.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {ResultDeliveryError} from '../host-common/result-delivery.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// The installed Result owner supplies the original runtime/policy. A READ is
// one existing Request admission, independent of its retired producing Run.
// These instance-local limits are not a separately reserved Host RAM pool.
export function createLocalResultReadWorkspace({runtime, requestMemory, assertCurrent}) {
  const reserve = runtime.clientProgramReserveRequestResultRead;
  const grow = runtime.clientProgramGrowRequestResultReadRow;
  const metadata = runtime.clientProgramReserveRequestResultMetadata;
  const retainData = runtime.clientProgramRetainRequestResultMetadataData;
  const releaseMetadata = runtime.clientProgramReleaseRequestResultMetadata;
  const finishMetadata = runtime.clientProgramFinishRequestResultMetadata;
  const reconcileSerializer = runtime.clientProgramReconcileRequestResultReadSerializer;
  if (typeof assertCurrent !== 'function') {
    throw Object.assign(new Error('ResultReadCapacityUnavailable'), {code: 'ResultReadCapacityUnavailable'});
  }
  const context = Object.freeze({runtime, requestMemory});
  const reads = new Map();
  let closing = false;
  const unavailable = () => {throw Object.assign(new Error('ForeignResultReadWorkspace'),
    {code: 'ForeignResultReadWorkspace'});};
  const original = request => reads.get(request) ?? unavailable();
  const pending = entry => {
    if (entry.active) return true;
    if (entry.unknownPhysical) return true;
    return entry.physical.some(child => {
      try {return Reflect.apply(child.status, child.receiver, []).pending !== false;}
      catch {return true;}
    });
  };
  function retire(entry) {
    if (pending(entry)) return false;
    cleanupRequestInput(entry.state);
    reads.delete(entry.request);
    return true;
  }
  async function retry(entry) {
    if (entry.active) return Object.freeze({pending: true});
    for (const child of entry.physical) {
      let stopped = false;
      try {stopped = Reflect.apply(child.status, child.receiver, []).pending === false;} catch {}
      if (!stopped) await Reflect.apply(child.retry, child.receiver, []);
    }
    return Object.freeze({pending: !retire(entry)});
  }
  function cleanupFailure(entry, cause) {
    const error = Object.assign(new Error('ResultReadCleanupPending', {cause}), {
      code: 'ResultReadCleanupPending', cleanupPending: true, primaryFailure: cause,
      cleanupHandle: Object.freeze({status: () => Object.freeze({pending: reads.has(entry.request)}),
        retry: () => retry(entry)}),
    });
    return error;
  }
  return Object.freeze({
    begin(request, control) {
      if (closing || reads.has(request)) unavailable();
      if ([reserve, grow, metadata, retainData, releaseMetadata, finishMetadata, reconcileSerializer].some(method => typeof method !== 'function')) {
        throw Object.assign(new Error('ResultReadCapacityUnavailable'), {code: 'ResultReadCapacityUnavailable'});
      }
      assertCurrent();
      // Retain the original before any fallible platform/Core constructor.
      const retained = control === undefined ? undefined : Object.getOwnPropertyDescriptor(control, 'retainResultReadMetadata')?.value;
      const entry = {request, state: {context}, control, retained, active: true, rowUnits: 0,
        prepared: false, metadataActive: false, physical: [], unknownPhysical: false};
      reads.set(request, entry);
      try {
        openRequestPreparation(entry.state, request, assertCurrent, () => pending(entry));
      } catch (cause) {
        entry.active = false;
        try {retire(entry);} catch {throw cleanupFailure(entry, cause);}
        throw cause;
      }
    },
    metadata(request, bytes) {
      const entry = original(request);
      if (!entry.active || !Number.isSafeInteger(bytes) || bytes < 0 || bytes > 2147483647) unavailable();
      assertCurrent();
      checked(Reflect.apply(metadata, runtime,
        [entry.state.parent, request, bytes]));
      entry.metadataActive = true;
    },
    metadataRetain(request, slot, originalContract, mode) {
      const entry = original(request);
      if (!entry.active || typeof entry.retained !== 'function') unavailable();
      Reflect.apply(entry.retained, entry.control, [entry.state.parent, request, slot, originalContract, mode]);
    },
    metadataData(request, slot, nodes, textUnits) {
      const entry = original(request);
      if (!entry.active) unavailable();
      checked(Reflect.apply(retainData, runtime,
        [entry.state.parent, request, slot, nodes, textUnits]));
    },
    metadataRelease(request, slot) {
      const entry = original(request);
      if (!entry.active) unavailable();
      checked(Reflect.apply(releaseMetadata, runtime,
        [entry.state.parent, request, slot]));
    },
    metadataFinish(request) {
      const entry = original(request);
      if (!entry.active) unavailable();
      if (!entry.metadataActive) return;
      checked(Reflect.apply(finishMetadata, runtime, [entry.state.parent, request]));
      entry.metadataActive = false;
    },
    prepare(request, metadata, limits, frames) {
      const entry = original(request);
      if (!entry.active || entry.prepared) unavailable();
      assertCurrent();
      const payload = metadata.payloadBytes;
      if (!Number.isSafeInteger(payload) || payload < 0) unavailable();
      const maxRow = Math.max(1, Math.min(frames.maxRowBytes, payload));
      const frame = Math.max(1, Math.min(frames.maxFrameBytes, payload));
      let schemaUnits = metadata.resultSchemaWire.length;
      for (const field of metadata.resultFields) schemaUnits += field.length;
      if (!Number.isSafeInteger(schemaUnits) || schemaUnits > 2147483647) unavailable();
      const desired = Math.max(1, Math.min(physicalContentReadWindowBytes,
        frames.maxFrameBytes, limits.maxWireBytes, payload));
      const window = checked(Reflect.apply(reserve, runtime,
        [entry.state.parent, request, maxRow, frame, schemaUnits, limits.maxNodes, desired]));
      if (!Number.isSafeInteger(window) || window < 1 || window > desired) unavailable();
      entry.prepared = true;
      entry.window = window;
      return window;
    },
    serializer(request, value) {
      const entry = original(request);
      if (!entry.active || !entry.prepared) unavailable();
      checked(Reflect.apply(reconcileSerializer, runtime, [entry.state.parent, request, value]));
    },
    row(request, units) {
      const entry = original(request);
      if (!entry.active || !entry.prepared || !Number.isSafeInteger(units) || units < 0) unavailable();
      // Pure local counters consume an already acquired window. Core/current
      // is crossed only at a new geometric high-water constructor boundary.
      if (units <= entry.rowUnits) return {units: entry.rowUnits, window: entry.window};
      const admitted = checked(Reflect.apply(grow, runtime,
        [entry.state.parent, request, units]));
      const high = runtimeField(admitted, 0), window = runtimeField(admitted, 1);
      if (!Number.isSafeInteger(high) || high < units || !Number.isSafeInteger(window) ||
          window < 1 || window > entry.window) unavailable();
      entry.rowUnits = high;
      entry.window = window;
      return {units: high, window};
    },
    close(request, failure) {
      const entry = original(request);
      entry.active = false;
      // The canonical delivery failure can join a failed terminal-record
      // write with its SAME original reader failure. Both duties survive;
      // record completion alone cannot release an outstanding physical FD.
      const primary = failure instanceof ResultDeliveryError
        ? Object.getOwnPropertyDescriptor(failure, 'primaryFailure')?.value : undefined;
      for (const original of [failure, primary]) {
        if (original === null || typeof original !== 'object') continue;
        try {
          const pending = Object.getOwnPropertyDescriptor(original, 'cleanupPending');
          const handle = Object.getOwnPropertyDescriptor(original, 'cleanupHandle');
          if (handle === undefined) {
            if (pending?.value === true) entry.unknownPhysical = true;
            continue;
          }
          if (!Object.hasOwn(handle, 'value')) {entry.unknownPhysical = true;continue;}
          const receiver = handle.value;
          if (entry.physical.some(child => child.receiver === receiver)) continue;
          const status = Object.getOwnPropertyDescriptor(receiver, 'status')?.value;
          const retry = Object.getOwnPropertyDescriptor(receiver, 'retry')?.value;
          if (typeof status !== 'function' || typeof retry !== 'function') {
            entry.unknownPhysical = true;
          } else entry.physical.push({receiver, status, retry});
        } catch {entry.unknownPhysical = true;}
      }
      try {retire(entry);} catch (cause) {throw cleanupFailure(entry, failure ?? cause);}
    },
    async closeAll() {
      closing = true;
      for (const entry of reads.values()) await retry(entry);
      return Object.freeze({pending: reads.size !== 0});
    },
  });
}
