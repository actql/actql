import {runInstalledStrategy} from './strategy.mjs';

type Strategy = Parameters<typeof runInstalledStrategy>[0];
type Execution = Awaited<ReturnType<typeof runInstalledStrategy>>;
type CompletedExecution = Execution & Readonly<{status: 'host-tasks-completed'}>;
export type ScopedStrategyConsumer<Result> = (execution: CompletedExecution) => Result;
export type ScopedStrategyFailure = AggregateError & {
  cleanupHandle?: Readonly<{
    status(): Readonly<{pending: boolean}>;
    retry(): ReturnType<Execution['cleanup']>;
  }>;
};

// One invocation owns result consumption and recovery. No module-global run,
// input cache, binding, request context or environment is retained here.
// The callback may run consumers while outputs are live. All task handles are
// invalidated before this call returns; cross-request persistence is not a port.
// Trusted composition helper. Product entry points bind core/implementations;
// request data does not choose these callbacks or replace a verifier.
// Historical diagnostic text is retained; it is not an environment restriction.
export async function withScopedStrategy<Result>(
  setup: Strategy['setup'], core: Strategy['runtime']['core'],
  contributions: Strategy['runtime']['contributions'], consume: ScopedStrategyConsumer<Result>,
  signal?: AbortSignal, {authorization}: Pick<Strategy['runtime'], 'authorization'> = {},
): Promise<Awaited<Result>> {
  if (typeof consume !== 'function') throw new TypeError('A scoped consumer is required');
  const report = await runInstalledStrategy({setup, runtime: {core, contributions, authorization}, control: {signal}});
  const errors: unknown[] = [];
  let value: Awaited<Result> | undefined;
  try {
    if (report.status !== 'host-tasks-completed') {
      throw new Error('Workers strategy failed', {cause:report.failure});
    }
    value = await consume(report as CompletedExecution);
  } catch (error) { errors.push(error); }
  try { await report.close(); } catch (error) { errors.push(error); }
  try {
    if (!await report.cleanup()) throw new Error('Unconfirmed resource cleanup');
  } catch (error) { errors.push(error); }
  if (errors.length) {
    const error: ScopedStrategyFailure = new AggregateError(errors, 'Workers invocation failed');
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
  return value as Awaited<Result>;
}
