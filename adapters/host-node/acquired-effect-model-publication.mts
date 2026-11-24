import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {preparePrivatePublicationHolding} from '../host-common/private-publication-holding.mjs';
import {fundedInferCaptureInventoryCount, originalInferEvidenceCopyFunding, startCompleteInferObservation}
  from './infer-operation.mjs';
import type {openNodeComposedInferProvider} from './infer-operation.mjs';
import type {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {projectInferEvidence} from './infer-evaluation-evidence.mjs';

type Projection = Parameters<typeof projectInferEvidence>[0];
type Capture = ReturnType<typeof openNodeInferCaptureCustody>;
type Operation = NonNullable<ReturnType<ReturnType<typeof openNodeComposedInferProvider>['operation']>>;
type EvidenceCopy = Parameters<Projection['retainCopy']>[0];
type HoldingName = 'observation_set' | 'run_invocation';
type Evidence = Readonly<{name: HoldingName; wire: string; identity: string}>;
type Acquired = Readonly<{
  prepared: unknown; authorityScopeCid: string; storeAuthorityCid: string;
  control: Projection['control'] & Readonly<{
    modelPrivateHoldingCid(definition: unknown, authority: string, role: HoldingName, slot: number): string;
  }>;
}>;
type Publication<Plan> = Readonly<{observation: Evidence; invocation: Evidence; plan: Plan}>;
type PublicationInputs = Readonly<{
  acquired: Acquired; sources: readonly unknown[] | undefined; compiled: unknown;
  operation: Operation; operations: readonly Operation[]; issuance: unknown;
  modelEvidence: readonly unknown[]; keyedSource: unknown; captureStartedAt: string | undefined;
  captureCompletedAt: string | undefined; sourcePlan: unknown; managedRun: unknown; sourceHost: unknown;
  sourceUnitsOriginal: unknown; deferCatalogs: boolean; signal?: AbortSignal; fundingOperation?: Operation;
  current(): void; retainBinding(binding: unknown): void;
}>;
type Runtime = Projection['moon'] & Parameters<typeof startCompleteInferObservation>[0]['moon'] &
  Parameters<typeof originalInferEvidenceCopyFunding>[0]['moon'] & Readonly<{
    clientProgramAdvanceInferObservationIssuance(issuance: unknown, work: number): unknown;
    clientProgramCancelInferObservationIssuance(issuance: unknown): boolean;
    clientProgramCleanupInferObservationIssuance(issuance: unknown): unknown;
    clientProgramReleaseInferInvocationBinding(binding: unknown): boolean;
    clientProgramEffectDefinitionCid(prepared: unknown): string;
  }>;
type Child = {
  selection: Projection['selected']; capture?: Capture; operation?: Operation; record?: unknown;
  continuation?: Projection['continuation']; completed?: boolean; copy?: EvidenceCopy; copyCloseAttempted?: boolean;
};
type Options<Plan> = Readonly<{
  moon: Runtime; acquired: Acquired; children: readonly Child[]; preparedProgram: unknown;
  plan: Projection['plan']; store: Parameters<typeof preparePrivatePublicationHolding>[0]; signal?: AbortSignal;
  inferEvidence?: Projection['configuration']; sourcePlan: unknown; managedRun: unknown;
  same(): void; buildPublication(inputs: PublicationInputs): Promise<Publication<Plan>>;
  releaseUnitOutputs(): boolean; preconsumerPending(): boolean; originalHost?(): unknown;
  faultInjection?(event: 'infer_private_holding_commit', facts: Readonly<{role: HoldingName; slot: -1}>): unknown;
  readIdentityRetained(): bigint; readIdentityExecution(): bigint;
  readCaptureStartedAt(): string | undefined; readCaptureCompletedAt(): string | undefined;
  readEvidence(): readonly unknown[] | undefined; readKeyedSource(): unknown; readSourceUnitsOriginal(): unknown;
}>;

export function createAcquiredEffectModelPublication<Plan>({moon, acquired, children, preparedProgram, plan,
  store, signal, inferEvidence, sourcePlan, managedRun, same, buildPublication, releaseUnitOutputs, preconsumerPending,
  originalHost, faultInjection, readIdentityRetained, readIdentityExecution, readCaptureStartedAt,
  readCaptureCompletedAt, readEvidence, readKeyedSource, readSourceUnitsOriginal}: Options<Plan>) {
  let issuance: unknown, issuanceComplete = false, publicationOwner: Operation | undefined,
    publication: Publication<Plan> | undefined, holding: ReturnType<typeof preparePrivatePublicationHolding> | undefined;
  let publicationPreparation: Promise<Plan> | undefined, publicationFailure: unknown, publicationFailed = false;
  let projectionPending = false;
  let retirementRequested = false, publicationRetirement: Promise<boolean> | undefined;
  const publicationBindings: unknown[] = [];
  const retainCompleted = (child: Child) => {
    same();
    publicationOwner ??= child.operation;
    if (!child.capture!.retainCompleted(publicationOwner)) return false;
    child.completed = true;
    if (children.some(member => !member.completed)) return true;
    let calls = 0;
    let allFunded = true;
    for (const member of children) {
      const count = member.capture!.completedCallCount();
      allFunded &&= fundedInferCaptureInventoryCount(member.capture!.completedInventoryReceipt?.(), member.operation) === count;
      if (!Number.isSafeInteger(count) || count! < 0 || count! > 2147483645 - calls ||
          (!allFunded && count! > 128 - calls)) {
        throw new Error('InstalledComposedInferOriginalObservationUnavailable');
      }
      calls += count!;
    }
    issuance ??= startCompleteInferObservation({moon, operations: children.map(member => member.operation!),
      maxSlots: calls, maxWireBytes: 16384, maxWork: calls + 2});
    for (let step = 0; step < calls + 2 && !issuanceComplete; step++) {
      issuanceComplete = runtimeField(checked(moon.clientProgramAdvanceInferObservationIssuance(issuance, 1)), 0) as boolean;
    }
    if (!issuanceComplete) throw new Error('InstalledComposedInferOriginalObservationUnavailable');
    return true;
  };
  const publicationRetained = () => {
    signal?.throwIfAborted();
    if (retirementRequested) throw new Error('InstalledEffectModelPublicationRetired');
  };
  const publicationCurrent = () => {same(); publicationRetained();};
  async function retirePublication() {
    // Retirement shares the original pending preparation. It cannot treat a
    // Promise as a binding, detach it, or publish after that preparation settles.
    retirementRequested = true;
    // A Sink can reenter first close from its own pending callback. It cannot
    // wait on itself: retain this original phase/copy and report Pending.
    if (projectionPending || preconsumerPending()) return false;
    publicationRetirement ??= Promise.resolve().then(async () => {
      if (publicationPreparation !== undefined) {
        try {await publicationPreparation;} catch { /* The persist caller retains its primary failure. */ }
        publicationPreparation = undefined;
      }
      // Retire the same original holding without starting a private write
      // after cancellation/failure. Abort awaits its actual in-flight work,
      // confirms an already committed original, and retains pending cleanup.
      if (holding !== undefined) {await holding.abort(); holding = undefined;}
      for (const child of children) if (child.copy !== undefined) {
        if (child.copy.cleanupPending()) {
          const retry = child.copyCloseAttempted === true; child.copyCloseAttempted = true;
          const result = await (retry ? child.copy.cleanup() : child.copy.close());
          if (result === false || child.copy.cleanupPending()) return false;
        }
        child.copy = undefined;
      }
      while (publicationBindings.length > 0) {
        if (moon.clientProgramReleaseInferInvocationBinding(publicationBindings[0]) !== true) return false;
        publicationBindings.shift();
      }
      publication = undefined;
      if (issuance !== undefined) {
        if (moon.clientProgramCancelInferObservationIssuance(issuance)) checked(moon.clientProgramAdvanceInferObservationIssuance(issuance, 1));
        if (!checked(moon.clientProgramCleanupInferObservationIssuance(issuance))) return false;
        issuance = undefined;
      }
      if (publicationOwner !== undefined) {
        let pending = false;
        for (const child of children) if (child.operation !== undefined && !child.operation.physicalStopped()) await child.operation.stop();
        for (const child of children) if (child.capture !== undefined && !await child.capture.custody.retirePublication()) pending = true;
        if (pending || !releaseUnitOutputs() || !publicationOwner.releaseOriginalPublicationCapacity()) return false;
        publicationOwner = undefined;
      }
      return true;
    });
    const originalRetirement = publicationRetirement;
    try {return await originalRetirement;} finally {
      if (publicationRetirement === originalRetirement) publicationRetirement = undefined;
    }
  }
  async function persistPublication() {
    if (publicationFailed) throw publicationFailure;
    publicationCurrent();
    // Install the shared phase before invoking any callback, including capture
    // persistence. Reentry observes this same phase and cannot issue twice.
    publicationPreparation ??= Promise.resolve().then(async () => {
      publicationCurrent();
      if (!issuanceComplete || issuance === undefined) throw new Error('InstalledComposedInferOriginalObservationUnavailable');
      for (const child of children) {await child.capture!.persist(); publicationCurrent();}
      // Optional projection consumes these SAME Store-confirmed originals
      // before any child, issuance or publication capacity is retired. The
      // original shared phase prevents a second projection on persist reentry;
      // restored Models remain lookup-only and never export their inputs again.
      if (inferEvidence !== undefined) for (const child of children) {
        if (child.record !== undefined) continue;
        publicationCurrent();
        projectionPending = true;
        try {
          await projectInferEvidence({configuration: inferEvidence, moon, control: acquired.control,
            preparedProgram, plan, selected: child.selection, operation: child.operation!,
            // This group retains an Effect Run, not a PreparedClientProgram.
            // Read immutable definition DATA from its same original computation.
            programDefinitionCid: moon.clientProgramEffectDefinitionCid(acquired.prepared),
            captureOwner: child.capture!, continuation: child.continuation,
            current: publicationCurrent,
            authorityScopeCid: acquired.authorityScopeCid,
            copyFunding: originalInferEvidenceCopyFunding({moon, funding: publicationOwner!, operation: child.operation!,
              current: publicationCurrent, retainedPrefix: () => readIdentityRetained(),
              executionPrefix: () => readIdentityExecution()}),
            retainCopy(copy) {
              if (child.copy?.cleanupPending()) throw new Error('InferEvidenceCopyAlreadyRetained');
              child.copy = copy;
            }});
        } finally {projectionPending = false;}
        publicationCurrent();
      }
      publication = await buildPublication({
        acquired, sources: readEvidence(), compiled: plan.compiled,
        operation: children[0].operation!, operations: children.map(child => child.operation!), issuance,
        modelEvidence: children.flatMap(child => child.capture!.modelEvidence()), keyedSource: readKeyedSource(),
        captureStartedAt: readCaptureStartedAt(), captureCompletedAt: readCaptureCompletedAt(), sourcePlan, managedRun, sourceHost: originalHost?.(),
        sourceUnitsOriginal: readSourceUnitsOriginal(), deferCatalogs: managedRun !== undefined && sourcePlan !== undefined,
        signal, fundingOperation: publicationOwner, current: publicationCurrent,
        retainBinding(binding) {publicationBindings.push(binding);}});
      publicationCurrent();
      for (const original of [publication.observation, publication.invocation]) {
        holding = preparePrivatePublicationHolding(store, {name: original.name, wire: original.wire,
          semanticCid: original.identity, holdingCid: acquired.control.modelPrivateHoldingCid(
            plan.runDefinition, acquired.storeAuthorityCid, original.name, -1)});
        await faultInjection?.('infer_private_holding_commit', {role: original.name, slot: -1});
        publicationCurrent();
        await holding.commit(); holding = undefined;
        publicationCurrent();
      }
      for (const child of children) {
        if (!child.operation!.physicalStopped()) {await child.operation!.stop(); publicationCurrent();}
      }
      return publication.plan;
    }).catch(error => {
      publicationFailed = true; publicationFailure = error;
      throw error;
    });
    const result = await publicationPreparation;
    publicationCurrent();
    return result;
  }
  return {retainCompleted, publicationRetained, publicationCurrent, retirePublication, persistPublication,
    readPublicationOwner: () => publicationOwner, hasPublicationBindings: () => publicationBindings.length > 0,
    projectionPending: () => projectionPending};
}
