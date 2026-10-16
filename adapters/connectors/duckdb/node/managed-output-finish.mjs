import {runtimeField, runtimeOptionalField} from '../../../host-common/compiler-binding.generated.mjs';
import {setImmediate as yieldToHost} from 'node:timers/promises';

// The common owner issues the receipt and keeps partial roots. This adapter
// only yields between its bounded polls; the caller retains cleanup custody.
export async function finishManagedOutputReceipt(advance, signal) {
  const quantum = 64;
  for (;;) {
    signal?.throwIfAborted();
    const poll = advance(quantum);
    if (typeof runtimeOptionalField(poll, 0) !== 'boolean' || !Number.isSafeInteger(runtimeOptionalField(poll, 1))
        || runtimeField(poll, 1) <= 0 || runtimeField(poll, 1) > quantum) {
      throw new TypeError('Invalid managed output finish progress');
    }
    signal?.throwIfAborted();
    if (runtimeField(poll, 0)) return;
    await yieldToHost();
  }
}
