// Compose the existing original prefix, keyed Row receiver and Content
// custody. The caller retains this duty before any asynchronous Source work.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {installedSourceFor} from './installed-source.mjs';

export async function prepareAcquiredEffectKeyedPrefix({moon, acquired, managedRun,
  infer, selected, originalPreparation, plan, captures, sourceProfile, ledger,
  contentRun, store, principalId, signal, now, current, retain}) {
  const acquisition = checked(moon.clientProgramEffectComposedModelKeyedAcquisition(
    acquired.prepared, infer.graph));
  if (acquisition === undefined) return undefined;
  if (captures.length !== 2 || selected === undefined || originalPreparation?.scope === undefined ||
      plan?.compiled === undefined || typeof retain !== 'function') {
    throw new TypeError('InstalledComposedKeyedOriginalUnavailable');
  }
  let prefix, execution, lookup, keyedContent, failureRecovery, uncertain = false, closed = false;
  const cleanup = async () => {
    if (closed) return true;
    if (uncertain) return false;
    if (failureRecovery !== undefined) {
      await failureRecovery.close();
      if (await failureRecovery.cleanup() === false || failureRecovery.cleanupPending() !== false) return false;
      failureRecovery = undefined;
    }
    if (lookup !== undefined) {
      await lookup.close();
      if (await lookup.cleanup() === false || lookup.cleanupPending() !== false) return false;
      lookup = undefined;
    }
    if (keyedContent !== undefined) {
      if (await keyedContent.cleanup() === false || keyedContent.cleanupPending() !== false) return false;
      keyedContent = undefined;
    }
    if (execution !== undefined) {
      moon.clientProgramSerializationPrefixCancel(execution);
      if (checked(moon.clientProgramSerializationPrefixCleanup(execution)) !== true) return false;
      execution = undefined; prefix = undefined;
    }
    closed = true;
    return true;
  };
  retain(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !closed}));
  current();
  const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(acquisition));
  const adapter = installedSourceFor(sourceProfile, facts[0]);
  const access = adapter.sourceAccess;
  const capacity = adapter.keyedLedgerCapacity(acquisition);
  prefix = acquired.control.startInstalledOriginalComposedKeyedPrefix(managedRun,
    plan.compiled, plan.runDefinition, infer.graph, originalPreparation.scope, acquisition, captures);
  execution = moon.clientProgramOriginalComposedKeyedPrefixExecution(prefix);
  current();
  for (;;) {
    signal?.throwIfAborted();
    const poll = checked(moon.clientProgramOriginalComposedKeyedPrefixAdvance(prefix, 64));
    current();
    if (runtimeField(poll, 0)) break;
    if (runtimeField(poll, 2) !== undefined) {
      throw Object.assign(new Error('InstalledComposedKeyedPrefixFailed'),
        {code: 'MoonBitHostFailure', cause: runtimeField(poll, 2)});
    }
    if (runtimeField(poll, 1)) throw new Error('InstalledComposedKeyedPrefixStopped');
    await yieldEventLoop();
  }
  const left = checked(moon.clientProgramCompleteOriginalComposedKeyedPrefix(prefix));
  const prepared = await adapter.prepareKeyed({preparedEffect: acquired.prepared,
    keyedAcquisition: acquisition, requestIdentity: acquired.requestIdentity, sourceAccess: access});
  current();
  if (adapter.requiresRunContentCapture === true) {
    if (typeof contentRun?.captureKeyed !== 'function') throw new Error('InstalledContentCaptureUnavailable');
    const frame = contentRun.captureKeyed({preparedEffect: acquired.prepared, compilation: acquired.compilation,
      plan, acquisition, ledger, maxBytes: capacity.maxBytes, maxWork: capacity.maxWork,
      sourceBinding: adapter.keyedRecoveryBinding(prepared.prepared), store, principalId, signal,
      inputAvailable: () => {current(); return true;},
      retainExecution: child => {keyedContent = child;}});
    // The actual frame owns its operational methods, while its separately
    // retained child above owns cleanup even if construction fails.
    const child = keyedContent;
    keyedContent = Object.freeze({...child, frame});
  }
  try {
    lookup = await adapter.openKeyedLookup({preparedEffect: acquired.prepared,
      managedRun, keyedAcquisition: acquisition, left, ledger, signal,
      preparedKeyed: prepared.prepared, sourceAccess: access,
      originalCaptures: captures.map(value => value.capture),
      keyedContent: keyedContent?.frame, maxWork: capacity.maxWork});
  } catch (cause) {
    const end = acquisitionEndHandoff().outcome(cause);
    if (end.outcome === 'unknown') {
      failureRecovery = end.recovery;
      uncertain = failureRecovery === undefined;
    }
    throw cause;
  }
  current();
  const observation = await lookup.issueObservation({authorityScopeCid: acquired.authorityScopeCid,
    observedAt: now()});
  current();
  const original = await lookup.borrowSerializationInput();
  current();
  const evidence = acquired.control.keyedLookupPublicationEvidence(observation.observation);
  return Object.freeze({lookup: original, observation: observation.observation, evidence,
    ...(keyedContent === undefined ? {} : {capturedInput: Object.freeze({
      recovery: keyedContent.frame.recoveryInventory(), binding: keyedContent.frame.sourceBinding})})});
}
