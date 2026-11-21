type Action<T = unknown> = () => T | PromiseLike<T>;
type CloseOwner = {close: Action};
type CleanupIssue = Readonly<{owner: string; error: unknown}>;
type ObservedStatus = {pending?: unknown; errors?: readonly unknown[]};
type ObservedCleanup = {status?: () => ObservedStatus | null | undefined; retry?: Action};
type ObservedFailure = {
  code?: unknown;
  primaryFailure?: unknown;
  cleanupErrors?: readonly unknown[];
  cleanupPending?: unknown;
  cleanupHandle?: ObservedCleanup;
};
type PendingStatus = Readonly<{pending: boolean; errors: readonly unknown[]}>;
type HostCleanupStatus = PendingStatus & Readonly<{owners: readonly string[]}>;
type ShutdownStatus = Readonly<{pending: string[]}>;
type CleanupHandle<S, R = S> = Readonly<{status: () => S; retry: () => Promise<R>}>;
type CleanupFields<S, R = S> = {
  cleanupPending?: boolean;
  cleanupErrors?: readonly unknown[];
  cleanupError?: unknown;
  cleanupHandle?: CleanupHandle<S, R>;
};
type InitializationFailure = Error & {code: string; primaryFailure: unknown} &
  Required<Pick<CleanupFields<HostCleanupStatus>, 'cleanupPending' | 'cleanupErrors' | 'cleanupHandle'>>;
type InitialControl = {close?: unknown};
type InitializationHoldings = {
  journal?: CloseOwner; closeJournal?: Action; closeInitializationJournal?: Action;
  store?: CloseOwner; checkpoints?: CloseOwner & {stop: Action};
  dispatchOwner?: {drain: Action}; sourceReader?: object; sourceProfile?: CloseOwner;
  authorization?: object; secretMaterial?: CloseOwner; installedEffect?: CloseOwner;
  observation?: CloseOwner; ownerViews?: CloseOwner; initialControl?: InitialControl;
  publicationOwnership?: CloseOwner;
};
type CheckpointCloseResult = {pendingRetention?: readonly unknown[]; pendingAuthorization?: boolean};
type ShutdownHoldings = {
  stop: Action; drain: Action; retire: Action; checkpoint: Action<CheckpointCloseResult | undefined>;
  journal: Action; source: Action; effect: Action; store: Action; diagnostic?: Action;
  observation?: Action; ownerViews?: Action; initialControl?: InitialControl;
  finalize?: Action; publicationOwnership?: Action;
};
type ShutdownResult = Readonly<{
  storeCleanupPending: boolean;
  pendingRetention: readonly unknown[];
  authorizationCleanupPending: boolean;
}>;
type CredentialSite = CloseOwner & {cleanupPending: () => unknown};

// Failed initialization has no returned Host to own its resources. Keep the
// same retry/status protocol as publication cleanup, without restarting work.
export function originalInitialControlClose(original: InitialControl) {
  let close: unknown, captured = false;
  function captureOriginalClose() {
    if (!captured) {
      close = original.close;
      captured = true;
    }
  }
  // Retain a successfully observed callback before any child cleanup await.
  // Do not invoke it until those original children have completed.
  try {
    captureOriginalClose();
  } catch {
    // A failed getter has not supplied a callback. Keep the holding in its
    // cleanup Owner and retry only that still-unobserved getter there.
  }
  return async () => {
    captureOriginalClose();
    if (typeof close !== 'function') {
      throw new TypeError('InstalledHostInitialControlCleanupMissing');
    }
    const observed: ObservedStatus | null | undefined = await Reflect.apply(close, original, []);
    if (observed?.pending !== false) {
      throw new TypeError('InstalledHostInitialControlCleanupPending');
    }
    return observed;
  };
}

export async function retainInstalledHostInitializationFailure(cause: unknown,
  {journal, closeJournal, closeInitializationJournal, store, checkpoints, dispatchOwner, sourceReader, sourceProfile, authorization, secretMaterial,
    installedEffect, observation, ownerViews, initialControl, publicationOwnership}: InitializationHoldings) {
  const closeInitialControl = initialControl === undefined ? undefined :
    originalInitialControlClose(initialControl);
  // Retain the original receiver and methods before the first cleanup await.
  // A changed error property cannot acknowledge a different physical owner.
  let originalCleanup: ObservedCleanup | undefined, originalPending: boolean | undefined;
  let cleanupCaptured = false, pendingCaptured = false;
  let originalRetry: ObservedCleanup['retry'], originalStatus: ObservedCleanup['status'];
  let retryCaptured = false, statusCaptured = false;
  function captureOriginalCleanup() {
    if (!cleanupCaptured) {
      originalCleanup = (cause as ObservedFailure | null | undefined)?.cleanupHandle;
      cleanupCaptured = true;
    }
    if (originalCleanup === undefined && !pendingCaptured) {
      originalPending = (cause as ObservedFailure | null | undefined)?.cleanupPending === true;
      pendingCaptured = true;
    }
  }
  function captureOriginalStatus() {
    captureOriginalCleanup();
    if (!statusCaptured) {
      originalStatus = originalCleanup?.status;
      statusCaptured = true;
    }
  }
  // Establish custody before reading failure getters. A failed observation
  // cannot discard another already acquired holding during Owner setup.
  const pending = new Set(['initialization']);
  if (checkpoints !== undefined) pending.add('checkpoint-stop');
  if (dispatchOwner !== undefined) pending.add('dispatch');
  if (sourceReader !== undefined) pending.add('source-reader');
  if (sourceProfile !== undefined) pending.add('source-profile');
  if (authorization !== undefined) pending.add('authorization');
  if (secretMaterial !== undefined) pending.add('secret-material');
  if (installedEffect !== undefined) pending.add('effect-profile');
  if (checkpoints !== undefined) pending.add('checkpoints');
  if (journal !== undefined) pending.add('journal');
  if (store !== undefined) pending.add('store');
  if (observation !== undefined) pending.add('observation');
  if (ownerViews !== undefined) pending.add('owner-views');
  if (initialControl !== undefined) pending.add('initial-control');
  if (publicationOwnership !== undefined) pending.add('publication-ownership');
  let originalSourceReaderRetire: Action | undefined, sourceReaderRetireCaptured = false;
  function captureOriginalSourceReaderRetirement() {
    if (!sourceReaderRetireCaptured) {
      const field = Object.getOwnPropertyDescriptor(sourceReader!, 'retire');
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
        throw new TypeError('InstalledSourceReaderRetirementMissing');
      }
      originalSourceReaderRetire = field.value;
      sourceReaderRetireCaptured = true;
    }
  }
  let originalAuthorizationClose: Action | undefined, authorizationCloseCaptured = false;
  function captureOriginalAuthorizationClose() {
    if (!authorizationCloseCaptured) {
      const field = Object.getOwnPropertyDescriptor(authorization!, 'close');
      if (!field || !Object.hasOwn(field, 'value') || typeof field.value !== 'function') {
        throw new TypeError('InstalledSourceAuthorizationCleanupMissing');
      }
      originalAuthorizationClose = field.value;
      authorizationCloseCaptured = true;
    }
  }
  // The same constructed factory/Account must survive the first cleanup
  // await. Only their own synchronous true acknowledges retirement.
  if (sourceReader !== undefined) {
    try { captureOriginalSourceReaderRetirement(); }
    catch { /* Retry only the still-unobserved original method. */ }
  }
  if (authorization !== undefined) {
    try { captureOriginalAuthorizationClose(); }
    catch { /* Retain the original Account when method capture fails. */ }
  }
  const errors: CleanupIssue[] = [];
  let primaryFailure = cause;
  try { primaryFailure = (cause as ObservedFailure | null | undefined)?.primaryFailure ?? cause; }
  catch { /* Diagnostic access never replaces the original thrown value. */ }
  const failure = Object.assign(new Error('InstalledHostInitializationFailed',
    {cause}), {code: 'InstalledHostInitializationFailed',
    primaryFailure}) as InitializationFailure;
  let originalErrors: readonly unknown[] = [];
  let observationFailure: CleanupIssue | undefined;
  try {
    const observedErrors = (cause as ObservedFailure | null | undefined)?.cleanupErrors;
    if (Array.isArray(observedErrors)) originalErrors = observedErrors;
  } catch (error) {
    observationFailure = Object.freeze({owner: 'initialization', error});
  }
  function observeOriginalCleanup() {
    try {
      captureOriginalStatus();
      const observed = originalStatus?.call(originalCleanup);
      const observedPending = observed?.pending !== false;
      originalErrors = [...(observed?.errors ?? (cause as ObservedFailure | null | undefined)?.cleanupErrors ?? [])];
      return observedPending;
    } catch (error) {
      // Observation is not an ACK. Retain one diagnostic rather than growing
      // the error history on every status poll, and keep the original owner.
      observationFailure ??= Object.freeze({owner: 'initialization', error});
      return true;
    }
  }
  const status = () => {
    if (pending.has('initialization')) observeOriginalCleanup();
    return Object.freeze({pending: pending.size !== 0,
      owners: Object.freeze([...pending]), errors: Object.freeze([
        ...originalErrors, ...(observationFailure === undefined ? [] :
          [observationFailure]), ...errors])});
  };
  async function attempt(name: string, close: Action | undefined) {
    if (!pending.has(name)) return;
    try {
      await close!();
      pending.delete(name);
    } catch (error) {
      // A pending cleanup may be observed/retried for an unbounded duration.
      // Keep each original phase's first and latest failures, not an ever
      // growing retry history inside the same retained preparation holding.
      const record = Object.freeze({owner: name, error});
      const latest = errors.findLastIndex(item => item.owner === name);
      const first = errors.findIndex(item => item.owner === name);
      if (latest === first) errors.push(record);
      else errors[latest] = record;
    }
  }
  let flight: Promise<HostCleanupStatus> | undefined;
  async function drain() {
    // A failed actual Store opening can hold a physical cleanup child that
    // waits for this SAME Journal. Its Host caller retains this captured
    // original close only for that pre-service constructor failure. Do not
    // gate it behind the dependent child or change unrelated initializers.
    if (closeInitializationJournal !== undefined) {
      await attempt('journal', closeInitializationJournal);
    }
    await attempt('initialization', async () => {
      // Property access can itself fail. Keep it inside this original Owner's
      // attempt; only an unobserved method may be captured on a later retry.
      captureOriginalCleanup();
      if (originalCleanup === undefined && !originalPending) return;
      if (!retryCaptured) {
        originalRetry = originalCleanup?.retry;
        retryCaptured = true;
      }
      captureOriginalStatus();
      if (typeof originalRetry !== 'function' ||
          typeof originalStatus !== 'function') {
        throw new Error('InstalledHostInitializationCleanupOwnerMissing');
      }
      await originalRetry.call(originalCleanup);
      if (observeOriginalCleanup()) {
        throw new Error('InstalledHostInitializationCleanupPending');
      }
    });
    await attempt('checkpoint-stop', () => checkpoints!.stop());
    if (!pending.has('initialization') && !pending.has('checkpoint-stop')) {
      await attempt('dispatch', () => dispatchOwner!.drain());
      if (!pending.has('dispatch')) {
        await attempt('source-reader', async function retireSourceReader() {
          captureOriginalSourceReaderRetirement();
          const completed = Reflect.apply(originalSourceReaderRetire!, sourceReader, []);
          if (completed !== true) {
            if (typeof (completed as {then?: unknown} | null | undefined)?.then === 'function') await completed;
            throw new TypeError('InstalledSourceReaderRetirementPending');
          }
          sourceReader = originalSourceReaderRetire = undefined;
        });
        if (!pending.has('source-reader')) {
          await attempt('source-profile', () => sourceProfile!.close());
          if (!pending.has('source-profile')) {
            await attempt('authorization', async function closeAuthorization() {
              captureOriginalAuthorizationClose();
              const completed = Reflect.apply(originalAuthorizationClose!, authorization, []);
              if (completed !== true) {
                if (typeof (completed as {then?: unknown} | null | undefined)?.then === 'function') await completed;
                throw new TypeError('InstalledSourceAuthorizationCleanupPending');
              }
              authorization = originalAuthorizationClose = undefined;
            });
            if (!pending.has('authorization')) {
              await attempt('secret-material', () => secretMaterial!.close());
            }
          }
        }
        await attempt('effect-profile', () => installedEffect!.close());
        await attempt('checkpoints', () => checkpoints!.close());
        if (!pending.has('checkpoints')) {
          // Neither physical owner needs the other after dispatch has settled.
          // A journal close failure must not prevent the Store close attempt.
          await attempt('journal', closeJournal ?? (() => journal!.close()));
          await attempt('store', () => store!.close());
          await attempt('publication-ownership', () => publicationOwnership!.close());
          await attempt('observation', () => observation!.close());
          await attempt('owner-views', () => ownerViews!.close());
          // The initial control holding can contain every preparation/child
          // alias. Retain it until all original cleanup owners are confirmed;
          // a failed independent Store/journal close is not their retirement.
          if ([...pending].every(name => name === 'initial-control')) {
            await attempt('initial-control', closeInitialControl);
          }
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
export function retainInstalledHostRuntimeFailure<Cause>(cause: Cause, retire: Action) {
  let child = (cause as ObservedFailure | null | undefined)?.cleanupHandle;
  let childStatus = child?.status, childRetry = child?.retry;
  let childComplete = child === undefined && (cause as ObservedFailure | null | undefined)?.cleanupPending !== true;
  let retirementComplete = false, finalize: Action | undefined = retire,
    flight: Promise<HostCleanupStatus> | undefined, lastError: unknown;
  let failureOwner = 'initialization';
  const originalErrors = (cause as ObservedFailure | null | undefined)?.cleanupErrors;
  let childErrors: readonly unknown[] = Array.isArray(originalErrors) ? originalErrors : [];
  const failure = Object.assign(new Error('InstalledHostInitializationCleanupPending', {cause}), {
    code: (cause as ObservedFailure | null | undefined)?.code ?? 'InstalledHostInitializationCleanupPending',
    primaryFailure: (cause as ObservedFailure | null | undefined)?.primaryFailure ?? cause,
  }) as Error & {code: unknown; primaryFailure: unknown} & CleanupFields<HostCleanupStatus>;
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
    const observed: ObservedStatus | null | undefined = Reflect.apply(childStatus, child, []);
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
    finalize!();
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
          await Reflect.apply(childRetry!, child, []);
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
  journal, source, effect, store, diagnostic, observation, ownerViews,
  initialControl, finalize, publicationOwnership}: ShutdownHoldings) {
  const closeInitialControl = initialControl === undefined ? undefined :
    originalInitialControlClose(initialControl);
  const completed = new Set();
  const pending = Object.freeze(['stop', 'drain', 'retire', 'checkpoint',
    'journal', 'source', 'effect', 'store',
    ...(publicationOwnership === undefined ? [] : ['publicationOwnership']),
    ...(diagnostic === undefined ? [] : ['diagnostic']),
    ...(observation === undefined ? [] : ['observation']),
    ...(ownerViews === undefined ? [] : ['ownerViews']),
    ...(initialControl === undefined ? [] : ['initialControl']),
    ...(finalize === undefined ? [] : ['finalize'])]);
  let flight: Promise<ShutdownResult> | undefined;
  let checkpointResult: CheckpointCloseResult | undefined;
  let storeCleanupPending = false;
  const status = () => Object.freeze({pending: pending.filter(name =>
    !completed.has(name))});
  async function attempt<T>(name: string, action: Action<T> | undefined) {
    if (completed.has(name)) return undefined;
    const result = await action!();
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
    const failures: CleanupIssue[] = [];
    for (const [name, action] of ([['journal', journal],
      ['source', source], ['effect', effect], ['store', store],
      ...(publicationOwnership === undefined ? [] : [['publicationOwnership', publicationOwnership]]),
      ...(ownerViews === undefined ? [] : [['ownerViews',ownerViews]])] as [string, Action][])) {
      try {
        await attempt(name, action);
        if (name === 'store') storeCleanupPending = false;
      } catch (error) {
        if (name === 'store' &&
            (error as ObservedFailure | null | undefined)?.code === 'PublicationStoreCleanupPending') {
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
        storeCleanupPending}) as AggregateError & CleanupFields<ShutdownStatus, ShutdownResult>;
      error.cleanupHandle = Object.freeze({status, retry: close});
      throw error;
    }
    await attempt('diagnostic', () => diagnostic?.());
    await attempt('observation', () => observation?.());
    if (initialControl !== undefined) {
      // Completing a Promise alone cannot acknowledge the original scope.
      await attempt('initialControl', closeInitialControl);
    }
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
      const failure = (error !== null && typeof error === 'object' &&
        Object.isExtensible(error) ? error
        : Object.assign(new Error('InstalledHostCleanupPending', {cause: error}),
          {code: (error as ObservedFailure | null | undefined)?.code ?? 'InstalledHostCleanupPending',
            primaryFailure: error})) as object & CleanupFields<ShutdownStatus, ShutdownResult>;
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

// The failure of a caller that acquired `site`: the primary failure stays
// the error, and the Site's release is attempted at once. When it does not
// complete, the error carries the release responsibility (`cleanupPending`,
// `cleanupErrors`, `cleanupHandle` {retry, status}) to the caller, beside any
// cleanup responsibility it already carried. A frozen or non-object failure
// is wrapped with `primaryFailure`.
export function retainInstalledCredentialSiteCleanup(site: CredentialSite, primary: unknown,
  ownerFailureCode = 'InstalledCredentialSiteOwnerFailed') {
  const errors: unknown[] = [];
  try { site.close(); } catch (error) { errors.push(error); }
  return handOverCredentialSiteRelease(site, primary, errors, ownerFailureCode);
}

// Release `site` after its caller succeeded. A release that does not
// complete throws its failure carrying the retry responsibility; the failed
// attempt is not repeated here.
export function releaseInstalledCredentialSite(site: CredentialSite,
  ownerFailureCode = 'InstalledCredentialSiteOwnerFailed') {
  try { site.close(); }
  catch (error) { throw handOverCredentialSiteRelease(site, error, [error], ownerFailureCode); }
}

function handOverCredentialSiteRelease(site: CredentialSite, primary: unknown, errors: unknown[], ownerFailureCode: string) {
  // Capture the previous owner before wrapping or replacing its metadata.
  const earlier = (primary as ObservedFailure | null | undefined)?.cleanupHandle;
  const earlierOwned = earlier !== undefined || (primary as ObservedFailure | null | undefined)?.cleanupPending === true;
  const earlierErrors = (primary as ObservedFailure | null | undefined)?.cleanupErrors ?? [];
  let originalStatus: ObservedCleanup['status'], originalRetry: ObservedCleanup['retry'];
  let statusCaptured = false, retryCaptured = false;
  function captureEarlierMethods() {
    // Capture each successfully observed method once, before invoking either
    // one. A failed getter keeps the same receiver pending for a later check.
    if (!retryCaptured) {
      originalRetry = earlier?.retry;
      retryCaptured = true;
    }
    if (!statusCaptured) {
      originalStatus = earlier?.status;
      statusCaptured = true;
    }
  }
  const earlierStatus = () => {
    try {
      captureEarlierMethods();
      return typeof originalStatus === 'function'
        ? originalStatus.call(earlier) : undefined;
    } catch (error) {
      // An unavailable observation cannot replace the primary failure or
      // confirm release. Keep the retry owner and the observation failure.
      if (!errors.includes(error)) errors.push(error);
      return undefined;
    }
  };
  const failure = (primary !== null && typeof primary === 'object' &&
    Object.isExtensible(primary) ? primary
    : Object.assign(new Error(ownerFailureCode, {cause: primary}),
      {code: (primary as ObservedFailure | null | undefined)?.code ?? ownerFailureCode,
        primaryFailure: primary})) as object & CleanupFields<PendingStatus>;
  if (site.cleanupPending() !== true && !earlierOwned) return failure;
  const status = () => {
    const before = earlierStatus();
    return Object.freeze({
      // Only the previous owner can confirm its own release. A missing or
      // incomplete handle must not turn an outstanding duty into success.
      pending: site.cleanupPending() === true ||
        earlierOwned && before?.pending !== false,
      errors: Object.freeze([...(before?.errors ?? earlierErrors), ...errors])});
  };
  const handle = Object.freeze({status, async retry() {
    if (earlierStatus()?.pending !== false) {
      try {
        captureEarlierMethods();
        if (typeof originalRetry === 'function') {
          await originalRetry.call(earlier);
        }
      } catch (error) { if (!errors.includes(error)) errors.push(error); }
    }
    if (site.cleanupPending() === true) {
      try { site.close(); } catch (error) { errors.push(error); }
    }
    const current = status();
    failure.cleanupPending = current.pending;
    failure.cleanupErrors = current.errors;
    return current;
  }});
  failure.cleanupPending = status().pending;
  failure.cleanupErrors = status().errors;
  failure.cleanupHandle = handle;
  return failure;
}
