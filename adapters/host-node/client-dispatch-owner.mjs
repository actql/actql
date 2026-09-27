// One installed Host owner for an admitted Run's physical dispatch, stop
// observation, and recoverable cleanup. The journal and MoonBit control keep
// their existing authority; this owner does not decide whether to retry.
import {openCapturedDuckDBSource} from './captured-duckdb-source.mjs';
import {CapturedRunPublicationError,
  runPublishedCapturedStrategy} from './entry.mjs';
import {acquiredTaskPublicationPlan} from './local-values-plan.mjs';

export function installNodeClientDispatchOwner({moon, control, journal,
  store, checkpoints, startRun, hostConnection, beforeDispatch, observed,
  prepareAcquisition, planFor, sourceProfile, registry, values, fragment,
  ordered, tenantId, authorityScopeCid, storeAuthorityCid, now,
  runPublished = runPublishedCapturedStrategy}) {
  const entries = new Map();
  const keyOf = ref => ref.runDefinitionCid;
  const current = ref => entries.get(keyOf(ref));
  const cancel = ref => current(ref)?.abort.abort(
    new Error('ClientRunCancellationRequested'));
  const live = ref => current(ref)?.settled === false;
  const operation = ref => current(ref)?.promise;

  function retire(entry) {
    if (entry.settled && entry.cleanupOwner === undefined &&
        entry.cleanupHandle === undefined && !entry.unresolvedCleanup &&
        entry.sourceCapture === undefined &&
        !entry.stopObservationPending &&
        !entry.failureObservationPending && !entry.finishPending &&
        !entry.releasePending &&
        (!entry.physicalStarted || entry.stopObserved ||
          !entry.physicalWorkMayHaveStarted)) {
      entries.delete(keyOf(entry.ref));
    }
  }

  async function observeStop(entry) {
    let publicationCommitted = entry.publicationCommitted === true;
    if (!publicationCommitted) {
      publicationCommitted =
        await store.confirmCommittedIndex(entry.ref) !== undefined;
    }
    journal.markPhysicalClose(entry.ref, publicationCommitted ? null :
      entry.abort.signal.aborted ? 'cancelled' : 'failed');
    entry.stopObservationPending = false;
    entry.stopObserved = true;
  }

  async function settleCleanup(entry) {
    const execution = entry.cleanupOwner;
    if (execution !== undefined) {
      if (typeof execution.close !== 'function' ||
          typeof execution.cleanup !== 'function' ||
          typeof execution.cleanupPending !== 'function') {
        throw new Error('ClientDispatchCleanupOwnerInvalid');
      }
      await execution.close();
      await execution.cleanup();
      if (execution.cleanupPending()) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.cleanupOwner = undefined;
      entry.stopObservationPending = true;
    }
    if (entry.sourceCapture !== undefined) {
      entry.sourceCapture.close();
      entry.sourceCapture = undefined;
    }
    if (entry.stopObservationPending) await observeStop(entry);
    if (entry.cleanupHandle !== undefined) {
      const handle = entry.cleanupHandle;
      const status = handle.status();
      if (status?.pending === true) await handle.retry();
      if (handle.status()?.pending !== false) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.cleanupHandle = undefined;
    }
    if (entry.unresolvedCleanup) {
      throw new Error('ClientDispatchCleanupOwnerMissing');
    }
    if (entry.failureObservationPending) {
      journal.markPreDispatchFailure(entry.ref);
      entry.failureObservationPending = false;
    }
    if (entry.physicalStarted && !entry.stopObserved &&
        entry.physicalWorkMayHaveStarted) {
      throw new Error('ClientDispatchStopUnknown');
    }
  }

  async function finishRun(entry) {
    if (!entry.finishPending) return;
    await entry.finished?.();
    entry.finishPending = false;
  }

  function releaseAcquisition(entry) {
    if (!entry.releasePending) return;
    checkpoints.releaseAcquisition(entry.requestId);
    entry.releasePending = false;
  }

  const start = (submission, requested, accepted, held, finished, gate) => {
    const {preparedProgram, principalId: actual, connection} = submission;
    const unstarted = accepted.dispatchReserved !== true ||
      accepted.physicalStartReserved === false &&
      !accepted.preDispatchFailureConfirmed;
    if (entries.has(keyOf(accepted.ref)) || !unstarted ||
        accepted.cancellationRequested) {
      return Promise.resolve('not_started');
    }
    // Held requests can start only from the Checkpoint's admitted resume.
    if (gate === undefined && checkpoints?.heldOrigin(submission.requestId)) {
      return Promise.resolve('not_started');
    }
    let reached;
    const physical = new Promise(resolve => { reached = resolve; });
    const entry = {ref: accepted.ref, requestId: submission.requestId,
      finished, promise: undefined,
      reserved: false, settled: false, abort: new AbortController(),
      physicalStarted: false, physicalStartClaimAttempted: false,
      failureObservationPending: false, stopObservationPending: false,
      stopObserved: false, physicalWorkMayHaveStarted: false,
      finishPending: false, releasePending: checkpoints !== undefined,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, sourceCapture: undefined};
    entries.set(keyOf(accepted.ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      const claim = await startRun({identity: requested, tenantId,
        principalId: actual, connection});
      if (claim.kind !== 'reserved' &&
          !(claim.kind === 'reconcile' &&
            accepted.dispatchReserved === true &&
            accepted.physicalStartReserved === false &&
            !accepted.preDispatchFailureConfirmed)) return;
      entry.reserved = true;
      await observed('dispatch_reserved', {ref: claim.ref});
      if (beforeDispatch !== undefined) await beforeDispatch(claim.ref);
      if (entry.abort.signal.aborted) return;
      if (held.plan === undefined) {
        held.plan = planFor(submission, accepted.runDefinition.wire);
      }
      const acquiring = sourceProfile !== undefined &&
        moon.clientProgramPrepareQueryAcquisition(preparedProgram, 0, 0)
          ?.$tag === 1;
      let setup;
      if (!acquiring) {
        setup = moon.clientProgramOpenSourceFreeLocalHost(
          preparedProgram, registry, values, 1n, 0n, 0n, 0n,
          fragment, ordered);
        if (setup === undefined) throw new Error('ClientProgramNeedsInputs');
      }
      // The resumed admission and physical start reservation are adjacent.
      if (gate !== undefined) {
        try { gate.beforePhysicalStart(); }
        catch (error) {
          reached({refused: error});
          return;
        }
      }
      entry.physicalStartClaimAttempted = true;
      if (!journal.reservePhysicalStart(requested, {
        tenantId, ref: accepted.ref,
        currentAuthorization: hostConnection({principalId: actual,
          connection, ref: accepted.ref}),
      }, moon, control)) return;
      entry.physicalStarted = true;
      entry.finishPending = true;
      gate?.started();
      reached('started');
      await observed('physical_start_reserved', {ref: accepted.ref});
      const sourceAccess = checkpoints?.acquisitionAccess(
        submission.requestId, sourceProfile?.sourceAccess) ??
        sourceProfile?.sourceAccess;
      if (acquiring) {
        if (held.preparedSourceAccess !== sourceAccess) {
          held.preparedSource = await prepareAcquisition(preparedProgram,
            sourceAccess);
          held.preparedSourceAccess = sourceAccess;
        }
        const captureStartedAt = now();
        await observed('acquisition_started', {ref: accepted.ref});
        entry.physicalWorkMayHaveStarted = true;
        entry.sourceCapture = await openCapturedDuckDBSource({moon,
          preparedProgram, registry, values, fragment, ordered,
          database: sourceProfile.database, schema: sourceProfile.schema,
          table: sourceProfile.table, sourceAccess,
          transportLimits: sourceProfile.transportLimits,
          signal: entry.abort.signal,
          preparedSource: held.preparedSource});
        const captureCompletedAt = now();
        await observed('acquisition_completed', {ref: accepted.ref});
        const sourceEvidenceWire =
          await entry.sourceCapture.issueSourceEvidence({
            authorityScopeCid,
            effectiveDataPolicyCid:
              entry.sourceCapture.checkedSource.sourceDataPolicyCid});
        held.plan = acquiredTaskPublicationPlan({moon, control,
          acquired: held.plan, preparedProgram,
          captured: entry.sourceCapture, sourceEvidenceWire,
          authorityScopeCid,
          effectiveDataPolicyCid:
            entry.sourceCapture.checkedSource.sourceDataPolicyCid,
          captureStartedAt, captureCompletedAt, tenantId,
          requestId: submission.requestId, storeAuthorityCid, now});
        setup = entry.sourceCapture.setup;
      }
      entry.abort.signal.throwIfAborted();
      entry.physicalWorkMayHaveStarted = true;
      const published = await runPublished(setup,
        {store, plan: held.plan},
        sourceProfile === undefined ? {} :
          {authorization: sourceAccess.authorization},
        entry.abort.signal);
      entry.cleanupOwner = published;
      entry.publicationCommitted = true;
      await observed('computed', {ref: accepted.ref});
      await settleCleanup(entry);
      await finishRun(entry);
    }).catch(async cause => {
      entry.primaryFailure = cause;
      const failedExecution = cause instanceof CapturedRunPublicationError
        ? cause.execution : undefined;
      if (cause?.cleanupPending === true) {
        if (typeof cause.cleanupHandle?.status === 'function' &&
            typeof cause.cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = cause.cleanupHandle;
        } else if (failedExecution === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      if (entry.reserved && !entry.physicalStartClaimAttempted &&
          !entry.abort.signal.aborted) {
        entry.failureObservationPending = true;
      }
      if (failedExecution !== undefined) entry.cleanupOwner = failedExecution;
      if (entry.physicalStarted && entry.cleanupOwner !== undefined) {
        entry.stopObservationPending = true;
      }
      try { await settleCleanup(entry); }
      catch (cleanupFailure) { entry.cleanupFailure = cleanupFailure; }
      try { await finishRun(entry); }
      catch (failure) { entry.finishFailure = failure; }
    }).finally(() => {
      entry.settled = true;
      reached('not_started');
      try { releaseAcquisition(entry); }
      catch (failure) { entry.releaseFailure = failure; }
      retire(entry);
    });
    return physical;
  };

  const drain = async () => {
    for (;;) {
      const running = [...entries.values()].filter(entry => !entry.settled);
      if (running.length === 0) break;
      await Promise.allSettled(running.map(entry => entry.promise));
    }
    for (const entry of [...entries.values()]) {
      try {
        await settleCleanup(entry);
        await finishRun(entry);
        releaseAcquisition(entry);
      }
      catch (failure) { entry.cleanupFailure = failure; }
      retire(entry);
    }
    if (entries.size > 0) {
      throw Object.assign(new Error('ClientDispatchCleanupPending'), {
        code: 'ClientDispatchCleanupPending',
        pendingRefs: [...entries.values()].map(entry => entry.ref),
        failures: [...entries.values()].map(entry => ({ref: entry.ref,
          primary: entry.primaryFailure,
          cleanup: entry.cleanupFailure,
          finish: entry.finishFailure,
          release: entry.releaseFailure})),
      });
    }
  };
  return Object.freeze({start, cancel, live, operation, drain});
}
