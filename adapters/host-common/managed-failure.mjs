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

// close and settle are independently retried. Settlement is deliberately
// deferred while an input provider reports unconfirmed access; otherwise the
// common task ledger could release a generation still being read.
export function settleFailedManagedOperations(
  operations, checked, reason, alreadySettled = false,
  additionalCleanup = [],
) {
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
  let settled = alreadySettled;
  let refreshed = typeof member(operations, 'cleanup_refresh') !== 'function';
  const cleanupErrors = [];
  const record = error => { cleanupErrors.push(error); };
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
    try { operations.close(); closed = true; }
    catch (error) { record(error); }
  };
  const settle = () => {
    if (settled || cleanupState(upstream, upstreamRequired).pending ||
        additionalPending()) return;
    try { checked(operations.settle()); settled = true; }
    catch (error) { record(error); }
  };
  const refresh = () => {
    if (refreshed || !closed || !settled) return;
    try { refreshed = operations.cleanup_refresh() === true; }
    catch (error) { record(error); }
  };
  closeAdditional();
  close();
  settle();
  refresh();
  if (closed && settled && !cleanupState(upstream, upstreamRequired).pending &&
      !additionalPending() && refreshed && cleanupErrors.length === 0) {
    return reason;
  }
  const failure = ownedFailure(reason, 'ManagedExecutionFailed');
  const status = () => {
    const state = cleanupState(upstream, upstreamRequired);
    const extra = additional.map(cleanup =>
      cleanupState(cleanup.handle, cleanup.handle != null));
    return Object.freeze({
      pending: state.pending || additionalPending() ||
        !closed || !settled || !refreshed,
      errors: Object.freeze([
        ...state.errors,
        ...extra.flatMap(value => value.errors),
        ...cleanupErrors,
      ]),
    });
  };
  const handle = Object.freeze({
    status,
    async retry() {
      if (cleanupState(upstream, upstreamRequired).pending &&
          typeof member(upstream, 'retry') === 'function') {
        try { await upstream.retry(); } catch (error) { record(error); }
      }
      closeAdditional();
      for (const cleanup of additional) {
        if (cleanupState(cleanup.handle, cleanup.handle != null).pending &&
            typeof member(cleanup.handle, 'retry') === 'function') {
          try { await cleanup.handle.retry(); }
          catch (error) { record(error); }
        }
      }
      close();
      settle();
      refresh();
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
