// Failed initialization has no returned Host to own its resources. Keep the
// same retry/status protocol as publication cleanup, without restarting work.
export async function retainInstalledHostInitializationFailure(cause,
  {journal, store, checkpoints, dispatchOwner, sourceProfile,
    installedEffect, observation, ownerViews}) {
  const pending = new Set();
  if (cause?.cleanupHandle !== undefined || cause?.cleanupPending === true) {
    pending.add('initialization');
  }
  if (checkpoints !== undefined) pending.add('checkpoint-stop');
  if (dispatchOwner !== undefined) pending.add('dispatch');
  if (sourceProfile !== undefined) pending.add('source-profile');
  if (installedEffect !== undefined) pending.add('effect-profile');
  if (checkpoints !== undefined) pending.add('checkpoints');
  if (journal !== undefined) pending.add('journal');
  if (store !== undefined) pending.add('store');
  if (observation !== undefined) pending.add('observation');
  if (ownerViews !== undefined) pending.add('owner-views');
  const errors = [];
  const failure = Object.assign(new Error('InstalledHostInitializationFailed',
    {cause}), {code: 'InstalledHostInitializationFailed',
    primaryFailure: cause?.primaryFailure ?? cause});
  const status = () => Object.freeze({pending: pending.size !== 0,
    owners: Object.freeze([...pending]), errors: Object.freeze([
      ...(cause?.cleanupHandle?.status?.().errors ??
        cause?.cleanupErrors ?? []), ...errors])});
  async function attempt(name, close) {
    if (!pending.has(name)) return;
    try {
      await close();
      pending.delete(name);
    } catch (error) { errors.push(Object.freeze({owner: name, error})); }
  }
  let flight;
  async function drain() {
    await attempt('initialization', async () => {
      if (typeof cause.cleanupHandle?.retry !== 'function' ||
          typeof cause.cleanupHandle?.status !== 'function') {
        throw new Error('InstalledHostInitializationCleanupOwnerMissing');
      }
      await cause.cleanupHandle.retry();
      if (cause.cleanupHandle.status().pending !== false) {
        throw new Error('InstalledHostInitializationCleanupPending');
      }
    });
    await attempt('checkpoint-stop', () => checkpoints.stop());
    if (!pending.has('initialization') && !pending.has('checkpoint-stop')) {
      await attempt('dispatch', () => dispatchOwner.drain());
      if (!pending.has('dispatch')) {
        await attempt('source-profile', () => sourceProfile.close());
        await attempt('effect-profile', () => installedEffect.close());
        await attempt('checkpoints', () => checkpoints.close());
        if (!pending.has('checkpoints')) {
          // Neither physical owner needs the other after dispatch has settled.
          // A journal close failure must not prevent the Store close attempt.
          await attempt('journal', () => journal.close());
          await attempt('store', () => store.close());
          await attempt('observation', () => observation.close());
          await attempt('owner-views', () => ownerViews.close());
        }
      }
    }
    failure.cleanupPending = status().pending;
    failure.cleanupErrors = status().errors;
    return status();
  }
  function retry() {
    if (flight !== undefined) return flight;
    flight = drain().finally(() => { flight = undefined; });
    return flight;
  }
  failure.cleanupHandle = Object.freeze({status, retry});
  await retry();
  return failure;
}

// Keep the existing Host's final reference-retirement duty behind the exact
// failed initializer's cleanup. Never mutate a borrowed/frozen exception or
// infer successful retirement from its request/Promise alone.
export function retainInstalledHostRuntimeFailure(cause, retire) {
  let child = cause?.cleanupHandle;
  let childStatus = child?.status, childRetry = child?.retry;
  let childComplete = child === undefined && cause?.cleanupPending !== true;
  let retirementComplete = false, finalize = retire, flight, lastError;
  let failureOwner = 'initialization';
  const originalErrors = cause?.cleanupErrors;
  let childErrors = Array.isArray(originalErrors) ? originalErrors : [];
  const failure = Object.assign(new Error('InstalledHostInitializationCleanupPending', {cause}), {
    code: cause?.code ?? 'InstalledHostInitializationCleanupPending',
    primaryFailure: cause?.primaryFailure ?? cause,
  });
  const status = () => Object.freeze({pending: !childComplete || !retirementComplete,
    owners: Object.freeze([...(childComplete ? [] : ['initialization']),
      ...(retirementComplete ? [] : ['runtime'])]),
    errors: Object.freeze([...childErrors,
      ...(lastError === undefined ? [] : [Object.freeze({owner: failureOwner, error: lastError})])])});
  const observeChild = () => {
    if (childComplete) return true;
    if (typeof childStatus !== 'function' || typeof childRetry !== 'function') {
      throw new Error('InstalledHostInitializationCleanupOwnerMissing');
    }
    const observed = Reflect.apply(childStatus, child, []);
    const errors = observed?.errors;
    if (Array.isArray(errors)) childErrors = errors;
    if (observed?.pending !== false) return false;
    childComplete = true;
    child = childStatus = childRetry = undefined;
    return true;
  };
  const retireOnce = () => {
    if (retirementComplete) return;
    failureOwner = 'runtime';
    finalize();
    retirementComplete = true;
    finalize = undefined;
  };
  const update = () => {
    const observed = status();
    failure.cleanupPending = observed.pending;
    failure.cleanupErrors = observed.errors;
    failure.cleanupError = lastError;
    return observed;
  };
  function retry() {
    if (flight !== undefined) return flight;
    if (childComplete && retirementComplete) return Promise.resolve(status());
    flight = Promise.resolve().then(async () => {
      try {
        failureOwner = 'initialization';
        if (!observeChild()) {
          await Reflect.apply(childRetry, child, []);
          if (!observeChild()) return update();
        }
        retireOnce();
        return update();
      } catch (error) {
        lastError = error;
        update();
        throw failure;
      }
    }).finally(() => {flight = undefined;});
    return flight;
  }
  failure.cleanupHandle = Object.freeze({status, retry});
  // Merely attaching the finalizer must not retry the initializer's work.
  try {
    if (observeChild()) {
      retireOnce();
      return cause;
    }
  } catch (error) {lastError = error;}
  update();
  return failure;
}

// Once dispatch and Checkpoint owners have stopped, these resource closures
// are independent. A failed close retains only that owner for the next call;
// another adapter or the Store must not be skipped or closed twice.
export function createInstalledHostShutdown({stop, drain, retire, checkpoint,
  journal, source, effect, store, diagnostic, observation, ownerViews, finalize}) {
  const completed = new Set();
  const pending = Object.freeze(['stop', 'drain', 'retire', 'checkpoint',
    'journal', 'source', 'effect', 'store',
    ...(diagnostic === undefined ? [] : ['diagnostic']),
    ...(observation === undefined ? [] : ['observation']),
    ...(ownerViews === undefined ? [] : ['ownerViews']),
    ...(finalize === undefined ? [] : ['finalize'])]);
  let flight;
  let checkpointResult;
  let storeCleanupPending = false;
  const status = () => Object.freeze({pending: pending.filter(name =>
    !completed.has(name))});
  async function attempt(name, action) {
    if (completed.has(name)) return undefined;
    const result = await action();
    completed.add(name);
    return result;
  }
  async function closeOnce() {
    await attempt('stop', stop);
    await attempt('drain', drain);
    await attempt('retire', retire);
    const completedCheckpoint = await attempt('checkpoint', checkpoint);
    if (completedCheckpoint !== undefined) {
      checkpointResult = completedCheckpoint;
    }
    const failures = [];
    for (const [name, action] of [['journal', journal],
      ['source', source], ['effect', effect], ['store', store],
      ...(ownerViews === undefined ? [] : [['ownerViews',ownerViews]])]) {
      try {
        await attempt(name, action);
        if (name === 'store') storeCleanupPending = false;
      } catch (error) {
        if (name === 'store' &&
            error?.code === 'PublicationStoreCleanupPending') {
          storeCleanupPending = true;
        }
        failures.push(Object.freeze({owner: name, error}));
      }
    }
    if (failures.length > 0) {
      const error = Object.assign(new AggregateError(
        failures.map(item => item.error), 'InstalledHostCleanupPending'),
      {code: 'InstalledHostCleanupPending', cleanupErrors: failures,
        cleanupPending: status().pending.length > 0,
        storeCleanupPending});
      error.cleanupHandle = Object.freeze({status, retry: close});
      throw error;
    }
    await attempt('diagnostic', () => diagnostic?.());
    await attempt('observation', () => observation?.());
    if (finalize !== undefined) {
      try {
        await attempt('finalize', finalize);
        finalize = undefined;
      }
      catch (cause) {
        throw Object.assign(new Error('InstalledHostCleanupPending', {cause}), {
          code: 'InstalledHostCleanupPending', primaryFailure: cause,
        });
      }
    }
    return Object.freeze({storeCleanupPending,
      pendingRetention: checkpointResult?.pendingRetention ?? [],
      authorizationCleanupPending:
        checkpointResult?.pendingAuthorization ?? false});
  }
  function close() {
    if (flight !== undefined) return flight;
    flight = closeOnce().catch(error => {
      // stop/drain/retire/checkpoint failures also leave an owned shutdown.
      // The caller may retry without reopening either installed adapter.
      const failure = error !== null && typeof error === 'object' &&
        Object.isExtensible(error) ? error
        : Object.assign(new Error('InstalledHostCleanupPending', {cause: error}),
          {code: error?.code ?? 'InstalledHostCleanupPending',
            primaryFailure: error});
      if (failure.cleanupHandle === undefined) {
        failure.cleanupHandle = Object.freeze({status, retry: close});
      }
      failure.cleanupPending = status().pending.length > 0;
      throw failure;
    }).finally(() => { flight = undefined; });
    return flight;
  }
  return Object.freeze({close, status});
}
