import {instantiate} from '../../_build/workers/modules/bridge.mjs';
import {installStrategyContributions} from '../connectors-workers/strategy.generated.mjs';
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// One invocation owns result consumption and recovery. No module-global run,
// input cache, binding, request context or environment is retained here.
// The callback may run consumers while outputs are live. All task handles are
// invalidated before this call returns; cross-request persistence is not a port.
export function createWorkersHost(hashSeed) {
  const moon = instantiate(hashSeed);
  return Object.freeze({withCapturedStrategy, usage: setup => moon.strategyHostUsage(setup)});

async function withCapturedStrategy(setup, consume, signal) {
  if (typeof consume !== 'function') throw new TypeError('A scoped consumer is required');
  const report = await runInstalledStrategy(setup, runtimeCore(moon),
    installStrategyContributions(moon, setup, checked, {}), signal);
  const errors = [];
  let value;
  try {
    if (report.status !== 'host-tasks-completed') {
      throw new Error('Workers strategy failed', {cause:report.failure});
    }
    value = await consume(report);
  } catch (error) { errors.push(error); }
  try { report.close(); } catch (error) { errors.push(error); }
  try {
    if (!await report.cleanup()) throw new Error('Unconfirmed resource cleanup');
  } catch (error) { errors.push(error); }
  if (errors.length) {
    const error = new AggregateError(errors, 'Workers invocation failed');
    if (report.cleanupPending()) {
      // Preserve the recovery owner, never return a successful response while
      // silently dropping it. The invoking Host must resolve/report this inside
      // its request lifetime; this is not a durable lease or retry of Compute.
      error.cleanupHandle = Object.freeze({
        status: () => ({pending:report.cleanupPending()}), retry: () => report.cleanup(),
      });
    }
    throw error;
  }
  return value;
}
}
