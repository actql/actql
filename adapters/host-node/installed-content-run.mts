// Installed transport for the original checked Content component. Compute,
// byte laws, identity and publication remain in their existing common owners.
import {checked} from '../host-common/runtime-result.mjs';
import {contentCid} from './local-account-config.mjs';
import {localOutputLimits, localContractLimits,
  serializationTaskPublicationPlan} from './local-values-plan.mjs';
import {runGeneratedContentPrefix, identifyGeneratedContentInput,
  writeGeneratedContent, stopGeneratedContentPrefix} from './generated-content-write.mjs';
import {issueStoredGeneratedContent, retainGeneratedContentEvidence} from './generated-content-holding.mjs';
import {serializationPublicationExecution} from './serialization-result-publication.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {installEffectContentFamily} from './installed-content-family.mjs';
import {createContentRecoveryDispatch} from './content-recovery-dispatch.mjs';
import {installRunKeyedContentCapture} from './installed-keyed-content-capture.mjs';
import {createKeyedContentRunRecovery} from './keyed-content-run-recovery.mjs';
import {createGeneratedContentRunRecovery} from './generated-content-run-recovery.mjs';

import type {contentGenerationControl} from '../host-common/content-generation-control.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import type {managedProgramInitialRetention} from './local-publication-plan.mjs';

type Control = ReturnType<typeof contentGenerationControl>;
type Prefix = Parameters<Control['prefixCancel']>[0];
type Input = Parameters<Control['inputCancel']>[0];
type Bodies = Parameters<Control['prefix']>[3];
type PrefixLimits = Parameters<Control['prefix']>[4];
type Workspace = ReturnType<Control['workspaceCapacity']>;
type GenerationLimits = Parameters<Control['encoder']>[1];
type ReferenceLimits = Parameters<Control['recoveryCandidate']>[2];
type ContractLimits = Parameters<Control['inputIdentityFinish']>[2];
type Demand = ReturnType<Control['prepareRequestOutputDemand']>;
type OutputLimits = Demand['outputLimits'];
type Capacity = ReturnType<Control['prefixCapacity']>;
type Store = Awaited<ReturnType<typeof openLocalPublicationStore>>;
type Writer = ReturnType<Store['createPreparedObjectWriter']>;
type Physical = Awaited<ReturnType<Writer['seal']>>;
type Holding = Readonly<{
  version: 'actql-local-physical-holding/0.1';
  namespace: 'content';
  holding_cid: string;
  manifest_cid: string;
  objects: readonly Readonly<{cid: string; byte_count: number}>[];
}>;
type Retirement = Awaited<ReturnType<Store['retirePhysicalHolding']>>['cleanup'];
type CommonObject = Prefix;
type HeldEvidence = Awaited<ReturnType<typeof retainGeneratedContentEvidence>>;
type Serialize = Parameters<typeof serializationPublicationExecution>[0];
type Complete = Parameters<typeof publishCompletedEffectFreeRun>[0];
type PublicationPlan = Parameters<typeof serializationTaskPublicationPlan<Complete['results'][number]['retention']>>[0];
type Publication = ReturnType<typeof serializationTaskPublicationPlan<Complete['results'][number]['retention']>> &
  Omit<Complete, 'execution' | 'store' | 'control' | 'signal'>;
type CaptureSetup = Parameters<typeof installRunKeyedContentCapture>[0];
type CapturedFrame = ReturnType<typeof installRunKeyedContentCapture>;
type CaptureOptions = Omit<CaptureSetup, 'moon' | 'publications' | 'control' | 'namespaceId' |
  'authorityScopeCid' | 'storeAuthorityCid' | 'ownerPrincipal' | 'now' | 'authorize'>;
type Family = Parameters<typeof installEffectContentFamily>[0];
type ManagedFamily = NonNullable<Family['managedOriginal']>;
type RecoveryDispatch = Parameters<typeof createContentRecoveryDispatch>[0];
type GeneratedRecovery = Parameters<typeof createGeneratedContentRunRecovery>[0];
type PrepareGraph = Family['plan']['serializationGraph'];
type RunDefinition = PublicationPlan['admitted']['runDefinition'];
type RunPlan = PublicationPlan['admitted'] & Readonly<{serializationGraph?: PrepareGraph; inferGraph?: unknown}>;
type PreparationInputs = Readonly<{preparedProgram: CommonObject; plan: RunPlan; request: unknown}>;
type Managed = Parameters<typeof managedProgramInitialRetention>[4] & Readonly<{
  selectedKeyed?: unknown;
  serialization?: unknown;
  contentCompilation?: unknown;
}>;
type ModelPreparation = {
  compiled: RunPlan['compiled'];
  runDefinition: RunDefinition;
  graph: unknown;
  serializationGraph: PrepareGraph;
  contentPreparation?: Preparation;
};
type Preparation = {
  prepared: CommonObject;
  plan: RunPlan;
  request: unknown;
  attempted: boolean;
  capacity?: Capacity;
  managed?: Managed;
  inputHolder?: unknown;
  localPreparation?: Readonly<{releaseAliases(managed: Managed | undefined, inputHolder: unknown): unknown}>;
  releaseSelection?: (prepared: CommonObject) => unknown;
  contentControl: Control;
  retired: boolean;
  failed: boolean;
  failure?: unknown;
  model?: ModelPreparation;
  ordinarySource?: boolean;
  prefixLimits?: PrefixLimits;
  generationLimits?: GenerationLimits;
  outputLimits?: OutputLimits;
  identitySlots?: number;
  workspace?: Workspace;
  acquiredLedgerAttempted?: boolean;
  acquiredLedger?: CommonObject;
};
type RetainedPreparation<Original extends Preparation | KeyedPreparation = Preparation | KeyedPreparation> = Original & Readonly<{
  releaseAliases(managed: Managed | undefined, inputHolder: unknown): undefined;
}>;
type KeyedRecipe = Bodies & PrepareGraph & Readonly<{keyedAcquisition: unknown; prefixLimits: PrefixLimits; workspace: Workspace}>;
type KeyedPreparation = Omit<Preparation, 'plan'> & {
  plan?: RunPlan;
  serializationGraph: PrepareGraph;
  keyedAcquisition: unknown;
  recipe?: KeyedRecipe;
};
type LedgerCapacity = Readonly<{capacity: unknown; transferBytes: bigint; executionBytes: bigint}>;
type KeyedCapacity = LedgerCapacity & Readonly<{maxBytes: number; maxWork: number}>;
type CaptureProof = Parameters<ReturnType<typeof import('../host-common/runtime-core.mjs').runtimeCore>['publicationControl']['bindCheckedClientSerializationCapture']>[3];
type ManagedSource = Parameters<ReturnType<typeof import('../host-common/runtime-core.mjs').runtimeCore>['publicationControl']['bindCheckedClientSerializationManagedCaptures']>[4][number];
type AcquiredContent = CaptureProof & Readonly<{
  ledger: CommonObject;
  captured: Readonly<{capture: Readonly<{source(): CommonObject; originalRowCapture(): unknown}>}>;
  keyedLookup?: CommonObject;
  keyedContent?: CapturedFrame;
  managedSources?: readonly (ManagedSource & Readonly<{sourceEvidence: unknown}>)[];
  sourceEvidence?: unknown;
  keyedSourceEvidence?: unknown;
}>;
type Execution = Readonly<{
  close(): Promise<boolean>;
  cleanup(): Promise<boolean>;
  cleanupPending(): boolean;
  resourceUsage(): unknown;
  cumulativeWork(): bigint;
}>;
type ContentStore = Complete['store'] & Parameters<typeof retainGeneratedContentEvidence>[0]['store'] &
  Parameters<typeof issueStoredGeneratedContent>[0]['store'] &
  Pick<Store, 'createPreparedObjectWriter' | 'confirmCommittedIndex' | 'retirePhysicalHolding'>;
type ExecuteOptions = Readonly<{
  preparedProgram: CommonObject; plan: RunPlan; store: ContentStore; principalId: string;
  signal?: AbortSignal; retainExecution(execution: Execution): unknown; acquiredContent?: AcquiredContent;
}>;
type CleanupHandle = Readonly<{retry(): Readonly<{pending: boolean}> | PromiseLike<Readonly<{pending: boolean}>>}>;
type CleanupFailure = Readonly<{cleanupPending?: unknown; cleanupHandle?: CleanupHandle}> | null | undefined;
type EffectFacts = Readonly<{
  modelCompiled?: unknown; allowed: unknown; runDefinition: Family['plan']['runDefinition'];
  prepared: unknown; compilation: unknown;
}>;
type Generated = Readonly<{
  generation: ReturnType<Control['complete']>;
  capturedContentRecovery: ReturnType<CapturedFrame['recoveryInventory']>;
  capturedContentBinding: CapturedFrame['sourceBinding'];
  sourceEvidence: readonly unknown[];
  recoveryBindings: HeldEvidence['bindings'];
  recovery: Readonly<{referenceWire: string; binding: Readonly<Record<string, unknown>>;
    byteHoldingCid: string; bindings: HeldEvidence['bindings']}>;
}>;
type KeyedPreparationInputs = PreparationInputs & Readonly<{keyedAcquisition: unknown}>;
type KeyedCompilationInputs = Omit<KeyedPreparationInputs, 'plan'> & Readonly<{serializationGraph: PrepareGraph}>;
type AcquiredLedgerInputs = Pick<PreparationInputs, 'preparedProgram' | 'plan'> &
  Readonly<{sourceCapacity: LedgerCapacity & {managedRun?: unknown}}>;
type OrdinaryLedgerInputs = Pick<PreparationInputs, 'preparedProgram' | 'plan'> &
  Readonly<{sourceCapacities: readonly (LedgerCapacity & {managedRun?: unknown; wholeInput?: boolean})[]}>;
type KeyedLedgerInputs = Pick<PreparationInputs, 'preparedProgram' | 'plan'> & Readonly<{
  direct: LedgerCapacity; acquisition: unknown; capacity: KeyedCapacity; capturedContent?: boolean;
}>;
type EffectSetup = Readonly<{facts: EffectFacts; store: Family['store']; principalId: string; retainCleanup: Family['retainCleanup']}>;
type EffectOptions = Pick<Family, 'prepared' | 'plan' | 'store' | 'principalId' | 'signal' | 'restored' | 'retainCleanup' | 'managedOriginal'>;

type EffectSelection = Readonly<{
  family: ReturnType<typeof installEffectContentFamily>;
  plan: Family['plan'] & Readonly<{kind: 'effect'}>;
  preparation: ReturnType<typeof installEffectContentFamily>['preparation'];
}>;
type ContentRun = ((options: ExecuteOptions) => Promise<Generated | undefined>) & Readonly<{
  prepareRun(options: PreparationInputs & {ordinarySource?: boolean}): Managed | undefined;
  prepareModelRun(options: PreparationInputs & Readonly<{model: ModelPreparation}>): void;
  generate(options: ExecuteOptions): Promise<Generated | undefined>;
  prepareManagedKeyedCompilation(options: KeyedCompilationInputs): unknown;
  prepareManagedKeyedRun(options: KeyedPreparationInputs): void;
  captureKeyed(options: CaptureOptions): CapturedFrame;
  recoverKeyed: ReturnType<typeof createKeyedContentRunRecovery>;
  prepareEffectFamily(options: EffectSetup): EffectSelection;
  effectFamily(options: EffectOptions): ReturnType<typeof installEffectContentFamily>;
  prepareRecoveredCommandContent: ReturnType<typeof createContentRecoveryDispatch>;
  prepareAcquiredLedger(options: AcquiredLedgerInputs): CommonObject;
  prepareOrdinaryAcquiredLedger(options: OrdinaryLedgerInputs): CommonObject;
  prepareKeyedLedger(options: KeyedLedgerInputs): CommonObject;
  recover: ReturnType<typeof createGeneratedContentRunRecovery>;
}>;

type Publications = PublicationPlan['control'] & Complete['control'] &
  Serialize['core']['publicationControl'] & CaptureSetup['publications'] & Family['publications'] &
  RecoveryDispatch['publications'] & GeneratedRecovery['publications'] & Readonly<{
    compiledSerializationPolicy(compiled: unknown): Readonly<{cid: string; wire: string}> | undefined;
    bindCheckedClientSerializationCapture(prepared: unknown, graph: PrepareGraph,
      captured: AcquiredContent['captured'], acquired: AcquiredContent): unknown;
    bindCheckedClientSerializationManagedCaptures(run: unknown, prepared: unknown, selected: unknown, graph: PrepareGraph,
      sources: readonly ManagedSource[], authority: string, started: string, completed: string): unknown;
    compiledSerializationGraph(compiled: unknown): PrepareGraph;
    checkedClientSerializationInputRows(compiled: unknown, graph: PrepareGraph): number | undefined;
    prepareCheckedClientEffectContentOriginal(prepared: unknown, compiled: unknown, compilation: unknown,
      definition: EffectFacts['runDefinition'], graph: PrepareGraph, bodies: Bodies,
      ...args: Parameters<ManagedFamily['prepare']>): ReturnType<ManagedFamily['prepare']>;
  }>;
type Moon = PublicationPlan['moon'] & CaptureSetup['moon'] & Family['moon'] & Readonly<{
  clientProgramAcquisitionCount(prepared: unknown): number;
  clientProgramPreparationBorrowRead(holder: unknown): unknown;
  clientProgramPreparationBorrowRetirementStarted(holder: unknown): boolean;
  clientProgramMultiCapturedLedgerUsage(ledger: unknown): unknown;
  clientProgramInstalledManagedRunAccounting(run: unknown): unknown;
  clientRequestScopeCid(request: unknown): unknown;
  clientRequestIntentCid(request: unknown): unknown;
  clientProgramInstalledManagedRunPrepareLedger?(parent: unknown, prepared: unknown, request: unknown,
    capacities: readonly unknown[], transfers: readonly bigint[], executions: readonly bigint[],
    registry: Bodies['registry'], values: Bodies['values'], fragment: Bodies['fragment'], ordered: Bodies['ordered']): unknown;
  clientProgramInstalledManagedWholeSourcesLedger?(parent: unknown, prepared: unknown, request: unknown,
    capacities: readonly unknown[], transfers: readonly bigint[], executions: readonly bigint[]): unknown;
  clientProgramPrepareSerializationCapturedLedger(prepared: unknown, task: number, capacity: unknown,
    transferBytes: bigint, executionBytes: bigint, retainedBytes: bigint, executionSpace: bigint,
    registry: Bodies['registry'], values: Bodies['values'], fragment: Bodies['fragment'], ordered: Bodies['ordered']): CommonObject | undefined;
  clientProgramPrepareKeyedSerializationCapturedLedger(prepared: unknown, directCapacity: unknown,
    acquisition: unknown, keyedCapacity: unknown, transfers: readonly bigint[], executions: readonly bigint[],
    maxBytes: number, maxWork: number, registry: Bodies['registry'], values: Bodies['values'], fragment: Bodies['fragment'],
    ordered: Bodies['ordered'], task: number, step: number, retainedBytes: bigint, executionSpace: bigint,
    capturedContent: boolean): CommonObject | undefined;
}>;
type Setup = Bodies & Pick<CaptureSetup, 'namespaceId' | 'authorityScopeCid' | 'storeAuthorityCid' |
  'ownerPrincipal' | 'now' | 'authorize'> & Readonly<{
  moon: Moon;
  core: Readonly<{
    contentGenerationControl: Control;
    publicationControl: Publications;
    contentCaptureControl: CaptureSetup['control'] & RecoveryDispatch['core']['contentCaptureControl'];
    outputExportControl: Serialize['core']['outputExportControl'];
  }>;
  faultInjection?: (step: string, facts: unknown) => unknown;
  assertRunCurrent?: () => undefined;
  preparedRunRequired?: boolean;
  prepareKeyedManagedRun?: (prepared: CommonObject, request: unknown, graph: PrepareGraph,
    recipe: KeyedRecipe, original: RetainedPreparation<KeyedPreparation>) => Managed | undefined;
  borrowKeyedManagedLedger?: (prepared: CommonObject, request: unknown, recipe: KeyedRecipe | undefined,
    direct: LedgerCapacity, keyed: unknown, capacity: KeyedCapacity) => CommonObject | undefined;
  prepareSerializationManagedRun?: (prepared: CommonObject, request: unknown, plan: RunPlan,
    limits: PrefixLimits, workspace: Workspace | undefined, original: RetainedPreparation<Preparation>) => Managed | undefined;
  prepareModelManagedRun?: (prepared: CommonObject, request: unknown, model: ModelPreparation) => Managed | undefined;
  retainPreparation?: (prepared: CommonObject, original: RetainedPreparation) => unknown;
  prepareSerializationOutputDemand?: (prepared: CommonObject, compiled: unknown, selection: PrepareGraph | undefined,
    generation: GenerationLimits, reference: ReferenceLimits, contract: ContractLimits, output: OutputLimits,
    identitySlots: number) => Demand;
}>;

export function installNodeContentRun({moon, core, registry, values, fragment, ordered,
  namespaceId, authorityScopeCid, storeAuthorityCid, ownerPrincipal, now, authorize,
  faultInjection, assertRunCurrent, preparedRunRequired = false,
  prepareKeyedManagedRun, borrowKeyedManagedLedger, prepareSerializationManagedRun,
  prepareModelManagedRun, retainPreparation, prepareSerializationOutputDemand}: Setup): ContentRun {
  const control = core.contentGenerationControl;
  const publications = core.publicationControl;
  const bodies = {registry, values, fragment, ordered};
  // Fixed installed finite ceilings; they never come from request JSON.
  const prefixLimits = Object.freeze({maxRows: localOutputLimits.maxRows,
    maxWork: 1000000, maxEntries: 100000, maxValueBytes: 1000000,
    maxValueNodes: 100000, maxValueDepth: 64, maxFrames: 256});
  const generationLimits = Object.freeze({maxRows: localOutputLimits.maxRows,
    maxBytes: localOutputLimits.maxWireBytes, maxValueNodes: 100000,
    maxValueDepth: 64, maxFrames: 256});
  const referenceLimits = Object.freeze({maxBytes: 16384, maxNodes: 256,
    maxDepth: 32, maxTextUnits: 16384});
  const completionLimits = Object.freeze({maxNodes: 1000, maxTextBytes: 100000,
    maxDepth: 64, maxWork: 100000, maxNameBytes: 16384});
  const identitySlots = 4 * localOutputLimits.maxWireNodes + 8 * localOutputLimits.maxColumns;
  const workspace = control.workspaceCapacity({generation: generationLimits,
    reference: referenceLimits, contract: localContractLimits,
    output: localOutputLimits, identitySlots});
  const acquiredLedgers = new WeakMap<CommonObject, RunPlan['compiled']>();
  const preparedRuns = new WeakMap<CommonObject, Preparation>();
  const preparedKeyedRuns = new WeakMap<CommonObject, KeyedPreparation>();
  let preparedRunCount = 0;
  function releasePreparationAliases(this: Preparation | KeyedPreparation, managed: Managed | undefined, inputHolder: unknown) {
    const original = this;
    if (original.retired === true) return;
    const prepared = original.prepared;
    if ((preparedRuns.get(prepared) !== original && preparedKeyedRuns.get(prepared) !== original) ||
        original.managed !== managed && managed !== undefined) throw new TypeError('ForeignInstalledContentRun');
    if (managed !== undefined) {
      // The original Host invokes this only inside its checked retirement
      // operation. Do not repeat its fallible current/payload observation.
      if (managed.retiringContent !== true || managed.prepared !== prepared ||
          managed.request !== original.request) throw new TypeError('InstalledContentRunCleanupPending');
    } else if (original.managed?.value !== undefined || inputHolder === undefined ||
        original.inputHolder !== inputHolder ||
        moon.clientProgramPreparationBorrowRead(inputHolder) !== prepared ||
        moon.clientProgramPreparationBorrowRetirementStarted(inputHolder) !== true) {
      throw new TypeError('InstalledContentRunCleanupPending');
    }
    if (original.localPreparation !== undefined) {
      Reflect.apply(original.localPreparation.releaseAliases, original.localPreparation, [managed, inputHolder]);
    }
    if (preparedRunCount <= 0) throw new TypeError('InvalidInstalledContentPreparationCount');
    // The original Host captured this pure cut before retaining the record.
    // Spend it before a consumed parent return can fail; partial construction
    // reaches this point only through the SAME Request abort/holder fence.
    if (typeof original.releaseSelection !== 'function') throw new TypeError('ForeignInstalledContentRun');
    Reflect.apply(original.releaseSelection, undefined, [prepared]);
    for (const key of Object.keys(original)) (original as Record<string, unknown>)[key] = undefined;
    original.retired = true;
    preparedRunCount--;
  }
  function retainOriginalPreparation(prepared: CommonObject, original: Preparation | KeyedPreparation) {
    Object.defineProperty(original, 'releaseAliases', {value: releasePreparationAliases});
    try { retainPreparation!(prepared, original as RetainedPreparation); }
    catch (cause) {
      // The fixed retainer refuses before taking this record. No constructor
      // or physical child has started; its unaccepted slot is not a Run.
      if (original.inputHolder === undefined) {
        for (const key of Object.keys(original)) (original as Record<string, unknown>)[key] = undefined;
        original.retired = true; preparedRunCount--;
      }
      throw cause;
    }
  }
  const installedBinding = (plan: Pick<Family['plan'], 'compiled' | 'runDefinition'>) => {
    const definition = JSON.parse(plan.runDefinition.wire) as Readonly<{valid_until: string}>;
    const graphPolicy = publications.compiledSerializationPolicy(plan.compiled);
    if (graphPolicy === undefined) throw new Error('ContentPolicyMissing');
    return {graphPolicy, binding: {
      content_store_id: namespaceId, content_store_cid: storeAuthorityCid,
      workspace_scope_cid: authorityScopeCid, storage_scope: 'workspace',
      retention_class: 'local-content', expires_at: definition.valid_until,
      availability_evidence_cid: contentCid({version: 'actql-installed-local-policy/0.1',
        name: 'content-availability', storeAuthorityCid, runDefinitionCid: plan.runDefinition.identity,
        expiresAt: definition.valid_until}), effective_data_policy_cid: graphPolicy.cid,
      data_classification: (JSON.parse(graphPolicy.wire) as Readonly<{classification: string}>).classification,
      issuer_contract_cid: contentCid({version: 'actql-installed-local-policy/0.1',
        name: 'content-issuer', storeAuthorityCid, authorityScopeCid}),
      capture_authority_cid: authorityScopeCid,
    }};
  };
  const execute = async ({preparedProgram, plan, store, principalId, signal, retainExecution,
    acquiredContent}: ExecuteOptions, intermediate = false): Promise<Generated | undefined> => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (plan.kind !== (intermediate ? 'infer' : 'serialization') ||
        plan.serializationGraph === undefined || principalId !== ownerPrincipal ||
        store.storeAuthorityCid !== storeAuthorityCid || typeof retainExecution !== 'function') {
      throw new TypeError('InvalidInstalledContentRun');
    }
    const {task, step} = plan.serializationGraph;
    let selectedOutputLimits: OutputLimits = localOutputLimits, selectedIdentitySlots = identitySlots;
    let selectedGenerationLimits: GenerationLimits = generationLimits;
    const definition = JSON.parse(plan.runDefinition.wire) as Readonly<{valid_until: string}>;
    const key = {namespaceId, authorityScopeCid, runDefinitionCid: plan.runDefinition.identity};
    let retired = false;
    const live = () => !retired && store.status().closed === false &&
      Date.parse(now()) < Date.parse(definition.valid_until) && authorize(principalId) === true;
    if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
    const managedSources = acquiredContent?.managedSources;
    const source = managedSources === undefined ? acquiredContent?.captured.capture.source() : undefined;
    const sourceEvidence = managedSources?.map(item => item.sourceEvidence) ?? (acquiredContent === undefined ? []
      : [acquiredContent.sourceEvidence, acquiredContent.keyedSourceEvidence].filter(Boolean));
    let ledger: CommonObject | undefined, managed: Managed | undefined, capacity: Capacity | undefined, selectedKeyed: unknown;
    if (acquiredContent === undefined || intermediate || managedSources !== undefined) {
      const original = preparedRuns.get(preparedProgram);
      if (original === undefined || original.retired || original.plan !== plan || original.attempted ||
          original.failure !== undefined || original.managed === undefined || original.managed.closed) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      // Consume before fallible currentness or prefix construction. Failure
      // remains attached to this Run, never a new scalar-ledger fallback.
      if (acquiredContent !== undefined && (original.acquiredLedger !== acquiredContent.ledger ||
          (managedSources !== undefined
            ? !original.ordinarySource || intermediate || typeof control.startRequestWholePrefix !== 'function'
            : original.model === undefined ||
              typeof acquiredContent.captured?.capture?.originalRowCapture !== 'function' ||
              typeof control.startRequestAcquiredPrefix !== 'function'))) {
        throw new TypeError('InstalledCapturedContentPreparationUnavailable');
      }
      {
        if (original.generationLimits === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
        selectedGenerationLimits = original.generationLimits;
        selectedOutputLimits = original.outputLimits!;
        selectedIdentitySlots = original.identitySlots!;
      }
      original.attempted = true;
      assertRunCurrent!();
      managed = original.managed; capacity = original.capacity;
      if (acquiredContent !== undefined) ledger = acquiredContent.ledger;
    } else if (preparedRunRequired) {
      const compiledLimits = publications.checkedClientSerializationGenerationLimits(plan.compiled, plan.serializationGraph);
      selectedGenerationLimits = Object.freeze({...generationLimits,
        maxRows: Math.min(generationLimits.maxRows, compiledLimits.maxRows),
        maxBytes: Math.min(generationLimits.maxBytes, compiledLimits.maxBytes)});
      const original = preparedKeyedRuns.get(preparedProgram);
      if (original === undefined || original.retired || original.plan !== plan || original.attempted ||
          original.failed || original.managed === undefined || original.managed.closed ||
          original.managed.selectedKeyed === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      // The original Request owns this exact prefix/provider and its source
      // bindings. Consume before fallible current/data projection; no old
      // capacity/start reconstruction or scalar Ledger can recover a failure.
      original.attempted = true;
      assertRunCurrent!();
      managed = original.managed; selectedKeyed = managed.selectedKeyed;
      capacity = control.requestKeyedPrefixCapacity(selectedKeyed);
      ledger = acquiredContent.ledger;
    } else {
      const compiledLimits = publications.checkedClientSerializationGenerationLimits(plan.compiled, plan.serializationGraph);
      selectedGenerationLimits = Object.freeze({...generationLimits,
        maxRows: Math.min(generationLimits.maxRows, compiledLimits.maxRows),
        maxBytes: Math.min(generationLimits.maxBytes, compiledLimits.maxBytes)});
      capacity = control.prefixCapacity(preparedProgram, task, step, bodies, prefixLimits, workspace, source);
      // The source-free case already selected its same Request above. This
      // remaining explicit acquired route borrows its original Source Ledger.
      ledger = acquiredContent.ledger;
    }
    if (acquiredContent !== undefined && acquiredLedgers.get(ledger!) !== plan.compiled) {
      throw new TypeError('Foreign Content acquisition ledger');
    }
    let prefix: Prefix | undefined, input: Input | undefined, writer: Writer | undefined,
      physical: Physical | undefined, byteHolding: Holding | undefined,
      retained: HeldEvidence | undefined, publication: Publication | undefined;
    let failureCleanup: CleanupHandle | undefined, cleanupFlight: Promise<boolean> | undefined,
      cleaned = false, generatedRetained = false;
    let work = 0n;
    const remainingWork = () => Number(BigInt(prefixLimits.maxWork) - work);
    const chargeWork = (delta: number) => {
      if (!Number.isInteger(delta) || delta < 0) throw new Error('InvalidGeneratedContentWork');
      work += BigInt(delta);
      return work <= BigInt(prefixLimits.maxWork);
    };
    const retirement = new Map<string, Retirement>();
    // Retain this composition before allocating any child. Failed children and
    // Store retirement keep their original handles; retry never redispatches.
    const cleanup = () => {
      if (cleaned) return Promise.resolve(true);
      if (cleanupFlight !== undefined) return cleanupFlight;
      let flight: Promise<boolean>;
      // Install the existing flight before entering any callback, including
      // synchronous cancellation. Reentry joins this same cleanup operation.
      flight = Promise.resolve().then(async () => {
        if (prefix !== undefined) control.prefixCancel(prefix);
        if (input !== undefined) control.inputCancel(input);
        if (failureCleanup !== undefined) {
          const status = await failureCleanup.retry();
          if (status.pending) return false;
          failureCleanup = undefined;
        }
        if (writer !== undefined) {
          await writer.cancel();
          if (writer.status().reservationHeld === true) return false;
        }
        if (physical?.prepared.status().pending === true) await physical.prepared.release();
        // Release can decline while the same prepared object remains owned.
        // Do not settle the prefix or forget this handle before its actual ACK.
        if (physical?.prepared.status().pending === true) return false;
        // Confirm the exact original index before selecting lawful retirement.
        // A failed observation retains custody; it is not proof of no commit.
        const committed = await store.confirmCommittedIndex(key);
        for (const holding of retained?.holdings ?? []) {
          await holding.abort();
          // False can mean an already committed holding. Its original owner
          // must still have reconciled and released every prepared child.
          const status = holding.status();
          if (status.operationPending !== false || status.preparedPending !== false ||
              (status.committed !== true && status.abandoned !== true)) return false;
        }
        // A retained intermediate generation keeps its original committed
        // holdings for the Model's fixed-input receipt, including Unknown.
        // Unreturned/failed generation stays on this same cleanup record.
        if (committed === undefined && !generatedRetained) {
          retired = true;
          for (const cid of [byteHolding?.holding_cid,
            ...(retained?.bindings ?? []).map(binding => binding.holdingCid)].filter(Boolean) as string[]) {
            let child = retirement.get(cid);
            if (child === undefined) {
              child = (await store.retirePhysicalHolding(cid)).cleanup;
              retirement.set(cid, child);
            }
            if (child.status().pending) await child.retry();
            if (child.status().pending) return false;
          }
        }
        // The actual writer/prepared/holding/Store duties above acknowledged
        // cleanup. Forget only this execution's aliases before fallible native
        // prefix settlement; the same managed Run retains a pending prefix.
        input = undefined;
        writer = undefined;
        physical = undefined;
        byteHolding = undefined;
        retained = undefined;
        publication = undefined;
        retirement.clear();
        if (managed !== undefined) {
          prefix = undefined;
          // This also retrieves cleanup after the original start retained a
          // prefix but threw before returning it to this JS caller.
          const acknowledged = selectedKeyed === undefined
            ? control.cleanupRequestPrefix(managed.value, managed.serialization)
            : control.cleanupRequestKeyedPrefix(managed.value, selectedKeyed);
          if (acknowledged !== true) return false;
          if (ledger !== undefined) acquiredLedgers.delete(ledger);
        } else if (prefix !== undefined) {
          if (!stopGeneratedContentPrefix({control, prefix, chargeWork})) return false;
          prefix = undefined;
        }
        cleaned = true;
        return true;
      }).finally(() => { if (cleanupFlight === flight) cleanupFlight = undefined; });
      cleanupFlight = flight;
      return flight;
    };
    retainExecution(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !cleaned,
      resourceUsage: () => managed === undefined ? moon.clientProgramMultiCapturedLedgerUsage(ledger)
        : checked(moon.clientProgramInstalledManagedRunAccounting(managed.value)),
      cumulativeWork: () => work}));
    try {
      signal?.throwIfAborted();
      const capturedProof = acquiredContent === undefined ? undefined
        : managedSources === undefined
          ? publications.bindCheckedClientSerializationCapture(preparedProgram,
            plan.serializationGraph, acquiredContent.captured, acquiredContent)
          : publications.bindCheckedClientSerializationManagedCaptures(managed!.value, preparedProgram,
            managed!.serialization, plan.serializationGraph, managedSources, authorityScopeCid,
            acquiredContent.captureStartedAt, acquiredContent.captureCompletedAt);
      prefix = managed === undefined
        ? control.prefix(preparedProgram, task, step, bodies, prefixLimits, ledger, workspace,
          source, acquiredContent?.keyedLookup)
        : selectedKeyed === undefined
          ? acquiredContent === undefined
            ? control.startRequestPrefix(managed.value, preparedProgram, managed.serialization)
            : managedSources === undefined
              ? control.startRequestAcquiredPrefix(managed.value, preparedProgram, managed.serialization,
                acquiredContent.captured.capture.originalRowCapture())
              : managedSources.length === 1 && managedSources[0].captured.inputKind !== 'whole-input' && managedSources[0].captured.requirement !== undefined
                ? control.startRequestAcquiredPrefix(managed.value, preparedProgram, managed.serialization,
                  managedSources[0].captured.capture!.originalRowCapture!())
                : control.startRequestWholePrefix(managed.value, preparedProgram, managed.serialization,
                  managedSources.map(item => item.captured.capture!.originalWholeInput!()))
          : control.startRequestKeyedPrefix(managed.value, preparedProgram, selectedKeyed,
            source, acquiredContent!.keyedLookup);
      await faultInjection?.('content_workspace_reserved', {capacity});
      const output = await runGeneratedContentPrefix({control, prefix, remainingWork, chargeWork, signal});
      const barrier = control.prepare(preparedProgram, task, step, 10000);
      const encoder = control.encoder(barrier, selectedGenerationLimits);
      input = control.bindInput(barrier, output, encoder);
      const inputEvidence = await identifyGeneratedContentInput({control, compiled: plan.compiled,
        input, limits: selectedOutputLimits, maxWorkspaceSlots: selectedIdentitySlots,
        identityLimits: localContractLimits, remainingWork, chargeWork, signal, captured: capturedProof});
      await faultInjection?.('content_input_identified', {work, signal});
      signal?.throwIfAborted();
      writer = store.createPreparedObjectWriter(selectedGenerationLimits.maxBytes);
      const generated = await writeGeneratedContent({control, input, writer, remainingWork, chargeWork, signal});
      if (!live()) throw new Error('InstalledContentAuthorityUnavailable');
      // The checked generation graph supplies its admitted policy; do not
      // infer classification from a filename or synthetic data values.
      const {graphPolicy, binding} = installedBinding(plan);
      const candidate = control.candidate(encoder, binding, referenceLimits);
      const description = control.inspect(candidate);
      physical = await writer.seal(generated.contentCid);
      byteHolding = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
        holding_cid: publications.checkedClientSerializationByteHoldingCid(plan.compiled,
          plan.runDefinition, storeAuthorityCid), manifest_cid: description.identity,
        objects: [{cid: physical.cid, byte_count: physical.bytes}]};
      await store.commitPhysicalHolding(byteHolding, [physical.prepared]);
      const content = await issueStoredGeneratedContent({store, control, candidate,
        holdingCid: byteHolding.holding_cid, workspaceScopeCid: authorityScopeCid,
        effectiveDataPolicyCid: graphPolicy.cid, available: live,
        authorize: () => live(), limits: referenceLimits});
      const generation = control.complete(plan.compiled, plan.runDefinition, input,
        inputEvidence, candidate, content, live, completionLimits);
      await retainGeneratedContentEvidence({store, publications, compiled: plan.compiled,
        generation, signal, retainHoldings(_holdings, recovery) { retained = recovery; }});
      if (intermediate) {
        generatedRetained = true;
        const capturedContentRecovery = acquiredContent?.keyedContent?.recoveryInventory();
        if (acquiredContent?.keyedContent !== undefined && capturedContentRecovery === undefined) {
          throw new Error('InstalledCapturedContentInventoryUnavailable');
        }
        return Object.freeze({generation,
          capturedContentRecovery,
          capturedContentBinding: acquiredContent?.keyedContent?.sourceBinding,
          sourceEvidence,
          recoveryBindings: retained!.bindings,
          // The Model fixed-input receipt authenticates this exact inventory
          // together with its original rows. It is not fresh generation proof.
          recovery: Object.freeze({referenceWire: description.wire,
            binding: Object.freeze({...binding}), byteHoldingCid: byteHolding.holding_cid,
            bindings: Object.freeze(retained!.bindings.map(value => Object.freeze({...value})))})});
      }
      publication = serializationTaskPublicationPlan<Complete['results'][number]['retention']>({moon, control: publications,
        preparedProgram, admitted: plan, generation, authorityScopeCid,
        namespaceId, storeAuthorityCid, now, managedPublication: managed, assertCurrent: assertRunCurrent,
        sourceEvidence}) as Publication;
      const execution = serializationPublicationExecution({moon, core, compiled: plan.compiled,
        preparedProgram, generation, contractLimits: localContractLimits, remainingWork, chargeWork});
      await publishCompletedEffectFreeRun({...publication, execution, store, control: publications, signal});
    } catch (error) {
      if ((error as CleanupFailure)?.cleanupPending === true && (error as NonNullable<CleanupFailure>).cleanupHandle !== undefined) {
        failureCleanup = (error as NonNullable<CleanupFailure>).cleanupHandle;
      }
      throw error;
    }
  };
  function selectOriginalOutputDemand(prepared: CommonObject, original: Preparation) {
    if (typeof prepareSerializationOutputDemand !== 'function') {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    const selected = prepareSerializationOutputDemand(prepared, original.plan.compiled, original.plan.serializationGraph,
      generationLimits, referenceLimits, localContractLimits, localOutputLimits, identitySlots);
    assertRunCurrent!();
    if (preparedRuns.get(prepared) !== original || original.retired || original.prepared !== prepared) {
      throw new TypeError('ForeignInstalledContentRun');
    }
    // These fixed fields are constructed only after their same-Request debit.
    // Execution consumes this exact selection; it never recalculates a quota.
    original.generationLimits = selected.generationLimits;
    original.outputLimits = selected.outputLimits;
    original.identitySlots = selected.identitySlots;
    original.workspace = selected.workspace;
  }
  const run = (options: ExecuteOptions) => execute(options);
  // The ordinary trusted Host prepares this exact checked Run before durable
  // admission. This Ledger expresses managed limits; platform allocation is
  // the supplier, and no successful allocation, authority or physical ACK is
  // inferred from these numbers. Store/native children keep their own duties.
  run.prepareRun = ({preparedProgram, plan, request, ordinarySource = false}: PreparationInputs & {ordinarySource?: boolean}) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function' ||
        typeof prepareSerializationManagedRun !== 'function' || typeof retainPreparation !== 'function' || request === undefined) {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    assertRunCurrent();
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (plan.kind !== 'serialization' || plan.serializationGraph === undefined ||
        ordinarySource !== (moon.clientProgramAcquisitionCount(preparedProgram) > 0)) {
      throw new TypeError('InstalledContentRunPreparationUnsupported');
    }
    const prior = preparedRuns.get(preparedProgram);
    if (prior !== undefined) {
      if (prior.retired || prior.plan !== plan || prior.request !== request || prior.attempted) throw new TypeError('ForeignInstalledContentRun');
      if (prior.failed) throw prior.failure;
      return prior.managed;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original: Preparation = {prepared: preparedProgram, plan, request, ordinarySource, attempted: false, capacity: undefined, managed: undefined,
      inputHolder: undefined, localPreparation: undefined, releaseSelection: undefined, contentControl: control,
      retired: false, failed: false, failure: undefined};
    preparedRuns.set(preparedProgram, original);
    try {
      retainOriginalPreparation(preparedProgram, original);
      // Retain the SAME Host bag before current/requirements projections.
      // The Request constructor owns the provider and original compilation.
      selectOriginalOutputDemand(preparedProgram, original);
      original.managed = prepareSerializationManagedRun(preparedProgram, request, plan, prefixLimits, original.workspace, original as RetainedPreparation<Preparation>);
      if (original.managed === undefined || original.managed.value === undefined ||
          original.managed.serialization === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
      original.capacity = control.requestPrefixCapacity(original.managed.serialization);
      assertRunCurrent();
      return original.managed;
    } catch (error) {if (!original.retired) {original.failed = true; original.failure = error;} throw error;}
  };
  // Intermediate Model generation uses the same Request/Run as its Model
  // Scope. Retain the original Content record before the Host constructor;
  // no separate Content completion, adoption or scalar Ledger is selected.
  run.prepareModelRun = ({preparedProgram, plan, request, model}: PreparationInputs & Readonly<{model: ModelPreparation}>) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function' ||
        typeof prepareModelManagedRun !== 'function' || typeof retainPreparation !== 'function' ||
        request === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
    assertRunCurrent();
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const acquisitions = moon.clientProgramAcquisitionCount(preparedProgram);
    if (plan.kind !== 'infer' || plan.serializationGraph === undefined ||
        (acquisitions !== 0 && acquisitions !== 1) ||
        model?.compiled !== plan.compiled || model.runDefinition !== plan.runDefinition ||
        model.graph !== plan.inferGraph || model.serializationGraph !== plan.serializationGraph) {
      throw new TypeError('InstalledContentRunPreparationUnsupported');
    }
    const prior = preparedRuns.get(preparedProgram);
    if (prior !== undefined) {
      if (prior.retired || prior.plan !== plan || prior.request !== request || prior.model !== model ||
          prior.attempted) throw new TypeError('ForeignInstalledContentRun');
      if (prior.failed) throw prior.failure;
      return;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original: Preparation = {prepared: preparedProgram, plan, request, model, attempted: false,
      capacity: undefined, managed: undefined, inputHolder: undefined, localPreparation: undefined,
      releaseSelection: undefined, contentControl: control, prefixLimits,
      generationLimits: undefined, outputLimits: undefined, identitySlots: undefined,
      workspace: undefined, retired: false, failed: false, failure: undefined};
    preparedRuns.set(preparedProgram, original);
    try {
      retainOriginalPreparation(preparedProgram, original);
      selectOriginalOutputDemand(preparedProgram, original);
      model.contentPreparation = original;
      original.managed = prepareModelManagedRun(preparedProgram, request, model);
      if (original.managed?.value === undefined || original.managed.serialization === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      original.capacity = control.requestPrefixCapacity(original.managed.serialization);
      assertRunCurrent();
    } catch (error) {if (!original.retired) {original.failed = true; original.failure = error;} throw error;}
  };
  run.generate = (options: ExecuteOptions) => execute(options, true);
  // The selected existing Source owner creates the same-Run Content parent
  // before durable admission or I/O. This finite prefix recipe is DATA; the
  // callback must retain its real Resource original and partial cleanup.
  run.prepareManagedKeyedCompilation = ({preparedProgram, serializationGraph, request, keyedAcquisition}:
    KeyedCompilationInputs) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function' || request === undefined ||
        typeof prepareKeyedManagedRun !== 'function' || typeof borrowKeyedManagedLedger !== 'function' ||
        typeof retainPreparation !== 'function') {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    assertRunCurrent();
    if (serializationGraph === undefined || keyedAcquisition === undefined ||
        moon.clientProgramKeyedAcquisitionMatchesProgram(keyedAcquisition, preparedProgram) !== true) {
      throw new TypeError('ForeignInstalledContentRun');
    }
    const prior = preparedKeyedRuns.get(preparedProgram);
    if (prior !== undefined) {
      if (prior.retired || prior.serializationGraph !== serializationGraph || prior.keyedAcquisition !== keyedAcquisition ||
          prior.request !== request) throw new TypeError('ForeignInstalledContentRun');
      if (prior.failed) throw prior.failure;
      if (prior.managed!.closed || prior.managed!.contentCompilation === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      return prior.managed!.contentCompilation;
    }
    if (preparedRunCount === 4096) throw new TypeError('InstalledContentRunLimit');
    preparedRunCount++;
    const original: KeyedPreparation = {prepared: preparedProgram, serializationGraph, plan: undefined, request, keyedAcquisition, attempted: false,
      recipe: undefined, managed: undefined, inputHolder: undefined, localPreparation: undefined, releaseSelection: undefined,
      contentControl: control, retired: false, failed: false, failure: undefined};
    preparedKeyedRuns.set(preparedProgram, original);
    try {
      retainOriginalPreparation(preparedProgram, original);
      const {task, step} = serializationGraph;
      original.recipe = Object.freeze({...bodies, task, step, keyedAcquisition,
        prefixLimits, workspace});
      original.managed = prepareKeyedManagedRun(preparedProgram, request, serializationGraph, original.recipe, original as RetainedPreparation<KeyedPreparation>);
      if (original.managed === undefined || original.managed.value === undefined ||
          original.managed.selectedKeyed === undefined || original.managed.contentCompilation === undefined) {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      assertRunCurrent();
      return original.managed.contentCompilation;
    } catch (cause) {if (!original.retired) {original.failed = true; original.failure = cause;} throw cause;}
  };
  // Compilation/adoption belongs to the original Request before Run definition.
  // This later call only binds the SAME issuer's completed plan to that holder.
  run.prepareManagedKeyedRun = ({preparedProgram, plan, request, keyedAcquisition}: KeyedPreparationInputs) => {
    if (!preparedRunRequired || typeof assertRunCurrent !== 'function') {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    assertRunCurrent();
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const original = preparedKeyedRuns.get(preparedProgram);
    if (original === undefined || original.retired) throw new TypeError('InstalledContentRunPreparationUnavailable');
    const scope = original.request === request ? undefined : moon.clientRequestScopeCid(request);
    if (plan.kind !== 'serialization' || plan.serializationGraph !== original.serializationGraph ||
        original.keyedAcquisition !== keyedAcquisition || original.plan !== undefined && original.plan !== plan ||
        original.request !== request && (typeof scope !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(scope) ||
          scope !== moon.clientRequestScopeCid(original.request) ||
          moon.clientRequestIntentCid(request) !== moon.clientRequestIntentCid(original.request))) {
      throw new TypeError('ForeignInstalledContentRun');
    }
    if (original.failed) throw original.failure;
    if (original.managed!.closed || original.managed!.value === undefined) {
      throw new TypeError('InstalledContentRunPreparationUnavailable');
    }
    original.plan = plan;
  };
  run.captureKeyed = (options: CaptureOptions) => installRunKeyedContentCapture({moon, publications,
    control: core.contentCaptureControl, namespaceId, authorityScopeCid, storeAuthorityCid,
    ownerPrincipal, now, authorize, ...options});
  run.recoverKeyed = createKeyedContentRunRecovery({publications, run});
  run.prepareEffectFamily = ({facts, store, principalId, retainCleanup}: EffectSetup) => {
    // The Model compilation already retains this same serialization component.
    // Reuse its original holder instead of issuing a second compiled Run.
    const compiled = facts.modelCompiled ??
      publications.adoptCheckedClientEffectSerializationRun(facts.allowed, facts.runDefinition);
    const plan = Object.freeze({kind: 'effect' as const, compiled, runDefinition: facts.runDefinition,
      serializationGraph: publications.compiledSerializationGraph(compiled)});
    const managedOriginal = Object.freeze<ManagedFamily>({
      inputRows: publications.checkedClientSerializationInputRows(compiled, plan.serializationGraph),
      prepare(workspace, physical, retain) {
      return publications.prepareCheckedClientEffectContentOriginal(facts.prepared, compiled,
        facts.compilation, facts.runDefinition, plan.serializationGraph, bodies, workspace, physical, retain);
    }});
    const family = run.effectFamily({prepared: facts.prepared, plan, store, principalId,
      retainCleanup, managedOriginal});
    return Object.freeze({family, plan, preparation: family.preparation});
  };
  run.effectFamily = ({prepared, plan, store, principalId, signal, restored, retainCleanup, managedOriginal}: EffectOptions) =>
    installEffectContentFamily({moon, control, publications, bodies,
      prepared, plan, store, principalId, ownerPrincipal, now, authorize, signal, managedOriginal,
      namespaceId, authorityScopeCid, storeAuthorityCid, installedBinding,
      referenceLimits, completionLimits,
      outputLimits: localOutputLimits, faultInjection, restored, retainCleanup});
  run.prepareRecoveredCommandContent = createContentRecoveryDispatch({moon, core, publications, control,
    ownerPrincipal, storeAuthorityCid, authorityScopeCid, namespaceId, now, authorize,
    installedBinding, referenceLimits});
  // Resolve this before physical acquisition. The selected Source capacity is
  // opaque and requirement-bound in the common owner, never estimated from rows.
  run.prepareOrdinaryAcquiredLedger = ({preparedProgram, plan, sourceCapacities}: OrdinaryLedgerInputs) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const original = preparedRuns.get(preparedProgram), managed = original?.managed;
    const query = sourceCapacities.length === 1 && sourceCapacities[0].wholeInput !== true;
    const admit = query ? moon.clientProgramInstalledManagedRunPrepareLedger : moon.clientProgramInstalledManagedWholeSourcesLedger;
    if (original === undefined || !original.ordinarySource || original.attempted ||
        original.acquiredLedgerAttempted || original.plan !== plan || managed?.value === undefined ||
        sourceCapacities.length !== moon.clientProgramAcquisitionCount(preparedProgram) ||
        sourceCapacities.some(value => value.managedRun !== managed.value || (!query && value.wholeInput !== true)) ||
        typeof admit !== 'function') throw new TypeError('InstalledContentRunPreparationUnavailable');
    const runOwner = managed.value, request = original.request;
    const requireCurrent = () => {
      assertRunCurrent!();
      if (preparedRuns.get(preparedProgram) !== original || original.retired || original.failed ||
          managed.closed || managed.value !== runOwner || original.managed !== managed) {
        throw new TypeError('ForeignInstalledContentRun');
      }
    };
    original.acquiredLedgerAttempted = true;
    try {
      requireCurrent();
      const args = [runOwner, preparedProgram, request, sourceCapacities.map(item => item.capacity),
        sourceCapacities.map(item => item.transferBytes), sourceCapacities.map(item => item.executionBytes)] as const;
      const ledger = checked(Reflect.apply(admit, moon,
        query ? [...args, registry, values, fragment, ordered] : args)) as CommonObject;
      requireCurrent();
      original.acquiredLedger = ledger;
      acquiredLedgers.set(ledger, plan.compiled);
      return ledger;
    } catch (cause) {
      if (!original.retired) {original.failed = true; original.failure = cause;}
      throw cause;
    }
  };
  run.prepareAcquiredLedger = ({preparedProgram, plan, sourceCapacity}:
    AcquiredLedgerInputs) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (preparedRunRequired) {
      const original = preparedRuns.get(preparedProgram), managed = original?.managed;
      if (original === undefined || original.retired || original.failed || original.attempted ||
          original.acquiredLedgerAttempted || original.plan !== plan || original.model === undefined ||
          managed === undefined || managed.closed || managed.value === undefined ||
          sourceCapacity.managedRun !== managed.value ||
          typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      original.acquiredLedgerAttempted = true;
      const parent = managed.value, request = original.request;
      try {
        assertRunCurrent!();
        if (preparedRuns.get(preparedProgram) !== original || original.retired || original.failed ||
            original.plan !== plan || original.request !== request ||
            original.managed !== managed || managed.closed || managed.value !== parent) {
          throw new TypeError('ForeignInstalledContentRun');
        }
        const ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(parent,
          preparedProgram, request, [sourceCapacity.capacity], [sourceCapacity.transferBytes],
          [sourceCapacity.executionBytes], registry, values, fragment, ordered)) as CommonObject;
        // This getter borrows the existing Ledger, so a callback that retired
        // the record creates no new child. Never resurrect its spent aliases.
        if (preparedRuns.get(preparedProgram) !== original || original.retired || original.failed ||
            original.plan !== plan || original.request !== request ||
            original.managed !== managed || managed.closed || managed.value !== parent) {
          throw new TypeError('ForeignInstalledContentRun');
        }
        original.acquiredLedger = ledger;
        assertRunCurrent!();
        if (preparedRuns.get(preparedProgram) !== original || original.retired || original.failed ||
            original.plan !== plan || original.request !== request ||
            original.managed !== managed || managed.closed || managed.value !== parent) {
          throw new TypeError('ForeignInstalledContentRun');
        }
        acquiredLedgers.set(ledger, plan.compiled);
        return ledger;
      } catch (cause) {
        if (!original.retired) {original.failed = true; original.failure = cause;}
        throw cause;
      }
    }
    const {task, step} = plan.serializationGraph!;
    const prefix = control.prefixCapacity(preparedProgram, task, step,
      bodies, prefixLimits, workspace, true);
    const ledger = moon.clientProgramPrepareSerializationCapturedLedger(preparedProgram,
      task, sourceCapacity.capacity, sourceCapacity.transferBytes, sourceCapacity.executionBytes,
      prefix.retainedBytes, prefix.executionBytes, registry, values, fragment, ordered);
    if (ledger === undefined) throw new TypeError('Content acquisition capacity unavailable');
    acquiredLedgers.set(ledger, plan.compiled);
    return ledger;
  };
  run.prepareKeyedLedger = ({preparedProgram, plan, direct, acquisition, capacity, capturedContent = false}:
    KeyedLedgerInputs) => {
    publications.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    if (preparedRunRequired) {
      const original = preparedKeyedRuns.get(preparedProgram);
      if (original === undefined || original.retired || original.plan !== plan || original.failed ||
          !capturedContent || typeof borrowKeyedManagedLedger !== 'function') {
        throw new TypeError('InstalledContentRunPreparationUnavailable');
      }
      assertRunCurrent!();
      const ledger = borrowKeyedManagedLedger(preparedProgram, original.request, original.recipe,
        direct, acquisition, capacity);
      if (ledger === undefined) throw new TypeError('InstalledContentRunPreparationUnavailable');
      assertRunCurrent!();
      acquiredLedgers.set(ledger, plan.compiled);
      return ledger;
    }
    const {task, step} = plan.serializationGraph!;
    const prefix = control.prefixCapacity(preparedProgram, task, step,
      bodies, prefixLimits, workspace, true);
    const ledger = moon.clientProgramPrepareKeyedSerializationCapturedLedger(preparedProgram,
      direct.capacity, acquisition, capacity.capacity,
      [direct.transferBytes, capacity.transferBytes], [direct.executionBytes, capacity.executionBytes],
      capacity.maxBytes, capacity.maxWork, registry, values, fragment, ordered,
      task, step, prefix.retainedBytes, prefix.executionBytes, capturedContent);
    if (ledger === undefined) throw new TypeError('Content keyed acquisition capacity unavailable');
    acquiredLedgers.set(ledger, plan.compiled);
    return ledger;
  };
  run.recover = createGeneratedContentRunRecovery({publications, control, ownerPrincipal, storeAuthorityCid,
    authorityScopeCid, now, authorize, installedBinding, referenceLimits, faultInjection});
  return Object.freeze(run);
}
