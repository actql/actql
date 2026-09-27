// Composition of one installed Effect Site with the common captured Run owner.
// Provider hooks supply only Preview/current-use and physical dispatch facts;
// the common Effect application, receipt, publication and recovery order stays
// here. The Host's durable Run-start and Checkpoint owners remain external.
import {completeCapturedEffectRun, completeRecoveredEffectRun} from
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
      typeof stage.continuationWire !== 'string') fail(code);
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
  prepareCaptured, prepareRecovered, claimant = 'installed-effect-host',
  leaseMs = 60_000}) {
  if (typeof environmentWire !== 'string' || !environmentWire ||
      typeof prepareCaptured !== 'function' ||
      typeof prepareRecovered !== 'function' ||
      typeof claimant !== 'string' || !claimant ||
      !Number.isSafeInteger(leaseMs) || leaseMs < 1) {
    fail('InvalidInstalledEffectSiteFactory');
  }
  return Object.freeze({
    environmentWire,
    async execute(facts) {
      const {moon, retainExecution, signal} = facts;
      signal?.throwIfAborted();
      if (typeof facts.openComputation !== 'function') {
        fail('InvalidInstalledEffectComputationPort');
      }
      const execution = await facts.openComputation();
      // A failed Preview or Store operation still belongs to the dispatch
      // cleanup owner. Retain before any provider callback can fail.
      retainExecution(execution);
      const stage = ownedStage(await prepareCaptured(Object.freeze({...facts,
        execution})), 'InvalidInstalledEffectCapture');
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
      const gate = await authorization(facts, stage, async () => {
        await suspendCompletedEffectfulComputation({execution,
          store: facts.store, storedResults: stage.storedResults,
          control: facts.control, computation: stage.computation,
          preview: stage.preview});
      });
      try {
        const result = await completeCapturedEffectRun(
          completionOptions(stage, gate, signal));
        recordUnknown(facts, result, stage);
        return finishStatus(result);
      } finally { gate.close(); }
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
      const stage = ownedStage(await prepareRecovered(Object.freeze({
        ...facts, recovered})), 'InvalidInstalledEffectRecovery');
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
      const gate = await authorization(facts, stage, () => {
        fail('InstalledEffectRepeatDeferralUnsupported');
      });
      try {
        const result = await completeRecoveredEffectRun(completionOptions(
          stage, gate, signal, Object.freeze({claim: claimed})));
        if (result.status === 'waiting') {
          fail('InstalledEffectRepeatDeferralUnsupported');
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
      } finally { gate.close(); }
    },
  });
}
