// Composition of one installed Effect Site with the common captured Run owner.
// Provider hooks supply only Preview/current-use and physical dispatch facts;
// the common Effect application, receipt, publication and recovery order stays
// here. The Host's durable Run-start and Checkpoint owners remain external.
import {completeCapturedEffectRun, completeRecoveredEffectRun,
  completeInterruptedEffectRun} from
  './entry.mjs';
import {releaseCompletedRunPreparedPayloads,
  suspendCompletedEffectfulComputation} from
  '../host-common/completed-run-publication.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {isEffectApplyPreflightRejection} from './effect-run-apply.mjs';
import {isEffectPreparationRefusal} from '../host-common/effect-preparation-result.mjs';
import {isEffectCaptureRecoveryRefusal} from './effect-run-recovery.mjs';
import {isEffectTargetReadRefusal} from './effect-target-read-continuation.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

function ownedStage(stage, code) {
  if (stage === null || typeof stage !== 'object' ||
      !stage.preview || !stage.computation || !stage.storedResults ||
      !stage.apply || !stage.receipt || !stage.publication ||
      !Array.isArray(stage.scopes) || stage.scopes.length === 0 ||
      typeof stage.continuationWire !== 'string' ||
      stage.dispose !== undefined && typeof stage.dispose !== 'function' ||
      stage.releaseInputs !== undefined && typeof stage.releaseInputs !== 'function') {
    fail(code);
  }
  return stage;
}

function effectUnitId(facts) {
  const unit = facts.compilation === undefined
    ? facts.continuation?.unit_id
    : facts.moon.clientProgramEffectCompilationUnitId(facts.compilation);
  if (typeof unit !== 'string' || !unit ||
      facts.compilation === undefined &&
        (facts.view?.subject?.kind !== 'run_unit' ||
          facts.view.subject.unit_id !== unit)) {
    fail('InstalledEffectContinuationMismatch');
  }
  return unit;
}

function continuation(facts, stage) {
  let provider;
  try { provider = JSON.parse(stage.continuationWire); }
  catch { fail('InvalidInstalledEffectContinuation'); }
  return canonicalJson({version: 'actql-installed-effect-continuation/0.1',
    run_definition_cid: facts.ref.runDefinitionCid,
    unit_id: effectUnitId(facts),
    preview_cid: facts.control.effectComputationPreviewSemanticCid(
      stage.preview),
    ...(facts.targetReads === undefined ? {} : {
      target_read_binding: facts.targetReads.captureBinding()}),
    provider});
}

function checkContinuation(facts, stage) {
  const expected = continuation(facts, stage);
  if (canonicalJson(facts.continuation) !== expected) {
    fail('InstalledEffectContinuationMismatch');
  }
}

function checkContinuationBinding(facts, recovered) {
  effectUnitId(facts);
  const saved = facts.continuation;
  if (saved?.version !== 'actql-installed-effect-continuation/0.1' ||
      saved.run_definition_cid !== facts.ref.runDefinitionCid ||
      saved.preview_cid !== facts.control.effectComputationPreviewSemanticCid(
        recovered.preview)) {
    fail('InstalledEffectContinuationMismatch');
  }
}

function authorization(facts, stage, beforeDefer) {
  const declaredResults = facts.compilation === undefined
    ? facts.retained?.resultNames
    : facts.moon.clientProgramEffectCompilationResultNames(
      facts.compilation);
  if (!Array.isArray(declaredResults) || declaredResults.length === 0) {
    fail('InvalidInstalledEffectResultInventory');
  }
  return facts.effectAuthorization({
    runId: facts.control.runDefinitionRunId(facts.retained?.runDefinition ??
      facts.runDefinition),
    runDefinitionCid: facts.ref.runDefinitionCid,
    unitId: effectUnitId(facts),
    declaredResults,
    reviewWire: facts.control.effectComputationPreviewWire(stage.preview),
    continuationWire: continuation(facts, stage),
    beforeDefer,
    targetReads: facts.targetReads,
  });
}

function completionOptions(stage, gate, signal, resume, beforeDispatch) {
  const apply = {...stage.apply, authorization: Object.freeze({gate,
    scopes: stage.scopes,
    ...(resume === undefined ? {} : {resume})})};
  return Object.freeze({apply, receipt: stage.receipt,
    publication: stage.publication, signal, beforeDispatch});
}

function noEffectRowWasSent(options) {
  const {apply, receipt} = options;
  const control = runtimeCore(apply.moon).effectApplicationControl;
  return receipt.members.every(member => member.rowOwners.every(owner => {
    const entry = apply.ledger.currentAdmitted(
      control.logicalItemLocatorCid(owner.claim.locator));
    return entry !== undefined && control.ledgerEntryStateCode(entry) === 0;
  }));
}

function terminalPreSendRefusal(error, options) {
  return error instanceof ExecutionAuthorizationError &&
      error.authorization?.action === 'deny' ||
    (isEffectApplyPreflightRejection(error) || isEffectPreparationRefusal(error) ||
      isEffectTargetReadRefusal(error)) &&
      noEffectRowWasSent(options);
}

function finishStatus(result) {
  if (result.status === 'waiting') {
    if (result.progress?.checkpoint === undefined) {
      fail('InstalledEffectReadDeferralUnsupported');
    }
    return Object.freeze({status: 'waiting_checkpoint', result});
  }
  return Object.freeze({status: result.status === 'failed'
    ? 'failed_effect_set' : result.status, result});
}

function cleanupCustody(physical, requirePhysical = false) {
  let stage;
  let readAuthorization;
  let disposed = false;
  let release;
  let released = false;
  let inputsReleased = false;
  const releaseInputs = async () => {
    if (!inputsReleased && typeof stage?.releaseInputs === 'function') {
      await stage.releaseInputs();
      inputsReleased = true;
    }
  };
  return Object.freeze({
    expectPhysical() { requirePhysical = true; },
    retainReadAuthorization(owner) {
      if (readAuthorization !== undefined || typeof owner?.close !== 'function') {
        fail('InstalledEffectCleanupOwnerAlreadySet');
      }
      readAuthorization = owner;
    },
    attachPhysical(value) {
      if (physical !== undefined && physical !== value ||
          typeof value?.close !== 'function' ||
          typeof value?.cleanup !== 'function' ||
          typeof value?.cleanupPending !== 'function') {
        fail('InstalledEffectCleanupOwnerAlreadySet');
      }
      physical = value;
    },
    attach(value) {
      if (stage !== undefined) fail('InstalledEffectCleanupOwnerAlreadySet');
      stage = value;
    },
    requireRelease(operation) {
      if (release !== undefined || typeof operation !== 'function') {
        fail('InstalledEffectCleanupOwnerAlreadySet');
      }
      release = operation;
    },
    async close() {
      // Effect execution has stopped before dispatch custody closes. Its
      // consumer pins must go before the borrowed Compute output can reclaim.
      let failure;
      try { readAuthorization?.close(); } catch (error) { failure = error; }
      try { await releaseInputs(); } catch (error) { failure = error; }
      try { await physical?.close(); } catch (error) { failure ??= error; }
      if (failure !== undefined) throw failure;
    },
    async cleanup() {
      // Opening may have begun physical work before returning an owner.
      // Missing custody is not evidence that the operation stopped.
      if (requirePhysical && physical === undefined) return false;
      await releaseInputs();
      const cleaned = await physical?.cleanup() ?? true;
      if (cleaned === false || physical?.cleanupPending() === true) {
        return false;
      }
      if (release !== undefined && !released) {
        await release();
        released = true;
      }
      if (!disposed && typeof stage?.dispose === 'function') {
        await stage.dispose();
      }
      disposed = true;
      return true;
    },
    cleanupPending() {
      return requirePhysical && physical === undefined ||
        physical?.cleanupPending() === true ||
        release !== undefined && !released ||
        !disposed && stage?.dispose !== undefined;
    },
  });
}

function recordUnknown(facts, result, stage) {
  if (result.status !== 'needs_reconciliation') return undefined;
  return facts.recordReconciliation(facts.ref, {issuedSet: result.issuedSet,
    ledger: stage.apply.ledger, preview: stage.preview});
}

async function currentRunState(facts, result, stage) {
  const unknown = recordUnknown(facts, result, stage);
  if (unknown !== undefined) return unknown;
  const observed = await facts.observeRun({ref: facts.ref});
  const {control: _control, ...state} = observed;
  return state;
}

// The installed Host owns this factory. `prepareCaptured` and
// `prepareRecovered` are connector-supplied projections over the same common
// owners; neither hook may decide that an unknown send succeeded or restart
// Compute. The recovered hook receives the exact durable capture only.
export function createInstalledEffectSite({environmentWire,
  prepareCaptured, prepareRecovered, privateEvidenceKey,
  targetReadInventory, targetReadAuthorization,
  claimant = 'installed-effect-host', leaseMs = 60_000}) {
  if (typeof environmentWire !== 'string' || !environmentWire ||
      typeof prepareCaptured !== 'function' ||
      typeof prepareRecovered !== 'function' ||
      targetReadInventory !== undefined && typeof targetReadInventory !== 'function' ||
      (targetReadInventory === undefined) !== (targetReadAuthorization === undefined) ||
      privateEvidenceKey !== undefined &&
        (!(privateEvidenceKey instanceof Uint8Array) ||
          privateEvidenceKey.byteLength !== 32) ||
      typeof claimant !== 'string' || !claimant ||
      !Number.isSafeInteger(leaseMs) || leaseMs < 1) {
    fail('InvalidInstalledEffectSiteFactory');
  }
  return Object.freeze({
    environmentWire,
    targetReadInventory, targetReadAuthorization,
    privateEvidenceKey: privateEvidenceKey === undefined ? undefined :
      Uint8Array.from(privateEvidenceKey),
    async execute(facts) {
      const {moon, retainExecution, signal} = facts;
      signal?.throwIfAborted();
      if (typeof facts.openComputation !== 'function') {
        fail('InvalidInstalledEffectComputationPort');
      }
      const custody = cleanupCustody(undefined);
      retainExecution(custody);
      if (facts.targetReads !== undefined) {
        custody.retainReadAuthorization(facts.targetReads);
        let readiness;
        try { readiness = await facts.targetReads.prepare(); }
        catch (error) { facts.observePreEffectFailure?.(); throw error; }
        if (readiness.status === 'waiting_checkpoint') return readiness;
      }
      custody.expectPhysical();
      facts.beginPhysicalWork?.();
      let opened;
      try {
        facts.targetReads?.enterComputation();
        opened = await facts.openComputation(Object.freeze({
          retainComputationOwner: owner => custody.attachPhysical(owner),
        }));
      } catch (failure) {
        // No Effect provider callback has run. The same failure remains the
        // primary cause; the dispatch owner publishes this terminal outcome
        // only after the physical owner confirms stop and cleanup.
        facts.observePreEffectFailure?.();
        throw failure;
      }
      if (opened?.status === 'waiting_checkpoint' && opened.checkpoint !== undefined) {
        // The Source owner has persisted its exact continuation and retained
        // inputs. Waiting is neither a failed computation nor Effect approval.
        return Object.freeze({status: 'waiting_checkpoint', checkpoint: opened.checkpoint});
      }
      const {execution, checkedHost} = opened ?? {};
      if (execution === undefined || checkedHost === undefined) {
        fail('InvalidInstalledEffectComputationPort');
      }
      // A failed Preview or Store operation still belongs to the dispatch
      // cleanup owner. Retain before any provider callback can fail.
      custody.attachPhysical(opened.cleanupOwner ?? execution);
      // Acquired Runs can issue their Observation Set only after acquisition.
      // The installed Host supplies this plan from the same checked owner.
      if (opened.publicationPlan !== undefined) {
        facts = Object.freeze({...facts,
          publicationPlan: opened.publicationPlan});
      }
      let stage;
      try {
        stage = await prepareCaptured(Object.freeze({...facts,
          execution, checkedHost}));
      } catch (error) {
        // Preparation has no Effect dispatch permit. A checked refusal is
        // definitive here, but observation/transport failures are not. The
        // dispatch owner still waits for physical stop and cleanup before
        // recording the outcome; this does not release that responsibility.
        if (isEffectPreparationRefusal(error) || isEffectTargetReadRefusal(error) ||
            error instanceof ExecutionAuthorizationError &&
              error.authorization?.action === 'deny') {
          facts.observePreEffectFailure?.();
        }
        throw error;
      }
      custody.attach(stage);
      ownedStage(stage, 'InvalidInstalledEffectCapture');
      if (stage.publication.execution !== execution ||
          stage.publication.store !== facts.store ||
          stage.publication.control !== facts.control ||
          stage.publication.storedResults !== stage.storedResults ||
          stage.publication.computation !== stage.computation ||
          stage.publication.preview !== stage.preview ||
          stage.apply.moon !== moon ||
          stage.receipt.commonMoon !== moon) {
        fail('InvalidInstalledEffectCapture');
      }
      let gate;
      try {
        gate = await authorization(facts, stage, async () => {
          // The approved continuation must be able to reconstruct exact
          // claims after process loss. These are durable intents, not send
          // claims; the resumed path still repeats current admission.
          stage.apply.ledger.prepareCapturedSetIntents(
            stage.apply.capturedInputs, stage.apply.members,
            stage.apply.maxFrontierWork);
          await suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
        });
        const options = completionOptions(stage, gate, signal, undefined,
          facts.assertContinuationCurrent);
        let result;
        try { result = await completeCapturedEffectRun(options); }
        catch (error) {
          try { result = await completeInterruptedEffectRun(options, false); }
          catch (completionError) {
            if (completionError?.code === 'EffectRunNoUncertainSend') {
              if (terminalPreSendRefusal(error, options)) {
                custody.requireRelease(() =>
                  releaseCompletedRunPreparedPayloads(
                    stage.storedResults, facts.control));
                return Object.freeze({status: 'failed_without_effect_dispatch'});
              }
              throw error;
            }
            throw completionError;
          }
        }
        if (result.status === 'needs_reconciliation') {
          await suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
        } else if (result.status === 'failed') {
          custody.requireRelease(() => releaseCompletedRunPreparedPayloads(
            stage.storedResults, facts.control));
        }
        recordUnknown(facts, result, stage);
        return finishStatus(result);
      } finally {
        gate?.close();
      }
    },
    async resume(facts) {
      const {signal, ref, view, checkpointJournal, checkpointBinding} = facts;
      signal?.throwIfAborted();
      // The Host resolves this Ref through its original request and current
      // evidence-read authority. No new physical-start claim exists here.
      // Retain custody before a fallible Store read. A failed read or busy
      // claim has not begun a new physical continuation and may be retried.
      const custody = cleanupCustody(undefined);
      facts.retainExecution(custody);
      let recovered;
      try { recovered = await facts.recoverCapture({signal}); }
      catch (error) {
        if (isEffectCaptureRecoveryRefusal(error)) {
          checkpointJournal.refuseUnsentEffectResume(view.checkpointCid,
            ref.runDefinitionCid);
        }
        throw error;
      }
      let releaseMode = 'retain';
      custody.requireRelease(() => releaseMode === 'retire'
        ? releaseCompletedRunPreparedPayloads(
          recovered.computation.storedResults, facts.control)
        : suspendCompletedEffectfulComputation({execution: null,
          store: facts.store,
          storedResults: recovered.computation.storedResults,
          control: facts.control,
          computation: recovered.computation.computation,
          preview: recovered.computation.preview}));
      checkContinuationBinding(facts, recovered.computation);
      const claimed = checkpointJournal.claimResume(view.runId, {
        claimant, leaseMs, binding: checkpointBinding});
      if (claimed.action === 'invalidated') {
        // The journal has durably failed this Run before any Effect send.
        // Transfer the recovered capture's cleanup before reporting that
        // stopped outcome to the common dispatch owner.
        releaseMode = 'retire';
        // The original Compute stop was already observed as nonterminal
        // while waiting. Its earlier observation must not be rewritten to
        // failed; the Checkpoint journal already owns the failed Run state.
        return Object.freeze({status: 'failed'});
      }
      if (claimed.action !== 'claimed') return claimed;
      let stage;
      try {
        if (facts.prepareTargetReads !== undefined) {
          const targetReads = await facts.prepareTargetReads(claimed);
          if (targetReads !== undefined) {
            custody.retainReadAuthorization(targetReads);
            const readiness = await targetReads.prepare();
            if (readiness.status !== 'ready') fail('InstalledEffectRepeatDeferralUnsupported');
            facts = Object.freeze({...facts, targetReads});
          }
        }
        stage = await prepareRecovered(Object.freeze({...facts,
          recovered,
          retainRecoveryOwner: owner => custody.attachPhysical(owner)}));
      } catch (error) {
        if (isEffectPreparationRefusal(error) || isEffectTargetReadRefusal(error) ||
            error instanceof ExecutionAuthorizationError &&
              error.authorization?.action === 'deny') {
          const refused = checkpointJournal.refuseUnsentEffectResume(
            view.checkpointCid, ref.runDefinitionCid);
          if (refused.outcome === 'failed') releaseMode = 'retire';
        }
        throw error;
      }
      if (stage?.cleanupOwner !== undefined) {
        custody.attachPhysical(stage.cleanupOwner);
      }
      custody.attach(stage);
      ownedStage(stage, 'InvalidInstalledEffectRecovery');
      if (stage.publication.execution !== null ||
          stage.publication.store !== facts.store ||
          stage.publication.control !== facts.control ||
          stage.storedResults !== recovered.computation.storedResults ||
          stage.computation !== recovered.computation.computation ||
          stage.preview !== recovered.computation.preview ||
          stage.publication.storedResults !== stage.storedResults ||
          stage.publication.computation !==
            recovered.computation.computation ||
          stage.publication.preview !== stage.preview ||
          stage.apply.computation !== recovered.computation.computation ||
          stage.apply.preview !== stage.preview ||
          stage.apply.requestScope !== recovered.requestScope ||
          stage.apply.moon !== facts.moon ||
          stage.receipt.commonMoon !== facts.moon) {
        fail('InvalidInstalledEffectRecovery');
      }
      checkContinuation(facts, stage);
      const cleanupOwner = stage.cleanupOwner;
      if (typeof facts.retainExecution !== 'function' ||
          typeof cleanupOwner?.close !== 'function' ||
          typeof cleanupOwner.cleanup !== 'function' ||
          typeof cleanupOwner.cleanupPending !== 'function') {
        fail('InvalidInstalledEffectRecoveryOwner');
      }
      // The resumed operation has no Compute owner. Its provider must still
      // hand over physical stop and cleanup custody before any send.
      custody.attachPhysical(cleanupOwner);
      let gate;
      try {
        gate = await authorization(facts, stage, () => {
          fail('InstalledEffectRepeatDeferralUnsupported');
        });
        const options = completionOptions(stage, gate, signal,
          Object.freeze({claim: claimed}));
        facts.beginPhysicalWork?.();
        let result;
        try { result = await completeRecoveredEffectRun(options); }
        catch (error) {
          try { result = await completeInterruptedEffectRun(options, true); }
          catch (completionError) {
            if (completionError?.code === 'EffectRunNoUncertainSend') {
              if (terminalPreSendRefusal(error, options)) {
                checkpointJournal.completeResume(claimed.claim,
                  {status: 'failed'});
                releaseMode = 'retire';
                return Object.freeze({status: 'failed'});
              }
              throw error;
            }
            throw completionError;
          }
        }
        if (result.status === 'waiting') {
          fail('InstalledEffectRepeatDeferralUnsupported');
        }
        if (result.status === 'published') {
          // Publication may already have released an idempotent result owner.
          // Keep later cleanup on that same terminal release mode.
          releaseMode = 'retire';
        }
        if (result.status === 'needs_reconciliation') {
          await suspendCompletedEffectfulComputation({execution: null,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
        }
        if (result.status === 'failed') {
          checkpointJournal.completeResume(claimed.claim, {status: 'failed'});
          releaseMode = 'retire';
        } else {
          const state = await currentRunState(facts, result, stage);
          checkpointJournal.completeResume(claimed.claim, {
            runStateWire: JSON.stringify(state),
          });
          if (result.status !== 'needs_reconciliation') {
            releaseMode = 'retire';
          }
        }
        return finishStatus(result);
      } finally {
        gate?.close();
      }
    },
  });
}
