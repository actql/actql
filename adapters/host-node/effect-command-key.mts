import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

type CommandKeyAdvance<Key> = {
  clientProgramEffectCommandKeyAdvance?: (key: Key, quantum: number) => unknown;
};
type CleanupStatus = Readonly<{pending: boolean}>;
export type EffectCommandKeyCleanupFailure = Error & {
  cleanupError: unknown;
  cleanupPending: true;
  cleanupHandle: Readonly<{status: () => CleanupStatus; retry: () => Promise<CleanupStatus>}>;
};

// The original Common continuation owns traversal, duplicate checks, cleanup
// and capture transfer. This caller never inspects or constructs key values.
export async function advanceEffectCommandKey<Key>(moon: CommandKeyAdvance<Key>, key: Key | undefined,
  signal: AbortSignal | undefined, quantum: number) {
  if (key === undefined) return;
  const advance = moon.clientProgramEffectCommandKeyAdvance;
  for (;;) {
    signal?.throwIfAborted();
    const progress = checked(advance!.call(moon, key, quantum));
    if (runtimeField(progress, 0)) return;
    // The installed Common successful payload is (Bool, Int); extract it through the JS binding.
    if ((runtimeField(progress, 1) as number) <= 0) {
      throw new Error('EffectCommandKeyDidNotAdvance');
    }
    await yieldEventLoop(undefined, {signal});
  }
}

// Private key retirement has no physical reader ACK. Keep the exact original
// cleanup callback reachable if it refuses; an aborted traversal must not
// discard its bounded workspace merely because its import is closing.
export async function retireEffectCommandKeyWorkspace(cleanup: () => boolean, cause?: unknown) {
  let pending = true;
  const retry = async () => {
    while (pending) {
      if (cleanup() === true) pending = false;
      else await yieldEventLoop();
    }
    return Object.freeze({pending});
  };
  try {
    await retry();
  } catch (cleanupError) {
    const error = new Error('EffectCommandKeyCleanupPending', {
      cause: cause ?? cleanupError,
    }) as EffectCommandKeyCleanupFailure;
    error.cleanupError = cleanupError;
    error.cleanupPending = true;
    error.cleanupHandle = Object.freeze({
      status: () => Object.freeze({pending}), retry,
    });
    throw error;
  }
}
