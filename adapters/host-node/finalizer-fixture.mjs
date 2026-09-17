// Portable protocol fixture. Real semantic completion is tested separately.
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {withScopedStrategy} from '../workers/invocation.mjs';

export async function finalizerCase(kind, scoped = false) {
  const first = kind === 'undefined' ? undefined : kind === 'null' ? null : new Error('first');
  const registration = {}, setup = {};
  let finished = 0, closed = 0, complete = false, consumed = 0;
  const core = {
    count: () => 2, next: () => ({}), task: () => 1,
    taskCapacity: () => [0n, 0n],
    registration: () => registration, completed: () => complete,
    finished: () => complete, stop() {}, usage: () => ({}),
    closeOutputs() { closed++; }, output: () => complete ? 1 : undefined,
  };
  const entries = [{
    registration, run() { complete = true; },
    finish() { finished++; throw first; },
  }, {
    registration: {}, run() { throw new Error('unused'); },
    finish() { finished++; throw new Error('secondary'); },
  }];
  if (scoped) {
    try {
      await withScopedStrategy(setup, core, entries, () => { consumed++; });
      throw new Error('Unexpected success');
    } catch (error) {
      return {
        failed: error instanceof AggregateError,
        firstPreserved: error.errors?.[0]?.cause === first,
        pending: error.cleanupHandle?.status().pending,
        cleanup: await error.cleanupHandle?.retry(), finished, closed, consumed,
      };
    }
  }
  const result = await runInstalledStrategy(setup, core, entries);
  const output = result.output(1);
  const cleanups = await Promise.all([result.cleanup(), result.cleanup()]);
  result.close(); result.close();
  return {
    failed: result.status === 'host-tasks-failed', firstPreserved: result.failure === first,
    output, pending: result.cleanupPending(), cleanups,
    cleanup: await result.cleanup(), finished, closed,
  };
}

export async function asynchronousCloseCase(kind) {
  const registration = {}, setup = {};
  let complete = false, closed = 0, retries = 0, pending = true;
  const recovery = {status: () => ({pending}), retry() { retries++; pending = false; }};
  const first = kind === 'undefined' ? undefined : kind === 'null' ? null :
    Object.assign(new Error('asynchronous close'), {cleanupHandle: recovery});
  const core = {
    count: () => 2, next: () => ({}), task: () => 1,
    taskCapacity: () => [0n, 0n],
    registration: () => registration, completed: () => complete,
    finished: () => complete, stop() {}, usage: () => ({}),
    closeOutputs() { closed++; }, output: () => complete ? 1 : undefined,
  };
  try {
    await withScopedStrategy(setup, core, [{registration, run() {
      complete = true;
      return {async close() { await Promise.resolve(); throw first; }};
    }}], () => 1);
    return {failed: false};
  } catch (error) {
    return {failed: error instanceof AggregateError, firstPreserved: error.errors?.[0] === first,
      pending: error.cleanupHandle?.status().pending ?? false, closed, retries};
  }
}
