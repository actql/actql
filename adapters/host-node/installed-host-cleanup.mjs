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
    owners: Object.freeze([...pending]), errors: Object.freeze([...errors])});
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
