// Physical custody while one admitted Effect Run acquires its source and
// computes. This does not retry acquisition, Compute, or an Effect dispatch.
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {acquiredEffectPublicationPlan} from './local-values-plan.mjs';
import {runCapturedEffectComputation} from './entry.mjs';

export async function openAcquiredEffectComputation({moon, owner, acquired,
  sourceProfile, registry, values, fragment, ordered, sourceAccess,
  signal, now, retainComputationOwner}) {
  if (typeof retainComputationOwner !== 'function' ||
      typeof sourceProfile?.prepare !== 'function' ||
      typeof sourceProfile?.open !== 'function') {
    throw new TypeError('InvalidAcquiredEffectComputationPort');
  }
  let captured;
  let execution;
  let recovery;
  let unresolved = false;
  let pending = true;
  let settled = false;
  let closed = false;
  const custody = Object.freeze({
    async close() {
      closed = true;
      // A physical owner's cleanup, not another Compute call, recovers a
      // failed close. Retain the captured source until consumers are gone.
      await (execution ?? recovery)?.close();
    },
    async cleanup() {
      if (!closed || !settled || unresolved) return false;
      const physical = execution ?? recovery;
      if (physical !== undefined) {
        if (await physical.cleanup() === false ||
            physical.cleanupPending() !== false) return false;
        execution = undefined;
        recovery = undefined;
      }
      if (captured !== undefined) {
        await captured.close();
        captured = undefined;
      }
      pending = false;
      return true;
    },
    cleanupPending: () => pending,
  });
  // Even preparation can fail. The dispatch owner receives custody before
  // the first asynchronous boundary or provider operation.
  retainComputationOwner(custody);
  try {
    signal?.throwIfAborted();
    const preparedSource = await sourceProfile.prepare({
      preparedEffect: acquired.prepared, registry, values, fragment, ordered,
      sourceAccess});
    signal?.throwIfAborted();
    const captureStartedAt = now();
    const acquisition = acquisitionEndHandoff();
    try {
      captured = await sourceProfile.open({preparedEffect: acquired.prepared,
        registry, values, fragment, ordered, sourceAccess, signal,
        preparedSource, reportAcquisitionFailure: acquisition.retain});
    } catch (error) {
      const ended = acquisition.outcome(error);
      recovery = ended.recovery;
      unresolved = ended.outcome === 'unknown' && recovery === undefined;
      throw error;
    }
    const captureCompletedAt = now();
    const sourceEvidenceWire = await captured.issueSourceEvidence({
      authorityScopeCid: acquired.authorityScopeCid,
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid});
    const publicationPlan = acquiredEffectPublicationPlan({acquired,
      captured, sourceEvidenceWire, captureStartedAt, captureCompletedAt});
    signal?.throwIfAborted();
    const checkedHost = moon.clientProgramOpenCapturedLocalEffectHost(owner,
      captured.capture.source(), registry, values, 1n, 0n, 0n, 0n,
      fragment, ordered);
    if (checkedHost === undefined) {
      throw new Error('InstalledEffectProgramUnsupported');
    }
    // Without a returned Compute owner an exception cannot prove a stop.
    // Keep the responsibility rather than relabeling it as released.
    unresolved = true;
    execution = await runCapturedEffectComputation(checkedHost,
      {authorization: sourceAccess.authorization}, signal);
    unresolved = false;
    return Object.freeze({execution, checkedHost, publicationPlan,
      cleanupOwner: custody});
  } finally {
    settled = true;
  }
}
