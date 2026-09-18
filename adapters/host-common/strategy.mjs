// Trusted JavaScript coordination only. Checked readiness, selected ownership,
// reservations and atomic completion are enforced by the common MoonBit core.
// Installed entries are implementation code, not user-supplied success proofs.
import {bindExecutionSiteCandidate, executionSiteCandidate,
  executionSiteDescription, executionSiteOperationAvailable,
  executionSitePlacements, installExecutionSites,
  prepareSingleExecutionSitePolicy, releaseExecutionSiteHolding,
  retainExecutionSiteOperationHolding, settleExecutionSiteOperation,
  startExecutionSiteOperation} from './execution-sites.mjs';
import {createManagedSiteTransferCoordinator} from
  './managed-site-transfer.mjs';

export class StrategyHostError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const active = new WeakSet();
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
  const holding = retainExecutionSiteOperationHolding(
    operation, result?.material ?? result, retainedBytes,
  );
  let released = false;
  let closeStarted = false;
  let closeResult;
  let closeFailure;
  let cleanupTracked = false;
  const release = () => {
    if (released) return;
    releaseExecutionSiteHolding(holding);
    released = true;
  };
  return Object.freeze({
    status: () => Object.freeze({released}),
    close() {
      if (released || closeStarted) return closeResult;
      closeStarted = true;
      try {
        closeResult = typeof result?.close === 'function'
          ? result.close() : undefined;
      }
      catch (reason) { closeFailure = reason; throw reason; }
      if (closeResult != null && typeof closeResult.then === 'function') {
        closeResult = Promise.resolve(closeResult).then(
          value => { release(); return value; },
          reason => { closeFailure = reason; throw reason; },
        );
      } else {
        release();
      }
      return closeResult;
    },
    afterFailure(reason, remember) {
      if (cleanupTracked || released || reason !== closeFailure) return;
      const upstream = failureMember(reason, 'cleanupHandle');
      if (failureMember(reason, 'cleanupPending') !== true ||
          !upstream || typeof failureMember(upstream, 'status') !== 'function') {
        return;
      }
      cleanupTracked = true;
      const state = () => {
        try {
          const value = upstream.status();
          if (value?.pending === false) release();
          return Object.freeze({
            pending: !released,
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
function coreOutputSiteOwner(core, setup) {
  const retained = new Set();
  let closeFailure;
  let cleanupTracked = false;
  const release = () => {
    for (const holding of retained) releaseExecutionSiteHolding(holding);
    retained.clear();
  };
  return Object.freeze({
    retain(operation, value, retainedBytes) {
      retained.add(retainExecutionSiteOperationHolding(
        operation, value, retainedBytes,
      ));
    },
    close() {
      try { core.closeOutputs(setup); }
      catch (reason) { closeFailure = reason; throw reason; }
      release();
    },
    afterFailure(reason, remember) {
      if (cleanupTracked || retained.size === 0 || reason !== closeFailure) return;
      const upstream = failureMember(reason, 'cleanupHandle');
      if (failureMember(reason, 'cleanupPending') !== true ||
          !upstream || typeof failureMember(upstream, 'status') !== 'function') {
        return;
      }
      cleanupTracked = true;
      const state = () => {
        try {
          const value = upstream.status();
          if (value?.pending === false) release();
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
  setup, core, contributions, signal, observeCompletion, sitePolicy,
) {
  if (observeCompletion !== undefined && typeof observeCompletion !== 'function') {
    throw new StrategyHostError('InvalidCompletionObserver');
  }
  if (active.has(setup)) throw new StrategyHostError('StrategyAlreadyRunning');
  core = Object.freeze({ ...core });
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
  );
  const transfers = createManagedSiteTransferCoordinator(
    setup, core, siteInstallation,
  );
  const coreSiteOutputs = coreOutputSiteOwner(core, setup);
  // A contribution that explicitly reports unconfirmed cleanup without a
  // usable status authority cannot release its Site operation. There is no
  // safe retry to invent, but the reservation and teardown responsibility
  // must remain visible.
  const unconfirmedSiteOperations = new Set();
  const settleSiteAfterFailure = (operation, error) => {
    if (failureMember(error, 'cleanupPending') !== true) {
      settleExecutionSiteOperation(operation);
      return error;
    }
    const upstream = failureMember(error, 'cleanupHandle');
    const failure = ownedStrategyFailure(error, 'StrategyExecutionFailed');
    if (typeof failureMember(upstream, 'status') !== 'function') {
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
        if (state?.pending === false) settleExecutionSiteOperation(operation);
        return Object.freeze({
          pending: state?.pending !== false,
          errors: Object.freeze(Array.isArray(state?.errors)
            ? [...state.errors] : []),
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
  active.add(setup);
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
  const cleanupPending = () => {
    if (pendingCloses.size) return true;
    if (unconfirmedRelease.size) return true;
    if (unconfirmedSiteOperations.size) return true;
    for (const handle of pendingCleanup) {
      try { if (handle.status().pending) return true; }
      catch { return true; }
    }
    return false;
  };
  try {
    const count = core.count(setup);
    for (let step = 1; step < count; step++) {
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
      const excludedManagedCandidates = [];
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
            excludedManagedCandidates.push(reason);
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
        const duration = candidate.siteCandidate.durationMilliseconds;
        const key = candidate.siteCandidate.selectionKey;
        if (candidate.task.task !== managedTask ||
            typeof duration !== 'bigint' || duration < 0n ||
            typeof key !== 'string' || key.length === 0) {
          throw new StrategyHostError('InvalidManagedCandidate');
        }
      }
      if (new Set(prepared.map(value => value.siteCandidate.selectionKey)).size !==
          prepared.length) {
        throw new StrategyHostError('DuplicateManagedSelectionKey');
      }
      prepared.sort((left, right) => {
        const a = left.siteCandidate.durationMilliseconds;
        const b = right.siteCandidate.durationMilliseconds;
        if (a !== b) return a < b ? -1 : 1;
        const leftKey = left.siteCandidate.selectionKey;
        const rightKey = right.siteCandidate.selectionKey;
        return leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0;
      });
      const managed = prepared[0];
      if (!managed && Array.isArray(managedInputs) && managedInputs.length !== 0) {
        const retainedInputs = managedInputs.filter(producer =>
          managedOutputs.has(producer));
        // A task whose producers are all still legacy follows the existing
        // dispatcher. Once any exact managed producer is selected, silently
        // dropping it or mixing it with a legacy reconstruction is forbidden.
        if (retainedInputs.length !== 0) {
          const code = excludedManagedCandidates.some(value =>
            ['MissingDurationEstimate', 'MissingTransferEstimate']
              .includes(value))
            ? 'ManagedCandidateEstimateUnavailable'
            : excludedManagedCandidates.some(value =>
              ['MissingTransferProvider',
                'UnsupportedTransferRepresentation',
                'SourceSiteRevoked'].includes(value))
              ? 'ManagedSiteTransferUnavailable'
              : 'NoCompatibleManagedStrategy';
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
        placementCandidates.sort((left, right) => {
          if (left.durationMilliseconds !== right.durationMilliseconds) {
            return left.durationMilliseconds < right.durationMilliseconds
              ? -1 : 1;
          }
          return left.selectionKey < right.selectionKey ? -1
            : left.selectionKey > right.selectionKey ? 1 : 0;
        });
        siteCandidate = placementCandidates[0];
      }
      if (!siteCandidate || siteCandidate.excluded !== undefined) {
        throw new StrategyHostError(
          siteCandidate?.excluded ??
            [...legacyExclusions].sort()[0] ?? 'ExecutionSiteUnavailable',
        );
      }
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
      try {
        result = await (managed
          ? entry.runPrepared(siteTask, signal)
          : entry.run(task, signal, siteCompletionPermit));
        siteCompletionPermit.assertAvailable();
        if (!core.completed(setup, index)) {
          throw new StrategyHostError('TaskNotCompleted');
        }
        if (managed || result?.close) {
          siteResult = retainSiteResult(
            siteOperation, result, siteCandidate.capacity.retainedBytes,
          );
        } else {
          const output = core.output(setup, index);
          if (output == null) throw new StrategyHostError('MissingCompletedOutput');
          coreSiteOutputs.retain(
            siteOperation, output, siteCandidate.capacity.retainedBytes,
          );
        }
        settleExecutionSiteOperation(siteOperation);
        if (siteResult) outputs.push(siteResult);
      } catch (error) {
        throw settleSiteAfterFailure(siteOperation, error);
      }
      // A callback's resolved Promise is not a completion proof. The core must
      // already have installed this exact task's retained, verified output.
      if (result?.completed != null || result?.material != null) {
        if (result.completed == null || result.material == null ||
            !core.managedMatches(setup, index, result.completed)) {
          throw new StrategyHostError('InvalidManagedCompletion');
        }
        managedOutputs.set(index, Object.freeze({
          task: index,
          completed: result.completed,
          material: result.material,
          site: siteCandidate.site,
          siteMaterial: result.siteMaterial ?? result.material,
          materialGeneration: result.materialGeneration ?? result.material,
          close: siteResult?.close,
          releaseOwner: siteResult,
        }));
      }
      completed.push(Object.freeze({
        ...result?.diagnostic,
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
        try { await observeCompletion(Object.freeze({task: index, output})); }
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
  return Object.freeze({
    // Internal task records only, not Program/Run publication or partial success.
    status: failed ? 'host-tasks-failed' : 'host-tasks-completed',
    failure,
    completed: Object.freeze(completed),
    candidateExclusions: Object.freeze(candidateExclusions),
    candidateComparisons: Object.freeze(candidateComparisons),
    usage: () => core.usage(setup),
    cleanupPending,
    cleanup() {
      if (cleanupInFlight) return cleanupInFlight;
      cleanupInFlight = (async () => {
        // Attempt every independent recovery even when an earlier one fails.
        // Only an explicit recovery handle authorizes retry; never run Compute.
        const errors = [];
        const attempted = new Set();
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
        // A retained output close may wait for a failed Transfer's source pin,
        // while that pin belongs to an already known recovery handle. Progress
        // known operation cleanup first, then observe every initiated close.
        // Close failures can contribute new explicit handles, so run one more
        // pass after those Promises have settled.
        await retryKnown();
        await Promise.all([...pendingCloses]);
        await retryKnown();
        if (errors.length) throw new AggregateError(errors, 'Strategy cleanup failed');
        return !cleanupPending();
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
      if (!Number.isSafeInteger(task) || task < 1 || task >= core.count(setup)) {
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
}
