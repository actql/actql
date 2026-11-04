// Composition of one installed Effect Site with the common captured Run owner.
// Provider hooks supply only Preview/current-use and physical dispatch facts;
// the common Effect application, receipt, publication and recovery order stays
// here. The Host's durable Run-start and Checkpoint owners remain external.
import {completeCapturedEffectRun, completeRecoveredEffectRun,
  completeInterruptedEffectRun, settleRefusedEffectRun} from
  './entry.mjs';
import {releaseCompletedRunPreparedPayloads,
  suspendCompletedEffectfulComputation, isCompletedEffectfulPublicationCleanupFailure} from
  '../host-common/completed-run-publication.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {projectEffectApplication} from '../host-common/observation.mjs';
import {isEffectApplyPreflightRejection} from './effect-run-apply.mjs';
import {isEffectPreparationRefusal} from '../host-common/effect-preparation-result.mjs';
import {isEffectCaptureRecoveryRefusal} from './effect-run-recovery.mjs';
import {assertEffectTargetReadBinding, isEffectTargetReadRefusal} from
  './effect-target-read-continuation.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeUnboxedReferenceOption} from '../host-common/compiler-binding.generated.mjs';
import {INSTALLED_EFFECT_CHECKPOINT_LIMITS} from
  '../host-common/installed-checkpoint-codec-limits.mjs';

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

function requestedStopOriginal(facts, stage) {
  if (stage.requestedStop !== undefined) {
    stage.assertRequestedStopCurrent();
    return stage.requestedStop;
  }
  const original = facts.originalSubmittedIntent;
  if (original === undefined) return undefined;
  original.assertCurrent();
  return runtimeUnboxedReferenceOption(checked(
    facts.moon.clientProgramRequestedEffectStop(original.intent,
      original.referenceWire, facts.identity, facts.allowed, facts.definition,
      stage.apply.capturedInputs)));
}

function continuation(facts, stage, settlementOnly = false, requestedStop) {
  let provider;
  try { provider = JSON.parse(stage.continuationWire); }
  catch { fail('InvalidInstalledEffectContinuation'); }
  let targetBinding = facts.targetReads?.captureBinding();
  if (settlementOnly && facts.continuation?.target_read_binding !== undefined) {
    // This authenticated historical binding identifies the original capture.
    // Observing that capture does not reopen its target-read authorization.
    targetBinding = facts.continuation.target_read_binding;
    assertEffectTargetReadBinding(targetBinding);
  }
  if (requestedStop !== undefined) {
    return checked(facts.moon.clientProgramRequestedEffectStopContinuation(
      requestedStop, stage.continuationWire,
      targetBinding === undefined ? undefined : canonicalValueJson(targetBinding, {dataKeys:true}),
      INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxWireBytes,
      INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxNodes,
      INSTALLED_EFFECT_CHECKPOINT_LIMITS.maxDepth));
  }
  return canonicalValueJson({version: 'actql-installed-effect-continuation/0.1',
    run_definition_cid: facts.ref.runDefinitionCid,
    unit_id: effectUnitId(facts),
    preview_cid: facts.control.effectComputationPreviewSemanticCid(
      stage.preview),
    ...(targetBinding === undefined ? {} : {target_read_binding: targetBinding}),
    provider}, {dataKeys: true});
}

function checkContinuation(facts, stage, settlementOnly = false) {
  const original = facts.continuation?.requested_stop === undefined ? undefined
    : requestedStopOriginal(facts, stage);
  if (facts.continuation?.requested_stop !== undefined && original === undefined) {
    fail('RequestedEffectStopUnavailable');
  }
  const expected = continuation(facts, stage, settlementOnly, original);
  if (canonicalValueJson(facts.continuation, {dataKeys: true}) !== expected) {
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
  if (!Array.isArray(declaredResults) ||
      declaredResults.some(name => typeof name !== 'string' || !name) ||
      new Set(declaredResults).size !== declaredResults.length) {
    fail('InvalidInstalledEffectResultInventory');
  }
  const requestedStop = requestedStopOriginal(facts, stage);
  if (requestedStop !== undefined && typeof facts.effectAuthorization !== 'function') {
    fail('RequestedEffectStopUnavailable');
  }
  return facts.effectAuthorization({
    runId: facts.control.runDefinitionRunId(facts.retained?.runDefinition ??
      facts.runDefinition),
    runDefinitionCid: facts.ref.runDefinitionCid,
    runDefinition: facts.retained?.runDefinition ?? facts.runDefinition,
    unitId: effectUnitId(facts),
    declaredResults,
    reviewWire: facts.control.effectComputationPreviewWire(stage.preview),
    // Capture the same actual Preview, not its public CID or a restored DATA
    // substitute. The Checkpoint Owner supplies its original policy/claims.
    projectReview: (policy, limits) =>
      facts.control.projectEffectComputationReview(stage.preview, policy, limits),
    continuationWire: continuation(facts, stage, false, requestedStop),
    ...(requestedStop === undefined ? {} : {requestedStop,
      assertRequestedStopCurrent: stage.assertRequestedStopCurrent ??
        (() => facts.originalSubmittedIntent.assertCurrent())}),
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
    // The physical owner records a dispatch claim before invoking a provider.
    // An absent head and a Prepared intent are both unattempted states.
    return entry === undefined || control.ledgerEntryStateCode(entry) === 0;
  }));
}

function terminalPreSendRefusal(error, options) {
  return (error instanceof ExecutionAuthorizationError &&
      error.authorization?.action === 'deny' ||
    isEffectApplyPreflightRejection(error) || isEffectPreparationRefusal(error) ||
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
  const authorizations = [];
  let physicalCloseAttempted = false;
  let physicalReleased = false;
  let disposed = false;
  let release;
  let released = false;
  let inputsReleased = false;
  let recoveryResources;
  let constructionOwner;
  const releaseAuthorizations = async () => {
    let failure;
    for (const state of authorizations) {
      if (state.released) continue;
      try {
        // A full child owns recovery through cleanup. A close-only child has a
        // synchronous, retryable close: false or an exception retains custody.
        const recover = state.closeAttempted &&
          typeof state.owner.cleanup === 'function';
        state.closeAttempted = true;
        const result = await (recover ? state.owner.cleanup() : state.owner.close());
        state.released = result !== false &&
          (typeof state.owner.cleanupPending !== 'function' ||
            state.owner.cleanupPending() === false);
      } catch (error) { failure ??= error; }
    }
    if (failure !== undefined) throw failure;
    return authorizations.every(state => state.released);
  };
  const releaseInputs = async () => {
    if (!inputsReleased && typeof stage?.releaseInputs === 'function') {
      await stage.releaseInputs();
      inputsReleased = true;
    }
  };
  return Object.freeze({
    expectPhysical() { requirePhysical = true; },
    retainAuthorization(owner) {
      if (authorizations.some(state => state.owner === owner) ||
          typeof owner?.close !== 'function') {
        fail('InstalledEffectCleanupOwnerAlreadySet');
      }
      authorizations.push({owner, closeAttempted: false, released: false});
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
    retainConstruction(original) {
      if (constructionOwner !== undefined || typeof original?.close !== 'function' ||
          typeof original?.status !== 'function') fail('InstalledEffectCleanupOwnerAlreadySet');
      constructionOwner = original;
    },
    retainRecoveryResources(original) {
      if (recoveryResources === original) return;
      if (recoveryResources !== undefined || typeof original?.close !== 'function' ||
          typeof original?.status !== 'function') fail('InstalledEffectCleanupOwnerAlreadySet');
      recoveryResources = original;
    },
    closeAuthorizations: releaseAuthorizations,
    async close() {
      // Effect execution has stopped before dispatch custody closes. Its
      // consumer pins must go before the borrowed Compute output can reclaim.
      let failure;
      try { await releaseAuthorizations(); } catch (error) { failure = error; }
      try { await releaseInputs(); } catch (error) { failure ??= error; }
      if (physical !== undefined && !physicalCloseAttempted && !physicalReleased) {
        physicalCloseAttempted = true;
        try { await physical.close(); } catch (error) { failure ??= error; }
      }
      if (failure !== undefined) throw failure;
    },
    async cleanup() {
      // Opening may have begun physical work before returning an owner.
      // Missing custody is not evidence that the operation stopped.
      if (!await releaseAuthorizations()) return false;
      if (requirePhysical && !physicalReleased && physical === undefined) return false;
      await releaseInputs();
      if (physical !== undefined && !physicalReleased) {
        const cleaned = await physical.cleanup();
        if (cleaned === false || physical.cleanupPending() !== false) return false;
        physicalReleased = true;
      }
      if (release !== undefined && !released) {
        await release();
        released = true;
      }
      if (!disposed && typeof stage?.dispose === 'function') {
        await stage.dispose();
      }
      disposed = true;
      // Actual inputs/authorizations/physical children and completed payloads
      // are gone before their capture decode allowance can be returned. Cut
      // this custody's strong aliases before that consuming return callback.
      stage = release = physical = undefined;
      authorizations.length = 0;
      if (constructionOwner !== undefined) {
        if (await constructionOwner.close() !== true || constructionOwner.status().pending !== false) return false;
        constructionOwner = undefined;
      }
      if (recoveryResources !== undefined) {
        if (await recoveryResources.close() !== true) return false;
        recoveryResources = undefined;
      }
      return true;
    },
    cleanupPending() {
      return authorizations.some(state => !state.released) ||
        !inputsReleased && typeof stage?.releaseInputs === 'function' ||
        requirePhysical && !physicalReleased && physical === undefined ||
        physical !== undefined && !physicalReleased ||
        release !== undefined && !released ||
        !disposed && stage?.dispose !== undefined || recoveryResources !== undefined || constructionOwner !== undefined;
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
  prepareCaptured, prepareRecovered, prepareManagedPlan, validateRecoveredInstallation, privateEvidenceKey,
  queryTableBindings,
  queryTableWriteAccesses,
  targetReadInventory, targetReadAuthorization,
  claimant = 'installed-effect-host', leaseMs = 60_000}) {
  if (typeof environmentWire !== 'string' || !environmentWire ||
      typeof prepareCaptured !== 'function' ||
      typeof prepareRecovered !== 'function' ||
      (prepareManagedPlan !== undefined && typeof prepareManagedPlan !== 'function') ||
      (validateRecoveredInstallation !== undefined && typeof validateRecoveredInstallation !== 'function') ||
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
    // Retain the SAME installed implementation callback. Selection and its
    // nominal Plan/current/capacity checks stay with the original Run owner.
    prepareManagedPlan,
    queryTableBindings,
    queryTableWriteAccesses,
    targetReadInventory, targetReadAuthorization,
    privateEvidenceKey: privateEvidenceKey === undefined ? undefined :
      Uint8Array.from(privateEvidenceKey),
    async execute(facts) {
      const {moon, retainExecution, signal} = facts;
      signal?.throwIfAborted();
      facts.assertUpdateSelectionCurrent?.();
      if (typeof facts.openComputation !== 'function') {
        fail('InvalidInstalledEffectComputationPort');
      }
      const custody = cleanupCustody(undefined);
      retainExecution(custody);
      if (facts.targetReads !== undefined) {
        custody.retainAuthorization(facts.targetReads);
        let readiness;
        try { readiness = await facts.targetReads.prepare(); }
        catch (error) { facts.observePreEffectFailure?.(); throw error; }
        if (readiness.status === 'waiting_checkpoint') return readiness;
        facts.assertUpdateSelectionCurrent?.();
      }
      custody.expectPhysical();
      facts.beginPhysicalWork?.();
      let opened;
      try {
        facts.assertUpdateSelectionCurrent?.();
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
      if (opened?.status === 'needs_reconciliation' && opened.modelUnknown === true) {
        // An entered Model attempt is neither an Effect failure nor a
        // fabricated Effect ledger. Keep its original physical custody and
        // stop before Preview/Effect authorization or any Effect write.
        return Object.freeze({status: 'needs_reconciliation', modelUnknown: true});
      }
      const {execution, checkedHost} = opened ?? {};
      if (execution === undefined || checkedHost === undefined) {
        fail('InvalidInstalledEffectComputationPort');
      }
      // A failed Preview or Store operation still belongs to the dispatch
      // cleanup owner. Retain before any provider callback can fail.
      custody.attachPhysical(opened.cleanupOwner ?? execution);
      // This original belongs to the completed computation's retained cleanup
      // owner. It is not a holding-CID resolver supplied by the caller.
      const contentOwner = opened.contentOwner;
      // Acquired Runs can issue their Observation Set only after acquisition.
      // The installed Host supplies this plan from the same checked owner.
      if (opened.publicationPlan !== undefined) {
        facts = Object.freeze({...facts,
          publicationPlan: opened.publicationPlan});
      }
      let stage;
      try {
        facts.assertUpdateSelectionCurrent?.();
        const capturedFacts = {...facts, execution, checkedHost,
          retainConstructionOwner: owner => custody.retainConstruction(owner)};
        delete capturedFacts.contentOwner;
        if (contentOwner !== undefined) capturedFacts.contentOwner = contentOwner;
        stage = await prepareCaptured(Object.freeze(capturedFacts));
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
      // Capture has transferred the prepared Result handles to this owner.
      // Register their cleanup before validation or any fallible apply work.
      // Until a terminal outcome selects retirement, release local handles
      // only. Existing Host owners still decide durable retention/retirement
      // and transfer; cleanup does not reclassify the application failure.
      let releaseMode = 'retain';
      const storedResults = stage?.storedResults;
      if (storedResults !== undefined) {
        custody.requireRelease(() => releaseMode === 'retire'
          ? releaseCompletedRunPreparedPayloads(storedResults, facts.control)
          : suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults, control: facts.control,
            computation: stage.computation, preview: stage.preview}));
      }
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
      let failed = false;
      try {
        facts.assertUpdateSelectionCurrent?.();
        const gate = await authorization(facts, stage, async () => {
          facts.assertUpdateSelectionCurrent?.();
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
          facts.assertUpdateSelectionCurrent?.();
        });
        custody.retainAuthorization(gate);
        facts.assertUpdateSelectionCurrent?.();
        const options = completionOptions(stage, gate, signal, undefined,
          facts.assertContinuationCurrent);
        let result;
        try { result = await completeCapturedEffectRun(options); }
        catch (error) {
          // Preserve only the completed owner's exact terminal cleanup
          // failure. Provider/apply cleanup still needs interrupted completion.
          if (isCompletedEffectfulPublicationCleanupFailure(options.publication, error)) throw error;
          try { result = await completeInterruptedEffectRun(options, false); }
          catch (completionError) {
            if (completionError?.code === 'EffectRunNoAttemptedSend') {
              if (terminalPreSendRefusal(error, options)) {
                releaseMode = 'retire';
                return Object.freeze({status: 'failed_without_effect_dispatch'});
              }
              throw error;
            }
            throw completionError;
          }
        }
        projectEffectApplication(facts.observation, facts.ref, result);
        if (result.status === 'needs_reconciliation') {
          await suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
        } else if (result.status === 'failed' || result.status === 'published') {
          // An idempotent publication may already have released this owner.
          // Retry with the same terminal mode, never switch back to retain.
          releaseMode = 'retire';
        }
        recordUnknown(facts, result, stage);
        return finishStatus(result);
      } catch (error) {
        failed = true;
        throw error;
      } finally {
        try { await custody.closeAuthorizations(); }
        catch (error) {
          // Cleanup remains with the retained owner. Never replace the
          // application failure or detach any cleanup handle it carries.
          if (!failed) throw error;
        }
      }
    },
    async resume(facts) {
      const {signal, ref, view, checkpointJournal, checkpointBinding} = facts;
      const observing = facts.reconciliationOnly === true;
      signal?.throwIfAborted();
      // The Host resolves this Ref through its original request and current
      // evidence-read authority. No new physical-start claim exists here.
      // Retain custody before a fallible Store read. A failed read or busy
      // claim has not begun a new physical continuation and may be retried.
      const custody = cleanupCustody(undefined);
      facts.retainExecution(custody);
      let recovered;
      try { recovered = await facts.recoverCapture({signal,
        retainRecoveryResources: custody.retainRecoveryResources}); }
      catch (error) {
        if (!observing && isEffectCaptureRecoveryRefusal(error)) {
          checkpointJournal.refuseUnsentEffectResume(view.checkpointCid,
            ref.runDefinitionCid);
        }
        throw error;
      }
      let releaseMode = 'retain';
      if (recovered.recoveryResources !== undefined) {
        custody.retainRecoveryResources(recovered.recoveryResources);
      }
      custody.requireRelease(async () => {
        if (releaseMode === 'retire') {
          await releaseCompletedRunPreparedPayloads(recovered.computation.storedResults, facts.control);
        } else {
          await suspendCompletedEffectfulComputation({execution: null,
            store: facts.store, storedResults: recovered.computation.storedResults,
            control: facts.control, computation: recovered.computation.computation,
            preview: recovered.computation.preview});
        }
        recovered = undefined;
      });
      checkContinuationBinding(facts, recovered.computation);
      // Installation fencing must precede resumed target-read preparation.
      // prepareRecovered alone is too late: reads may already have occurred.
      validateRecoveredInstallation?.(Object.freeze({...facts, recovered}));
      recovered.assertUpdateSelectionCurrent?.();
      // Observing an unknown Effect is not a new approved continuation. Keep
      // the completed resume intent and physical start identity unchanged.
      const claimed = observing ? undefined : checkpointJournal.claimResume(view.runId, {
        claimant, leaseMs, binding: checkpointBinding,
        expectedCheckpointCid: view.checkpointCid,
        settleEffectRevalidation: true});
      if (claimed?.action === 'invalidated') {
        // The journal has durably failed this Run before any Effect send.
        // Transfer the recovered capture's cleanup before reporting that
        // stopped outcome to the common dispatch owner.
        releaseMode = 'retire';
        // The original Compute stop was already observed as nonterminal
        // while waiting. Its earlier observation must not be rewritten to
        // failed; the Checkpoint journal already owns the failed Run state.
        return Object.freeze({status: 'failed'});
      }
      const settling = claimed?.action === 'settlement';
      if (!observing && claimed.action !== 'claimed' && !settling) return claimed;
      const originalContinuationFacts = facts;
      const originalContinuationCurrent = facts.assertContinuationCurrent;
      const assertResumeCurrent = () => {
        signal?.throwIfAborted();
        if (!observing && !settling) {
          if (originalContinuationCurrent !== undefined) {
            Reflect.apply(originalContinuationCurrent, originalContinuationFacts, []);
          }
          checkpointJournal.admitResume(claimed.claim, {checkpointCid: view.checkpointCid});
        }
      };
      facts = Object.freeze({...facts, assertContinuationCurrent: assertResumeCurrent});
      if (recovered.updateTargetSelections !== undefined) {
        const original = recovered.assertUpdateSelectionCurrent;
        recovered = Object.freeze({...recovered, assertUpdateSelectionCurrent() {
          original();
          assertResumeCurrent();
        }});
      }
      let stage;
      try {
        recovered.assertUpdateSelectionCurrent?.();
        if (!observing && !settling && facts.prepareTargetReads !== undefined) {
          const targetReads = await facts.prepareTargetReads(claimed);
          recovered.assertUpdateSelectionCurrent?.();
          if (targetReads !== undefined) {
            custody.retainAuthorization(targetReads);
            const readiness = await targetReads.prepare();
            recovered.assertUpdateSelectionCurrent?.();
            if (readiness.status !== 'ready') fail('InstalledEffectRepeatDeferralUnsupported');
            facts = Object.freeze({...facts, targetReads});
          }
        }
        stage = await prepareRecovered(Object.freeze({...facts,
          recovered,
          retainRecoveryOwner: owner => custody.attachPhysical(owner),
          retainConstructionOwner: owner => custody.retainConstruction(owner)}));
        recovered.assertUpdateSelectionCurrent?.();
      } catch (error) {
        if (!observing && !settling && (isEffectPreparationRefusal(error) || isEffectTargetReadRefusal(error) ||
            error instanceof ExecutionAuthorizationError &&
              error.authorization?.action === 'deny')) {
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
      checkContinuation(facts, stage, settling || observing);
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
      if (settling) {
        const result = await settleRefusedEffectRun(
          completionOptions(stage, undefined, signal));
        projectEffectApplication(facts.observation, facts.ref, result);
        if (result.status === 'needs_reconciliation') {
          const state = recordUnknown(facts, result, stage);
          checkpointJournal.completeResume(claimed.claim,
            {runStateWire: JSON.stringify(state)});
        } else {
          checkpointJournal.completeResume(claimed.claim, {status: 'failed'});
          releaseMode = 'retire';
        }
        return finishStatus(result);
      }
      let failed = false;
      try {
        recovered.assertUpdateSelectionCurrent?.();
        const gate = observing ? undefined : await authorization(facts, stage, () => {
          fail('InstalledEffectRepeatDeferralUnsupported');
        });
        if (gate !== undefined) custody.retainAuthorization(gate);
        recovered.assertUpdateSelectionCurrent?.();
        const completion = completionOptions(stage, gate, signal,
          observing ? undefined : Object.freeze({claim: claimed}));
        const options = observing ? Object.freeze({...completion,
          apply: Object.freeze({...completion.apply, observationOnly: true})}) : completion;
        facts.beginPhysicalWork?.();
        let result;
        try { result = await completeRecoveredEffectRun(options); }
        catch (error) {
          // A rejected observation must not publish an old receipt as a new
          // reconciliation result. Keep uncertainty and custody for retry.
          if (observing || isCompletedEffectfulPublicationCleanupFailure(options.publication, error)) throw error;
          try { result = await completeInterruptedEffectRun(options, true); }
          catch (completionError) {
            if (completionError?.code === 'EffectRunNoAttemptedSend') {
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
        projectEffectApplication(facts.observation, facts.ref, result);
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
          if (observing) checkpointJournal.finishRun(view.runId,
            {from: 'needs_reconciliation', status: 'failed'});
          else checkpointJournal.completeResume(claimed.claim, {status: 'failed'});
          releaseMode = 'retire';
        } else {
          const state = await currentRunState(facts, result, stage);
          if (observing) checkpointJournal.finishRun(view.runId,
            {from: 'needs_reconciliation', status: state.status,
              runStateWire: JSON.stringify(state)});
          else checkpointJournal.completeResume(claimed.claim, {
            runStateWire: JSON.stringify(state),
          });
          if (result.status !== 'needs_reconciliation') {
            releaseMode = 'retire';
          }
        }
        return finishStatus(result);
      } catch (error) {
        failed = true;
        throw error;
      } finally {
        try { await custody.closeAuthorizations(); }
        catch (error) {
          // Cleanup remains with the retained owner. Never replace the
          // application failure or detach any cleanup handle it carries.
          if (!failed) throw error;
        }
      }
    },
  });
}
