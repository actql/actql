// Trusted JavaScript coordination only. Checked readiness, selected ownership,
// reservations and atomic completion are enforced by the common MoonBit core.
// Installed entries are implementation code, not user-supplied success proofs.
export class StrategyHostError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const active = new WeakSet();

export async function runInstalledStrategy(setup, core, contributions, signal, observeCompletion) {
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
      run: entry.run,
      prepareNext: entry.prepareNext,
      runPrepared: entry.runPrepared,
      beforeNext: entry.beforeNext,
      finish: entry.finish,
    }));
  }
  active.add(setup);
  const completed = [];
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
  const cleanupPending = () => {
    if (pendingCloses.size) return true;
    if (unconfirmedRelease.size) return true;
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
      const prepared = [];
      for (const entry of installed.values()) {
        const task = await entry.prepareNext?.(managedOutputs);
        if (task != null) prepared.push({entry, task});
      }
      if (prepared.length > 1) {
        throw new StrategyHostError('AmbiguousManagedStrategy');
      }
      const managed = prepared[0];
      const task = managed ? managed.task : core.next(setup);
      if (task == null) break;
      const index = managed ? task.task : core.task(task);
      const entry = managed ? managed.entry : installed.get(core.registration(task));
      if (!entry || (managed && typeof entry.runPrepared !== 'function')) {
        throw new StrategyHostError('MissingStrategyImplementation');
      }
      signal?.throwIfAborted();
      const result = await (managed
        ? entry.runPrepared(task, signal)
        : entry.run(task, signal));
      if (result?.close) outputs.push(result);
      // A callback's resolved Promise is not a completion proof. The core must
      // already have installed this exact task's retained, verified output.
      if (!core.completed(setup, index)) throw new StrategyHostError('TaskNotCompleted');
      if (result?.completed != null || result?.material != null) {
        if (result.completed == null || result.material == null ||
            !core.managedMatches(setup, index, result.completed)) {
          throw new StrategyHostError('InvalidManagedCompletion');
        }
        managedOutputs.set(index, Object.freeze({
          completed: result.completed, material: result.material,
        }));
      }
      completed.push(Object.freeze({ ...result?.diagnostic, task: index }));
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
    usage: () => core.usage(setup),
    cleanupPending,
    cleanup() {
      if (cleanupInFlight) return cleanupInFlight;
      cleanupInFlight = (async () => {
        // Closing a file-backed output may still be awaiting readers or native
        // cleanup. Observe every initiated close before inspecting its recovery
        // handles; an unresolved Promise is not release confirmation.
        await Promise.all([...pendingCloses]);
        // Attempt every independent recovery even when an earlier one fails.
        // Only an explicit recovery handle authorizes retry; never run Compute.
        const errors = [];
        for (const handle of pendingCleanup) {
          try {
            if (handle.status().pending) await handle.retry();
            if (!handle.status().pending) pendingCleanup.delete(handle);
          } catch (error) { errors.push(error); }
        }
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
        rememberCleanup(error, owner);
      };
      for (const output of outputs) {
        try {
          const result = output.close();
          if (result != null && typeof result.then === 'function') {
            const pending = Promise.resolve(result).then(
              () => {}, error => releaseFailed(error, output),
            ).finally(() => pendingCloses.delete(pending));
            pendingCloses.add(pending);
          }
        } catch (error) { releaseFailed(error, output); }
      }
      outputs.length = 0;
      try { core.closeOutputs(setup); } catch (error) { releaseFailed(error, core); }
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
