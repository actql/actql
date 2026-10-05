// Shared private custody for the existing installed Model component. Local
// and Effect-free Runs keep their own execution/publication owners; accepted
// captures, attempt proofs and Store writes follow this same persistence path.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';

const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});

export function openNodeInferCaptureCustody({moon, control, operation, plan,
  store, storeAuthorityCid, sourceEvidence = [], replay = false, faultInjection,
  publicationFor, durableCalls = false}) {
  if (typeof publicationFor !== 'function' || !Array.isArray(sourceEvidence)) {
    throw new TypeError('InvalidInferCaptureCustody');
  }
  let issuance, publication, capture, exporter, captureOutput, count;
  let reclaimed = false;
  let pendingHolding;
  let captureStored = false;
  let issuanceComplete = false;
  let persistCapture;
  let attemptsStored = false;
  let sourceStored = false;
  let settling;
  let observeModelEntry;
  let modelEntryFor;

  // A failed write retains its exact physical owner. Cleanup retries only
  // that write, never operation.run or the provider.
  const cleanup = async () => {
    if (reclaimed) return true;
    if (!operation.physicalStopped()) return false;
    if (settling !== undefined) await persistSettlement();
    // Once a response has been accepted, reclamation cannot discard it
    // merely because a private write failed. Resume persistence of the same
    // common-owned evidence; this never reruns Compute or dispatch.
    if (capture !== undefined && !captureStored) await persistCapture();
    if (capture === undefined && !replay) await persistStoppedAttempts();
    if (pendingHolding !== undefined) {
      await pendingHolding.commit();
      pendingHolding = undefined;
    }
    if (publication !== undefined) {
      moon.clientProgramReleaseInferInvocationBinding(publication.binding);
      publication = undefined;
    }
    if (issuance !== undefined) {
      if (moon.clientProgramCancelInferObservationIssuance(issuance)) {
        checked(moon.clientProgramAdvanceInferObservationIssuance(issuance, 1));
      }
      if (!checked(moon.clientProgramCleanupInferObservationIssuance(issuance))) {
        return false;
      }
      issuance = undefined;
    }
    if (exporter !== undefined) {
      if (moon.clientProgramCancelInferCaptureExport(exporter)) {
        checked(moon.clientProgramAdvanceInferCaptureExport(exporter, 1));
      }
      if (!checked(moon.clientProgramCleanupInferCaptureExport(exporter))) {
        return false;
      }
      exporter = undefined;
    }
    if (capture !== undefined) {
      moon.clientProgramReleaseInferCapture(capture);
      capture = undefined;
    }
    if (captureOutput !== undefined) {
      moon.clientProgramReleaseInferOutput(captureOutput);
      captureOutput = undefined;
    }
    for (;;) {
      const before = operation.cleanupProgress?.();
      reclaimed = operation.cleanup();
      if (reclaimed || operation.cleanupProgress?.() === before) return reclaimed;
      // The common owner released one more physical cursor. Yield before
      // advancing cleanup again; an unchanged/pending cursor remains owned.
      await yieldEventLoop();
    }
  };
  const custody = Object.freeze({cleanup,
    cleanupPending: () => !reclaimed,
    async close() {
      // Stop without reclaiming: failed executions still own attempt proofs
      // that must reach private custody before the model owner is released.
      await operation.stop();
      if (!await cleanup()) throw pending();
    }});
  function retainCompleted() {
    if (capture !== undefined) return true;
    captureOutput ??= operation.acquireOutput();
    if (captureOutput === undefined) throw new Error('InstalledInferOutputUnavailable');
    capture = operation.acquireCapture();
    count = moon.clientProgramInferCaptureCallCount(capture);
    if (!Number.isInteger(count) || count < 0 || count > 128) {
      throw new Error('InstalledInferCaptureInventoryUnavailable');
    }
    return true;
  }
  async function hold(name, slot, wire, semanticCid, entry, phase = 'settled') {
    if (pendingHolding !== undefined) {
      await pendingHolding.commit();
      pendingHolding = undefined;
    }
    pendingHolding = preparePrivatePublicationHolding(store, {name, wire,
      semanticCid, holdingCid: entry === undefined
        ? control.modelPrivateHoldingCid(plan.runDefinition, storeAuthorityCid, name, slot)
        : control.modelScopedPrivateHoldingCid(plan.runDefinition, storeAuthorityCid, entry, name, phase)});
    await faultInjection?.('infer_private_holding_commit', {role: name, slot});
    await pendingHolding.commit();
    pendingHolding = undefined;
  }
  async function holdEvidence(name, slot, evidence, entry, phase) {
    const wire = moon.strategyRunEvidenceJson(evidence);
    const admitted = control.admitRunEvidence(name, wire,
      {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});
    await hold(name, slot, admitted.wire, admitted.identity, entry, phase);
    return admitted;
  }
  async function persistStoppedAttempts() {
    if (attemptsStored) return;
    await persistSourceObservation();
    const attempts = operation.stoppedAttemptCount();
    if (!Number.isInteger(attempts) || attempts < 0 || attempts > 128) {
      throw new Error('InstalledInferAttemptInventoryUnavailable');
    }
    for (let index = 0; index < attempts; index++) {
      const slot = operation.stoppedAttemptSlot?.(index) ?? index;
      const proof = operation.attemptEvidence(slot);
      const entry = durableCalls ? modelEntryFor?.(slot) : undefined;
      let terminalFailure = false;
      if (durableCalls) {
        const outcome = JSON.parse(moon.strategyRunEvidenceJson(
          moon.clientProgramInferAttemptLeaf(proof, 'outcome')));
        // Adopted responses/failures reached their settled Store cells before
        // the next send. A stopped unknown keeps separate entered-phase proof.
        if (['ok', 'provider_failure'].includes(outcome.category)) continue;
        terminalFailure = outcome.category === 'contract_violation';
        if (entry === undefined) throw new Error('InferStoppedAttemptEntryMissing');
      }
      for (const [kind, name] of [
        ['attempt', 'model_call_attempt'],
        ['accounting', 'model_attempt_accounting'],
        ['outcome', 'model_attempt_outcome'],
        ['authority', 'model_dispatch_authority'],
      ]) {
        await holdEvidence(name, slot,
          moon.clientProgramInferAttemptLeaf(proof, kind), entry,
          durableCalls && !terminalFailure ? 'entered' : undefined);
      }
      if (terminalFailure) await observeModelEntry(entry);
      await yieldEventLoop();
    }
    attemptsStored = true;
  }
  async function persistSourceObservation() {
    if (sourceStored) return;
    for (const [slot, evidence] of sourceEvidence.entries()) {
      await hold('source_evidence', slot, evidence.wire, evidence.identity);
    }
    sourceStored = true;
  }
  async function persistSettlement() {
    if (settling === undefined) throw new Error('InferSettlementMissing');
    const current = settling;
    const slot = operation.settlementSlot(current.settlement);
    if (slot !== current.entry.ordinal) throw new Error('InferSettlementBindingMismatch');
    await persistSourceObservation();
    const proof = operation.attemptEvidence(slot);
    for (const [kind, name] of [
      ['attempt', 'model_call_attempt'], ['accounting', 'model_attempt_accounting'],
      ['outcome', 'model_attempt_outcome'], ['authority', 'model_dispatch_authority'],
    ]) {
      await holdEvidence(name, slot, moon.clientProgramInferAttemptLeaf(proof, kind), current.entry);
    }
    await holdEvidence('model_slot_capture', slot, operation.issuedSlotCapture(slot), current.entry);
    const observation = operation.invocationEvidence(slot);
    if (observation !== undefined) {
      await holdEvidence('model_invocation_evidence', slot, observation, current.entry);
    }
    current.exporter ??= checked(moon.clientProgramStartInferCallSettlementExport(
      current.settlement, 1048576, 1000000));
    while (!current.complete) {
      const progress = checked(moon.clientProgramAdvanceInferCaptureExport(current.exporter, 256));
      current.wire += progress._1;
      current.complete = progress._0;
      if (!current.complete) await yieldEventLoop();
    }
    await hold('model_capture_bundle', slot, current.wire,
      moon.clientProgramInferCaptureExportIdentity(current.exporter), current.entry);
    await faultInjection?.('infer_model_response_stored', {slot,
      scopeCid: current.entry.scopeCid, attemptCid: current.entry.attemptCid});
    if (typeof observeModelEntry !== 'function') throw new Error('InferSettlementObserverMissing');
    const observed = await observeModelEntry(current.entry);
    if (!['SavedSuccess', 'SavedFailure'].includes(observed?.state)) {
      throw new Error('InferSettlementNotDurable');
    }
    await faultInjection?.('infer_model_settlement_committed', {slot,
      scopeCid: current.entry.scopeCid, attemptCid: current.entry.attemptCid, state: observed.state});
    if (!checked(moon.clientProgramCleanupInferCaptureExport(current.exporter))) throw pending();
    operation.acknowledgeSettlement(current.settlement);
    settling = undefined;
    return observed;
  }
  const modelEvidence = [];
  let wire = '';
  let exportComplete = false;
  persistCapture = async () => {
    if (captureStored) return;
    await persistSourceObservation();
    modelEvidence.length = 0;
    for (let slot = 0; slot < count; slot++) {
      // Replay already adopted verified slot records and their original
      // attempt proofs. It must not issue a new physical attempt or accounting.
      if (!replay) {
        const proof = operation.attemptEvidence(slot);
        for (const [kind, name] of [
          ['attempt', 'model_call_attempt'],
          ['accounting', 'model_attempt_accounting'],
          ['outcome', 'model_attempt_outcome'],
          ['authority', 'model_dispatch_authority'],
        ]) {
          await holdEvidence(name, slot,
            moon.clientProgramInferAttemptLeaf(proof, kind));
        }
        const adopted = operation.issuedSlotCapture(slot);
        checked(moon.clientProgramBindInferSlotCapture(capture, slot, adopted));
        await holdEvidence('model_slot_capture', slot, adopted);
      }
      const evidence = operation.invocationEvidence(slot);
      if (evidence !== undefined) {
        modelEvidence.push(control.admitRunEvidence('model_invocation_evidence',
          moon.strategyRunEvidenceJson(evidence),
          {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20}));
      }
    }
    exporter ??= checked(moon.clientProgramStartInferCaptureExport(capture,
      1048576, 1000000));
    while (!exportComplete) {
      const progress = checked(moon.clientProgramAdvanceInferCaptureExport(
        exporter, 256));
      wire += progress._1;
      if (progress._0) { exportComplete = true; break; }
      await yieldEventLoop();
    }
    await hold('model_capture_bundle', -1, wire,
      moon.clientProgramInferCaptureExportIdentity(exporter));
    if (publication === undefined) {
      // A persistence retry must keep the original issuer, its reservations
      // and progress, including completion before the publication binding.
      if (issuance === undefined) {
        const ledger = checked(moon.clientProgramInferPublicationLedger(
          262144n + BigInt(count) * 128n, count + 2));
        issuance = operation.startObservation({ledger, maxSlots: count,
          maxWireBytes: 16384, maxWork: count + 2});
      }
      while (!issuanceComplete) {
        issuanceComplete = checked(
          moon.clientProgramAdvanceInferObservationIssuance(issuance, 1))._0;
        await faultInjection?.('infer_observation_advanced', {
          complete: issuanceComplete,
        });
        if (!issuanceComplete) await yieldEventLoop();
      }
      publication = publicationFor({operation, issuance, modelEvidence});
    }
    await hold('observation_set', -1, publication.observation.wire,
      publication.observation.identity);
    await hold('run_invocation', -1, publication.invocation.wire,
      publication.invocation.identity);
    captureStored = true;
  };
  return Object.freeze({custody, retainCompleted, persistStoppedAttempts,
    configureModelJournal({observe, entry}) {
      if (!durableCalls || typeof observe !== 'function' || observeModelEntry !== undefined) {
        throw new TypeError('InvalidInferModelJournal');
      }
      if (typeof entry !== 'function') throw new TypeError('InvalidInferModelEntryReader');
      observeModelEntry = observe;
      modelEntryFor = entry;
      operation.installSettlementCleanup(async settlement => {
        const receipt = entry(operation.settlementSlot(settlement));
        if (receipt === undefined) throw new Error('InferSettlementEntryMissing');
        settling ??= {settlement, entry: receipt, wire: '', complete: false};
        return persistSettlement();
      });
    },
    async persistSettlement(settlement, entry) {
      if (!durableCalls || settling !== undefined &&
          (operation.settlementSlot(settling.settlement) !== operation.settlementSlot(settlement) ||
            settling.entry.attemptCid !== entry.attemptCid)) {
        throw new Error('ForeignInferSettlement');
      }
      settling ??= {settlement, entry, wire: '', complete: false};
      return persistSettlement();
    },
    async persist() {
      if (capture === undefined) throw new Error('InstalledInferCaptureUnavailable');
      await persistCapture();
      return publication;
    }});
}
