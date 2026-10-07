import {setImmediate as yieldToHost} from 'node:timers/promises';

// The common owner issues the receipt and keeps partial roots. This adapter
// only yields between its bounded polls; the caller retains cleanup custody.
export async function finishManagedOutputReceipt(advance, signal) {
  const quantum = 64;
  for (;;) {
    signal?.throwIfAborted();
    const poll = advance(quantum);
    if (typeof poll?._0 !== 'boolean' || !Number.isSafeInteger(poll?._1)
        || poll._1 <= 0 || poll._1 > quantum) {
      throw new TypeError('Invalid managed output finish progress');
    }
    signal?.throwIfAborted();
    if (poll._0) return;
    await yieldToHost();
  }
}
