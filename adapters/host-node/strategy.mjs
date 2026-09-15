// Trusted Node coordination only. Checked readiness, selected ownership,
// reservations and atomic completion are enforced by the common MoonBit core.
// Installed entries are implementation code, not user-supplied success proofs.
export class StrategyHostError extends Error {
  constructor(code) { super(code); this.code = code; }
}

const active = new WeakSet();

export async function runInstalledStrategy(setup, core, contributions, signal) {
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
      run: entry.run, beforeNext: entry.beforeNext, finish: entry.finish,
    }));
  }
  active.add(setup);
  const completed = [];
  const outputs = [];
  const pendingCleanup = new Set();
  let failure;
  let closed = false;
  const rememberCleanup = error => {
    if (error?.cleanupHandle?.status().pending) pendingCleanup.add(error.cleanupHandle);
  };
  try {
    const count = core.count(setup);
    for (let step = 1; step < count; step++) {
      signal?.throwIfAborted();
      for (const entry of installed.values()) await entry.beforeNext?.();
      const task = core.next(setup);
      if (task == null) break;
      const index = core.task(task);
      const entry = installed.get(core.registration(task));
      if (!entry) throw new StrategyHostError('MissingStrategyImplementation');
      const result = await entry.run(task, signal);
      if (result?.close) outputs.push(result);
      // A callback's resolved Promise is not a completion proof. The core must
      // already have installed this exact task's retained, verified output.
      if (!core.completed(setup, index)) throw new StrategyHostError('TaskNotCompleted');
      completed.push(Object.freeze({ ...result?.diagnostic, task: index }));
    }
    if (!core.finished(setup)) throw new StrategyHostError('StrategyNotComplete');
  } catch (error) {
    failure = error;
    rememberCleanup(error);
    core.stop(setup);
  } finally {
    for (const entry of installed.values()) {
      try { await entry.finish?.(); }
      catch (error) { failure ??= error; rememberCleanup(error); }
    }
    active.delete(setup);
  }
  return Object.freeze({
    // Internal task records only, not Program/Run publication or partial success.
    status: failure === undefined ? 'host-tasks-completed' : 'host-tasks-failed',
    failure,
    completed: Object.freeze(completed),
    usage: () => core.usage(setup),
    cleanupPending: () => [...pendingCleanup].some(handle => handle.status().pending),
    async cleanup() {
      // Resource recovery, never another dispatch or a retry of computation.
      for (const handle of pendingCleanup) {
        if (handle.status().pending) await handle.retry();
        if (!handle.status().pending) pendingCleanup.delete(handle);
      }
      return pendingCleanup.size === 0;
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
      if (closed) return;
      closed = true;
      let closeFailure;
      for (const output of outputs) {
        try { output.close(); } catch (error) { closeFailure ??= error; }
      }
      outputs.length = 0;
      try { core.closeOutputs(setup); } catch (error) { closeFailure ??= error; }
      if (closeFailure) throw closeFailure;
    },
  });
}
