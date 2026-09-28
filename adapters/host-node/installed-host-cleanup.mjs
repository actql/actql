// Failed initialization has no returned Host to own its resources. Keep the
// same retry/status protocol as publication cleanup, without restarting work.
export async function retainInstalledHostInitializationFailure(cause,
  {journal, store, checkpoints, dispatchOwner, sourceProfile,
    installedEffect}) {
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

// Once dispatch and Checkpoint owners have stopped, these resource closures
// are independent. A failed close retains only that owner for the next call;
// another adapter or the Store must not be skipped or closed twice.
export function createInstalledHostShutdown({stop, drain, retire, checkpoint,
  journal, source, effect, store}) {
  const completed = new Set();
  const pending = Object.freeze(['stop', 'drain', 'retire', 'checkpoint',
    'journal', 'source', 'effect', 'store']);
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
      ['source', source], ['effect', effect], ['store', store]]) {
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
      if (error.cleanupHandle === undefined) {
        error.cleanupHandle = Object.freeze({status, retry: close});
      }
      error.cleanupPending = status().pending.length > 0;
      throw error;
    }).finally(() => { flight = undefined; });
    return flight;
  }
  return Object.freeze({close, status});
}
