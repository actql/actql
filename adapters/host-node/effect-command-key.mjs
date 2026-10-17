import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

// The original Common continuation owns traversal, duplicate checks, cleanup
// and capture transfer. This caller never inspects or constructs key values.
export async function advanceEffectCommandKey(moon, key, signal, quantum) {
  if (key === undefined) return;
  const advance = moon.clientProgramEffectCommandKeyAdvance;
  for (;;) {
    signal?.throwIfAborted();
    const progress = checked(advance.call(moon, key, quantum));
    if (runtimeField(progress, 0)) return;
    if (runtimeField(progress, 1) <= 0) {
      throw new Error('EffectCommandKeyDidNotAdvance');
    }
    await yieldEventLoop(undefined, {signal});
  }
}

// Private key retirement has no physical reader ACK. Keep the exact original
// cleanup callback reachable if it refuses; an aborted traversal must not
// discard its bounded workspace merely because its import is closing.
export async function retireEffectCommandKeyWorkspace(cleanup, cause) {
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
    });
    error.cleanupError = cleanupError;
    error.cleanupPending = true;
    error.cleanupHandle = Object.freeze({
      status: () => Object.freeze({pending}), retry,
    });
    throw error;
  }
}
