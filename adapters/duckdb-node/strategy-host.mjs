// Trusted finite serial transport driver. Readiness, exact input binding and
// selected capability validation stay in MoonBit; this is not a Program runner.
import { runStrategyHostCompute, openResidentStrategyEnvironment,
  importResidentStrategyInput, runResidentStrategyHostCompute } from './host.mjs';
import { DuckDBTransportError } from './session.mjs';
import { checked } from './runtime-result.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/duckdb_host_node/duckdb_host_node.js', import.meta.url);
let runtime;
const active = new WeakSet();
const usageKeys = ['planningWork', 'attempts', 'holdings', 'transferredBytes',
  'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes'];

export async function runCapturedStrategy(setup, transportLimits, importLimits, signal) {
  const moon = await (runtime ??= import(runtimeUrl.href));
  if (active.has(setup)) throw new DuckDBTransportError('StrategyAlreadyRunning');
  active.add(setup);
  const limits = Object.freeze({ ...transportLimits });
  const imports = Object.freeze({ ...importLimits });
  const completed = [];
  const nativeResults = [];
  let failure;
  let closed = false;
  let residentEnvironment;
  const pendingCleanup = new Set();
  const rememberCleanup = error => {
    if (error?.cleanupHandle?.status().pending) pendingCleanup.add(error.cleanupHandle);
  };
  const usage = () => Object.freeze(Object.fromEntries(
    moon.strategyHostUsage(setup).map((value, index) => [usageKeys[index], value]),
  ));
  try {
    const count = moon.strategyHostCount(setup);
    for (let step = 1; step < count; step++) {
      signal?.throwIfAborted();
      if (residentEnvironment && !residentEnvironment.status().live) {
        // No new task has started. Close invalidates stale dispatch and keeps
        // incurred cost; pending cleanup is not silently treated as capacity.
        await residentEnvironment.close();
        residentEnvironment = undefined;
      }
      const task = checked(moon.strategyHostNext(setup));
      if (task === undefined || task === null) break;
      const index = moon.strategyHostTask(task);
      if (moon.strategyHostNative(task)) {
        const resident = moon.strategyHostResident(task);
        const residentInputs = [];
        let mapping;
        if (resident) {
          residentEnvironment ??= await openResidentStrategyEnvironment(moon.strategyHostRun(setup), index, limits);
          for (const [producer, bytes, entries, names] of checked(moon.strategyHostResidentInputs(setup, index))) {
            mapping = { maxEntries: Number(entries), maxNameBytes: Number(names) };
            if (!residentEnvironment.hasTable(Number(producer))) {
              await importResidentStrategyInput(residentEnvironment, Number(producer), bytes, limits, mapping, signal);
            }
            residentInputs.push(residentEnvironment.table(Number(producer)));
          }
        }
        const selected = checked(moon.strategyHostTakeNative(task));
        const result = resident
          ? await runResidentStrategyHostCompute(selected, residentEnvironment, residentInputs, limits, mapping, signal)
          : await runStrategyHostCompute(selected, limits, imports, signal);
        nativeResults.push(result);
        completed.push(Object.freeze({ task: index, realization: resident ? 'duckdb-resident' : 'duckdb', transport: result.usage }));
      } else {
        checked(moon.strategyHostExecuteLocal(task));
        completed.push(Object.freeze({ task: index, realization: 'local' }));
      }
    }
    if (!moon.strategyHostFinished(setup)) throw new DuckDBTransportError('StrategyNotComplete');
  } catch (error) {
    failure = error;
    rememberCleanup(error);
    moon.strategyHostStop(setup);
  } finally {
    if (residentEnvironment) {
      try { await residentEnvironment.close(); }
      catch (error) { failure ??= error; rememberCleanup(error); }
    }
    active.delete(setup);
  }
  return Object.freeze({
    // Internal task completion only: never Program/Run success or partial publication.
    status: failure === undefined ? 'host-tasks-completed' : 'host-tasks-failed',
    failure,
    completed: Object.freeze(completed),
    usage,
    cleanupPending() {
      return [...pendingCleanup].some(handle => handle.status().pending);
    },
    async cleanup() {
      // Resource recovery only. Never dispatch or retry a failed Compute.
      for (const handle of pendingCleanup) {
        if (handle.status().pending) await handle.retry();
        if (!handle.status().pending) pendingCleanup.delete(handle);
      }
      return pendingCleanup.size === 0;
    },
    explain(maxBytes = 65536, maxNodes = 10000) {
      for (const limit of [maxBytes, maxNodes]) {
        if (!Number.isSafeInteger(limit) || limit < 0 || limit > 2147483647) {
          throw new DuckDBTransportError('InvalidExplanationLimit');
        }
      }
      return JSON.parse(checked(moon.strategyHostExplain(setup, maxBytes, maxNodes)));
    },
    output(task) {
      if (closed) throw new DuckDBTransportError('ReleasedStrategy');
      if (!Number.isSafeInteger(task) || task < 1 || task >= moon.strategyHostCount(setup)) {
        throw new DuckDBTransportError('InvalidStrategyTask');
      }
      return moon.strategyHostOutput(setup, task);
    },
    close() {
      if (closed) return;
      closed = true;
      for (const result of nativeResults) result.close();
      nativeResults.length = 0;
      moon.strategyHostCloseOutputs(setup);
    },
  });
}
