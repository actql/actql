import {ownedHostFailure} from './failure-envelope.mjs';

const CANCEL_OUTPUT = 0;
const CLOSE_OUTPUT_OWNERS = 1;
const RECLAIM_OUTPUT = 2;
const CLOSE_EXECUTION = 3;
const AWAIT_NATIVE_STOP = 4;
const SETTLE_EXECUTION = 5;
const REFRESH_EXECUTION_CLEANUP = 6;
const AWAIT_OUTPUT_CLEANUP = 7;
const FAILURE_FINISHED = 8;

const RETRY_NATIVE_CLEANUP = 0;
const RETRY_OUTPUT_CLEANUP = 1;
const RESUME_FAILURE_PROGRESS = 2;

const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};

const cleanupState = (handle, required = false) => {
  if (!handle || typeof member(handle, 'status') !== 'function') {
    return Object.freeze({pending: required, errors: Object.freeze([])});
  }
  try {
    const state = handle.status();
    return state && typeof state.pending === 'boolean'
      ? Object.freeze({
        pending: state.pending,
        errors: Object.freeze(Array.isArray(state.errors)
          ? [...state.errors] : []),
      })
      : Object.freeze({pending: true, errors: Object.freeze([])});
  } catch (error) {
    return Object.freeze({pending: true, errors: Object.freeze([error])});
  }
};

// The portable DuckDB driver selects every lifecycle action. This adapter owns
// only Node resources and observations: native cleanup, Store cleanup, and the
// bridge calls that apply the selected common task operation.
export async function settleFailedManagedDuckDB(
  moon, checked, state, reason,
) {
  if (!moon || typeof moon.managedStrategyFailureAction !== 'function' ||
      typeof moon.managedStrategyFailureRetryAction !== 'function' ||
      !state || typeof state !== 'object' ||
      !state.lifecycle || typeof state.lifecycle !== 'object') {
    throw new Error('MissingManagedDuckDBFailureProgress');
  }
  const failure = ownedHostFailure(reason, 'ManagedStrategyFailed');
  const upstreamRequired = failure.cleanupPending === true;
  const nativeCleanup = upstreamRequired
    ? member(failure, 'cleanupHandle') : undefined;
  const diagnostics = [...failure.cleanupErrors];
  let outputCancelAttempted = state.output === undefined;
  // Even when allocation failed before an owner was created, the portable
  // close step must establish the retention-release observation explicitly.
  let outputOwnersCloseAttempted = false;
  let outputReclaimAttempted = state.store === undefined;
  let executionCloseAttempted = state.run === undefined;
  let executionCleanupConfirmed = state.run === undefined;
  if (state.run === undefined) state.lifecycle.executionSettled = true;

  const record = error => { diagnostics.push(error); };
  const nativeState = () => cleanupState(nativeCleanup, upstreamRequired);
  const outputState = () => {
    if (!state.store) {
      return Object.freeze({pending: false, errors: Object.freeze([])});
    }
    try {
      const current = state.store.status();
      return current && typeof current.cleanupPending === 'boolean'
        ? Object.freeze({
          pending: current.cleanupPending,
          errors: Object.freeze([]),
        })
        : Object.freeze({pending: true, errors: Object.freeze([])});
    } catch (error) {
      return Object.freeze({pending: true, errors: Object.freeze([error])});
    }
  };
  const nextAction = () => moon.managedStrategyFailureAction(
    outputCancelAttempted,
    outputOwnersCloseAttempted,
    outputReclaimAttempted,
    executionCloseAttempted,
    !nativeState().pending,
    state.lifecycle.executionSettled === true,
    executionCleanupConfirmed,
    !outputState().pending,
  );

  const cancelOutput = () => {
    outputCancelAttempted = true;
    if (!state.output) return;
    try { moon.managedOutputCancel(state.output); }
    catch (error) { record(error); }
  };
  const closeOutputOwners = () => {
    outputOwnersCloseAttempted = true;
    for (const owner of [state.body, state.store]) {
      if (!owner || typeof member(owner, 'close') !== 'function') continue;
      try { owner.close(); }
      catch (error) { record(error); }
    }
    state.lifecycle.outputDisposed = true;
  };
  const reclaimOutput = async () => {
    outputReclaimAttempted = true;
    try { await state.store?.cleanup(); }
    catch (error) { record(error); }
  };
  const closeExecution = () => {
    executionCloseAttempted = true;
    if (!state.run) return;
    try { moon.managedStrategyClose(state.run); }
    catch (error) { record(error); }
  };
  const settleExecution = () => {
    if (!state.run || state.lifecycle.executionSettled === true) return;
    try {
      checked(moon.managedStrategySettle(state.run, true));
      state.lifecycle.executionSettled = true;
    } catch (error) { record(error); }
  };
  const refreshExecution = () => {
    if (!state.run || executionCleanupConfirmed) return;
    try {
      executionCleanupConfirmed = checked(
        moon.managedStrategyCleanupRefresh(state.run),
      ) === true;
    } catch (error) { record(error); }
  };

  const drive = async () => {
    const attempted = new Set();
    for (let step = 0; step < 16; step++) {
      let action;
      try { action = nextAction(); }
      catch (error) { record(error); return false; }
      if (action === CANCEL_OUTPUT) {
        if (attempted.has(action)) return false;
        attempted.add(action);
        cancelOutput();
        continue;
      }
      if (action === CLOSE_OUTPUT_OWNERS) {
        if (attempted.has(action)) return false;
        attempted.add(action);
        closeOutputOwners();
        continue;
      }
      if (action === RECLAIM_OUTPUT) {
        if (attempted.has(action)) return false;
        attempted.add(action);
        await reclaimOutput();
        continue;
      }
      if (action === CLOSE_EXECUTION) {
        if (attempted.has(action)) return false;
        attempted.add(action);
        closeExecution();
        continue;
      }
      if (action === AWAIT_NATIVE_STOP || action === AWAIT_OUTPUT_CLEANUP) {
        return false;
      }
      if (action === SETTLE_EXECUTION) {
        if (attempted.has(action)) return false;
        attempted.add(action);
        settleExecution();
        if (state.lifecycle.executionSettled !== true) return false;
        continue;
      }
      if (action === REFRESH_EXECUTION_CLEANUP) {
        if (attempted.has(action)) return false;
        attempted.add(action);
        refreshExecution();
        if (!executionCleanupConfirmed) return false;
        continue;
      }
      if (action === FAILURE_FINISHED) return true;
      record(new Error('InvalidManagedDuckDBFailureProgress'));
      return false;
    }
    record(new Error('ManagedDuckDBFailureProgressDidNotConverge'));
    return false;
  };

  await drive();
  const status = () => {
    const native = nativeState();
    const outputCleanup = outputState();
    let pending = true;
    const statusErrors = [];
    try { pending = nextAction() !== FAILURE_FINISHED; }
    catch (error) { statusErrors.push(error); }
    return Object.freeze({
      pending,
      errors: Object.freeze([
        ...native.errors,
        ...outputCleanup.errors,
        ...diagnostics,
        ...statusErrors,
      ]),
    });
  };
  const handle = Object.freeze({
    status,
    async retry() {
      let nativeRetryAttempted = false;
      let outputRetryAttempted = false;
      for (let step = 0; step < 4; step++) {
        let action;
        try {
          action = moon.managedStrategyFailureRetryAction(
            nativeState().pending,
            nativeRetryAttempted,
            outputState().pending,
            outputRetryAttempted,
          );
        } catch (error) { record(error); break; }
        if (action === RETRY_NATIVE_CLEANUP) {
          nativeRetryAttempted = true;
          if (typeof member(nativeCleanup, 'retry') === 'function') {
            try { await nativeCleanup.retry(); }
            catch (error) { record(error); }
          }
          continue;
        }
        if (action === RETRY_OUTPUT_CLEANUP) {
          outputRetryAttempted = true;
          try { await state.store?.cleanup(); }
          catch (error) { record(error); }
          continue;
        }
        if (action === RESUME_FAILURE_PROGRESS) break;
        record(new Error('InvalidManagedDuckDBFailureRetryProgress'));
        break;
      }
      await drive();
      const current = status();
      failure.cleanupErrors = current.errors;
      failure.cleanupPending = current.pending;
      return current;
    },
  });
  const current = status();
  failure.cleanupErrors = current.errors;
  failure.cleanupPending = current.pending;
  if (current.pending || current.errors.length > 0) {
    failure.cleanupHandle = handle;
  } else {
    delete failure.cleanupHandle;
  }
  return failure;
}
