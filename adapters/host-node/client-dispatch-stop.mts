import type {openClientRequestJournal} from './client-request-journal.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';

type Journal = ReturnType<typeof openClientRequestJournal>;
type LookupRun = Journal['lookupRunDefinition'];
type RunRef = Parameters<LookupRun>[0];
type RunFrame = NonNullable<ReturnType<LookupRun>>;
type CancellationFacts = Readonly<{
  cancellationRequested: boolean;
  modelFenceRequired: boolean;
  modelFenced: boolean;
  unresolvedModelCalls: boolean;
  unresolvedEffects: boolean;
  reconciliationRequired: boolean;
  publicationCommitted: boolean;
  physicalStopConfirmed: boolean;
  cleanupConfirmed: boolean;
  revisionUnchanged: boolean;
}>;
type ModelJournal = Readonly<{
  discoverModelCallSets: (selection: Readonly<{runId: string; limit: 1}>) => readonly unknown[];
  modelCancellationFenced?: (runId: string, runDefinitionCid: string) => boolean;
  hasUnresolvedModelCalls: (runId: string) => boolean;
  getRunState?: (runId: string) => Readonly<{status: string}> | undefined;
}>;
type RunIdentity = Readonly<{
  ref: RunRef;
  journal: Pick<Journal, 'lookupRunDefinition' | 'markPhysicalClose'>;
  moon: Parameters<LookupRun>[1];
  control: Parameters<LookupRun>[2];
}>;
type StopFacts = RunIdentity & Readonly<{
  journal: RunIdentity['journal'] & Pick<Journal, 'lookupReconciliationState'> &
    Partial<Pick<Journal, 'canReinspectRunStopAfterStatePublication' | 'observeStoppedLocalExecutionOwner'>>;
  store: Pick<Awaited<ReturnType<typeof openLocalPublicationStore>>, 'confirmCommittedIndex'>;
  control: RunIdentity['control'] & Readonly<{
    runDefinitionRunId: (definition: RunFrame['runDefinition']) => string;
    runCancellationConfirmed: (facts: CancellationFacts) => boolean;
  }>;
  checkpoints?: Readonly<{journal?: ModelJournal}>;
  cleanupConfirmed?: boolean;
  physicalStopConfirmed?: boolean;
}>;
type Continuation = StopFacts & Readonly<{
  currentDispatchIdle: () => boolean;
  checkpoints: NonNullable<StopFacts['checkpoints']> & Readonly<{
    cancelEffectContinuation: (runId: string, runDefinitionCid: string) => boolean;
  }>;
}>;

// Terminal observation only, never a send or cancellation permission. The
// physical owner calls this after confirmed stop and temporary reclamation;
// restored observers use their persisted physical-close confirmation.
async function collectNodeRunStop({ref, journal, store,
  checkpoints, moon, control, cleanupConfirmed, physicalStopConfirmed = false}: StopFacts, originalFrame?: RunFrame) {
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

export async function observeNodeRunCancellation(facts: StopFacts, originalFrame?: RunFrame) {
  if (typeof facts.journal?.lookupRunDefinition !== 'function' ||
      typeof facts.journal?.lookupReconciliationState !== 'function') return {cancelled: false};
  const before = originalFrame ?? facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control);
  let observation = await collectNodeRunStop(facts, before);
  // A public status publication can race this asynchronous Store inspection.
  // Recollect every fact once only when the Journal proves that all control
  // and immutable fields remained exact; never accept a changed frame itself.
  if (observation.revisionUnchanged === false &&
      facts.journal.canReinspectRunStopAfterStatePublication?.(before!, observation.frame!) === true) {
    observation = await collectNodeRunStop(facts, observation.frame);
  }
  return observation;
}

export async function confirmNodeRunCancellation(facts: StopFacts) {
  return (await observeNodeRunCancellation(facts)).cancelled;
}

export async function cancelNodeRunContinuation({currentDispatchIdle, ...facts}: Continuation) {
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

export async function observeNodeRestoredLocalStop(facts: StopFacts) {
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
          facts.journal.canReinspectRunStopAfterStatePublication?.(before, retained!) === true) continue;
      throw new Error('ClientRunStopObservationChanged');
    }
    if (facts.journal.observeStoppedLocalExecutionOwner(facts.ref, retained) !== true ||
        facts.journal.lookupReconciliationState(facts.ref) !== undefined) return;
    facts.journal.markPhysicalClose(facts.ref, committed ? null : 'failed', retained);
    return;
  }
  throw new Error('ClientRunStopObservationChanged');
}

export async function observeNodeRestoredModelStop(facts: StopFacts) {
  return observeNodeRunStop(facts, {failureObserved: false});
}

export function recordNodeRunPhysicalStop({ref, journal, moon, control}: RunIdentity, outcome: Parameters<Journal['markPhysicalClose']>[1]) {
  const retained = journal.lookupRunDefinition(ref, moon, control);
  if (retained?.physicalCloseConfirmed === true) return;
  journal.markPhysicalClose(ref, outcome, retained);
}

export async function observeNodeRunStop(facts: StopFacts, {failureObserved}: Readonly<{failureObserved: boolean}>) {
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
      if(inspection===0&&facts.journal.canReinspectRunStopAfterStatePublication?.(before,retained!)===true) continue;
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
