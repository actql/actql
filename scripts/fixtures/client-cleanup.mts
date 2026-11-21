// Acceptance drivers consume the SDK's documented cleanup retry, not another
// Run/Host attempt. Only fulfillment from this same sealed Client confirms
// its release. A deadline or a cancellation request is never that ACK.
import {setTimeout} from 'node:timers/promises';
import type {Client} from '@actql/sdk';

type ClientClose = Pick<Client, 'close'>;
type CleanupOptions = {signal?: AbortSignal};
type CloseFailure = {code?: unknown; cleanupPending?: unknown};

export async function closeFixtureClient(client: ClientClose, {signal = AbortSignal.timeout(5000)}: CleanupOptions = {}) {
  for (;;) {
    try { await client.close(); return; }
    catch (error) {
      if ((error as CloseFailure | null | undefined)?.code !== 'ClientCleanupPending' || (error as CloseFailure).cleanupPending !== true ||
          signal.aborted) throw error;
      try { await setTimeout(10, undefined, {signal}); }
      catch { throw error; }
    }
  }
}

export async function withFixtureClientCleanup<Value>(
  client: ClientClose, operation: () => Value | PromiseLike<Value>, options?: CleanupOptions,
): Promise<Value> {
  let failed = false, primary: unknown, value: Value | undefined;
  try { value = await operation(); }
  catch (error) { failed = true; primary = error; }
  try { await closeFixtureClient(client, options); }
  catch (cleanup) {
    if (failed) {
      throw new AggregateError([primary, cleanup], 'FixtureOperationAndCleanupFailed',
        {cause: primary});
    }
    throw cleanup;
  }
  if (failed) throw primary;
  return value as Value;
}
