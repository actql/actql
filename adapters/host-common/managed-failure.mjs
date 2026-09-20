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
  const record = error => { cleanupErrors.push(error); };
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
