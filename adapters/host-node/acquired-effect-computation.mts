// Physical custody while one admitted Effect Run acquires its source and
// computes. This does not retry acquisition, Compute, or an Effect dispatch.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {acquiredKeyedEffectPublicationPlan, acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan,
  acquiredInferEffectPublicationPlan, sourceFreeInferEffectPublicationPlan,
  sourceFreeContentEffectPublicationPlan, localContractLimits} from './local-values-plan.mjs';
import {selectAcquiredEffectSources} from './acquired-effect-sources.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runCapturedEffectComputation} from './entry.mjs';
import {openNodeComposedInferProvider} from './infer-operation.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {ledgerUsageDiagnostic} from '../host-common/runtime-core.mjs';
import {prepareAcquiredEffectKeyedPrefix, prepareAcquiredEffectKeyedCapture} from './acquired-effect-keyed-prefix.mjs';
import {acquiredEffectModelGroup, selectRestoredKeyedSource} from './acquired-effect-model-group.mjs';
export {acquiredEffectModelGroup} from './acquired-effect-model-group.mjs';

import type {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import type {runtimeCore} from '../host-common/runtime-core.mjs';
import type {installNodeContentRun} from './installed-content-run.mjs';

type GroupInputs = Parameters<typeof acquiredEffectModelGroup>[0];
type Group = ReturnType<typeof acquiredEffectModelGroup>;
type GroupModelController = NonNullable<GroupInputs['modelController']>;
type ModelController = Omit<GroupModelController, 'open'> & Readonly<{
  open(options: Omit<Parameters<GroupModelController['open']>[0],
    'preserveEvidenceInputs' | 'originalPreparation'> & Partial<Pick<Parameters<GroupModelController['open']>[0],
      'preserveEvidenceInputs' | 'originalPreparation'>>): ReturnType<GroupModelController['open']>;
  unresolved(runId: string): boolean;
}>;
type RecordOriginal = NonNullable<GroupInputs['existingModel']>;
type Token = Awaited<ReturnType<ModelController['prime']>>;
type ModelOpen = Parameters<ModelController['open']>[0];
type ModelContinuation = Awaited<ReturnType<ModelController['open']>>;
type ModelPlan = GroupInputs['plan'] & Readonly<{graph?: unknown}>;
type CommonControl = ReturnType<typeof runtimeCore>['publicationControl'];
type Issued = ReturnType<CommonControl['bindIssuedClientInferInvocation']>;
type Provider = Parameters<typeof openNodeComposedInferProvider>[0];
type Component = ReturnType<typeof openNodeComposedInferProvider>;
type Operation = NonNullable<ReturnType<Component['operation']>>;
type Selection = ModelOpen['selected'] & NonNullable<Provider['selected']>;
type Inference = Selection & GroupInputs['infer'];
type Preparation = NonNullable<GroupInputs['originalPreparation']> &
  NonNullable<Provider['originalPreparation']> & Readonly<{
    retain(): void; retire(): unknown; assertRuntimeCurrent?(): void;
  }>;
type InferCaptureInput = Parameters<typeof openNodeInferCaptureCustody>[0];
type ModelPublication = Awaited<ReturnType<typeof acquiredInferEffectPublicationPlan>>;
type InferPublication = ReturnType<typeof sourceFreeInferEffectPublicationPlan<Issued>> | (ModelPublication & Issued);
type BoundInferCapture = ReturnType<typeof openNodeInferCaptureCustody<InferPublication>>;
type Execution = Awaited<ReturnType<typeof runCapturedEffectComputation>>;
type StrategyCleanup = NonNullable<Parameters<typeof runCapturedEffectComputation>[4]>;
type PreflightOwner = Parameters<NonNullable<StrategyCleanup['retainPreflightCleanup']>>[0];
type Cleanup = Readonly<{close(): unknown; cleanup(): unknown; cleanupPending(): unknown}>;
type EffectPublication = Parameters<typeof acquiredEffectPublicationPlan>[0];
type PluralPublication = Parameters<typeof acquiredMultiEffectPublicationPlan>[0];
type KeyedOptions = Parameters<typeof prepareAcquiredEffectKeyedPrefix>[0];
type BoundKeyedEvidence = NonNullable<ReturnType<typeof selectRestoredKeyedSource>>;
type KeyedFamily = Omit<NonNullable<Awaited<ReturnType<typeof prepareAcquiredEffectKeyedPrefix>>>, 'evidence'> &
  Readonly<{evidence: BoundKeyedEvidence}>;
type KeyedCleanup = Parameters<KeyedOptions['retain']>[0];
type SourceContinuation = NonNullable<ReturnType<typeof acquiredEffectContinuation>>;
type ContinuedSource = Parameters<SourceContinuation['beforeRead']>[0];
type SourceAccess = Parameters<SourceContinuation['accessFor']>[0];
type PreparedSource = ContinuedSource['preparedSource'] & Readonly<{selection?: unknown}>;
type SourceSelection = Parameters<typeof selectAcquiredEffectSources<SourceAdapter>>[0];
type SourceOccurrence = ContinuedSource['occurrence'];
type SourceFacts = Readonly<{preparedEffect: unknown; registry: SourceSelection['registry'];
  values: SourceSelection['values']; fragment: SourceSelection['fragment']; ordered: SourceSelection['ordered'];
  sourceAccess: SourceAccess | undefined; occurrence: SourceOccurrence}>;
type Capture = EffectPublication['captured'] & KeyedOptions['captures'][number] & Readonly<{
  identity: unknown; occurrence?: SourceOccurrence; inputKind?: string;
  acquisition?: unknown; checkedSource: Readonly<{sourceDataPolicyCid: string}>;
  close(): unknown;
  capture: EffectPublication['captured']['capture'] & Readonly<{retainTask(dag: unknown, task: number): unknown}>;
  issueSourceEvidence(options: Readonly<{authorityScopeCid: string; effectiveDataPolicyCid: string}>): string | Promise<string>;
  prepareSourceEvidenceOriginal(options: Readonly<{authorityScopeCid: string; effectiveDataPolicyCid: string}>): unknown;
}>;
type RetainedCapture = Omit<ReturnType<SourceContinuation['restore']>['captured'], 'checkedSource'> &
  EffectPublication['captured'];
type Captured = Capture | RetainedCapture;
type Evidence = Readonly<{name: string; identity: string; wire: string}>;
type SourceEvidence = Readonly<{captured: Captured; sourceEvidence?: Evidence; sourceEvidenceWire: string}>;
type EvidenceWithOriginal = SourceEvidence & Readonly<{sourceEvidence: Evidence}>;
type KeyedEvidenceSources = KeyedOptions['sources'];
type ModelSources = Parameters<Group['bind']>[0]['evidence'];
type RestoredContentInput = NonNullable<Parameters<ContentRun['recover']>[0]['restoredInput']>;
type RestoredContent = NonNullable<Parameters<ContentRun['effectFamily']>[0]['restored']>;
type SourceFreeContent = Parameters<typeof sourceFreeContentEffectPublicationPlan>[0];
type FreeInfer = Parameters<typeof sourceFreeInferEffectPublicationPlan<Issued>>[0];
type ModelEffect = Parameters<typeof acquiredInferEffectPublicationPlan>[0];
type SourceAdapter = ContinuedSource['adapter'] & Readonly<{
  admitsSource(sourceRef: string): boolean; realizationKey: string; sourceAccess?: SourceAccess;
  prepare(input: SourceFacts & Readonly<{queryTimePreparation?: unknown; requestIdentity: unknown;
    managedRun: unknown}>): PreparedSource | Promise<PreparedSource>;
  open(input: SourceFacts & Readonly<{signal?: AbortSignal; preparedSource: PreparedSource;
    ledger: unknown; reportAcquisitionFailure: ReturnType<typeof acquisitionEndHandoff>['retain']}>): Capture | Promise<Capture>;
  ledgerCapacity(prepared: PreparedSource): Readonly<{capacity: unknown; transferBytes: bigint;
    executionBytes: bigint; managedRun?: unknown; wholeInput?: boolean}>;
}>;
type SelectedSource = ReturnType<typeof selectAcquiredEffectSources<SourceAdapter>>[number];
type Source = Readonly<{adapter: SourceAdapter; access: SourceAccess | undefined;
  preparedSource: PreparedSource; occurrence: SourceOccurrence}>;
type ContentRun = ReturnType<typeof installNodeContentRun> & NonNullable<KeyedOptions['contentRun']>;
type Family = ReturnType<ContentRun['effectFamily']>;
type ContentPlan = Parameters<ContentRun['effectFamily']>[0]['plan'] &
  Readonly<{kind: 'effect'; inferGraph?: unknown}>;
type ContentRecovery = Awaited<ReturnType<ContentRun['recover']>>;
type ContentRecoveryOwner = Parameters<NonNullable<Parameters<ContentRun['recover']>[0]['retainExecution']>>[0];
type ContentOwner = Parameters<NonNullable<Parameters<ContentRun['effectFamily']>[0]['retainCleanup']>>[0];
type PublicationPlan = ReturnType<typeof acquiredEffectPublicationPlan> |
  ReturnType<typeof acquiredMultiEffectPublicationPlan> |
  ReturnType<typeof acquiredKeyedEffectPublicationPlan> |
  ReturnType<typeof sourceFreeContentEffectPublicationPlan> | Awaited<ReturnType<Group['persist']>> |
  InferPublication['plan'];
type Pause = Parameters<Group['handlePause']>[0];
type PauseDecision = Awaited<ReturnType<Group['handlePause']>> | Awaited<ReturnType<Family['handlePause']>>;
type Configuration = Readonly<Record<string, unknown>>;
type Store = GroupInputs['store'] & NonNullable<KeyedOptions['store']> & Parameters<ContentRun['effectFamily']>[0]['store'];
type CheckedHost = Parameters<typeof runCapturedEffectComputation>[0];
type Control = Pick<CommonControl, 'adoptCheckedClientEffectInferRun' | 'admitRunEvidence' |
  'takeSourceEvidenceOriginal' | 'compiledSerializationPolicy'> &
  Omit<GroupInputs['acquired']['control'], 'admitRunEvidence' | 'takeSourceEvidenceOriginal'> &
  Omit<EffectPublication['acquired']['control'], 'admitRunEvidence' | 'takeSourceEvidenceOriginal'> &
  KeyedOptions['acquired']['control'] & NonNullable<Provider['control']> & InferCaptureInput['control'] &
  Readonly<{
    admitComposedInferSources(occurrence: unknown, captures: readonly Captured[], evidence: readonly (Evidence | undefined)[],
      authorityScopeCid: string, started: string, completed?: string, keyed?: unknown): unknown;
    adoptCheckedClientEffectSerializationRun(allowed: unknown, definition: unknown): ModelPlan['compiled'];
    compiledSerializationGraph(compiled: ModelPlan['compiled']): ContentPlan['serializationGraph'];
    restoredInferSourceOriginals(compiled: unknown, definition: unknown, savedScope: unknown,
      occurrence: unknown, graph: unknown): Parameters<typeof selectRestoredKeyedSource>[1];
    openCheckedClientInstalledRestoredModelEffectHost(compiled: unknown, definition: unknown, managedRun: unknown,
      owner: unknown, sources: readonly unknown[], output: unknown, graph: unknown): unknown;
  }>;
type Acquired = Omit<GroupInputs['acquired'], 'control' | 'selectRetention' | 'moon'> &
  Omit<PluralPublication['acquired'], 'control' | 'selectRetention' | 'moon'> &
  Pick<KeyedOptions['acquired'], 'selectRetention'> & Readonly<{
    moon: GroupInputs['acquired']['moon'] & PluralPublication['acquired']['moon'] & SourceFreeContent['acquired']['moon'];
  }> &
  Readonly<{control: Control; queryTimePreparation?: unknown;
    resultDataPolicy?: Parameters<CommonControl['adoptCheckedClientEffectInferRun']>[2]}>;
type Moon = GroupInputs['moon'] & KeyedOptions['moon'] & SourceSelection['moon'] &
  Provider['moon'] & InferCaptureInput['moon'] &
  Readonly<{
    clientProgramReleaseInferOutput(output: unknown): boolean;
    clientProgramRefreshAcquiredEffectCleanup(host: unknown): boolean;
    clientProgramRetireInstalledEffectCapturedConsumers(run: unknown): unknown;
    clientProgramLocalEffectHostRuntime(host: unknown): object | undefined;
    strategyHostUsage(host: object | undefined): object;
    clientProgramMultiCapturedLedgerUsage(ledger: unknown): object;
    clientProgramInstalledEffectManagedOperationPlan?(run: unknown, prepared: unknown, request: unknown): unknown;
    clientProgramEffectRunQueryTimeMatches?(owner: unknown, queryTime: unknown, request: unknown): boolean;
    clientProgramEffectSerializationOccurrences?(prepared: unknown): readonly unknown[];
    clientProgramInferPlanBoundary(graph: unknown): unknown;
    clientProgramInstalledEffectManagedSourcesLedger?(run: unknown, prepared: unknown, request: unknown): unknown;
    clientProgramInstalledEffectManagedRunPrepareLedger?(run: unknown, prepared: unknown, request: unknown,
      capacities: readonly unknown[], transfer: readonly bigint[], execution: readonly bigint[],
      registry: SourceSelection['registry'], values: SourceSelection['values'],
      fragment: SourceSelection['fragment'], ordered: SourceSelection['ordered']): unknown;
    clientProgramInferOccurrenceResultImports(occurrence: unknown): readonly unknown[];
    clientProgramEffectComposedModelKeyedAcquisition(prepared: unknown, graph: unknown): unknown;
    clientProgramInstalledEffectManagedHostOpen?(run: unknown, owner: unknown, sources: readonly unknown[]): unknown;
    clientProgramInstalledEffectManagedDeferredKeyedHostOpen(run: unknown, owner: unknown, sources: readonly unknown[]): unknown;
    clientProgramInstalledEffectManagedKeyedHostOpen(run: unknown, owner: unknown, sources: readonly unknown[], lookup: unknown): unknown;
    clientProgramInstalledEffectManagedKeyedHostBind(run: unknown, host: unknown, lookup: unknown): unknown;
    strategyHostRun(host: object | undefined): unknown;
    clientProgramEffectCompilationResultNames(compilation: unknown): readonly string[];
  }>;
type Fault = NonNullable<GroupInputs['faultInjection']> &
  ((name: 'infer_capture_committed', facts: Readonly<Record<string, never>>) => unknown);
type Options = Pick<GroupInputs, 'principalId' | 'signal' | 'inferEvidence' | 'submission' |
  'modelClaim' | 'parentResume' | 'modelJournalPort'> & Pick<KeyedOptions, 'requestJournal' | 'runRef'> &
  Pick<SourceSelection, 'registry' | 'values' | 'fragment' | 'ordered'> &
  Readonly<{
    moon: Moon; owner: unknown; acquired: Acquired; managedRun: unknown;
    sourceProfile?: NonNullable<SourceSelection['sourceProfile']> & NonNullable<KeyedOptions['sourceProfile']>;
    sourceAccess?: SourceAccess; now(): string; retainComputationOwner(owner: Cleanup): void;
    infer?: Inference; store: Store; faultInjection?: Fault; observe?: unknown; sourceContinuation?: SourceContinuation;
    computeConfigurations?: Configuration;
    withComputePauseHandler?(configs: Configuration, pause: (boundary: Pause) => Promise<PauseDecision | unknown>,
      beforePrepare: (task: number, physicalSource: unknown) => Promise<void>): Configuration;
    modelController?: ModelController; existingModel?: RecordOriginal; contentRun?: ContentRun;
    assertUpdateSelectionCurrent?(): unknown; assertContinuationCurrent?(): unknown;
    originalPreparation?: Preparation; originalModelPlan?: ModelPlan;
    originalModelComponent?: Component; originalModelComponents?: readonly Component[];
    originalModelSelection?: Selection & NonNullable<GroupInputs['originalModelSelection']>;
    originalContent?: Readonly<{plan: ContentPlan; family: Family}>;
    sourceSelection?: readonly SelectedSource[]; sourceSelectionPlan?: unknown;
    sourceKeyedPreparation?: KeyedOptions['sourcePreparation'];
  }>;

export async function openAcquiredEffectComputation({moon, owner, acquired, managedRun,
  sourceProfile, registry, values, fragment, ordered, sourceAccess,
  signal, now, retainComputationOwner, infer, store, principalId, faultInjection,
  observe, sourceContinuation, computeConfigurations = {}, withComputePauseHandler, modelController, inferEvidence,
  submission, existingModel, modelClaim, parentResume, modelJournalPort, contentRun,
  assertUpdateSelectionCurrent, assertContinuationCurrent, originalPreparation, originalModelPlan,
  originalModelComponent, originalModelComponents, originalModelSelection, originalContent,
  sourceSelection, sourceSelectionPlan, sourceKeyedPreparation, requestJournal, runRef}: Options) {
  const preparedOriginal = acquired.prepared, requestOriginal = acquired.requestIdentity;
  const count = moon?.clientProgramEffectAcquisitionCount?.(acquired.prepared) as number;
  const sourceFree = count === 0;
  const multiple = count > 1;
  const serializations = moon?.clientProgramEffectSerializationOccurrences?.(acquired.prepared) ?? [];
  if (typeof retainComputationOwner !== 'function' ||
      !Number.isSafeInteger(count) || count < 0 ||
      sourceFree && infer === undefined && serializations.length === 0 ||
      !sourceFree && sourceProfile === undefined) {
    throw new TypeError('InvalidAcquiredEffectComputationPort');
  }
  const captures: Captured[] = [];
  let execution: Execution | undefined;
  let checkedHost: CheckedHost | undefined;
  let recovery: Cleanup | undefined;
  let inferCapture: BoundInferCapture | undefined;
  let inferOperation: Operation | undefined;
  let modelContinuation: ModelContinuation | undefined;
  let modelToken: Token | undefined;
  let modelPlan = originalModelPlan;
  let modelRecord = existingModel;
  const pluralModels = Array.isArray(infer?.components);
  let modelGroup: Group | undefined;
  let ledger: unknown | undefined;
  let contentFamily: Family | undefined;
  let contentFamilyCleanup: ContentOwner | undefined;
  let contentPlan: ContentPlan | undefined;
  let contentRecovery: ContentRecoveryOwner | undefined;
  let restoredModelInput: Provider['restoredInput'];
  let keyedFamily: KeyedFamily | undefined;
  let keyedCleanup: KeyedCleanup | undefined;
  let restoredKeyedSource: BoundKeyedEvidence | undefined;
  let deferredKeyedMember: ReturnType<Group['keyedMember']>;
  let keyedPreparation: Promise<void> | undefined;
  let keyedAttempted = false;
  // This output pin is retained on the already-published computation custody
  // before Host construction. Even a throwing/absent Host retains this duty.
  let restoredModelOutput: unknown;
  let restoredModelHostAttempted = false;
  let hostOpenAttempted = false, computeEntered = false;
  const diagnostic = diagnosticObserver(observe);
  const observeUsage = (name: string, facts: Readonly<Record<string, unknown>> = {}) => {
    const usage = ledger === undefined ? checkedHost === undefined ? undefined
      : moon.strategyHostUsage(moon.clientProgramLocalEffectHostRuntime(checkedHost))
      : moon.clientProgramMultiCapturedLedgerUsage(ledger);
    if (usage === undefined) return;
    diagnostic(name, {...facts, resourceUsage: ledgerUsageDiagnostic(usage)});
  };
  let unresolved = false;
  let pending = true;
  let settled = false;
  let closed = false;
  let originalPreparationRetained = false;
  const originalCurrent = () => {
    signal?.throwIfAborted();
    if (closed) throw Object.assign(new Error('ClientRunCancellationRequested'),
      {code: 'ClientRunCancellationRequested'});
    if (assertUpdateSelectionCurrent === undefined) return;
    const changed = () => { throw refusedEffectPreparation(Object.assign(
      new Error('InstalledEffectOriginalSelectionChanged'),
      {code: 'InstalledEffectOriginalSelectionChanged'})); };
    if (typeof assertUpdateSelectionCurrent !== 'function') changed();
    const result = assertUpdateSelectionCurrent();
    if (typeof (result as {then?: unknown} | undefined)?.then === 'function') {
      void Promise.resolve(result).catch(() => {});
      changed();
    }
  };
  const current = () => {
    originalCurrent();
    assertContinuationCurrent?.();
  };
  let inferCloseAttempted = false, inferReleased = false;
  let modelCloseAttempted = false, modelReleased = false;
  const inferCleanupPending = () => modelGroup !== undefined ? modelGroup.cleanupPending() : (inferCapture !== undefined || inferOperation !== undefined) && !inferReleased ||
    modelContinuation !== undefined && !modelReleased;
  // Publication aliases/capacity can retire after Store persistence while
  // the accepted Local output still retains the SAME Model child. This phase
  // cannot acknowledge that child's cleanup or return its output backing.
  const retireInferPublication = async () => {
    if (modelGroup !== undefined) return modelGroup.retirePublication();
    let phase = 'stop';
    try {
      if (originalPreparation !== undefined && inferOperation?.publicationCapacityPending?.()) {
        // A completed result still owns its Model stop/settlement. Await
        // that SAME operation before retiring publication aliases: the
        // custody gate requires physicalStopped and cannot initiate stop.
        // Keep this continuation/result while pending; never run it again.
        phase = 'stop';
        await inferOperation!.stop();
        phase = 'publication';
        if (!await inferCapture!.custody.retirePublication()) {
          diagnostic('effect_computation_model_cleanup_pending', {modelCleanupPhase: 'publication'});
          return false;
        }
        phase = 'publication_capacity';
        if (!inferOperation.releaseOriginalPublicationCapacity()) {
          diagnostic('effect_computation_model_cleanup_pending', {modelCleanupPhase: 'publication_capacity'});
          return false;
        }
      }
    } catch (error) {
      diagnostic('effect_computation_model_cleanup_pending',
        {modelCleanupPhase: phase, modelCleanupOutcome: 'throw'});
      throw error;
    }
    return true;
  };
  const cleanupInfer = async (includeContinuation = true) => {
    if (modelGroup !== undefined) return modelGroup.cleanup(includeContinuation);
    let failure, failed = false;
    if ((inferCapture !== undefined || inferOperation !== undefined) && !inferReleased) {
      let phase = 'model_child';
      try {
        const child = (inferCapture?.custody ?? inferOperation)!;
        phase = 'publication_prerequisites';
        if (!await retireInferPublication()) return false;
        // Prerequisite refusal is not a child close attempt. Once invoked,
        // even a throwing close recovers only through this same child's cleanup.
        phase = 'model_child';
        const recover = inferCloseAttempted;
        inferCloseAttempted = true;
        const result = await (recover ? child.cleanup() : child.close());
        inferReleased = result !== false && child.cleanupPending() === false;
        if (!inferReleased) diagnostic('effect_computation_model_cleanup_pending', {modelCleanupPhase: 'model_child'});
      } catch (error) {
        if (phase === 'model_child') diagnostic('effect_computation_model_cleanup_pending',
          {modelCleanupPhase: phase, modelCleanupOutcome: 'throw'});
        failure = error; failed = true;
      }
    }
    if (includeContinuation && modelContinuation !== undefined && !modelReleased) {
      const recover = modelCloseAttempted;
      modelCloseAttempted = true;
      try {
        const result = await (recover ? modelContinuation.cleanup() : modelContinuation.close());
        modelReleased = result !== false && modelContinuation.cleanupPending() === false;
      } catch (error) { if (!failed) { failure = error; failed = true; } }
    }
    if (failed) throw failure;
    return ((inferCapture === undefined && inferOperation === undefined) || inferReleased) &&
      (!includeContinuation || modelContinuation === undefined || modelReleased);
  };
  const retireUnenteredCompute = () => {
    if (!hostOpenAttempted || computeEntered) return true;
    // The original parent owns even a partially constructed DAG. Ask that
    // owner to stop and retire it before closing Source or prefix backing.
    if (checked(moon.clientProgramRetireInstalledEffectCapturedConsumers(managedRun)) !== true) return false;
    hostOpenAttempted = false;
    restoredModelHostAttempted = false;
    unresolved = false;
    return true;
  };
  const custody = Object.freeze({
    async close() {
      closed = true;
      if (!retireUnenteredCompute()) return;
      // A physical owner's cleanup, not another Compute call, recovers a
      // failed close. Retain the captured source until consumers are gone.
      let failure, failed = false;
      try {
        // Final dependency consumption keeps these original Model bindings live
        // until this enclosing close, even when preparation itself succeeded.
        // Retire the same publication borrow before parent Model cleanup; actual
        // restored output pins still require their separate parent retirement.
        if (modelGroup !== undefined) await modelGroup.retirePublication();
        await (execution ?? recovery)?.close();
      }
      catch (error) { failure = error; failed = true; }
      try { if (settled && restoredModelOutput === undefined && !modelGroup?.hasOutputPins()) await cleanupInfer(); }
      catch (error) { if (!failed) failure = error; failed = true; }
      try { if (settled) await (contentFamilyCleanup ?? contentFamily)?.close(); }
      catch (error) { if (!failed) failure = error; failed = true; }
      try { if (settled) await contentRecovery?.close(); }
      catch (error) { if (!failed) failure = error; failed = true; }
      if (failed) observeUsage('effect_computation_cleanup_pending');
      if (failed) throw failure;
    },
    async cleanup() {
      if (!pending) return true;
      if (!closed || !settled) return false;
      if (!retireUnenteredCompute()) return false;
      if (modelGroup !== undefined && !await modelGroup.retirePublication()) return false;
      if (unresolved && restoredModelOutput === undefined && !modelGroup?.hasOutputPins()) return false;
      const physical = execution ?? recovery;
      let physicalRetired = false;
      if (restoredModelOutput !== undefined) {
        if (physical !== undefined) {
          if (await physical.cleanup() === false || physical.cleanupPending() !== false) return false;
          physicalRetired = true;
        }
        // A failed constructor can attach consumers without returning a Host.
        // Only the same original parent's actual retirement can release this pin.
        if (restoredModelHostAttempted && !checked(
          moon.clientProgramRetireInstalledEffectCapturedConsumers(managedRun))) return false;
        if (moon.clientProgramReleaseInferOutput(restoredModelOutput) !== true) return false;
        restoredModelOutput = undefined;
        unresolved = false;
      }
      if (modelGroup?.hasUnitPins() && !modelGroup.releaseUnitOutputs()) return false;
      if (modelGroup?.hasOutputPins()) {
        // Fresh group OutputUses must return before their same Model children
        // can reclaim. Restored parents retain their separate retirement duty.
        // Actual Host cleanup is still required below, after cleanupInfer.
        if (modelGroup.outputBorrowsRequireParentRetirement() &&
            physical !== undefined && !physicalRetired) {
          if (await physical.cleanup() === false || physical.cleanupPending() !== false) return false;
          physicalRetired = true;
        }
        if (!modelGroup.releaseOutputs()) return false;
        unresolved = false;
      }
      if (!await cleanupInfer()) {
        observeUsage('effect_computation_cleanup_pending');
        return false;
      }
      const familyCleanup = contentFamilyCleanup ?? contentFamily;
      if (familyCleanup !== undefined && (!await familyCleanup.cleanup() ||
          familyCleanup.cleanupPending())) {
        observeUsage('effect_computation_cleanup_pending');
        return false;
      }
      if (contentRecovery !== undefined && (!await contentRecovery.cleanup() ||
          contentRecovery.cleanupPending())) return false;
      if (physical !== undefined && !physicalRetired) {
        if (await physical.cleanup() === false ||
            physical.cleanupPending() !== false) {
          observeUsage('effect_computation_cleanup_pending');
          return false;
        }
      }
      if (keyedCleanup !== undefined &&
          (await keyedCleanup.cleanup() === false || keyedCleanup.cleanupPending() !== false)) return false;
      // A failed startup can stop before its local runner returns operations.
      // Closing only completed outputs does not retire that DAG's input
      // consumers. All physical and component cleanup above acknowledged;
      // let the SAME parent confirm retirement before any Source can close.
      if (execution?.status === 'host-tasks-failed' && checked(
        moon.clientProgramRetireInstalledEffectCapturedConsumers(managedRun)) !== true) return false;
      while (captures.length > 0) {
        await captures[0].close();
        captures.shift();
      }
      if (originalPreparationRetained) {
        if (await originalPreparation!.retire() !== true) return false;
        originalPreparationRetained = false;
      }
      if (checkedHost !== undefined &&
          !moon.clientProgramRefreshAcquiredEffectCleanup(checkedHost)) {
        observeUsage('effect_computation_cleanup_pending');
        return false;
      }
      execution = undefined;
      recovery = undefined;
      await sourceContinuation?.close();
      if (modelToken !== undefined) modelController!.release(modelToken);
      pending = false;
      observeUsage('effect_computation_cleanup_completed');
      return true;
    },
    cleanupPending: () => pending,
  });
  const retainPreflightCleanup = (owner: PreflightOwner) => {
    if (settled || execution !== undefined || recovery !== undefined) {
      throw new Error('EffectComputationCleanupAlreadyRetained');
    }
    // Only the installed preflight owner can make this handoff, before any
    // Compute task enters. Its actual stop/output/Site duties remain pending;
    // receiving it is not a physical cleanup acknowledgement.
    recovery = owner;
    unresolved = false;
  };
  // Even preparation can fail. The dispatch owner receives custody before
  // the first asynchronous boundary or provider operation.
  retainComputationOwner(custody);
  try {
    if (originalPreparation !== undefined) {
      originalPreparation.retain();
      originalPreparationRetained = true;
    }
    current();
    const readPlan = moon.clientProgramInstalledEffectManagedOperationPlan;
    if (managedRun === undefined || typeof readPlan !== 'function' ||
        typeof moon.clientProgramInstalledEffectManagedHostOpen !== 'function') {
      throw new Error('InstalledEffectPlanUnavailable');
    }
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    const operationPlan = checked(Reflect.apply(readPlan, moon,
      [managedRun, preparedOriginal, requestOriginal]));
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    current();
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    if (acquired.queryTimePreparation !== undefined) {
      if (typeof moon.clientProgramEffectRunQueryTimeMatches !== 'function' ||
          typeof moon.clientProgramEffectRunQueryTimeMatches !== 'function' ||
          moon.clientProgramEffectRunQueryTimeMatches(owner,
            acquired.queryTimePreparation, acquired.requestIdentity) !== true) {
        throw new Error('OriginalQueryTimeUnavailable');
      }
    }
    if (assertUpdateSelectionCurrent !== undefined && infer !== undefined && !pluralModels) {
      const originalInfer = infer;
      if (typeof originalInfer.observeAccount !== 'function') {
        throw new Error('InstalledInferAuthorityUnavailable');
      }
      // The same dispatch admission re-observes this actual account at its
      // final send gate, including after Entry persistence. Preserve its
      // original result; the installed selection assertion adds no permit.
      infer = Object.freeze({...originalInfer, observeAccount() {
        current();
        const account = originalInfer.observeAccount!();
        current();
        return account;
      }});
    }
    // The immediate caller already selected these immutable installation
    // inputs from this SAME original Plan. Current/authorization/read gates
    // below remain live, including after Model and continuation awaits.
    if (sourceSelection !== undefined && (sourceSelectionPlan !== operationPlan ||
        !Array.isArray(sourceSelection) || !Object.isFrozen(sourceSelection) ||
        sourceSelection.length !== count || sourceSelection.some(value =>
          !Object.isFrozen(value) || !Object.isFrozen(value.occurrence)))) {
      throw new TypeError('ForeignInstalledEffectSourceSelection');
    }
    const selectedSources = sourceSelection ?? (sourceFree ? [] : selectAcquiredEffectSources({moon,
      preparedEffect: acquired.prepared, sourceProfile, registry, values, fragment, ordered,
      queryTimePreparation: acquired.queryTimePreparation, requestIdentity: acquired.requestIdentity,
      managedPlan: operationPlan, managedRun}));
    const wholeInputs = selectedSources.some(source => source.sourceKind === 'whole-input');
    const singleSourceAccess = sourceAccess ?? selectedSources[0]?.adapter.sourceAccess;
    if (infer !== undefined && !pluralModels) {
      if (modelController === undefined) throw new Error('InstalledModelJournalRequired');
      const runId = acquired.control.runDefinitionRunId(acquired.runDefinition);
      const taskIndex = runtimeField(moon.clientProgramInferPlanBoundary(infer.graph), 0);
      modelRecord ??= modelController.discover(runId).find(record => record.inventory.taskIndex === taskIndex);
      if (modelRecord !== undefined) {
        current();
        modelToken = await modelController.prime(modelRecord);
        current();
        if (!sourceFree && sourceContinuation?.restoringModel !== true) {
          throw new Error('ModelSourceCaptureRestoreRequired');
        }
      }
    }
    if (pluralModels) {
      modelGroup = acquiredEffectModelGroup({moon, acquired, infer: infer!, originalModelComponents: originalModelComponents!,
        preparedProgram: owner, inferEvidence,
        originalModelSelection, originalPreparation, plan: modelPlan!, store, principalId, signal, now,
        modelController, submission, existingModel, modelClaim, parentResume, modelJournalPort,
        sourceContinuation, faultInjection, current, sourcePlan: operationPlan, managedRun, originalHost: () => checkedHost});
      await modelGroup.prime();
      current();
    }
    const sources: Source[] = [];
    for (const {adapter, occurrence} of selectedSources) {
      current();
      const baseAccess = multiple ? adapter.sourceAccess : singleSourceAccess;
      const access = sourceContinuation?.accessFor(baseAccess!, occurrence) ?? baseAccess;
      current();
      const preparedSource = await adapter.prepare({
        preparedEffect: acquired.prepared, registry, values, fragment, ordered,
        queryTimePreparation: acquired.queryTimePreparation, requestIdentity: acquired.requestIdentity,
        sourceAccess: access, occurrence, managedRun});
      current();
      sources.push({adapter, access, preparedSource, occurrence});
    }
    await sourceContinuation?.prepared(sources);
    current();
    const captureStartedAt = sourceContinuation?.times().captureStartedAt ?? now();
    let captureCompletedAt: string | undefined;
    const evidence: SourceEvidence[] = [];
    let component: Component | undefined;
    if (serializations.length > 0 && originalContent !== undefined) {
      if (multiple || serializations.length !== 1 ||
          infer !== undefined && (modelPlan === undefined || originalContent.plan?.compiled !== modelPlan.compiled)) {
        throw new TypeError('UnsupportedInstalledContentEffectClosure');
      }
      contentPlan = originalContent.plan;
      contentFamily = originalContent.family;
      contentFamilyCleanup = contentFamily;
      contentFamily.bindExecution!({prepared: acquired.prepared, plan: contentPlan, store, principalId: principalId!, signal});
    } else if (serializations.length > 0) {
      if (multiple || serializations.length !== 1 ||
          typeof contentRun?.effectFamily !== 'function' ||
          !sourceFree && typeof sources[0]?.adapter.ledgerCapacity !== 'function') {
        throw new TypeError('UnsupportedInstalledContentEffectClosure');
      }
      // Both children borrow this exact compiled Run, not two independently
      // reconstructed wrappers with merely equal wire identities.
      const compiled = (infer === undefined
        ? acquired.control.adoptCheckedClientEffectSerializationRun(acquired.allowed, acquired.runDefinition)
        : acquired.control.adoptCheckedClientEffectInferRun(acquired.allowed, acquired.runDefinition,
          acquired.resultDataPolicy, acquired.resultDataPolicyLimits)) as ModelPlan['compiled'];
      if (infer !== undefined) {
        modelPlan = {compiled, runDefinition: acquired.runDefinition};
      }
      contentPlan = {kind: 'effect', compiled, runDefinition: acquired.runDefinition,
        inferGraph: infer?.graph,
        serializationGraph: acquired.control.compiledSerializationGraph(compiled)};
      let restored: ContentRecovery | undefined;
      if (modelToken !== undefined) {
        restoredModelInput = {
          token: modelToken, snapshot: modelToken.snapshot,
          sendSlots: () => modelController!.state(modelRecord!.inventory).slots,
          savedScope: modelController!.savedScope(modelPlan!, acquired.prepared, infer!, modelToken),
        };
        current();
        restored = await contentRun.recover({preparedEffect: acquired.prepared,
          plan: contentPlan, store, principalId: principalId!, signal, restoredInput: restoredModelInput as RestoredContentInput,
          retainExecution(value: ContentRecoveryOwner) { contentRecovery = value; }});
        current();
      }
      contentFamily = contentRun.effectFamily({prepared: acquired.prepared,
        plan: contentPlan, store, principalId: principalId!, signal, restored: restored as RestoredContent | undefined,
        retainCleanup(value: ContentOwner) {contentFamilyCleanup = value;}});
    }
    const prepareInferComponent = () => {
      current();
      if (infer === undefined) return undefined;
      if (!multiple && !sourceFree && contentFamily === undefined) {
        throw new TypeError('UnsupportedComposedInferSourceClosure');
      }
      const sourceEvidence = evidence.map(value => value.sourceEvidence!);
      // Saved input is validated by the original saved Scope below; it may
      // neither repeat the keyed read nor invent a fresh Source observation.
      const savedOriginal = originalModelComponent !== undefined &&
        (restoredModelInput !== undefined || modelToken !== undefined);
      const admittedSources = sourceFree || contentFamily !== undefined || savedOriginal ? undefined
        : acquired.control.admitComposedInferSources(
          infer.occurrence, captures, sourceEvidence, acquired.authorityScopeCid,
          captureStartedAt, captureCompletedAt, keyedFamily?.observation);
      const compiled = modelPlan?.compiled ?? acquired.control.adoptCheckedClientEffectInferRun(
        acquired.allowed, acquired.runDefinition, acquired.resultDataPolicy,
        acquired.resultDataPolicyLimits) as ModelPlan['compiled'];
      const plan = modelPlan ?? {compiled, runDefinition: acquired.runDefinition};
      modelPlan = plan;
      const restoredInput = restoredModelInput ?? (modelToken === undefined ? undefined : {
        token: modelToken, snapshot: modelToken.snapshot,
        sendSlots: () => modelController!.state(modelRecord!.inventory).slots,
        savedScope: modelController!.savedScope(plan, acquired.prepared, infer, modelToken),
      });
      if (savedOriginal && multiple && checked(
        moon.clientProgramEffectComposedModelKeyedAcquisition(acquired.prepared, infer.graph)) !== undefined) {
        const originals = acquired.control.restoredInferSourceOriginals(
          compiled, plan.runDefinition, restoredInput!.savedScope,
          (originalModelSelection ?? infer).occurrence, (originalModelSelection ?? infer)!.graph);
        restoredKeyedSource = selectRestoredKeyedSource(moon, originals, evidence as readonly EvidenceWithOriginal[]);
        current();
      }
      const context: Provider = {moon, selected: originalModelSelection ?? infer, sources: admittedSources,
        originalPreparation,
        assertRuntimeCurrent: originalPreparation?.assertRuntimeCurrent,
        ...(contentFamily === undefined ? {} : {generatedInput: {
          generation: () => contentFamily!.generation(),
          recovery: () => contentFamily!.recovery(),
        }}),
        control: acquired.control, plan, principalId, signal, now, durableCalls: true, restoredInput,
        capturedInput: keyedFamily?.capturedInput,
        retainOperation(operation: Operation) {
          inferOperation = operation;
          inferCapture = openNodeInferCaptureCustody<InferPublication>({moon, control: acquired.control,
            operation, plan, store, storeAuthorityCid: acquired.storeAuthorityCid, durableCalls: true,
            sourceEvidence: keyedFamily === undefined && restoredKeyedSource === undefined ? sourceEvidence
              : [...sourceEvidence, (keyedFamily?.evidence ?? restoredKeyedSource)!.source],
            faultInjection,
            publicationFor: ({issuance, modelEvidence}) =>
              sourceFree ? sourceFreeInferEffectPublicationPlan<Issued>({acquired,
                compiled, operation: operation as unknown as FreeInfer['operation'], issuance, modelEvidence, managedRun,
                sourcePlan: operationPlan, sourceHost: checkedHost}) :
              acquiredInferEffectPublicationPlan({acquired, sources: evidence,
                compiled, operation: operation as unknown as ModelEffect['operation'], issuance, modelEvidence, sourcePlan: operationPlan, managedRun,
                sourceHost: checkedHost,
                deferCatalogs: managedRun !== undefined && operationPlan !== undefined,
                keyedSource: keyedFamily?.evidence ?? restoredKeyedSource,
                captureStartedAt, captureCompletedAt, signal}) as Promise<ModelPublication & Issued>});
        },
        retainCompleted: () => inferCapture!.retainCompleted()};
      return originalModelComponent === undefined ? openNodeComposedInferProvider(context)
        : originalModelComponent.bindOriginal!(context);
    };
    // The original plan already selected its configuration/Source capacities.
    // A provider family requiring a different scope cannot acquire a scalar
    // replacement here. Its full plan must have been admitted before capture.
    if (contentFamily !== undefined && !pluralModels) component = prepareInferComponent();
    if (!sourceFree) {
      const capacities = sources.map(source => source.adapter.ledgerCapacity(source.preparedSource));
      if (capacities.some((value, index) => value?.managedRun !== managedRun ||
          (value.wholeInput === true) !== (selectedSources[index].sourceKind === 'whole-input'))) {
        throw new Error('ForeignInstalledEffectManagedRun');
      }
      if (wholeInputs) {
        if (typeof moon.clientProgramInstalledEffectManagedSourcesLedger !== 'function') {
          throw new Error('InstalledEffectSourceLedgerUnavailable');
        }
        // The same admitted Plan already retains each actual input/read and
        // its complete capacity. A Whole input is never a Query-capacity token.
        ledger = checked(moon.clientProgramInstalledEffectManagedSourcesLedger(
          managedRun, acquired.prepared, acquired.requestIdentity));
      } else {
        if (typeof moon.clientProgramInstalledEffectManagedRunPrepareLedger !== 'function') {
          throw new Error('InstalledEffectSourceLedgerUnavailable');
        }
        ledger = checked(moon.clientProgramInstalledEffectManagedRunPrepareLedger(managedRun,
          acquired.prepared, acquired.requestIdentity, capacities.map(value => value.capacity),
          capacities.map(value => value.transferBytes), capacities.map(value => value.executionBytes),
          registry, values, fragment, ordered));
      }
    }
    for (const source of sources) {
      current();
      const capacity = source.adapter.ledgerCapacity(source.preparedSource);
      if (capacity?.managedRun !== managedRun) throw new Error('ForeignInstalledEffectManagedRun');
      const acquisition = acquisitionEndHandoff();
      let captured: Capture;
      current();
      const admission = await sourceContinuation?.beforeRead(source);
      if (admission?.waiting !== undefined) {
        originalCurrent();
        return Object.freeze({status: 'waiting_checkpoint',
          checkpoint: admission.waiting, cleanupOwner: custody});
      }
      current();
      if (admission?.retained !== undefined) {
        const restored = sourceContinuation!.restore(source, admission.retained, ledger) as
          Readonly<{captured: RetainedCapture; sourceEvidenceWire: string}>;
        captures.push(restored.captured);
        current();
        // This wire came from the same authenticated, current Source closure.
        // Admit its original sealed evidence into this control's nominal map;
        // it is not a newly issued observation or a second provider read.
        const sourceEvidence = infer === undefined && sourceKeyedPreparation === undefined
          ? undefined : acquired.control.admitRunEvidence(
          'source_evidence', restored.sourceEvidenceWire, localContractLimits);
        current();
        evidence.push(sourceEvidence === undefined ? restored : {...restored, sourceEvidence});
        continue;
      }
      // A refused fence proves this attempt has not called the adapter.
      // Do not feed it into the adapter's unknown physical-outcome path.
      admission?.enter!();
      current();
      try {
        // Only this original adapter call starts a new Source attempt. A
        // retained capture or a refused admission must not invent another.
        diagnostic('acquisition_started', {task: source.occurrence.task,
          selection: source.preparedSource.selection});
        captured = await source.adapter.open({preparedEffect: acquired.prepared,
          registry, values, fragment, ordered, sourceAccess: source.access, signal,
          preparedSource: source.preparedSource, occurrence: source.occurrence,
          ledger, reportAcquisitionFailure: acquisition.retain});
      } catch (error) {
        const ended = acquisition.outcome(error);
        recovery = ended.recovery as Cleanup | undefined;
        unresolved = ended.outcome === 'unknown' && recovery === undefined;
        throw error;
      }
      captures.push(captured);
      // Retain physical custody before a post-await refusal. It must still
      // close this acquired source even if its installed owner changed.
      current();
      diagnostic('acquisition_completed', {task: source.occurrence.task,
        acquisition: captured.acquisition});
      current();
      const sourceEvidenceOptions = {
        authorityScopeCid: acquired.authorityScopeCid,
        effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
      let sourceEvidence: Evidence | undefined;
      let sourceEvidenceWire: string;
      if (infer === undefined && sourceKeyedPreparation === undefined) {
        sourceEvidenceWire = await captured.issueSourceEvidence(sourceEvidenceOptions);
      } else {
        await captured.prepareSourceEvidenceOriginal(sourceEvidenceOptions);
        current();
        sourceEvidence = acquired.control.takeSourceEvidenceOriginal(captured.capture);
        sourceEvidenceWire = sourceEvidence.wire;
      }
      current();
      evidence.push({captured, sourceEvidenceWire,
        ...(sourceEvidence === undefined ? {} : {sourceEvidence})});
      await sourceContinuation?.captured(source, captured, sourceEvidenceWire,
        captureStartedAt, now());
      current();
    }
    captureCompletedAt = sourceContinuation?.times().captureCompletedAt ?? now();
    if (!sourceFree) contentFamily?.bindCapture(captures[0], {...evidence[0],
      authorityScopeCid: acquired.authorityScopeCid, captureStartedAt, captureCompletedAt});
    // A completed Source does not close a Run containing a generation barrier.
    // Its original Content evidence must be issued by the selected component
    // before publication is prepared; never fill that inventory with [] or
    // claim a Source-only Invocation for the same checked Template.
    let publicationPlan: PublicationPlan | undefined;
    if (multiple && (pluralModels ? modelGroup !== undefined && !modelGroup.restored() :
        originalModelComponent !== undefined && modelToken === undefined && infer !== undefined)) {
      const member = pluralModels ? modelGroup!.keyedMember() : undefined;
      const keyedTask = member === undefined ? undefined
        : runtimeField(moon.clientProgramInferPlanBoundary(member.selection.graph), 0);
      deferredKeyedMember = member !== undefined && captures.every((value, index) =>
        value.inputKind === 'whole-input' &&
        (sources[index].occurrence.computeTask ?? sources[index].occurrence.task) !== keyedTask) &&
        moon.clientProgramInferOccurrenceResultImports(member.selection.occurrence).length > 0 ? member : undefined;
      keyedFamily = pluralModels && member === undefined || deferredKeyedMember !== undefined ? undefined : await prepareAcquiredEffectKeyedPrefix({moon, acquired, managedRun, infer: member?.selection ?? infer,
        selected: member?.originalSelection ?? originalModelSelection,
        originalPreparation: member?.originalPreparation ?? originalPreparation, plan: modelPlan as KeyedOptions['plan'], captures, sources: evidence as KeyedEvidenceSources, requestJournal, runRef,
        sourceProfile: sourceProfile!, ledger, contentRun, store, principalId, signal, now, current,
        retain(child) {
          if (keyedCleanup !== undefined) throw new Error('InstalledComposedKeyedAlreadyRetained');
          keyedCleanup = child;
        }}) as KeyedFamily | undefined;
      current();
      if (keyedFamily !== undefined) captureCompletedAt = now();
    } else if (infer === undefined && serializations.length === 0 &&
        sourceKeyedPreparation !== undefined) {
      keyedFamily = await prepareAcquiredEffectKeyedCapture({moon, acquired, managedRun,
        sourcePreparation: sourceKeyedPreparation, captures, sources: evidence as KeyedEvidenceSources,
        requestJournal, runRef, sourceProfile: sourceProfile!, ledger, contentRun, store, principalId,
        signal, now, current,
        retain(child) {
          if (keyedCleanup !== undefined) throw new Error('InstalledComposedKeyedAlreadyRetained');
          keyedCleanup = child;
        }}) as KeyedFamily | undefined;
      current();
      captureCompletedAt = now();
    }
    async function handleModelPause(boundary: Pick<Pause, 'status' | 'slot'>) {
      current();
      const operation = component!.operation();
      if (operation === undefined || inferCapture === undefined) throw new Error('ModelPauseOwnerMissing');
      if (boundary.status === 'settling') {
        const settlement = operation.pendingSettlement();
        const slot = operation.settlementSlot(settlement);
        const entry = modelContinuation?.entry(slot!);
        if (entry === undefined || slot !== boundary.slot) throw new Error('ModelPauseSettlementMismatch');
        current();
        await inferCapture.persistSettlement(settlement, entry);
        current();
        return {action: 'resume'};
      }
      if (boundary.status !== 'waiting') throw new Error('InvalidModelPause');
      if (modelContinuation === undefined) {
        const preparedCallSet = operation.preparedCallSet();
        if (preparedCallSet === undefined) throw new Error('ModelPausePreparedOwnerMissing');
        current();
        const sourceClosure = await sourceContinuation?.retainAll();
        current();
        modelContinuation = await modelController!.open({operation, preparedCallSet,
          plan: modelPlan!, selected: infer!, principalId,
          declaredResults: moon.clientProgramEffectCompilationResultNames(acquired.compilation),
          submission, signal, existing: modelRecord, inputToken: modelToken, claim: modelClaim, parentResume,
          journalPort: modelJournalPort, sourceContinuation: sourceClosure});
        current();
        inferCapture.configureModelJournal({observe: modelContinuation.observe, entry: modelContinuation.entry});
        if (modelRecord !== undefined) return {action: 'resume'};
      }
      current();
      const decision = await modelContinuation.authorize();
      if (decision.status === 'dispatch') {
        current();
        return {action: 'resume'};
      }
      originalCurrent();
      if (decision.status !== 'waiting_checkpoint') throw new Error('InvalidModelPauseDecision');
      // Stop/cleanup the retained Model owner before Local settles its
      // reservation. This handle never calls operation.run or a provider.
      const cleanupHandle = Object.freeze({
        status: () => ({pending: inferCleanupPending()}),
        retry: cleanupInfer,
      });
      return {action: 'waiting_checkpoint', checkpoint: decision.checkpoint,
        cleanupPending: true, cleanupHandle};
    }
    if (pluralModels) modelGroup!.bind({captures, evidence: evidence as ModelSources, captureStartedAt, captureCompletedAt,
      keyedFamily, contentFamily});
    else if (component === undefined && infer !== undefined) component = prepareInferComponent();
    current();
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    const currentPlan = checked(Reflect.apply(readPlan, moon,
      [managedRun, preparedOriginal, requestOriginal]));
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    if (currentPlan !== operationPlan) throw new Error('ForeignInstalledEffectManagedRun');
    const restoredModel = restoredKeyedSource !== undefined;
    if (pluralModels && modelGroup!.restored()) {
      const decision = await modelGroup!.restore();
      current();
      if (decision?.status === 'waiting_checkpoint') return Object.freeze({...decision, cleanupOwner: custody});
      restoredModelHostAttempted = true;
      hostOpenAttempted = true;
      checkedHost = modelGroup!.openRestoredHost(managedRun, owner, captures);
    } else if (restoredModel) {
      const operation = component!.startRestored();
      for (;;) {
        current();
        const boundary = await operation.run();
        current();
        if (boundary?.status !== 'waiting' && boundary?.status !== 'settling') break;
        const pause = boundary.status === 'settling' ? {...boundary,
          slot: operation.settlementSlot(boundary.settlement)} : boundary;
        const decision = await handleModelPause(pause);
        if (decision.action === 'waiting_checkpoint') {
          return Object.freeze({status: 'waiting_checkpoint', checkpoint: decision.checkpoint,
            cleanupOwner: custody});
        }
      }
      if (inferCapture!.retainCompleted() === false) throw new Error('InstalledInferCaptureUnavailable');
      current();
      restoredModelOutput = operation.acquireOutput();
      if (restoredModelOutput === undefined) throw new Error('RestoredModelOutputUnavailable');
      current();
      restoredModelHostAttempted = true;
      hostOpenAttempted = true;
      checkedHost = acquired.control.openCheckedClientInstalledRestoredModelEffectHost(
        modelPlan!.compiled, modelPlan!.runDefinition, managedRun, owner,
        captures.map(value => value.capture.source()), restoredModelOutput,
        (originalModelSelection ?? infer)!.graph);
    } else {
      hostOpenAttempted = true;
      checkedHost = checked(deferredKeyedMember !== undefined
        ? moon.clientProgramInstalledEffectManagedDeferredKeyedHostOpen(managedRun, owner,
          captures.map(value => value.capture.source()))
        : keyedFamily === undefined ? moon.clientProgramInstalledEffectManagedHostOpen(managedRun, owner, captures.map(value => value.capture.source()))
        : moon.clientProgramInstalledEffectManagedKeyedHostOpen(managedRun,
          owner, captures.map(value => value.capture.source()), keyedFamily.lookup));
    }
    if (checkedHost === undefined) {
      throw new Error('InstalledEffectProgramUnsupported');
    }
    // Without a returned Compute owner an exception cannot prove a stop.
    // Keep the responsibility rather than relabeling it as released.
    unresolved = true;
    // The existing custody was retained before Host construction. Issue once
    // on its actual DAG; an issuer failure keeps that same cleanup owner.
    if (infer === undefined && serializations.length === 0) {
      publicationPlan = keyedFamily?.sourceOriginal !== undefined
        ? acquiredKeyedEffectPublicationPlan({acquired, sources: evidence, keyedFamily: keyedFamily as Parameters<typeof acquiredKeyedEffectPublicationPlan>[0]['keyedFamily'],
          captureStartedAt, captureCompletedAt, sourcePlan: operationPlan,
          managedRun, sourceHost: checkedHost,
          deferCatalogs: managedRun !== undefined && operationPlan !== undefined},
          sourceKeyedPreparation!.runDefinition)
        : multiple
        ? acquiredMultiEffectPublicationPlan({acquired, sources: evidence,
          captureStartedAt, captureCompletedAt, sourcePlan: operationPlan,
          managedRun, sourceHost: checkedHost,
          deferCatalogs: managedRun !== undefined && operationPlan !== undefined})
        : acquiredEffectPublicationPlan({acquired, ...evidence[0],
          captureStartedAt, captureCompletedAt, sourcePlan: operationPlan,
          managedRun, sourceHost: checkedHost,
          deferCatalogs: managedRun !== undefined && operationPlan !== undefined});
    }

    if (multiple || wholeInputs || contentFamily !== undefined) {
      const dag = moon.strategyHostRun(moon.clientProgramLocalEffectHostRuntime(checkedHost));
      for (const [task, captured] of captures.entries()) {
        captured.capture.retainTask(dag, captured.occurrence?.computeTask ?? task);
      }
    }
    if ((component !== undefined || modelGroup !== undefined || contentFamily !== undefined) && typeof withComputePauseHandler !== 'function') {
      throw new TypeError('PhysicalPauseConfigurationMissing');
    }
    async function beforeModelPrepare(task: number, physicalSource: unknown) {
      await modelGroup?.prepareNext(task, physicalSource);
      current();
      if (deferredKeyedMember === undefined || task !== runtimeField(
          moon.clientProgramInferPlanBoundary(deferredKeyedMember.selection.graph), 0)) return;
      if (!keyedAttempted) {
        keyedAttempted = true;
        keyedPreparation = Promise.resolve().then(async () => {
          current();
          const member = deferredKeyedMember!;
          keyedFamily = await prepareAcquiredEffectKeyedPrefix({moon, acquired, managedRun,
            infer: member.selection, selected: member.originalSelection,
            originalPreparation: member.originalPreparation, plan: modelPlan as KeyedOptions['plan'], captures, sources: evidence as KeyedEvidenceSources,
            requestJournal, runRef, sourceProfile: sourceProfile!, ledger, contentRun, store, principalId, signal, now,
            current, originalHost: checkedHost,
            retain(child) {
              if (keyedCleanup !== undefined) throw new Error('InstalledComposedKeyedAlreadyRetained');
              keyedCleanup = child;
            }}) as KeyedFamily | undefined;
          current();
          if (keyedFamily === undefined) throw new Error('OriginalKeyedHostInputUnavailable');
          checked(moon.clientProgramInstalledEffectManagedKeyedHostBind(managedRun, checkedHost, keyedFamily.lookup));
          current();
          captureCompletedAt = now();
          modelGroup!.bindKeyedFamily(keyedFamily, captureCompletedAt);
        });
      }
      await keyedPreparation;
      current();
    }
    const configurations = component === undefined && modelGroup === undefined && contentFamily === undefined ? computeConfigurations
      : withComputePauseHandler!(computeConfigurations, async boundary => {
        current();
        // Slots are local to each child. A shared numerical slot must not
        // route a Model settlement into the already-completed Content owner.
        if (contentFamily !== undefined && contentFamily.generation() === undefined) {
          const decision = await contentFamily.handlePause(boundary as Parameters<Family['handlePause']>[0]);
          current();
          return decision;
        }
        if (modelGroup !== undefined) return modelGroup.handlePause(boundary);
        if (component !== undefined) return handleModelPause(boundary);
        throw new Error('PhysicalPauseOwnerMissing');
      }, beforeModelPrepare);
    current();
    computeEntered = true;
    execution = await runCapturedEffectComputation(checkedHost,
      {...configurations,
        authorization: multiple ? undefined : singleSourceAccess?.authorization}, signal,
      undefined, {retainPreflightCleanup});
    unresolved = false;
    if (execution.status === 'host-tasks-waiting') {
      originalCurrent();
      return Object.freeze({status: 'waiting_checkpoint', checkpoint: execution.checkpoint,
        execution, checkedHost, cleanupOwner: custody});
    }
    current();
    if (execution.status !== 'host-tasks-completed' && modelGroup !== undefined) await modelGroup.persistStopped();
    if (execution.status !== 'host-tasks-completed' && component?.operation()?.physicalStopped()) {
      current();
      await inferCapture!.persistStoppedAttempts();
      current();
    }
    if (execution.status !== 'host-tasks-completed' && (component !== undefined || modelGroup !== undefined) &&
        modelController!.unresolved(acquired.control.runDefinitionRunId(acquired.runDefinition))) {
      let primaryFailure, primaryRecorded = false;
      try {
        if (modelGroup?.hasFailure()) {
          primaryFailure = modelGroup.failure();primaryRecorded = true;
        } else if (component?.hasFailure?.()) {
          primaryFailure = component.failure();primaryRecorded = true;
        } else if (Object.hasOwn(execution, 'failure')) {
          primaryFailure = execution.failure;primaryRecorded = true;
        }
      } catch { /* Failure inspection cannot replace the actual Unknown outcome. */ }
      return Object.freeze({status: 'needs_reconciliation', modelUnknown: true,
        execution, checkedHost, cleanupOwner: custody,
        ...(primaryRecorded ? {primaryFailure} : {})});
    }
    if (execution.status !== 'host-tasks-completed') {
      if (modelGroup?.hasFailure()) throw modelGroup.failure();
      throw component?.failure() ?? execution.failure ?? new Error('InstalledEffectComputationFailed');
    }
    observeUsage('effect_computation_completed', {
      carrierSnapshots: (execution.completed ?? [])
        .filter(task => task.snapshot !== undefined)
        .map(task => ({task: task.task, ...(task.snapshot as object)})),
      relationSnapshots: (execution.completed ?? [])
        .filter(task => task.relationSnapshot !== undefined)
        .map(task => ({task: task.task, ...(task.relationSnapshot as object)})),
    });
    if (modelGroup !== undefined) {
      publicationPlan = await modelGroup.persist();
      current();
      const refreshScratch = execution.refreshCompletedScratch;
      if (typeof refreshScratch !== 'function') throw new TypeError('InstalledEffectCompletedScratchUnavailable');
      if (!modelGroup.hasOutputPins() && !await retireInferPublication()) throw Object.assign(new Error('ClientDispatchCleanupPending'), {code: 'ClientDispatchCleanupPending'});
      current();
      await Reflect.apply(refreshScratch, execution, []);
      current();
      await faultInjection?.('infer_capture_committed', {});
      current();
    }
    if (component !== undefined) {
      if (inferCapture === undefined) throw component.failure() ?? new Error('InstalledInferCaptureUnavailable');
      current();
      publicationPlan = (await inferCapture.persist())!.plan;
      current();
      if (originalPreparation !== undefined && restoredModelOutput === undefined) {
        // The complete immutable publication plan and Store capture now own
        // their evidence. Retire only publication aliases/capacity here;
        // the same Model/output, Content and journal keep their own lifetime.
        const refreshScratch = execution.refreshCompletedScratch;
        if (typeof refreshScratch !== 'function') {
          throw new TypeError('InstalledEffectCompletedScratchUnavailable');
        }
        if ((publicationPlan as InferPublication['plan'] & {localEvidenceContext?: {modelOriginalByUnit?: unknown}}).localEvidenceContext?.modelOriginalByUnit !== undefined) {
          // Final Effect dependency issuance still needs the live Model
          // observation. Stop only its completed physical work here; the
          // existing enclosing cleanup retires its binding after consumption.
          await inferOperation!.stop();
        } else if (!await retireInferPublication()) {
          throw Object.assign(new Error('ClientDispatchCleanupPending'),
            {code: 'ClientDispatchCleanupPending'});
        }
        current();
        // This reconciles actual stopped-provider scratch while preserving
        // successful output/holding custody. It grants no physical close ACK.
        await Reflect.apply(refreshScratch, execution, []);
        current();
      }
      await faultInjection?.('infer_capture_committed', {});
      current();
    }
    if (contentFamily !== undefined && component === undefined && modelGroup === undefined) {
      const generation = contentFamily.generation();
      if (generation === undefined) throw new Error('InstalledContentGenerationEvidenceUnavailable');
      publicationPlan = sourceFree
        ? sourceFreeContentEffectPublicationPlan({acquired,compiled:contentPlan!.compiled,generation,
          managedRun, sourcePlan: operationPlan, sourceHost: checkedHost})
        : acquiredEffectPublicationPlan({acquired, ...evidence[0],
          captureStartedAt, captureCompletedAt, content: {...contentPlan!, generation},
          managedRun, sourcePlan: operationPlan, sourceHost: checkedHost,
          deferCatalogs: managedRun !== undefined && operationPlan !== undefined});
    }
    if (publicationPlan === undefined) {
      throw new Error('InstalledContentGenerationEvidenceUnavailable');
    }
    current();
    const result: {execution: Execution; checkedHost: CheckedHost; publicationPlan: PublicationPlan;
      cleanupOwner: typeof custody; contentOwner?: Family | KeyedFamily['contentOwner']} =
      {execution, checkedHost, publicationPlan, cleanupOwner: custody};
    // The serialization family keeps priority. A Source-only keyed frame owns
    // its original Reference/Store bytes even when there is no such family.
    // Both are borrowed from their retained cleanup owner, never rebuilt CIDs.
    const contentOwner = contentFamily ?? keyedFamily?.contentOwner;
    if (contentOwner !== undefined) result.contentOwner = contentOwner;
    return Object.freeze(result);
  } finally {
    settled = true;
  }
}

// The original acquisition/dispatch boundary keeps the same prepared/request
// across the bound getter and its existing outer current callback.
function assertAcquiredEffectOriginal(acquired: Pick<Acquired, 'prepared' | 'requestIdentity'>, prepared: unknown, request: unknown) {
  if (acquired.prepared !== prepared || acquired.requestIdentity !== request) {
    throw Object.assign(new Error('ForeignInstalledEffectManagedRun'),
      {code: 'ForeignInstalledEffectManagedRun'});
  }
}
