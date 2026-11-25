// Installed control Host wiring, not a connector-supplied completion verifier.
import {prepareManagedExecution, startManagedExecution} from './process-channel.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {snapshotProcessLimits, snapshotProcessUsage, emptyProcessUsage} from './process-accounting.mjs';

type LedgerLimits = ReturnType<typeof snapshotProcessLimits>;
type LedgerUsage = ReturnType<typeof snapshotProcessUsage>;
type ExecutionConfiguration = Omit<Parameters<typeof prepareManagedExecution>[0], 'accounting'> &
  Readonly<{accounting?: never}>;
type Capacity = Readonly<{retainedBytes: bigint; executionBytes: bigint; childLimits?: unknown}>;
type CleanupHandle = Awaited<ReturnType<typeof startManagedExecution>>['cleanupHandle'];
type ProcessFailure = {cleanupHandle?: CleanupHandle | SettledCleanup};
type SettledCleanup = Readonly<{
  status(): Readonly<{pending: boolean}>;
  whenStopped(): Promise<void>;
  retry(): Promise<Readonly<{pending: boolean}>>;
}>;

declare const accountingIdentity: unique symbol;
type AccountingValue<Kind extends string> = {readonly [accountingIdentity]: Kind};
type Ledger = AccountingValue<'ledger'>;
type Delegation = AccountingValue<'delegation'>;
type Reservation = AccountingValue<'reservation'>;
export type ProcessCapacityRuntime = Readonly<{
  processLedgerCreate(limits: LedgerLimits): unknown;
  processLedgerUsage(ledger: Ledger): unknown;
  processReserve(ledger: Ledger, retained: bigint, execution: bigint): unknown;
  processDelegate(ledger: Ledger, limits: LedgerLimits, retained: bigint, execution: bigint): unknown;
  processStarted(ledger: Ledger, reservation: Reservation): unknown;
  processDelegationStarted(ledger: Ledger, delegation: Delegation): unknown;
  processStopped(ledger: Ledger, reservation: Reservation): unknown;
  processDelegationStopped(ledger: Ledger, delegation: Delegation, finalUsage: LedgerUsage | undefined): unknown;
  processReportUsage(ledger: Ledger, delegation: Delegation, usage: LedgerUsage): unknown;
}>;

const runtimeUrl = new URL('../../_build/js/release/build/process_host_bridge/process_host_bridge.js', import.meta.url);

export async function createManagedProcessHost(limits: unknown) {
  limits = snapshotProcessLimits(limits);
  const runtime: ProcessCapacityRuntime = await import(runtimeUrl.href);
  const ledger = checked(runtime.processLedgerCreate(limits as LedgerLimits)) as Ledger;
  return Object.freeze({
    usage: () => snapshotProcessUsage(runtime.processLedgerUsage(ledger)),
    async start(configuration: ExecutionConfiguration, capacity: Capacity, signal?: AbortSignal) {
      signal?.throwIfAborted();
      if (configuration.accounting !== undefined) throw new TypeError('InstalledProcessAccountingOnly');
      const {retainedBytes, executionBytes} = capacity;
      const childLimits = capacity.childLimits === undefined ? undefined : snapshotProcessLimits(capacity.childLimits);
      if (typeof retainedBytes !== 'bigint' || typeof executionBytes !== 'bigint' ||
          retainedBytes < 0n || executionBytes <= 0n ||
          retainedBytes > 9223372036854775807n || executionBytes > 9223372036854775807n) {
        throw new TypeError('InvalidProcessCapacity');
      }
      let delegation: Delegation | undefined, finalUsage: LedgerUsage | undefined;
      const prepared = prepareManagedExecution({...configuration,
        ...(childLimits ? {accounting: {limits: childLimits, report(usage: LedgerUsage, terminal: boolean) {
          checked(runtime.processReportUsage(ledger, delegation!, usage));
          if (terminal) finalUsage = usage;
        }}} : {}),
      });
      signal?.throwIfAborted();
      const reservation = childLimits ? undefined : checked(runtime.processReserve(ledger, retainedBytes, executionBytes)) as Reservation;
      if (childLimits) delegation = checked(runtime.processDelegate(ledger, childLimits, retainedBytes, executionBytes)) as Delegation;
      let settled = false;
      let settlement!: Promise<void>;
      const release = () => {
        if (!settled) {
          if (delegation) checked(runtime.processDelegationStopped(ledger, delegation, finalUsage));
          else checked(runtime.processStopped(ledger, reservation!));
          settled = true;
        }
      };
      const track = (handle: CleanupHandle): SettledCleanup => {
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
        channel = await startManagedExecution(prepared, signal, () => {
          if (delegation) checked(runtime.processDelegationStarted(ledger, delegation));
          else checked(runtime.processStarted(ledger, reservation!));
        });
      } catch (error) {
        if ((error as ProcessFailure | undefined)?.cleanupHandle)
          (error as ProcessFailure).cleanupHandle = track((error as {cleanupHandle: CleanupHandle}).cleanupHandle);
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
        async request(body: unknown, requestSignal?: AbortSignal) {
          try { return await channel.request(body, requestSignal); }
          catch (error) {
            if ((error as ProcessFailure | undefined)?.cleanupHandle) (error as ProcessFailure).cleanupHandle = cleanupHandle;
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
