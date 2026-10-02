// Physical custody while one admitted Effect Run acquires its source and
// computes. This does not retry acquisition, Compute, or an Effect dispatch.
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan} from './local-values-plan.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {capturedDuckDBNativeConfiguration, capturedDuckDBPhysicalCapacity} from './captured-duckdb-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runCapturedEffectComputation} from './entry.mjs';

export async function openAcquiredEffectComputation({moon, owner, acquired,
  sourceProfile, registry, values, fragment, ordered, sourceAccess,
  signal, now, retainComputationOwner}) {
  const multiple = moon?.clientProgramEffectAcquisitionCount?.(acquired.prepared) === 2;
  if (typeof retainComputationOwner !== 'function' ||
      (multiple ? sourceProfile?.sources?.length !== 2 :
        typeof sourceProfile?.prepare !== 'function' ||
        typeof sourceProfile?.open !== 'function')) {
    throw new TypeError('InvalidAcquiredEffectComputationPort');
  }
  const captures = [];
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
      while (captures.length > 0) {
        await captures[0].close();
        captures.shift();
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
    const sources = [];
    for (let task = 0; task < (multiple ? 2 : 1); task++) {
      const occurrence = {stage: task, input: 0, task};
      const requirement = multiple ? checked(
        moon.clientProgramEffectPrepareLocalQueryRequirement(acquired.prepared,
          task, 0, registry, values, fragment, ordered)) : undefined;
      const adapter = multiple ? installedSourceFor(sourceProfile,
        moon.clientProgramQueryRequirementSourceRef(requirement)) : sourceProfile;
      if (multiple && adapter.realizationKey !== 'duckdb-acquired') {
        throw new TypeError('UnsupportedEffectSourceRealization');
      }
      const access = multiple ? adapter.sourceAccess : sourceAccess;
      const preparedSource = await adapter.prepare({
        preparedEffect: acquired.prepared, registry, values, fragment, ordered,
        sourceAccess: access, occurrence});
      sources.push({adapter, access, preparedSource, occurrence});
      signal?.throwIfAborted();
    }
    let ledger;
    if (multiple) {
      const capacities = sources.map(value => capturedDuckDBPhysicalCapacity(value.preparedSource));
      ledger = moon.clientProgramPrepareMultiCapturedEffectLocalLedger(
        acquired.prepared,
        sources.map(value => capturedDuckDBNativeConfiguration(value.preparedSource)),
        capacities.map(value => value.transferBytes),
        capacities.map(value => value.executionBytes), registry, values, fragment, ordered);
      if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
    }
    const captureStartedAt = now();
    const evidence = [];
    for (const source of sources) {
      signal?.throwIfAborted();
      const acquisition = acquisitionEndHandoff();
      let captured;
      try {
        captured = await source.adapter.open({preparedEffect: acquired.prepared,
          registry, values, fragment, ordered, sourceAccess: source.access, signal,
          preparedSource: source.preparedSource, occurrence: source.occurrence,
          ledger, reportAcquisitionFailure: acquisition.retain});
      } catch (error) {
        const ended = acquisition.outcome(error);
        recovery = ended.recovery;
        unresolved = ended.outcome === 'unknown' && recovery === undefined;
        throw error;
      }
      captures.push(captured);
      const sourceEvidenceWire = await captured.issueSourceEvidence({
        authorityScopeCid: acquired.authorityScopeCid,
        effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid});
      evidence.push({captured, sourceEvidenceWire});
    }
    const captureCompletedAt = now();
    const publicationPlan = multiple
      ? acquiredMultiEffectPublicationPlan({acquired, sources: evidence,
        captureStartedAt, captureCompletedAt})
      : acquiredEffectPublicationPlan({acquired, ...evidence[0],
        captureStartedAt, captureCompletedAt});
    signal?.throwIfAborted();
    const checkedHost = multiple
      ? moon.clientProgramOpenMultiCapturedLocalEffectHost(owner,
        captures.map(value => value.capture.source()), ledger,
        registry, values, fragment, ordered)
      : moon.clientProgramOpenCapturedLocalEffectHost(owner,
        captures[0].capture.source(), registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
    if (checkedHost === undefined) {
      throw new Error('InstalledEffectProgramUnsupported');
    }
    // Without a returned Compute owner an exception cannot prove a stop.
    // Keep the responsibility rather than relabeling it as released.
    unresolved = true;
    if (multiple) {
      const dag = moon.strategyHostRun(moon.clientProgramLocalEffectHostRuntime(checkedHost));
      for (const [task, captured] of captures.entries()) captured.capture.retainTask(dag, task);
    }
    execution = await runCapturedEffectComputation(checkedHost,
      {authorization: multiple ? undefined : sourceAccess?.authorization}, signal);
    unresolved = false;
    if (execution.status !== 'host-tasks-completed') {
      throw execution.failure ?? new Error('InstalledEffectComputationFailed');
    }
    return Object.freeze({execution, checkedHost, publicationPlan,
      cleanupOwner: custody});
  } finally {
    settled = true;
  }
}
