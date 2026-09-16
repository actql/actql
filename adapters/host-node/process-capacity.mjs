// Installed control Host wiring, not a connector-supplied completion verifier.
import {prepareManagedExecution, startManagedExecution} from './process-channel.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {snapshotProcessLimits, emptyProcessUsage} from './process-accounting.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/process_host_bridge/process_host_bridge.js', import.meta.url);

export async function createManagedProcessHost(limits) {
  limits = snapshotProcessLimits(limits);
  const runtime = await import(runtimeUrl.href);
  const ledger = checked(runtime.processLedgerCreate(limits));
  return Object.freeze({
    usage: () => Object.freeze({...runtime.processLedgerUsage(ledger)}),
    async start(configuration, capacity, signal) {
      signal?.throwIfAborted();
      if (configuration.accounting !== undefined) throw new TypeError('InstalledProcessAccountingOnly');
      const {retainedBytes, executionBytes} = capacity;
      const childLimits = capacity.childLimits === undefined ? undefined : snapshotProcessLimits(capacity.childLimits);
      if (typeof retainedBytes !== 'bigint' || typeof executionBytes !== 'bigint' ||
          retainedBytes < 0n || executionBytes <= 0n ||
          retainedBytes > 9223372036854775807n || executionBytes > 9223372036854775807n) {
        throw new TypeError('InvalidProcessCapacity');
      }
      let delegation, finalUsage;
      const prepared = prepareManagedExecution({...configuration,
        ...(childLimits ? {accounting: {limits: childLimits, report(usage, terminal) {
          checked(runtime.processReportUsage(ledger, delegation, usage));
          if (terminal) finalUsage = usage;
        }}} : {}),
      });
      signal?.throwIfAborted();
      const reservation = childLimits ? undefined : checked(runtime.processReserve(ledger, retainedBytes, executionBytes));
      if (childLimits) delegation = checked(runtime.processDelegate(ledger, childLimits, retainedBytes, executionBytes));
      let settled = false;
      let settlement;
      const release = () => {
        if (!settled) {
          if (delegation) checked(runtime.processDelegationStopped(ledger, delegation, finalUsage));
          else checked(runtime.processStopped(ledger, reservation));
          settled = true;
        }
      };
      const track = handle => {
        settlement = handle.whenStopped().then(release);
        // Preserve a failed settlement for explicit cleanup, without allowing an
        // ignored cleanup promise to become an unhandled rejection.
        settlement.catch(() => {});
        return Object.freeze({
          status: () => Object.freeze({pending: !settled || handle.status().pending}),
          whenStopped: () => settlement,
          retry: async () => {
            await handle.retry();
            await settlement;
            return Object.freeze({pending: !settled || handle.status().pending});
          },
        });
      };
      let channel;
      try {
        channel = await startManagedExecution(prepared, signal);
      } catch (error) {
        if (error?.cleanupHandle) error.cleanupHandle = track(error.cleanupHandle);
        else {
          finalUsage = emptyProcessUsage(); // Known unstarted: no delegated work.
          release();
        }
        throw error;
      }
      const cleanupHandle = track(channel.cleanupHandle);
      return Object.freeze({
        ...channel,
        cleanupHandle,
        async request(body, requestSignal) {
          try { return await channel.request(body, requestSignal); }
          catch (error) {
            if (error?.cleanupHandle) error.cleanupHandle = cleanupHandle;
            throw error;
          }
        },
        async close() {
          const result = await channel.close();
          await settlement;
          return result;
        },
      });
    },
  });
}
