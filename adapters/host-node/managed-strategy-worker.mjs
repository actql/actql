// Execution-process assembly for the same standard Host used in-process.
// prepare is installed module wiring, never received through IPC. It constructs
// owned MoonBit preparation locally; process-local authority is not serialized.
import {runCapturedStrategy} from './entry.mjs';
import {serveManagedExecution} from './worker-channel.mjs';
import {encodeProcessLimits, emptyProcessUsage} from './process-accounting.mjs';

export function serveManagedStrategy(prepare, frames) {
  if (typeof prepare !== 'function') throw new TypeError('Missing installed application');
  let phase = 'empty', prepared, opened, execution, closeStarted = false;
  let accounting;
  const recovery = new Set(), unknown = new Set();
  const remember = (error, owner) => {
    const handle = error?.cleanupHandle;
    if (handle && typeof handle.status === 'function' && typeof handle.retry === 'function') recovery.add(handle);
    else unknown.add(owner);
  };
  const pending = () => unknown.size !== 0 || [...recovery].some(handle => handle.status().pending) ||
    !!execution?.cleanupPending();
  const cleanup = async () => {
    const errors = [];
    if (execution) {
      try { await execution.cleanup(); } catch (error) { errors.push(error); }
    }
    for (const handle of recovery) {
      try {
        if (handle.status().pending) await handle.retry();
        if (!handle.status().pending) recovery.delete(handle);
      } catch (error) { errors.push(error); }
    }
    if (errors.length) throw new AggregateError(errors, 'ManagedStrategyCleanupFailed');
    return !pending();
  };
  const release = async () => {
    if (!closeStarted) {
      closeStarted = true;
      // Observe every independent owner even if an earlier close rejects.
      if (execution) {
        try { await execution.close(); }
        catch { /* The standard driver retains its own close/retry owners. */ }
      }
      if (opened) {
        try { await opened.close(); } catch (error) { remember(error, opened); }
      }
      prepared = undefined;
    }
    const complete = await cleanup();
    phase = complete ? 'released' : 'cleanup-pending';
    return {kind: 'strategy-release', complete};
  };
  return serveManagedExecution(async (request, signal, context) => {
    signal.throwIfAborted();
    if (!request || typeof request !== 'object' || Array.isArray(request)) throw Error('InvalidStrategyRequest');
    if (request.command === 'prepare' && phase === 'empty' &&
        Object.keys(request).sort().join(',') === 'command,input') {
      phase = 'preparing';
      const plan = await prepare(request.input, signal, context);
      signal.throwIfAborted();
      if (!plan || typeof plan.open !== 'function') throw Error('InvalidStrategyPreparation');
      if (context.resourceLimits) {
        if (typeof plan.usage !== 'function' ||
            JSON.stringify(encodeProcessLimits(plan.resourceLimits)) !== JSON.stringify(encodeProcessLimits(context.resourceLimits))) {
          throw Error('ForeignStrategyResourceLimits');
        }
        accounting = plan.usage;
      }
      prepared = Object.freeze({open: plan.open});
      phase = 'prepared';
      return {kind: 'strategy-prepared', pid: process.pid};
    }
    if (Object.keys(request).join(',') !== 'command') throw Error('InvalidStrategyRequest');
    if (request.command === 'execute' && phase === 'prepared') {
      phase = 'running'; // No failure path restores dispatch permission.
      try {
        opened = await prepared.open(signal, context);
        signal.throwIfAborted();
        if (!opened || typeof opened.close !== 'function' || typeof opened.describe !== 'function') {
          throw Error('InvalidStrategyApplication');
        }
        // Only the installed application can supply this opaque observer. It is
        // not taken from the IPC request or interpreted as execution evidence.
        execution = await runCapturedStrategy(opened.setup, opened.configurations, signal, opened.observer);
        phase = execution.status === 'host-tasks-completed' ? 'completed' : 'failed';
        // Diagnostics only. Neither rows nor opaque completion/producer handles
        // are returned. Retained-result re-admission has a separate contract.
        return {kind: 'strategy-report', pid: process.pid, program_success: false,
          report: opened.describe(execution)};
      } catch (error) {
        phase = 'failed';
        // An open failure may own started I/O even without a returned handle.
        if (!opened) remember(error, prepared);
        throw error;
      }
    }
    if (request.command === 'release' && phase !== 'empty' && phase !== 'running') return release();
    throw Error('StrategyPhaseMismatch');
  }, frames, {accounting: () => accounting ? accounting() : emptyProcessUsage(), finish: async () => {
    const result = await release();
    if (!result.complete) throw Error('ManagedStrategyCleanupUnconfirmed');
  }});
}
