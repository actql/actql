// Trusted finite serial transport driver. Readiness, exact input binding and
// selected capability validation stay in MoonBit; this is not a Program runner.
import { runStrategyHostCompute } from './host.mjs';
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
  const usage = () => Object.freeze(Object.fromEntries(
    moon.strategyHostUsage(setup).map((value, index) => [usageKeys[index], value]),
  ));
  try {
    const count = moon.strategyHostCount(setup);
    for (let step = 1; step < count; step++) {
      signal?.throwIfAborted();
      const task = checked(moon.strategyHostNext(setup));
      if (task === undefined || task === null) break;
      const index = moon.strategyHostTask(task);
      if (moon.strategyHostNative(task)) {
        const selected = checked(moon.strategyHostTakeNative(task));
        const result = await runStrategyHostCompute(selected, limits, imports, signal);
        nativeResults.push(result);
        completed.push(Object.freeze({ task: index, realization: 'duckdb', transport: result.usage }));
      } else {
        checked(moon.strategyHostExecuteLocal(task));
        completed.push(Object.freeze({ task: index, realization: 'local' }));
      }
    }
    if (!moon.strategyHostFinished(setup)) throw new DuckDBTransportError('StrategyNotComplete');
  } catch (error) {
    failure = error;
    moon.strategyHostStop(setup);
  } finally {
    active.delete(setup);
  }
  return Object.freeze({
    // Internal task completion only: never Program/Run success or partial publication.
    status: failure === undefined ? 'host-tasks-completed' : 'host-tasks-failed',
    failure,
    completed: Object.freeze(completed),
    usage,
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
