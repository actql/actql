import {dispatchFailureSnapshot, dispatchFailureCodeSite, publicBudgetFailureMessage} from './client-dispatch-diagnostic.mjs';
// One installed Host owner for an admitted Run's physical dispatch, stop
// observation, and recoverable cleanup. The journal and MoonBit control keep
// their existing authority; this owner does not decide whether to retry.
import {addAbortListener} from 'node:events';
import {types as nodeTypes} from 'node:util';
import {runtimeField, runtimeOptionalField, runtimeTag, runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
import {CapturedRunPublicationError,
  runPublishedCapturedStrategy} from './entry.mjs';
import {acquiredTaskPublicationPlan, acquiredMultiTaskPublicationPlan,
  acquiredKeyedTaskPublicationPlan, localContractLimits, sourceFreePlanExecutionOwner} from './local-values-plan.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {ordinarySourceDescriptors, verifyOrdinarySourceBinding} from './ordinary-source-binding.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installTaskObservation} from '../host-common/task-observation.mjs';
import {prepareInstalledLogicalObservation} from './logical-task-observation.mjs';
import {bindClientSourceOperation} from './client-source-operation.mjs';
import {ledgerUsageDiagnostic, ledgerUsageHasPendingResources} from '../host-common/runtime-core.mjs';
import {issueInstalledUnpublishedRunState} from '../host-common/run-state-observation.mjs';
import {isModelCredentialRefusal} from './infer-operation.mjs';

// Diagnostics must not become a second owner of execution/cleanup capabilities.
// Read only inert own data, including one existing primaryFailure diagnostic
// slot. Accessors and error/cause chains are not invoked or traversed, and the
// returned receipt retains no thrown object or cleanup capability.
const dispatchFailureFields = Object.freeze(['primaryFailure', 'closeFailure',
  'cleanupFailure', 'finishFailure', 'releaseFailure', 'preparationRetirementFailure']);


// This message extends the existing failed Run observation, not its status,
// authority or cleanup evidence. Never format arbitrary exception text.


// Only diagnostic custody moves here. An Unknown result keeps its outcome,
// physical owner and current gates; a later cleanup refusal is not its cause.
function retainDispatchPrimaryFailure(entry, result) {
  try {
    const primary = Object.getOwnPropertyDescriptor(result, 'primaryFailure');
    if (!Object.hasOwn(entry, 'primaryFailure') &&
        primary !== undefined && Object.hasOwn(primary, 'value')) {
      entry.primaryFailure = primary.value;
    }
  } catch { /* Optional failure DATA cannot interrupt the original cleanup. */ }
}

// One original Core holder covers the ordinary configured Host and its
// transitive outputs through confirmed cleanup. This is not a numeric grant.
function releaseDispatchPreparationHost(entry) {
  const holder = entry.preparationHostBorrow;
  if (holder === undefined) return;
  const release = entry.preparationHostReturn, runtime = entry.preparationHostRuntime;
  entry.preparationHostBorrow = entry.preparationHostReturn = entry.preparationHostRuntime = undefined;
  // A valid Core return consumes its token before any settlement failure;
  // the original retirement receipt retains a failed debit for cleanup retry.
  checked(Reflect.apply(release, runtime, [holder]));
}
function retainDispatchPreparationHost(entry, moon, managedRun, prepared, request, hasCustody) {
  const acquire = moon.clientProgramInstalledManagedPreparationBorrow;
  if (typeof acquire !== 'function') throw new Error('PreparationHostCustodyUnavailable');
  if (entry.preparationHostBorrow !== undefined) throw new Error('DuplicatePreparationHostBorrow');
  const release = moon.clientProgramPreparationBorrowReturn, read = moon.clientProgramPreparationBorrowRead;
  if (typeof release !== 'function' || typeof read !== 'function') throw new Error('PreparationHostCustodyUnavailable');
  const holder = checked(Reflect.apply(acquire, moon, [managedRun, prepared, request]));
  if (holder === undefined) throw new Error('PreparationHostCustodyUnavailable');
  entry.preparationHostBorrow = holder;
  entry.preparationHostReturn = release;
  entry.preparationHostRuntime = moon;
  try {
    if (!hasCustody || Reflect.apply(read, moon, [holder]) !== prepared) {
      throw new Error('ForeignPreparationHostCustody');
    }
  } catch (error) {
    releaseDispatchPreparationHost(entry);
    throw error;
  }
}

// Terminal observation only, never a send or cancellation permission. The
// physical owner calls this after confirmed stop and temporary reclamation;
// restored observers use their persisted physical-close confirmation.
async function collectNodeRunStop({ref, journal, store,
  checkpoints, moon, control, cleanupConfirmed, physicalStopConfirmed = false}, originalFrame) {
  if (typeof journal?.lookupRunDefinition !== 'function' ||
      typeof journal?.lookupReconciliationState !== 'function') return {cancelled: false};
  const before = originalFrame ?? journal.lookupRunDefinition(ref, moon, control);
  if (before === undefined) return {cancelled: false};
  const runId = control.runDefinitionRunId(before.runDefinition);
  const model = checkpoints?.journal;
  const publicationCommitted = await store.confirmCommittedIndex(ref) !== undefined;
  // Publication inspection is asynchronous. A changed request observation
  // must be re-evaluated rather than sealed as a terminal cancellation.
  const after = journal.lookupRunDefinition(ref, moon, control, before);
  // Collect fresh synchronous facts after the await, then hand the terminal
  // decision to the same common Run owner for normal and restored execution.
  const cancelled = control.runCancellationConfirmed({
    cancellationRequested: after?.cancellationRequested === true,
    modelFenceRequired: (model?.discoverModelCallSets({runId, limit: 1}) ?? []).length !== 0,
    modelFenced: model?.modelCancellationFenced?.(runId, ref.runDefinitionCid) === true,
    unresolvedModelCalls: model?.hasUnresolvedModelCalls(runId) === true,
    unresolvedEffects: journal.lookupReconciliationState(ref) !== undefined,
    reconciliationRequired: model?.getRunState?.(runId)?.status === 'needs_reconciliation',
    publicationCommitted,
    physicalStopConfirmed: physicalStopConfirmed === true,
    cleanupConfirmed: cleanupConfirmed === true,
    revisionUnchanged: after === before,
  });
  return {cancelled, publicationCommitted, revisionUnchanged: after === before, frame: after};
}

export async function observeNodeRunCancellation(facts, originalFrame) {
  if (typeof facts.journal?.lookupRunDefinition !== 'function' ||
      typeof facts.journal?.lookupReconciliationState !== 'function') return {cancelled: false};
  const before = originalFrame ?? facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control);
  let observation = await collectNodeRunStop(facts, before);
  // A public status publication can race this asynchronous Store inspection.
  // Recollect every fact once only when the Journal proves that all control
  // and immutable fields remained exact; never accept a changed frame itself.
  if (observation.revisionUnchanged === false &&
      facts.journal.canReinspectRunStopAfterStatePublication?.(before, observation.frame) === true) {
    observation = await collectNodeRunStop(facts, observation.frame);
  }
  return observation;
}

export async function confirmNodeRunCancellation(facts) {
  return (await observeNodeRunCancellation(facts)).cancelled;
}

export async function cancelNodeRunContinuation({currentDispatchIdle, ...facts}) {
  if (typeof currentDispatchIdle !== 'function' || !currentDispatchIdle()) return false;
  const retained = facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control);
  // A waiting Checkpoint may be visible before its producer has reclaimed
  // its temporary resources. Require the persisted stop receipt as well as
  // absence of a newer live or pending-cleanup owner; neither alone suffices.
  if (retained?.physicalCloseConfirmed !== true) return false;
  const observation=await observeNodeRunCancellation({...facts,physicalStopConfirmed:true,
    cleanupConfirmed:true},retained);
  if (!observation.cancelled || !currentDispatchIdle() ||
      facts.journal.lookupRunDefinition(facts.ref,facts.moon,facts.control,
        observation.frame)!==observation.frame) {
    return false;
  }
  return facts.checkpoints.cancelEffectContinuation(
    facts.control.runDefinitionRunId(retained.runDefinition), facts.ref.runDefinitionCid);
}

export async function observeNodeRestoredLocalStop(facts) {
  // Same-process original stop is an execution observation, not a cleanup
  // acknowledgement or proof that a requested cancellation was honored.
  // Publication/Carrier cleanup remains owned by its actual original APIs.
  for (let inspection = 0; inspection < 2; inspection++) {
    const before = facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control);
    if (before === undefined || before.physicalCloseConfirmed === true ||
        facts.journal.observeStoppedLocalExecutionOwner?.(facts.ref, before) !== true) return;
    const committed = await facts.store.confirmCommittedIndex(facts.ref) !== undefined;
    const retained = facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control, before);
    if (retained?.physicalCloseConfirmed === true) return;
    if (retained !== before) {
      if (inspection === 0 &&
          facts.journal.canReinspectRunStopAfterStatePublication?.(before, retained) === true) continue;
      throw new Error('ClientRunStopObservationChanged');
    }
    if (facts.journal.observeStoppedLocalExecutionOwner(facts.ref, retained) !== true ||
        facts.journal.lookupReconciliationState(facts.ref) !== undefined) return;
    facts.journal.markPhysicalClose(facts.ref, committed ? null : 'failed', retained);
    return;
  }
  throw new Error('ClientRunStopObservationChanged');
}

export async function observeNodeRestoredModelStop(facts) {
  return observeNodeRunStop(facts, {failureObserved: false});
}

export function recordNodeRunPhysicalStop({ref, journal, moon, control}, outcome) {
  const retained = journal.lookupRunDefinition(ref, moon, control);
  if (retained?.physicalCloseConfirmed === true) return;
  journal.markPhysicalClose(ref, outcome, retained);
}

async function observeNodeRunStop(facts, {failureObserved}) {
  if (facts.physicalStopConfirmed !== true || facts.cleanupConfirmed !== true) return;
  for(let inspection=0;inspection<2;inspection++){
    const before=facts.journal.lookupRunDefinition(facts.ref,facts.moon,facts.control);
    if(before?.physicalCloseConfirmed===true)return;
    if(before===undefined)throw new Error('ClientRunStopObservationChanged');
    const observation = await collectNodeRunStop(facts,before);
    // Preserve another confirmed observer's immutable physical-stop record,
    // including a nonterminal stop from an earlier phase of this same Run.
    const retained = observation.frame;
    if (retained?.physicalCloseConfirmed === true) return;
    if (observation.revisionUnchanged !== true) {
      // A real public observation may advance only its own metadata during
      // the Store await. The Journal's nominal frame comparison must prove
      // every immutable/control field unchanged before one full reinspection.
      if(inspection===0&&facts.journal.canReinspectRunStopAfterStatePublication?.(before,retained)===true) continue;
      throw new Error('ClientRunStopObservationChanged');
    }
    facts.journal.markPhysicalClose(facts.ref, observation.publicationCommitted ? null :
      observation.cancelled ? 'cancelled' : failureObserved && retained?.cancellationRequested !== true ? 'failed' : null,
    retained);
    return;
  }
  // Continued changes retain this same physical owner for later inspection.
  throw new Error('ClientRunStopObservationChanged');
}

function invalidSampleStartReceiver(value, code = 'InvalidClientRunSampleStartReceiver') {
  if (typeof value?.then === 'function') void Promise.resolve(value).catch(() => {});
  throw new TypeError(code);
}

// The installed Host owns the Account and Core port. A selected profile may
// prepare its controller, then cross the acknowledged start boundary once.
export function installNodeRelationSampleStart(moon, observeAccount, hostConnection, site) {
  const advance = moon.clientProgramAdvanceRelationSampleStartControl;
  if (typeof advance !== 'function') return undefined;
  return (setup, owner, profile, authority) => {
    const observe = () => {
      if (hostConnection(authority) !== true) throw new Error('ClientRunSampleStartAuthorityLost');
      return observeAccount();
    };
    const original = observe();
    const assertCurrent = () => {
      if (observe() !== original) throw new Error('ClientRunSampleStartAuthorityLost');
    };
    checked(advance.call(moon, profile, owner, setup, original, authority.principalId, site, false));
    assertCurrent();
    let pending = true;
    return () => {
      if (!pending) throw new Error('ClientRunSampleStartOriginalUnavailable');
      pending = false;
      assertCurrent();
      checked(advance.call(moon, profile, owner, setup, original, authority.principalId, site, true));
      assertCurrent();
    };
  };
}

// A drain interrupts the local wait, independently of cancellation or failure.
class DebugPauseHostClosing extends Error {
  constructor() {
    super('ClientRunDebugEntryHostClosing');
    this.code = 'ClientRunDebugEntryHostClosing';
  }
}

// The installed entry reads its actual Core phase after the shared start ACK.
// Closing this port releases the borrowed aliases and its outstanding wait.
export function installNodeRelationSampleDebugEntry(moon, observeAccount, hostConnection, site,
  {journal, control, now}) {
  const advance = moon.clientProgramAdvanceRelationSampleDebugEntry;
  const runnable = moon.clientProgramRelationSampleDebugEntryRunnable;
  const pause = moon.clientProgramRelationSampleDebugTaskPause;
  const nextInput = moon.clientProgramRelationSampleDebugNextInput;
  const resume = moon.clientProgramResumeRelationSampleDebugTask;
  const resumeAllowed = moon.clientProgramRelationSampleDebugResumeAllowed;
  if (typeof advance !== 'function' || typeof runnable !== 'function' ||
      typeof pause !== 'function' || typeof resume !== 'function' || typeof resumeAllowed !== 'function' ||
      typeof journal?.parkDebugTask !== 'function' || typeof journal.acceptDebugTaskResume !== 'function' ||
      typeof journal.debugPauseCurrent !== 'function') {
    return undefined;
  }
  return (setup, owner, authority, profile, signal, logicalMapCid, runDefinition) => {
    if (profile === undefined || hostConnection(authority) !== true) {
      throw new Error('ClientRunDebugEntryOriginalUnavailable');
    }
    const account = observeAccount();
    let live = {setup, owner, authority, account, profile, signal, logicalMapCid, runDefinition,
      startRevision: 0, revision: 0};
    let activated = false, waiting, resuming = false, hostClosing = false;
    const current = () => {
      const original = live;
      return original !== undefined && !original.signal.aborted &&
        hostConnection(original.authority) === true && observeAccount() === original.account &&
        live === original && !original.signal.aborted && hostConnection(original.authority) === true &&
        live === original && !original.signal.aborted;
    };
    const requireCurrent = original => {
      if (!current() || live !== original) throw new Error('ClientRunDebugEntryDenied');
    };
    const call = (original, command, revision) => {
      requireCurrent(original);
      checked(advance.call(moon, original.profile, original.owner, original.setup, original.account,
        original.authority.principalId, site, command, revision));
      requireCurrent(original);
    };
    const phase = actual => {
      const original = live;
      if (original === undefined || actual !== original.setup || original.startRevision === 0) {
        throw new Error('ClientRunDebugEntryOriginalUnavailable');
      }
      requireCurrent(original);
      const ready = checked(runnable.call(moon, original.profile, original.owner, original.setup, original.startRevision));
      requireCurrent(original);
      if (typeof ready !== 'boolean') throw new TypeError('InvalidInstalledTaskController');
      return ready ? 'runnable' : 'paused';
    };
    function stopWaiting(wait, failure, handoff) {
      if (waiting !== wait) return;
      waiting = undefined;
      wait.listener[Symbol.dispose]();
      clearTimeout(wait.timer);
      if (failure === undefined) wait.resolve(handoff);
      else wait.reject(failure);
    }
    function expireWaiting(wait) {
      if (waiting !== wait) return;
      const left = wait.parked.expiresAt - Date.parse(now());
      if (!Number.isFinite(left) || left <= 0) {
        stopWaiting(wait, new Error('ClientRunDebugEntryExpired'));
      } else {
        wait.timer = setTimeout(expireWaiting, Math.min(left, 2147483647), wait);
      }
    }
    function holdPause(parked, signal) {
      if (!Number.isSafeInteger(parked.pausedAt) || parked.pausedAt < 0 || parked.pausedAt >= parked.expiresAt) {
        throw new Error('ClientRunDebugEntryOriginalUnavailable');
      }
      if (hostClosing) throw new DebugPauseHostClosing();
      return new Promise((resolve, reject) => {
        const wait = {parked, resolve, reject};
        wait.listener = addAbortListener(signal, () => stopWaiting(wait, signal.reason));
        waiting = wait;
        try {expireWaiting(wait);}
        catch (cause) {stopWaiting(wait, cause);}
      });
    }
    call(live, 'prepare', 0);
    return Object.freeze({
      current,
      activate(witness) {
        const original = live;
        const revision = witness?.physicalStartRevision;
        const command = witness?.until;
        if (activated || original === undefined || !Number.isInteger(revision) ||
            revision < 1 || revision > 2147483647 || (command !== 'step' && command !== 'terminal')) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        activated = true;
        call(original, command, revision);
        original.startRevision = original.revision = revision;
      },
      parkEntry(identity, expectedRevision, expiresAt) {
        const original = live;
        if (original === undefined || activated || waiting !== undefined ||
            typeof journal.parkDebugEntry !== 'function' || typeof journal.acceptDebugEntryResume !== 'function') {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        requireCurrent(original);
        const parked = journal.parkDebugEntry(identity, {
          ref: original.authority.ref, expectedRevision, expiresAt, current,
        }, moon, control);
        requireCurrent(original);
        if (parked?.kind === 'expired') throw new Error('ClientRunDebugEntryExpired');
        if (parked?.kind !== 'parked' || parked.revision !== expectedRevision + 1 || parked.expiresAt !== expiresAt) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        return holdPause(parked, original.signal);
      },
      observePause(authorize, inspect = false) {
        const original = live, wait = waiting;
        const local = () => waiting === wait && !hostClosing && !resuming && !wait.unresolved;
        const allowed = () => local() && current() && authorize() === true && current() && local();
        if (original === undefined || wait === undefined || !allowed() ||
            !journal.debugPauseCurrent(original.authority.ref, {
              parked: wait.parked, startRevision: original.startRevision, current: allowed, requireEntryDeadline: inspect,
            }) || !local()) return undefined;
        return Object.freeze({revision: wait.parked.revision,
          ...(wait.parked.stepId === undefined ? {} : {completedStepId: wait.parked.stepId,
            committedGeneration: wait.parked.committedGeneration}),
          ...(wait.parked.nextStepId == null ? {} : {nextStepId: wait.parked.nextStepId}),
          ...(inspect ? {logicalMapCid: original.logicalMapCid, startRevision: original.startRevision,
            controlRevision: wait.parked.controlRevision, runRef: original.authority.ref,
            ttlPolicy: 'original_debug_entry_deadline'} : {}),
          expiresAt: wait.parked.expiresAt, pausedAt: wait.parked.pausedAt});
      },
      readNextSample(selected, authorize, reserve, bindProducer) {
        const original = live, wait = waiting;
        const local = () => waiting === wait && !hostClosing && !resuming && !wait.unresolved;
        const denied = () => {throw Object.assign(new Error('ClientRelationSampleDenied'), {code: 'ClientRelationSampleDenied'});};
        const stale = () => {throw Object.assign(new Error('ClientRunDebugEntryRevisionConflict'),
          {code: 'ClientRunDebugEntryRevisionConflict'});};
        const allowed = () => local() && live === original && current() && authorize() === true && current() && local();
        if (typeof nextInput !== 'function' || typeof journal.readRetainedRelationSample !== 'function' ||
            typeof reserve !== 'function' || typeof bindProducer !== 'function' || !Object.isFrozen(selected)) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        if (original === undefined || wait?.parked.controlRevision === undefined || !local() ||
            selected.revision !== wait.parked.revision || selected.nextStepId !== wait.parked.nextStepId) stale();
        if (!allowed()) denied();
        // The fixed Read covers the bridge call, checked edge/port probes
        // and the borrowed producer tuple. It holds no Run payload or pin.
        const quote = reserve(2048);
        if (quote !== undefined) {
          if (typeof quote?.then === 'function') void Promise.resolve(quote).catch(() => {});
          throw Object.assign(new Error('ClientRelationSampleCapacity'), {code: 'ClientRelationSampleCapacity'});
        }
        if (!local()) stale();
        if (!allowed()) denied();
        const result = nextInput.call(moon, original.profile, original.owner, original.setup,
          original.startRevision, wait.parked.controlRevision, wait.parked.committedGeneration,
          selected.nextStepId, selected.inputOrdinal, selected.maxWork);
        if (!allowed()) denied();
        if (runtimeIsError(result)) {
          const issue = runtimeField(result, 0);
          if (issue === 'stale') stale();
          if (issue === 'capacity' || issue === 'foreign') {
            const code = issue === 'capacity' ? 'ClientRelationSampleCapacity' : 'ForeignClientRunSampleOutput';
            throw Object.assign(new Error(code), {code});
          }
        }
        const selectedProducer = checked(result);
        if (selectedProducer === undefined) return Object.freeze({kind: 'unobserved'});
        const producer = Object.freeze({stepId: runtimeField(selectedProducer, 0),
          outputPortId: runtimeField(selectedProducer, 1), carrierContractCid: runtimeField(selectedProducer, 2),
          generation: runtimeField(selectedProducer, 3), attemptSequence: runtimeField(selectedProducer, 4)});
        const bound = bindProducer(producer);
        if (bound !== true) {
          if (typeof bound?.then === 'function') void Promise.resolve(bound).catch(() => {});
          throw Object.assign(new Error('ForeignClientRunSampleOutput'), {code: 'ForeignClientRunSampleOutput'});
        }
        if (!local()) stale();
        if (!allowed()) denied();
        return journal.readRetainedRelationSample(original.authority.ref, Object.freeze({
          compiledPlanCid: selected.compiledPlanCid, logicalMapCid: selected.logicalMapCid,
          stepId: producer.stepId, outputPortId: producer.outputPortId, carrierContractCid: producer.carrierContractCid,
          nextStepId: selected.nextStepId, maxBytes: selected.maxBytes,
        }), {current: allowed, reserve, debugPause: {parked: wait.parked,
          startRevision: original.startRevision, producer}}, control);
      },
      resumeTask(commandWire, authorize, reserve) {
        const original = live, wait = waiting;
        if (original === undefined || wait === undefined || hostClosing || resuming) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        const reconciliationRequired = () => Object.assign(new Error('ClientRunDebugEntryReconciliationRequired'),
          {code: 'ClientRunDebugEntryReconciliationRequired'});
        resuming = true;
        const allowed = () => waiting === wait && !hostClosing && current() && authorize() === true &&
          current() && !hostClosing && waiting === wait;
        try {
          if (!allowed() || resumeAllowed.call(moon, original.profile, original.owner, original.setup,
            original.account, original.authority.principalId, site) !== true || !allowed()) {
            throw Object.assign(new Error('ClientRunDebugEntryDenied'), {code: 'ClientRunDebugEntryDenied'});
          }
          if (wait.unresolved) throw reconciliationRequired();
          const receiptOriginal = reserve === undefined ? undefined : {
            runDefinition: original.runDefinition, logicalMapCid: original.logicalMapCid, reserve,
          };
          let result;
          if (wait.parked.controlRevision === undefined) {
            result = journal.acceptDebugEntryResume(original.authority.ref, {commandWire, current: allowed, receiptOriginal,
              capture(witness) {
                try {
                  if (!allowed()) throw new Error('ClientRunDebugEntryDenied');
                  if (witness?.kind !== 'resume_accepted' || witness.revision !== wait.parked.revision + 1 ||
                      typeof witness.commandCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(witness.commandCid) ||
                      (witness.until !== 'step' && witness.until !== 'terminal')) {
                    throw new Error('ClientRunDebugEntryOriginalUnavailable');
                  }
                  stopWaiting(wait, undefined, witness.commandCid);
                } catch (cause) {
                  stopWaiting(wait, cause);
                  // The funded caller's receipt records the committed
                  // acceptance. The original Driver receives this failure.
                  if (receiptOriginal === undefined) throw cause;
                }
              },
            }, control);
          } else {
            result = journal.acceptDebugTaskResume(original.authority.ref, {
              commandWire, startRevision: original.startRevision, stepId: wait.parked.stepId, nextStepId: wait.parked.nextStepId,
              committedGeneration: wait.parked.committedGeneration,
              current: allowed, receiptOriginal, capture(witness) {
                try {
                  if (!allowed()) throw new Error('ClientRunDebugEntryDenied');
                  if (witness?.kind !== 'resume_accepted' || witness.revision !== wait.parked.revision + 1 ||
                      witness.controlRevision !== wait.parked.controlRevision || witness.stepId !== wait.parked.stepId ||
                      witness.nextStepId !== wait.parked.nextStepId ||
                      witness.committedGeneration !== wait.parked.committedGeneration ||
                      (witness.until !== 'step' && witness.until !== 'terminal')) {
                    throw new Error('ClientRunDebugEntryOriginalUnavailable');
                  }
                  checked(resume.call(moon, original.profile, original.owner, original.setup, original.account,
                    original.authority.principalId, site, original.startRevision,
                    witness.controlRevision, witness.stepId, witness.nextStepId ?? '', witness.committedGeneration,
                    witness.until === 'step'));
                  if (!allowed()) throw new Error('ClientRunDebugEntryDenied');
                  original.revision = witness.revision;
                  stopWaiting(wait);
                } catch (cause) {
                  stopWaiting(wait, cause);
                  // The funded caller's receipt records the committed
                  // acceptance. The original Driver receives this failure.
                  if (receiptOriginal === undefined) throw cause;
                }
              },
            }, control);
          }
          // An exact retry can read the receipt, but cannot take the live handoff.
          if (waiting === wait && result?.kind === 'resume_accepted') {
            wait.unresolved = true;
            throw reconciliationRequired();
          }
          return result;
        } catch (cause) {
          // A lost reply may have consumed this durable pause. Keep the
          // original wait for cancellation/expiry and allow receipt lookup.
          // Known refusals leave any still-current pause usable.
          if (cause?.outcome === 'unknown' && waiting === wait) wait.unresolved = true;
          throw cause;
        } finally {resuming = false;}
      },
      taskControl: Object.freeze({
        phase,
        waitForResume(actual, waitSignal) {
          const original = live;
          if (original === undefined || waitSignal !== original.signal || waiting !== undefined || phase(actual) !== 'paused') {
            throw new Error('ClientRunDebugEntryOriginalUnavailable');
          }
          const boundary = checked(pause.call(moon, original.profile, original.owner, original.setup, original.startRevision));
          requireCurrent(original);
          const controlRevision = runtimeField(boundary, 0), stepId = runtimeField(boundary, 1),
            nextOriginal = runtimeField(boundary, 2), committedGeneration = runtimeField(boundary, 3);
          if (typeof nextOriginal !== 'string') throw new Error('ClientRunDebugEntryOriginalUnavailable');
          const nextStepId = nextOriginal === '' ? null : nextOriginal;
          const parked = journal.parkDebugTask(original.authority.ref, {
            startRevision: original.startRevision, expectedRevision: original.revision, controlRevision, stepId,
            nextStepId, committedGeneration, current,
          }, control);
          requireCurrent(original);
          if (parked?.kind === 'expired') throw new Error('ClientRunDebugEntryExpired');
          if (parked?.kind !== 'parked' || parked.revision !== original.revision + 1 ||
              parked.controlRevision !== controlRevision || parked.stepId !== stepId || parked.nextStepId !== nextStepId ||
              parked.committedGeneration !== committedGeneration || !Number.isSafeInteger(parked.expiresAt)) {
            throw new Error('ClientRunDebugEntryOriginalUnavailable');
          }
          return holdPause(parked, waitSignal);
        },
      }),
      beginDrain() {
        hostClosing = true;
        if (waiting !== undefined) stopWaiting(waiting,
          new DebugPauseHostClosing());
      },
      close() {
        live = undefined;
        if (waiting !== undefined) stopWaiting(waiting, new Error('ClientRunDebugEntryOriginalUnavailable'));
      },
    });
  };
}

// The existing dispatch entry owns the Journal writer until cleanup. A
// prepared Driver only receives a synchronous port to the checked prefix.
function selectedSampleAdoption(entry, visit, hostConnection, authority, authorizeSampleCapture, owner, profile) {
  let writer, armed = false;
  const unavailable = () => {throw new Error('ClientRunSampleStartOriginalUnavailable');};
  const active = () => armed && entry !== undefined && entry.computeStartAttempted &&
    !entry.abort.signal.aborted;
  const scope = {
    captureAdoption(original) {
      if (entry === undefined || writer !== undefined || typeof original !== 'function') unavailable();
      writer = original;
    },
    requireWriter() {
      if (typeof writer !== 'function' || entry === undefined) unavailable();
    },
    arm() {armed = true;},
    adopt(prefix) {
      const current = scope.driver.current;
      if (!current()) unavailable();
      let receipt;
      const write = writer;
      visit(prefix, current, ticket => {receipt = write(ticket);});
      if (!current() || receipt === undefined) unavailable();
      return receipt;
    },
    close() {
      armed = false;
      writer = visit = authority = entry = undefined;
      owner = profile = undefined;
    },
  };
  scope.driver = Object.freeze({
    get owner() {return owner;},
    get profile() {return profile;},
    maxWireBytes: localContractLimits.maxWireBytes,
    maxNodes: localContractLimits.maxNodes,
    maxDepth: localContractLimits.maxDepth,
    current() {
      if (!active() || hostConnection(authority) !== true || !active()) return false;
      const outcome = authorizeSampleCapture(authority);
      if (typeof outcome?.then === 'function') void Promise.resolve(outcome).catch(() => {});
      return outcome === true && active() && hostConnection(authority) === true && active();
    },
    adopt(prefix) {scope.adopt(prefix);},
  });
  return scope;
}

export function installNodeClientDispatchOwner({moon, control, journal,
  store, checkpoints, startRun, hostConnection, beforeDispatch, observed,
  prepareAcquisition, planFor, sourceProfile, registry, values, fragment,
  ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
  faultInjection, runInfer, runContent, computeConfigurations = {},
  observation, preparationCustody, beforePublication, authorizeLogicalObservation, authorizeSampleCapture, prepareSampleStart,
  prepareDebugEntryResume,
  managedComputeRequired = false,
  retainedRelationOutput = false,
  runPublished = runPublishedCapturedStrategy}) {
  const entries = new Map();
  let draining = false;
  const capturedRun = moon?.strategyHostRun;
  const diagnostic = diagnosticObserver(observed);
  const diagnosticErrorType = Error;
  const diagnosticStackFormatter = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace')?.value;
  const step = async (name, detail) => {
    diagnostic(name, detail);
    await faultInjection?.(name, detail);
  };
  const keyOf = ref => ref.runDefinitionCid;
  const current = ref => entries.get(keyOf(ref));
  const resourceUsage = ledger => {
    const usage = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    return ledgerUsageDiagnostic(usage);
  };
  const cancel = ref => current(ref)?.abort.abort(
    new Error('ClientRunCancellationRequested'));
  const live = ref => current(ref)?.settled === false;

  function controlledDebugTask(ref, {principalId, connection, authorize}, consume) {
    const entry = current(ref);
    const original = entry?.debugControl;
    const authority = {principalId, connection, ref};
    if (entry === undefined || entry.ref.namespaceId !== ref.namespaceId ||
        entry.ref.authorityScopeCid !== ref.authorityScopeCid || original === undefined ||
        typeof authorize !== 'function') throw new Error('ClientRunDebugEntryOriginalUnavailable');
    const allowed = () => entry.debugControl === original &&
      hostConnection(authority) === true && authorize() === true &&
      entry.debugControl === original && hostConnection(authority) === true;
    return consume(original, allowed);
  }
  const observeDebugTask = (ref, actor) => controlledDebugTask(ref, actor,
    (owner, allowed) => owner.observePause(allowed));
  const observeDebugInspect = (ref, actor) => current(ref)?.debugControl === undefined ? undefined :
    controlledDebugTask(ref, actor, (owner, allowed) => owner.observePause(allowed, true));
  const readDebugNextSample = (ref, actor, selected, reserve, bindProducer) => controlledDebugTask(ref, actor,
    (owner, allowed) => owner.readNextSample(selected, allowed, reserve, bindProducer));
  const resumeDebugTask = (ref, actor, commandWire) => {
    if (typeof actor.reserve !== 'function' || current(ref)?.debugControl === undefined) {
      throw Object.assign(new Error('ClientOperationUnavailable'), {code: 'ClientOperationUnavailable'});
    }
    return controlledDebugTask(ref, actor, (owner, allowed) => owner.resumeTask(commandWire, allowed, actor.reserve));
  };
  const lookupDebugResume = ({run_ref: ref, operation_id: operationId, command_cid: commandCid,
    accepted_from_revision: acceptedFromRevision}, {principalId, connection, authorize, reserve, reserveConstruction}) => {
    const authority = {principalId, connection, ref};
    if (typeof authorize !== 'function') throw new Error('ClientRunDebugEntryDenied');
    const current = () => hostConnection(authority) === true &&
      authorize() === true && hostConnection(authority) === true;
    return journal.lookupDebugResume(ref, {operationId, commandCid, acceptedFromRevision, current, reserve, reserveConstruction}, control);
  };
  const operation = ref => current(ref)?.promise;
  const credentialRefusalPending = ref => {
    const entry = current(ref);
    return entry?.requestId !== undefined && entry.settled &&
      entry.ref.namespaceId === ref.namespaceId && entry.ref.authorityScopeCid === ref.authorityScopeCid &&
      !entry.stopObserved && isModelCredentialRefusal(entry.primaryFailure);
  };
  const failureMessage = ref => {
    const entry = current(ref);
    return entry === undefined ? undefined : publicBudgetFailureMessage(
      entry.primaryFailure, control?.executionFailureExplanation);
  };

  async function acquireSource(entry, preparedProgram, preparedSource, sourceAccess,
    {captureOnly = false, originalEvidence = false, ledger, occurrence} = {}) {
    if (entry.sourceCapture !== undefined) {
      throw new TypeError('ClientSourceCaptureAlreadyRetained');
    }
    const installedSource = installedSourceFor(sourceProfile,
      preparedSource.checkedSource.sourceRef);
    const captureStartedAt = now();
    await step('acquisition_started', {ref: entry.ref,
      ...(preparedSource.selection === undefined ? {} :
        {selection: preparedSource.selection})});
    entry.physicalStarted = true;
    entry.physicalWorkMayHaveStarted = true;
    const acquisition = acquisitionEndHandoff();
    const measured = observation?.canMeasure('source') ? performance.now() : undefined;
    let returned = false;
    try {
      const open = captureOnly ? installedSource.openCapture : installedSource.open;
      if (typeof open !== 'function') throw new TypeError('InstalledSourceCaptureUnavailable');
      entry.sourceCapture = await open({preparedProgram,
        registry, values, fragment, ordered, sourceAccess,
        signal: entry.abort.signal, preparedSource,
        retainedRelationOutput, ledger,
        reportAcquisitionFailure: acquisition.retain,
        ...(entry.sourceOperationScope === undefined ? {} : {
          originalOperationScope: bindClientSourceOperation(entry.sourceOperationScope,
            journal, store, preparedProgram, preparedSource, occurrence ?? {stage: 0, input: 0, task: 0}),
        })});
      returned = true;
    } catch (error) {
      const ended = acquisition.outcome(error);
      if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
        entry.stopObservationPending = true;
      } else if (ended.recovery !== undefined) {
        entry.cleanupOwner = ended.recovery;
      } else {
        entry.unresolvedCleanup = true;
      }
      throw error;
    } finally {
      if (measured !== undefined) observation.emit('source', 'acquisition_interval',
        {ref: entry.ref, outcome: returned ? 'confirmed' : 'failed'},
        {segment: 'source-acquisition', durationMs: performance.now() - measured});
    }
    const captureCompletedAt = now();
    await step('acquisition_completed', {ref: entry.ref,
      ...(entry.sourceCapture.acquisition === undefined ? {} :
        {acquisition: entry.sourceCapture.acquisition})});
    const evidenceOptions = {authorityScopeCid,
      effectiveDataPolicyCid: entry.sourceCapture.checkedSource.sourceDataPolicyCid};
    let sourceEvidence, sourceEvidenceWire;
    if (originalEvidence) {
      await entry.sourceCapture.prepareSourceEvidenceOriginal(evidenceOptions);
      sourceEvidence = control.takeSourceEvidenceOriginal(entry.sourceCapture.capture);
    } else sourceEvidenceWire = await entry.sourceCapture.issueSourceEvidence(evidenceOptions);
    return {captured: entry.sourceCapture, captureStartedAt, captureCompletedAt,
      sourceEvidence, sourceEvidenceWire};
  }

  async function acquireKeyedSources(entry, preparedProgram, selected, acquired, principalId) {
    const {directAdapter, keyedAdapter, preparedSource, directOccurrence,
      directAccess, keyedAccess, preparedKeyed, acquisition, capacity, ledger, capturedContent,
      managedRun, requestIdentity} = selected;
    // Retain the aggregate before the first await. Compute borrows these
    // inputs; its confirmed close must precede reclamation of either source.
    entry.borrowedSources = true;
    const children = [];
    const closed = new Set();
    entry.sourceCapture = Object.freeze({async close() {
      const failures = [];
      for (const child of [...children].reverse()) {
        if (closed.has(child)) continue;
        try {
          await child.close();
          if (typeof child.cleanup === 'function' &&
              (await child.cleanup() === false || child.cleanupPending() !== false)) {
            throw new Error('ClientSourceCleanupPending');
          }
          closed.add(child);
        } catch (error) {
          failures.push(error);
          // The lookup can still borrow its left capture while stopping.
          // Keep earlier children until that dependent custody is reclaimed.
          break;
        }
      }
      if (failures.length) throw new AggregateError(failures, 'ClientSourceCleanupPending');
    }});
    const open = async (kind, operation) => {
      let returned = false;
      entry.abort.signal.throwIfAborted();
      await step('acquisition_started', {ref: entry.ref, kind,
        resourceUsage: resourceUsage(ledger)});
      entry.physicalWorkMayHaveStarted = true;
      try {
        const child = await operation();
        children.push(child);
        returned = true;
        await step('acquisition_completed', {ref: entry.ref, kind,
          resourceUsage: resourceUsage(ledger)});
        return child;
      } catch (error) {
        if (returned) throw error;
        const ended = acquisitionEndHandoff().outcome(error);
        if (ended.outcome === 'unknown') {
          // A lookup's failed child is source custody, not an execution owner.
          // Keep it alongside the already acquired Direct input for retry.
          if (ended.recovery !== undefined) children.push(ended.recovery);
          else entry.unresolvedCleanup = true;
        }
        throw error;
      }
    };
    const captureStartedAt = now();
    const captured = await open('direct', () => directAdapter.openCapture({preparedProgram,
      registry, values, fragment, ordered, preparedSource,
      occurrence: directOccurrence, sourceAccess: directAccess,
      signal: entry.abort.signal, ledger}));
    const left = checked(moon.clientProgramKeyedCaptureLeftRead(acquisition,
      captured.capture.source()));
    const keyedContent = !capturedContent ? undefined : runContent.captureKeyed({
      preparedProgram, plan: acquired, acquisition, ledger, maxBytes: capacity.maxBytes, maxWork: capacity.maxWork,
      sourceBinding: keyedAdapter.keyedRecoveryBinding(preparedKeyed),
      store, principalId, signal: entry.abort.signal, retainExecution: child => children.push(child)});
    const lookup = await open('keyed', () => keyedAdapter.openKeyedLookup({preparedProgram,
      keyedAcquisition: acquisition, left, ledger, signal: entry.abort.signal,
      originalCapture: captured.capture, keyedContent,
      sourceAccess: keyedAccess, preparedKeyed, maxWork: capacity.maxWork}));
    const evidenceOptions = {authorityScopeCid,
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
    const contentOrInfer = acquired.serializationGraph !== undefined || acquired.kind === 'infer';
    let sourceEvidence, sourceEvidenceWire;
    if (contentOrInfer) sourceEvidenceWire = await captured.issueSourceEvidence(evidenceOptions);
    else {
      await captured.prepareSourceEvidenceOriginal(evidenceOptions);
      sourceEvidence = control.takeSourceEvidenceOriginal(captured.capture);
    }
    const keyedObservation = await lookup.issueObservation({authorityScopeCid, observedAt: now()});
    const effectiveDataPolicyCid = moon.clientProgramPublicationDataPolicyCid(preparedProgram);
    if (effectiveDataPolicyCid === undefined) throw new Error('InstalledKeyedSourcePolicyUnavailable');
    if (contentOrInfer) {
      // Both acquisition children remain in this supervisor's custody. The
      // Content provider borrows their exact sealed inputs; cleanup stops that
      // dependent before closing lookup and its left capture in reverse order.
      return {plan: acquired, acquiredContent: {captured, ledger, sourceEvidenceWire,
        authorityScopeCid, captureStartedAt, captureCompletedAt: now(), keyedObservation,
        keyedLookup: await lookup.borrowSerializationInput(), keyedContent,
        sourceEvidence: control.admitRunEvidence('source_evidence', sourceEvidenceWire,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
        keyedSourceEvidence: control.admitRunEvidence('source_evidence', keyedObservation.sourceEvidenceWire,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})}};
    }
    const plan = acquiredKeyedTaskPublicationPlan({moon, control, acquired,
      publicationOriginal: managedRun === undefined ? undefined
        : {kind: 'installed_run', value: managedRun},
      preparedProgram, captured, sourceEvidence, keyedObservation,
      authorityScopeCid, effectiveDataPolicyCid, captureStartedAt, captureCompletedAt: now(),
      namespaceId, storeAuthorityCid, now});
    const setup = await lookup.openHost({registry, values, fragment, ordered, retainedRelationOutput,
      managedRun, requestIdentity});
    entry.pendingSetup = setup;
    return {plan, setup};
  }

  function retirementReady(entry) {
    return entry.settled && entry.cleanupOwner === undefined &&
        entry.cleanupHandle === undefined && !entry.unresolvedCleanup &&
        entry.sourceCapture === undefined && entry.sourcePreparations === undefined &&
        entry.pendingSetup === undefined && entry.sampleProfileObservation === undefined &&
        entry.sampleAdoption === undefined && entry.debugControl === undefined &&
        !entry.stopObservationPending &&
        !entry.failureObservationPending && !entry.finishPending &&
        !entry.releasePending &&
        (!entry.physicalStarted || entry.stopObserved ||
          !entry.physicalWorkMayHaveStarted);
  }

  function retainBudgetFailureObservation(entry) {
    const message = publicBudgetFailureMessage(entry.primaryFailure,
      control?.executionFailureExplanation);
    if (message === undefined || !entry.stopObserved) return;
    const frame = journal.lookupRunDefinition(entry.ref, moon, control);
    if (frame?.physicalCloseConfirmed !== true || frame.observedTerminalOutcome !== 'failed') return;
    const state = issueInstalledUnpublishedRunState(moon, {
      runId: control.runDefinitionRunId(frame.runDefinition),
      observedAt: now(), resultNames: frame.resultNames,
      dispatchReserved: frame.dispatchReserved,
      preDispatchFailureConfirmed: frame.preDispatchFailureConfirmed,
      cancelledBeforeStart: false, observedTerminalOutcome: 'failed',
      executionUnknown: false,
    });
    if (state.status !== 'failed' || state.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN') return;
    state.terminal_error = {...state.terminal_error, message};
    // The original journal's exact frame and CAS still own this observation.
    // No successful/pending/Unknown state or cleanup fact is issued here.
    journal.publishRunState(frame, state, moon, control);
  }

  function retire(entry) {
    if (retirementReady(entry) && !entry.publishingBudgetDiagnostic) {
      if (!entry.budgetDiagnosticAttempted && entry.primaryFailure !== undefined) {
        entry.budgetDiagnosticAttempted = true;
        entry.publishingBudgetDiagnostic = true;
        try { retainBudgetFailureObservation(entry); }
        catch { /* Optional diagnosis cannot mask the primary or block cleanup. */ }
        finally { entry.publishingBudgetDiagnostic = false; }
        if (!retirementReady(entry) || entries.get(keyOf(entry.ref)) !== entry) return;
      }
      try {
        entry.retirePreparation?.();
      } catch (failure) {
        // Keep the original retirement capability and identity for drain.
        // A settled operation alone does not release preparation custody.
        entry.preparationRetirementFailure = failure;
        return;
      }
      entry.retirePreparation = undefined;
      entry.preparationRetirementFailure = undefined;
      const removed = entries.delete(keyOf(entry.ref));
      // This diagnostic describes the complete original owner, not just its
      // physical children. Preparation/finished and acquisition release have
      // now completed under the unchanged retirement predicate above.
      if (removed && entry.acquisitionLedger !== undefined) {
        try {diagnostic('dispatch_cleanup_completed', {ref: entry.ref,
          resourceUsage: resourceUsage(entry.acquisitionLedger)});}
        catch { /* Optional observation cannot restore or prevent retirement. */ }
      }
    }
  }

  async function observeStop(entry) {
    if (entry.terminalOutcome === 'cancelled' &&
        !await confirmNodeRunCancellation({ref: entry.ref, journal, store,
          checkpoints, moon, control, cleanupConfirmed: true, physicalStopConfirmed: true})) {
      entry.terminalOutcome = null;
    }
    if (entry.observeStopped !== undefined) {
      // An Effect continuation may stop its in-process Compute while its Run
      // waits for approval. Only that common Run owner can publish the
      // observed outcome; absence of a public index does not imply failure.
      await entry.observeStopped(entry.terminalOutcome ?? null);
      entry.stopObservationPending = false;
      entry.stopObserved = true;
      return;
    }
    const primary = entry.primaryFailure instanceof CapturedRunPublicationError
      ? entry.primaryFailure.primaryFailure : entry.primaryFailure;
    await observeNodeRunStop({ref: entry.ref, journal, store, checkpoints,
      moon, control, cleanupConfirmed: true, physicalStopConfirmed: true},
    {failureObserved: !entry.abort.signal.aborted && !(primary instanceof DebugPauseHostClosing)});
    entry.stopObservationPending = false;
    entry.stopObserved = true;
  }

  async function settleCleanupHandle(entry) {
    if (entry.cleanupHandle === undefined) return;
    const handle = entry.cleanupHandle;
    if (handle.status()?.pending === true) await handle.retry();
    if (handle.status()?.pending !== false) {
      throw new Error('ClientDispatchCleanupPending');
    }
    entry.cleanupHandle = undefined;
  }

  function closeSampleAdoption(entry) {
    if (entry.sampleAdoption !== undefined) {
      entry.sampleAdoption.close();
      entry.sampleAdoption = undefined;
    }
  }

  function closeDebugControl(entry) {
    entry.debugControl?.close?.();
    entry.debugControl = undefined;
  }

  async function settleCleanup(entry) {
    closeDebugControl(entry);
    closeSampleAdoption(entry);
    returnSampleProfileObservation(entry);
    const execution = entry.cleanupOwner;
    if (entry.borrowedSources && entry.sourceCapture !== undefined) {
      // Stop Compute before closing any borrowed native input. The same
      // NativePhysical issuer must confirm close before the DAG can release
      // its transferred holding. A failed close retains these exact owners.
      if (execution !== undefined) {
        try { await execution.close(); } catch (failure) { entry.closeFailure ??= failure; }
      }
      if (entry.pendingSetup !== undefined) moon.strategyHostStop(entry.pendingSetup);
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      if (!entry.computeStartAttempted && !entry.unresolvedCleanup) entry.stopObservationPending = true;
    }
    if (entry.pendingSetup !== undefined) {
      moon.strategyHostStop(entry.pendingSetup);
      moon.strategyHostCloseOutputs(entry.pendingSetup);
      if (ledgerUsageHasPendingResources(moon.strategyHostUsage(entry.pendingSetup)) &&
          !(entry.preparationHostBorrow !== undefined &&
            typeof moon.clientProgramPreparationBorrowUsageIsolated === 'function' &&
            moon.clientProgramPreparationBorrowUsageIsolated(entry.preparationHostBorrow, moon.strategyHostRun(entry.pendingSetup)) === true)) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.pendingSetup = undefined;
      // This exact setup has stopped and returned its temporary resources.
      // An unentered Compute needs no execution-owner handoff; the existing
      // Run owner still decides the outcome from current durable facts.
      if (entry.physicalStarted && !entry.computeStartAttempted) {
        entry.stopObservationPending = true;
      }
    }
    if (execution !== undefined) {
      if (typeof execution.close !== 'function' ||
          typeof execution.cleanup !== 'function' ||
          typeof execution.cleanupPending !== 'function') {
        throw new Error('ClientDispatchCleanupOwnerInvalid');
      }
      // close may permanently retain its first rejected Promise. Recovery is
      // owned by cleanup, not by invoking close again or repeating Compute.
      try { await execution.close(); }
      catch (failure) { entry.closeFailure ??= failure; }
      // A failed Store consumer can still pin the completed output. Ask the
      // retained Store owner to settle before retrying the execution's
      // reclamation; cancellation alone still grants neither release.
      await settleCleanupHandle(entry);
      const recovered = await execution.cleanup();
      if (recovered === false || execution.cleanupPending() !== false) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.cleanupOwner = undefined;
      entry.stopObservationPending = true;
    }
    if (entry.sourceCapture !== undefined) {
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      // Acquisition returned successfully, but evidence/plan preparation can
      // fail before Compute has an owner. Closing that exact capture confirms
      // this physical end; it does not confirm an unowned Compute attempt.
      if (!entry.computeStartAttempted) entry.stopObservationPending = true;
    }
    await settleCleanupHandle(entry);
    if (entry.unresolvedCleanup) {
      throw new Error('ClientDispatchCleanupOwnerMissing');
    }
    if (entry.sourcePreparations !== undefined) {
      for (const {source, prepared, retire} of entry.sourcePreparations) {
        Reflect.apply(retire, source, [prepared]);
      }
      entry.sourcePreparations = undefined;
    }
    if (entry.stopObservationPending) await observeStop(entry);
    if (entry.failureObservationPending) {
      journal.markPreDispatchFailure(entry.ref);
      entry.failureObservationPending = false;
    }
    if (entry.physicalStarted && !entry.stopObserved &&
        entry.physicalWorkMayHaveStarted) {
      throw new Error('ClientDispatchStopUnknown');
    }
    observation?.emit('cleanup', 'cleanup_completed', {ref: entry.ref,
      physicalStop: entry.stopObserved ? 'confirmed' : undefined});
  }

  function returnSampleProfileObservation(entry) {
    if (entry.sampleProfileObservation === undefined) return;
    checked(moon.clientProgramReturnLogicalObservation(entry.sampleProfileObservation));
    entry.sampleProfileObservation = undefined;
  }

  function checkSampleProfile(entry, requested, accepted, run, execution, definition, setup, profile) {
    const result = control.prepareClientLogicalObservation(run, execution,
      definition, localContractLimits);
    try {
      entry.sampleProfileObservation = checked(result);
    } catch (error) {
      entry.sampleProfileObservation = moon.clientProgramLogicalObservationCleanup(result);
      throw error;
    }
    const original = journal.originalSubmittedIntent(requested,
      {namespaceId, sampleRunRef: accepted.ref, reserveSampleRead(bytes, previousBytes) {
        control.reserveClientRelationSampleStart(run, requested, execution, definition, setup,
          bytes, false, previousBytes);
        entry.abort.signal.throwIfAborted();
      }}, moon, control);
    if (typeof original?.checkSampleProfile !== 'function') {
      throw new Error('ClientRunSampleStartOriginalUnavailable');
    }
    const profileCheck = original.checkSampleProfile(run, definition,
      entry.sampleProfileObservation, profile, localContractLimits);
    if (profileCheck?.profile === null || typeof profileCheck?.profile !== 'object' ||
        profileCheck.startTicket === null || typeof profileCheck.startTicket !== 'object' ||
        typeof profileCheck.withAdoption !== 'function' ||
        typeof profileCheck.then === 'function') invalidSampleStartReceiver(profileCheck);
    return profileCheck;
  }

  async function finishRun(entry) {
    if (!entry.finishPending) return;
    await entry.finished?.();
    entry.finishPending = false;
  }

  function releaseAcquisition(entry) {
    if (!entry.releasePending) return;
    checkpoints.releaseAcquisition(entry.requestId);
    entry.releasePending = false;
  }

  const start = (submission, requested, accepted, held, finished, gate) => {
    const {principalId: actual, connection} = submission;
    const unstarted = accepted.dispatchReserved !== true ||
      accepted.physicalStartReserved === false &&
      !accepted.preDispatchFailureConfirmed;
    if (entries.has(keyOf(accepted.ref)) || !unstarted ||
        accepted.cancellationRequested) {
      return Promise.resolve('not_started');
    }
    // Held requests can start only from the Checkpoint's admitted resume.
    if (gate === undefined && checkpoints?.heldOrigin(submission.requestId)) {
      return Promise.resolve('not_started');
    }
    let debugResumeCid = held.debugResumeCid;
    const debugEntryExpiresAt = held.debugEntryExpiresAt;
    const parkDebugEntry = debugEntryExpiresAt !== undefined;
    const resumesDebug = parkDebugEntry || debugResumeCid !== undefined;
    let preparationLease = preparationCustody?.begin(submission);
    let preparedProgram = preparationLease === undefined
      ? submission.preparedProgram : preparationLease.preparedProgram;
    let reached;
    const physical = new Promise(resolve => { reached = resolve; });
    const entry = {ref: accepted.ref, requestId: submission.requestId,
      finished, promise: undefined,
      reserved: false, settled: false, abort: new AbortController(),
      physicalStarted: false, physicalStartClaimAttempted: false,
      computeStartAttempted: false,
      failureObservationPending: false, stopObservationPending: false,
      stopObserved: false, physicalWorkMayHaveStarted: false,
      finishPending: false, releasePending: checkpoints !== undefined,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, sourceCapture: undefined};
    if (preparationLease !== undefined) {
      entry.retirePreparation = () => {
        // A settled Run is not an observation-delivery ACK. The same original
        // Request stays owned while any queue/callback still holds its loan.
        if (entry.logicalObservation !== undefined) {
          entry.logicalObservation.close();
          entry.logicalObservation = undefined;
        }
        // The complete retirement predicate has settled callbacks, physical
        // custody and acquisition release. No later drain needs these raw
        // aliases; discard them before the private owner returns its charge.
        preparedProgram = undefined;
        if (held !== undefined) held.plan = undefined;
        submission = requested = accepted = held = finished = gate = undefined;
        entry.finished = undefined;
        entry.observeStopped = undefined;
        for (const field of dispatchFailureFields) {
          entry[field] = dispatchFailureSnapshot(entry[field]);
        }
        releaseDispatchPreparationHost(entry);
        preparationLease.retire();
        preparationLease = undefined;
      };
    }
    entries.set(keyOf(accepted.ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      // Request preparation can already own unentered Source reads. Keep
      // their original retirement ports before a start or authorization
      // refusal; started captures still complete their physical cleanup first.
      const preparedSources = held.preparedSources ?? (held.preparedSource === undefined ? [] : [{
        adapter: installedSourceFor(sourceProfile, held.preparedSource.checkedSource.sourceRef),
        prepared: held.preparedSource,
      }]);
      for (const source of preparedSources) {
        const retire = source.adapter.retirePreparedSource;
        if (retire === undefined) continue;
        if (typeof retire !== 'function') throw new TypeError('InstalledSourceCleanupUnavailable');
        entry.sourcePreparations ??= [];
        entry.sourcePreparations.push({source: source.adapter, prepared: source.prepared, retire});
      }
      const claim = await startRun({identity: requested, namespaceId,
        principalId: actual, connection});
      if (claim.kind !== 'reserved' &&
          !(claim.kind === 'reconcile' &&
            accepted.dispatchReserved === true &&
            accepted.physicalStartReserved === false &&
            !accepted.preDispatchFailureConfirmed)) return;
      entry.reserved = true;
      await step('dispatch_reserved', {ref: claim.ref});
      if (beforeDispatch !== undefined) await beforeDispatch(claim.ref);
      if (entry.abort.signal.aborted) return;
      if (held.plan === undefined) {
        held.plan = planFor(submission, accepted.runDefinition.wire, requested);
      }
      const acquiring = sourceProfile !== undefined &&
        moon.clientProgramAcquisitionCount(preparedProgram) > 0;
      const inferring = held.plan.kind === 'infer';
      const serializing = held.plan.kind === 'serialization';
      const generatingContent = held.plan.serializationGraph !== undefined;
      // Managed Compute publication cannot publish an acquisition Result.
      // Inspect the common checked graph before reserving physical custody or
      // capturing rows. Content and Infer have their own publication owners.
      if (!inferring && !serializing && !generatingContent) {
        if (held.managedRun !== undefined &&
            typeof moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication !== 'function') {
          throw new TypeError('InstalledManagedSourcePlanUnavailable');
        }
        const requiresAcquisitionResult = held.managedRun === undefined
          ? moon.clientProgramRequiresAcquisitionResultPublication(preparedProgram)
          : checked(moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication(
            held.managedRun, preparedProgram, requested));
        if (requiresAcquisitionResult) throw new TypeError('InstalledAcquisitionResultPublicationUnsupported');
      }
      // A checked model barrier is not a Values task. The installed Model
      // connection must consume this exact plan and transfer physical custody
      // before advancing; this supervisor still owns the one Run-start claim.
      if (inferring && typeof runInfer !== 'function') {
        throw new Error('InstalledInferDispatchUnavailable');
      }
      if ((serializing || generatingContent) && typeof runContent !== 'function') {
        // Only the Host's installed physical composition may consume this
        // checked Content plan. Never execute it as dense Relation/Values.
        throw new Error('InstalledContentDispatchUnavailable');
      }
      const multiple = held.preparedSources?.length === 2;
      const keyedAcquisition = held.keyedSource?.acquisition ?? (typeof moon.clientProgramSelectSingleKeyedAcquisition === 'function'
        ? checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram)) : undefined);
      if (keyedAcquisition !== undefined && (multiple ||
          inferring && !generatingContent && typeof runInfer.prepareKeyedLedger !== 'function')) {
        throw new Error('InstalledKeyedSourceRunProfileUnsupported');
      }
      if (keyedAcquisition !== undefined && checkpoints !== undefined && held.keyedSource === undefined) {
        // A listing-only inventory must not authorize keyed content I/O.
        throw new Error('InstalledKeyedSourceAdmissionInventoryUnavailable');
      }
      if (inferring && multiple && typeof sourceProfile?.modelPreparation !== 'function') {
        throw new Error('InstalledInferMultiSourceUnsupported');
      }
      const installedSource = acquiring && !multiple
        ? installedSourceFor(sourceProfile, held.preparedSource.checkedSource.sourceRef) : undefined;
      if (retainedRelationOutput && !inferring && installedSource !== undefined &&
          installedSource.supportsRetainedRelationOutput !== true) {
        throw new TypeError('InstalledSourceRetainedOutputUnsupported');
      }
      let ledger;
      let keyedSelection;
      const selectedSources = [];
      if (keyedAcquisition !== undefined) {
        const coordinates = moon.clientProgramKeyedDirectAcquisitionCoordinates(keyedAcquisition);
        if (coordinates === undefined || installedSource === undefined) {
          throw new Error('InstalledKeyedSourcePreparationUnavailable');
        }
        const directOccurrence = {stage: runtimeField(coordinates, 0), input: runtimeField(coordinates, 1), task: runtimeField(coordinates, 2)};
        const directAccess = checkpoints?.acquisitionAccess(submission.requestId,
          installedSource.sourceAccess, {...directOccurrence,
            checkedSource: held.preparedSource.checkedSource,
            readTuple: held.preparedSource.readTuple,
            physicalBinding: held.preparedSource.physicalBinding,
            ...(held.keyedSource === undefined ? {} : {installationBinding: {
              connectorId: installedSource.connectorBindings[0].connectorId,
              connectorRegistration: installedSource.connectorRegistration,
              connectorRevision: installedSource.connectorRevision,
              bindingCid: installedSource.connectorBindings[0].bindingCid}})}) ?? installedSource.sourceAccess;
        const preparedSource = directAccess === held.preparedSourceAccess ? held.preparedSource :
          await prepareAcquisition(preparedProgram, directAccess, directOccurrence,
            held.managedRun === undefined ? undefined : held.preparedSource);
        const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
        const keyedAdapter = installedSourceFor(sourceProfile, facts[0]);
        if (typeof installedSource.openCapture !== 'function' ||
            typeof keyedAdapter.openKeyedLookup !== 'function' ||
            typeof keyedAdapter.keyedLedgerCapacity !== 'function') {
          throw new Error('InstalledKeyedSourceCapacityUnavailable');
        }
        const direct = installedSource.ledgerCapacity(preparedSource);
        const capacity = keyedAdapter.keyedLedgerCapacity(keyedAcquisition);
        const capturedContent = keyedAdapter.requiresRunContentCapture === true;
        if (capturedContent && typeof runContent?.captureKeyed !== 'function') {
          throw new Error('InstalledContentCaptureUnavailable');
        }
        const retainedKeyed = held.keyedSource;
        const keyedAccess = retainedKeyed === undefined ? keyedAdapter.sourceAccess
          : checkpoints?.acquisitionAccess(submission.requestId, keyedAdapter.sourceAccess,
            {...retainedKeyed.occurrence, checkedSource: retainedKeyed.prepared.checkedSource,
              readTuple: retainedKeyed.prepared.readTuple, physicalBinding: retainedKeyed.prepared.physicalBinding,
              installationBinding: {connectorId: keyedAdapter.connectorBindings[0].connectorId,
                connectorRegistration: keyedAdapter.connectorRegistration, connectorRevision: keyedAdapter.connectorRevision,
                bindingCid: keyedAdapter.connectorBindings[0].bindingCid}}) ?? keyedAdapter.sourceAccess;
        const preparedKeyed = retainedKeyed === undefined ? undefined :
          (await keyedAdapter.prepareKeyed({preparedProgram, keyedAcquisition,
            requestIdentity: retainedKeyed.requestIdentity, sourceAccess: keyedAccess})).prepared;
        // Captured Content must retain the admitted physical read binding.
        // Refuse missing custody before reserving a start or listing any rows;
        // acquisition rechecks that binding before issuing its Content frame.
        if (capturedContent) {
          if (typeof keyedAdapter.keyedRecoveryBinding !== 'function') {
            throw new Error('InstalledCapturedContentBindingUnavailable');
          }
          keyedAdapter.keyedRecoveryBinding(preparedKeyed);
        }
        const managedKeyed = !generatingContent && !inferring && direct.managedRun !== undefined;
        if (managedKeyed) {
          if (direct.managedRun !== held.managedRun ||
              typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
            throw new Error('InstalledKeyedSourceOriginalRunUnavailable');
          }
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested,
            preparationLease !== undefined);
          // The retained Plan already owns Direct and Compute. Borrow its
          // SAME Ledger; each actual keyed RowRun/lookup admits and grows its
          // own demand there before use. A full budget is not another cost.
          ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
            held.managedRun, preparedProgram, requested, [direct.capacity],
            [direct.transferBytes], [direct.executionBytes], registry, values, fragment, ordered));
        } else ledger = generatingContent ? runContent.prepareKeyedLedger({preparedProgram, plan: held.plan,
          direct, acquisition: keyedAcquisition, capacity, capturedContent}) :
          inferring ? runInfer.prepareKeyedLedger({preparedProgram, plan: held.plan,
            direct, acquisition: keyedAcquisition, capacity, capturedContent}) :
          moon.clientProgramPrepareKeyedCapturedLocalInstalledLedger(preparedProgram,
          direct.capacity, keyedAcquisition, capacity.capacity,
          [direct.transferBytes, capacity.transferBytes], [direct.executionBytes, capacity.executionBytes],
          capacity.maxBytes, capacity.maxWork, registry, values, fragment, ordered, capturedContent);
        if (ledger === undefined) throw new Error('InstalledKeyedSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
        keyedSelection = {directAdapter: installedSource, keyedAdapter, preparedSource,
          directOccurrence, directAccess, keyedAccess, preparedKeyed,
          acquisition: keyedAcquisition, capacity, ledger, capturedContent,
          ...(managedKeyed ? {managedRun: held.managedRun, requestIdentity: requested} : {})};
      }
      if (multiple) {
        // Read approvals retain their occurrence and physical target. Resolve
        // resumed access before selecting configurations and sizing the one
        // ledger; the exact preparations below also own the subsequent reads.
        const descriptors = ordinarySourceDescriptors(held.preparedSources);
        for (const [index, source] of held.preparedSources.entries()) {
          entry.abort.signal.throwIfAborted();
          const occurrence = descriptors[index];
          const access = checkpoints?.acquisitionAccess(submission.requestId,
            source.sourceAccess, occurrence) ?? source.sourceAccess;
          const preparedSource = access === source.sourceAccess ? source.prepared :
            await prepareAcquisition(preparedProgram, access, source.occurrence);
          if (occurrence.installationBinding !== undefined) {
            verifyOrdinarySourceBinding(source.adapter, preparedSource, occurrence.installationBinding);
          }
          selectedSources.push({...source, access, preparedSource});
        }
        const capacities = selectedSources.map(source => {
          if (retainedRelationOutput &&
              source.adapter.supportsRetainedRelationOutput !== true) {
            throw new TypeError('InstalledSourceRetainedOutputUnsupported');
          }
          if (typeof source.adapter.ledgerCapacity !== 'function') {
            throw new TypeError('InstalledMultiSourceCapacityUnavailable');
          }
          return source.adapter.ledgerCapacity(source.preparedSource);
        });
        const managedRun = capacities[0]?.managedRun;
        if (capacities.some(value => value.managedRun !== undefined)) {
          if (managedRun === undefined || capacities.some(value => value.managedRun !== managedRun) ||
              typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
            throw new Error('InstalledMultiSourceOriginalRunUnavailable');
          }
          // The original operational parent was admitted before preparation.
          // Do not replace it with the legacy scalar accounting constructor,
          // even when another Source has equal capacities or matching CIDs.
          if (inferring) {
            if (held.managedRun !== managedRun || typeof runInfer.prepareAcquiredLedger !== 'function') {
              throw new Error('InstalledMultiSourceOriginalRunUnavailable');
            }
            retainDispatchPreparationHost(entry, moon, managedRun, preparedProgram, requested, preparationLease !== undefined);
            ledger = runInfer.prepareAcquiredLedger({preparedProgram, plan: held.plan, sourceCapacities: capacities});
            entry.borrowedSources = true;
          } else {
          if (capacities.some(value => value.wholeInput === true)) {
            if (capacities.some(value => value.wholeInput !== true) ||
                typeof moon.clientProgramInstalledManagedWholeSourcesLedger !== 'function') {
              throw new Error('InstalledMultiSourceOriginalRunUnavailable');
            }
            ledger = checked(moon.clientProgramInstalledManagedWholeSourcesLedger(
              managedRun, preparedProgram, requested, capacities.map(value => value.capacity),
              capacities.map(value => value.transferBytes), capacities.map(value => value.executionBytes)));
          } else {
          ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
            managedRun, preparedProgram, requested,
            capacities.map(value => value.capacity),
            capacities.map(value => value.transferBytes),
            capacities.map(value => value.executionBytes),
            registry, values, fragment, ordered));
          }
          }
        } else {
          ledger = moon.clientProgramPrepareMultiCapturedLocalInstalledLedger(preparedProgram,
            capacities.map(value => value.capacity),
            capacities.map(value => value.transferBytes),
            capacities.map(value => value.executionBytes),
            registry, values, fragment, ordered);
        }
        if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
      }
      const requestModelAcquired = inferring && !generatingContent && acquiring && !multiple &&
        keyedSelection === undefined && held.managedRun !== undefined;
      if ((generatingContent || requestModelAcquired) && acquiring && keyedSelection === undefined) {
        if (multiple ||
            typeof (requestModelAcquired ? runInfer : runContent).prepareAcquiredLedger !== 'function' ||
            typeof installedSource?.ledgerCapacity !== 'function') {
          throw new Error('InstalledContentAcquiredDispatchUnavailable');
        }
        const access = checkpoints?.acquisitionAccess(submission.requestId,
          installedSource.sourceAccess) ?? installedSource.sourceAccess;
        if (held.preparedSourceAccess !== access) {
          held.preparedSource = await prepareAcquisition(preparedProgram, access, undefined,
            held.managedRun === undefined ? undefined : held.preparedSource);
          held.preparedSourceAccess = access;
        }
        if (requestModelAcquired) {
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
          ledger = runInfer.prepareAcquiredLedger({preparedProgram, plan: held.plan,
            sourceCapacity: installedSource.ledgerCapacity(held.preparedSource)});
          entry.borrowedSources = true;
        } else ledger = runContent.prepareAcquiredLedger({preparedProgram, plan: held.plan,
          sourceCapacity: installedSource.ledgerCapacity(held.preparedSource)});
        entry.acquisitionLedger = ledger;
      }
      const singleAccounted = acquiring && !multiple && keyedSelection === undefined &&
        !inferring && !serializing;
      if (singleAccounted) {
        const access = checkpoints?.acquisitionAccess(submission.requestId,
          installedSource.sourceAccess) ?? installedSource.sourceAccess;
        if (held.preparedSourceAccess !== access) {
          held.preparedSource = await prepareAcquisition(preparedProgram, access, undefined,
            held.managedRun === undefined ? undefined : held.preparedSource);
          held.preparedSourceAccess = access;
        }
        if (typeof installedSource.ledgerCapacity !== 'function') {
          throw new Error('InstalledSingleSourceCapacityUnavailable');
        }
        const capacity = installedSource.ledgerCapacity(held.preparedSource);
        if (capacity.managedRun !== undefined) {
          if (capacity.managedRun !== held.managedRun) {
            throw new Error('InstalledSingleSourceOriginalRunUnavailable');
          }
          if (capacity.wholeInput === true) {
            if (typeof moon.clientProgramInstalledManagedWholeSourceLedger !== 'function') {
              throw new Error('InstalledSingleSourceOriginalRunUnavailable');
            }
            ledger = checked(moon.clientProgramInstalledManagedWholeSourceLedger(
              capacity.managedRun, preparedProgram, requested,
              capacity.capacity, capacity.transferBytes, capacity.executionBytes));
          } else {
            if (typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
              throw new Error('InstalledSingleSourceOriginalRunUnavailable');
            }
            // One Source uses the same operational parent as the checked
            // capture prefix. Equal scalar capacity is not a replacement Run.
            ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
              capacity.managedRun, preparedProgram, requested,
              [capacity.capacity], [capacity.transferBytes], [capacity.executionBytes],
              registry, values, fragment, ordered));
          }
        } else {
          if (capacity.wholeInput === true || held.managedRun !== undefined) {
            throw new Error('InstalledSingleSourceOriginalRunUnavailable');
          }
          ledger = moon.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
            capacity.capacity, capacity.transferBytes, capacity.executionBytes,
            registry, values, fragment, ordered);
        }
        if (ledger === undefined) throw new Error('InstalledSingleSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
      }
      let setup;
      let acquiredInfer;
      let acquiredContent;
      if (!acquiring && !inferring && !serializing) {
        if (managedComputeRequired && held.managedRun === undefined) {
          throw new Error('InstalledManagedComputeRunUnavailable');
        }
        if (held.managedRun !== undefined) {
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
          if (typeof moon.clientProgramOpenInstalledManagedSourceFreeHost !== 'function') {
            throw new Error('InstalledManagedComputeHostUnavailable');
          }
          if (!generatingContent && !Object.hasOwn(held, 'sampleProfile') && preparationLease !== undefined &&
              typeof capturedRun === 'function' && typeof authorizeLogicalObservation === 'function') {
            const logical = prepareInstalledLogicalObservation(moon, control,
              held.managedRun, sourceFreePlanExecutionOwner(held.plan), held.plan.runDefinition, observation);
            if (logical !== undefined) entry.logicalObservation = logical;
          }
          // This opaque Run already owns the original operational Ledger.
          // Missing/foreign/parked originals cannot fall back to accounting.
          setup = checked(moon.clientProgramOpenInstalledManagedSourceFreeHost(
            held.managedRun, preparedProgram, requested, registry, values,
            fragment, ordered, retainedRelationOutput));
        } else {
          const open = retainedRelationOutput
            ? moon.clientProgramOpenSourceFreeLocalRetainedHost
            : moon.clientProgramOpenSourceFreeLocalHost;
          setup = open(
            preparedProgram, registry, values, 1n, 0n, 0n, 0n,
            fragment, ordered);
        }
        if (setup === undefined) throw new Error('ClientProgramNeedsInputs');
        // Retain before the reservation/fault boundary: cancellation can
        // arrive there before runPublished transfers execution custody.
        entry.pendingSetup = setup;
        if (entry.logicalObservation !== undefined) {
          entry.logicalObservation.attach(Reflect.apply(capturedRun, moon, [setup]),
            accepted.ref, actual, operation => authorizeLogicalObservation(operation, connection),
            control.runDefinitionRunId(accepted.runDefinition));
        }
      }
      // The resumed admission and physical start reservation are adjacent.
      if (gate !== undefined) {
        try { gate.beforePhysicalStart(); }
        catch (error) {
          reached({refused: error});
          await settleCleanup(entry);
          return;
        }
      }
      let physicalStarted, taskControl;
      {
        let debugController, debugStart, debugResume;
        if (resumesDebug && (typeof prepareDebugEntryResume !== 'function' ||
            (parkDebugEntry
              ? !Number.isSafeInteger(debugEntryExpiresAt) || debugEntryExpiresAt <= 0 ||
                debugResumeCid !== undefined || !Object.hasOwn(held, 'sampleProfile')
              : typeof debugResumeCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(debugResumeCid)) ||
            acquiring || inferring || serializing || generatingContent ||
            gate !== undefined || setup === undefined || entry.pendingSetup !== setup ||
            held.managedRun === undefined || entry.preparationHostBorrow === undefined)) {
          throw new Error('ClientRunDebugEntryOriginalUnavailable');
        }
        // Transfer the selected writer into the original dispatch entry.
        // The remaining synchronous aliases end before the following awaits.
        let sampleReady, sampleStartSelection, sampleStartRevision, checkedSampleProfile, debugMapCid;
        let sampleRun, sampleExecution, sampleDefinition, sampleCaptured;
        // Only the installed owner can provide this private receiver.
        // The ordinary wire Debug intent does not opt in to unattended resume.
        if (Object.hasOwn(held, 'sampleProfile')) {
          // The already selected Run transfers its original profile once.
          // Merely installing the shared dispatcher never selects a Normal Run.
          const sampleProfile = held.sampleProfile;
          delete held.sampleProfile;
          if ((!resumesDebug && (typeof prepareSampleStart !== 'function' || accepted.dispatchReserved === true)) ||
              sampleProfile === undefined || gate !== undefined || preparationLease === undefined ||
              acquiring || inferring || serializing || generatingContent ||
              held.managedRun === undefined || setup === undefined ||
              entry.pendingSetup !== setup || entry.preparationHostBorrow === undefined) {
            throw new Error('ClientRunSampleStartOriginalUnavailable');
          }
          const execution = sourceFreePlanExecutionOwner(held.plan);
          if (execution === undefined ||
              typeof capturedRun !== 'function' ||
              typeof journal.originalSubmittedIntent !== 'function' ||
              typeof control.prepareClientLogicalObservation !== 'function' ||
              typeof moon.clientProgramLogicalObservationCleanup !== 'function' ||
              typeof moon.clientProgramReturnLogicalObservation !== 'function' ||
              typeof authorizeSampleCapture !== 'function' ||
              typeof control.reserveClientRelationSampleStart !== 'function' ||
              typeof control.acknowledgeClientRelationSampleStart !== 'function') {
            throw new Error('ClientRunSampleStartOriginalUnavailable');
          }
          sampleRun = held.managedRun;
          // The Journal admits its own copy of the definition. Its ACK must
          // match this Run, while the compiler and setup keep their nominal original.
          sampleDefinition = held.plan.runDefinition;
          if (sampleDefinition?.identity !== accepted.ref.runDefinitionCid ||
              sampleDefinition.identity !== accepted.runDefinition.identity ||
              sampleDefinition.wire !== accepted.runDefinition.wire) {
            throw new Error('ClientRunSampleStartOriginalUnavailable');
          }
          control.reserveClientRelationSampleStart(sampleRun, requested, execution, sampleDefinition, setup, undefined, resumesDebug);
          entry.abort.signal.throwIfAborted();
          const {profile: checkedProfile, startTicket, withAdoption, logicalMapCid} = checkSampleProfile(entry, requested, accepted, sampleRun, execution,
            sampleDefinition, setup, sampleProfile);
          returnSampleProfileObservation(entry);
          entry.abort.signal.throwIfAborted();
          // The temporary profile reader and the optional boundary observer
          // reuse one sibling slot on the same Request. Only the latter may
          // stay live through Compute and observation delivery.
          if (typeof authorizeLogicalObservation === 'function') {
            const logical = prepareInstalledLogicalObservation(moon, control,
              sampleRun, execution, sampleDefinition, observation);
            if (logical !== undefined) {
              entry.logicalObservation = logical;
              logical.attach(Reflect.apply(capturedRun, moon, [setup]),
                accepted.ref, actual, operation => authorizeLogicalObservation(operation, connection),
                control.runDefinitionRunId(sampleDefinition));
            }
          }
          entry.abort.signal.throwIfAborted();
          const sampleAuthority = {principalId: actual, connection, ref: accepted.ref};
          if (!resumesDebug) {
            sampleReady = prepareSampleStart(setup, sampleRun, checkedProfile, sampleAuthority);
            if (typeof sampleReady !== 'function') invalidSampleStartReceiver(sampleReady);
          }
          checkedSampleProfile = checkedProfile;
          debugMapCid = logicalMapCid;
          sampleExecution = execution;
          sampleCaptured = Reflect.apply(capturedRun, moon, [setup]);
          if (sampleCaptured === undefined) throw new Error('ClientRunSampleStartOriginalUnavailable');
          entry.sampleAdoption = selectedSampleAdoption(entry, withAdoption, hostConnection,
            sampleAuthority, authorizeSampleCapture, sampleRun, checkedProfile);
          sampleStartSelection = {captureSampleStart: {program: execution.program, compiled: execution.compiled, startTicket,
            captureAdoption: entry.sampleAdoption.captureAdoption,
            captureRevision(revision) { sampleStartRevision = revision; }}};
          entry.abort.signal.throwIfAborted();
        }
        if (resumesDebug) {
          const authority = Object.freeze({principalId: actual, connection, ref: accepted.ref});
          debugController = checkedSampleProfile === undefined
            ? prepareDebugEntryResume(setup, held.managedRun, authority)
            : prepareDebugEntryResume(setup, held.managedRun, authority, checkedSampleProfile,
              entry.abort.signal, debugMapCid, sampleDefinition);
          entry.debugControl = debugController;
          taskControl = debugController?.taskControl;
          if (typeof debugController?.activate !== 'function' || typeof debugController.current !== 'function' ||
              typeof taskControl?.phase !== 'function' || typeof taskControl.waitForResume !== 'function') {
            throw new TypeError('InvalidInstalledTaskController');
          }
          const current = () => !entry.abort.signal.aborted && hostConnection(authority) === true &&
            debugController.current() === true && hostConnection(authority) === true && !entry.abort.signal.aborted;
          if (parkDebugEntry) {
            if (typeof debugController.parkEntry !== 'function' || !Number.isInteger(claim.revision)) {
              throw new Error('ClientRunDebugEntryOriginalUnavailable');
            }
            if (draining) throw new Error('ClientRunDebugEntryHostClosing');
            entry.waitingForDebugEntry = true;
            try {
              debugResumeCid = await debugController.parkEntry(requested, claim.revision, debugEntryExpiresAt);
            } finally {entry.waitingForDebugEntry = false;}
            entry.abort.signal.throwIfAborted();
            if (!current()) throw new Error('ClientRunDebugEntryDenied');
            if (draining) throw new Error('ClientRunDebugEntryHostClosing');
          }
          debugResume = {commandCid: debugResumeCid, current,
            capture(witness) {debugStart = witness;}};
        }
        entry.physicalStartClaimAttempted = true;
        physicalStarted = journal.reservePhysicalStart(requested, {
          namespaceId, ref: accepted.ref,
          currentAuthorization: hostConnection({principalId: actual,
            connection, ref: accepted.ref}),
          ...(!acquiring && !inferring && !serializing && !generatingContent ? {
            localExecutionOwner: sourceFreePlanExecutionOwner(held.plan),
          } : {}),
          ...(acquiring && journal.sourceOperationConfigured === true ? {
            captureSourceOperation: {program: preparedProgram, compiled: held.plan.compiled, store,
              capture(scope) {entry.sourceOperationScope = scope;}},
          } : {}),
          ...sampleStartSelection,
          ...(debugResume === undefined ? {} : {debugResume}),
        }, moon, control);
        if (physicalStarted) {
          // A refusal in the receiver cannot erase the committed start.
          entry.physicalStarted = true;
          entry.finishPending = true;
          if (debugResume !== undefined) {
            if (debugStart?.commandCid !== debugResumeCid ||
                !['step', 'terminal'].includes(debugStart.until) ||
                !Number.isInteger(debugStart.acceptedRevision) || debugStart.acceptedRevision < 1 ||
                debugStart.physicalStartRevision !== debugStart.acceptedRevision + 1 ||
                debugStart.physicalStartRevision > 2147483647 || debugResume.current() !== true) {
              throw new Error('ClientRunDebugEntryOriginalUnavailable');
            }
          }
          // The writer and both acknowledged originals must agree before
          // either Core Sample custody or the live Debug task can advance.
          if (sampleStartSelection !== undefined) {
            if (!Number.isInteger(sampleStartRevision) || sampleStartRevision <= 0 ||
                sampleStartRevision > 2147483647 ||
                (debugStart !== undefined && sampleStartRevision !== debugStart.physicalStartRevision)) {
              throw new Error('ClientRunSampleStartOriginalUnavailable');
            }
            entry.sampleAdoption.requireWriter();
            control.acknowledgeClientRelationSampleStart(sampleRun, requested, sampleExecution,
              sampleDefinition, sampleCaptured, sampleStartRevision);
            entry.abort.signal.throwIfAborted();
          }
          if (debugResume !== undefined) {
            if (sampleStartSelection !== undefined && debugResume.current() !== true) {
              throw new Error('ClientRunDebugEntryDenied');
            }
            const result = debugController.activate(debugStart);
            if (result !== undefined) invalidSampleStartReceiver(result, 'InvalidInstalledTaskController');
            if (debugResume.current() !== true) throw new Error('ClientRunDebugEntryDenied');
          } else if (sampleReady !== undefined) {
            const result = sampleReady();
            if (result !== undefined) invalidSampleStartReceiver(result);
          }
          if (sampleStartSelection !== undefined) {
            entry.abort.signal.throwIfAborted();
            entry.sampleAdoption.arm();
          }
        }
      }
      if (!physicalStarted) {
        await settleCleanup(entry);
        return;
      }
      if (draining) entry.debugControl?.beginDrain?.();
      gate?.started();
      reached('started');
      await step('physical_start_reserved', {ref: accepted.ref});
      const sourceAccess = checkpoints?.acquisitionAccess(
        submission.requestId, installedSource?.sourceAccess) ??
        installedSource?.sourceAccess;
      if (keyedSelection !== undefined) {
        const keyed = await acquireKeyedSources(entry, preparedProgram, keyedSelection, held.plan, actual);
        held.plan = keyed.plan;
        setup = keyed.setup;
        acquiredContent = keyed.acquiredContent;
      } else if (multiple) {
        entry.borrowedSources = true;
        const captures = [];
        const closed = new Set();
        entry.sourceCapture = Object.freeze({async close() {
          const failures = [];
          for (const capture of captures) {
            if (closed.has(capture)) continue;
            try {
              await step('acquisition_cleanup_started', {ref: accepted.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
              await capture.close();
              closed.add(capture);
              diagnostic('acquisition_cleanup_completed', {ref: accepted.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
            }
            catch (error) { failures.push(error); }
          }
          if (failures.length) throw new AggregateError(failures, 'ClientSourceCleanupPending');
        }});
        const captureStartedAt = now();
        const sources = [];
        for (const source of selectedSources) {
          entry.abort.signal.throwIfAborted();
          const {access, preparedSource} = source;
          await step('acquisition_started', {ref: accepted.ref, task: source.occurrence.task,
            selection: preparedSource.selection,
            resourceUsage: resourceUsage(ledger)});
          entry.abort.signal.throwIfAborted();
          entry.physicalWorkMayHaveStarted = true;
          const acquisition = acquisitionEndHandoff();
          const measured = observation?.canMeasure('source') ? performance.now() : undefined;
          let captured;
          let returned = false;
          try {
            captured = await source.adapter.open({preparedProgram, registry, values,
              fragment, ordered, sourceAccess: access, signal: entry.abort.signal,
              preparedSource, occurrence: source.occurrence, ledger,
              reportAcquisitionFailure: acquisition.retain,
              ...(entry.sourceOperationScope === undefined ? {} : {
                originalOperationScope: bindClientSourceOperation(entry.sourceOperationScope,
                  journal, store, preparedProgram, preparedSource, source.occurrence),
              })});
            returned = true;
          } catch (error) {
            const ended = acquisition.outcome(error);
            if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
              entry.stopObservationPending = true;
            } else if (ended.recovery !== undefined) {
              entry.cleanupOwner = ended.recovery;
            } else {
              // Earlier captures settling proves nothing about an unknown
              // current acquisition that handed back no physical owner.
              entry.unresolvedCleanup = true;
            }
            throw error;
          } finally {
            if (measured !== undefined) observation.emit('source', 'acquisition_interval',
              {ref: accepted.ref, task: source.occurrence.task,
                outcome: returned ? 'confirmed' : 'failed'},
              {segment: 'source-acquisition', durationMs: performance.now() - measured});
          }
          captures.push(captured);
          await step('acquisition_completed', {ref: accepted.ref, task: source.occurrence.task,
            acquisition: captured.acquisition,
            resourceUsage: resourceUsage(ledger)});
          const evidenceOptions = {authorityScopeCid,
            effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
          await captured.prepareSourceEvidenceOriginal(evidenceOptions);
          const sourceEvidence = control.takeSourceEvidenceOriginal(captured.capture);
          sources.push({...source, captured, sourceEvidence,
            ...(inferring ? {sourceEvidenceWire: sourceEvidence.wire} : {})});
        }
        const captureCompletedAt = now();
        const effectiveDataPolicyCid = moon.clientProgramPublicationDataPolicyCid(preparedProgram);
        if (effectiveDataPolicyCid === undefined) throw new Error('InstalledMultiSourcePolicyUnavailable');
        if (inferring) {
          acquiredInfer = {sources, ledger, managedRun: held.managedRun, captureStartedAt, captureCompletedAt,
            sourceEvidence: sources.map(source => source.sourceEvidence)};
        } else {
        held.plan = acquiredMultiTaskPublicationPlan({moon, control, acquired: held.plan,
          publicationOriginal: held.managedRun === undefined ? undefined
            : {kind: 'installed_run', value: held.managedRun},
          preparedProgram, sources, authorityScopeCid, effectiveDataPolicyCid,
          captureStartedAt, captureCompletedAt, namespaceId, storeAuthorityCid, now});
        if (held.managedRun !== undefined) {
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
          if (typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
            throw new Error('InstalledManagedComputeHostUnavailable');
          }
          setup = checked(moon.clientProgramOpenInstalledManagedCaptureHost(
            held.managedRun, preparedProgram, requested, captures.map(value => value.capture.source())));
        } else {
          const open = retainedRelationOutput
            ? moon.clientProgramOpenMultiCapturedLocalRetainedHost
            : moon.clientProgramOpenMultiCapturedLocalHost;
          setup = open(preparedProgram,
            captures.map(value => value.capture.source()), ledger, registry, values, fragment, ordered);
        }
        if (setup === undefined) throw new Error('InstalledMultiSourceHostUnavailable');
        entry.pendingSetup = setup;
        const dag = moon.strategyHostRun(setup);
        for (const [slot, captured] of captures.entries()) {
          const occurrence = selectedSources[slot].occurrence;
          captured.capture.retainTask(dag, occurrence.computeTask ?? occurrence.task);
        }
        }
      } else if (acquiring) {
        if (held.preparedSourceAccess !== sourceAccess) {
          held.preparedSource = await prepareAcquisition(preparedProgram,
            sourceAccess, undefined, held.managedRun === undefined ? undefined : held.preparedSource);
          held.preparedSourceAccess = sourceAccess;
        }
        const {captureStartedAt, captureCompletedAt, sourceEvidence, sourceEvidenceWire} =
          await acquireSource(entry, preparedProgram, held.preparedSource, sourceAccess,
            {captureOnly: generatingContent || requestModelAcquired, originalEvidence: singleAccounted || inferring && !generatingContent,
              ledger: generatingContent || singleAccounted || requestModelAcquired ? ledger : undefined,
              occurrence: inferring ? runInfer.sourceOccurrence?.(preparedProgram, 0) : undefined});
        if (generatingContent) {
          acquiredContent = {captured: entry.sourceCapture, ledger, sourceEvidenceWire,
            authorityScopeCid, captureStartedAt, captureCompletedAt,
            sourceEvidence: control.admitRunEvidence('source_evidence', sourceEvidenceWire,
              {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})};
        } else if (inferring) {
          const captured = entry.sourceCapture;
          const input = requestModelAcquired || captured.composedInfer ? undefined : control.admitInferCapturedInput(
            preparedProgram, captured, sourceEvidence, authorityScopeCid,
            captured.checkedSource.sourceDataPolicyCid, captureStartedAt, captureCompletedAt);
          acquiredInfer = {input, captured, adapter: installedSource, preparedSource: held.preparedSource, sourceAccess,
            occurrence: runInfer.sourceOccurrence?.(preparedProgram, 0),
            ...(requestModelAcquired ? {ledger, managedRun: held.managedRun} : {}),
            sourceEvidenceWire: sourceEvidence.wire, captureStartedAt, captureCompletedAt, sourceEvidence};
        } else {
          held.plan = acquiredTaskPublicationPlan({moon, control,
          acquired: held.plan, preparedProgram,
          publicationOriginal: held.managedRun === undefined ? undefined
            : {kind: 'installed_run', value: held.managedRun},
          captured: entry.sourceCapture, sourceEvidence,
          authorityScopeCid,
          effectiveDataPolicyCid: moon.clientProgramPublicationDataPolicyCid(preparedProgram),
          captureStartedAt, captureCompletedAt, namespaceId,
          requestId: submission.requestId, storeAuthorityCid, now});
        }
        if (singleAccounted) {
          // Reuse the existing borrowed-input cleanup order: stop Compute,
          // close its original physical input, then reclaim DAG outputs.
          entry.borrowedSources = true;
          const capture = entry.sourceCapture.capture;
          if (held.managedRun !== undefined) {
            retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
            if (typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
              throw new Error('InstalledManagedComputeHostUnavailable');
            }
            setup = checked(moon.clientProgramOpenInstalledManagedCaptureHost(
              held.managedRun, preparedProgram, requested, [capture.source()]));
          } else {
            setup = moon.clientProgramOpenSingleCapturedLocalHost(preparedProgram,
              capture.source(), ledger, registry, values, fragment, ordered, retainedRelationOutput);
          }
          if (setup === undefined) throw new Error('InstalledSingleSourceHostUnavailable');
          // Retain before binding the borrow: a failed binding still leaves
          // this same Compute owner in child-first cleanup custody.
          entry.pendingSetup = setup;
          capture.retainTask(moon.strategyHostRun(setup), 0);
        } else setup = entry.sourceCapture.setup;
      }
      entry.abort.signal.throwIfAborted();
      entry.physicalWorkMayHaveStarted = true;
      entry.computeStartAttempted = true;
      if (serializing) {
        await runContent({preparedProgram, plan: held.plan, store,
          principalId: actual, signal: entry.abort.signal, acquiredContent,
          retainExecution(execution) {
            if (entry.cleanupOwner !== undefined && entry.cleanupOwner !== execution) {
              throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
            }
            if (typeof execution?.close !== 'function' ||
                typeof execution?.cleanup !== 'function' ||
                typeof execution?.cleanupPending !== 'function') {
              throw new TypeError('ClientDispatchCleanupOwnerInvalid');
            }
            entry.cleanupOwner = execution;
          }});
        // A byte writer or private capture alone is not a public Result. The
        // same committed Store index and physical-close owner govern success.
        if (entry.cleanupOwner === undefined ||
            await store.confirmCommittedIndex(entry.ref) === undefined) {
          throw new Error('InstalledContentPublicationIncomplete');
        }
        entry.publicationCommitted = true;
        await step('computed', {ref: accepted.ref});
        await settleCleanup(entry);
        await finishRun(entry);
        return;
      }
      if (inferring) {
        const result = await runInfer({preparedProgram, plan: held.plan, store,
          preparationHolder: entry.preparationHostBorrow,
          acquiredInfer, acquiredContent,
          ...(acquiredInfer?.sources === undefined ? {} : {
            originalPreparation: sourceProfile.modelPreparation(preparedProgram, held.plan)}),
          submission: Object.fromEntries(['requestId', 'principalId', 'connection',
            'kind', 'input', 'parameters'].filter(key => Object.hasOwn(submission, key))
            .map(key => [key, submission[key]])),
          principalId: actual, signal: entry.abort.signal,
          retainExecution(execution) {
            if (entry.cleanupOwner !== undefined &&
                entry.cleanupOwner !== execution) {
              throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
            }
            if (typeof execution?.close !== 'function' ||
                typeof execution?.cleanup !== 'function' ||
                typeof execution?.cleanupPending !== 'function') {
              throw new TypeError('ClientDispatchCleanupOwnerInvalid');
            }
            entry.cleanupOwner = execution;
          }});
        if (result?.status === 'waiting_checkpoint') {
          const checkpoint = checkpoints?.journal.inspect(result.checkpoint?.checkpointCid);
          if (entry.cleanupOwner === undefined || checkpoint?.kind !== 'model_invocation' ||
              checkpoint.prepareAttemptId !== null ||
              checkpoint.runDefinitionCid !== accepted.ref.runDefinitionCid ||
              checkpoint.runId !== control.runDefinitionRunId(accepted.runDefinition)) {
            throw new Error('InstalledInferWaitingNotCommitted');
          }
          // The fixed input and continuation have reached durable custody.
          // Stopping this physical owner is not a failed or cancelled Run;
          // the Checkpoint lifecycle remains authoritative for its next step.
          entry.observeStopped = () => recordNodeRunPhysicalStop({ref: entry.ref,
            journal, moon, control}, null);
          await step('infer_waiting_checkpoint', {ref: accepted.ref,
            checkpointCid: checkpoint.checkpointCid});
          await settleCleanup(entry);
          await finishRun(entry);
          return;
        }
        if (result?.status === 'needs_reconciliation') {
          const runId = control.runDefinitionRunId(accepted.runDefinition);
          if (entry.cleanupOwner === undefined ||
              checkpoints?.journal.hasUnresolvedModelCalls(runId) !== true) {
            throw new Error('InstalledInferUnknownNotRecorded');
          }
          retainDispatchPrimaryFailure(entry, result);
          // The owner made all permitted progress and retained an entered
          // call without a saved response. Physical stop is not an ordinary
          // failure and cannot turn that call into a completed barrier.
          entry.observeStopped = () => recordNodeRunPhysicalStop({ref: entry.ref,
            journal, moon, control}, null);
          await step('infer_needs_reconciliation', {ref: accepted.ref});
          await settleCleanup(entry);
          await finishRun(entry);
          return;
        }
        // Success is the existing Store's committed index, not merely a
        // returned model value or a completed private capture.
        if (entry.cleanupOwner === undefined ||
            await store.confirmCommittedIndex(entry.ref) === undefined) {
          throw new Error('InstalledInferPublicationIncomplete');
        }
        entry.publicationCommitted = true;
        await step('computed', {ref: accepted.ref});
        await settleCleanup(entry);
        await finishRun(entry);
        return;
      }
      const published = await runPublished(setup,
        {store, plan: held.plan},
        { ...computeConfigurations,
          ...(sourceAccess === undefined ? {} :
            {authorization: sourceAccess.authorization}) },
        entry.abort.signal, undefined, owner => {
          // One synchronous transfer consumes this exact pending setup before
          // either the preflight or completed-execution owner may close it.
          if (entry.cleanupOwner !== undefined ||
              entry.pendingSetup !== undefined && entry.pendingSetup !== setup) {
            throw new Error('ClientDispatchCleanupOwnerAlreadyRetained');
          }
          // The managed driver has returned. Publication may await an
          // independent Store, but it no longer owns a Sample commit visit.
          closeDebugControl(entry);
          closeSampleAdoption(entry);
          entry.cleanupOwner = owner;
          entry.pendingSetup = undefined;
        }, observation === undefined ? undefined : installTaskObservation(({event, task, durationMs}) =>
          observation.emit('compute', event, {ref: accepted.ref, task}, {durationMs}),
          entry.logicalObservation === undefined ? undefined
            : (phase, task) => entry.logicalObservation.project(phase, task)), entry.preparationHostBorrow,
        entry.preparationHostBorrow === undefined ? undefined : () => {
          if (typeof beforePublication !== 'function') throw new Error('PreparationPublicationUnavailable');
          return beforePublication(preparedProgram);
        }, entry.sampleAdoption?.driver, taskControl);
      entry.cleanupOwner = published;
      entry.publicationCommitted = true;
      await step('computed', {ref: accepted.ref,
        outputRepresentations: (published.execution?.completed ?? [])
          .map(task => ({task:task.task,
            representation:task.outputRepresentation})),
        carrierSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.snapshot !== undefined)
          .map(task => ({task:task.task,...task.snapshot})),
        relationSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.relationSnapshot !== undefined)
          .map(task => ({task:task.task,...task.relationSnapshot}))});
      await settleCleanup(entry);
      await finishRun(entry);
    }).catch(async cause => {
      if (!Object.hasOwn(entry, 'primaryFailure')) entry.primaryFailure = cause;
      try {
        const original = entry.primaryFailure;
        const primaryFailure = original instanceof CapturedRunPublicationError
          ? original.primaryFailure : original;
        const issue = primaryFailure?.cause;
        const issueTag = runtimeTag(issue);
        const nestedIssue = runtimeOptionalField(issue, 0);
        const nestedTag = runtimeTag(nestedIssue);
        const leafIssue = runtimeOptionalField(nestedIssue, 0);
        const leafTag = runtimeTag(leafIssue);
        diagnostic('dispatch_failed', {ref: accepted.ref,
          code: cause?.code ?? cause?.message ?? 'ClientDispatchFailed',
          primaryCode: primaryFailure?.code,
          primaryDiagnostic: dispatchFailureSnapshot(primaryFailure)?.primaryDiagnostic ??
            dispatchFailureCodeSite(primaryFailure, diagnosticErrorType, diagnosticStackFormatter),
          cleanupDiagnostic: dispatchFailureSnapshot(primaryFailure)?.cleanupDiagnostic,
          issueTag: issueTag === undefined && Number.isSafeInteger(issue) &&
            issue >= 0 && issue <= 65535 ? issue : issueTag,
          nestedIssueTag: nestedTag === undefined && Number.isSafeInteger(nestedIssue) &&
            nestedIssue >= 0 && nestedIssue <= 65535 ? nestedIssue : nestedTag,
          leafIssueTag: leafTag === undefined && Number.isSafeInteger(leafIssue) &&
            leafIssue >= 0 && leafIssue <= 65535 ? leafIssue
            : Number.isSafeInteger(leafTag) && leafTag >= 0 && leafTag <= 65535 ? leafTag : undefined});
      } catch { /* Optional diagnostics cannot interrupt cleanup. */ }
      const failedExecution = cause instanceof CapturedRunPublicationError
        ? cause.execution : undefined;
      if (cause?.cleanupPending === true) {
        if (typeof cause.cleanupHandle?.status === 'function' &&
            typeof cause.cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = cause.cleanupHandle;
        } else if (failedExecution === undefined && entry.cleanupOwner === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      if (entry.reserved && !entry.physicalStartClaimAttempted &&
          !resumesDebug && !entry.abort.signal.aborted) {
        entry.failureObservationPending = true;
      }
      if (failedExecution !== undefined) entry.cleanupOwner = failedExecution;
      if (entry.physicalStarted && entry.cleanupOwner !== undefined) {
        entry.stopObservationPending = true;
      }
      try { await settleCleanup(entry); }
      catch (cleanupFailure) { entry.cleanupFailure = cleanupFailure; }
      try { await finishRun(entry); }
      catch (failure) { entry.finishFailure = failure; }
    }).finally(() => {
      entry.settled = true;
      reached('not_started');
      try { releaseAcquisition(entry); }
      catch (failure) { entry.releaseFailure = failure; }
      retire(entry);
    });
    // Retain only the originating optional observation, not a new operation
    // or a release receipt. The physical-start barrier remains independent.
    try {observation?.retainOperation?.(entry.promise);} catch { /* Optional metadata. */ }
    return physical;
  };

  // The installed Effect Run owner supplies the already-admitted operation.
  // This is the same physical supervisor as ordinary dispatch, not another
  // Run-start or Effect retry engine. It never invokes run again during drain.
  // The callback must transfer cleanup custody before any fallible operation
  // that can retain resources. Its common Run observer records the stop
  // independently from waiting, failed, unknown or published outcome.
  const track = (ref, {run, observeStopped,
    barrierFailureOutcome = null}) => {
    if (typeof ref?.runDefinitionCid !== 'string' ||
        typeof run !== 'function' || typeof observeStopped !== 'function') {
      throw new TypeError('InvalidClientOwnedDispatch');
    }
    const existing = current(ref);
    if (existing !== undefined) return existing.promise;
    const entry = {ref: Object.freeze({...ref}), settled: false,
      abort: new AbortController(), observeStopped,
      // The original Run-start claim does not prove that this continuation
      // began physical work. The installed Site marks that boundary itself.
      physicalStarted: false, physicalWorkMayHaveStarted: false,
      stopObserved: false, stopObservationPending: false,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, runInvoked: false};
    entries.set(keyOf(ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      if (beforeDispatch !== undefined) await beforeDispatch(ref);
      entry.abort.signal.throwIfAborted();
      entry.runInvoked = true;
      return run(Object.freeze({
      signal: entry.abort.signal,
      acquireSource({preparedProgram, preparedSource, sourceAccess}) {
        return acquireSource(entry, preparedProgram, preparedSource, sourceAccess, {originalEvidence: true});
      },
      beginPhysicalWork() {
        entry.physicalStarted = true;
        entry.physicalWorkMayHaveStarted = true;
      },
      observePreEffectFailure() {
        // Only the installed opening boundary can assert this: acquisition
        // or Compute failed before the Effect adapter was invoked. This is
        // an outcome observation, not a physical stop or cleanup exemption.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : 'failed';
      },
      retainExecution(execution) {
        if (entry.cleanupOwner !== undefined &&
            entry.cleanupOwner !== execution) {
          throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
        }
        if (typeof execution?.close !== 'function' ||
            typeof execution?.cleanup !== 'function' ||
            typeof execution?.cleanupPending !== 'function') {
          throw new TypeError('ClientDispatchCleanupOwnerInvalid');
        }
        entry.cleanupOwner = execution;
      },
      }));
    }).then(async result => {
      if (result?.status === 'needs_reconciliation') {
        retainDispatchPrimaryFailure(entry, result);
      }
      // A trusted installed Site may confirm that a pre-Preview refusal
      // performed no external Effect dispatch. Record that observation only
      // after its physical owner has stopped and cleanup has completed.
      if (result?.status === 'failed_without_effect_dispatch' ||
          result?.status === 'failed_effect_set') {
        entry.terminalOutcome = 'failed';
      }
      await settleCleanup(entry);
      return result;
    }).catch(async cause => {
      if (!Object.hasOwn(entry, 'primaryFailure')) entry.primaryFailure = cause;
      try {
        const original = entry.primaryFailure;
        const primaryFailure = original instanceof CapturedRunPublicationError
          ? original.primaryFailure : original;
        const issue = primaryFailure?.cause;
        const issueTag = runtimeTag(issue);
        const nestedIssue = runtimeOptionalField(issue, 0);
        const nestedTag = runtimeTag(nestedIssue);
        const leafIssue = runtimeOptionalField(nestedIssue, 0);
        const leafTag = runtimeTag(leafIssue);
        diagnostic('dispatch_failed', {ref: entry.ref,
          code: cause?.code ?? 'ClientDispatchFailed',
          primaryCode: primaryFailure?.code,
          primaryDiagnostic: dispatchFailureSnapshot(primaryFailure)?.primaryDiagnostic ??
            dispatchFailureCodeSite(primaryFailure, diagnosticErrorType, diagnosticStackFormatter),
          issueTag: issueTag === undefined && Number.isSafeInteger(issue) &&
            issue >= 0 && issue <= 65535 ? issue : issueTag,
          nestedIssueTag: nestedTag === undefined && Number.isSafeInteger(nestedIssue) &&
            nestedIssue >= 0 && nestedIssue <= 65535 ? nestedIssue : nestedTag,
          leafIssueTag: leafTag === undefined && Number.isSafeInteger(leafIssue) &&
            leafIssue >= 0 && leafIssue <= 65535 ? leafIssue
            : Number.isSafeInteger(leafTag) && leafTag >= 0 && leafTag <= 65535 ? leafTag : undefined});
      } catch { /* Optional diagnostics cannot interrupt original cleanup. */ }
      if (!entry.runInvoked) {
        // A refused execution barrier ran no Site callback. This is a
        // positive no-start observation, not an inferred physical stop.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : barrierFailureOutcome;
        entry.stopObservationPending = true;
      }
      if (cause?.cleanupPending === true) {
        if (typeof cause.cleanupHandle?.status === 'function' &&
            typeof cause.cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = cause.cleanupHandle;
        } else if (entry.cleanupOwner === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      try { await settleCleanup(entry); }
      catch (failure) { entry.cleanupFailure = failure; }
      throw cause;
    }).finally(() => {
      entry.settled = true;
      retire(entry);
    });
    // submit returns its durable RunRef before the owned operation settles.
    // Observation remains available through operation(), without an unhandled
    // rejection when a Client disconnects or never calls wait().
    entry.promise.catch(() => {});
    try {observation?.retainOperation?.(entry.promise);} catch { /* Optional metadata. */ }
    return entry.promise;
  };

  function settleRetainedEntry(entry) {
    if (entry.retainedCleanup !== undefined) return entry.retainedCleanup;
    entry.retainedCleanup = Promise.resolve().then(async () => {
      try {
        await settleCleanup(entry);
        await finishRun(entry);
        releaseAcquisition(entry);
      } catch (failure) { entry.cleanupFailure = failure; }
      retire(entry);
    }).finally(() => {entry.retainedCleanup = undefined;});
    return entry.retainedCleanup;
  }
  // The accepted initial Run retained a physical preparation, but the nominal
  // credential refusal proves this Model never reached Entry. A wait can help
  // settle that exact stopped owner. It cannot restart dispatch or confirm stop.
  const settleCredentialRefusal = ref => credentialRefusalPending(ref)
    ? settleRetainedEntry(current(ref)) : undefined;

  const drain = async () => {
    draining = true;
    for (;;) {
      const running = [...entries.values()].filter(entry => !entry.settled);
      if (running.length === 0) break;
      // Entry pauses have no physical start to join. Started pauses stop
      // via the same Driver and can still owe physical cleanup.
      for (const entry of running) {
        if (entry.waitingForDebugEntry) closeDebugControl(entry);
        else if (entry.physicalStarted) entry.debugControl?.beginDrain?.();
      }
      await Promise.allSettled(running.map(entry => entry.promise));
    }
    for (const entry of [...entries.values()]) {
      await settleRetainedEntry(entry);
    }
    if (entries.size > 0) {
      throw Object.assign(new Error('ClientDispatchCleanupPending'), {
        code: 'ClientDispatchCleanupPending',
        pendingRefs: [...entries.values()].map(entry => entry.ref),
        failures: [...entries.values()].map(entry => ({ref: entry.ref,
          primary: dispatchFailureSnapshot(entry.primaryFailure),
          close: dispatchFailureSnapshot(entry.closeFailure),
          cleanup: dispatchFailureSnapshot(entry.cleanupFailure),
          finish: dispatchFailureSnapshot(entry.finishFailure),
          release: dispatchFailureSnapshot(entry.releaseFailure),
          preparation: dispatchFailureSnapshot(entry.preparationRetirementFailure)})),
      });
    }
  };
  return Object.freeze({start, track, cancel, live, operation, failureMessage, drain,
    credentialRefusalPending, settleCredentialRefusal, observeDebugTask, resumeDebugTask, lookupDebugResume,
    readDebugNextSample, observeDebugInspect});
}
