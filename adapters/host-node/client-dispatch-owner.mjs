// One installed Host owner for an admitted Run's physical dispatch, stop
// observation, and recoverable cleanup. The journal and MoonBit control keep
// their existing authority; this owner does not decide whether to retry.
import {CapturedRunPublicationError,
  runPublishedCapturedStrategy} from './entry.mjs';
import {acquiredTaskPublicationPlan, acquiredMultiTaskPublicationPlan} from './local-values-plan.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {checked} from '../host-common/runtime-result.mjs';

export function installNodeClientDispatchOwner({moon, control, journal,
  store, checkpoints, startRun, hostConnection, beforeDispatch, observed,
  prepareAcquisition, planFor, sourceProfile, registry, values, fragment,
  ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
  faultInjection, runInfer, computeConfigurations = {},
  retainedRelationOutput = false,
  runPublished = runPublishedCapturedStrategy}) {
  const entries = new Map();
  const diagnostic = diagnosticObserver(observed);
  const step = async (name, detail) => {
    diagnostic(name, detail);
    await faultInjection?.(name, detail);
  };
  const keyOf = ref => ref.runDefinitionCid;
  const current = ref => entries.get(keyOf(ref));
  const resourceUsage = ledger => {
    const usage = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    return Object.freeze(Object.fromEntries([
      'planningWork', 'attempts', 'holdings', 'transferredBytes',
      'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes',
      'reservedExecutionBytes', 'uncertainTransferBytes',
    ].map((name, index) => [name, usage[index].toString()])));
  };
  const cancel = ref => current(ref)?.abort.abort(
    new Error('ClientRunCancellationRequested'));
  const live = ref => current(ref)?.settled === false;
  const operation = ref => current(ref)?.promise;

  async function acquireSource(entry, preparedProgram, preparedSource, sourceAccess) {
    if (entry.sourceCapture !== undefined) {
      throw new TypeError('ClientSourceCaptureAlreadyRetained');
    }
    const installedSource = installedSourceFor(sourceProfile,
      preparedSource.checkedSource.sourceRef);
    const captureStartedAt = now();
    await step('acquisition_started', {ref: entry.ref,
      ...(preparedSource.selection === undefined ? {} :
        {selection: preparedSource.selection})});
    entry.physicalStarted = true;
    entry.physicalWorkMayHaveStarted = true;
    const acquisition = acquisitionEndHandoff();
    try {
      entry.sourceCapture = await installedSource.open({preparedProgram,
        registry, values, fragment, ordered, sourceAccess,
        signal: entry.abort.signal, preparedSource,
        retainedRelationOutput,
        reportAcquisitionFailure: acquisition.retain});
    } catch (error) {
      const ended = acquisition.outcome(error);
      if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
        entry.stopObservationPending = true;
      } else if (ended.recovery !== undefined) {
        entry.cleanupOwner = ended.recovery;
      } else {
        entry.unresolvedCleanup = true;
      }
      throw error;
    }
    const captureCompletedAt = now();
    await step('acquisition_completed', {ref: entry.ref,
      ...(entry.sourceCapture.acquisition === undefined ? {} :
        {acquisition: entry.sourceCapture.acquisition})});
    const sourceEvidenceWire = await entry.sourceCapture.issueSourceEvidence({
      authorityScopeCid,
      effectiveDataPolicyCid: entry.sourceCapture.checkedSource.sourceDataPolicyCid});
    return {captured: entry.sourceCapture, captureStartedAt, captureCompletedAt,
      sourceEvidenceWire};
  }

  function retire(entry) {
    if (entry.settled && entry.cleanupOwner === undefined &&
        entry.cleanupHandle === undefined && !entry.unresolvedCleanup &&
        entry.sourceCapture === undefined && entry.pendingSetup === undefined &&
        !entry.stopObservationPending &&
        !entry.failureObservationPending && !entry.finishPending &&
        !entry.releasePending &&
        (!entry.physicalStarted || entry.stopObserved ||
          !entry.physicalWorkMayHaveStarted)) {
      entries.delete(keyOf(entry.ref));
    }
  }

  async function observeStop(entry) {
    if (entry.observeStopped !== undefined) {
      // An Effect continuation may stop its in-process Compute while its Run
      // waits for approval. Only that common Run owner can publish the
      // observed outcome; absence of a public index does not imply failure.
      await entry.observeStopped(entry.terminalOutcome ?? null);
      entry.stopObservationPending = false;
      entry.stopObserved = true;
      return;
    }
    let publicationCommitted = entry.publicationCommitted === true;
    if (!publicationCommitted) {
      publicationCommitted =
        await store.confirmCommittedIndex(entry.ref) !== undefined;
    }
    const retainedWait = entry.modelCheckpointRetained &&
      !entry.abort.signal.aborted;
    journal.markPhysicalClose(entry.ref, publicationCommitted || retainedWait
      ? null : entry.abort.signal.aborted ? 'cancelled' : 'failed');
    entry.stopObservationPending = false;
    entry.stopObserved = true;
  }

  async function settleCleanupHandle(entry) {
    if (entry.cleanupHandle === undefined) return;
    const handle = entry.cleanupHandle;
    if (handle.status()?.pending === true) await handle.retry();
    if (handle.status()?.pending !== false) {
      throw new Error('ClientDispatchCleanupPending');
    }
    entry.cleanupHandle = undefined;
  }

  async function settleCleanup(entry) {
    const execution = entry.cleanupOwner;
    if (entry.multiSources && entry.sourceCapture !== undefined) {
      // Stop Compute before closing any borrowed native input. The same
      // NativePhysical issuer must confirm close before the DAG can release
      // its transferred holding. A failed close retains these exact owners.
      if (execution !== undefined) {
        try { await execution.close(); } catch (failure) { entry.closeFailure ??= failure; }
      }
      if (entry.pendingSetup !== undefined) moon.strategyHostStop(entry.pendingSetup);
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      if (!entry.computeStartAttempted && !entry.unresolvedCleanup) entry.stopObservationPending = true;
    }
    if (entry.pendingSetup !== undefined) {
      moon.strategyHostStop(entry.pendingSetup);
      moon.strategyHostCloseOutputs(entry.pendingSetup);
      if (moon.strategyHostUsage(entry.pendingSetup).slice(4).some(value => value !== 0n)) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.pendingSetup = undefined;
    }
    if (execution !== undefined) {
      if (typeof execution.close !== 'function' ||
          typeof execution.cleanup !== 'function' ||
          typeof execution.cleanupPending !== 'function') {
        throw new Error('ClientDispatchCleanupOwnerInvalid');
      }
      // close may permanently retain its first rejected Promise. Recovery is
      // owned by cleanup, not by invoking close again or repeating Compute.
      try { await execution.close(); }
      catch (failure) { entry.closeFailure ??= failure; }
      // A failed Store consumer can still pin the completed output. Ask the
      // retained Store owner to settle before retrying the execution's
      // reclamation; cancellation alone still grants neither release.
      await settleCleanupHandle(entry);
      const recovered = await execution.cleanup();
      if (recovered === false || execution.cleanupPending() !== false) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.cleanupOwner = undefined;
      entry.stopObservationPending = true;
    }
    if (entry.sourceCapture !== undefined) {
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      // Acquisition returned successfully, but evidence/plan preparation can
      // fail before Compute has an owner. Closing that exact capture confirms
      // this physical end; it does not confirm an unowned Compute attempt.
      if (!entry.computeStartAttempted) entry.stopObservationPending = true;
    }
    if (entry.stopObservationPending) await observeStop(entry);
    await settleCleanupHandle(entry);
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
    if (entry.acquisitionLedger !== undefined) {
      diagnostic('dispatch_cleanup_completed', {ref: entry.ref,
        resourceUsage: resourceUsage(entry.acquisitionLedger)});
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
      computeStartAttempted: false,
      failureObservationPending: false, stopObservationPending: false,
      stopObserved: false, physicalWorkMayHaveStarted: false,
      finishPending: false, releasePending: checkpoints !== undefined,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, sourceCapture: undefined};
    entries.set(keyOf(accepted.ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      const claim = await startRun({identity: requested, namespaceId,
        principalId: actual, connection});
      if (claim.kind !== 'reserved' &&
          !(claim.kind === 'reconcile' &&
            accepted.dispatchReserved === true &&
            accepted.physicalStartReserved === false &&
            !accepted.preDispatchFailureConfirmed)) return;
      entry.reserved = true;
      await step('dispatch_reserved', {ref: claim.ref});
      if (beforeDispatch !== undefined) await beforeDispatch(claim.ref);
      if (entry.abort.signal.aborted) return;
      if (held.plan === undefined) {
        held.plan = planFor(submission, accepted.runDefinition.wire);
      }
      const acquiring = sourceProfile !== undefined &&
        moon.clientProgramAcquisitionCount(preparedProgram) > 0;
      const inferring = held.plan.kind === 'infer';
      // A checked model barrier is not a Values task. The installed Model
      // connection must consume this exact plan and transfer physical custody
      // before advancing; this supervisor still owns the one Run-start claim.
      if (inferring && typeof runInfer !== 'function') {
        throw new Error('InstalledInferDispatchUnavailable');
      }
      const multiple = held.preparedSources?.length === 2;
      if (inferring && multiple) {
        throw new Error('InstalledInferMultiSourceUnsupported');
      }
      const installedSource = acquiring && !multiple
        ? installedSourceFor(sourceProfile, held.preparedSource.checkedSource.sourceRef) : undefined;
      if (retainedRelationOutput && !inferring && installedSource !== undefined &&
          installedSource.supportsRetainedRelationOutput !== true) {
        throw new TypeError('InstalledSourceRetainedOutputUnsupported');
      }
      let ledger;
      const selectedSources = [];
      if (multiple) {
        // Read approvals retain their occurrence and physical target. Resolve
        // resumed access before selecting configurations and sizing the one
        // ledger; the exact preparations below also own the subsequent reads.
        for (const source of held.preparedSources) {
          entry.abort.signal.throwIfAborted();
          const occurrence = {...source.occurrence,
            checkedSource: source.prepared.checkedSource,
            readTuple: source.prepared.readTuple, physicalBinding: source.prepared.physicalBinding};
          const access = checkpoints?.acquisitionAccess(submission.requestId,
            source.sourceAccess, occurrence) ?? source.sourceAccess;
          const preparedSource = access === source.sourceAccess ? source.prepared :
            await prepareAcquisition(preparedProgram, access, source.occurrence);
          selectedSources.push({...source, access, preparedSource});
        }
        const capacities = selectedSources.map(source => {
          if (retainedRelationOutput &&
              source.adapter.supportsRetainedRelationOutput !== true) {
            throw new TypeError('InstalledSourceRetainedOutputUnsupported');
          }
          if (typeof source.adapter.ledgerCapacity !== 'function') {
            throw new TypeError('InstalledMultiSourceCapacityUnavailable');
          }
          return source.adapter.ledgerCapacity(source.preparedSource);
        });
        ledger = moon.clientProgramPrepareMultiCapturedLocalInstalledLedger(preparedProgram,
          capacities.map(value => value.capacity),
          capacities.map(value => value.transferBytes),
          capacities.map(value => value.executionBytes),
          registry, values, fragment, ordered);
        if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
      }
      let setup;
      let acquiredInfer;
      if (!acquiring && !inferring) {
        const open = retainedRelationOutput
          ? moon.clientProgramOpenSourceFreeLocalRetainedHost
          : moon.clientProgramOpenSourceFreeLocalHost;
        setup = open(
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
        namespaceId, ref: accepted.ref,
        currentAuthorization: hostConnection({principalId: actual,
          connection, ref: accepted.ref}),
      }, moon, control)) return;
      entry.physicalStarted = true;
      entry.finishPending = true;
      gate?.started();
      reached('started');
      await step('physical_start_reserved', {ref: accepted.ref});
      const sourceAccess = checkpoints?.acquisitionAccess(
        submission.requestId, installedSource?.sourceAccess) ??
        installedSource?.sourceAccess;
      if (multiple) {
        entry.multiSources = true;
        const captures = [];
        const closed = new Set();
        entry.sourceCapture = Object.freeze({async close() {
          const failures = [];
          for (const capture of captures) {
            if (closed.has(capture)) continue;
            try {
              await step('acquisition_cleanup_started', {ref: accepted.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
              await capture.close();
              closed.add(capture);
              diagnostic('acquisition_cleanup_completed', {ref: accepted.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
            }
            catch (error) { failures.push(error); }
          }
          if (failures.length) throw new AggregateError(failures, 'ClientSourceCleanupPending');
        }});
        const captureStartedAt = now();
        const sources = [];
        for (const source of selectedSources) {
          entry.abort.signal.throwIfAborted();
          const {access, preparedSource} = source;
          await step('acquisition_started', {ref: accepted.ref, task: source.occurrence.task,
            selection: preparedSource.selection,
            resourceUsage: resourceUsage(ledger)});
          entry.physicalWorkMayHaveStarted = true;
          const acquisition = acquisitionEndHandoff();
          let captured;
          try {
            captured = await source.adapter.open({preparedProgram, registry, values,
              fragment, ordered, sourceAccess: access, signal: entry.abort.signal,
              preparedSource, occurrence: source.occurrence, ledger,
              reportAcquisitionFailure: acquisition.retain});
          } catch (error) {
            const ended = acquisition.outcome(error);
            if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
              entry.stopObservationPending = true;
            } else if (ended.recovery !== undefined) {
              entry.cleanupOwner = ended.recovery;
            } else {
              // Earlier captures settling proves nothing about an unknown
              // current acquisition that handed back no physical owner.
              entry.unresolvedCleanup = true;
            }
            throw error;
          }
          captures.push(captured);
          await step('acquisition_completed', {ref: accepted.ref, task: source.occurrence.task,
            acquisition: captured.acquisition,
            resourceUsage: resourceUsage(ledger)});
          const sourceEvidenceWire = await captured.issueSourceEvidence({authorityScopeCid,
            effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid});
          sources.push({captured, sourceEvidenceWire});
        }
        const captureCompletedAt = now();
        const effectiveDataPolicyCid = moon.clientProgramPublicationDataPolicyCid(preparedProgram);
        if (effectiveDataPolicyCid === undefined) throw new Error('InstalledMultiSourcePolicyUnavailable');
        held.plan = acquiredMultiTaskPublicationPlan({moon, control, acquired: held.plan,
          preparedProgram, sources, authorityScopeCid, effectiveDataPolicyCid,
          captureStartedAt, captureCompletedAt, namespaceId, storeAuthorityCid, now});
        const open = retainedRelationOutput
          ? moon.clientProgramOpenMultiCapturedLocalRetainedHost
          : moon.clientProgramOpenMultiCapturedLocalHost;
        setup = open(preparedProgram,
          captures.map(value => value.capture.source()), ledger, registry, values, fragment, ordered);
        if (setup === undefined) throw new Error('InstalledMultiSourceHostUnavailable');
        entry.pendingSetup = setup;
        const dag = moon.strategyHostRun(setup);
        for (const [task, captured] of captures.entries()) captured.capture.retainTask(dag, task);
      } else if (acquiring) {
        if (held.preparedSourceAccess !== sourceAccess) {
          held.preparedSource = await prepareAcquisition(preparedProgram,
            sourceAccess);
          held.preparedSourceAccess = sourceAccess;
        }
        const {captureStartedAt, captureCompletedAt, sourceEvidenceWire} =
          await acquireSource(entry, preparedProgram, held.preparedSource, sourceAccess);
        if (inferring) {
          const captured = entry.sourceCapture;
          const input = checked(moon.clientProgramAdmitInferCapturedInput(
            preparedProgram, captured.inferStep, captured.capturedSource,
            captured.identity, captured.requirement, captured.logicalInput,
            sourceEvidenceWire, authorityScopeCid,
            captured.checkedSource.sourceDataPolicyCid,
            captureStartedAt, captureCompletedAt));
          acquiredInfer = {input, sourceEvidence: control.admitRunEvidence(
            'source_evidence', sourceEvidenceWire,
            {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})};
        } else {
          held.plan = acquiredTaskPublicationPlan({moon, control,
          acquired: held.plan, preparedProgram,
          captured: entry.sourceCapture, sourceEvidenceWire,
          authorityScopeCid,
          effectiveDataPolicyCid:
            entry.sourceCapture.checkedSource.sourceDataPolicyCid,
          captureStartedAt, captureCompletedAt, namespaceId,
          requestId: submission.requestId, storeAuthorityCid, now});
        }
        setup = entry.sourceCapture.setup;
      }
      entry.abort.signal.throwIfAborted();
      entry.physicalWorkMayHaveStarted = true;
      entry.computeStartAttempted = true;
      if (inferring) {
        const inferResult = await runInfer({preparedProgram, plan: held.plan, store,
          acquiredInfer,
          principalId: actual, signal: entry.abort.signal,
          retainExecution(execution) {
            if (entry.cleanupOwner !== undefined &&
                entry.cleanupOwner !== execution) {
              throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
            }
            if (typeof execution?.close !== 'function' ||
                typeof execution?.cleanup !== 'function' ||
                typeof execution?.cleanupPending !== 'function') {
              throw new TypeError('ClientDispatchCleanupOwnerInvalid');
            }
            entry.cleanupOwner = execution;
          }});
        if (inferResult?.status === 'waiting_checkpoint') {
          // A returned Waiting is not a completed Model or a terminal Run.
          // Accept only the exact durable Model Checkpoint in the existing
          // continuation journal. Its owner keeps the input custody needed
          // for resume; this supervisor still settles physical preparation.
          const continuation = checkpoints?.effectRunState(
            control.runDefinitionRunId(held.plan.runDefinition),
            entry.ref.runDefinitionCid);
          const checkpoint = continuation?.runState?.checkpoint;
          if (entry.cleanupOwner === undefined ||
              continuation?.status !== 'waiting_checkpoint' ||
              checkpoint?.kind !== 'model_invocation' ||
              checkpoint.checkpoint_cid !== inferResult.checkpointCid) {
            throw new Error('InstalledInferCheckpointNotRetained');
          }
          entry.modelCheckpointRetained = true;
          await settleCleanup(entry);
          await finishRun(entry);
          return;
        }
        // Success is the existing Store's committed index, not merely a
        // returned model value or a completed private capture.
        if (entry.cleanupOwner === undefined ||
            await store.confirmCommittedIndex(entry.ref) === undefined) {
          throw new Error('InstalledInferPublicationIncomplete');
        }
        entry.publicationCommitted = true;
        await step('computed', {ref: accepted.ref});
        await settleCleanup(entry);
        await finishRun(entry);
        return;
      }
      const published = await runPublished(setup,
        {store, plan: held.plan},
        { ...computeConfigurations,
          ...(sourceAccess === undefined ? {} :
            {authorization: sourceAccess.authorization}) },
        entry.abort.signal, undefined, execution => {
          entry.cleanupOwner = execution;
          entry.pendingSetup = undefined;
        });
      entry.cleanupOwner = published;
      entry.publicationCommitted = true;
      await step('computed', {ref: accepted.ref,
        outputRepresentations: (published.execution?.completed ?? [])
          .map(task => ({task:task.task,
            representation:task.outputRepresentation})),
        carrierSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.snapshot !== undefined)
          .map(task => ({task:task.task,...task.snapshot})),
        relationSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.relationSnapshot !== undefined)
          .map(task => ({task:task.task,...task.relationSnapshot}))});
      await settleCleanup(entry);
      await finishRun(entry);
    }).catch(async cause => {
      diagnostic('dispatch_failed', {ref: accepted.ref,
        code: cause?.code ?? cause?.message ?? 'ClientDispatchFailed'});
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

  // The installed Effect Run owner supplies the already-admitted operation.
  // This is the same physical supervisor as ordinary dispatch, not another
  // Run-start or Effect retry engine. It never invokes run again during drain.
  // The callback must transfer cleanup custody before any fallible operation
  // that can retain resources. Its common Run observer records the stop
  // independently from waiting, failed, unknown or published outcome.
  const track = (ref, {run, observeStopped,
    barrierFailureOutcome = null}) => {
    if (typeof ref?.runDefinitionCid !== 'string' ||
        typeof run !== 'function' || typeof observeStopped !== 'function') {
      throw new TypeError('InvalidClientOwnedDispatch');
    }
    const existing = current(ref);
    if (existing !== undefined) return existing.promise;
    const entry = {ref: Object.freeze({...ref}), settled: false,
      abort: new AbortController(), observeStopped,
      // The original Run-start claim does not prove that this continuation
      // began physical work. The installed Site marks that boundary itself.
      physicalStarted: false, physicalWorkMayHaveStarted: false,
      stopObserved: false, stopObservationPending: false,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, runInvoked: false};
    entries.set(keyOf(ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      if (beforeDispatch !== undefined) await beforeDispatch(ref);
      entry.abort.signal.throwIfAborted();
      entry.runInvoked = true;
      return run(Object.freeze({
      signal: entry.abort.signal,
      acquireSource({preparedProgram, preparedSource, sourceAccess}) {
        return acquireSource(entry, preparedProgram, preparedSource, sourceAccess);
      },
      beginPhysicalWork() {
        entry.physicalStarted = true;
        entry.physicalWorkMayHaveStarted = true;
      },
      observePreEffectFailure() {
        // Only the installed opening boundary can assert this: acquisition
        // or Compute failed before the Effect adapter was invoked. This is
        // an outcome observation, not a physical stop or cleanup exemption.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : 'failed';
      },
      retainExecution(execution) {
        if (entry.cleanupOwner !== undefined &&
            entry.cleanupOwner !== execution) {
          throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
        }
        if (typeof execution?.close !== 'function' ||
            typeof execution?.cleanup !== 'function' ||
            typeof execution?.cleanupPending !== 'function') {
          throw new TypeError('ClientDispatchCleanupOwnerInvalid');
        }
        entry.cleanupOwner = execution;
      },
      }));
    }).then(async result => {
      // A trusted installed Site may confirm that a pre-Preview refusal
      // performed no external Effect dispatch. Record that observation only
      // after its physical owner has stopped and cleanup has completed.
      if (result?.status === 'failed_without_effect_dispatch' ||
          result?.status === 'failed_effect_set') {
        entry.terminalOutcome = 'failed';
      }
      await settleCleanup(entry);
      return result;
    }).catch(async cause => {
      entry.primaryFailure = cause;
      if (!entry.runInvoked) {
        // A refused execution barrier ran no Site callback. This is a
        // positive no-start observation, not an inferred physical stop.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : barrierFailureOutcome;
        entry.stopObservationPending = true;
      }
      if (cause?.cleanupPending === true) {
        if (typeof cause.cleanupHandle?.status === 'function' &&
            typeof cause.cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = cause.cleanupHandle;
        } else if (entry.cleanupOwner === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      try { await settleCleanup(entry); }
      catch (failure) { entry.cleanupFailure = failure; }
      throw cause;
    }).finally(() => {
      entry.settled = true;
      retire(entry);
    });
    // submit returns its durable RunRef before the owned operation settles.
    // Observation remains available through operation(), without an unhandled
    // rejection when a Client disconnects or never calls wait().
    entry.promise.catch(() => {});
    return entry.promise;
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
          close: entry.closeFailure,
          cleanup: entry.cleanupFailure,
          finish: entry.finishFailure,
          release: entry.releaseFailure})),
      });
    }
  };
  return Object.freeze({start, track, cancel, live, operation, drain});
}
