// Composition of one installed Effect Site with the common captured Run owner.
// Provider hooks supply only Preview/current-use and physical dispatch facts;
// the common Effect application, receipt, publication and recovery order stays
// here. The Host's durable Run-start and Checkpoint owners remain external.
import {completeCapturedEffectRun, completeRecoveredEffectRun,
  completeInterruptedEffectRun} from
  './entry.mjs';
import {suspendCompletedEffectfulComputation} from
  '../host-common/completed-run-publication.mjs';
import {canonicalJson} from './local-account-config.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

function ownedStage(stage, code) {
  if (stage === null || typeof stage !== 'object' ||
      !stage.preview || !stage.computation || !stage.storedResults ||
      !stage.apply || !stage.receipt || !stage.publication ||
      !Array.isArray(stage.scopes) || stage.scopes.length === 0 ||
      typeof stage.continuationWire !== 'string' ||
      stage.dispose !== undefined && typeof stage.dispose !== 'function') {
    fail(code);
  }
  return stage;
}

function continuation(facts, stage) {
  let provider;
  try { provider = JSON.parse(stage.continuationWire); }
  catch { fail('InvalidInstalledEffectContinuation'); }
  return canonicalJson({version: 'actql-installed-effect-continuation/0.1',
    run_definition_cid: facts.ref.runDefinitionCid,
    preview_cid: facts.control.effectComputationPreviewSemanticCid(
      stage.preview),
    provider});
}

function checkContinuation(facts, stage) {
  const expected = continuation(facts, stage);
  if (canonicalJson(facts.continuation) !== expected) {
    fail('InstalledEffectContinuationMismatch');
  }
}

function checkContinuationBinding(facts, recovered) {
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
    unitId: 'values',
    declaredResults,
    reviewWire: facts.control.effectComputationPreviewWire(stage.preview),
    continuationWire: continuation(facts, stage),
    beforeDefer,
  });
}

function completionOptions(stage, gate, signal, resume) {
  const apply = {...stage.apply, authorization: Object.freeze({gate,
    scopes: stage.scopes,
    ...(resume === undefined ? {} : {resume})})};
  return Object.freeze({apply, receipt: stage.receipt,
    publication: stage.publication, signal});
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

function cleanupCustody(physical) {
  let stage;
  let disposed = false;
  return Object.freeze({
    attach(value) {
      if (stage !== undefined) fail('InstalledEffectCleanupOwnerAlreadySet');
      stage = value;
    },
    async close() { await physical?.close(); },
    async cleanup() {
      const cleaned = await physical?.cleanup() ?? true;
      if (cleaned === false || physical?.cleanupPending() === true) {
        return false;
      }
      if (!disposed && typeof stage?.dispose === 'function') {
        await stage.dispose();
      }
      disposed = true;
      return true;
    },
    cleanupPending() {
      return physical?.cleanupPending() === true ||
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
  claimant = 'installed-effect-host', leaseMs = 60_000}) {
  if (typeof environmentWire !== 'string' || !environmentWire ||
      typeof prepareCaptured !== 'function' ||
      typeof prepareRecovered !== 'function' ||
      privateEvidenceKey !== undefined &&
        (!(privateEvidenceKey instanceof Uint8Array) ||
          privateEvidenceKey.byteLength !== 32) ||
      typeof claimant !== 'string' || !claimant ||
      !Number.isSafeInteger(leaseMs) || leaseMs < 1) {
    fail('InvalidInstalledEffectSiteFactory');
  }
  return Object.freeze({
    environmentWire,
    privateEvidenceKey: privateEvidenceKey === undefined ? undefined :
      Uint8Array.from(privateEvidenceKey),
    async execute(facts) {
      const {moon, retainExecution, signal} = facts;
      signal?.throwIfAborted();
      if (typeof facts.openComputation !== 'function') {
        fail('InvalidInstalledEffectComputationPort');
      }
      const opened = await facts.openComputation();
      const {execution, checkedHost} = opened ?? {};
      if (execution === undefined || checkedHost === undefined) {
        fail('InvalidInstalledEffectComputationPort');
      }
      // A failed Preview or Store operation still belongs to the dispatch
      // cleanup owner. Retain before any provider callback can fail.
      const custody = cleanupCustody(execution);
      retainExecution(custody);
      const stage = await prepareCaptured(Object.freeze({...facts,
        execution, checkedHost}));
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
        const options = completionOptions(stage, gate, signal);
        let result;
        try { result = await completeCapturedEffectRun(options); }
        catch (error) {
          try { result = await completeInterruptedEffectRun(options, false); }
          catch (completionError) {
            if (completionError?.code === 'EffectRunNoUncertainSend') {
              throw error;
            }
            throw completionError;
          }
        }
        if (result.status === 'needs_reconciliation' ||
            result.status === 'failed') {
          await suspendCompletedEffectfulComputation({execution,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
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
      const recovered = await facts.recoverCapture({signal});
      checkContinuationBinding(facts, recovered.computation);
      const claimed = checkpointJournal.claimResume(view.runId, {
        claimant, leaseMs, binding: checkpointBinding});
      if (claimed.action !== 'claimed') return claimed;
      const stage = await prepareRecovered(Object.freeze({
        ...facts, recovered}));
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
      const custody = cleanupCustody(cleanupOwner);
      custody.attach(stage);
      facts.retainExecution(custody);
      let gate;
      try {
        gate = await authorization(facts, stage, () => {
          fail('InstalledEffectRepeatDeferralUnsupported');
        });
        const options = completionOptions(stage, gate, signal,
          Object.freeze({claim: claimed}));
        let result;
        try { result = await completeRecoveredEffectRun(options); }
        catch (error) {
          try { result = await completeInterruptedEffectRun(options, true); }
          catch (completionError) {
            if (completionError?.code === 'EffectRunNoUncertainSend') {
              throw error;
            }
            throw completionError;
          }
        }
        if (result.status === 'waiting') {
          fail('InstalledEffectRepeatDeferralUnsupported');
        }
        if (result.status === 'needs_reconciliation' ||
            result.status === 'failed') {
          await suspendCompletedEffectfulComputation({execution: null,
            store: facts.store, storedResults: stage.storedResults,
            control: facts.control, computation: stage.computation,
            preview: stage.preview});
        }
        if (result.status === 'failed') {
          checkpointJournal.completeResume(claimed.claim, {status: 'failed'});
        } else {
          const state = await currentRunState(facts, result, stage);
          checkpointJournal.completeResume(claimed.claim, {
            runStateWire: JSON.stringify(state),
          });
        }
        return finishStatus(result);
      } finally {
        gate?.close();
      }
    },
  });
}
