// Installed physical composition of the existing checked Infer, observation
// and publication owners. It neither interprets a Program nor issues proof JSON.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {preparePrivatePublicationHolding} from
  '../host-common/private-publication-holding.mjs';
import {publishCompletedEffectFreeRun} from
  '../host-common/completed-run-publication.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {inferTaskPublicationPlan} from './local-values-plan.mjs';
import {inferPublicationExecution} from './infer-result-publication.mjs';
import {readInstalledInferCapture} from './installed-infer-capture.mjs';

const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});

export function installNodeInferRun({moon, core, registry, values, selections,
  namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection}) {
  const control = core.publicationControl;
  return async ({preparedProgram, plan, store, principalId, signal,
    retainExecution, replay = false, beginPhysicalWork = () => {}}) => {
    const selected = selections.get(preparedProgram);
    if (selected === undefined || selected.graph !== plan.inferGraph) {
      throw new Error('InstalledInferSelectionMissing');
    }
    const savedSlots = replay ? await readInstalledInferCapture({moon,
      control, store, compiled: plan.compiled, runDefinition: plan.runDefinition,
      storeAuthorityCid, signal}) : undefined;
    let operation;
    try {
      operation = openNodeInferOperation({moon, preparedProgram,
        step: selected.step, graph: selected.graph, registry, values, signal,
        ...(replay ? {savedSlots} : {provider: selected.provider,
          quantityCapacity: selected.quantityCapacity,
          physicalPreflight: selected.physicalPreflight,
          egressAdmission: selected.egressAdmission})});
    } finally {
      if (savedSlots !== undefined) {
        moon.clientProgramReleaseInferSlotReplay(savedSlots);
      }
    }
    let issuance, publication, capture, exporter, captureOutput;
    let reclaimed = false;
    let pendingHolding;
    let captureStored = false;
    let issuanceComplete = false;
    let persistCapture;
    let attemptsStored = false;
    // A failed write retains its exact physical owner. Cleanup retries only
    // that write, never operation.run or the provider.
    const cleanup = async () => {
      if (reclaimed) return true;
      if (!operation.physicalStopped()) return false;
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
      reclaimed = operation.cleanup();
      return reclaimed;
    };
    retainExecution(Object.freeze({cleanup,
      cleanupPending: () => !reclaimed,
      async close() {
        // Stop without reclaiming: failed executions still own attempt proofs
        // that must reach private custody before the model owner is released.
        await operation.stop();
        if (!await cleanup()) throw pending();
      }}));
    beginPhysicalWork();
    operation.bindRun(control, plan);
    if (!replay) {
      operation.bindDispatch(control, {...plan, account: selected.account,
        principalId, at: now(), observeAccount: selected.observeAccount,
        observeAt: now});
    }
    await operation.run();
    // Observation issuance also needs the completed Relation. Keep its own
    // use across failed persistence, before close can begin child cleanup.
    captureOutput = operation.acquireOutput();
    if (captureOutput === undefined) throw new Error('InstalledInferOutputUnavailable');
    capture = operation.acquireCapture();
    const count = moon.clientProgramInferCaptureCallCount(capture);
    if (!Number.isInteger(count) || count < 0 || count > 128) {
      throw new Error('InstalledInferCaptureInventoryUnavailable');
    }
    async function hold(name, slot, wire, semanticCid) {
      if (pendingHolding !== undefined) {
        await pendingHolding.commit();
        pendingHolding = undefined;
      }
      pendingHolding = preparePrivatePublicationHolding(store, {name, wire,
        semanticCid, holdingCid: control.modelPrivateHoldingCid(
          plan.runDefinition, storeAuthorityCid, name, slot)});
      await faultInjection?.('infer_private_holding_commit', {role: name, slot});
      await pendingHolding.commit();
      pendingHolding = undefined;
    }
    async function holdEvidence(name, slot, evidence) {
      const wire = moon.strategyRunEvidenceJson(evidence);
      const admitted = control.admitRunEvidence(name, wire,
        {maxWireBytes: 16384, maxNodes: 1024, maxDepth: 20});
      await hold(name, slot, admitted.wire, admitted.identity);
      return admitted;
    }
    async function persistStoppedAttempts() {
      if (attemptsStored) return;
      const attempts = operation.stoppedAttemptCount();
      if (!Number.isInteger(attempts) || attempts < 0 || attempts > 128) {
        throw new Error('InstalledInferAttemptInventoryUnavailable');
      }
      for (let slot = 0; slot < attempts; slot++) {
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
        await yieldEventLoop();
      }
      attemptsStored = true;
    }
    const modelEvidence = [];
    let wire = '';
    let exportComplete = false;
    persistCapture = async () => {
      if (captureStored) return;
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
        publication = inferTaskPublicationPlan({moon, control, preparedProgram,
          admitted: plan, operation, issuance, modelEvidence, namespaceId,
          authorityScopeCid, storeAuthorityCid, now});
      }
      await hold('observation_set', -1, publication.observation.wire,
        publication.observation.identity);
      await hold('run_invocation', -1, publication.invocation.wire,
        publication.invocation.identity);
      captureStored = true;
    };
    await persistCapture();
    await faultInjection?.('infer_capture_committed', {});
    signal.throwIfAborted();
    const execution = inferPublicationExecution({moon, core, operation,
      binding: publication.binding, compiled: plan.compiled, preparedProgram});
    await publishCompletedEffectFreeRun({...publication.plan, execution,
      store, control, signal});
  };
}
