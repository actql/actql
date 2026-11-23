import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {fundedEffectModelGroupCount} from './installed-effect-managed-run.mjs';
import {createAcquiredEffectModelPublication} from './acquired-effect-model-publication.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import type {openNodeComposedInferProvider} from './infer-operation.mjs';
import {localContractLimits} from './local-publication-limits.mjs';
import {acquiredInferEffectPublicationPlan, prepareAcquiredEffectSourceUnits} from './local-values-plan.mjs';

type Publication = Parameters<typeof createAcquiredEffectModelPublication>[0];
type CaptureOptions = Parameters<typeof openNodeInferCaptureCustody>[0];
type Capture = ReturnType<typeof openNodeInferCaptureCustody>;
type Component = ReturnType<typeof openNodeComposedInferProvider>;
type Bind = Parameters<NonNullable<Component['bindOriginal']>>[0];
type Selection = Bind['selected'] & Publication['children'][number]['selection'] &
  Readonly<{observeAccount?(): unknown}>;
type Plan = Publication['plan'] & NonNullable<Bind['plan']>;
type Operation = CaptureOptions['operation'];
type Restored = NonNullable<Bind['restoredInput']>;
type ProjectionContinuation = NonNullable<Publication['children'][number]['continuation']>;
type Entry = Parameters<Capture['persistSettlement']>[1] & NonNullable<ReturnType<ProjectionContinuation['entry']>>;
type SavedRecord = Readonly<{inventory: Readonly<{taskIndex: number; scopeCid: string}>}>;
type SavedToken = Restored['token'] & Readonly<{snapshot: Restored['snapshot'] & Readonly<{sourceContinuation?: unknown}>}>;
type Evidence = NonNullable<CaptureOptions['sourceEvidence']>[number];
type EvidenceSource = Readonly<{captured: Readonly<{identity: unknown}>; sourceEvidence: Evidence}>;
type SourceUnitPublication = Parameters<typeof prepareAcquiredEffectSourceUnits>[0];
type OriginalModelPublication = Parameters<typeof acquiredInferEffectPublicationPlan>[0];
type PublicationSource = EvidenceSource & SourceUnitPublication['sources'][number];
type KeyedSource = Readonly<{source: Evidence; logicalRelationCid: string}>;
type KeyedFamily = Readonly<{
  evidence: KeyedSource; observation: unknown;
  capturedInput?: ReturnType<NonNullable<Bind['prepareSourceContext']>>['capturedInput'];
}>;
type Context = Readonly<{
  captures: readonly Readonly<{capture: Readonly<{source(): unknown}>}>[];
  evidence: readonly PublicationSource[]; captureStartedAt?: string; captureCompletedAt?: string; keyedFamily?: KeyedFamily;
  contentFamily?: Readonly<{generation(): unknown; recovery(): unknown}>;
}>;
type OriginalPreparation = NonNullable<Bind['originalPreparation']> & Readonly<{
  selection: Selection; component: Component; assertRuntimeCurrent?: () => void;
}>;
type Pause = Readonly<{task: unknown; status?: string; slot?: number}>;
type PauseDecision = Readonly<{action: 'resume'} | {action: 'waiting_checkpoint'; checkpoint: unknown}>;
type Continuation = Omit<ProjectionContinuation, 'entry'> & Readonly<{
  close(): unknown; cleanup(): unknown; cleanupPending(): boolean; hasResponseReconciliation?: boolean;
  observe: Parameters<Capture['configureModelJournal']>[0]['observe'];
  entry(slot: number): Entry | undefined;
  authorize(): Promise<Readonly<{status: string; checkpoint?: unknown}>>;
}>;
type ModelController = Readonly<{
  discover(runId: string): readonly SavedRecord[]; prime(record: SavedRecord): Promise<SavedToken>;
  release(token: SavedToken): unknown; state(inventory: SavedRecord['inventory']): Readonly<{
    slots: ReturnType<NonNullable<Restored['sendSlots']>>;
  }>;
  savedScope(plan: Plan, prepared: unknown, selection: Selection, token: SavedToken): unknown;
  open(options: Readonly<{
    operation: Operation; preparedCallSet: unknown; preserveEvidenceInputs: boolean; plan: Plan; selected: Selection;
    principalId?: string; submission: unknown; signal?: AbortSignal; declaredResults: readonly string[];
    originalPreparation: OriginalPreparation; existing?: SavedRecord; inputToken?: SavedToken;
    claim?: unknown; parentResume: unknown; journalPort: unknown; sourceContinuation: unknown;
  }>): Promise<Continuation>;
}>;
type UnitResult = Readonly<{index: number; artifact: unknown; manifest: unknown}>;
type Child = Omit<Publication['children'][number], 'continuation'> & {
  selection: Selection; originalSelection: Selection; authorizationSelection: Selection;
  originalPreparation: OriginalPreparation; component: Component; continuation?: Continuation;
  captureReleased?: boolean; continuationReleased?: boolean; closeAttempted?: boolean;
  continuationCloseAttempted?: boolean; token?: SavedToken; record?: SavedRecord; restoredInput?: Restored;
  output?: unknown; prepareResults?: (physicalSource: unknown) => Promise<readonly UnitResult[] | undefined>;
  resultsPreparation?: Promise<void>; resultsReady?: boolean; resultsFailed?: boolean; resultsFailure?: unknown;
  resultsRetired?: boolean; preparedResults?: readonly UnitResult[];
};
type UnitResults = {
  pins?: unknown; exports: unknown[]; receipts: unknown[]; artifacts: Readonly<{name: string; artifact: unknown}>[];
  manifest?: unknown; modelScan?: unknown; modelOriginal?: unknown;
  identityRetainedBytes?: bigint; identityExecutionBytes?: bigint;
};
type UnitValue = Readonly<{catalogBodies?: readonly unknown[]}>;
type UnitEntry = {
  preparing: boolean; value?: UnitValue; modelProducer?: Child; modelOperation?: Operation; results?: UnitResults;
  resultAttempted?: boolean; resultPreparing?: boolean; resultFailed?: boolean; resultFailure?: unknown;
};
type UnitInventory = Readonly<{byUnit: Map<number, UnitEntry>; retention: unknown}>;
type Limits = typeof localContractLimits;
type Control = Publication['acquired']['control'] & CaptureOptions['control'] & NonNullable<Bind['control']> & Readonly<{
  runDefinitionRunId(definition: Plan['runDefinition']): string;
  restoredInferSourceOriginals(compiled: unknown, definition: unknown, scope: unknown,
    occurrence: unknown, graph: unknown): readonly KeyedSource[];
  composedInferSourcesFor(occurrence: unknown, source: unknown): unknown;
  admitComposedInferSources(occurrence: unknown, captures: Context['captures'], evidence: readonly Evidence[],
    authorityScopeCid: string, startedAt: string | undefined, completedAt: string | undefined, keyedObservation: unknown): unknown;
  retireOriginalEffectUnitResults(results: UnitResults): boolean;
  prepareOriginalEffectModelUnitEvidence(managedRun: unknown, sourcePlan: unknown, request: unknown,
    output: unknown, compiled: unknown, definition: unknown, graph: unknown, unit: number, retention: unknown,
    catalogs: readonly unknown[], publicationOwner: Operation | undefined, limits: Limits, results: UnitResults,
    current: () => void, retained: bigint, execution: bigint, deferCatalogs: boolean): UnitValue;
  prepareOriginalEffectSourceUnitResults(managedRun: unknown, sourcePlan: unknown, request: unknown, host: unknown,
    unit: UnitValue | undefined, admission: unknown, definition: unknown, limits: Limits, results: UnitResults,
    current: () => void, prepared: unknown, occurrence: unknown, source: unknown, signal: AbortSignal | undefined,
    publicationRetained: () => void): unknown;
  openCheckedClientInstalledRestoredModelsEffectHost(compiled: unknown, definition: unknown, managedRun: unknown,
    owner: unknown, captures: readonly unknown[], outputs: readonly unknown[], graphs: readonly unknown[]): unknown;
}>;
type Runtime = Publication['moon'] & CaptureOptions['moon'] & Readonly<{
  clientProgramCapturedSourceLogicalCid(identity: unknown): string;
  clientProgramInferPlanBoundary(graph: unknown): unknown;
  clientProgramEffectCompilationResultNames(compilation: unknown): readonly string[];
  clientProgramRetireInstalledEffectCapturedConsumers(run: unknown): unknown;
  clientProgramEffectAcquisitionCount(prepared: unknown): number;
  clientProgramEffectComposedModelKeyedAcquisition(prepared: unknown, graph: unknown): unknown;
  clientProgramInferOccurrenceCoordinates(occurrence: unknown): unknown;
  clientProgramInferOccurrenceResultImports(occurrence: unknown): readonly unknown[];
  clientProgramLocalEffectHostRun(host: unknown): unknown;
  clientProgramReleaseInferOutput(output: unknown): boolean;
}>;
type Options = Readonly<{
  moon: Runtime; acquired: Publication['acquired'] & OriginalModelPublication['acquired'] & Readonly<{control: Control; requestIdentity: unknown;
    admission: unknown; compilation: unknown}>;
  infer: Readonly<{components?: readonly Selection[]}>;
  originalModelComponents: readonly Component[]; preparedProgram: unknown; inferEvidence?: Publication['inferEvidence'];
  originalModelSelection?: Readonly<{components: readonly Selection[]}>;
  originalPreparation?: Readonly<{components: readonly OriginalPreparation[]}>;
  plan: Plan; store: Publication['store'] & CaptureOptions['store']; principalId?: string;
  signal?: AbortSignal; now?: () => string; modelController?: ModelController;
  submission: unknown; existingModel?: SavedRecord; modelClaim: unknown; parentResume: unknown; modelJournalPort: unknown;
  sourceContinuation?: Readonly<{restoringModel?: boolean; retainAll(): unknown}>;
  faultInjection?: NonNullable<Publication['faultInjection']> & NonNullable<CaptureOptions['faultInjection']>;
  current(): void; sourcePlan: unknown; managedRun: unknown; originalHost?(): unknown;
}>;

// The nominal SavedScope projection has already checked the original compiled
// Run, definition, occurrence, graph and custody. Match its retained leaves to
// the same actual direct captures; the sole remaining leaf is the keyed one.
export function selectRestoredKeyedSource<Original extends KeyedSource>(
  moon: Pick<Runtime, 'clientProgramCapturedSourceLogicalCid'>, originals: readonly Original[] | undefined,
  direct: readonly EvidenceSource[]): Original {
  if (!Array.isArray(originals) || originals.length !== direct.length + 1) {
    throw new Error('RestoredModelSourceOriginalsUnavailable');
  }
  const remaining = new Set<Original>(originals);
  for (const item of direct) {
    const logical = moon.clientProgramCapturedSourceLogicalCid(item.captured.identity);
    const matching = [...remaining].filter(value => value.logicalRelationCid === logical &&
      value.source.identity === item.sourceEvidence.identity);
    if (matching.length !== 1) throw new Error('RestoredModelSourceOriginalsUnavailable');
    remaining.delete(matching[0]);
  }
  if (remaining.size !== 1) throw new Error('RestoredModelSourceOriginalsUnavailable');
  return remaining.values().next().value!;
}

// The existing Local task driver schedules every component. This continuation
// only retains their original journal/capture duties and seals one complete Run
// observation, using the same publication borrow as the Program group caller.
export function acquiredEffectModelGroup({moon, acquired, infer, originalModelComponents,
  preparedProgram, inferEvidence,
  originalModelSelection, originalPreparation, plan, store, principalId, signal, now,
  modelController, submission, existingModel, modelClaim, parentResume, modelJournalPort,
  sourceContinuation, faultInjection, current, sourcePlan, managedRun, originalHost}: Options) {
  const selected = infer.components, originals = originalPreparation?.components;
  if (!Array.isArray(selected) || selected.length < 2 ||
      selected.length > 128 && fundedEffectModelGroupCount(originalPreparation) !== selected.length ||
      !Object.isFrozen(selected) || !Array.isArray(originalModelComponents) ||
      originalModelComponents.length !== selected.length ||
      !Array.isArray(originalModelSelection?.components) ||
      !Array.isArray(originals) || originals.length !== selected.length ||
      selected.some((member, index) => originalModelSelection.components[index] !== member ||
        originals[index].selection !== member || originals[index].component !== originalModelComponents[index]) ||
      plan?.compiled === undefined || plan.runDefinition === undefined || modelController === undefined) {
    throw new TypeError('InstalledEffectModelOriginalInventoryUnavailable');
  }
  const children: Child[] = selected.map((selection: Selection, index: number) => {
    if (typeof selection.observeAccount !== 'function') throw new Error('InstalledInferAuthorityUnavailable');
    return {selection, originalSelection: selection, originalPreparation: originals[index],
      component: originalModelComponents[index], authorizationSelection: Object.freeze({...selection,
        observeAccount() {same(); const account = selection.observeAccount!(); same(); return account;}})};
  });
  let releasingOutputs = false;
  let captures: Context['captures'], evidence: Context['evidence'], captureStartedAt: string | undefined,
    captureCompletedAt: string | undefined, keyedFamily: KeyedFamily | undefined, restoredHost: unknown,
    restoredKeyed: KeyedSource | undefined, sourceUnitsOriginal: UnitInventory | undefined;
  let sourceUnitsAttempted = false, sourceUnitsFailed = false, sourceUnitsFailure: unknown;
  let earlyIdentityRetained = 0n, earlyIdentityExecution = 0n;
  const runId = acquired.control.runDefinitionRunId(plan.runDefinition);
  const same = () => {
    current();
    if (infer.components !== selected || originalPreparation!.components !== originals ||
        selected.some((member, index) => children[index].selection !== member ||
          originals[index].selection !== member || originals[index].component !== children[index].component)) {
      throw new TypeError('ForeignInstalledEffectModelInventory');
    }
  };
  const unitPinsPending = () => sourceUnitsOriginal !== undefined && [...sourceUnitsOriginal.byUnit.values()]
    .some(entry => entry.resultPreparing || entry.results?.pins !== undefined ||
      entry.results?.modelScan !== undefined || entry.results?.modelOriginal !== undefined);
  const preconsumerPending = () => children.some(child => child.resultsPreparation !== undefined && !child.resultsReady && !child.resultsFailed);
  const {retainCompleted, publicationRetained, publicationCurrent, retirePublication, persistPublication,
    readPublicationOwner, hasPublicationBindings, projectionPending} = createAcquiredEffectModelPublication({
    moon, acquired, children, preparedProgram, plan, store, signal, inferEvidence, sourcePlan, managedRun, same,
    // This group supplies the matching Core, Source and Model originals through the generic publication port.
    buildPublication: acquiredInferEffectPublicationPlan as unknown as Publication['buildPublication'],
    releaseUnitOutputs, preconsumerPending, originalHost, faultInjection,
    readIdentityRetained: () => earlyIdentityRetained, readIdentityExecution: () => earlyIdentityExecution,
    readCaptureStartedAt: () => captureStartedAt, readCaptureCompletedAt: () => captureCompletedAt,
    readEvidence: () => evidence, readKeyedSource: () => keyedFamily?.evidence ?? restoredKeyed,
    readSourceUnitsOriginal: () => sourceUnitsOriginal,
  });
  const pending = () => projectionPending() || preconsumerPending() || unitPinsPending() || children.some(child => child.copy?.cleanupPending() || child.capture !== undefined && !child.captureReleased ||
    child.continuation !== undefined && !child.continuationReleased || child.output !== undefined);
  async function cleanup(includeContinuation: boolean) {
    if (!await retirePublication()) return false;
    let pending = false;
    for (const child of children) {
      const physical = child.capture?.custody ?? child.operation;
      if (physical !== undefined && !child.captureReleased) {
        const retry = child.closeAttempted === true; child.closeAttempted = true;
        const result = await (retry ? physical.cleanup() : physical.close());
        child.captureReleased = result !== false && physical.cleanupPending() === false;
        pending ||= !child.captureReleased;
      }
      if (includeContinuation && child.continuation !== undefined && !child.continuationReleased) {
        const retry = child.continuationCloseAttempted === true; child.continuationCloseAttempted = true;
        const result = await (retry ? child.continuation.cleanup() : child.continuation.close());
        child.continuationReleased = result !== false && child.continuation.cleanupPending() === false;
        pending ||= !child.continuationReleased;
      }
      if (includeContinuation && child.continuation === undefined && child.token !== undefined &&
          (child.operation === undefined || child.captureReleased)) {
        modelController!.release(child.token); child.token = undefined;
      }
    }
    if (!pending && includeContinuation) {
      sourceUnitsOriginal?.byUnit.clear();
      sourceUnitsOriginal = undefined;
    }
    return !pending;
  }
  async function handlePause(boundary: Pause): Promise<PauseDecision> {
    same();
    const child = children.find(member => runtimeField(moon.clientProgramInferPlanBoundary(member.selection.graph), 0) === boundary.task);
    if (child?.operation === undefined || child.capture === undefined) throw new Error('ModelPauseOwnerMissing');
    if (boundary.status === 'settling') {
      const settlement = child.operation.pendingSettlement(), slot = child.operation.settlementSlot(settlement);
      const entry = child.continuation?.entry(slot!);
      if (entry === undefined || slot !== boundary.slot) throw new Error('ModelPauseSettlementMismatch');
      await child.capture.persistSettlement(settlement, entry); same();
      return {action: 'resume'};
    }
    if (boundary.status !== 'waiting') throw new Error('InvalidModelPause');
    if (child.continuation === undefined) {
      const preparedCallSet = child.operation.preparedCallSet();
      if (preparedCallSet === undefined) throw new Error('ModelPausePreparedOwnerMissing');
      const sourceClosure = await sourceContinuation?.retainAll(); same();
      child.continuation = await modelController!.open({operation: child.operation, preparedCallSet,
        preserveEvidenceInputs: false,
        plan, selected: child.authorizationSelection, principalId, submission, signal,
        declaredResults: moon.clientProgramEffectCompilationResultNames(acquired.compilation),
        originalPreparation: child.originalPreparation, existing: child.record, inputToken: child.token,
        ...(child.record?.inventory.scopeCid === existingModel?.inventory.scopeCid ? {claim: modelClaim} : {}),
        parentResume, journalPort: modelJournalPort, sourceContinuation: sourceClosure});
      same();
      child.capture.configureModelJournal({observe: child.continuation.observe, entry: child.continuation.entry});
      if (child.record !== undefined && !child.continuation.hasResponseReconciliation) return {action: 'resume'};
    }
    const decision = await child.continuation.authorize(); same();
    if (decision.status === 'dispatch') return {action: 'resume'};
    if (decision.status !== 'waiting_checkpoint') throw new Error('InvalidModelPauseDecision');
    // Local retains the actual child, never a recursive parent cleanup handle.
    return {action: 'waiting_checkpoint', checkpoint: decision.checkpoint};
  }
  function releaseUnitOutputs() {
    if (releasingOutputs || preconsumerPending() || [...(sourceUnitsOriginal?.byUnit.values() ?? [])].some(entry => entry.resultPreparing)) return false;
    releasingOutputs = true;
    try {
      if (unitPinsPending()) {
        // Request actual captured consumer retirement first. It may remain
        // pending precisely because these original Unit pins are still held.
        checked(moon.clientProgramRetireInstalledEffectCapturedConsumers(managedRun));
      }
      for (const entry of sourceUnitsOriginal?.byUnit.values() ?? []) {
        if (entry.results !== undefined && !acquired.control.retireOriginalEffectUnitResults(entry.results)) return false;
        // Completed Unit consumers have stopped. Drop this group's borrowed
        // Model metadata/scan aliases before returning its publication borrow.
        // Final Store/Run children retain and retire their own original data.
        if (entry.modelProducer !== undefined) entry.value = undefined;
      }
      for (const child of children) {
        child.preparedResults = child.resultsPreparation = child.prepareResults = undefined;
        child.resultsRetired = true;
      }
      // Only our aliases/pins returned. Enclosing physical.cleanup and the
      // original Run retirement still decide their separate ACK/Unknown facts.
      return true;
    } finally {releasingOutputs = false;}
  }
  return Object.freeze({
    async prime() {
      same();
      const records = modelController.discover(runId), matched = new Set();
      let savedSources: unknown;
      for (const child of children) {
        const task = runtimeField(moon.clientProgramInferPlanBoundary(child.selection.graph), 0);
        const candidates = records.filter(record => record.inventory.taskIndex === task);
        if (candidates.length > 1) throw new Error('ModelResumeScopeAmbiguous');
        if (candidates.length === 0) continue;
        child.record = candidates[0]; matched.add(child.record.inventory.scopeCid);
        child.token = await modelController.prime(child.record); same();
        const snapshot = child.token.snapshot;
        if (moon.clientProgramEffectAcquisitionCount(acquired.prepared) > 0 &&
            (sourceContinuation?.restoringModel !== true || snapshot.sourceContinuation === undefined)) {
          throw new Error('ModelSourceClosureCustodyUnavailable');
        }
        if (savedSources === undefined) savedSources = snapshot.sourceContinuation;
        else if (canonicalJson(savedSources) !== canonicalJson(snapshot.sourceContinuation)) throw new Error('ModelSourceClosureMismatch');
        child.restoredInput = {token: child.token, snapshot,
          sendSlots: () => modelController.state(child.record!.inventory).slots,
          savedScope: modelController.savedScope(plan, acquired.prepared, child.selection, child.token)};
      }
      if (matched.size !== records.length) throw new Error('ModelResumeForeignInventory');
    },
    restored: () => children.some(child => child.restoredInput !== undefined),
    keyedMember() {
      same();
      return children.find(child => checked(moon.clientProgramEffectComposedModelKeyedAcquisition(
        acquired.prepared, child.selection.graph)) !== undefined);
    },
    bind(context: Context) {
      ({captures, evidence, captureStartedAt, captureCompletedAt, keyedFamily} = context);
      const sourceEvidence = evidence.map(value => value.sourceEvidence);
      if (sourceUnitsFailed) throw sourceUnitsFailure;
      if (sourceUnitsAttempted) throw new Error('EffectSourceUnitsAlreadyBound');
      sourceUnitsAttempted = true;
      try {
        publicationCurrent();
        if (captures.length > 1) sourceUnitsOriginal = prepareAcquiredEffectSourceUnits({acquired,
          sources: evidence, sourcePlan, managedRun, deferCatalogs: managedRun !== undefined && sourcePlan !== undefined,
          modelUnits: children.map(child => runtimeField(moon.clientProgramInferOccurrenceCoordinates(child.selection.occurrence), 1) as number)}) as UnitInventory | undefined;
        publicationCurrent();
      } catch (cause) {
        sourceUnitsFailed = true; sourceUnitsFailure = cause; throw cause;
      }
      const sourceClosures: unknown[] = [];
      for (const child of children) {
        same();
        if (child.restoredInput !== undefined && captures.length > 0 && checked(
            moon.clientProgramEffectComposedModelKeyedAcquisition(acquired.prepared, child.selection.graph)) !== undefined) {
          const originals = acquired.control.restoredInferSourceOriginals(plan.compiled, plan.runDefinition,
            child.restoredInput.savedScope, child.selection.occurrence, child.selection.graph);
          const original = selectRestoredKeyedSource(moon, originals, evidence);
          if (restoredKeyed !== undefined && (restoredKeyed.source.identity !== original.source.identity ||
              restoredKeyed.logicalRelationCid !== original.logicalRelationCid)) throw new Error('RestoredModelSourceOriginalsUnavailable');
          restoredKeyed = original;
        }
        const selectedKeyed = checked(moon.clientProgramEffectComposedModelKeyedAcquisition(
          acquired.prepared, child.selection.graph)) !== undefined;
        let sourceContext: ReturnType<NonNullable<Bind['prepareSourceContext']>> | undefined;
        const prepareSourceContext = () => {
          publicationCurrent();
          if (sourceContext !== undefined) return sourceContext;
          const ownsKeyed = keyedFamily !== undefined && selectedKeyed;
          if (selectedKeyed && child.restoredInput === undefined && keyedFamily === undefined) {
            throw new Error('OriginalKeyedHostInputUnavailable');
          }
          let sources: unknown;
          if (child.restoredInput === undefined && captures.length !== 0 && context.contentFamily === undefined) {
            const inherited = sourceClosures.filter(original =>
              acquired.control.composedInferSourcesFor(child.selection.occurrence, original) === original);
            if (inherited.length > 1) throw new Error('ForeignInstalledEffectModelSources');
            sources = inherited[0] ?? acquired.control.admitComposedInferSources(
              child.selection.occurrence, captures, sourceEvidence, acquired.authorityScopeCid,
              captureStartedAt, captureCompletedAt, ownsKeyed ? keyedFamily!.observation : undefined);
            if (!sourceClosures.includes(sources)) sourceClosures.push(sources);
          }
          publicationCurrent();
          sourceContext = {sources, capturedInput: ownsKeyed ? keyedFamily!.capturedInput : undefined};
          return sourceContext;
        };
        child.prepareResults = async physicalSource => {
          publicationCurrent();
          if (sourceUnitsOriginal === undefined) return undefined;
          const imports = moon.clientProgramInferOccurrenceResultImports(child.selection.occurrence);
          const bound: UnitResult[] = [];
          for (const [index, imported] of imports.entries()) {
            const unit = runtimeField(imported, 0) as number, name = runtimeField(imported, 1) as string;
            let entry = sourceUnitsOriginal.byUnit.get(unit);
            if (entry === undefined) {
              const producer = children.find(member =>
                runtimeField(moon.clientProgramInferOccurrenceCoordinates(member.selection.occurrence), 1) === unit);
              if (producer?.completed !== true || producer.operation === undefined) {
                throw new Error('OriginalEffectProducerUnitUnavailable');
              }
              entry = {preparing: false, value: undefined, modelProducer: producer};
              sourceUnitsOriginal.byUnit.set(unit, entry);
            }
            if (entry.resultFailed) throw entry.resultFailure;
            if (entry.resultPreparing) throw new Error('EffectProducerUnitPreparationPending');
            if (!entry.resultAttempted) {
              entry.resultAttempted = true; entry.resultPreparing = true;
              entry.results = {pins: undefined, exports: [], receipts: [], artifacts: [], manifest: undefined};
              try {
                const host = originalHost?.();
                if (host === undefined) throw new Error('OriginalEffectProducerHostUnavailable');
                if (entry.modelProducer !== undefined) {
                  const producer = entry.modelProducer;
                  producer.output ??= producer.operation!.acquireOutput();
                  if (producer.output === undefined || readPublicationOwner() === undefined) {
                    throw new Error('OriginalCompletedModelOutputUnavailable');
                  }
                  const catalogs = [...sourceUnitsOriginal.byUnit.values()]
                    .flatMap(original => original.value?.catalogBodies ?? []);
                  entry.modelOperation = producer.operation;
                  entry.value = acquired.control.prepareOriginalEffectModelUnitEvidence(managedRun,
                    sourcePlan, acquired.requestIdentity, producer.output, plan.compiled, plan.runDefinition,
                    producer.selection.graph, unit, sourceUnitsOriginal.retention, catalogs,
                    readPublicationOwner(), localContractLimits, entry.results, publicationCurrent,
                    earlyIdentityRetained, earlyIdentityExecution, true);
                  earlyIdentityRetained += entry.results.identityRetainedBytes!;
                  earlyIdentityExecution += entry.results.identityExecutionBytes!;
                }
                await acquired.control.prepareOriginalEffectSourceUnitResults(managedRun, sourcePlan, acquired.requestIdentity,
                  moon.clientProgramLocalEffectHostRun(host), entry.value, acquired.admission, plan.runDefinition,
                  localContractLimits, entry.results, publicationCurrent, acquired.prepared, child.selection.occurrence, physicalSource, signal, publicationRetained);
              } catch (cause) {
                entry.resultFailed = true; entry.resultFailure = cause; throw cause;
              } finally {entry.resultPreparing = false;}
            }
            const artifact = entry.results!.artifacts.find(value => value.name === name)?.artifact;
            if (artifact === undefined || entry.results!.manifest === undefined) throw new Error('OriginalEffectUnitResultUnavailable');
            bound.push({index, artifact, manifest: entry.results!.manifest});
          }
          publicationCurrent();
          return bound;
        };
        child.component.bindOriginal!({moon, selected: child.selection, prepareSourceContext, control: acquired.control, plan,
          originalPreparation: child.originalPreparation, assertRuntimeCurrent: child.originalPreparation.assertRuntimeCurrent,
          principalId, signal, now, durableCalls: true, restoredInput: child.restoredInput,
          ...(context.contentFamily === undefined ? {} : {generatedInput: {
            generation: () => context.contentFamily!.generation(), recovery: () => context.contentFamily!.recovery()}}),
          prepareOriginalResults() {
            publicationCurrent();
            if (sourceUnitsOriginal === undefined) return undefined;
            if (child.resultsRetired) throw new Error('OriginalEffectUnitResultsRetired');
            if (child.resultsReady !== true) throw new Error('OriginalEffectUnitResultsNotPrepared');
            return child.preparedResults;
          },
          retainOperation(operation) {
            child.operation = operation;
            child.capture = openNodeInferCaptureCustody({moon, control: acquired.control, operation, plan, store,
              storeAuthorityCid: acquired.storeAuthorityCid, sourceEvidence: keyedFamily === undefined && restoredKeyed === undefined ? sourceEvidence
                : [...sourceEvidence, (keyedFamily?.evidence ?? restoredKeyed)!.source], faultInjection, durableCalls: true, captureOnly: true});
          }, retainCompleted: () => retainCompleted(child)} as Bind & {moon: Runtime});
      }
    },
    async prepareNext(task: number, physicalSource: unknown) {
      publicationCurrent();
      const child = children.find(member => runtimeField(moon.clientProgramInferPlanBoundary(member.selection.graph), 0) === task);
      if (child === undefined) return;
      if (child.resultsRetired) throw new Error('OriginalEffectUnitResultsRetired');
      if (child.prepareResults === undefined || child.resultsReady) return;
      if (child.resultsFailed) throw child.resultsFailure;
      child.resultsPreparation ??= Promise.resolve().then(() => child.prepareResults!(physicalSource)).then(result => {
        publicationCurrent();
        child.preparedResults = result; child.resultsReady = true;
      }).catch(cause => {
        child.resultsFailed = true; child.resultsFailure = cause; throw cause;
      });
      await child.resultsPreparation;
      publicationCurrent();
    },
    bindKeyedFamily(original: KeyedFamily | undefined, completedAt: string) {
      same();
      if (original === undefined || keyedFamily !== undefined) throw new Error('OriginalKeyedHostInputAlreadyBound');
      keyedFamily = original;
      captureCompletedAt = completedAt;
    },
    handlePause,
    async restore() {
      for (const child of children) {
        if (child.restoredInput === undefined) continue;
        const operation = child.component.startRestored();
        for (;;) {
          same(); const boundary = await operation.run(); same();
          if (boundary?.status !== 'waiting' && boundary?.status !== 'settling') break;
          const pause = boundary.status === 'settling' ? {...boundary, task: runtimeField(moon.clientProgramInferPlanBoundary(child.selection.graph), 0),
            slot: operation.settlementSlot(boundary.settlement)} : {...boundary, task: runtimeField(moon.clientProgramInferPlanBoundary(child.selection.graph), 0)};
          const decision = await handlePause(pause);
          if (decision.action === 'waiting_checkpoint') return {status: 'waiting_checkpoint', checkpoint: decision.checkpoint};
        }
        if (!retainCompleted(child)) throw new Error('InstalledInferCaptureUnavailable');
        child.output = operation.acquireOutput();
        if (child.output === undefined) throw new Error('RestoredModelOutputUnavailable');
      }
    },
    openRestoredHost(managedRun: unknown, owner: unknown, captures: Context['captures']) {
      same();
      const retained = children.filter(child => child.output !== undefined);
      if (retained.length === 0) throw new Error('RestoredModelOutputUnavailable');
      restoredHost = managedRun;
      return acquired.control.openCheckedClientInstalledRestoredModelsEffectHost(plan.compiled, plan.runDefinition,
        managedRun, owner, captures.map(value => value.capture.source()), retained.map(child => child.output),
        retained.map(child => child.selection.graph));
    },
    // Final Effect dependency issuance still borrows each Model original.
    // Keep these bindings until the existing Host/output retirement boundary.
    hasOutputPins: () => unitPinsPending() || hasPublicationBindings() || children.some(child => child.output !== undefined),
    hasUnitPins: unitPinsPending,
    outputBorrowsRequireParentRetirement: () => restoredHost !== undefined,
    releaseUnitOutputs,
    releaseOutputs() {
      if (!releaseUnitOutputs()) return false;
      if (restoredHost !== undefined && !checked(moon.clientProgramRetireInstalledEffectCapturedConsumers(restoredHost))) return false;
      for (const child of children) {
        if (child.output !== undefined && moon.clientProgramReleaseInferOutput(child.output) !== true) return false;
        child.output = undefined;
      }
      return true;
    },
    async persistStopped() {
      for (const child of children) if (child.operation?.physicalStopped()) await child.capture!.persistStoppedAttempts();
    },
    hasFailure: () => children.some(child => child.resultsFailed || child.component.hasFailure?.() || child.component.failure() !== undefined),
    failure() {
      const preparation = children.find(child => child.resultsFailed);
      if (preparation !== undefined) return preparation.resultsFailure;
      const failed = children.find(child => child.component.hasFailure?.() || child.component.failure() !== undefined);
      return failed?.component.failure();
    },
    persist: persistPublication,
    retirePublication, cleanup, cleanupPending: pending,
  });
}
