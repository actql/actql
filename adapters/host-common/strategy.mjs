// Trusted JavaScript coordination only. Checked readiness, selected ownership,
// reservations and atomic completion are enforced by the common MoonBit core.
// Installed entries are implementation code, not user-supplied success proofs.
import {bindExecutionSiteCandidate, classifyManagedExecutionSiteFallback,
  beginFailedExecutionSiteOperation,
  beginExecutionSiteHostCleanup,
  beginExecutionSiteHostTaskSuccess,
  beginRetainedExecutionSiteClose,
  beginRetainedExecutionSiteHolding,
  executionSiteCandidate,
  executionSiteDescription, executionSiteHostCleanupAction,
  executionSiteHostCleanupPending, executionSiteHostTaskRunOutcome,
  executionSiteHostTaskSuccessAction,
  executionSiteHostTaskSiteOperationSettled,
  executionSiteOperationAvailable,
  executionSitePlacements, failedExecutionSiteOperationAction,
  installExecutionSites,
  prepareSingleExecutionSitePolicy, releaseExecutionSiteHolding,
  recordExecutionSiteHostCleanupClosesAwaited,
  recordExecutionSiteHostCleanupRetry,
  recordExecutionSiteHostTaskCommonCompletion,
  recordExecutionSiteHostTaskManagedBinding,
  recordExecutionSiteHostTaskOutputRetained,
  recordExecutionSiteHostTaskSiteCompletion,
  recordExecutionSiteHostTaskSiteOperationSettled,
  recordFailedExecutionSiteOperationSettlement,
  recordFailedExecutionSiteOperationStop,
  recordRetainedExecutionSiteCleanupAuthority,
  recordRetainedExecutionSiteCleanupStopped,
  recordRetainedExecutionSiteCloseFailed,
  recordRetainedExecutionSiteCloseStarted,
  recordRetainedExecutionSiteCloseSucceeded,
  recordRetainedExecutionSiteHoldingReleased,
  retainedExecutionSiteCloseAction,
  retainedExecutionSiteHoldingAction,
  retainExecutionSiteOperationHolding, settleExecutionSiteOperation,
  selectExecutionSiteCandidateIndex, startExecutionSiteOperation} from
  './execution-sites.mjs';
import {createManagedSiteTransferCoordinator} from
  './managed-site-transfer.mjs';
import {storeCompletedResultPublicationPayload} from
  './durable-result-payload.mjs';
import {publishCompletedEffectFreeRun} from
  './completed-run-publication.mjs';
import {prepareCompletedEffectFreeRunPublication} from
  './run-publication-preflight.mjs';
import {ExecutionAuthorizationError, missingAuthorizationGate} from
  './authorization-gate.mjs';

export class StrategyHostError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const active = new WeakSet();
const publicationContract = value => value !== null &&
  typeof value === 'object' && typeof value.name === 'string' &&
  typeof value.identity === 'string' && typeof value.wire === 'string';
const failureMember = (value, name) => {
  try {
    return value !== null &&
      (typeof value === 'object' || typeof value === 'function')
      ? value[name] : undefined;
  } catch { return undefined; }
};

function ownedStrategyFailure(reason, fallbackCode) {
  const code = typeof failureMember(reason, 'code') === 'string'
    ? failureMember(reason, 'code') : fallbackCode;
  const failure = new StrategyHostError(code);
  failure.cause = reason;
  failure.primaryFailure = reason;
  const errors = failureMember(reason, 'cleanupErrors');
  failure.cleanupErrors = Object.freeze(
    Array.isArray(errors) ? [...errors] : [],
  );
  return failure;
}

// A Site holding describes the lifetime of the concrete retained result, not
// merely the JavaScript wrapper returned by a contribution. This adapter
// deliberately preserves the contribution's synchronous/asynchronous close
// behavior and original thrown value. Its separate cleanup observer releases
// the Site holding only after an explicit underlying recovery handle confirms
// physical reclamation.
function retainSiteResult(operation, result, retainedBytes) {
  const closeProgress = beginRetainedExecutionSiteClose(operation);
  const holdingProgress = beginRetainedExecutionSiteHolding(
    closeProgress,
    operation,
  );
  const holding = retainExecutionSiteOperationHolding(
    operation, result?.material ?? result, retainedBytes,
  );
  let closeResult;
  let closeFailure;
  let cleanupTracked = false;
  const release = () => {
    releaseExecutionSiteHolding(holding);
    recordRetainedExecutionSiteHoldingReleased(holdingProgress);
  };
  const progress = () => {
    let action = retainedExecutionSiteHoldingAction(holdingProgress);
    if (action === 3) {
      release();
      action = retainedExecutionSiteHoldingAction(holdingProgress);
    }
    if (action === 5) {
      throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
    }
    return action;
  };
  return Object.freeze({
    status: () => Object.freeze({released: progress() === 4}),
    close() {
      const action = progress();
      if (action === 4 || action === 1 || action === 2) return closeResult;
      if (action !== 0) {
        throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
      }
      recordRetainedExecutionSiteCloseStarted(closeProgress);
      try {
        closeResult = typeof result?.close === 'function'
          ? result.close() : undefined;
      }
      catch (reason) {
        closeFailure = reason;
        recordRetainedExecutionSiteCloseFailed(closeProgress);
        progress();
        throw reason;
      }
      if (closeResult != null && typeof closeResult.then === 'function') {
        closeResult = Promise.resolve(closeResult).then(
          value => {
            recordRetainedExecutionSiteCloseSucceeded(closeProgress);
            progress();
            return value;
          },
          reason => {
            closeFailure = reason;
            recordRetainedExecutionSiteCloseFailed(closeProgress);
            progress();
            throw reason;
          },
        );
      } else {
        recordRetainedExecutionSiteCloseSucceeded(closeProgress);
        progress();
      }
      return closeResult;
    },
    afterFailure(reason, remember) {
      if (cleanupTracked || progress() === 4 || reason !== closeFailure) return;
      const upstream = failureMember(reason, 'cleanupHandle');
      if (failureMember(reason, 'cleanupPending') !== true ||
          !upstream || typeof failureMember(upstream, 'status') !== 'function') {
        return;
      }
      recordRetainedExecutionSiteCleanupAuthority(closeProgress);
      cleanupTracked = true;
      const state = () => {
        try {
          const value = upstream.status();
          if (value?.pending === false) {
            recordRetainedExecutionSiteCleanupStopped(closeProgress);
          }
          return Object.freeze({
            pending: progress() !== 4,
            errors: Object.freeze(Array.isArray(value?.errors)
              ? [...value.errors] : []),
          });
        } catch (error) {
          return Object.freeze({pending: true, errors: Object.freeze([error])});
        }
      };
      const cleanupHandle = Object.freeze({
        status: state,
        async retry() { return state(); },
      });
      remember(Object.assign(new Error('ExecutionSiteCleanupPending'), {
        cleanupPending: true,
        cleanupHandle,
      }), cleanupHandle);
    },
  });
}

// Core-owned synchronous outputs have no connector close callback. Keep their
// Site holdings through the exact common output lifetime and release them only
// after the Core close succeeds or its explicit cleanup handle confirms it.
function coreOutputSiteOwner(core, setup, siteInstallation) {
  const retained = new Map();
  const closeProgress = beginRetainedExecutionSiteClose(siteInstallation);
  let closeFailure;
  let cleanupTracked = false;
  const progress = () => {
    for (const [holding, holdingProgress] of retained) {
      const action = retainedExecutionSiteHoldingAction(holdingProgress);
      if (action === 3) {
        releaseExecutionSiteHolding(holding);
        recordRetainedExecutionSiteHoldingReleased(holdingProgress);
        retained.delete(holding);
      }
      if (action === 5) {
        throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
      }
    }
  };
  return Object.freeze({
    retain(operation, value, retainedBytes) {
      const holding = retainExecutionSiteOperationHolding(
        operation, value, retainedBytes,
      );
      try {
        retained.set(holding, beginRetainedExecutionSiteHolding(
          closeProgress,
          operation,
        ));
      } catch (error) {
        releaseExecutionSiteHolding(holding);
        throw error;
      }
    },
    close() {
      const action = retainedExecutionSiteCloseAction(closeProgress);
      if (action === 1 || action === 2 || action === 3) return;
      if (action !== 0) {
        throw new StrategyHostError('InvalidExecutionSiteHoldingProgress');
      }
      progress();
      recordRetainedExecutionSiteCloseStarted(closeProgress);
      try { core.closeOutputs(setup); }
      catch (reason) {
        closeFailure = reason;
        recordRetainedExecutionSiteCloseFailed(closeProgress);
        progress();
        throw reason;
      }
      recordRetainedExecutionSiteCloseSucceeded(closeProgress);
      progress();
    },
    afterFailure(reason, remember) {
      if (cleanupTracked || retained.size === 0 || reason !== closeFailure) return;
      const upstream = failureMember(reason, 'cleanupHandle');
      if (failureMember(reason, 'cleanupPending') !== true ||
          !upstream || typeof failureMember(upstream, 'status') !== 'function') {
        return;
      }
      recordRetainedExecutionSiteCleanupAuthority(closeProgress);
      cleanupTracked = true;
      const state = () => {
        try {
          const value = upstream.status();
          if (value?.pending === false) {
            recordRetainedExecutionSiteCleanupStopped(closeProgress);
          }
          progress();
          return Object.freeze({
            pending: retained.size !== 0,
            errors: Object.freeze(Array.isArray(value?.errors)
              ? [...value.errors] : []),
          });
        } catch (error) {
          return Object.freeze({pending: true, errors: Object.freeze([error])});
        }
      };
      const cleanupHandle = Object.freeze({
        status: state,
        async retry() {
          if (state().pending && typeof failureMember(upstream, 'retry') ===
              'function') {
            await upstream.retry();
          }
          return state();
        },
      });
      remember(Object.assign(new Error('ExecutionSiteCleanupPending'), {
        cleanupPending: true,
        cleanupHandle,
      }), cleanupHandle);
    },
  });
}

export async function runInstalledStrategy(
  setup,
  core,
  contributions,
  signal,
  observeCompletion,
  sitePolicy,
  beforeCompute,
  authorization = missingAuthorizationGate(),
) {
  if (observeCompletion !== undefined && typeof observeCompletion !== 'function') {
    throw new StrategyHostError('InvalidCompletionObserver');
  }
  if (authorization === null || typeof authorization !== 'object' ||
      typeof authorization.authorize !== 'function' ||
      typeof authorization.cover !== 'function' ||
      typeof authorization.isProtectedSite !== 'function') {
    throw new StrategyHostError('InvalidAuthorizationGate');
  }
  if (active.has(setup)) throw new StrategyHostError('StrategyAlreadyRunning');
  core = Object.freeze({ ...core });
  // Seal the per-task activation requirement before any implementation can
  // start a task. Every start below consumes an exact grant for its task.
  core.requireActivation?.(setup);
  if (beforeCompute !== undefined && typeof beforeCompute !== 'function') {
    throw new StrategyHostError('InvalidBeforeComputeAdmission');
  }
  const programDefinitionCid = core.programDefinitionCid?.(setup);
  const resultInventory = core.resultInventory?.(setup) ?? [];
  if (!Array.isArray(resultInventory) ||
      (resultInventory.length > 0 && programDefinitionCid === undefined)) {
    throw new StrategyHostError('InvalidCheckedResultInventory');
  }
  const checkedResultInventory = Object.freeze(resultInventory.map(result =>
    Object.freeze({name: result.name, task: result.task})));
  const publicationInventory = checkedResultInventory.length === 0
    ? undefined
    : Object.freeze({
      programDefinitionCid,
      occurrences: Object.freeze(resultInventory.map(result =>
        Object.freeze({
          name: result.name,
          task: result.task,
          definition: result.definition,
          definitionContract: result.definitionContract,
        }))),
      requestInventory: Object.freeze(resultInventory.map(result =>
        Object.freeze({
          result_name: result.name,
          result_definition_cid: result.definition.result_definition_cid,
        }))),
    });
  active.add(setup);
  let preflight;
  try {
    if (beforeCompute !== undefined) {
      signal?.throwIfAborted();
      preflight = await beforeCompute(Object.freeze({
        programDefinitionCid,
        resultInventory: checkedResultInventory,
        publicationInventory,
        publicationControl: core.publicationControl,
      }));
      signal?.throwIfAborted();
    }
  } catch (primary) {
    let stopFailed = false;
    let stopFailure;
    try { core.stop(setup); }
    catch (error) {
      stopFailed = true;
      stopFailure = error;
    }
    active.delete(setup);
    if (!stopFailed) throw primary;
    const failure = ownedStrategyFailure(
      primary,
      'PublicationPreflightFailed',
    );
    failure.cleanupPending = true;
    failure.cleanupErrors = Object.freeze([
      ...failure.cleanupErrors,
      stopFailure,
    ]);
    const cleanupHandle = failureMember(stopFailure, 'cleanupHandle');
    if (cleanupHandle !== undefined) failure.cleanupHandle = cleanupHandle;
    throw failure;
  }
  // Snapshot the implementation set before invoking any implementation. Opaque
  // registration object identity, never a display name, selects the driver.
  const installed = new Map();
  for (const entry of contributions) {
    if (entry.registration == null || installed.has(entry.registration) ||
        typeof entry.run !== 'function') {
      throw new StrategyHostError('InvalidStrategyInstallation');
    }
    installed.set(entry.registration, Object.freeze({
      registration: entry.registration,
      run: entry.run,
      prepareNext: entry.prepareNext,
      runPrepared: entry.runPrepared,
      managedSelectionKey: entry.managedSelectionKey,
      beforeNext: entry.beforeNext,
      finish: entry.finish,
    }));
  }
  const siteInstallation = installExecutionSites(
    sitePolicy ?? prepareSingleExecutionSitePolicy(),
    [...installed.values()],
    core.siteControl,
  );
  const transfers = createManagedSiteTransferCoordinator(
    setup, core, siteInstallation, {
      authorization,
      subjectCid: programDefinitionCid,
    },
  );
  // Every activation is proven inside the admitted envelope by a cheap local
  // check: an unprotected in-process Site running pure compute over captured
  // inputs is covered without evaluation; a Host-declared protected Site needs
  // an evaluated dispatch decision for its exact scope (reused per Run, never
  // widened). No per-row callback, bulk pass or extra hashing.
  const authorizeActivation = async (site, entry, index) => {
    const siteKey = executionSiteDescription(site).key;
    const scope = Object.freeze({
      connection: siteKey,
      resource: entry.managedSelectionKey ?? 'installed-strategy',
      operation: 'write',
    });
    if (!authorization.isProtectedSite(siteKey)) {
      authorization.cover('activation', scope);
      if (typeof core.coverActivation === 'function' &&
          core.coverActivation(setup, index) !== true) {
        throw new StrategyHostError('ActivationGrantRejected');
      }
      return;
    }
    const decision = await authorization.authorize('activation', scope, {
      subjectCid: programDefinitionCid,
      signal,
    });
    if (decision.action !== 'dispatch') {
      throw new ExecutionAuthorizationError(decision);
    }
    signal?.throwIfAborted();
    if (typeof core.requireActivation === 'function' &&
        (typeof core.authorizeActivation !== 'function' ||
          core.authorizeActivation(setup, index, decision.runtimeDecision) !==
            true)) {
      throw new StrategyHostError('ActivationGrantRejected');
    }
  };
  const coreSiteOutputs = coreOutputSiteOwner(core, setup, siteInstallation);
  // A contribution that explicitly reports unconfirmed cleanup without a
  // usable status authority cannot release its Site operation. There is no
  // safe retry to invent, but the reservation and teardown responsibility
  // must remain visible.
  const unconfirmedSiteOperations = new Set();
  const settleSiteAfterFailure = (
    operation,
    error,
    alreadySettled = false,
  ) => {
    const cleanupRequired = failureMember(error, 'cleanupPending') === true;
    const upstream = failureMember(error, 'cleanupHandle');
    const failureProgress = beginFailedExecutionSiteOperation(
      operation,
      cleanupRequired,
      alreadySettled,
    );
    const drive = cleanupStopped => {
      if (cleanupRequired && cleanupStopped) {
        recordFailedExecutionSiteOperationStop(operation, failureProgress);
      }
      const action = failedExecutionSiteOperationAction(
        operation,
        failureProgress,
      );
      if (action === 1) {
        settleExecutionSiteOperation(operation);
        recordFailedExecutionSiteOperationSettlement(
          operation,
          failureProgress,
        );
        return failedExecutionSiteOperationAction(
          operation,
          failureProgress,
        );
      }
      return action;
    };
    if (!cleanupRequired) {
      drive(true);
      return error;
    }
    const failure = ownedStrategyFailure(error, 'StrategyExecutionFailed');
    if (typeof failureMember(upstream, 'status') !== 'function') {
      drive(false);
      unconfirmedSiteOperations.add(operation);
      failure.cleanupPending = true;
      return failure;
    }
    const combined = Object.freeze({
      status() {
        let state;
        try { state = upstream.status(); }
        catch (failure) {
          return Object.freeze({pending: true, errors: Object.freeze([failure])});
        }
        const errors = Array.isArray(state?.errors) ? [...state.errors] : [];
        let action;
        try { action = drive(state?.pending === false); }
        catch (error) {
          errors.push(error);
          action = 0;
        }
        return Object.freeze({
          pending: action !== 2,
          errors: Object.freeze(errors),
        });
      },
      async retry() {
        if (upstream.status()?.pending !== false &&
            typeof upstream.retry === 'function') await upstream.retry();
        return combined.status();
      },
    });
    failure.cleanupHandle = combined;
    failure.cleanupPending = combined.status().pending;
    return failure;
  };
  const completed = [];
  const candidateExclusions = [];
  const candidateComparisons = [];
  const outputs = [];
  const managedOutputs = new Map();
  const pendingCleanup = new Set();
  const pendingCloses = new Set();
  // A release without a recovery handle has no safe implicit retry contract.
  // Retain its owner and report unknown cleanup rather than forgetting it.
  const unconfirmedRelease = new Set();
  let cleanupInFlight;
  let failed = false;
  let failure;
  let closed = false;
  let closeResult;
  const rememberCleanup = (error, releaseOwner) => {
    const handle = error?.cleanupHandle;
    if (handle && typeof handle.status === 'function' && typeof handle.retry === 'function') {
      pendingCleanup.add(handle);
    } else if (releaseOwner) {
      unconfirmedRelease.add(releaseOwner);
    }
  };
  const rememberFailure = (error, releaseOwner) => {
    if (!failed) failure = error;
    failed = true;
    rememberCleanup(error, releaseOwner);
  };
  const rememberOwnedReleaseFailure = (error, owner) => {
    rememberCleanup(error, owner);
    owner?.afterFailure?.(error, rememberCleanup);
  };
  const releaseOwnedResult = owner => {
    try {
      const result = owner?.close?.();
      return result != null && typeof result.then === 'function'
        ? Promise.resolve(result).catch(error => {
          rememberOwnedReleaseFailure(error, owner);
          throw error;
        })
        : result;
    } catch (error) {
      rememberOwnedReleaseFailure(error, owner);
      throw error;
    }
  };
  const knownCleanupPending = () => {
    for (const handle of pendingCleanup) {
      try { if (handle.status().pending) return true; }
      catch { return true; }
    }
    return false;
  };
  const cleanupPending = () => executionSiteHostCleanupPending(
    siteInstallation,
    pendingCloses.size !== 0,
    knownCleanupPending(),
    unconfirmedRelease.size !== 0 || unconfirmedSiteOperations.size !== 0,
  );
  let firstTask = 1;
  try {
    const count = core.count(setup);
    if (core.nextTask?.(setup) === 0) firstTask = 0;
    // Captured Acquisition starts at task one; a checked source-free root
    // starts at task zero and uses the same managed task lifecycle.
    for (let step = firstTask; step < count; step++) {
      signal?.throwIfAborted();
      for (const entry of installed.values()) {
        signal?.throwIfAborted();
        await entry.beforeNext?.();
        // Even an absent callback yields to the caller. Cancellation during
        // preparation must not authorize another callback or a fresh attempt.
        signal?.throwIfAborted();
      }
      signal?.throwIfAborted();
      const managedInputs = core.managedProducers?.(setup) ?? [];
      const prepared = [];
      const excludedManagedCandidateCodes = [];
      for (const entry of installed.values()) {
        const task = await entry.prepareNext?.(managedOutputs);
        if (task == null) continue;
        for (const site of executionSitePlacements(siteInstallation, entry)) {
          const siteCandidate = executionSiteCandidate({
            installation: siteInstallation,
            contribution: entry,
            site,
            task: task.task,
            registration: entry.registration,
            inputs: Array.isArray(task.inputs) ? task.inputs : [],
            durationMilliseconds: task.durationMilliseconds,
            acceptsSiteTransfer: task.acceptsSiteTransfer === true,
            capacity: task.siteCapacity,
          });
          if (siteCandidate && siteCandidate.excluded === undefined) {
            prepared.push({entry, task, siteCandidate});
            candidateComparisons.push(Object.freeze({
              task: task.task,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              durationMilliseconds: siteCandidate.durationMilliseconds,
            }));
          } else {
            const reason = siteCandidate?.excluded ?? 'ExecutionSiteUnavailable';
            excludedManagedCandidateCodes.push(
              siteCandidate?.exclusionCode ?? 8,
            );
            candidateExclusions.push(Object.freeze({
              task: task.task,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              reason,
            }));
          }
        }
      }
      const managedTask = prepared.length ? core.nextTask(setup) : -1;
      for (const candidate of prepared) {
        if (candidate.task.task !== managedTask) {
          throw new StrategyHostError('InvalidManagedCandidate');
        }
      }
      const managedCandidate = prepared.length === 0 ? -1
        : selectExecutionSiteCandidateIndex(
          prepared.map(value => value.siteCandidate),
          {
            invalid: 'InvalidManagedCandidate',
            duplicate: 'DuplicateManagedSelectionKey',
          },
        );
      const managed = managedCandidate < 0
        ? undefined : prepared[managedCandidate];
      if (!managed && Array.isArray(managedInputs) && managedInputs.length !== 0) {
        const retainedInputs = managedInputs.filter(producer =>
          managedOutputs.has(producer));
        // A task whose producers are all still legacy follows the existing
        // dispatcher. Once any exact managed producer is selected, silently
        // dropping it or mixing it with a legacy reconstruction is forbidden.
        if (retainedInputs.length !== 0) {
          const outcome = classifyManagedExecutionSiteFallback(
            siteInstallation,
            retainedInputs.length,
            excludedManagedCandidateCodes,
          );
          const code = [undefined, 'ManagedCandidateEstimateUnavailable',
            'ManagedSiteTransferUnavailable',
            'NoCompatibleManagedStrategy'][outcome];
          if (code === undefined) {
            throw new StrategyHostError('InvalidManagedCandidateFallback');
          }
          throw new StrategyHostError(code);
        }
      }
      const task = managed ? managed.task : core.next(setup);
      if (task == null) break;
      const index = managed ? task.task : core.task(task);
      const entry = managed ? managed.entry : installed.get(core.registration(task));
      if (!entry || (managed && typeof entry.runPrepared !== 'function')) {
        throw new StrategyHostError('MissingStrategyImplementation');
      }
      signal?.throwIfAborted();
      if (managed && !core.selectManaged(setup, index, managed.entry.registration)) {
        throw new StrategyHostError('ManagedSelectionRejected');
      }
      let siteCandidate = managed?.siteCandidate;
      let legacyExclusions = [];
      if (!siteCandidate) {
        const value = core.taskCapacity(setup, index);
        if (!Array.isArray(value) || value.length !== 2 ||
            value.some(item => typeof item !== 'bigint' || item < 0n)) {
          throw new StrategyHostError('InvalidExecutionSiteCapacity');
        }
        const capacity = Object.freeze({
          retainedBytes: value[0],
          executionBytes: value[1],
        });
        const placementCandidates = [];
        for (const site of executionSitePlacements(siteInstallation, entry)) {
          // The implementation and task are already fixed by the checked
          // legacy dispatcher. Its unknown execution duration is a shared
          // term, not zero work; only the known Site placement cost varies and
          // participates in this comparison.
          const candidate = executionSiteCandidate({
            installation: siteInstallation,
            contribution: entry,
            site,
            task: index,
            registration: entry.registration,
            inputs: [],
            durationMilliseconds: 0n,
            acceptsSiteTransfer: false,
            capacity,
          });
          if (candidate && candidate.excluded === undefined) {
            placementCandidates.push(candidate);
            candidateComparisons.push(Object.freeze({
              task: index,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              durationMilliseconds: candidate.durationMilliseconds,
              scope: 'selected-registration-placement',
            }));
          } else {
            const reason = candidate?.excluded ?? 'ExecutionSiteUnavailable';
            legacyExclusions.push(reason);
            candidateExclusions.push(Object.freeze({
              task: index,
              registrationKey: entry.managedSelectionKey,
              site: executionSiteDescription(site),
              reason,
              scope: 'selected-registration-placement',
            }));
          }
        }
        const selectedPlacement = placementCandidates.length === 0 ? -1
          : selectExecutionSiteCandidateIndex(placementCandidates);
        siteCandidate = selectedPlacement < 0
          ? undefined : placementCandidates[selectedPlacement];
      }
      if (!siteCandidate || siteCandidate.excluded !== undefined) {
        throw new StrategyHostError(
          siteCandidate?.excluded ??
            [...legacyExclusions].sort()[0] ?? 'ExecutionSiteUnavailable',
        );
      }
      // Protected boundary: nothing below (Site operation, input transfer,
      // implementation start) happens unless this exact activation is
      // authorized. A deny, failure, unsupported defer or persisted wait
      // stops the Run through the existing stop path.
      await authorizeActivation(siteCandidate.site, entry, index);
      const siteBinding = bindExecutionSiteCandidate(siteCandidate);
      const siteOperation = startExecutionSiteOperation(siteBinding);
      let siteInputsResolved = siteCandidate.transfers.length === 0;
      let siteResolution;
      const resolveSiteInputs = (inputs, transferSignal = signal) => {
        if (!siteResolution) {
          siteResolution = transfers.resolve(
            siteCandidate, inputs, transferSignal,
          ).then(value => {
            siteInputsResolved = true;
            return value;
          });
        }
        return siteResolution;
      };
      const siteCompletionReady = () => siteInputsResolved &&
        executionSiteOperationAvailable(siteOperation);
      const siteCompletionPermit = Object.freeze({
        isAvailable: siteCompletionReady,
        assertAvailable() {
          if (!siteCompletionReady()) {
            throw new StrategyHostError('ExecutionSiteCompletionNotReady');
          }
        },
      });
      const siteTask = managed ? Object.freeze({
        ...task,
        executionSite: siteCandidate.site,
        resolveSiteInputs,
        siteCompletionReady,
      }) : task;
      let result, siteResult;
      let successProgress;
      // The same physical task boundary is measured for every realization.
      // This is diagnostic timing, never a cost estimate or execution proof.
      const taskStarted = performance.now();
      try {
        result = await (managed
          ? entry.runPrepared(siteTask, signal)
          : entry.run(task, signal, siteCompletionPermit));
        const connectorOwnedOutput = Boolean(managed || result?.close);
        const managedBindingClaimed = result?.completed != null ||
          result?.material != null;
        successProgress = beginExecutionSiteHostTaskSuccess(
          siteInstallation,
          connectorOwnedOutput,
          managedBindingClaimed,
        );
        for (let step = 0; step < 12; step++) {
          const action = executionSiteHostTaskSuccessAction(
            siteInstallation,
            successProgress,
          );
          if (action === 0) {
            recordExecutionSiteHostTaskSiteCompletion(
              siteInstallation,
              successProgress,
              siteCompletionReady(),
            );
            continue;
          }
          if (action === 1) {
            throw new StrategyHostError('ExecutionSiteCompletionNotReady');
          }
          if (action === 2) {
            recordExecutionSiteHostTaskCommonCompletion(
              siteInstallation,
              successProgress,
              core.completed(setup, index),
            );
            continue;
          }
          if (action === 3) throw new StrategyHostError('TaskNotCompleted');
          if (action === 4) {
            siteResult = retainSiteResult(
              siteOperation, result, siteCandidate.capacity.retainedBytes,
            );
            outputs.push(siteResult);
            recordExecutionSiteHostTaskOutputRetained(
              siteInstallation,
              successProgress,
            );
            continue;
          }
          if (action === 5) {
            const output = core.output(setup, index);
            if (output == null) {
              throw new StrategyHostError('MissingCompletedOutput');
            }
            coreSiteOutputs.retain(
              siteOperation, output, siteCandidate.capacity.retainedBytes,
            );
            recordExecutionSiteHostTaskOutputRetained(
              siteInstallation,
              successProgress,
            );
            continue;
          }
          if (action === 6) {
            if (!settleExecutionSiteOperation(siteOperation)) {
              throw new StrategyHostError(
                'ExecutionSiteOperationSettlementRejected',
              );
            }
            recordExecutionSiteHostTaskSiteOperationSettled(
              siteInstallation,
              successProgress,
            );
            continue;
          }
          if (action === 7) {
            const relationOutput = result?.material != null;
            const carrierOutput = result?.carrierMaterial != null;
            const managedBindingValid = result?.completed != null &&
              relationOutput !== carrierOutput &&
              (carrierOutput
                ? core.managedCarrierMatches?.(
                  setup,
                  index,
                  result.completed,
                ) === true
                : core.managedMatches(setup, index, result.completed));
            recordExecutionSiteHostTaskManagedBinding(
              siteInstallation,
              successProgress,
              managedBindingValid,
            );
            continue;
          }
          if (action === 8) {
            throw new StrategyHostError('InvalidManagedCompletion');
          }
          if (action === 9) {
            successProgress = undefined;
            break;
          }
          throw new StrategyHostError('InvalidHostTaskSuccessProgress');
        }
        if (successProgress !== undefined) {
          throw new StrategyHostError('HostTaskSuccessDidNotConverge');
        }
      } catch (error) {
        throw settleSiteAfterFailure(
          siteOperation,
          error,
          successProgress !== undefined &&
            executionSiteHostTaskSiteOperationSettled(
              siteInstallation,
              successProgress,
            ),
        );
      }
      // A callback's resolved Promise is not a completion proof. The core must
      // already have installed this exact task's retained, verified output.
      if (result?.completed != null || result?.material != null ||
          result?.carrierMaterial != null) {
        const relationOutput = result?.material != null;
        const carrierOutput = result?.carrierMaterial != null;
        const matches = carrierOutput
          ? core.managedCarrierMatches?.(setup, index, result.completed)
          : core.managedMatches?.(setup, index, result.completed);
        if (result?.completed == null || relationOutput === carrierOutput ||
            matches !== true) {
          throw new StrategyHostError('InvalidManagedCompletion');
        }
        managedOutputs.set(index, Object.freeze({
          task: index,
          completed: result.completed,
          material: result.material ?? result.carrierMaterial,
          carrierMaterial: result.carrierMaterial,
          site: siteCandidate.site,
          siteMaterial: result.siteMaterial ?? result.material ??
            result.carrierMaterial,
          materialGeneration: result.materialGeneration ?? result.material ??
            result.carrierMaterial,
          withRows: result.withRows,
          close: siteResult?.close,
          releaseOwner: siteResult,
        }));
      }
      completed.push(Object.freeze({
        ...result?.diagnostic,
        taskElapsedMilliseconds: performance.now() - taskStarted,
        task: index,
        executionSite: executionSiteDescription(siteCandidate.site),
      }));
      if (observeCompletion) {
        const output = result?.completed ?? core.output(setup, index);
        if (output == null) throw new StrategyHostError('MissingCompletedOutput');
        signal?.throwIfAborted();
        // Deliver the core's exact output, never a connector diagnostic/CID or
        // callback-supplied substitute. Failure stops future tasks but cannot
        // undo this already completed task's independent result.
        const readRetained = typeof result?.readRetained === 'function'
          ? async (accept, readSignal) => {
              if (siteResult?.status().released) {
                throw new StrategyHostError('RetainedUnavailable');
              }
              return result.readRetained(accept, readSignal);
            }
          : undefined;
        try { await observeCompletion(Object.freeze({task: index, output,
          ...(readRetained === undefined ? {} : {readRetained})})); }
        catch (error) { rememberCleanup(error, observeCompletion); throw error; }
        signal?.throwIfAborted();
      }
      if (managed) {
        for (const producer of task.releasableProducers ?? []) {
          const output = task.outputs?.get(producer);
          if (output?.siteMaterial) {
            await transfers.releaseSource(output);
          }
          if (output?.releaseOwner) {
            await releaseOwnedResult(output.releaseOwner);
          } else if (output?.close) {
            await output.close();
          }
          task.outputs?.delete(producer);
          managedOutputs.delete(producer);
        }
      }
    }
    if (!core.finished(setup)) throw new StrategyHostError('StrategyNotComplete');
  } catch (error) {
    rememberFailure(error);
    try { core.stop(setup); }
    catch (stopError) { rememberCleanup(stopError, core); }
  } finally {
    for (const entry of installed.values()) {
      try { await entry.finish?.(); }
      catch (error) { rememberFailure(error, entry); }
    }
    active.delete(setup);
  }
  const runFinished = failed ? false : core.finished(setup);
  const outcome = executionSiteHostTaskRunOutcome(
    siteInstallation,
    failed,
    runFinished,
  );
  if (outcome === 2) throw new StrategyHostError('InvalidStrategyOutcome');
  let execution;
  execution = Object.freeze({
    // Internal task records only, not Program/Run publication or partial success.
    status: outcome === 1 ? 'host-tasks-failed' : 'host-tasks-completed',
    failure,
    completed: Object.freeze(completed),
    candidateExclusions: Object.freeze(candidateExclusions),
    candidateComparisons: Object.freeze(candidateComparisons),
    programDefinitionCid,
    resultInventory: checkedResultInventory,
    publicationInventory,
    ...(preflight === undefined ? {} : {publicationPreflight: preflight}),
    async publishEffectFreeRun(store, publication, signal) {
      if (closed) throw new StrategyHostError('ReleasedStrategy');
      if (failed || !core.finished(setup)) {
        throw new StrategyHostError('StrategyNotComplete');
      }
      if (publication === null || typeof publication !== 'object' ||
          Array.isArray(publication) ||
          ['execution', 'store', 'control', 'signal']
            .some(name => Object.hasOwn(publication, name))) {
        throw new StrategyHostError('InvalidRunPublicationRequest');
      }
      const admitted = prepareCompletedEffectFreeRunPublication({
        store,
        control: core.publicationControl,
        publicationInventory,
        plan: publication,
      });
      return publishCompletedEffectFreeRun({
        ...admitted.plan,
        execution,
        store,
        control: core.publicationControl,
        signal,
      });
    },
    async storePublicationResult(result, store, publication, signal) {
      if (closed) throw new StrategyHostError('ReleasedStrategy');
      if (!Number.isSafeInteger(result) || result < 0 ||
          result >= resultInventory.length ||
          publication === null || typeof publication !== 'object' ||
          publication.outputLimits === undefined ||
          publication.contractLimits === undefined ||
          publication.runDefinition === undefined ||
          publication.invocation === undefined ||
          publication.retention === undefined ||
          publication.evidenceContext === undefined ||
          typeof core.outputExportControl?.beginResult !== 'function' ||
          typeof core.publicationControl?.issueResultArtifact !== 'function') {
        throw new StrategyHostError('InvalidResultPublicationExport');
      }
      const occurrence = resultInventory[result];
      if (!publicationContract(occurrence.definitionContract)) {
        throw new StrategyHostError('MissingResultDefinitionContract');
      }
      const managed = managedOutputs.get(occurrence.task);
      const beginManagedResult = managed === undefined ||
          typeof managed.withRows !== 'function'
        ? undefined
        : async (host, result, limits) => {
          const importing = core.outputExportControl.beginManagedResultImport(
            host,
            result,
            managed.completed,
            managed.material,
            limits,
          );
          let finished = false;
          try {
            const exported = await managed.withRows(
              row => core.outputExportControl.appendManagedResultImport(
                importing, row, limits,
              ),
              signal,
              () => core.outputExportControl.finishManagedResultImport(
                importing,
              ),
            );
            finished = true;
            return exported;
          } finally {
            if (!finished) {
              core.outputExportControl.cancelManagedResultImport(importing);
            }
          }
        };
      const stored = await storeCompletedResultPublicationPayload(
        store,
        core.outputExportControl,
        setup,
        result,
        publication.outputLimits,
        {
          control: core.publicationControl,
          runDefinition: publication.runDefinition,
          definition: occurrence.definitionContract,
          invocation: publication.invocation,
          retention: publication.retention,
          evidenceContext: publication.evidenceContext,
          limits: publication.contractLimits,
        },
        signal,
        beginManagedResult,
      );
      return Object.freeze({
        occurrence: Object.freeze({
          name: occurrence.name,
          task: occurrence.task,
          definition: occurrence.definitionContract,
        }),
        ...stored,
      });
    },
    usage: () => core.usage(setup),
    cleanupPending,
    cleanup() {
      if (cleanupInFlight) return cleanupInFlight;
      cleanupInFlight = (async () => {
        // Attempt every independent recovery even when an earlier one fails.
        // Only an explicit recovery handle authorizes retry; never run Compute.
        const errors = [];
        const attempted = new Set();
        const cleanupProgress = beginExecutionSiteHostCleanup(siteInstallation);
        const retryKnown = async () => {
          for (const handle of [...pendingCleanup]) {
            if (attempted.has(handle)) continue;
            attempted.add(handle);
            try {
              if (handle.status().pending) await handle.retry();
              if (!handle.status().pending) pendingCleanup.delete(handle);
            } catch (error) { errors.push(error); }
          }
        };
        for (let step = 0; step < 8; step++) {
          const action = executionSiteHostCleanupAction(
            siteInstallation,
            cleanupProgress,
            pendingCloses.size !== 0,
            knownCleanupPending(),
            unconfirmedRelease.size !== 0 ||
              unconfirmedSiteOperations.size !== 0,
            errors.length !== 0,
          );
          if (action === 0) {
            await retryKnown();
            recordExecutionSiteHostCleanupRetry(
              siteInstallation,
              cleanupProgress,
            );
            continue;
          }
          if (action === 1) {
            await Promise.all([...pendingCloses]);
            recordExecutionSiteHostCleanupClosesAwaited(
              siteInstallation,
              cleanupProgress,
            );
            continue;
          }
          if (action === 2) return false;
          if (action === 3) {
            throw new AggregateError(errors, 'Strategy cleanup failed');
          }
          if (action === 4) return true;
          throw new StrategyHostError('InvalidStrategyCleanupProgress');
        }
        throw new StrategyHostError('StrategyCleanupDidNotConverge');
      })().finally(() => { cleanupInFlight = undefined; });
      return cleanupInFlight;
    },
    explain(maxBytes = 65536, maxNodes = 10000) {
      for (const limit of [maxBytes, maxNodes]) {
        if (!Number.isSafeInteger(limit) || limit < 0 || limit > 2147483647) {
          throw new StrategyHostError('InvalidExplanationLimit');
        }
      }
      return core.explain(setup, maxBytes, maxNodes);
    },
    output(task) {
      if (closed) throw new StrategyHostError('ReleasedStrategy');
      if (!Number.isSafeInteger(task) ||
          task < (firstTask === 0 ? 0 : 1) || task >= core.count(setup)) {
        throw new StrategyHostError('InvalidStrategyTask');
      }
      return core.output(setup, task);
    },
    close() {
      if (closed) return closeResult;
      closed = true;
      let closeFailed = false;
      let closeFailure;
      const releaseFailed = (error, owner) => {
        if (!closeFailed) closeFailure = error;
        closeFailed = true;
        rememberOwnedReleaseFailure(error, owner);
      };
      try {
        const result = transfers.close();
        if (result != null && typeof result.then === 'function') {
          const pending = Promise.resolve(result).then(
            () => {}, error => releaseFailed(error, transfers),
          ).finally(() => pendingCloses.delete(pending));
          pendingCloses.add(pending);
        }
      } catch (error) { releaseFailed(error, transfers); }
      for (const output of outputs) {
        try {
          const result = releaseOwnedResult(output);
          if (result != null && typeof result.then === 'function') {
            const pending = Promise.resolve(result).then(
              () => {}, error => releaseFailed(error, output),
            ).finally(() => pendingCloses.delete(pending));
            pendingCloses.add(pending);
          }
        } catch (error) { releaseFailed(error, output); }
      }
      outputs.length = 0;
      try { coreSiteOutputs.close(); }
      catch (error) { releaseFailed(error, coreSiteOutputs); }
      if (pendingCloses.size) {
        closeResult = Promise.all([...pendingCloses]).then(() => {
          if (closeFailed) throw closeFailure;
        });
        // Older synchronous callers may ignore the return value. Responsibility
        // still stays in this driver's cleanup state, never an unhandled reject.
        closeResult.catch(() => {});
      }
      if (closeFailed) throw closeFailure;
      return closeResult;
    },
  });
  return execution;
}
