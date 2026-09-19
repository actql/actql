// Failure settlement for synchronous managed implementations. A returned
// Promise and a stopped representation reader are different facts: reservation
// settlement waits for the latter, while close is attempted immediately.
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

// The MoonBit planner fixes progression. This adapter only performs physical
// close, stop observation, retry, settlement, and cleanup-refresh calls.
export function settleFailedManagedOperations(
  operations, checked, reason, alreadySettled = false,
  additionalCleanup = [], nextAction,
) {
  if (typeof nextAction !== 'function') {
    throw new Error('MissingManagedFailureProgress');
  }
  const upstreamRequired = member(reason, 'cleanupPending') === true;
  const upstream = upstreamRequired
    ? member(reason, 'cleanupHandle') : undefined;
  const additional = (Array.isArray(additionalCleanup)
    ? additionalCleanup : []).map(value => Object.seal({
    close: member(value, 'close'),
    handle: member(value, 'cleanupHandle'),
    closed: typeof member(value, 'close') !== 'function',
  }));
  let closed = false;
  let closeAttempted = false;
  let settled = alreadySettled;
  let refreshed = typeof member(operations, 'cleanup_refresh') !== 'function';
  const cleanupErrors = [];
  const record = error => { cleanupErrors.push(error); };
  const additionalClosed = () => additional.every(cleanup => cleanup.closed);
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
    if (closed) return;
    closeAttempted = true;
    try { operations.close(); closed = true; }
    catch (error) { record(error); }
  };
  const settle = () => {
    if (settled) return;
    try { checked(operations.settle()); settled = true; }
    catch (error) { record(error); }
  };
  const refresh = () => {
    if (refreshed) return;
    try { refreshed = operations.cleanup_refresh() === true; }
    catch (error) { record(error); }
  };
  const stopped = () =>
    !cleanupState(upstream, upstreamRequired).pending && !additionalPending();
  const action = () => nextAction(
    additionalClosed(), closeAttempted, closed, stopped(), settled, refreshed,
  );
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
        if (!settled) return false;
        continue;
      }
      if (selected === FAILURE_REFRESH_CLEANUP) {
        refresh();
        if (!refreshed) return false;
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
    let pending = true;
    const statusErrors = [];
    try { pending = action() !== FAILURE_FINISHED; }
    catch (error) { statusErrors.push(error); }
    return Object.freeze({
      pending,
      errors: Object.freeze([
        ...state.errors,
        ...extra.flatMap(value => value.errors),
        ...cleanupErrors,
        ...statusErrors,
      ]),
    });
  };
  const handle = Object.freeze({
    status,
    async retry() {
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
      failure.cleanupErrors = status().errors;
      failure.cleanupPending = status().pending;
      return status();
    },
  });
  failure.cleanupErrors = status().errors;
  failure.cleanupPending = status().pending;
  failure.cleanupHandle = handle;
  return failure;
}
