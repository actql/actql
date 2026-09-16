// Local connector's Node driver. The kernel and reservation authority stay in
// MoonBit; this wrapper never evaluates an expression or synthesizes a result.
import {readLocalRetainedInput} from './retained-input.mjs';
import {localRetainedStore} from './retained-store.mjs';
import {prepareLocalRetainedOutput} from './retained-output.mjs';

export function localStrategyContribution(moon, setup, checked, configuration) {
  const createLease = localRetainedStore(configuration);
  return Object.freeze({
    registration: moon.strategyModule_local_Registration(setup),
    async run(task, signal) {
      signal?.throwIfAborted();
      const operations = checked(moon.strategyModule_local_Dispatch(setup, task));
      let settled = false;
      let importedRows = 0, importedBytes = 0n;
      let output;
      try {
        if (operations.output != null) output = prepareLocalRetainedOutput(operations.output, createLease, checked, signal);
        for (const input of operations.inputs) {
          signal?.throwIfAborted();
          const usage = await readLocalRetainedInput(input, checked, signal);
          importedRows += usage.rows;
          importedBytes += BigInt(usage.bytes);
        }
        signal?.throwIfAborted();
        checked(operations.execute());
        const exported = output ? await output.write() : {};
        checked(operations.settle());
        settled = true;
        checked(operations.complete());
        return {diagnostic: {realization: 'local', importedRows, importedBytes: String(importedBytes), ...exported},
          close: output ? async () => {
            output?.close();
            operations.close();
            if (output) {
              try {
                await output.cleanupHandle.retry();
                if (output.cleanupHandle.status().pending) throw new Error('LocalOutputCleanupPending');
              } catch (error) {
                const failure = error instanceof Error ? error : new Error('LocalOutputCleanupFailed');
                failure.cleanupHandle = output.cleanupHandle;
                throw failure;
              }
            }
          } : () => operations.close()};
      } catch (error) {
        output?.close();
        operations.close();
        // All awaited reader work has returned; no asynchronous Local operation
        // remains. This does not acknowledge cleanup of the source Store.
        if (!settled) checked(operations.settle());
        if (output) {
          const prior = error?.cleanupHandle;
          const failure = error instanceof Error ? error : new Error('LocalOutputFailed', {cause: error});
          const combined = Object.freeze({
            status: () => ({pending: output.cleanupHandle.status().pending || !!prior?.status().pending}),
            async retry() {
              const failures = [];
              for (const handle of [prior, output.cleanupHandle]) {
                try { await handle?.retry(); } catch (error) { failures.push(error); }
              }
              if (failures.length) throw new AggregateError(failures, 'LocalOutputCleanupFailed');
              return combined.status();
            },
          });
          failure.cleanupHandle = combined;
          throw failure;
        }
        throw error;
      }
    },
  });
}
