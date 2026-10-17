// Acceptance drivers consume the SDK's documented cleanup retry, not another
// Run/Host attempt. Only fulfillment from this same sealed Client confirms
// its release. A deadline or a cancellation request is never that ACK.
import {setTimeout} from 'node:timers/promises';

export async function closeFixtureClient(client, {signal = AbortSignal.timeout(5000)} = {}) {
  for (;;) {
    try { await client.close(); return; }
    catch (error) {
      if (error?.code !== 'ClientCleanupPending' || error.cleanupPending !== true ||
          signal.aborted) throw error;
      try { await setTimeout(10, undefined, {signal}); }
      catch { throw error; }
    }
  }
}

export async function withFixtureClientCleanup(client, operation, options) {
  let failed = false, primary, value;
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
  return value;
}
