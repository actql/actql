import {writeSync} from 'node:fs';

// Test diagnostics only: fixed labels, no request, reference, payload or key.
// Synchronous stderr survives a later child timeout without changing stdout.
export function contentCommandStageTrace(phase, {
  write = text => writeSync(2, text), now = () => performance.now(),
} = {}) {
  const startedAt = now();
  let records = 0;
  return stage => {
    if (records >= 64) return;
    records++;
    try {
      // Call sites supply literal labels. Refuse other diagnostic input rather
      // than stringify an escaped object or accidentally emit its contents.
      if (!['capture', 'approve', 'approve-model', 'read'].includes(phase) ||
          typeof stage !== 'string' || !/^[a-z-]{1,48}$/u.test(stage)) return;
      write(JSON.stringify({contentCommandStage: stage, phase, pid: process.pid,
        elapsedMs: Math.round(now() - startedAt)}) + '\n');
    } catch {
      // A closed diagnostic sink cannot replace the original failure or its
      // cleanup duties. There is no fallback output, retry or extra work.
    }
  };
}
