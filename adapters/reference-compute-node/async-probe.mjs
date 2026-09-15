// Test Connector transport for the independent numeric implementation. The
// asynchronous port represents pending work/stop acknowledgement, not a proof
// of numeric correctness. Owned completion is checked by the real MoonBit code.
export function numericProbeContribution(moon, operations, setup, checked, port) {
  return Object.freeze({
    registration: moon.strategyModule_reference_compute_Registration(setup),
    async run(task, signal) {
      signal?.throwIfAborted();
      const work = checked(operations.beginAsyncProbe(setup,task));
      let settled = false;
      const stop = async () => {
        await port.stop();
        checked(operations.settleAsyncProbe(work));
        settled = true;
      };
      try {
        await port.wait('reserved');
        signal?.throwIfAborted();
        checked(operations.executeAsyncProbe(work));
        await port.wait('computed');
        signal?.throwIfAborted();
        await stop();
        checked(operations.completeAsyncProbe(work));
        return {
          diagnostic:{realization:'asynchronous-numeric-probe'},
          close() { operations.closeAsyncProbe(work); },
        };
      } catch (cause) {
        operations.closeAsyncProbe(work);
        // Cancelling the owner is not evidence that asynchronous work stopped.
        const error = new Error('Numeric probe stopped without completion', {cause});
        if (!settled) error.cleanupHandle = Object.freeze({
          status: () => ({pending:!settled}),
          retry: async () => { if (!settled) await stop(); },
        });
        throw error;
      }
    },
  });
}
