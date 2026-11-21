// Transport plumbing only. Selection, counters, completion and capture stay
// in the existing RowRun; no JS matcher or second listing state machine.
import {setImmediate} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';

type ListingRuntime = Readonly<{
  clientProgramRowSourceBeginListingRequest(run: unknown, token: string | undefined, elapsed: bigint): unknown;
  clientProgramRowSourceBeginListingPage(run: unknown, body: Uint8Array, elapsed: bigint, charge: unknown): unknown;
  clientProgramRowSourceAdvanceListingPage(run: unknown, quantum: number, elapsed: bigint): unknown;
}>;
type ListingOptions = Readonly<{moon: ListingRuntime; run: unknown; currentRead: () => unknown;
  signal?: AbortSignal; now?: () => number}>;
type ListingProgress = Readonly<{status: string; rows: number; work: number}>;

export function rowListingCallbacks({moon, run, currentRead, signal,
  now = () => performance.now()}: ListingOptions) {
  const started = now();
  const elapsed = () => BigInt(Math.floor(now() - started));
  const checkCurrent = async () => {
    signal?.throwIfAborted();
    await currentRead();
    signal?.throwIfAborted();
  };
  return Object.freeze({
    async beginRequest(token: string | null | undefined) {
      await checkCurrent();
      return checked(moon.clientProgramRowSourceBeginListingRequest(
        run, token ?? undefined, elapsed()));
    },
    async consumePage(body: Uint8Array, {charge}: Readonly<{charge?: unknown}> = {}) {
      await checkCurrent();
      checked(moon.clientProgramRowSourceBeginListingPage(
        run, body, elapsed(), charge));
      for (;;) {
        await checkCurrent();
        const result = JSON.parse(checked(
          moon.clientProgramRowSourceAdvanceListingPage(run, 64, elapsed())) as string) as ListingProgress;
        if (result.status === 'complete') return result.rows;
        // A normal runtime Continue spent positive bounded work. Yield before
        // resuming, so cancellation/current authority can interrupt the scan.
        if (result.status !== 'continue' || !Number.isSafeInteger(result.work) ||
            result.work <= 0 || result.work > 64) {
          throw Object.assign(new Error('InvalidRowListingProgress'),
            {code: 'InvalidRowListingProgress'});
        }
        await setImmediate(undefined, {signal});
      }
    },
  });
}
