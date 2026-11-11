// Shared private custody for the existing installed Model component. Local
// and Effect-free Runs keep their own execution/publication owners; accepted
// captures, attempt proofs and Store writes follow this same persistence path.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';

const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});

export function openNodeInferCaptureCustody({moon, control, operation, plan,
  store, storeAuthorityCid, sourceEvidence = [], replay = false, faultInjection,
  publicationFor, durableCalls = false, captureOnly = false}) {
  if ((!captureOnly && typeof publicationFor !== 'function') ||
      captureOnly && !durableCalls || !Array.isArray(sourceEvidence)) {
    throw new TypeError('InvalidInferCaptureCustody');
  }
  let issuance, publication, capture, exporter, captureOutput, count;
  let reclaimed = false;
  let pendingHolding;
  let captureStored = false;
  let capturePersisted = false;
  let issuanceComplete = false;
  let persistCapture;
  let attemptsStored = false;
  let sourceStored = false;
  let settling;
  let observeModelEntry;
  let modelEntryFor;
  let durableSettlements = new Map();
  let cleanupFlight;
  let publicationCleanupFlight, publicationRetirementFlight;
  let publicationCleaned = false, publicationRetired = false;
  let storedCaptureWireLimit;

  // Same immutable original Store extent, before constructing its exporter.
  // This scalar is not funding, persistence, currentness or a cleanup ACK.
  // Cache a known zero as zero; absence/invalid DATA never defaults to1MiB.
  function maximumStoredCaptureWire() {
    if (storedCaptureWireLimit !== undefined) return storedCaptureWireLimit;
    const select = store.privateEvidenceWireLimit;
    if (typeof select !== 'function') {
      throw Object.assign(new Error('InstalledInferCaptureStoreWireLimitUnavailable'),
        {code: 'InstalledInferCaptureStoreWireLimitUnavailable'});
    }
    const limit = Reflect.apply(select, store, []);
    if (!Number.isSafeInteger(limit) || limit < 0) {
      throw Object.assign(new Error('InstalledInferCaptureStoreWireLimitUnavailable'),
        {code: 'InstalledInferCaptureStoreWireLimitUnavailable'});
    }
    storedCaptureWireLimit = Math.min(1048576, limit);
    return storedCaptureWireLimit;
  }

  // Retire only this adapter's aliases after its existing physical/Core
  // cleanup succeeds. Durable Store originals and previously transferred
  // immutable views retain their own custody; this does not erase them or
  // claim that GC has reclaimed their backing allocations.
  function retirePublicationAliases() {
    wire = '';
    modelEvidence = undefined;
    durableSettlements = undefined;
    observeModelEntry = undefined;
    modelEntryFor = undefined;
    settling = undefined;
    pendingHolding = undefined;
    sourceEvidence = undefined;
    publicationFor = undefined;
    faultInjection = undefined;
    storedCaptureWireLimit = undefined;
    publicationRetired = true;
  }
  function retireAliases() {
    retirePublicationAliases();
    operation = undefined;
    plan = undefined;
    control = undefined;
    store = undefined;
    moon = undefined;
  }

  // A failed write retains its exact physical owner. Cleanup retries only
  // that write, never operation.run or the provider.
  const cleanupPublicationOwned = async () => {
    if (publicationCleaned) return true;
    if (!operation.physicalStopped()) return false;
    if (settling !== undefined) await persistSettlement();
    // Once a response has been accepted, reclamation cannot discard it
    // merely because a private write failed. Resume persistence of the same
    // common-owned evidence; this never reruns Compute or dispatch.
    if (capture !== undefined && !capturePersisted) {
      await persistCapture(false);
    }
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
    publicationCleaned = true;
    return true;
  };
  const cleanupPublication = () => {
    // Both the normal parent cleanup and the private byte-borrow caller use
    // this same physical child flight. A pending/failed write or exporter
    // keeps its original responsibility and permits retry of only that child.
    if (publicationCleanupFlight !== undefined) return publicationCleanupFlight;
    publicationCleanupFlight = cleanupPublicationOwned().then(value => {
      if (!value) publicationCleanupFlight = undefined;
      return value;
    }, error => { publicationCleanupFlight = undefined; throw error; });
    return publicationCleanupFlight;
  };
  const retirePublication = () => {
    // This is local alias retirement, not Model cleanup or a capacity grant.
    // Its existing same-Ledger borrower is released separately, BEFORE the
    // parent Model cleanup that waits for that borrow's output use. The parent
    // operation/Store/Core originals remain retained for pending final cleanup.
    if (publicationRetirementFlight !== undefined) return publicationRetirementFlight;
    publicationRetirementFlight = cleanupPublication().then(value => {
      if (value) retirePublicationAliases();
      else publicationRetirementFlight = undefined;
      return value;
    }, error => { publicationRetirementFlight = undefined; throw error; });
    return publicationRetirementFlight;
  };
  const cleanupOwned = async () => {
    if (reclaimed) return true;
    if (!await cleanupPublication()) return false;
    for (;;) {
      const before = operation.cleanupProgress?.();
      reclaimed = operation.cleanup();
      if (reclaimed) { retireAliases(); return true; }
      if (operation.cleanupProgress?.() === before) return false;
      // The common owner released one more physical cursor. Yield before
      // advancing cleanup again; an unchanged/pending cursor remains owned.
      await yieldEventLoop();
    }
  };
  const cleanup = () => {
    // Several existing parents may observe the same pending cleanup. Do not
    // let a second await race the first owner's final alias retirement.
    // Keep the successful flight stable; false/rejection permits retry of
    // the same original responsibility, never persistence or dispatch anew.
    if (cleanupFlight !== undefined) return cleanupFlight;
    cleanupFlight = cleanupOwned().then(value => {
      if (!value) cleanupFlight = undefined;
      return value;
    }, error => { cleanupFlight = undefined; throw error; });
    return cleanupFlight;
  };
  const custody = Object.freeze({cleanup, retirePublication,
    cleanupPending: () => !reclaimed,
    async close() {
      if (reclaimed) return;
      // Stop without reclaiming: failed executions still own attempt proofs
      // that must reach private custody before the model owner is released.
      await operation.stop();
      if (!await cleanup()) throw pending();
    }});
  function retainCompleted(publicationOriginal = operation) {
    if (reclaimed || publicationCleaned) throw new Error('InstalledInferCaptureUnavailable');
    if (capture !== undefined) return true;
    // The actual original operation selects and reserves terminal publication
    // capacity before these additional captures/exporters/metadata are built.
    // Its initial record and per-slot/raw phases require earlier startup funds.
    publicationOriginal.reserveOriginalPublicationCapacity?.();
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
  async function holdAttachments(slot, entry, phase) {
    const admission = operation.issuedAttachmentAdmission(slot);
    if (admission !== undefined) {
      await holdEvidence('model_attachment_admission', slot, admission, entry, phase);
    }
  }
  async function persistStoppedAttempts() {
    if (reclaimed || publicationCleaned) return;
    if (attemptsStored) return;
    await persistSourceObservation();
    const attempts = operation.stoppedAttemptCount();
    if (!Number.isInteger(attempts) || attempts < 0 || attempts > 128) {
      throw new Error('InstalledInferAttemptInventoryUnavailable');
    }
    for (let index = 0; index < attempts; index++) {
      const slot = operation.stoppedAttemptSlot?.(index) ?? index;
      const entry = durableCalls ? modelEntryFor?.(slot) : undefined;
      // This same custody already persisted AND acknowledged that exact
      // attempt. A completed Model refuses the stopped-only usage reader;
      // do not reopen it merely because publication was never acquired.
      // Other/unknown attempts still retire their original reader below.
      if (entry !== undefined) {
        const acknowledgedAttempt = durableSettlements.get(slot);
        if (acknowledgedAttempt !== undefined && acknowledgedAttempt === entry.attemptCid) continue;
      }
      if (typeof operation.advanceStoppedAttemptUsage !== 'function') {
        throw new Error('InstalledInferRawUsageUnavailable');
      }
      // Persist only after the original Common usage child has retired.
      // Common preserves partials and reader issues on the same attempt; JS
      // neither decodes raw bytes nor classifies a stopped outcome as success.
      for (;;) {
        const progress = operation.advanceStoppedAttemptUsage(slot, 1);
        if (typeof progress?.complete !== 'boolean') {
          throw new Error('InstalledInferRawUsageUnavailable');
        }
        if (progress.complete) break;
        await yieldEventLoop();
      }
      const proof = operation.attemptEvidence(slot);
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
      await holdAttachments(slot, entry, durableCalls && !terminalFailure ? 'entered' : undefined);
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
    await holdAttachments(slot, current.entry);
    await holdEvidence('model_slot_capture', slot, operation.issuedSlotCapture(slot), current.entry);
    const observation = operation.invocationEvidenceView(control, slot);
    if (observation !== undefined) {
      await hold('model_invocation_evidence', slot, observation.wire,
        observation.identity, current.entry);
    }
    current.exporter ??= checked(moon.clientProgramStartInferCallSettlementExport(
      current.settlement, maximumStoredCaptureWire(), 1000000));
    while (!current.complete) {
      const progress = checked(moon.clientProgramAdvanceInferCaptureExport(current.exporter, 256));
      current.wire += runtimeField(progress, 1);
      current.complete = runtimeField(progress, 0);
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
    // Store observation alone is not this same Common settlement ACK.
    // Failed cleanup/ACK must keep the stopped-reader responsibility above.
    durableSettlements.set(slot, current.entry.attemptCid);
    // Both original duties succeeded. Retire only this record's aliases even
    // if its completed async frame remains reachable; Store/Core originals
    // and a later terminal export retain their independent lifetimes.
    current.exporter = undefined;
    current.wire = '';
    settling = undefined;
    return observed;
  }
  let modelEvidence = [];
  let wire = '';
  let exportComplete = false;
  persistCapture = async (preparePublication = true) => {
    if (captureStored) return;
    if (!capturePersisted) {
      await persistSourceObservation();
      modelEvidence.length = 0;
      for (let slot = 0; slot < count; slot++) {
        if (captureOnly) {
          const entry = modelEntryFor?.(slot);
          if (entry === undefined || durableSettlements.get(slot) !== entry.attemptCid) {
            throw new Error('InferSettlementNotDurable');
          }
        }
        // Replay already adopted verified slot records and their original
        // attempt proofs. It must not issue a new physical attempt or accounting.
        if (!replay && !captureOnly) {
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
          await holdAttachments(slot);
          const adopted = operation.issuedSlotCapture(slot);
          checked(moon.clientProgramBindInferSlotCapture(capture, slot, adopted));
          await holdEvidence('model_slot_capture', slot, adopted);
        }
        const evidence = operation.invocationEvidenceView(control, slot);
        if (evidence !== undefined) {
          modelEvidence.push(evidence);
        }
      }
      // captureOnly's whole bundle is not stored in this per-slot cell. Keep
      // its existing bound; do not mistake a different Store's extent for it.
      exporter ??= checked(moon.clientProgramStartInferCaptureExport(capture,
        captureOnly ? 1048576 : maximumStoredCaptureWire(), 1000000));
      while (!exportComplete) {
        const progress = checked(moon.clientProgramAdvanceInferCaptureExport(
          exporter, 256));
        wire += runtimeField(progress, 1);
        if (runtimeField(progress, 0)) { exportComplete = true; break; }
        await yieldEventLoop();
      }
      if (captureOnly) {
        // Each original slot already reached scoped private Store custody at
        // Settling. Multiple components must not compete for the legacy single
        // whole-bundle cell. The complete Run issuer is retained by the parent.
        capturePersisted = true;
        captureStored = true;
        return;
      }
      await hold('model_capture_bundle', -1, wire,
        moon.clientProgramInferCaptureExportIdentity(exporter));
      capturePersisted = true;
    }
    // A failed semantic projection cannot make first close reconstruct it.
    // Preserve the SAME accepted capture in Store, then release the existing
    // issuer/exporter/output owners. Any pending physical write remains owned
    // by pendingHolding below; no publication or Run success is fabricated.
    if (!preparePublication) return;
    if (publication === undefined) {
      // A persistence retry must keep the original issuer, its reservations
      // and progress, including completion before the publication binding.
      if (issuance === undefined) {
        issuance = operation.startObservation({maxSlots: count,
          maxWireBytes: 16384, maxWork: count + 2});
      }
      while (!issuanceComplete) {
        issuanceComplete = runtimeField(checked(
          moon.clientProgramAdvanceInferObservationIssuance(issuance, 1)), 0);
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
    // Count of the actual retained completed capture, not a persistence proof
    // or publication grant. The same Core issuer verifies the complete slots.
    completedCallCount() {return capture !== undefined && !publicationCleaned && !reclaimed ? count : undefined;},
    modelEvidence() {return !publicationRetired && !reclaimed && captureStored ? Object.freeze([...modelEvidence]) : undefined;},
    // This immutable original is available only after the existing Store
    // commit. It conveys no read/capture permission and retains no new owner.
    evaluationBundle() {
      if (!captureStored || !exportComplete || reclaimed || publicationCleaned) return undefined;
      const calls = [];
      for (let slot = 0; slot < count; slot++) {
        const call = moon.clientProgramInferCaptureCall(capture, slot);
        const outcome = moon.clientProgramInferCaptureOutcome(capture, slot);
        if (call === undefined || outcome === undefined) return undefined;
        calls.push(Object.freeze({slotCid: moon.strategyRunEvidenceIdentity(call),
          callWire: moon.strategyRunEvidenceJson(call), outcome}));
      }
      return Object.freeze({wire, cid: moon.clientProgramInferCaptureExportIdentity(exporter), count,
        calls: Object.freeze(calls)});
    },
    configureModelJournal({observe, entry}) {
      if (publicationCleaned || reclaimed || !durableCalls || typeof observe !== 'function' || observeModelEntry !== undefined) {
        throw new TypeError('InvalidInferModelJournal');
      }
      if (typeof entry !== 'function') throw new TypeError('InvalidInferModelEntryReader');
      observeModelEntry = observe;
      modelEntryFor = entry;
      operation.installSettlementCleanup(async settlement => {
        if (publicationCleaned || reclaimed) throw new Error('ForeignInferSettlement');
        const receipt = entry(operation.settlementSlot(settlement));
        if (receipt === undefined) throw new Error('InferSettlementEntryMissing');
        settling ??= {settlement, entry: receipt, wire: '', complete: false};
        return persistSettlement();
      });
    },
    async persistSettlement(settlement, entry) {
      if (publicationCleaned || reclaimed || !durableCalls || settling !== undefined &&
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
