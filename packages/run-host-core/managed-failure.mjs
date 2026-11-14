// Failure settlement for synchronous managed implementations. A returned
// Promise and a stopped representation reader are different facts: reservation
// settlement waits for the latter, while close is attempted immediately.

// Private cleanup lists have two positional diagnostic roles: the first
// refusal and the latest refusal. Throwable identity includes primitives and
// undefined; equality or a status snapshot is never a retirement witness.
// This mutates only diagnostics, not the original cleanup/progress owner.
export function retainFirstAndLatestCleanupError(errors, error, retainedPrefix = 0) {
  // A caller may already retain a finite initial diagnostic for each original
  // child. Preserve that prefix; only this owner's subsequent retry tail has
  // first/latest roles. The prefix is captured once, not recomputed per retry.
  if (errors.length < retainedPrefix + 2) errors.push(error);
  else errors[retainedPrefix + 1] = error;
}

const member = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};

const cleanupState = (handle, required = false) => {
  if (!handle || typeof member(handle, 'status') !== 'function') {
    return {pending: required, errors: []};
  }
  try {
    const state = handle.status();
    return state && typeof state.pending === 'boolean'
      ? {pending: state.pending,
        errors: Array.isArray(state.errors) ? [...state.errors] : []}
      : {pending: true, errors: []};
  } catch (error) { return {pending: true, errors: [error]}; }
};

function ownedFailure(reason, fallbackCode) {
  const code = typeof member(reason, 'code') === 'string'
    ? member(reason, 'code') : fallbackCode;
  const hasPrimary = reason !== null &&
    (typeof reason === 'object' || typeof reason === 'function') &&
    Object.hasOwn(reason, 'primaryFailure');
  const primary = hasPrimary ? member(reason, 'primaryFailure') : reason;
  const failure = new Error(code, {cause: primary});
  if (typeof member(primary, 'name') === 'string') {
    failure.name = member(primary, 'name');
  }
  failure.code = code;
  failure.primaryFailure = primary;
  // Keep immutable diagnostic DATA through this existing ownership wrapper.
  // The receiving public codec validates fields; never invoke an accessor.
  try {
    const diagnostic = Object.getOwnPropertyDescriptor(reason, 'primaryDiagnostic');
    if (diagnostic !== undefined && Object.hasOwn(diagnostic, 'value')) {
      failure.primaryDiagnostic = diagnostic.value;
    }
  } catch { /* A primitive or unavailable diagnostic leaves the original intact. */ }
  failure.cleanupErrors = Object.freeze(
    Array.isArray(member(reason, 'cleanupErrors'))
      ? [...member(reason, 'cleanupErrors')]
      : [],
  );
  return failure;
}

const FAILURE_CLOSE_ADDITIONAL = 0;
const FAILURE_CLOSE_OPERATIONS = 1;
const FAILURE_AWAIT_STOP = 2;
const FAILURE_SETTLE_OPERATIONS = 3;
const FAILURE_REFRESH_CLEANUP = 4;
const FAILURE_FINISHED = 5;

// Optional observation from the original Local owner. An unsigned JS Int64
// representation of -1 still means blocked, never runnable cleanup.
function localCleanupContinuation(operations) {
  if (typeof operations.cleanup_local_continuation !== 'function') return undefined;
  try {
    const value = operations.cleanup_local_continuation();
    if (typeof value !== 'bigint' || value < -(1n << 63n) ||
        value > (1n << 64n) - 1n) return undefined;
    return BigInt.asIntN(64, value);
  } catch { return undefined; }
}

const managedFailureProgresses = new WeakMap();
const requiredProgressMethods = [
  'strategyHostBeginManagedFailureProgress',
  'strategyHostRecordManagedFailureAdditionalClosed',
  'strategyHostRecordManagedFailureOperationsCloseAttempted',
  'strategyHostRecordManagedFailureOperationsClosed',
  'strategyHostRecordManagedFailureCleanupStopped',
  'strategyHostRecordManagedFailureExecutionSettled',
  'strategyHostRecordManagedFailureCleanupRefreshed',
  'strategyHostManagedFailureAction',
];

export function beginManagedFailureProgress(
  moon,
  additionalClosed,
  cleanupRefreshed,
) {
  if (moon === null || typeof moon !== 'object' ||
      requiredProgressMethods.some(name => typeof moon[name] !== 'function')) {
    throw new Error('MissingManagedFailureProgress');
  }
  const progress = moon.strategyHostBeginManagedFailureProgress(
    additionalClosed,
    false,
    cleanupRefreshed,
  );
  if (progress === undefined || progress === null) {
    throw new Error('InvalidManagedFailureProgress');
  }
  const owner = Object.freeze({});
  managedFailureProgresses.set(owner, {moon, progress});
  return owner;
}

const managedProgress = owner => {
  const state = managedFailureProgresses.get(owner);
  if (state === undefined) throw new Error('ForeignManagedFailureProgress');
  return state;
};
const recordProgress = (owner, method) => {
  const state = managedProgress(owner);
  if (state.moon[method](state.progress) !== true) {
    throw new Error('InvalidManagedFailureProgress');
  }
};

export function recordManagedFailureExecutionSettled(owner) {
  recordProgress(owner, 'strategyHostRecordManagedFailureExecutionSettled');
}

// The MoonBit planner fixes progression. This adapter only performs physical
// close, stop observation, retry, settlement, and cleanup-refresh calls.
export function settleFailedManagedOperations(
  operations, checked, reason, progressOwner, additionalCleanup = [],
) {
  const progressState = managedProgress(progressOwner);
  const {moon, progress} = progressState;
  const upstreamRequired = member(reason, 'cleanupPending') === true;
  const upstream = upstreamRequired
    ? member(reason, 'cleanupHandle') : undefined;
  const additional = (Array.isArray(additionalCleanup)
    ? additionalCleanup : []).map(value => Object.seal({
    close: member(value, 'close'),
    handle: member(value, 'cleanupHandle'),
    closed: typeof member(value, 'close') !== 'function',
  }));
  const cleanupErrors = [];
  const record = error => { retainFirstAndLatestCleanupError(cleanupErrors, error); };
  const additionalClosed = () => additional.every(cleanup => cleanup.closed);
  const observeAdditionalClosed = () => {
    if (additionalClosed()) {
      recordProgress(
        progressOwner,
        'strategyHostRecordManagedFailureAdditionalClosed',
      );
    }
  };
  const closeAdditional = () => {
    for (const cleanup of additional) {
      if (cleanup.closed) continue;
      try { cleanup.close(); cleanup.closed = true; }
      catch (error) { record(error); }
    }
  };
  const additionalPending = () => additional.some(cleanup =>
    !cleanup.closed || cleanupState(cleanup.handle, cleanup.handle != null).pending);
  const close = () => {
    recordProgress(
      progressOwner,
      'strategyHostRecordManagedFailureOperationsCloseAttempted',
    );
    try {
      operations.close();
      recordProgress(
        progressOwner,
        'strategyHostRecordManagedFailureOperationsClosed',
      );
    }
    catch (error) { record(error); }
  };
  const settle = () => {
    try {
      checked(operations.settle());
      recordManagedFailureExecutionSettled(progressOwner);
    }
    catch (error) { record(error); }
  };
  const refresh = () => {
    try {
      if (operations.cleanup_refresh() === true) {
        recordProgress(
          progressOwner,
          'strategyHostRecordManagedFailureCleanupRefreshed',
        );
      }
    }
    catch (error) { record(error); }
  };
  const stopped = () =>
    !cleanupState(upstream, upstreamRequired).pending && !additionalPending();
  const action = () => {
    observeAdditionalClosed();
    let selected = moon.strategyHostManagedFailureAction(progress);
    if (selected === FAILURE_AWAIT_STOP && stopped()) {
      recordProgress(
        progressOwner,
        'strategyHostRecordManagedFailureCleanupStopped',
      );
      selected = moon.strategyHostManagedFailureAction(progress);
    }
    return selected;
  };
  const drive = () => {
    const attempted = new Set();
    for (let step = 0; step < 12; step++) {
      let selected;
      try { selected = action(); }
      catch (error) { record(error); return false; }
      if (selected === FAILURE_CLOSE_ADDITIONAL) {
        if (attempted.has(selected)) return false;
        attempted.add(selected);
        closeAdditional();
        continue;
      }
      if (selected === FAILURE_CLOSE_OPERATIONS) {
        if (attempted.has(selected)) return false;
        attempted.add(selected);
        close();
        continue;
      }
      if (selected === FAILURE_AWAIT_STOP) return false;
      if (selected === FAILURE_SETTLE_OPERATIONS) {
        settle();
        if (action() === FAILURE_SETTLE_OPERATIONS) return false;
        continue;
      }
      if (selected === FAILURE_REFRESH_CLEANUP) {
        refresh();
        if (action() === FAILURE_REFRESH_CLEANUP) return false;
        continue;
      }
      if (selected === FAILURE_FINISHED) return true;
      record(new Error('InvalidManagedFailureProgress'));
      return false;
    }
    record(new Error('ManagedFailureProgressDidNotConverge'));
    return false;
  };
  const initiallyFinished = drive();
  if (initiallyFinished && cleanupErrors.length === 0) {
    return reason;
  }
  const failure = ownedFailure(reason, 'ManagedExecutionFailed');
  const status = () => {
    const state = cleanupState(upstream, upstreamRequired);
    const extra = additional.map(cleanup =>
      cleanupState(cleanup.handle, cleanup.handle != null));
    let pending = true, selected;
    const statusErrors = [];
    try { selected = action(); pending = selected !== FAILURE_FINISHED; }
    catch (error) { statusErrors.push(error); }
    return Object.freeze({
      pending,
      errors: Object.freeze([
        ...state.errors,
        ...extra.flatMap(value => value.errors),
        ...cleanupErrors,
        ...statusErrors,
      ]),
      ...(pending && Number.isInteger(selected) && selected >= 0 && selected < FAILURE_FINISHED
        ? {cleanupDiagnostic: Object.freeze({
          owner: typeof operations.cleanup_local_continuation === 'function' ? 'local_managed' : 'managed_operations',
          phase: ['close_additional', 'close_operations', 'await_stop', 'settle_operations', 'refresh_cleanup'][selected],
          continuation: (() => {
            const cursor = localCleanupContinuation(operations);
            return cursor === undefined ? 'unavailable' : cursor < 0n ? 'blocked' : 'runnable';
          })(),
        })} : {}),
    });
  };
  const retryOnce = async () => {
    drive();
    if (cleanupState(upstream, upstreamRequired).pending &&
        typeof member(upstream, 'retry') === 'function') {
      try { await upstream.retry(); } catch (error) { record(error); }
    }
    for (const cleanup of additional) {
      if (cleanupState(cleanup.handle, cleanup.handle != null).pending &&
          typeof member(cleanup.handle, 'retry') === 'function') {
        try { await cleanup.handle.retry(); }
        catch (error) { record(error); }
      }
    }
    drive();
    return status();
  };
  let retryFlight;
  const handle = Object.freeze({
    status,
    retry() {
      if (retryFlight !== undefined) return retryFlight;
      retryFlight = Promise.resolve().then(async () => {
        // A borrowed reader can block the initial failure callback, then
        // return before a later retry of this SAME handle. Continue only
        // witnessed finite local retirement; external stalls/errors remain
        // pending and no Compute, stop or release authority is synthesized.
        let previous = localCleanupContinuation(operations);
        let state = await retryOnce();
        while (state.pending && state.errors.length === 0 &&
            typeof previous === 'bigint' && previous >= 0n) {
          const current = localCleanupContinuation(operations);
          if (typeof current !== 'bigint' || current <= previous) break;
          previous = current;
          await new Promise(resolve => setTimeout(resolve, 0));
          const ready = localCleanupContinuation(operations);
          if (typeof ready !== 'bigint' || ready < previous) break;
          state = await retryOnce();
        }
        failure.cleanupErrors = state.errors;
        failure.cleanupPending = state.pending;
        failure.cleanupDiagnostic = state.cleanupDiagnostic;
        return state;
      }).finally(() => { retryFlight = undefined; });
      return retryFlight;
    },
  });
  const initial = status();
  failure.cleanupErrors = initial.errors;
  failure.cleanupPending = initial.pending;
  failure.cleanupDiagnostic = initial.cleanupDiagnostic;
  failure.cleanupHandle = handle;
  return failure;
}
