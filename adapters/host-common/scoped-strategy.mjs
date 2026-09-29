import {runInstalledStrategy} from './strategy.mjs';

// One invocation owns result consumption and recovery. No module-global run,
// input cache, binding, request context or environment is retained here.
// The callback may run consumers while outputs are live. All task handles are
// invalidated before this call returns; cross-request persistence is not a port.
// Trusted composition helper. Product entry points bind core/implementations;
// request data does not choose these callbacks or replace a verifier.
// Historical diagnostic text is retained; it is not an environment restriction.
export async function withScopedStrategy(setup, core, contributions, consume, signal) {
  if (typeof consume !== 'function') throw new TypeError('A scoped consumer is required');
  const report = await runInstalledStrategy(setup, core, contributions, signal);
  const errors = [];
  let value;
  try {
    if (report.status !== 'host-tasks-completed') {
      throw new Error('Workers strategy failed', {cause:report.failure});
    }
    value = await consume(report);
  } catch (error) { errors.push(error); }
  try { await report.close(); } catch (error) { errors.push(error); }
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
