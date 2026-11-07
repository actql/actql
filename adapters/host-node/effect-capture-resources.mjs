// Fixed adapter to the existing Request preparation or SAME adopted Run.
// No standalone Ledger, semantic Request/Run issuer or IO grant lives here.
import {openRequestPreparation, cleanupRequestInput, assertRequestPreparationControl}
  from '../local-node/request-preparation-adapter.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {CompletedRunPublicationError} from '../host-common/completed-run-publication.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const pending = value => {
  const property = value !== null && typeof value === 'object'
    ? Object.getOwnPropertyDescriptor(value, 'pending') : undefined;
  return property === undefined || !Object.hasOwn(property, 'value') || property.value !== false;
};
function captureFailure(state, error) {
  state.failure ??= error;
  // Capture the existing original carrier, including the one capture-read
  // wrapper. Do not classify a code string or replace an unavailable child.
  try {
    const source = error instanceof CompletedRunPublicationError && error.cause !== undefined
      ? error.cause : error;
    if (source === null || typeof source !== 'object') return;
    const handle = Object.getOwnPropertyDescriptor(source, 'cleanupHandle');
    const required = Object.getOwnPropertyDescriptor(source, 'cleanupPending');
    if (handle !== undefined && Object.hasOwn(handle, 'value') && handle.value !== undefined) {
      if (state.child !== undefined && state.child !== handle.value) state.unknownChild = true;
      else state.child = handle.value;
    } else if (handle !== undefined || required !== undefined &&
        (!Object.hasOwn(required, 'value') || required.value === true)) {
      state.unknownChild = true;
    }
  } catch {
    // A foreign carrier cannot replace the original failure or prove that
    // an unavailable physical child has stopped.
    state.unknownChild = true;
  }
}

function recoveryView(state) {
  let view;
  const reserve = encryptedBytes => {
    if (!Number.isSafeInteger(encryptedBytes) || encryptedBytes < 0 || encryptedBytes > 2147483647) {
      fail('EffectCaptureResourceExtentInvalid');
    }
    if (state.closing || state.closed || state.preparing) fail('EffectCaptureResourceUnavailable');
    state.preparing = true;
    try {
      if (state.live) {
        checked(state.context.runtime.clientProgramReserveInstalledEffectCaptureRecovery(
          state.value, encryptedBytes));
      } else {
        Reflect.apply(state.reserve, state.control, [state.parent, state.input,
          state.request, state.runDefinition, encryptedBytes, state.limits]);
      }
      if (state.closing || state.closed) fail('EffectCaptureResourceUnavailable');
    } catch (cause) {captureFailure(state, cause); throw cause;}
    finally {state.preparing = false;}
  };
  const close = () => {
    if (state.closed) return Promise.resolve(true);
    if (state.closeFlight !== undefined) return state.closeFlight;
    state.closing = true;
    const flight = Promise.resolve().then(async () => {
      if (state.busy || state.preparing || state.unknownChild) return false;
      if (state.child !== undefined) {
        state.childStatus ??= state.child.status;
        state.childRetry ??= state.child.retry;
        if (typeof state.childStatus !== 'function' || typeof state.childRetry !== 'function') return false;
        if (pending(Reflect.apply(state.childStatus, state.child, []))) {
          await Reflect.apply(state.childRetry, state.child, []);
        }
        if (pending(Reflect.apply(state.childStatus, state.child, []))) return false;
        state.child = state.childStatus = state.childRetry = undefined;
      }
      if (state.resultCleanup !== undefined) {
        // The same completed owner closes its original schemas/payloads and
        // cuts its private decoded aliases. A failed callback remains here;
        // it owns its own original child retry, not a replacement ACK.
        await Reflect.apply(state.resultCleanup, undefined, []);
        state.resultCleanup = undefined;
      }
      // Only after actual original child cleanup. Clear the variable aliases
      // before returning capacity: the original return may consume then fail.
      state.request = state.runDefinition = state.control = state.reserve = state.limits = state.input = undefined;
      state.failure = undefined;
      // The original Request settlement still enters its existing Resource
      // current callback. Keep that same light control until settlement ACK;
      // clearing it here would turn a missing method into sticky stopping.
      if (state.live) {
        if (state.value !== undefined) {
          checked(state.context.runtime.clientProgramRetireInstalledEffectCaptureRecovery(state.value));
          state.value = undefined;
        }
      } else {
        cleanupRequestInput(state);
      }
      state.closed = true;
      state.assertCurrent = undefined;
      state.complete = undefined;
      state.context = undefined;
      const retired = state.retired;
      state.retired = undefined;
      retired?.(view);
      return true;
    }).finally(() => {if (state.closeFlight === flight) state.closeFlight = undefined;});
    state.closeFlight = flight;
    return flight;
  };
  view = Object.freeze({reserve,
    reserveDecoded(wire) {
      if (typeof wire !== 'string' || !state.busy || state.closing || state.closed || state.preparing) {
        fail('EffectCaptureResourceUnavailable');
      }
      if (!state.live) return;
      state.preparing = true;
      try {checked(state.context.runtime.clientProgramReserveInstalledEffectCaptureDecoded(state.value, wire));}
      catch (cause) {captureFailure(state, cause); throw cause;}
      finally {state.preparing = false;}
    },
    retainCleanup(operation) {
      if (state.closed || state.resultCleanup !== undefined || typeof operation !== 'function') {
        fail('EffectCaptureResourceUnavailable');
      }
      // Store/schema construction may finish after close was requested while
      // busy. Retain the actual child before that pending close can continue.
      state.resultCleanup = operation;
    },
    begin() {
      if (state.busy || state.closing || state.closed) fail('EffectCaptureResourceUnavailable');
      state.busy = true;
    },
    finish(failed, cause) {
      if (!state.busy) fail('EffectCaptureResourceUnavailable');
      try {
        if (failed) captureFailure(state, cause);
        else {
          if (state.closing || state.child !== undefined || state.unknownChild) fail('EffectCaptureResourceUnavailable');
          if (state.live) {
            // Only the existing trusted Store return reaches successful finish:
            // its FD and temporary decode aliases are already closed/cut. The
            // SAME Core token keeps all returned schemas and typed originals.
            state.preparing = true;
            try {checked(Reflect.apply(state.complete, state.context.runtime, [state.value]));}
            finally {state.preparing = false;}
          }
        }
      } catch (error) {captureFailure(state, error);throw error;}
      finally {state.busy = false;}
    },
    close,
    status: () => Object.freeze({pending: !state.closed, busy: state.busy || state.preparing}),
  });
  return view;
}

// The caller is the existing Host bag, after its actual journal selection and
// evidence-read authorization. Retain receives this SAME view before either
// existing resource constructor can fail; failed opening stays closeable.
export function prepareEffectCaptureResources({moon, control, request, runDefinition,
  contractLimits, managed, assertCurrent, retain, retired}) {
  if (typeof assertCurrent !== 'function' || typeof retain !== 'function' ||
      typeof control?.reserveEffectCaptureRecovery !== 'function') fail('EffectCaptureResourceUnavailable');
  const limits = Object.freeze({maxWireBytes: contractLimits.maxWireBytes,
    maxNodes: contractLimits.maxNodes, maxDepth: contractLimits.maxDepth});
  const state = {context: {runtime: moon}, control, request, runDefinition, limits,
    reserve: control.reserveEffectCaptureRecovery, assertCurrent, retired,
    live: managed !== undefined, busy: false, preparing: false, closing: false, closed: false,
    unknownChild: false};
  const view = recoveryView(state);
  retain(view);
  try {
    assertCurrent();
    if (state.closing || state.closed) fail('EffectCaptureResourceUnavailable');
    if (managed !== undefined) {
      state.complete = Object.getOwnPropertyDescriptor(moon,
        'clientProgramCompleteInstalledEffectCaptureRecovery')?.value;
      if (typeof moon.clientProgramPrepareInstalledEffectCaptureRecovery !== 'function' ||
          typeof moon.clientProgramReserveInstalledEffectCaptureDecoded !== 'function' ||
          typeof state.complete !== 'function') {
        fail('EffectCaptureResourceUnavailable');
      }
      // The live Host already owns this exact compiled Definition. Do not
      // replace it with a newly admitted, equal-CID journal contract copy.
      state.value = checked(moon.clientProgramPrepareInstalledEffectCaptureRecovery(
        managed.value, managed.prepared, managed.request, managed.definitionOriginal.definition,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    } else {
      assertRequestPreparationControl(state.context);
      // New physical-process custody of this already selected saved Request,
      // not another semantic Request/Run or the old compiler/Source route.
      state.input = Object.freeze({request, runDefinition});
      openRequestPreparation(state, state.input, () => state.assertCurrent(),
        () => state.busy || state.child !== undefined || state.unknownChild);
      view.reserve(0);
    }
    assertCurrent();
    return view;
  } catch (cause) {captureFailure(state, cause); throw cause;}
}
