import {mock} from 'node:test';

// Install before importing the Host under test. The real entry and all of its
// ownership/admission checks still run; only calls into it are counted.
export async function installEffectComputationProbe(entryUrl, onCall = () => {}) {
  if (typeof mock.module !== 'function' || typeof onCall !== 'function') {
    throw new TypeError('EffectComputeProbeRequiresModuleMocks');
  }
  const actual = await import(entryUrl);
  if (typeof actual.runCapturedEffectComputation !== 'function') {
    throw new TypeError('EffectComputeEntryUnavailable');
  }
  let calls = 0;
  const replacement = mock.module(entryUrl, {
    namedExports: {...actual,
      runCapturedEffectComputation(...args) {
        calls++;
        onCall(calls);
        return actual.runCapturedEffectComputation(...args);
      }},
  });
  return Object.freeze({calls: () => calls, restore: () => replacement.restore()});
}
